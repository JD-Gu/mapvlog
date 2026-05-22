import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../models/vlog.dart';
import '../../screens/vlog/vlog_player_screen.dart';
import '../../services/firestore_service.dart';
import '../../services/location_service.dart';
import '../../utils/constants.dart';
import '../../utils/marker_colors.dart';
import '../../widgets/map_controls.dart';

const _defaultLocation = LatLng(37.5665, 126.9780); // 서울 시청

// ─── 클러스터 그룹 모델 ───────────────────────────────────────────────────────

class _ClusterGroup {
  final List<Vlog> vlogs;
  _ClusterGroup(this.vlogs);

  String get id => vlogs.map((v) => v.id).join('_');
  int get count => vlogs.length;
  bool get isSingle => vlogs.length == 1;

  LatLng get center {
    if (isSingle) return LatLng(vlogs.first.lat, vlogs.first.lng);
    final lat =
        vlogs.map((v) => v.lat).reduce((a, b) => a + b) / vlogs.length;
    final lng =
        vlogs.map((v) => v.lng).reduce((a, b) => a + b) / vlogs.length;
    return LatLng(lat, lng);
  }
}

// ─── 화면 ─────────────────────────────────────────────────────────────────────

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  GoogleMapController? _mapController;
  Vlog? _selectedVlog;
  List<Vlog> _vlogs = [];
  Set<Marker> _markers = {};
  double _zoom = 12.0;
  MapType _mapType = MapType.normal;
  LatLng _mapCenter = _defaultLocation;
  StreamSubscription<List<Vlog>>? _vlogsSub; // 누수 방지

  @override
  void initState() {
    super.initState();
    _loadVlogs();
  }

  // ─── 데이터 로드 ────────────────────────────────────────────────────────────

  void _loadVlogs() {
    _vlogsSub = FirestoreService.watchVlogs(limit: 50).listen((vlogs) {
      if (!mounted) return;
      _vlogs = vlogs;
      _rebuildMarkers();
    });
  }

  // ─── 클러스터링 ─────────────────────────────────────────────────────────────

  /// zoom 레벨에 따른 LatLng 반경 (줌 아웃 → 반경 커짐)
  double _clusterRadius() => 0.6 / math.pow(2, _zoom - 8);

  List<_ClusterGroup> _computeClusters() {
    if (_vlogs.isEmpty) return [];
    final radius = _clusterRadius();
    final groups = <_ClusterGroup>[];
    final assigned = <String>{};

    for (final vlog in _vlogs) {
      if (assigned.contains(vlog.id)) continue;
      final nearby = _vlogs.where((other) {
        if (assigned.contains(other.id)) return false;
        return (vlog.lat - other.lat).abs() <= radius &&
            (vlog.lng - other.lng).abs() <= radius;
      }).toList();
      for (final v in nearby) {
        assigned.add(v.id);
      }
      groups.add(_ClusterGroup(nearby));
    }
    return groups;
  }

  Future<void> _rebuildMarkers() async {
    final groups = _computeClusters();
    final markers =
        await Future.wait(groups.map((g) => _groupToMarker(g)));
    if (mounted) setState(() => _markers = markers.toSet());
  }

  Future<Marker> _groupToMarker(_ClusterGroup group) async {
    return Marker(
      markerId: MarkerId(group.id),
      position: group.center,
      icon: await _markerBitmap(
        group.count,
        !group.isSingle,
        color: group.isSingle
            ? MarkerColors.fromValue(group.vlogs.first.markerColor)
            : null,
      ),
      // 단일=핀 끝점, 클러스터=원 중심
      anchor: group.isSingle
          ? const Offset(0.5, 68.0 / 72.0)
          : const Offset(0.5, 0.5),
      onTap: () {
        if (group.isSingle) {
          setState(() => _selectedVlog = group.vlogs.first);
        } else if (_wouldClusterAtMaxZoom(group)) {
          // 아무리 확대해도 안 나뉨(동일 위치) → 목록 시트
          _showClusterList(group.vlogs);
        } else {
          // 확대하면 분리됨 → 카메라 확대
          _mapController?.animateCamera(
            CameraUpdate.newLatLngZoom(
                group.center, math.min(_zoom + 2, 20)),
          );
          setState(() => _selectedVlog = null);
        }
      },
    );
  }

  /// 최대 줌(20)에서도 여전히 클러스터링될지 확인 (≈ 반경 16m 이내)
  bool _wouldClusterAtMaxZoom(_ClusterGroup group) {
    const maxRadius = 0.6 / 4096.0; // zoom 20 반경
    final lat0 = group.vlogs.first.lat;
    final lng0 = group.vlogs.first.lng;
    return group.vlogs.every(
      (v) =>
          (v.lat - lat0).abs() <= maxRadius &&
          (v.lng - lng0).abs() <= maxRadius,
    );
  }

  void _showClusterList(List<Vlog> vlogs) {
    final nav = Navigator.of(context); // async gap 전에 캡처
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => _ClusterListSheet(
        vlogs: vlogs,
        onSelect: (vlog) {
          Navigator.pop(sheetCtx); // 시트 닫기
          nav.push(MaterialPageRoute(
              builder: (_) => VlogPlayerScreen(vlog: vlog)));
        },
      ),
    );
  }

  // ─── 마커 비트맵 생성 ────────────────────────────────────────────────────────

  static Future<BitmapDescriptor> _markerBitmap(
      int count, bool isCluster, {Color? color}) async {
    if (isCluster) {
      // ── 클러스터 마커: 흰 테두리 링 + 파란 원 + 숫자 ──────────────────
      const int size = 72;
      const double c = size / 2.0;

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);

      // 그림자
      canvas.drawCircle(
        Offset(c, c + 3),
        28,
        Paint()
          ..color = Colors.black.withAlpha(55)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
      );
      // 흰색 외곽 링
      canvas.drawCircle(Offset(c, c), 34, Paint()..color = Colors.white);
      // 주색 채우기
      canvas.drawCircle(Offset(c, c), 26, Paint()..color = AppColors.primary);

      // 개수 텍스트
      final label = count > 99 ? '99+' : '$count';
      final tp = TextPainter(textDirection: TextDirection.ltr)
        ..text = TextSpan(
          text: label,
          style: TextStyle(
            fontSize: label.length > 2 ? 13.0 : 18.0,
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        )
        ..layout();
      tp.paint(canvas, Offset(c - tp.width / 2, c - tp.height / 2));

      final img = await recorder.endRecording().toImage(size, size);
      final data = await img.toByteData(format: ui.ImageByteFormat.png);
      return BitmapDescriptor.bytes(data!.buffer.asUint8List());
    } else {
      // ── 단일 마커: 핀(pin) 모양 ──────────────────────────────────────
      final pinColor = color ?? AppColors.primary;
      const int w = 56;
      const int h = 72;
      const double cx = w / 2.0;       // 28
      const double circleR = 22.0;
      const double circleCy = 26.0;    // 원 중심 Y
      const double tipY = 68.0;        // 핀 끝 Y

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);

      // 그림자
      canvas.drawCircle(
        Offset(cx, circleCy + 4),
        circleR - 2,
        Paint()
          ..color = Colors.black.withAlpha(50)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );

      // 꼬리(tail) — 원이 위쪽 경계를 덮음
      final tailPath = Path()
        ..moveTo(cx - 13, circleCy + 13)
        ..quadraticBezierTo(cx - 7, circleCy + 28, cx, tipY)
        ..quadraticBezierTo(cx + 7, circleCy + 28, cx + 13, circleCy + 13)
        ..close();
      canvas.drawPath(tailPath, Paint()..color = pinColor);

      // 원 본체
      canvas.drawCircle(
          Offset(cx, circleCy), circleR, Paint()..color = pinColor);

      // 흰색 테두리 링
      canvas.drawCircle(
        Offset(cx, circleCy),
        circleR,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4.5,
      );

      // 흰색 내부 원 + 중심점
      canvas.drawCircle(
          Offset(cx, circleCy), 8.0, Paint()..color = Colors.white);
      canvas.drawCircle(
          Offset(cx, circleCy), 4.0, Paint()..color = pinColor);

      final img = await recorder.endRecording().toImage(w, h);
      final data = await img.toByteData(format: ui.ImageByteFormat.png);
      return BitmapDescriptor.bytes(data!.buffer.asUint8List());
    }
  }

  // ─── 위치 이동 ────────────────────────────────────────────────────────────

  Future<void> _moveToCurrentLocation() async {
    final position = await LocationService.getCurrentPosition(context);
    if (position == null || _mapController == null) return;
    _mapController!.animateCamera(
      CameraUpdate.newLatLng(
          LatLng(position.latitude, position.longitude)),
    );
  }

  @override
  void dispose() {
    _vlogsSub?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  // ─── UI ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: const CameraPosition(
              target: _defaultLocation,
              zoom: 12,
            ),
            markers: _markers,
            mapType: _mapType,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            onMapCreated: (controller) => _mapController = controller,
            onCameraMove: (pos) {
              _zoom = pos.zoom;
              _mapCenter = pos.target;
            },
            onCameraIdle: _rebuildMarkers,
            onTap: (_) => setState(() => _selectedVlog = null),
          ),

          // 검색창
          Positioned(
            top: MediaQuery.of(context).padding.top + AppSpacing.sm,
            left: AppSpacing.md,
            right: AppSpacing.md,
            child: Container(
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppRadius.full),
                boxShadow: AppShadow.card,
              ),
              child: Row(
                children: [
                  const SizedBox(width: AppSpacing.md),
                  const Icon(Icons.search,
                      color: AppColors.textSecondary),
                  const SizedBox(width: AppSpacing.sm),
                  const Expanded(
                    child: Text('장소 검색',
                        style: TextStyle(
                            color: AppColors.textSecondary)),
                  ),
                  if (_vlogs.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(
                          right: AppSpacing.sm),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${_vlogs.length}',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),

          // 지도 레이어 + 스트리트뷰 컨트롤
          Positioned(
            right: AppSpacing.md,
            bottom: (_selectedVlog != null ? 180.0 : AppSpacing.xl) + 56,
            child: MapControls(
              mapType: _mapType,
              onMapTypeChanged: (t) => setState(() => _mapType = t),
              center: _mapCenter,
            ),
          ),

          // 현재 위치 버튼
          Positioned(
            bottom: _selectedVlog != null ? 180 : AppSpacing.xl,
            right: AppSpacing.md,
            child: FloatingActionButton(
              mini: true,
              backgroundColor: AppColors.surface,
              onPressed: _moveToCurrentLocation,
              child: const Icon(Icons.my_location,
                  color: AppColors.primary),
            ),
          ),

          // 마커 팝업
          if (_selectedVlog != null)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _VlogPopup(
                vlog: _selectedVlog!,
                onClose: () =>
                    setState(() => _selectedVlog = null),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── 팝업 위젯 ────────────────────────────────────────────────────────────────

class _VlogPopup extends StatelessWidget {
  final Vlog vlog;
  final VoidCallback onClose;

  const _VlogPopup({required this.vlog, required this.onClose});

  @override
  Widget build(BuildContext context) {
    final thumbUrl = vlog.thumbnailUrl ?? '';

    return Container(
      margin: const EdgeInsets.all(AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: AppShadow.elevated,
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            child: SizedBox(
              width: 72,
              height: 72,
              child: thumbUrl.isNotEmpty
                  ? Image.network(thumbUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stack) =>
                          _iconBox())
                  : _iconBox(),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  vlog.title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Row(children: [
                  const Icon(Icons.location_on,
                      size: 13, color: AppColors.primary),
                  const SizedBox(width: 2),
                  Text(vlog.placeName,
                      style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary)),
                ]),
                const SizedBox(height: 4),
                Row(children: [
                  const Icon(Icons.favorite,
                      size: 13, color: AppColors.error),
                  const SizedBox(width: 2),
                  Text('${vlog.likeCount}',
                      style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary)),
                  const SizedBox(width: 8),
                  const Icon(Icons.remove_red_eye,
                      size: 13, color: AppColors.textDisabled),
                  const SizedBox(width: 2),
                  Text('${vlog.viewCount}',
                      style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textDisabled)),
                ]),
              ],
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: onClose,
                color: AppColors.textSecondary,
                padding: EdgeInsets.zero,
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => VlogPlayerScreen(vlog: vlog),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm, vertical: 6),
                  minimumSize: Size.zero,
                  shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(AppRadius.sm),
                  ),
                ),
                child: const Text('▶ 재생',
                    style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _iconBox() => Container(
        color: AppColors.surfaceVariant,
        child: const Icon(Icons.videocam,
            size: 32, color: AppColors.textDisabled),
      );
}

// ─── 동일 위치 클러스터 목록 시트 ─────────────────────────────────────────────

class _ClusterListSheet extends StatelessWidget {
  final List<Vlog> vlogs;
  final void Function(Vlog) onSelect;
  const _ClusterListSheet({required this.vlogs, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.85,
      builder: (_, scrollCtrl) => Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // 드래그 핸들
            Container(
              margin: const EdgeInsets.only(top: 10, bottom: 4),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.textDisabled,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // 헤더
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
              child: Row(
                children: [
                  const Icon(Icons.location_on,
                      color: AppColors.primary, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    '같은 위치의 브이로그 ${vlogs.length}개',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // 목록 — 단일 팝업 카드 스타일
            Expanded(
              child: ListView.separated(
                controller: scrollCtrl,
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                itemCount: vlogs.length,
                separatorBuilder: (_, index) =>
                    const SizedBox(height: 8),
                itemBuilder: (_, i) =>
                    _VlogCard(vlog: vlogs[i], onSelect: onSelect),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 클러스터 시트용 카드 — 단일 팝업과 동일한 레이아웃
class _VlogCard extends StatelessWidget {
  final Vlog vlog;
  final void Function(Vlog) onSelect;
  const _VlogCard({required this.vlog, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final thumb = vlog.thumbnailUrl ?? '';
    final isVideo = (vlog.videoUrl ?? '').isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.surfaceVariant),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(13),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // 썸네일
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 64,
              height: 64,
              child: thumb.isNotEmpty
                  ? Image.network(thumb,
                      fit: BoxFit.cover,
                      errorBuilder: (_, err, stack) => _thumb(isVideo))
                  : _thumb(isVideo),
            ),
          ),
          const SizedBox(width: 12),
          // 제목·위치·통계
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  vlog.title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: AppColors.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Row(children: [
                  const Icon(Icons.location_on,
                      size: 12, color: AppColors.primary),
                  const SizedBox(width: 2),
                  Expanded(
                    child: Text(
                      vlog.placeName,
                      style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ]),
                const SizedBox(height: 4),
                Row(children: [
                  const Icon(Icons.favorite,
                      size: 12, color: AppColors.error),
                  const SizedBox(width: 2),
                  Text('${vlog.likeCount}',
                      style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary)),
                  const SizedBox(width: 8),
                  const Icon(Icons.remove_red_eye,
                      size: 12, color: AppColors.textDisabled),
                  const SizedBox(width: 2),
                  Text('${vlog.viewCount}',
                      style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textDisabled)),
                ]),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // 재생 버튼
          ElevatedButton(
            onPressed: () => onSelect(vlog),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 6),
              minimumSize: Size.zero,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
            ),
            child: const Text('▶ 재생',
                style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _thumb(bool isVideo) => Container(
        color: AppColors.surfaceVariant,
        child: Center(
          child: Icon(
            isVideo ? Icons.videocam : Icons.photo,
            color: AppColors.primary,
            size: 22,
          ),
        ),
      );
}
