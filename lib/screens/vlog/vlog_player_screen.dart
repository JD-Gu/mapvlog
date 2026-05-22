import 'dart:async';
import 'dart:ui' as ui;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geocoding/geocoding.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:video_player/video_player.dart';

import '../../models/vlog.dart';
import '../../services/firestore_service.dart';
import '../../services/gps_interpolator.dart';
import '../../utils/constants.dart';
import '../../utils/marker_colors.dart';
import '../../widgets/map_controls.dart';

/// 영상·지도 동기화 플레이어
///
/// 레이아웃: 상단 영상 / 하단 지도 (세로 분할)
/// - 영상 재생 타임코드 → GPS 보간 → 지도 마커 실시간 이동
/// - 이동 경로 폴리라인 표시
/// - 가로 모드 전환 시 영상 전체화면
class VlogPlayerScreen extends StatefulWidget {
  final Vlog vlog;

  const VlogPlayerScreen({super.key, required this.vlog});

  @override
  State<VlogPlayerScreen> createState() => _VlogPlayerScreenState();
}

class _VlogPlayerScreenState extends State<VlogPlayerScreen> {
  // ─── 영상 플레이어 ────────────────────────────────────────────────────────
  VideoPlayerController? _videoController;
  bool _videoReady = false;
  bool _showControls = true; // 항상 표시, 탭으로 수동 토글만 허용
  bool _isBuffering = false; // 버퍼링 중 스피너 표시용

  // ─── 지도 ────────────────────────────────────────────────────────────────
  GoogleMapController? _mapController;
  // ignore: unused_field  (지도 카메라 애니메이션 목적으로만 사용)
  LatLng? _currentPosition;
  Set<Polyline> _polylines = {};
  Set<Marker> _markers = {};
  BitmapDescriptor? _currentMarkerIcon; // 파란 현재위치 마커 (캐시)
  MapType _mapType = MapType.normal;
  LatLng _mapCenter = const LatLng(37.5665, 126.9780);
  /// 현재위치 마커 탭 시 역지오코딩 결과 캐시 (null = 좌표만 표시)
  String? _currentMarkerAddress;

  // ─── 로컬 편집 상태 (수정 후 즉시 반영용) ───────────────────────────────────
  late String _title;
  late String _placeName;

  // ─── 좋아요 ────────────────────────────────────────────────────────────────
  bool _isLiked = false;
  bool _isLikeLoading = false; // 중복 탭 방지
  late int _likeCount;

  // ─── 화면 방향 / 레이아웃 ─────────────────────────────────────────────────
  bool _isFullscreen = false;
  /// true = 좌(미디어) | 우(지도)  /  false = 상(미디어) | 하(지도)
  bool _isHorizontalSplit = false;

  /// 현재 로그인 사용자가 이 vlog의 등록자인지 여부
  bool get _isAuthor =>
      FirebaseAuth.instance.currentUser?.uid == widget.vlog.authorId;

  @override
  void initState() {
    super.initState();
    _title = widget.vlog.title;
    _placeName = widget.vlog.placeName;
    _likeCount = widget.vlog.likeCount;
    _initVideo();
    _initMapAsync();
    _checkIfLiked();
    // 조회수 증가 (비동기, 결과 무시)
    FirestoreService.incrementView(widget.vlog.id);
  }

  // ─── 초기화 ───────────────────────────────────────────────────────────────

  /// 현재 사용자가 이미 좋아요를 눌렀는지 확인
  Future<void> _checkIfLiked() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final liked = await FirestoreService.isLiked(widget.vlog.id, uid);
    if (mounted) setState(() => _isLiked = liked);
  }

  /// 좋아요 토글 (낙관적 UI 업데이트 + 중복 탭 방지)
  Future<void> _toggleLike() async {
    if (_isLikeLoading) return; // 중복 탭 차단
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('좋아요는 로그인 후 이용할 수 있습니다.')),
      );
      return;
    }
    setState(() {
      _isLikeLoading = true;
      _isLiked = !_isLiked;
      _likeCount += _isLiked ? 1 : -1;
    });
    await FirestoreService.toggleLike(widget.vlog.id, uid);
    if (mounted) setState(() => _isLikeLoading = false);
  }

  Future<void> _initVideo() async {
    if (!widget.vlog.hasVideo) return;

    final ctrl = VideoPlayerController.networkUrl(
      Uri.parse(widget.vlog.videoUrl!),
    );

    try {
      await ctrl.initialize();
      ctrl.addListener(_onVideoTick);
      if (!mounted) return;
      setState(() {
        _videoController = ctrl;
        _videoReady = true;
      });
    } catch (e) {
      debugPrint('영상 초기화 실패: $e');
    }
  }

  Future<void> _initMapAsync() async {
    final track = widget.vlog.gpsTrack;
    if (track.isEmpty) return;

    // 폴리라인 (전체 경로)
    final polylines = {
      Polyline(
        polylineId: const PolylineId('route'),
        points: GpsInterpolator.toPolyline(track),
        color: AppColors.primary,
        width: 4,
        patterns: [],
      ),
    };

    // 등록자가 선택한 마커 색상 (없으면 기본 파랑)
    final vlogColor = MarkerColors.fromValue(widget.vlog.markerColor);

    final startIcon   = await _coloredPinMarker(Colors.green);
    final endIcon     = await _coloredPinMarker(AppColors.error);
    final currentIcon = await _coloredPinMarker(vlogColor);

    // 출발·도착 좌표 문자열 (7자리)
    final startLat = track.first.lat;
    final startLng = track.first.lng;
    final endLat   = track.last.lat;
    final endLng   = track.last.lng;
    final startCoord = '${startLat.toStringAsFixed(7)}, ${startLng.toStringAsFixed(7)}';
    final endCoord   = '${endLat.toStringAsFixed(7)}, ${endLng.toStringAsFixed(7)}';

    // 초기 마커 (역지오코딩 전 "로드 중..." 표시)
    var markers = <Marker>{
      Marker(
        markerId: const MarkerId('start'),
        position: LatLng(startLat, startLng),
        icon: startIcon,
        infoWindow: InfoWindow(title: '출발', snippet: startCoord),
        anchor: const Offset(0.5, 1.0),
      ),
      Marker(
        markerId: const MarkerId('end'),
        position: LatLng(endLat, endLng),
        icon: endIcon,
        infoWindow: InfoWindow(title: '도착', snippet: endCoord),
        anchor: const Offset(0.5, 1.0),
      ),
    };

    // ── 출발·도착 역지오코딩 (병렬) ─────────────────────────────────────────
    if (!kIsWeb) {
      final results = await Future.wait([
        _buildGeoSnippet(startLat, startLng, startCoord),
        _buildGeoSnippet(endLat, endLng, endCoord),
      ]);
      markers = {
        Marker(
          markerId: const MarkerId('start'),
          position: LatLng(startLat, startLng),
          icon: startIcon,
          infoWindow: InfoWindow(title: '출발', snippet: results[0]),
          anchor: const Offset(0.5, 1.0),
        ),
        Marker(
          markerId: const MarkerId('end'),
          position: LatLng(endLat, endLng),
          icon: endIcon,
          infoWindow: InfoWindow(title: '도착', snippet: results[1]),
          anchor: const Offset(0.5, 1.0),
        ),
      };
    }

    if (!mounted) return;
    setState(() {
      _polylines = polylines;
      _markers = markers;
      _currentMarkerIcon = currentIcon;
      _currentPosition = LatLng(startLat, startLng);
    });
  }

  /// 좌표 → "lat, lng\n주소" 문자열 (실패 시 좌표만 반환)
  static Future<String> _buildGeoSnippet(
      double lat, double lng, String coordText) async {
    try {
      final placemarks = await placemarkFromCoordinates(lat, lng);
      if (placemarks.isNotEmpty) {
        final p = placemarks.first;
        final parts = <String>[
          if ((p.administrativeArea ?? '').isNotEmpty) p.administrativeArea!,
          if ((p.subAdministrativeArea ?? '').isNotEmpty)
            p.subAdministrativeArea!,
          if ((p.subLocality ?? '').isNotEmpty) p.subLocality!,
          if ((p.thoroughfare ?? '').isNotEmpty) p.thoroughfare!,
        ];
        if (parts.isNotEmpty) return '$coordText\n${parts.join(' ')}';
      }
    } catch (_) {}
    return coordText;
  }

  /// 현재위치 마커 탭 시 역지오코딩 → snippet 갱신
  Future<void> _geocodeCurrentMarker(LatLng pos) async {
    if (kIsWeb) return;
    final snippet = await _buildGeoSnippet(
      pos.latitude, pos.longitude,
      '${pos.latitude.toStringAsFixed(7)}, ${pos.longitude.toStringAsFixed(7)}',
    );
    if (!mounted) return;
    setState(() => _currentMarkerAddress = snippet);
  }

  /// 웹·모바일 공용 컬러 핀 마커 생성
  /// (BitmapDescriptor.defaultMarkerWithHue는 웹 미지원)
  static Future<BitmapDescriptor> _coloredPinMarker(Color color) async {
    const int w = 36, h = 48;
    const double cx = w / 2.0;
    const double r = 14.0;
    const double cy = 16.0;
    const double tipY = 44.0;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // 꼬리
    final tail = Path()
      ..moveTo(cx - 9, cy + 9)
      ..quadraticBezierTo(cx - 5, cy + 20, cx, tipY)
      ..quadraticBezierTo(cx + 5, cy + 20, cx + 9, cy + 9)
      ..close();
    canvas.drawPath(tail, Paint()..color = color);

    // 원 본체
    canvas.drawCircle(Offset(cx, cy), r, Paint()..color = color);

    // 흰 테두리 링
    canvas.drawCircle(
      Offset(cx, cy), r,
      Paint()
        ..color = Colors.white.withAlpha(200)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );

    // 흰 중심 점
    canvas.drawCircle(Offset(cx, cy), 5, Paint()..color = Colors.white);

    final img = await recorder.endRecording().toImage(w, h);
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.bytes(data!.buffer.asUint8List());
  }

  // ─── 영상 동기화 콜백 ─────────────────────────────────────────────────────

  void _onVideoTick() {
    if (_videoController == null) return;

    // 버퍼링 상태 감지 → 스피너 표시 전환
    final buffering = _videoController!.value.isBuffering;
    if (buffering != _isBuffering) {
      setState(() => _isBuffering = buffering);
    }

    // 버퍼링 중에는 맵 동기화 스킵 (불필요한 setState 방지)
    if (buffering) return;

    final timeMs = _videoController!.value.position.inMilliseconds;
    _syncMapToTime(timeMs);
  }

  void _syncMapToTime(int videoTimeMs) {
    final track = widget.vlog.gpsTrack;
    if (track.isEmpty) return;

    final pos = GpsInterpolator.interpolate(track, videoTimeMs);
    if (pos == null || !mounted) return;

    // 지도 마커 업데이트
    final updatedMarkers = Set<Marker>.from(
      _markers.where((m) =>
          m.markerId.value != 'current' &&
          m.markerId.value != 'start' &&
          m.markerId.value != 'end'),
    )
      ..addAll(_markers.where(
          (m) => m.markerId.value == 'start' || m.markerId.value == 'end'))
      ..add(Marker(
        markerId: const MarkerId('current'),
        position: pos,
        icon: _currentMarkerIcon ?? BitmapDescriptor.defaultMarker,
        infoWindow: InfoWindow(
          title: '현재 위치',
          snippet: _currentMarkerAddress ??
              '${pos.latitude.toStringAsFixed(7)}, ${pos.longitude.toStringAsFixed(7)}',
        ),
        onTap: () => _geocodeCurrentMarker(pos),
        anchor: const Offset(0.5, 1.0),
        zIndexInt: 2,
      ));

    setState(() {
      _currentPosition = pos;
      _markers = updatedMarkers;
    });

    // 카메라가 현재 위치를 따라가도록
    _mapController?.animateCamera(
      CameraUpdate.newLatLng(pos),
    );
  }

  // ─── 컨트롤 표시/숨김 ─────────────────────────────────────────────────────

  /// 영상 탭 → 컨트롤 수동 토글 (자동 숨김 없음)
  void _onTapVideo() {
    setState(() => _showControls = !_showControls);
  }

  // ─── 재생 컨트롤 ──────────────────────────────────────────────────────────

  void _togglePlay() {
    if (_videoController == null) return;
    setState(() {
      if (_videoController!.value.isPlaying) {
        _videoController!.pause();
      } else {
        _videoController!.play();
      }
    });
  }

  void _seekTo(double ratio) {
    if (_videoController == null) return;
    final duration = _videoController!.value.duration;
    final target = Duration(
        milliseconds: (duration.inMilliseconds * ratio).round());
    _videoController!.seekTo(target);
  }

  void _rewind10() {
    if (_videoController == null) return;
    final current = _videoController!.value.position;
    _videoController!
        .seekTo(current - const Duration(seconds: 10));
  }

  void _forward10() {
    if (_videoController == null) return;
    final current = _videoController!.value.position;
    _videoController!
        .seekTo(current + const Duration(seconds: 10));
  }

  // ─── 전체화면 전환 ─────────────────────────────────────────────────────────

  void _toggleFullscreen() {
    setState(() => _isFullscreen = !_isFullscreen);
    if (_isFullscreen) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);
    } else {
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  }

  // ─── 수정 / 삭제 (등록자 전용) ───────────────────────────────────────────

  /// 등록자 전용 바텀시트 메뉴
  void _showOwnerMenu() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.edit, color: AppColors.primary),
              title: const Text('수정'),
              subtitle: const Text('제목·장소명 변경'),
              onTap: () {
                Navigator.pop(sheetCtx); // 시트 닫기
                _showEditDialog();
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: AppColors.error),
              title: const Text('삭제', style: TextStyle(color: AppColors.error)),
              subtitle: const Text('이 기록을 영구 삭제합니다'),
              onTap: () {
                Navigator.pop(sheetCtx); // 시트 닫기
                _confirmDelete();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// 제목·장소 수정 다이얼로그
  Future<void> _showEditDialog() async {
    final titleCtrl = TextEditingController(text: _title);
    final placeCtrl = TextEditingController(text: _placeName);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(children: [
          Icon(Icons.edit, color: AppColors.primary, size: 20),
          SizedBox(width: 8),
          Text('기록 수정', style: TextStyle(fontSize: 16)),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleCtrl,
              decoration: const InputDecoration(
                labelText: '제목 *',
                border: OutlineInputBorder(),
              ),
              autofocus: true,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: placeCtrl,
              decoration: const InputDecoration(
                labelText: '장소명 *',
                border: OutlineInputBorder(),
              ),
              textInputAction: TextInputAction.done,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            child: const Text('저장'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) {
      titleCtrl.dispose();
      placeCtrl.dispose();
      return;
    }

    final newTitle = titleCtrl.text.trim();
    final newPlace = placeCtrl.text.trim();
    titleCtrl.dispose();
    placeCtrl.dispose();

    if (newTitle.isEmpty || newPlace.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('제목과 장소명을 입력해 주세요')),
        );
      }
      return;
    }

    try {
      await FirestoreService.updateVlog(
        id: widget.vlog.id,
        title: newTitle,
        placeName: newPlace,
      );
      if (mounted) {
        setState(() {
          _title    = newTitle;
          _placeName = newPlace;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ 수정됐습니다'),
            backgroundColor: AppColors.secondary,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('수정 실패: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  /// 삭제 확인 후 Firestore에서 제거
  Future<void> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(children: [
          Icon(Icons.warning_amber, color: AppColors.error, size: 22),
          SizedBox(width: 8),
          Text('삭제 확인', style: TextStyle(fontSize: 16)),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '"$_title"',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            const Text('이 기록을 영구 삭제합니다.\n삭제 후 복구할 수 없습니다.'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            child: const Text('삭제'),
          ),
        ],
      ),
    );

    if (ok != true || !mounted) return;

    try {
      await FirestoreService.deleteVlog(widget.vlog.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🗑️ 삭제됐습니다'),
            duration: Duration(seconds: 2),
          ),
        );
        Navigator.pop(context); // 플레이어 화면 닫기
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('삭제 실패: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  // ─── 생명주기 ─────────────────────────────────────────────────────────────

  @override
  void dispose() {
    _videoController?.removeListener(_onVideoTick);
    _videoController?.dispose();
    _mapController?.dispose();
    // 시스템 방향 제한 해제 (기기 자동회전 설정 복원)
    SystemChrome.setPreferredOrientations([]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  // ─── 포맷 헬퍼 ────────────────────────────────────────────────────────────

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  // ─── 빌드 ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // 전체화면 (영상 전용)
    if (_isFullscreen) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: _buildMediaSection(fullscreen: true),
      );
    }

    final mediaWidget = _buildMediaSection();
    final mapWidget   = _buildMapSection();

    return Scaffold(
      backgroundColor: Colors.black,
      body: Column(
        children: [
          _buildAppBar(),
          Expanded(
            child: _isHorizontalSplit
                // 좌우 분할
                ? Row(children: [
                    Expanded(child: mediaWidget),
                    Expanded(child: mapWidget),
                  ])
                // 상하 분할 (기본)
                : Column(children: [
                    SizedBox(
                      height: MediaQuery.of(context).size.height * 0.42,
                      child: mediaWidget,
                    ),
                    Expanded(child: mapWidget),
                  ]),
          ),
          _buildInfoBar(),
        ],
      ),
    );
  }

  // ── 앱바 ──────────────────────────────────────────────────────────────────
  Widget _buildAppBar() {
    return Container(
      color: Colors.black,
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
            Expanded(
              child: Text(
                _title,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // 레이아웃 전환 버튼 (상하 ↔ 좌우)
            IconButton(
              icon: Icon(
                _isHorizontalSplit
                    ? Icons.horizontal_split   // 클릭하면 상하로 전환
                    : Icons.vertical_split,    // 클릭하면 좌우로 전환
                color: Colors.white,
              ),
              tooltip: _isHorizontalSplit ? '상하 분할로 전환' : '좌우 분할로 전환',
              onPressed: () =>
                  setState(() => _isHorizontalSplit = !_isHorizontalSplit),
            ),
            IconButton(
              icon: const Icon(Icons.share, color: Colors.white),
              onPressed: () {},
            ),
            // 수정·삭제 메뉴 — 등록자에게만 표시
            if (_isAuthor)
              IconButton(
                icon: const Icon(Icons.more_vert, color: Colors.white),
                onPressed: _showOwnerMenu,
              ),
          ],
        ),
      ),
    );
  }

  // ── 미디어 섹션 (사진 or 영상 자동 분기) ─────────────────────────────────
  Widget _buildMediaSection({bool fullscreen = false}) {
    if (widget.vlog.isPhoto) return _buildPhotoSection();
    return _buildVideoSection(fullscreen: fullscreen);
  }

  /// 사진 vlog 표시 (썸네일 URL = 사진 원본)
  Widget _buildPhotoSection() {
    return Container(
      color: Colors.black,
      width: double.infinity,
      height: double.infinity,
      child: Image.network(
        widget.vlog.thumbnailUrl!,
        fit: BoxFit.contain,
        loadingBuilder: (_, child, progress) => progress == null
            ? child
            : Center(
                child: CircularProgressIndicator(
                  value: progress.expectedTotalBytes != null
                      ? progress.cumulativeBytesLoaded /
                          progress.expectedTotalBytes!
                      : null,
                  color: AppColors.primary,
                ),
              ),
        errorBuilder: (context2, e, stack) => Container(
          color: const Color(0xFF1A1A2E),
          child: const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.broken_image, color: Colors.white38, size: 64),
                SizedBox(height: 8),
                Text('사진을 불러올 수 없습니다',
                    style: TextStyle(color: Colors.white38, fontSize: 13)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── 영상 섹션 ─────────────────────────────────────────────────────────────
  Widget _buildVideoSection({bool fullscreen = false}) {
    return GestureDetector(
      onTap: _onTapVideo,
      child: Container(
        color: Colors.black,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // 비디오 또는 placeholder
            if (_videoReady && _videoController != null)
              AspectRatio(
                aspectRatio: _videoController!.value.aspectRatio,
                child: VideoPlayer(_videoController!),
              )
            else
              _buildVideoPlaceholder(),

            // 버퍼링 스피너 (재생 중 데이터 로딩 시)
            if (_isBuffering)
              Container(
                color: Colors.black38,
                child: const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(
                          color: Colors.white70, strokeWidth: 2.5),
                      SizedBox(height: 8),
                      Text('버퍼링 중...',
                          style: TextStyle(
                              color: Colors.white60, fontSize: 12)),
                    ],
                  ),
                ),
              ),

            // 재생 컨트롤 오버레이
            if (_showControls) _buildVideoControls(fullscreen: fullscreen),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoPlaceholder() {
    return Container(
      color: const Color(0xFF1A1A2E),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.primary.withAlpha(51),
              border:
                  Border.all(color: AppColors.primary.withAlpha(102), width: 2),
            ),
            child: const Icon(Icons.videocam, color: Colors.white54, size: 36),
          ),
          const SizedBox(height: 12),
          Text(
            widget.vlog.hasVideo ? '영상 로딩 중...' : '영상 없음 (더미 데이터)',
            style:
                const TextStyle(color: Colors.white38, fontSize: 13),
          ),
          if (widget.vlog.hasGpsTrack) ...[
            const SizedBox(height: 6),
            Text(
              'GPS ${widget.vlog.gpsTrack.length}포인트 트랙 로드됨',
              style: TextStyle(
                  color: AppColors.secondary.withAlpha(179), fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildVideoControls({bool fullscreen = false}) {
    final ctrl = _videoController;
    final isPlaying = ctrl?.value.isPlaying ?? false;
    final position = ctrl?.value.position ?? Duration.zero;
    final duration = ctrl?.value.duration ?? Duration.zero;
    final progress =
        duration.inMilliseconds > 0
            ? position.inMilliseconds / duration.inMilliseconds
            : 0.0;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            Colors.black.withAlpha(179),
          ],
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          // 진행 바
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16),
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                thumbShape:
                    const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape:
                    const RoundSliderOverlayShape(overlayRadius: 12),
                trackHeight: 3,
              ),
              child: Slider(
                value: progress.clamp(0.0, 1.0),
                onChanged: _seekTo,
                activeColor: AppColors.primary,
                inactiveColor: Colors.white30,
              ),
            ),
          ),

          // 시간 + 컨트롤 버튼
          Padding(
            padding:
                const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                Text(
                  _formatDuration(position),
                  style: const TextStyle(
                      color: Colors.white, fontSize: 12),
                ),
                const Spacer(),
                // -10초
                IconButton(
                  icon: const Icon(Icons.replay_10,
                      color: Colors.white, size: 28),
                  onPressed: _rewind10,
                  padding: EdgeInsets.zero,
                ),
                const SizedBox(width: 8),
                // 재생/일시정지
                GestureDetector(
                  onTap: _togglePlay,
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withAlpha(51),
                    ),
                    child: Icon(
                      isPlaying ? Icons.pause : Icons.play_arrow,
                      color: Colors.white,
                      size: 32,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // +10초
                IconButton(
                  icon: const Icon(Icons.forward_10,
                      color: Colors.white, size: 28),
                  onPressed: _forward10,
                  padding: EdgeInsets.zero,
                ),
                const Spacer(),
                Text(
                  _formatDuration(duration),
                  style: const TextStyle(
                      color: Colors.white70, fontSize: 12),
                ),
                const SizedBox(width: 8),
                // 전체화면
                IconButton(
                  icon: Icon(
                    fullscreen
                        ? Icons.fullscreen_exit
                        : Icons.fullscreen,
                    color: Colors.white,
                    size: 22,
                  ),
                  onPressed: _toggleFullscreen,
                  padding: EdgeInsets.zero,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── 지도 섹션 ─────────────────────────────────────────────────────────────
  Widget _buildMapSection() {
    final track = widget.vlog.gpsTrack;
    final center = track.isNotEmpty
        ? GpsInterpolator.centerOf(track)!
        : LatLng(widget.vlog.lat, widget.vlog.lng);

    return Stack(
      children: [
        GoogleMap(
          initialCameraPosition: CameraPosition(
            target: center,
            zoom: 15,
          ),
          polylines: _polylines,
          markers: _markers,
          mapType: _mapType,
          myLocationEnabled: false,
          zoomControlsEnabled: false,
          myLocationButtonEnabled: false,
          compassEnabled: false,
          mapToolbarEnabled: false,
          onCameraMove: (pos) => _mapCenter = pos.target,
          onMapCreated: (ctrl) {
            _mapController = ctrl;
            _mapCenter = center;
            // 트랙 전체가 보이도록 카메라 조정
            if (track.length > 1) {
              final bounds = GpsInterpolator.boundsOf(track)!;
              Future.delayed(const Duration(milliseconds: 300), () {
                _mapController?.animateCamera(
                  CameraUpdate.newLatLngBounds(
                    LatLngBounds(
                      southwest: LatLng(bounds.south, bounds.west),
                      northeast: LatLng(bounds.north, bounds.east),
                    ),
                    60, // padding
                  ),
                );
              });
            }
          },
        ),

        // 지도 레전드
        Positioned(
          top: 8,
          right: 8,
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(230),
              borderRadius: BorderRadius.circular(8),
              boxShadow: AppShadow.card,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _LegendItem(
                    color: Colors.green, label: '출발'),
                const SizedBox(height: 3),
                _LegendItem(
                    color: AppColors.primary, label: '경로'),
                const SizedBox(height: 3),
                _LegendItem(
                    color: Colors.blue, label: '현재'),
                const SizedBox(height: 3),
                _LegendItem(
                    color: Colors.red, label: '도착'),
              ],
            ),
          ),
        ),

        // 지도 레이어 + 스트리트뷰 컨트롤
        Positioned(
          right: 8,
          bottom: 8,
          child: MapControls(
            mapType: _mapType,
            onMapTypeChanged: (t) => setState(() => _mapType = t),
            center: _mapCenter,
          ),
        ),

        // GPS 포인트 수 뱃지
        if (track.isNotEmpty)
          Positioned(
            bottom: 8,
            left: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.gps_fixed,
                      size: 11, color: AppColors.secondary),
                  const SizedBox(width: 4),
                  Text(
                    'GPS ${track.length}포인트',
                    style: const TextStyle(
                        color: Colors.white, fontSize: 11),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  // ── 하단 정보 바 ──────────────────────────────────────────────────────────
  Widget _buildInfoBar() {
    // 시스템 네비게이션 바 높이만큼 하단 패딩 추가 (홈 제스처 바 포함)
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return Container(
      color: AppColors.surface,
      padding: EdgeInsets.fromLTRB(16, 10, 16, 16 + bottomInset),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Icon(Icons.location_on,
                        size: 13, color: AppColors.primary),
                    const SizedBox(width: 3),
                    Text(
                      _placeName,
                      style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  widget.vlog.authorName,
                  style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textDisabled),
                ),
              ],
            ),
          ),
          Row(
            children: [
              // ── 좋아요 버튼 (탭 가능)
              GestureDetector(
                onTap: _toggleLike,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  transitionBuilder: (child, anim) =>
                      ScaleTransition(scale: anim, child: child),
                  child: Icon(
                    _isLiked ? Icons.favorite : Icons.favorite_border,
                    key: ValueKey(_isLiked),
                    size: 20,
                    color: AppColors.error,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Text(
                '$_likeCount',
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary),
              ),
              const SizedBox(width: 14),
              const Icon(Icons.remove_red_eye,
                  size: 14, color: AppColors.textDisabled),
              const SizedBox(width: 3),
              Text(
                '${widget.vlog.viewCount}',
                style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── 서브 위젯 ────────────────────────────────────────────────────────────────

class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendItem({required this.color, required this.label});

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
