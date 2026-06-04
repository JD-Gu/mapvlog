import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:firebase_auth/firebase_auth.dart';

import '../../models/friendship.dart';
import '../../models/vlog.dart';
import '../../screens/vlog/vlog_player_screen.dart';
import '../../services/firestore_service.dart';
import '../../services/friend_service.dart';
import '../../services/location_service.dart';
import '../../utils/constants.dart';
import '../../utils/marker_colors.dart';
import '../../utils/marker_emojis.dart';
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
  List<Vlog> _vlogs = [];
  List<String>? _friendUids;
  StreamSubscription<List<Friendship>>? _friendsSub;
  double _pixelRatio = 3.0;
  String? _categoryFilter; // null = 전체, 그 외 = MarkerEmojiGroup.name

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _pixelRatio = MediaQuery.of(context).devicePixelRatio;
  }
  Set<Marker> _markers = {};
  double _zoom = 12.0;
  MapType _mapType = MapType.normal;
  LatLng _mapCenter = _defaultLocation;
  LatLng? _pendingLocation; // 지도 준비 전에 GPS 위치가 도착하면 임시 저장
  StreamSubscription<List<Vlog>>? _vlogsSub; // 누수 방지

  @override
  void initState() {
    super.initState();
    _loadVlogs();
    // 첫 프레임 후 현재 위치로 카메라 이동
    WidgetsBinding.instance.addPostFrameCallback((_) => _initCurrentLocation());
  }

  Future<void> _initCurrentLocation() async {
    final pos = await LocationService.getCurrentPosition(context);
    if (pos == null || !mounted) return;
    final latlng = LatLng(pos.latitude, pos.longitude);
    setState(() => _mapCenter = latlng);
    if (_mapController != null) {
      _mapController!.animateCamera(CameraUpdate.newLatLng(latlng));
    } else {
      _pendingLocation = latlng; // onMapCreated 에서 처리
    }
  }

  // ─── 데이터 로드 ────────────────────────────────────────────────────────────

  void _loadVlogs() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _vlogs = [];
      _friendUids = [];
      return;
    }
    // 친구 목록 구독 → 친구 바뀌면 vlog 스트림 재구독
    _friendsSub = FriendService.watchMyFriends().listen((friends) {
      if (!mounted) return;
      final newUids = friends.map((f) => f.friendUid).toList();
      if (_friendUids != null &&
          _friendUids!.length == newUids.length &&
          _friendUids!.toSet().containsAll(newUids)) {
        return; // 변경 없음
      }
      _friendUids = newUids;
      _resubscribeVlogs();
    });
  }

  void _resubscribeVlogs() {
    _vlogsSub?.cancel();
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    _vlogsSub = FirestoreService.watchFriendsVlogs(
      friendUids: _friendUids ?? [],
      myUid: user.uid,
      limit: 50,
    ).listen((vlogs) {
      if (!mounted) return;
      // 체크인은 1시간 후 지도에서 자동 hide ("지금" 의미 사라짐)
      // 일반 vlog는 그대로 유지
      final now = DateTime.now();
      _vlogs = vlogs.where((v) {
        if (!v.isCheckIn) return true;
        return now.difference(v.createdAt).inMinutes < 60;
      }).toList();
      _rebuildMarkers();
    });
  }

  // ─── 클러스터링 ─────────────────────────────────────────────────────────────

  /// zoom 레벨에 따른 LatLng 반경 (줌 아웃 → 반경 커짐)
  double _clusterRadius() => 0.6 / math.pow(2, _zoom - 8);

  List<Vlog> get _filteredVlogs {
    if (_categoryFilter == null) return _vlogs;
    return _vlogs.where((v) {
      if (v.markerEmoji == null) return _categoryFilter == '일반';
      return MarkerEmojis.fromEmoji(v.markerEmoji).category ==
          _categoryFilter;
    }).toList();
  }

  List<_ClusterGroup> _computeClusters() {
    final source = _filteredVlogs;
    if (source.isEmpty) return [];
    final radius = _clusterRadius();
    final groups = <_ClusterGroup>[];
    final assigned = <String>{};

    for (final vlog in source) {
      if (assigned.contains(vlog.id)) continue;
      final nearby = source.where((other) {
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
    if (group.isSingle) {
      // 단일 마커: 제목 라벨 + 핀 비트맵
      final vlog  = group.vlogs.first;
      final color = MarkerColors.fromValue(vlog.markerColor);
      final res   = await _singleMarkerWithLabel(vlog, color, _pixelRatio);
      return Marker(
        markerId: MarkerId(group.id),
        position: group.center,
        icon: res.icon,
        anchor: res.anchor,
        onTap: () {
          HapticFeedback.selectionClick();
          _openVlogSheet(vlog);
        },
      );
    }

    // 클러스터 마커
    return Marker(
      markerId: MarkerId(group.id),
      position: group.center,
      icon: await _clusterMarkerBitmap(group.count, _pixelRatio),
      anchor: const Offset(0.5, 0.5),
      onTap: () {
        HapticFeedback.selectionClick();
        if (_wouldClusterAtMaxZoom(group)) {
          _showClusterList(group.vlogs);
        } else {
          // 한 번에 클러스터 멤버 전체 영역으로 줌 → 즉시 분기
          _fitToCluster(group);
        }
      },
    );
  }

  /// 클러스터 멤버 전체를 화면에 꽉 차게 줌 (한 번 탭으로 분기).
  void _fitToCluster(_ClusterGroup group) {
    final ctrl = _mapController;
    if (ctrl == null) return;
    double minLat = group.vlogs.first.lat, maxLat = minLat;
    double minLng = group.vlogs.first.lng, maxLng = minLng;
    for (final v in group.vlogs) {
      minLat = math.min(minLat, v.lat);
      maxLat = math.max(maxLat, v.lat);
      minLng = math.min(minLng, v.lng);
      maxLng = math.max(maxLng, v.lng);
    }
    // degenerate(0 크기) bounds만 방지 — 과도한 패딩은 줌인을 막으므로 최소값
    const eps = 0.00003; // ≈3m
    if ((maxLat - minLat).abs() < eps) {
      minLat -= eps;
      maxLat += eps;
    }
    if ((maxLng - minLng).abs() < eps) {
      minLng -= eps;
      maxLng += eps;
    }
    final bounds = LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );
    // 패딩 작게 → 멤버 영역을 더 꽉 차게(더 깊이 줌) → 한 번에 분기
    ctrl.animateCamera(CameraUpdate.newLatLngBounds(bounds, 48));
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
          // 웹 호환: sheetCtx가 아닌 캡처한 nav 사용
          nav.pop();  // 시트 닫기
          nav.push(MaterialPageRoute(
              builder: (_) => VlogPlayerScreen(vlog: vlog)));
        },
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 마커 비트맵 생성 (모던/플레이풀 디자인)
  // ═══════════════════════════════════════════════════════════════════════════

  /// 단일 마커: 미디어 아이콘 + 그라디언트 핀 + 글로우 + 라벨 칩
  ///
  /// [vlog]의 미디어 타입(영상/사진/멀티사진)에 따라 핀 안 아이콘이 달라짐.
  /// 라벨 칩은 마커 색상 강조 보더 + 흰 배경 + 미세 그림자.
  static Future<({BitmapDescriptor icon, Offset anchor})>
      _singleMarkerWithLabel(Vlog vlog, Color color, double r) async {
    // ── 라벨 텍스트 준비 ─────────────────────────────────────────────
    final displayTitle = vlog.title.length > 12
        ? '${vlog.title.substring(0, 11)}…'
        : vlog.title;

    final double lPadV   = 5.0 * r;
    final double lPadH   = 9.0 * r;
    final double lGap    = 4.0 * r;
    final double lRadius = 10.0 * r;

    final tp = TextPainter(textDirection: TextDirection.ltr)
      ..text = TextSpan(
        text: displayTitle,
        style: TextStyle(
          fontSize: 11.0 * r,
          fontWeight: FontWeight.w700,
          color: const Color(0xFF202124),
          letterSpacing: -0.2 * r,
        ),
      )
      ..layout(maxWidth: 140 * r);

    // ── 치수 계산 ────────────────────────────────────────────────────
    final double pinW        = 68 * r;
    final double pinH        = 84 * r;
    final double pinTipRelY  = 80.0 * r;
    final double pinCircleR  = 26.0 * r;
    final double pinCircleCY = 30.0 * r;
    final double glowR       = 34.0 * r;

    final double labelW =
        (tp.width + lPadH * 2).clamp(46.0 * r, 150.0 * r);
    final double labelH = tp.height + lPadV * 2;
    final int    totalW =
        math.max(pinW, labelW).ceil() + (8 * r).ceil();
    final int    totalH = (labelH + lGap + pinH).ceil();
    final double cx     = totalW / 2.0;
    final double lblX   = cx - labelW / 2.0;
    final double pinTop = labelH + lGap;

    final recorder = ui.PictureRecorder();
    final canvas   = Canvas(recorder);

    // ── 라벨 칩 (둥근 사각형) ────────────────────────────────────────
    // 그림자
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(lblX, 3 * r, labelW, labelH),
        Radius.circular(lRadius),
      ),
      Paint()
        ..color = Colors.black.withAlpha(40)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 4 * r),
    );
    // 흰 배경
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(lblX, 0, labelW, labelH),
        Radius.circular(lRadius),
      ),
      Paint()..color = Colors.white,
    );
    // 컬러 보더
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(lblX, 0, labelW, labelH),
        Radius.circular(lRadius),
      ),
      Paint()
        ..color = color.withAlpha(150)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5 * r,
    );
    // 텍스트
    tp.paint(canvas, Offset(lblX + lPadH, lPadV));

    // ── 핀 ─────────────────────────────────────────────────────────
    // 글로우 (블러된 컬러 원)
    canvas.drawCircle(
      Offset(cx, pinTop + pinCircleCY),
      glowR,
      Paint()
        ..color = color.withAlpha(70)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 10 * r),
    );
    // 드롭 섀도우
    canvas.drawCircle(
      Offset(cx, pinTop + pinCircleCY + 4 * r),
      pinCircleR - 2 * r,
      Paint()
        ..color = Colors.black.withAlpha(70)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 6 * r),
    );
    // 꼬리 (그라디언트)
    final tailPath = Path()
      ..moveTo(cx - 14 * r, pinTop + pinCircleCY + 14 * r)
      ..quadraticBezierTo(
          cx - 6 * r, pinTop + pinCircleCY + 32 * r, cx, pinTop + pinTipRelY)
      ..quadraticBezierTo(
          cx + 6 * r, pinTop + pinCircleCY + 32 * r, cx + 14 * r,
          pinTop + pinCircleCY + 14 * r)
      ..close();
    canvas.drawPath(
        tailPath,
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(cx, pinTop + pinCircleCY),
            Offset(cx, pinTop + pinTipRelY),
            [color, Color.lerp(color, Colors.black, 0.35) ?? color],
          ));
    // 원 본체 — 그라디언트 (좌상단 밝게, 우하단 진하게)
    canvas.drawCircle(
      Offset(cx, pinTop + pinCircleCY),
      pinCircleR,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(cx - pinCircleR * 0.6, pinTop + pinCircleCY - pinCircleR * 0.6),
          Offset(cx + pinCircleR * 0.6, pinTop + pinCircleCY + pinCircleR * 0.6),
          [
            Color.lerp(color, Colors.white, 0.25) ?? color,
            Color.lerp(color, Colors.black, 0.20) ?? color,
          ],
        ),
    );
    // 흰 테두리 링
    canvas.drawCircle(
      Offset(cx, pinTop + pinCircleCY),
      pinCircleR,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.0 * r,
    );

    // ── 중앙 표시: 이모지가 있으면 이모지, 없으면 미디어 아이콘 ──────
    final emoji = vlog.markerEmoji;
    if (emoji != null && emoji.isNotEmpty) {
      // 이모지 직접 렌더링 (컬러 이모지 폰트 사용)
      final emojiPainter = TextPainter(textDirection: TextDirection.ltr)
        ..text = TextSpan(
          text: emoji,
          style: TextStyle(fontSize: 28 * r),
        )
        ..layout();
      emojiPainter.paint(
        canvas,
        Offset(
          cx - emojiPainter.width / 2,
          pinTop + pinCircleCY - emojiPainter.height / 2,
        ),
      );
    } else {
      IconData icon;
      if (vlog.hasVideo) {
        icon = Icons.play_arrow_rounded;
      } else if (vlog.photoUrls.length > 1) {
        icon = Icons.collections;
      } else {
        icon = Icons.photo_camera;
      }
      final iconPainter = TextPainter(textDirection: TextDirection.ltr)
        ..text = TextSpan(
          text: String.fromCharCode(icon.codePoint),
          style: TextStyle(
            fontSize: 24 * r,
            fontFamily: icon.fontFamily,
            package: icon.fontPackage,
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        )
        ..layout();
      iconPainter.paint(
        canvas,
        Offset(
          cx - iconPainter.width / 2,
          pinTop + pinCircleCY - iconPainter.height / 2,
        ),
      );
    }

    // ── 비트맵 변환 (imagePixelRatio 적용으로 선명) ───────────────
    final img  = await recorder.endRecording().toImage(totalW, totalH);
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    final iconBmp = BitmapDescriptor.bytes(
      data!.buffer.asUint8List(),
      imagePixelRatio: r,
    );

    final anchorY = (pinTop + pinTipRelY) / totalH;
    return (icon: iconBmp, anchor: Offset(0.5, anchorY));
  }

  /// 클러스터 마커: 그라디언트 + 글로우 + 큰 카운트 + "VLOGS" 라벨
  static Future<BitmapDescriptor> _clusterMarkerBitmap(
      int count, double r) async {
    final int size = (88 * r).ceil();
    final double c = size / 2.0;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // 외곽 글로우
    canvas.drawCircle(
      Offset(c, c),
      40 * r,
      Paint()
        ..color = AppColors.primary.withAlpha(80)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 12 * r),
    );
    // 드롭 섀도우
    canvas.drawCircle(
      Offset(c, c + 4 * r),
      32 * r,
      Paint()
        ..color = Colors.black.withAlpha(70)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 8 * r),
    );
    // 흰색 외곽 링
    canvas.drawCircle(Offset(c, c), 36 * r, Paint()..color = Colors.white);
    // 메인 그라디언트 본체
    canvas.drawCircle(
      Offset(c, c),
      30 * r,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(c - 20 * r, c - 20 * r),
          Offset(c + 20 * r, c + 20 * r),
          [
            const Color(0xFF42A5F5),
            const Color(0xFF1565C0),
          ],
        ),
    );
    // 하이라이트
    canvas.drawCircle(
      Offset(c - 8 * r, c - 10 * r),
      14 * r,
      Paint()
        ..color = Colors.white.withAlpha(60)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 6 * r),
    );

    // 카운트 텍스트
    final label = count > 99 ? '99+' : '$count';
    final tp = TextPainter(textDirection: TextDirection.ltr)
      ..text = TextSpan(
        text: label,
        style: TextStyle(
          fontSize: (label.length > 2 ? 16.0 : 22.0) * r,
          color: Colors.white,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.5 * r,
          shadows: [
            Shadow(
              color: const Color(0x66000000),
              blurRadius: 4 * r,
              offset: Offset(0, 1 * r),
            ),
          ],
        ),
      )
      ..layout();
    tp.paint(canvas, Offset(c - tp.width / 2, c - tp.height / 2 - 4 * r));

    // "VLOGS" 라벨
    final subPainter = TextPainter(textDirection: TextDirection.ltr)
      ..text = TextSpan(
        text: 'VLOGS',
        style: TextStyle(
          fontSize: 8.5 * r,
          color: Colors.white,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2 * r,
        ),
      )
      ..layout();
    subPainter.paint(canvas, Offset(c - subPainter.width / 2, c + 11 * r));

    final img = await recorder.endRecording().toImage(size, size);
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.bytes(
      data!.buffer.asUint8List(),
      imagePixelRatio: r,
    );
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
    _friendsSub?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  // ─── UI ──────────────────────────────────────────────────────────────────

  /// 마커 선택 시 모달 바텀시트 표시
  void _openVlogSheet(Vlog vlog) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _VlogBottomSheet(
        vlog: vlog,
        onPlay: () {
          Navigator.pop(context);
          Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => VlogPlayerScreen(vlog: vlog)),
          );
        },
      ),
    );
  }

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
            onMapCreated: (controller) {
              _mapController = controller;
              if (_pendingLocation != null) {
                controller.animateCamera(
                    CameraUpdate.newLatLng(_pendingLocation!));
                _pendingLocation = null;
              }
            },
            onCameraMove: (pos) {
              _zoom = pos.zoom;
              _mapCenter = pos.target;
            },
            onCameraIdle: _rebuildMarkers,
          ),

          // ── 상단 뒤로가기 + 검색바 (글래스 효과 + 카운트 칩) ─────────────
          Positioned(
            top: MediaQuery.of(context).padding.top + 10,
            left: AppSpacing.md,
            right: AppSpacing.md,
            child: Row(
              children: [
                // 뒤로가기 버튼 (MapScreen은 push로 진입하므로 필요)
                Material(
                  color: Theme.of(context).colorScheme.surface,
                  shape: const CircleBorder(),
                  elevation: 4,
                  shadowColor: Colors.black.withAlpha(40),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () {
                      HapticFeedback.selectionClick();
                      Navigator.pop(context);
                    },
                    child: SizedBox(
                      width: 44,
                      height: 44,
                      child: Icon(Icons.arrow_back,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface,
                          size: 22),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      // TODO: 검색 화면
                    },
                    child: Container(
                      height: 52,
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(AppRadius.full),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withAlpha(28),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [
                                  Color(0xFF1A73E8),
                                  Color(0xFF00ACC1),
                                ],
                              ),
                              borderRadius:
                                  BorderRadius.circular(AppRadius.full),
                            ),
                            child: const Icon(Icons.search,
                                color: Colors.white, size: 20),
                          ),
                          const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        '장소·브이로그 검색',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    if (_vlogs.isNotEmpty)
                      Container(
                        margin: const EdgeInsets.only(right: 6),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: AppColors.primary
                              .withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.place,
                                size: 12, color: AppColors.primary),
                            const SizedBox(width: 3),
                            Text(
                              '${_vlogs.length}',
                              style: const TextStyle(
                                color: AppColors.primary,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
                  ),
                ],
              ),
            ),

          // ── 카테고리 칩 필터 (검색바 아래) ────────────────────────────
          Positioned(
            top: MediaQuery.of(context).padding.top + 70,
            left: 0,
            right: 0,
            child: SizedBox(
              height: 38,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md),
                children: [
                  _CategoryFilterChip(
                    label: '전체',
                    emoji: '🌐',
                    selected: _categoryFilter == null,
                    onTap: () => setState(() {
                      _categoryFilter = null;
                      _rebuildMarkers();
                    }),
                  ),
                  const SizedBox(width: 6),
                  ...MarkerEmojis.groups.map((g) => Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: _CategoryFilterChip(
                          label: g.name,
                          emoji: g.hint,
                          selected: _categoryFilter == g.name,
                          onTap: () => setState(() {
                            _categoryFilter = g.name;
                            _rebuildMarkers();
                          }),
                        ),
                      )),
                ],
              ),
            ),
          ),

          // ── 우측 컨트롤 스택 (지도 레이어 + 스트리트뷰 + 현재 위치) ──
          Positioned(
            right: AppSpacing.md,
            bottom: AppSpacing.xl,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                MapControls(
                  mapType: _mapType,
                  onMapTypeChanged: (t) {
                    HapticFeedback.selectionClick();
                    setState(() => _mapType = t);
                  },
                  center: _mapCenter,
                ),
                const SizedBox(height: 10),
                _MapFab(
                  icon: Icons.my_location,
                  color: AppColors.primary,
                  onTap: () {
                    HapticFeedback.lightImpact();
                    _moveToCurrentLocation();
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── 지도용 FAB (현재위치 등) ────────────────────────────────────────────────
class _MapFab extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _MapFab({
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 6,
      shape: const CircleBorder(),
      shadowColor: Colors.black54,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Container(
          width: 48,
          height: 48,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.surface,
          ),
          child: Icon(icon, color: color, size: 22),
        ),
      ),
    );
  }
}

// ─── 마커 탭 시 큰 바텀시트 ──────────────────────────────────────────────────
class _VlogBottomSheet extends StatelessWidget {
  final Vlog vlog;
  final VoidCallback onPlay;
  const _VlogBottomSheet({required this.vlog, required this.onPlay});

  @override
  Widget build(BuildContext context) {
    final thumbUrl = vlog.thumbnailUrl ?? '';
    final markerColor = MarkerColors.fromValue(vlog.markerColor);

    return Container(
      margin: const EdgeInsets.fromLTRB(8, 0, 8, 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg + 4),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(50),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 드래그 핸들
          Container(
            margin: const EdgeInsets.only(top: 10),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.textDisabled.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 10),
          // 헤더: 마커색 표시 + 제목 + 닫기
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        markerColor,
                        Color.lerp(markerColor, Colors.black, 0.25) ??
                            markerColor,
                      ],
                    ),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: markerColor.withValues(alpha: 0.5),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  child: const Icon(Icons.location_on,
                      color: Colors.white, size: 16),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        vlog.title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          letterSpacing: -0.3,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        vlog.placeName,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close,
                      color: AppColors.textSecondary, size: 22),
                ),
              ],
            ),
          ),
          // 큰 미디어 영역
          Stack(
            children: [
              SizedBox(
                width: double.infinity,
                height: 220,
                child: thumbUrl.isNotEmpty
                    ? Image.network(thumbUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            _placeholder(vlog.hasVideo))
                    : _placeholder(vlog.hasVideo),
              ),
              // 그라디언트 오버레이
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.35),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              // 미디어 타입 배지 (좌상단)
              Positioned(
                top: 10,
                left: 10,
                child: _MediaBadge(
                  icon: vlog.hasVideo
                      ? Icons.play_arrow_rounded
                      : Icons.photo_camera,
                  label: vlog.hasVideo ? '영상' : '사진',
                ),
              ),
              // 통계 (좌하단)
              Positioned(
                bottom: 10,
                left: 10,
                child: Row(
                  children: [
                    _StatChip(
                        icon: Icons.favorite,
                        color: AppColors.error,
                        value: '${vlog.likeCount}'),
                    const SizedBox(width: 6),
                    _StatChip(
                        icon: Icons.visibility_outlined,
                        color: Colors.white,
                        value: '${vlog.viewCount}'),
                  ],
                ),
              ),
              // 작성자 (우하단)
              Positioned(
                bottom: 10,
                right: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.black.withAlpha(140),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.person,
                          color: Colors.white, size: 13),
                      const SizedBox(width: 3),
                      Text(
                        vlog.authorName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          // 주소 (있을 때만)
          if (vlog.address != null && vlog.address!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: [
                  const Icon(Icons.place_outlined,
                      size: 14, color: AppColors.textDisabled),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      vlog.address!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          // 액션 버튼
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  HapticFeedback.mediumImpact();
                  onPlay();
                },
                icon: const Icon(Icons.play_arrow_rounded, size: 22),
                label: const Text(
                  '재생',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  elevation: 3,
                  shadowColor: AppColors.primary.withValues(alpha: 0.5),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.full),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _placeholder(bool isVideo) => Container(
        color: AppColors.surfaceVariant,
        child: Icon(isVideo ? Icons.videocam : Icons.photo,
            size: 56, color: AppColors.textDisabled),
      );
}

class _MediaBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  const _MediaBadge({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(140),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 13),
          const SizedBox(width: 3),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String value;
  const _StatChip({
    required this.icon,
    required this.color,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(150),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 13),
          const SizedBox(width: 3),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── 동일 위치 클러스터 목록 시트 ─────────────────────────────────────────────

class _ClusterListSheet extends StatefulWidget {
  final List<Vlog> vlogs;
  final void Function(Vlog) onSelect;
  const _ClusterListSheet({required this.vlogs, required this.onSelect});

  @override
  State<_ClusterListSheet> createState() => _ClusterListSheetState();
}

class _ClusterListSheetState extends State<_ClusterListSheet> {
  String? _filter;

  List<Vlog> get _shown {
    if (_filter == null) return widget.vlogs;
    return widget.vlogs.where((v) {
      if (v.markerEmoji == null) return _filter == '일반';
      return MarkerEmojis.fromEmoji(v.markerEmoji).category == _filter;
    }).toList();
  }

  // 표시되는 카테고리만 칩으로 노출 (모두 표시 시 칩 영역 숨김)
  Set<String> get _availableCategories {
    final s = <String>{};
    for (final v in widget.vlogs) {
      s.add(v.markerEmoji == null
          ? '일반'
          : MarkerEmojis.fromEmoji(v.markerEmoji).category);
    }
    return s;
  }

  @override
  Widget build(BuildContext context) {
    final available = _availableCategories;
    final filteredCount = _shown.length;
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
                    '같은 위치의 브이로그 $filteredCount개',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
            // 카테고리 칩 필터 (2개 이상 카테고리가 있을 때만)
            if (available.length > 1)
              SizedBox(
                height: 38,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 4),
                  children: [
                    _CategoryFilterChip(
                      label: '전체',
                      emoji: '🌐',
                      selected: _filter == null,
                      onTap: () => setState(() => _filter = null),
                    ),
                    const SizedBox(width: 6),
                    ...MarkerEmojis.groups
                        .where((g) => available.contains(g.name))
                        .map((g) => Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: _CategoryFilterChip(
                                label: g.name,
                                emoji: g.hint,
                                selected: _filter == g.name,
                                onTap: () =>
                                    setState(() => _filter = g.name),
                              ),
                            )),
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
                itemCount: _shown.length,
                separatorBuilder: (_, index) =>
                    const SizedBox(height: 8),
                itemBuilder: (_, i) =>
                    _VlogCard(vlog: _shown[i], onSelect: widget.onSelect),
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
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
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

// ─── 카테고리 필터 칩 (지도 상단) ─────────────────────────────────────────
class _CategoryFilterChip extends StatelessWidget {
  final String label;
  final String emoji;
  final bool selected;
  final VoidCallback onTap;
  const _CategoryFilterChip({
    required this.label,
    required this.emoji,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.full),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(24),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 14)),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: selected ? Colors.white : AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
