import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../models/vlog.dart';
import '../../screens/vlog/vlog_player_screen.dart';
import '../../services/firestore_service.dart';
import '../../utils/constants.dart';
import '../../widgets/map_controls.dart';

class GalleryScreen extends StatefulWidget {
  const GalleryScreen({super.key});

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl = TabController(length: 2, vsync: this);

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: const Text(
          '갤러리',
          style: TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.bold,
              fontSize: 18),
        ),
        bottom: TabBar(
          controller: _tabCtrl,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textSecondary,
          indicatorColor: AppColors.primary,
          tabs: const [
            Tab(icon: Icon(Icons.grid_on, size: 20), text: '그리드'),
            Tab(icon: Icon(Icons.map, size: 20), text: '포토맵'),
          ],
        ),
      ),
      body: StreamBuilder<List<Vlog>>(
        stream: FirestoreService.watchVlogs(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
                child: CircularProgressIndicator(color: AppColors.primary));
          }
          final vlogs = snapshot.data ?? [];

          return TabBarView(
            controller: _tabCtrl,
            // 수평 스와이프를 TabBarView가 가로채지 않도록 설정
            // → 포토맵의 지도 팬/줌 제스처가 정상 동작함
            physics: const NeverScrollableScrollPhysics(),
            children: [
              _GridView(vlogs: vlogs),
              _PhotoMapView(
                  vlogs: vlogs.where((v) => v.lat != 0 || v.lng != 0).toList()),
            ],
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 그리드 뷰
// ─────────────────────────────────────────────────────────────────────────────

class _GridView extends StatelessWidget {
  final List<Vlog> vlogs;
  const _GridView({required this.vlogs});

  @override
  Widget build(BuildContext context) {
    if (vlogs.isEmpty) return const _EmptyState();

    return GridView.builder(
      padding: const EdgeInsets.all(AppSpacing.sm),
      itemCount: vlogs.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 3,
        mainAxisSpacing: 3,
      ),
      itemBuilder: (_, i) => _GridTile(vlog: vlogs[i]),
    );
  }
}

class _GridTile extends StatelessWidget {
  final Vlog vlog;
  const _GridTile({required this.vlog});

  bool get _isVideo => (vlog.videoUrl ?? '').isNotEmpty;
  String get _thumbUrl => vlog.thumbnailUrl ?? '';

  Future<void> _onLongPress(BuildContext context) async {
    // 본인 브이로그만 삭제 가능
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid != vlog.authorId) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (dlgCtx) => AlertDialog(
        title: const Text('브이로그 삭제'),
        content: Text(
          '"${vlog.title}"을(를) 삭제하시겠습니까?\n영상·사진 파일도 함께 삭제됩니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dlgCtx, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dlgCtx, true),
            child: const Text(
              '삭제',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      await FirestoreService.deleteVlog(vlog.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => VlogPlayerScreen(vlog: vlog)),
        );
      },
      onLongPress: () => _onLongPress(context),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 썸네일
          _thumbUrl.isNotEmpty
              ? Image.network(
                  _thumbUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stack) => _placeholderBox(),
                )
              : _placeholderBox(),

          // 영상 뱃지
          if (_isVideo)
            const Positioned(
              top: 4,
              left: 4,
              child: Icon(Icons.play_circle_filled,
                  size: 18, color: Colors.white70),
            ),

          // GPS 뱃지 (GPS 트랙이 있는 경우만)
          if (vlog.hasGpsTrack)
            Positioned(
              bottom: 4,
              right: 4,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Icon(Icons.gps_fixed,
                    size: 10, color: AppColors.secondary),
              ),
            ),
        ],
      ),
    );
  }

  Widget _placeholderBox() {
    return Container(
      color: AppColors.surfaceVariant,
      child: Center(
        child: Icon(
          _isVideo ? Icons.videocam : Icons.photo,
          size: 28,
          color: AppColors.textDisabled,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 포토맵 뷰
// ─────────────────────────────────────────────────────────────────────────────

class _PhotoMapView extends StatefulWidget {
  final List<Vlog> vlogs;
  const _PhotoMapView({required this.vlogs});

  @override
  State<_PhotoMapView> createState() => _PhotoMapViewState();
}

class _PhotoMapViewState extends State<_PhotoMapView> {
  Vlog? _selected;
  Set<Marker> _markers = {};
  double _zoom = 13.0;
  /// 단일 vlog 썸네일 마커 캐시 (vlog.id → BitmapDescriptor)
  final Map<String, BitmapDescriptor> _iconCache = {};
  GoogleMapController? _mapController;
  MapType _mapType = MapType.normal;
  LatLng _mapCenter = const LatLng(37.5665, 126.9780);

  @override
  void initState() {
    super.initState();
    _rebuildMarkers();
  }

  @override
  void didUpdateWidget(_PhotoMapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.vlogs != widget.vlogs) _rebuildMarkers();
  }

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }

  // ─── 클러스터링 ──────────────────────────────────────────────────────────

  List<_GalleryCluster> _computeClusters() {
    final vlogs = widget.vlogs;
    if (vlogs.isEmpty) return [];
    final radius = 0.6 / math.pow(2, _zoom - 8);
    final groups = <_GalleryCluster>[];
    final assigned = <String>{};

    for (final v in vlogs) {
      if (assigned.contains(v.id)) continue;
      final nearby = vlogs.where((o) {
        if (assigned.contains(o.id)) return false;
        return (v.lat - o.lat).abs() <= radius &&
            (v.lng - o.lng).abs() <= radius;
      }).toList();
      for (final n in nearby) { assigned.add(n.id); }
      groups.add(_GalleryCluster(nearby));
    }
    return groups;
  }

  Future<void> _rebuildMarkers() async {
    final groups = _computeClusters();
    final markers = await Future.wait(groups.map(_toMarker));
    if (mounted) setState(() => _markers = markers.toSet());
  }

  Future<Marker> _toMarker(_GalleryCluster group) async {
    BitmapDescriptor icon;

    if (group.isSingle) {
      final vlog = group.vlogs.first;
      // 캐시된 썸네일 마커가 있으면 재사용
      icon = _iconCache[vlog.id] ??= await _thumbnailMarkerBitmap(
        vlog.thumbnailUrl ?? '',
        vlog.hasVideo,
      );
    } else {
      icon = await _clusterBitmap(group.count);
    }

    return Marker(
      markerId: MarkerId(group.id),
      position: group.center,
      icon: icon,
      // 단일: 꼬리 끝(하단 중앙)이 좌표를 가리킴 / 클러스터: 원 중심
      anchor: group.isSingle
          ? const Offset(0.5, 1.0)
          : const Offset(0.5, 0.5),
      onTap: () {
        if (group.isSingle) {
          setState(() => _selected = group.vlogs.first);
        } else if (_wouldClusterAtMaxZoom(group)) {
          _showClusterList(group.vlogs);
        } else {
          _mapController?.animateCamera(
            CameraUpdate.newLatLngZoom(
                group.center, math.min(_zoom + 2, 20)),
          );
        }
      },
    );
  }

  bool _wouldClusterAtMaxZoom(_GalleryCluster group) {
    const maxRadius = 0.6 / 4096.0;
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
      builder: (sheetCtx) => _GalleryClusterSheet(
        vlogs: vlogs,
        onSelect: (vlog) {
          nav.pop(); // 시트 닫기 (캡처한 nav 사용 - 웹 호환)
          nav.push(MaterialPageRoute(
              builder: (_) => VlogPlayerScreen(vlog: vlog)));
        },
      ),
    );
  }

  /// 클러스터 원형 마커 (숫자 표시)
  static Future<BitmapDescriptor> _clusterBitmap(int count) async {
    const int size = 72;
    const double c = size / 2.0;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    canvas.drawCircle(
      Offset(c, c + 3), 28,
      Paint()
        ..color = Colors.black.withAlpha(55)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
    );
    canvas.drawCircle(Offset(c, c), 34, Paint()..color = Colors.white);
    canvas.drawCircle(Offset(c, c), 26, Paint()..color = AppColors.primary);

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
  }

  /// 단일 vlog 썸네일 말풍선 마커
  /// - 네트워크 이미지를 Canvas에 그려 BitmapDescriptor 반환
  /// - 실패 시 아이콘 placeholder 사용
  static Future<BitmapDescriptor> _thumbnailMarkerBitmap(
      String url, bool isVideo) async {
    const int imgSize = 64;   // 이미지 영역 크기
    const int border  = 3;    // 흰 테두리 두께
    const int tailH   = 14;   // 꼬리 길이
    const int totalH  = imgSize + tailH;
    const double radius = 10.0;
    const double cx = imgSize / 2.0;

    // ── 네트워크 이미지 로드 ──────────────────────────────────────────────
    ui.Image? netImage;
    if (url.isNotEmpty) {
      try {
        final completer = Completer<ui.Image>();
        final stream = NetworkImage(url).resolve(const ImageConfiguration());
        late ImageStreamListener listener;
        listener = ImageStreamListener(
          (info, _) {
            if (!completer.isCompleted) completer.complete(info.image);
            stream.removeListener(listener);
          },
          onError: (e, _) {
            if (!completer.isCompleted) completer.completeError(e);
            stream.removeListener(listener);
          },
        );
        stream.addListener(listener);
        netImage = await completer.future.timeout(const Duration(seconds: 6));
      } catch (_) {}
    }

    // ── Canvas 드로잉 ─────────────────────────────────────────────────────
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // 그림자
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(3, 5, imgSize - 3.0, imgSize - 3.0),
        const Radius.circular(radius),
      ),
      Paint()
        ..color = Colors.black.withAlpha(65)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );

    // 흰 테두리
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, imgSize.toDouble(), imgSize.toDouble()),
        const Radius.circular(radius),
      ),
      Paint()..color = Colors.white,
    );

    // 내부 이미지 영역
    final innerRect = Rect.fromLTWH(
      border.toDouble(), border.toDouble(),
      (imgSize - border * 2).toDouble(), (imgSize - border * 2).toDouble(),
    );
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(
      innerRect, Radius.circular(radius - border + 1),
    ));

    if (netImage != null) {
      // cover-fit: 비율 유지하면서 꽉 채우기
      final srcW = netImage.width.toDouble();
      final srcH = netImage.height.toDouble();
      final scale = math.max(innerRect.width / srcW, innerRect.height / srcH);
      final takeW = innerRect.width / scale;
      final takeH = innerRect.height / scale;
      canvas.drawImageRect(
        netImage,
        Rect.fromLTWH(
            (srcW - takeW) / 2, (srcH - takeH) / 2, takeW, takeH),
        innerRect,
        Paint(),
      );
    } else {
      // 썸네일 없음 → 플레이스홀더
      canvas.drawRect(innerRect, Paint()..color = const Color(0xFFF1F3F4));
      final tp = TextPainter(textDirection: TextDirection.ltr)
        ..text = TextSpan(
          text: isVideo ? '▶' : '📷',
          style: const TextStyle(fontSize: 22),
        )
        ..layout();
      tp.paint(canvas, Offset(
        innerRect.center.dx - tp.width / 2,
        innerRect.center.dy - tp.height / 2,
      ));
    }
    canvas.restore();

    // 영상 배지 (우하단 반투명 원 + ▶)
    if (isVideo) {
      canvas.drawCircle(
        Offset(imgSize - 13.0, imgSize - 13.0), 10,
        Paint()..color = Colors.black.withAlpha(170),
      );
      canvas.drawPath(
        Path()
          ..moveTo(imgSize - 17.5, imgSize - 17.0)
          ..lineTo(imgSize - 7.5,  imgSize - 13.0)
          ..lineTo(imgSize - 17.5, imgSize - 9.0)
          ..close(),
        Paint()..color = Colors.white,
      );
    }

    // 꼬리 삼각형 (하단 중앙)
    const double tailW = 14.0;
    canvas.drawPath(
      Path()
        ..moveTo(cx - tailW / 2, imgSize - 1.0)
        ..lineTo(cx + tailW / 2, imgSize - 1.0)
        ..lineTo(cx, totalH.toDouble())
        ..close(),
      Paint()..color = Colors.white,
    );

    final img = await recorder.endRecording().toImage(imgSize, totalH);
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.bytes(data!.buffer.asUint8List());
  }

  LatLng get _center {
    if (widget.vlogs.isEmpty) return const LatLng(37.5665, 126.9780);
    final lat = widget.vlogs.map((e) => e.lat).reduce((a, b) => a + b) /
        widget.vlogs.length;
    final lng = widget.vlogs.map((e) => e.lng).reduce((a, b) => a + b) /
        widget.vlogs.length;
    return LatLng(lat, lng);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.vlogs.isEmpty) {
      return const _EmptyState(message: 'GPS가 기록된 브이로그가 없습니다.');
    }

    return Stack(
      children: [
        GoogleMap(
          initialCameraPosition:
              CameraPosition(target: _center, zoom: 13),
          markers: _markers,
          mapType: _mapType,
          zoomControlsEnabled: false,
          myLocationButtonEnabled: false,
          onMapCreated: (ctrl) {
            _mapController = ctrl;
            _mapCenter = _center;
            _rebuildMarkers();
          },
          onCameraMove: (pos) {
            _zoom = pos.zoom;
            _mapCenter = pos.target;
          },
          onCameraIdle: _rebuildMarkers,
          onTap: (_) => setState(() => _selected = null),
        ),

        // 지도 레이어 + 스트리트뷰 컨트롤
        Positioned(
          right: 12,
          bottom: _selected != null ? 164 : 16,
          child: MapControls(
            mapType: _mapType,
            onMapTypeChanged: (t) => setState(() => _mapType = t),
            center: _mapCenter,
          ),
        ),

        // 범례
        Positioned(
          top: 12,
          right: 12,
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(230),
              borderRadius: BorderRadius.circular(8),
              boxShadow: AppShadow.card,
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _MapLegend(color: Color(0xFFFF6B9D), label: '사진'),
                SizedBox(height: 3),
                _MapLegend(color: AppColors.primary, label: '영상'),
              ],
            ),
          ),
        ),

        // 선택된 단일 vlog 팝업
        if (_selected != null)
          Positioned(
            bottom: 16,
            left: 16,
            right: 16,
            child: _MapPopup(
              vlog: _selected!,
              onClose: () => setState(() => _selected = null),
            ),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 공통 서브 위젯
// ─────────────────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final String message;
  const _EmptyState(
      {this.message = '업로드한 브이로그가 없습니다.\n촬영 탭에서 사진·영상을 올려보세요!'});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.photo_library_outlined,
              size: 64, color: AppColors.textDisabled),
          const SizedBox(height: 16),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: AppColors.textSecondary, fontSize: 14),
          ),
        ],
      ),
    );
  }
}

class _MapPopup extends StatefulWidget {
  final Vlog vlog;
  final VoidCallback onClose;
  // onPlay 제거: 팝업 자신의 context로 직접 내비게이션 (_VlogPopup 패턴)
  const _MapPopup({required this.vlog, required this.onClose});

  @override
  State<_MapPopup> createState() => _MapPopupState();
}

class _MapPopupState extends State<_MapPopup> {
  String? _address; // 역지오코딩 결과 (null = 로드 중 또는 웹)

  @override
  void initState() {
    super.initState();
    _loadAddress();
  }

  Future<void> _loadAddress() async {
    if (kIsWeb) return; // geocoding 패키지 웹 미지원
    try {
      final placemarks = await placemarkFromCoordinates(
          widget.vlog.lat, widget.vlog.lng);
      if (!mounted || placemarks.isEmpty) return;
      final p = placemarks.first;
      final parts = <String>[
        if ((p.administrativeArea ?? '').isNotEmpty) p.administrativeArea!,
        if ((p.subAdministrativeArea ?? '').isNotEmpty)
          p.subAdministrativeArea!,
        if ((p.subLocality ?? '').isNotEmpty) p.subLocality!,
        if ((p.thoroughfare ?? '').isNotEmpty) p.thoroughfare!,
      ];
      if (parts.isNotEmpty && mounted) {
        setState(() => _address = parts.join(' '));
      }
    } catch (_) {}
  }

  bool get _isVideo => (widget.vlog.videoUrl ?? '').isNotEmpty;
  String get _thumbUrl => widget.vlog.thumbnailUrl ?? '';

  @override
  Widget build(BuildContext context) {
    final coordText =
        '${widget.vlog.lat.toStringAsFixed(7)}, ${widget.vlog.lng.toStringAsFixed(7)}';

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: AppShadow.elevated,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 썸네일 박스
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            child: SizedBox(
              width: 56,
              height: 56,
              child: _thumbUrl.isNotEmpty
                  ? Image.network(_thumbUrl, fit: BoxFit.cover,
                      errorBuilder: (context, error, stack) => _iconBox())
                  : _iconBox(),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // 제목
                Text(
                  widget.vlog.title,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                      fontSize: 14),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                // 장소명
                Row(children: [
                  const Icon(Icons.location_on,
                      size: 11, color: AppColors.primary),
                  const SizedBox(width: 2),
                  Expanded(
                    child: Text(
                      widget.vlog.placeName,
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.textSecondary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ]),
                const SizedBox(height: 2),
                // 좌표 (7자리)
                Text(
                  coordText,
                  style: const TextStyle(
                      fontSize: 9.5, color: AppColors.textDisabled),
                ),
                // 역지오코딩 주소 (로드 완료 시)
                if (_address != null) ...[
                  const SizedBox(height: 1),
                  Text(
                    _address!,
                    style: const TextStyle(
                        fontSize: 9.5, color: AppColors.textDisabled),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          // 닫기 + 보기 버튼
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.close,
                    size: 18, color: AppColors.textSecondary),
                onPressed: widget.onClose,
                padding: EdgeInsets.zero,
              ),
              ElevatedButton(
                // 팝업 자신의 context 사용 — 웹 호환(_VlogPopup과 동일 패턴)
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => VlogPlayerScreen(vlog: widget.vlog)),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm, vertical: 6),
                  minimumSize: Size.zero,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                ),
                child: const Text('▶ 보기', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _iconBox() => Container(
        color: AppColors.surfaceVariant,
        child: Center(
          child: Icon(
            _isVideo ? Icons.videocam : Icons.photo,
            color: AppColors.primary,
            size: 28,
          ),
        ),
      );
}

class _MapLegend extends StatelessWidget {
  final Color color;
  final String label;
  const _MapLegend({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(label,
            style: const TextStyle(
                fontSize: 10, color: AppColors.textPrimary)),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 갤러리 포토맵 클러스터 그룹
// ─────────────────────────────────────────────────────────────────────────────

class _GalleryCluster {
  final List<Vlog> vlogs;
  _GalleryCluster(this.vlogs);

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

// ─────────────────────────────────────────────────────────────────────────────
// 동일 위치 클러스터 목록 시트
// ─────────────────────────────────────────────────────────────────────────────

class _GalleryClusterSheet extends StatelessWidget {
  final List<Vlog> vlogs;
  final void Function(Vlog) onSelect;
  const _GalleryClusterSheet({required this.vlogs, required this.onSelect});

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
            Container(
              margin: const EdgeInsets.only(top: 10, bottom: 4),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.textDisabled,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
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
            Expanded(
              child: ListView.separated(
                controller: scrollCtrl,
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                itemCount: vlogs.length,
                separatorBuilder: (_, index) =>
                    const SizedBox(height: 8),
                itemBuilder: (_, i) =>
                    _GalleryVlogCard(vlog: vlogs[i], onSelect: onSelect),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 갤러리 클러스터 시트용 카드
class _GalleryVlogCard extends StatelessWidget {
  final Vlog vlog;
  final void Function(Vlog) onSelect;
  const _GalleryVlogCard({required this.vlog, required this.onSelect});

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
