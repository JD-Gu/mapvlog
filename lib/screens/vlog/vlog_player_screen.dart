import 'dart:async';
import 'dart:ui' as ui;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart'
    show
        PointerDeviceKind,
        PointerScrollEvent,
        EagerGestureRecognizer,
        OneSequenceGestureRecognizer;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geocoding/geocoding.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:image/image.dart' as img;
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../../models/vlog.dart';
import '../../services/firebase_storage_service.dart';
import '../../services/firestore_service.dart';
import '../../services/gps_interpolator.dart';
import '../../utils/constants.dart';
import '../../utils/marker_colors.dart';
import '../../utils/marker_emojis.dart';
import '../../utils/location_format.dart';
import '../../widgets/comments_sheet.dart';
import '../../widgets/visibility_picker.dart';
import '../../widgets/emoji_picker_row.dart';
import '../../widgets/likers_sheet.dart';
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
  late String? _currentThumbnailUrl; // 회전 저장 후 갱신 (단일 사진 하위 호환)

  // ─── 멀티 사진 캐러셀 ─────────────────────────────────────────────────────
  late List<String> _currentPhotoUrls; // 현재 표시 중인 사진 URL 목록
  int _photoPageIndex = 0;
  PageController? _photoPageController;

  // ─── 좋아요 ────────────────────────────────────────────────────────────────
  bool _isLiked = false;
  bool _isSaved = false;
  bool _saveBusy = false;
  bool _isLikeLoading = false; // 중복 탭 방지
  late int _likeCount;

  // ─── 화면 방향 / 레이아웃 ─────────────────────────────────────────────────
  bool _isFullscreen = false;
  /// true = 좌(미디어) | 우(지도)  /  false = 상(미디어) | 하(지도)
  bool _isHorizontalSplit = false;
  /// true = 미디어 패널만 전체 표시 (지도 숨김)
  bool _mediaExpanded = false;
  /// true = 지도 패널만 전체 표시 (미디어 숨김)
  bool _mapExpanded = false;

  /// 현재 로그인 사용자가 이 vlog의 등록자인지 여부
  bool get _isAuthor =>
      FirebaseAuth.instance.currentUser?.uid == widget.vlog.authorId;

  @override
  void initState() {
    super.initState();
    _title = widget.vlog.title;
    _placeName = widget.vlog.placeName;
    _currentThumbnailUrl = widget.vlog.thumbnailUrl;
    _likeCount = widget.vlog.likeCount;
    _currentPhotoUrls = List.from(widget.vlog.displayPhotoUrls);
    if (_currentPhotoUrls.length > 1) {
      _photoPageController = PageController();
    }
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
    final saved = await FirestoreService.isSaved(widget.vlog.id, uid);
    if (mounted) {
      setState(() {
        _isLiked = liked;
        _isSaved = saved;
      });
    }
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

  /// 즐겨찾기 토글 (낙관적 UI 업데이트 + 중복 탭 방지)
  Future<void> _toggleSave() async {
    if (_saveBusy) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('저장은 로그인 후 이용할 수 있어요')),
      );
      return;
    }
    HapticFeedback.lightImpact();
    final prev = _isSaved;
    setState(() {
      _saveBusy = true;
      _isSaved = !prev;
    });
    try {
      await FirestoreService.toggleSave(widget.vlog.id, uid);
      if (mounted && _isSaved) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('🔖 저장됨 — 프로필에서 확인'),
          backgroundColor: AppColors.secondary,
          duration: Duration(seconds: 2),
        ));
      }
    } catch (_) {
      if (mounted) setState(() => _isSaved = prev); // rollback
    } finally {
      if (mounted) setState(() => _saveBusy = false);
    }
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
    HapticFeedback.selectionClick();
    setState(() {
      _mediaExpanded = !_mediaExpanded;
      if (_mediaExpanded) _mapExpanded = false;
    });
  }

  /// 사진/영상 탭 시 미디어 전체화면 토글 (앱바·하단 정보 유지)
  void _toggleMediaExpand() {
    HapticFeedback.selectionClick();
    setState(() {
      _mediaExpanded = !_mediaExpanded;
      if (_mediaExpanded) _mapExpanded = false;
    });
  }

  /// 마우스 휠로 사진 페이지 이동 (디바운스 적용)
  DateTime? _lastWheelTime;
  void _handleWheelScroll(PointerScrollEvent event) {
    if (_photoPageController == null) return;
    // 휠 이벤트는 매우 빠르게 발생 → 350ms 디바운스로 한 페이지씩 이동
    final now = DateTime.now();
    if (_lastWheelTime != null &&
        now.difference(_lastWheelTime!).inMilliseconds < 350) {
      return;
    }
    _lastWheelTime = now;

    final delta = event.scrollDelta.dy + event.scrollDelta.dx;
    final last = _currentPhotoUrls.length - 1;
    if (delta > 0 && _photoPageIndex < last) {
      _photoPageController!.nextPage(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOut,
      );
    } else if (delta < 0 && _photoPageIndex > 0) {
      _photoPageController!.previousPage(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOut,
      );
    }
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

  // ─── 공유 ─────────────────────────────────────────────────────────────────

  /// 공유 링크: https://pinflick.web.app/#/vlog/{id}
  ///   - 웹  : 클립보드에 URL 복사 + 스낵바 안내
  ///   - 앱  : 네이티브 공유 시트 (share_plus)
  Future<void> _shareVlog() async {
    const baseUrl = 'https://pinflick.web.app';
    final url  = '$baseUrl/#/vlog/${widget.vlog.id}';
    final text = '📍 $_title\n🗺️ $_placeName\n\nPinFlick에서 확인하기 👇\n$url';

    if (kIsWeb) {
      await Clipboard.setData(ClipboardData(text: url));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.link, color: Colors.white, size: 16),
                SizedBox(width: 8),
                Text('링크가 복사됐습니다'),
              ],
            ),
            backgroundColor: AppColors.secondary,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } else {
      await Share.share(text, subject: _title);
    }
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
              leading: const Icon(Icons.edit, color: Color(0xFFF57C00)),
              title: const Text('수정'),
              subtitle: const Text('제목·장소명·마커색상 변경'),
              onTap: () {
                Navigator.pop(sheetCtx);
                _showEditDialog();
              },
            ),
            // 공개 범위 변경
            ListTile(
              leading: Icon(
                widget.vlog.visibility == VlogVisibility.private
                    ? Icons.lock_outline
                    : widget.vlog.visibility == VlogVisibility.groups
                        ? Icons.group_outlined
                        : Icons.public,
                color: AppColors.primary,
              ),
              title: const Text('공개 범위 변경'),
              subtitle: Text(
                  '${widget.vlog.visibility.emoji} ${widget.vlog.visibility.label}'),
              onTap: () {
                Navigator.pop(sheetCtx);
                _showVisibilityEdit();
              },
            ),
            // 사진 vlog 전용 회전 메뉴
            if (widget.vlog.isPhoto) ...[
              ListTile(
                leading: const Icon(Icons.rotate_left,
                    color: AppColors.primary),
                title: const Text('왼쪽으로 90° 회전'),
                subtitle: const Text('사진을 반시계 방향으로 회전 후 저장'),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  _rotateAndSave(-90);
                },
              ),
              ListTile(
                leading: const Icon(Icons.rotate_right,
                    color: AppColors.primary),
                title: const Text('오른쪽으로 90° 회전'),
                subtitle: const Text('사진을 시계 방향으로 회전 후 저장'),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  _rotateAndSave(90);
                },
              ),
            ],
            ListTile(
              leading: const Icon(Icons.delete_outline, color: AppColors.error),
              title: const Text('삭제', style: TextStyle(color: AppColors.error)),
              subtitle: const Text('이 기록을 영구 삭제합니다'),
              onTap: () {
                Navigator.pop(sheetCtx);
                _confirmDelete();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// 공개 범위 변경 시트
  Future<void> _showVisibilityEdit() async {
    HapticFeedback.selectionClick();
    final initial = VisibilitySelection(
      visibility: widget.vlog.visibility,
      groupIds: widget.vlog.visibleGroupIds,
      visibleUids: widget.vlog.visibleUids,
    );
    // VisibilityPickerChip 의 시트를 재사용하기 위해 임시 Chip 을 렌더하지 않고
    // 직접 sheet 를 띄운다 — 결과만 받아서 service 호출
    final picked = await showModalBottomSheet<VisibilitySelection>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => VisibilityPickerSheet(initial: initial),
    );
    if (picked == null || !mounted) return;
    try {
      await FirestoreService.updateVisibility(
        vlogId: widget.vlog.id,
        visibility: picked.visibility,
        visibleGroupIds: picked.groupIds,
        visibleUids: picked.visibleUids,
      );
      if (!mounted) return;
      HapticFeedback.lightImpact();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            '${picked.visibility.emoji} ${picked.visibility.label} (으)로 변경됐어요'),
        backgroundColor: AppColors.secondary,
        duration: const Duration(seconds: 2),
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('변경 실패: $e'),
        backgroundColor: AppColors.error,
      ));
    }
  }

  /// 제목·장소·마커색상 수정 다이얼로그
  Future<void> _showEditDialog() async {
    final titleCtrl = TextEditingController(text: _title);
    final placeCtrl = TextEditingController(text: _placeName);
    String selectedEmoji = widget.vlog.markerEmoji ?? MarkerEmojis.defaultEmoji;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: const Row(children: [
            Icon(Icons.edit, color: Color(0xFFF57C00), size: 20),
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
              const SizedBox(height: 16),
              EmojiPickerRow(
                selected: selectedEmoji,
                onPick: (e) => setDlg(() => selectedEmoji = e),
                maxHeight: 200,
                suggestionText: '${titleCtrl.text} ${placeCtrl.text}',
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
        markerColor: MarkerEmojis.colorOf(selectedEmoji).toARGB32(),
        markerEmoji: selectedEmoji,
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

  // ─── 사진 회전 저장 ────────────────────────────────────────────────────────

  /// [degrees] : 90(오른쪽) 또는 -90(왼쪽)
  /// 1) Firebase Storage에서 원본 다운로드
  /// 2) image 패키지로 회전
  /// 3) 새 경로로 재업로드
  /// 4) Firestore thumbnailUrl 갱신
  /// 현재 보고 있는 사진을 회전 저장
  Future<void> _rotateAndSave(int degrees) async {
    // 멀티 사진: 현재 페이지 URL / 단일 사진: thumbnailUrl
    final url = _currentPhotoUrls.isNotEmpty
        ? _currentPhotoUrls[_photoPageIndex]
        : (_currentThumbnailUrl ?? widget.vlog.thumbnailUrl);
    if (url == null || url.isEmpty) return;

    // 진행 다이얼로그 표시
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _RotationLoadingDialog(),
    );
    try {
      // ── 1. 원본 bytes 다운로드 ─────────────────────────────────────────
      Uint8List? original;
      try {
        original = await FirebaseStorage.instance
            .refFromURL(url)
            .getData(20 * 1024 * 1024); // 최대 20MB
      } catch (_) {
        // Firebase Storage URL 파싱 실패 시 HTTP fallback
        // (CDN URL 등 예외 처리)
        rethrow;
      }
      if (original == null) throw Exception('이미지 데이터를 읽을 수 없습니다');

      // ── 2. 이미지 회전 ─────────────────────────────────────────────────
      final decoded = await compute(_decodeAndRotate,
          _RotateArgs(bytes: original, degrees: degrees));
      if (decoded == null) throw Exception('이미지 디코딩 실패');

      // ── 3. Firebase Storage 재업로드 ─────────────────────────────────
      final uid = FirebaseAuth.instance.currentUser?.uid ?? 'unknown';
      final newPath =
          'photos/$uid/${DateTime.now().millisecondsSinceEpoch}_rot.jpg';
      final newUrl = await FirebaseStorageService.uploadBytes(
        bytes: decoded,
        path: newPath,
        contentType: 'image/jpeg',
      );

      // ── 4. Firestore 갱신 ─────────────────────────────────────────────
      await FirestoreService.updateThumbnail(
          id: widget.vlog.id, thumbnailUrl: newUrl);

      if (!mounted) return;
      setState(() {
        // 멀티 사진 목록 갱신
        if (_currentPhotoUrls.isNotEmpty) {
          _currentPhotoUrls[_photoPageIndex] = newUrl;
        }
        // 단일 사진 / 첫 번째 사진이면 thumbnailUrl도 갱신
        if (_photoPageIndex == 0) _currentThumbnailUrl = newUrl;
      });
      Navigator.pop(context); // 다이얼로그 닫기
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(children: [
            Icon(Icons.check_circle, color: Colors.white, size: 16),
            SizedBox(width: 8),
            Text('회전 저장 완료'),
          ]),
          backgroundColor: AppColors.secondary,
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // 다이얼로그 닫기
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('회전 실패: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  /// 현재 미디어 다운로드
  /// - 사진: Firebase Storage → 임시파일 → share_plus (갤러리/다운로드 저장)
  /// - 영상: 외부 앱(브라우저/다운로더)으로 전달
  /// - 웹: 새 탭으로 열기
  Future<void> _downloadMedia() async {
    final url = widget.vlog.isPhoto
        ? (_currentPhotoUrls.isNotEmpty
            ? _currentPhotoUrls[_photoPageIndex]
            : (_currentThumbnailUrl ?? widget.vlog.thumbnailUrl ?? ''))
        : (widget.vlog.videoUrl ?? '');
    if (url.isEmpty) return;

    // ── 웹: 새 탭으로 열기
    if (kIsWeb) {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
      return;
    }

    // ── 영상: 외부 앱(시스템 다운로더)에 위임
    if (!widget.vlog.isPhoto) {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
      return;
    }

    // ── 사진: Firebase Storage bytes → 임시파일 → Share
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final controller = messenger.showSnackBar(
      const SnackBar(
        content: Row(children: [
          SizedBox(
            width: 16, height: 16,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: Colors.white),
          ),
          SizedBox(width: 12),
          Text('다운로드 중...'),
        ]),
        duration: Duration(minutes: 2),
      ),
    );

    try {
      final bytes = await FirebaseStorage.instance
          .refFromURL(url)
          .getData(30 * 1024 * 1024); // 최대 30MB
      if (bytes == null) throw Exception('데이터를 읽을 수 없습니다');

      final dir = await getTemporaryDirectory();
      final fileName =
          'pinflick_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(bytes);

      controller.close();
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'image/jpeg')],
        text: _title,
      );
    } catch (e) {
      controller.close();
      if (mounted) {
        messenger.showSnackBar(SnackBar(
          content: Text('다운로드 실패: $e'),
          backgroundColor: AppColors.error,
        ));
      }
    }
  }

  /// Isolate 에서 실행: 이미지 디코딩 + 회전 + JPEG 인코딩
  static Uint8List? _decodeAndRotate(_RotateArgs args) {
    final image = img.decodeImage(args.bytes);
    if (image == null) return null;
    final rotated = img.copyRotate(image, angle: args.degrees.toDouble());
    return Uint8List.fromList(img.encodeJpg(rotated, quality: 90));
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
    _photoPageController?.dispose();
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
    // 영상 가로 전체화면 (기존)
    if (_isFullscreen) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: _buildMediaSection(fullscreen: true),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Column(
        children: [
          _buildAppBar(),
          Expanded(child: _buildSplitContent()),
          _buildInfoBar(),
        ],
      ),
    );
  }

  /// 분할 / 미디어 전체 / 지도 전체 레이아웃 분기
  Widget _buildSplitContent() {
    // 미디어만 전체 표시 (지도 숨김)
    if (_mediaExpanded) return _buildMediaSection();
    // 지도만 전체 표시 (미디어 숨김)
    if (_mapExpanded)   return _buildMapSection();

    // 분할 레이아웃 (기존)
    final mediaWidget = _buildMediaSection();
    final mapWidget   = _buildMapSection();
    return _isHorizontalSplit
        ? Row(children: [
            Expanded(child: mediaWidget),
            Expanded(child: mapWidget),
          ])
        : Column(children: [
            SizedBox(
              height: MediaQuery.of(context).size.height * 0.42,
              child: mediaWidget,
            ),
            Expanded(child: mapWidget),
          ]);
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _title,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                  const SizedBox(height: 2),
                  // 정보 칩 한 줄: ♥ 좋아요 / 💬 댓글 / 👁 조회
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _InfoChip(
                          icon: Icons.favorite,
                          label: _fmtCount(_likeCount),
                          color: const Color(0xFFFF5252)),
                      const SizedBox(width: 6),
                      _InfoChip(
                          icon: Icons.chat_bubble_outline,
                          label: _fmtCount(widget.vlog.commentCount),
                          color: Colors.white70),
                      const SizedBox(width: 6),
                      _InfoChip(
                          icon: Icons.visibility_outlined,
                          label: _fmtCount(widget.vlog.viewCount),
                          color: Colors.white70),
                    ],
                  ),
                ],
              ),
            ),
            // 레이아웃 전환 버튼 (상하 ↔ 좌우) — 패널 전체화면 중에는 숨김
            if (!_mediaExpanded && !_mapExpanded)
              IconButton(
                icon: Icon(
                  _isHorizontalSplit
                      ? Icons.horizontal_split
                      : Icons.vertical_split,
                  color: Colors.white,
                ),
                tooltip: _isHorizontalSplit ? '상하 분할로 전환' : '좌우 분할로 전환',
                onPressed: () =>
                    setState(() => _isHorizontalSplit = !_isHorizontalSplit),
              ),
            // 다운로드·공유는 미디어 우측 TikTok 사이드바에 있음 (중복 제거)
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
    final content = widget.vlog.isPhoto
        ? _buildPhotoSection()
        : _buildVideoSection(fullscreen: fullscreen);

    // 가로 전체화면 모드에선 버튼 불필요
    if (fullscreen) return content;

    return Stack(
      children: [
        Positioned.fill(child: content),
        // TikTok 스타일 사이드 액션바 (우측 중앙)
        // 다운로드·공유 버튼이 여기 있어서 상단 앱바에서는 제거됨.
        Positioned(
          right: 8,
          top: 0,
          bottom: 0,
          child: _buildSideActions(),
        ),
      ],
    );
  }

  /// TikTok 스타일 우측 사이드 액션바
  Widget _buildSideActions() {
    return SafeArea(
      top: false,
      bottom: false,
      child: Align(
        alignment: Alignment.centerRight,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            // 좋아요 (탭 = 토글, 롱프레스 = 좋아요한 사람 목록)
            _TikTokActionButton(
              icon: _isLiked ? Icons.favorite : Icons.favorite_border,
              iconColor: _isLiked ? AppColors.error : Colors.white,
              label: _fmtCount(_likeCount),
              onTap: () {
                HapticFeedback.lightImpact();
                _toggleLike();
              },
              onLongPress: _likeCount > 0
                  ? () => LikersSheet.open(
                        context: context,
                        title: '좋아요 $_likeCount명',
                        stream: FirestoreService.watchVlogLikers(
                            widget.vlog.id),
                      )
                  : null,
              animateKey: ValueKey(_isLiked),
            ),
            const SizedBox(height: 14),
            // 댓글 (카운트 표시 + 시트 열기)
            _TikTokActionButton(
              icon: Icons.chat_bubble_outline_rounded,
              iconColor: Colors.white,
              label: _fmtCount(widget.vlog.commentCount),
              onTap: () {
                HapticFeedback.selectionClick();
                CommentsSheet.open(context, widget.vlog);
              },
            ),
            const SizedBox(height: 14),
            // 즐겨찾기 (북마크 — 본인만 보는 개인 컬렉션)
            _TikTokActionButton(
              icon: _isSaved ? Icons.bookmark : Icons.bookmark_border,
              iconColor: _isSaved ? const Color(0xFFFFC107) : Colors.white,
              label: _isSaved ? '저장됨' : '저장',
              onTap: _toggleSave,
              animateKey: ValueKey(_isSaved),
            ),
            const SizedBox(height: 14),
            // 조회수
            _TikTokActionButton(
              icon: Icons.visibility_outlined,
              iconColor: Colors.white,
              label: _fmtCount(widget.vlog.viewCount),
              onTap: () {},
              tappable: false,
            ),
            const SizedBox(height: 14),
            // 공유
            _TikTokActionButton(
              icon: Icons.send_rounded,
              iconColor: Colors.white,
              label: '공유',
              onTap: () {
                HapticFeedback.selectionClick();
                _shareVlog();
              },
            ),
            const SizedBox(height: 14),
            // 다운로드 (기기 저장 — 북마크 '저장'과 구분해 '받기')
            _TikTokActionButton(
              icon: Icons.download_rounded,
              iconColor: Colors.white,
              label: '받기',
              onTap: () {
                HapticFeedback.selectionClick();
                _downloadMedia();
              },
            ),
          ],
        ),
      ),
    );
  }

  static String _fmtCount(int n) {
    if (n < 1000) return '$n';
    if (n < 10000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '${(n / 1000).toStringAsFixed(0)}K';
  }

  /// 사진 vlog 표시 — 1장: 단일 뷰 / 복수: PageView 캐러셀
  Widget _buildPhotoSection() {
    if (_currentPhotoUrls.isEmpty) {
      return _buildSinglePhoto(_currentThumbnailUrl ?? '');
    }
    if (_currentPhotoUrls.length == 1) {
      return _buildSinglePhoto(_currentPhotoUrls[0]);
    }

    // 멀티 사진 캐러셀
    return Stack(
      children: [
        // 웹: 마우스 드래그 + 마우스 휠로 페이지 전환 가능
        Listener(
          onPointerSignal: (event) {
            if (event is PointerScrollEvent) _handleWheelScroll(event);
          },
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(
              dragDevices: {
                PointerDeviceKind.touch,
                PointerDeviceKind.mouse,
              },
            ),
            child: PageView.builder(
              controller: _photoPageController,
              itemCount: _currentPhotoUrls.length,
              onPageChanged: (i) => setState(() => _photoPageIndex = i),
              itemBuilder: (_, i) => _buildSinglePhoto(_currentPhotoUrls[i]),
            ),
          ),
        ),
        // 하단 점 인디케이터
        Positioned(
          bottom: 12,
          left: 0, right: 0,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(_currentPhotoUrls.length, (i) {
              final active = i == _photoPageIndex;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: active ? 16 : 6,
                height: 6,
                decoration: BoxDecoration(
                  color: active ? Colors.white : Colors.white38,
                  borderRadius: BorderRadius.circular(3),
                ),
              );
            }),
          ),
        ),
        // 장수 뱃지 (우상단)
        Positioned(
          top: 10, right: 10,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '${_photoPageIndex + 1} / ${_currentPhotoUrls.length}',
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSinglePhoto(String url) {
    if (url.isEmpty) {
      return GestureDetector(
        onTap: _toggleMediaExpand,
        behavior: HitTestBehavior.opaque,
        child: Container(
          color: const Color(0xFF1A1A2E),
          child: const Center(
            child: Icon(Icons.photo, color: Colors.white38, size: 64),
          ),
        ),
      );
    }
    return Container(
      color: Colors.black,
      width: double.infinity,
      height: double.infinity,
      child: _ZoomablePhoto(
        url: url,
        onTap: _toggleMediaExpand,
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
    // 실제 이동 경로(2점 이상)가 있을 때만 레전드 노출.
    // 사진·체크인처럼 단일 위치면 핀만 깔끔하게 표시.
    final hasRoute = track.length > 1;
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
          // 스와이프(PageView)가 지도 제스처를 가로채지 않도록 —
          // 지도 위 드래그·핀치는 지도가 우선 처리.
          gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
            Factory<OneSequenceGestureRecognizer>(
                () => EagerGestureRecognizer()),
          },
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

        // 지도 전체화면 토글 버튼 (좌상단)
        Positioned(
          top: 8,
          left: 8,
          child: _buildExpandBtn(
            expanded: _mapExpanded,
            onTap: () => setState(() {
              _mapExpanded = !_mapExpanded;
              if (_mapExpanded) _mediaExpanded = false;
            }),
          ),
        ),

        // 지도 레전드 — 실제 경로(2점 이상) 있을 때만
        if (hasRoute)
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

  // ── 패널 전체화면 토글 버튼 ──────────────────────────────────────────────
  Widget _buildExpandBtn({
    required bool expanded,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(
          expanded ? Icons.fullscreen_exit : Icons.fullscreen,
          color: Colors.white,
          size: 20,
        ),
      ),
    );
  }

  String _playerRelativeTime(DateTime d) {
    final diff = DateTime.now().difference(d);
    if (diff.inSeconds < 60) return '방금';
    if (diff.inMinutes < 60) return '${diff.inMinutes}분 전';
    if (diff.inHours < 24) return '${diff.inHours}시간 전';
    if (diff.inDays < 7) return '${diff.inDays}일 전';
    return '${d.month}/${d.day}';
  }

  // ── 하단 정보 바 (위치 카드 계층화) ────────────────────────────────────
  Widget _buildInfoBar() {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final cs = Theme.of(context).colorScheme;
    final loc = combinedLocationLabel(_placeName, widget.vlog.address);
    final timeAgo = _playerRelativeTime(widget.vlog.createdAt);
    return Container(
      color: cs.surface,
      padding: EdgeInsets.fromLTRB(14, 10, 14, 12 + bottomInset),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // 작성자 (강조)
                Text(
                  widget.vlog.authorName,
                  style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.2,
                      color: cs.onSurface),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                // 장소(결합 주소) · 시간
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 1),
                      child: Icon(Icons.location_on,
                          size: 12, color: AppColors.primary),
                    ),
                    const SizedBox(width: 3),
                    Expanded(
                      child: Text(
                        loc.isEmpty ? timeAgo : '$loc · $timeAgo',
                        style: TextStyle(
                            fontSize: 11.5,
                            height: 1.3,
                            color: cs.onSurfaceVariant),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          // 통계 — 좋아요 / 댓글 / 조회 (간결한 그룹)
          GestureDetector(
            onTap: _toggleLike,
            child: _MiniStat(
              icon: _isLiked ? Icons.favorite : Icons.favorite_border,
              label: '$_likeCount',
              color: AppColors.error,
            ),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: () => CommentsSheet.open(context, widget.vlog),
            child: _MiniStat(
              icon: Icons.chat_bubble_outline_rounded,
              label: '${widget.vlog.commentCount}',
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 12),
          _MiniStat(
            icon: Icons.remove_red_eye_outlined,
            label: '${widget.vlog.viewCount}',
            color: cs.onSurfaceVariant,
          ),
        ],
      ),
    );
  }
}

// ─── 하단 통계 미니 칩 (아이콘 + 카운트) ─────────────────────────────
class _MiniStat extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _MiniStat({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 17, color: color),
        const SizedBox(width: 3),
        Text(label,
            style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: color)),
      ],
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
                fontSize: 10)),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 회전 저장 진행 다이얼로그
// ─────────────────────────────────────────────────────────────────────────────

class _RotationLoadingDialog extends StatelessWidget {
  const _RotationLoadingDialog();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 24, height: 24,
              child: CircularProgressIndicator(
                  strokeWidth: 2.5, color: AppColors.primary),
            ),
            SizedBox(width: 16),
            Text('회전 저장 중...', style: TextStyle(fontSize: 14)),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 회전 Isolate 인자
// ─────────────────────────────────────────────────────────────────────────────

class _RotateArgs {
  final Uint8List bytes;
  final int degrees;
  const _RotateArgs({required this.bytes, required this.degrees});
}

// ─────────────────────────────────────────────────────────────────────────────
// 마커 색상 피커 (공용)
// ─────────────────────────────────────────────────────────────────────────────

// ─────────────────────────────────────────────────────────────────────────────
// TikTok 스타일 액션 버튼 (원형 다크 배경 + 흰 아이콘 + 라벨)
// ─────────────────────────────────────────────────────────────────────────────

class _TikTokActionButton extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool tappable;
  final Key? animateKey;

  const _TikTokActionButton({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.onTap,
    this.onLongPress,
    this.tappable = true,
    this.animateKey,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: tappable ? onTap : null,
      onLongPress: onLongPress,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.black.withAlpha(110),
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withAlpha(40),
                width: 0.6,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(80),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: animateKey != null
                ? AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    transitionBuilder: (child, anim) =>
                        ScaleTransition(scale: anim, child: child),
                    child: Icon(
                      icon,
                      key: animateKey,
                      color: iconColor,
                      size: 22,
                    ),
                  )
                : Icon(icon, color: iconColor, size: 22),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              shadows: [
                Shadow(
                  color: Color(0xCC000000),
                  blurRadius: 4,
                  offset: Offset(0, 1),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 줌 가능한 사진 위젯
// ─────────────────────────────────────────────────────────────────────────────
//
// - 핀치 줌 (모바일) + Ctrl+휠 줌 (웹/데스크탑)
// - 더블탭으로 줌 인/줌 아웃 토글
// - 줌 상태가 1.0일 때만 외부 onTap (전체화면 토글) 동작
// - 줌됐을 때는 단일탭 = 줌 아웃, 드래그로 팬 가능
// ─────────────────────────────────────────────────────────────────────────────

class _ZoomablePhoto extends StatefulWidget {
  final String url;
  final VoidCallback? onTap;
  const _ZoomablePhoto({required this.url, this.onTap});

  @override
  State<_ZoomablePhoto> createState() => _ZoomablePhotoState();
}

class _ZoomablePhotoState extends State<_ZoomablePhoto>
    with SingleTickerProviderStateMixin {
  final TransformationController _transformCtrl = TransformationController();
  late final AnimationController _animCtrl;
  Animation<Matrix4>? _animation;
  TapDownDetails? _doubleTapDetails;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _animCtrl.addListener(() {
      if (_animation != null) _transformCtrl.value = _animation!.value;
    });
  }

  @override
  void dispose() {
    _transformCtrl.dispose();
    _animCtrl.dispose();
    super.dispose();
  }

  bool get _isZoomed =>
      _transformCtrl.value.getMaxScaleOnAxis() > 1.05;

  void _handleDoubleTap() {
    HapticFeedback.lightImpact();
    Matrix4 target;
    if (_isZoomed) {
      target = Matrix4.identity();
    } else {
      final pos = _doubleTapDetails?.localPosition;
      if (pos == null) {
        target = Matrix4.identity()..scaleByDouble(2.5, 2.5, 2.5, 1);
      } else {
        const scale = 2.5;
        target = Matrix4.identity()
          ..translateByDouble(
              -pos.dx * (scale - 1), -pos.dy * (scale - 1), 0, 1)
          ..scaleByDouble(scale, scale, scale, 1);
      }
    }
    _animation = Matrix4Tween(
      begin: _transformCtrl.value,
      end: target,
    ).animate(CurvedAnimation(
      parent: _animCtrl,
      curve: Curves.easeOutCubic,
    ));
    _animCtrl.forward(from: 0);
  }

  void _handleTap() {
    if (_isZoomed) {
      // 줌 상태면 단일탭 = 줌 아웃 (전체화면 토글 안 함)
      _animation = Matrix4Tween(
        begin: _transformCtrl.value,
        end: Matrix4.identity(),
      ).animate(CurvedAnimation(
        parent: _animCtrl,
        curve: Curves.easeOutCubic,
      ));
      _animCtrl.forward(from: 0);
    } else {
      widget.onTap?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _handleTap,
      onDoubleTapDown: (d) => _doubleTapDetails = d,
      onDoubleTap: _handleDoubleTap,
      child: InteractiveViewer(
        transformationController: _transformCtrl,
        minScale: 1.0,
        maxScale: 5.0,
        clipBehavior: Clip.none,
        panEnabled: true,
        scaleEnabled: true,
        child: Image.network(
          widget.url,
          fit: BoxFit.contain,
          width: double.infinity,
          height: double.infinity,
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
          errorBuilder: (ctx, err, st) => Container(
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
      ),
    );
  }
}

// ─── 정보 미니 칩 (좋아요/댓글/조회 카운트) ──────────────────────────────
class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _InfoChip(
      {required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 3),
          Text(label,
              style: TextStyle(
                  fontSize: 10.5, color: color, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
