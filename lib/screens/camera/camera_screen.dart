import 'dart:async';
import 'dart:convert';
import 'dart:io' show HttpClient;

import 'package:camera/camera.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:video_compress/video_compress.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:exif/exif.dart' show readExifFromBytes;
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:video_thumbnail/video_thumbnail.dart' as vt;

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:geocoding/geocoding.dart';
import 'package:flutter_dropzone/flutter_dropzone.dart';

import '../../models/gps_point.dart';
import '../../models/recording_session.dart';
import '../../services/firebase_storage_service.dart';
import '../../services/firestore_service.dart';
import '../../services/gps_tracking_service.dart';
import '../../utils/constants.dart';
import '../../utils/marker_emojis.dart';
import '../../widgets/emoji_picker_row.dart';
import '../../widgets/visibility_picker.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver {
  // ─── 상태 ─────────────────────────────────────────────────────────────────
  CameraController? _cameraController;
  List<CameraDescription> _cameras = [];
  int _cameraIndex = 0;

  bool _isModeVideo = false;       // false = 사진, true = 동영상
  bool _isRecording = false;
  bool _isCameraReady = false;
  bool _isProcessing = false;

  // ── 웹 드래그&드롭 ───────────────────────────────────────────────────────
  DropzoneViewController? _dropzoneCtrl;
  bool _isWebDragging = false;

  // ── 연속 촬영 누적 (사진 모드) ────────────────────────────────────────────
  final List<XFile> _capturedPhotos = [];
  final List<Uint8List?> _capturedPreviews = [];
  GpsPoint? _captureFirstGps;       // 첫 장 촬영 시 GPS 스냅샷

  GpsPoint? _currentGps;
  StreamSubscription<GpsPoint?>? _gpsSub;
  final GpsTrackingService _gpsService = GpsTrackingService();

  // 녹화 타이머
  int _recordSeconds = 0;
  Timer? _recordTimer;

  // ─── 초기화 ───────────────────────────────────────────────────────────────

  /// 전/후면 카메라 전환 중복 호출 방지
  bool _isFlipping = false;

  /// 물리적 디바이스 회전 (0/1/2/3 = 0°/90°/180°/270°)
  /// 가속도계로 감지하여 UI 위젯들의 아이콘/텍스트 회전에 사용
  int _quarterTurns = 0;
  StreamSubscription? _accelSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 카메라 화면은 세로 모드로 고정 — 버튼이 회전해도 자리에 그대로
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    // 가속도계로 물리적 회전 감지 → 아이콘/텍스트만 회전 (UI는 고정)
    _accelSub = accelerometerEventStream(
            samplingPeriod: SensorInterval.uiInterval)
        .listen(_onAccel);
    // Android는 동시 권한 요청 불가 → GPS 먼저, 카메라 나중
    _initPermissionsAndStart();
  }

  /// 가속도계 이벤트 → 4방향 회전 결정 (히스테리시스로 흔들림 방지)
  ///
  /// Android 가속도계 좌표계 (자연 세로 기준):
  ///   X: 화면 가로 (오른쪽이 +)
  ///   Y: 화면 세로 (위쪽이 +)
  ///   Z: 화면에서 사용자 쪽이 +
  ///
  /// 정상 세로로 들었을 때 중력 반작용은 +Y 방향 → `ay > 0`
  void _onAccel(AccelerometerEvent e) {
    if (!mounted) return;
    final ax = e.x;
    final ay = e.y;
    final flatness = e.z.abs();
    if (flatness > 8.5 && ax.abs() < 4 && ay.abs() < 4) return;

    int turns;
    if (ay.abs() > ax.abs()) {
      // 세로 방향: ay > 0 = 정상, ay < 0 = 상하반전
      turns = ay > 0 ? 0 : 2;
    } else {
      // 가로 방향: ax > 0 = 반시계 90°(landscapeLeft), ax < 0 = 시계 90°(landscapeRight)
      turns = ax > 0 ? 1 : 3;
    }
    if (turns != _quarterTurns) {
      setState(() => _quarterTurns = turns);
      _updateCameraOrientation();
    }
  }

  /// 가속도계 회전을 카메라 캡처 방향에 반영
  /// (세로 잠금 SystemChrome으로 막은 자동 감지를 수동으로 보완)
  Future<void> _updateCameraOrientation() async {
    if (_isRecording) return;
    final ctrl = _cameraController;
    if (ctrl == null || !ctrl.value.isInitialized) return;
    DeviceOrientation orient;
    switch (_quarterTurns) {
      case 1:
        orient = DeviceOrientation.landscapeLeft;
      case 2:
        orient = DeviceOrientation.portraitDown;
      case 3:
        orient = DeviceOrientation.landscapeRight;
      case 0:
      default:
        orient = DeviceOrientation.portraitUp;
    }
    try {
      await ctrl.lockCaptureOrientation(orient);
    } catch (_) {}
  }

  /// 촬영 모드 전환
  ///
  /// 사진·동영상 모두 가로/세로 자유 전환 허용.
  /// (회전 잠금 불필요 — EXIF 회전 교정 + CameraX 치수 감지로 처리)
  void _setVideoMode(bool isVideo) {
    setState(() {
      _isModeVideo = isVideo;
      // 동영상 모드로 전환 시 미저장 사진 초기화
      if (isVideo) {
        _capturedPhotos.clear();
        _capturedPreviews.clear();
        _captureFirstGps = null;
      }
    });
    // 카메라 재초기화 없음 — 모드 전환 시 재초기화하면 Android에서
    // 프리뷰가 까맣게 되거나 카메라 자원 충돌이 발생함
  }

  Future<void> _initPermissionsAndStart() async {
    await _initGps();                           // GPS 권한 먼저 처리
    if (!kIsWeb && mounted) await _initCamera(); // 완료 후 카메라 권한
  }

  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) return;
      await _startCamera(_cameras[_cameraIndex]);
    } catch (e) {
      debugPrint('카메라 초기화 실패: $e');
    }
  }

  Future<void> _startCamera(CameraDescription desc) async {
    // 1. 기존 컨트롤러 먼저 해제 (Android 카메라 락 회피)
    final old = _cameraController;
    _cameraController = null;
    if (mounted) setState(() => _isCameraReady = false);
    try {
      await old?.dispose();
    } catch (_) {}

    // 2. 새 컨트롤러 초기화
    const preset = ResolutionPreset.medium;
    final ctrl = CameraController(
      desc,
      preset,
      enableAudio: true,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );
    try {
      await ctrl.initialize();
      if (!mounted) {
        await ctrl.dispose();
        return;
      }
      setState(() {
        _cameraController = ctrl;
        _isCameraReady = true;
      });
      // 카메라 초기화 직후 현재 물리적 방향 적용
      await _updateCameraOrientation();
    } catch (e) {
      debugPrint('카메라 시작 실패: $e');
      try { await ctrl.dispose(); } catch (_) {}
    }
  }

  Future<void> _initGps() async {
    // 위치 권한 확인
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      if (mounted) {
        permission = await Geolocator.requestPermission();
      }
    }

    // GPS 스트림 구독
    _gpsSub = _gpsService.positionStream.listen((point) {
      if (mounted) setState(() => _currentGps = point);
    });

    // 최초 단발 위치 획득
    final pt = await GpsTrackingService.getCurrentPoint();
    if (mounted) setState(() => _currentGps = pt);
  }

  // ─── 생명주기 ─────────────────────────────────────────────────────────────

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) {
      final old = _cameraController;
      _cameraController = null;
      if (mounted) setState(() => _isCameraReady = false);
      old?.dispose();
    } else if (state == AppLifecycleState.resumed) {
      if (_cameras.isNotEmpty && _cameraController == null) {
        _startCamera(_cameras[_cameraIndex]);
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _accelSub?.cancel();
    _cameraController?.dispose();
    _gpsSub?.cancel();
    _gpsService.dispose();
    _recordTimer?.cancel();
    // 카메라 화면 나갈 때 회전 제한 해제
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    super.dispose();
  }

  // ─── 카메라 조작 ──────────────────────────────────────────────────────────

  Future<void> _flipCamera() async {
    if (_isFlipping || _cameras.length < 2 || _isRecording) return;
    _isFlipping = true;
    try {
      HapticFeedback.lightImpact();
      _cameraIndex = (_cameraIndex + 1) % _cameras.length;
      await _startCamera(_cameras[_cameraIndex]);
    } finally {
      _isFlipping = false;
    }
  }

  Future<void> _takePhoto() async {
    if (_isProcessing) return;
    if (_capturedPhotos.length >= _maxPhotos) {
      _showErrorSnack('최대 $_maxPhotos장까지 촬영할 수 있습니다');
      return;
    }
    setState(() => _isProcessing = true);

    try {
      // 첫 장 촬영 시 GPS 위치 기록
      if (_capturedPhotos.isEmpty) {
        _captureFirstGps = await GpsTrackingService.getCurrentPoint();
      }
      final file = await _cameraController!.takePicture();

      // 미리보기 바이트 로드 (실패해도 촬영은 유지)
      Uint8List? preview;
      try { preview = await file.readAsBytes(); } catch (_) {}

      if (!mounted) return;
      setState(() {
        _capturedPhotos.add(file);
        _capturedPreviews.add(preview);
      });
    } catch (e) {
      _showErrorSnack('사진 촬영 실패: $e');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  /// 촬영된 사진 목록을 업로드 다이얼로그로 넘김
  Future<void> _finishPhotoCapture() async {
    if (_capturedPhotos.isEmpty) return;
    final photos = List<XFile>.from(_capturedPhotos);
    final gps = _captureFirstGps;
    final track = gps != null ? [gps] : <GpsPoint>[];
    setState(() {
      _capturedPhotos.clear();
      _capturedPreviews.clear();
      _captureFirstGps = null;
    });
    if (!mounted) return;
    await _showPhotoUploadDialog(photos: photos, gps: gps, gpsTrack: track);
  }

  /// 모바일 갤러리에서 멀티 사진 선택
  Future<void> _pickMultiPhoto() async {
    if (_isProcessing) return;
    try {
      final picker = ImagePicker();
      final gps = await GpsTrackingService.getCurrentPoint();
      final photos = await picker.pickMultiImage(limit: 5);
      if (photos.isEmpty || !mounted) return;
      final track = gps != null ? [gps] : <GpsPoint>[];
      await _showPhotoUploadDialog(photos: photos, gps: gps, gpsTrack: track);
    } catch (e) {
      _showErrorSnack('갤러리에서 사진을 불러오지 못했습니다: $e');
    }
  }

  Future<void> _startRecording() async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);

    try {
      await _cameraController!.startVideoRecording();
      await _gpsService.start(mediaType: MediaType.video);

      _recordSeconds = 0;
      _recordTimer = Timer.periodic(
        const Duration(seconds: 1),
        (_) => setState(() => _recordSeconds++),
      );

      setState(() {
        _isRecording = true;
        _isProcessing = false;
      });
    } catch (e) {
      setState(() => _isProcessing = false);
      _showErrorSnack('녹화 시작 실패: $e');
    }
  }

  Future<void> _stopRecording() async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);

    try {
      _recordTimer?.cancel();
      final recordedSeconds = _recordSeconds; // 종료 전 캡처
      final file = await _cameraController!.stopVideoRecording();
      final session = await _gpsService.stop(mediaPath: file.path);

      setState(() {
        _isRecording = false;
        _isProcessing = false;
      });

      if (!mounted) return;
      await _showUploadDialog(
          xfile: file,
          isVideo: true,
          gps: session.firstPoint,
          gpsTrack: session.gpsTrack,
          durationSeconds: recordedSeconds);
    } catch (e) {
      setState(() {
        _isRecording = false;
        _isProcessing = false;
      });
      _showErrorSnack('녹화 종료 실패: $e');
    }
  }

  // ─── 미디어 선택 (웹) ────────────────────────────────────────────────────

  Future<void> _webPickMedia() async {
    final picker = ImagePicker();
    final gps = await GpsTrackingService.getCurrentPoint();
    final track = gps != null ? [gps] : <GpsPoint>[];

    if (_isModeVideo) {
      final xfile = await picker.pickVideo(source: ImageSource.gallery);
      if (xfile == null || !mounted) return;
      await _showUploadDialog(
          xfile: xfile, isVideo: true, gps: gps, gpsTrack: track);
    } else {
      // 사진: 최대 5장 멀티 선택
      final photos = await picker.pickMultiImage(limit: 5);
      if (photos.isEmpty || !mounted) return;
      await _showPhotoUploadDialog(photos: photos, gps: gps, gpsTrack: track);
    }
  }

  // ─── 웹 드롭 핸들러 ──────────────────────────────────────────────────────

  /// 웹에서 파일을 드래그&드롭했을 때 호출
  Future<void> _onWebFilesDropped(List<dynamic> files) async {
    setState(() => _isWebDragging = false);
    if (_isModeVideo || files.isEmpty) return;

    final gps = await GpsTrackingService.getCurrentPoint();
    final track = gps != null ? [gps] : <GpsPoint>[];

    final List<XFile> xfiles = [];
    for (final file in files.take(_maxPhotos)) {
      try {
        final bytes = await _dropzoneCtrl!.getFileData(file);
        final name  = await _dropzoneCtrl!.getFilename(file);
        xfiles.add(XFile.fromData(bytes, name: name, mimeType: 'image/jpeg'));
      } catch (e) {
        debugPrint('드롭 파일 읽기 실패: $e');
      }
    }

    if (xfiles.isEmpty || !mounted) return;
    await _showPhotoUploadDialog(photos: xfiles, gps: gps, gpsTrack: track);
  }

  // ─── 멀티 사진 업로드 ───────────────────────────────────────────────────────

  static const _maxPhotos = 5;

  /// 멀티 사진 등록 다이얼로그 (1~5장)
  Future<void> _showPhotoUploadDialog({
    required List<XFile> photos,
    required GpsPoint? gps,
    List<GpsPoint> gpsTrack = const [],
  }) async {
    // 다이얼로그 열기 전 미리보기 바이트 로드
    List<Uint8List?> previews = await Future.wait(
      photos.map((f) async {
        try { return await f.readAsBytes(); } catch (_) { return null; }
      }),
    );

    final titleCtrl = TextEditingController();
    final placeCtrl = TextEditingController();
    String selectedEmoji = MarkerEmojis.defaultEmoji;
    VisibilitySelection selectedVis = VisibilitySelection.public;
    List<XFile> currentPhotos = List.from(photos);
    List<Uint8List?> currentPreviews = List.from(previews);

    if (!mounted) return;
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setDlg) => AlertDialog(
            titlePadding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            title: Row(children: [
              const Icon(Icons.photo_library,
                  color: AppColors.primary, size: 20),
              const SizedBox(width: 8),
              Text(
                '사진 등록 (${currentPhotos.length}/$_maxPhotos)',
                style: const TextStyle(fontSize: 16),
              ),
            ]),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 12),
                    // ── 사진 미리보기 행 ──────────────────────────────
                    SizedBox(
                      height: 80,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: currentPhotos.length +
                            (currentPhotos.length < _maxPhotos ? 1 : 0),
                        itemBuilder: (_, i) {
                          // "+" 추가 버튼
                          if (i == currentPhotos.length) {
                            return GestureDetector(
                              onTap: () async {
                                final picker = ImagePicker();
                                final added = await picker.pickMultiImage(
                                    limit: _maxPhotos - currentPhotos.length);
                                if (added.isEmpty) return;
                                final newPrev = await Future.wait(
                                  added.map((f) async {
                                    try {
                                      return await f.readAsBytes();
                                    } catch (_) {
                                      return null;
                                    }
                                  }),
                                );
                                setDlg(() {
                                  currentPhotos.addAll(added);
                                  currentPreviews.addAll(newPrev);
                                });
                              },
                              child: Container(
                                width: 72, height: 72,
                                margin: const EdgeInsets.only(right: 6),
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: AppColors.primary
                                        .withValues(alpha: 0.5),
                                    width: 1.5,
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.add_photo_alternate,
                                        color: AppColors.primary, size: 22),
                                    SizedBox(height: 2),
                                    Text('추가',
                                        style: TextStyle(
                                            fontSize: 10,
                                            color: AppColors.primary)),
                                  ],
                                ),
                              ),
                            );
                          }
                          // 사진 썸네일
                          return Stack(
                            children: [
                              Container(
                                width: 72, height: 72,
                                margin: const EdgeInsets.only(right: 6),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(8),
                                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: currentPreviews[i] != null
                                    ? Image.memory(currentPreviews[i]!,
                                        fit: BoxFit.cover)
                                    : const Icon(Icons.photo,
                                        color: AppColors.textDisabled),
                              ),
                              // 장 번호 뱃지
                              Positioned(
                                bottom: 3, left: 3,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 5, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: Colors.black54,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text('${i + 1}',
                                      style: const TextStyle(
                                          color: Colors.white, fontSize: 9)),
                                ),
                              ),
                              // × 삭제 버튼 (2장 이상일 때만)
                              if (currentPhotos.length > 1)
                                Positioned(
                                  top: 0, right: 6,
                                  child: GestureDetector(
                                    onTap: () => setDlg(() {
                                      currentPhotos.removeAt(i);
                                      currentPreviews.removeAt(i);
                                    }),
                                    child: Container(
                                      width: 18, height: 18,
                                      decoration: const BoxDecoration(
                                        color: Colors.black54,
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(Icons.close,
                                          color: Colors.white, size: 11),
                                    ),
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: titleCtrl,
                      decoration: const InputDecoration(
                        labelText: '제목 *',
                        hintText: '예: 홍대 카페 투어',
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
                        hintText: '예: 홍대입구역',
                        border: OutlineInputBorder(),
                      ),
                      textInputAction: TextInputAction.done,
                    ),
                    if (gps != null) ...[
                      const SizedBox(height: 10),
                      Row(children: [
                        const Icon(Icons.location_on,
                            size: 14, color: AppColors.primary),
                        const SizedBox(width: 4),
                        Text(
                          '${gps.lat.toStringAsFixed(7)}, ${gps.lng.toStringAsFixed(7)}',
                          style: const TextStyle(
                              fontSize: 11, color: AppColors.textSecondary),
                        ),
                      ]),
                    ] else ...[
                      const SizedBox(height: 8),
                      const Text('GPS 미수신 (위치 없이 등록)',
                          style: TextStyle(
                              fontSize: 12, color: AppColors.textSecondary)),
                    ],
                    const SizedBox(height: 14),
                    EmojiPickerRow(
                      selected: selectedEmoji,
                      onPick: (e) => setDlg(() => selectedEmoji = e),
                      suggestionText:
                          '${titleCtrl.text} ${placeCtrl.text}',
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Text('공개 범위',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textSecondary)),
                        const SizedBox(width: 8),
                        VisibilityPickerChip(
                          selection: selectedVis,
                          onChanged: (v) =>
                              setDlg(() => selectedVis = v),
                          dense: true,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
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
                child: const Text('업로드'),
              ),
            ],
          ),
        ),
      );

      if (confirmed != true || !mounted) return;

      final title = titleCtrl.text.trim();
      final place = placeCtrl.text.trim();
      if (title.isEmpty || place.isEmpty) {
        _showErrorSnack('제목과 장소명을 입력해 주세요');
        return;
      }

      // 역지오코딩: Nominatim(OSM) → Google REST → 기기 Geocoder 순 fallback
      String? address;
      if (!kIsWeb && gps != null) {
        address = await _reverseGeocodeNominatim(gps.lat, gps.lng);
        address ??= await _reverseGeocodeRest(gps.lat, gps.lng);
        if (address == null) {
          try {
            final placemarks =
                await placemarkFromCoordinates(gps.lat, gps.lng);
            if (placemarks.isNotEmpty) {
              address = _buildAddress(placemarks.first);
            }
          } catch (e) {
            debugPrint('역지오코딩 fallback 실패 (무시): $e');
          }
        }
      }

      await _uploadMultiPhotos(
        photos: currentPhotos,
        gps: gps,
        gpsTrack: gpsTrack,
        title: title,
        placeName: place,
        markerColor: MarkerEmojis.colorOf(selectedEmoji).toARGB32(),
        markerEmoji: selectedEmoji,
        address: address,
        visibility: selectedVis,
      );
    } finally {
      titleCtrl.dispose();
      placeCtrl.dispose();
    }
  }

  /// 멀티 사진 순차 업로드 → Firestore 저장
  Future<void> _uploadMultiPhotos({
    required List<XFile> photos,
    required GpsPoint? gps,
    required List<GpsPoint> gpsTrack,
    required String title,
    required String placeName,
    required int markerColor,
    String? markerEmoji,
    String? address,
    VisibilitySelection visibility = VisibilitySelection.public,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    final userId = user?.uid ?? 'anonymous';
    final authorName = user?.displayName ?? user?.email ?? '익명';
    bool hasError = false;

    if (!mounted) return;
    final navigator = Navigator.of(context, rootNavigator: true);
    final progressNotifier = ValueNotifier<_UploadState>(
        const _UploadState(step: '사진 준비 중...'));

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _UploadProgressDialog(
          notifier: progressNotifier, isVideo: false),
    );

    final List<String> uploadedUrls = [];
    try {
      final id = DateTime.now().millisecondsSinceEpoch.toString();

      for (int i = 0; i < photos.length; i++) {
        final xfile = photos[i];
        final storagePath =
            FirebaseStorageService.photoPath(userId, '${id}_${i + 1}.jpg');

        progressNotifier.value = _UploadState(
          step: '사진 ${i + 1}/${photos.length} 처리 중...',
          progress: i / photos.length * 0.85,
        );

        Uint8List bytes;
        if (kIsWeb) {
          bytes = await xfile.readAsBytes();
        } else {
          bytes = await _correctPhotoRotation(xfile);
        }

        final url = await FirebaseStorageService.uploadBytes(
          bytes: bytes,
          path: storagePath,
          contentType: 'image/jpeg',
          onProgress: (sent, total) {
            final r = total > 0 ? sent / total : 0.0;
            progressNotifier.value = _UploadState(
              step: '사진 ${i + 1}/${photos.length} 업로드 중...',
              progress: (i + r) / photos.length * 0.9,
              detail: '${(sent / 1024).toStringAsFixed(0)} / '
                  '${(total / 1024).toStringAsFixed(0)} KB',
            );
          },
        );
        uploadedUrls.add(url);
      }

      progressNotifier.value =
          const _UploadState(step: '저장 중...', progress: 0.95);
      await FirestoreService.createVlog(
        authorId: userId,
        authorName: authorName,
        authorPhotoUrl: user?.photoURL,
        title: title,
        placeName: placeName,
        lat: gps?.lat ?? 37.5665,
        lng: gps?.lng ?? 126.9780,
        videoUrl: '',
        thumbnailUrl: uploadedUrls.first,
        gpsTrack: gpsTrack,
        markerColor: markerColor,
        markerEmoji: markerEmoji,
        address: address,
        photoUrls: uploadedUrls,
        visibility: visibility.visibility,
        visibleGroupIds: visibility.groupIds,
        visibleUids: visibility.visibleUids,
      );
    } catch (e) {
      hasError = true;
      debugPrint('멀티 사진 업로드 실패: $e');
    } finally {
      progressNotifier.dispose();
      navigator.pop();
    }

    if (!mounted) return;
    if (hasError) {
      _showErrorSnack('업로드 실패. 네트워크를 확인해 주세요.');
    } else {
      _showSuccessSnack(
          '📷 사진 ${uploadedUrls.length}장이 홈 피드에 등록됐습니다!');
    }
  }

  /// 제목·장소 입력 다이얼로그 → 업로드 실행 (영상 전용)
  Future<void> _showUploadDialog({
    required XFile xfile,
    required bool isVideo,
    required GpsPoint? gps,
    List<GpsPoint> gpsTrack = const [],
    int? durationSeconds,
  }) async {
    final titleCtrl = TextEditingController();
    final placeCtrl = TextEditingController();
    String selectedEmoji = MarkerEmojis.defaultEmoji;
    VisibilitySelection selectedVis = VisibilitySelection.public;

    try {
      final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
        title: Row(children: [
          Icon(isVideo ? Icons.videocam : Icons.photo_camera,
              color: AppColors.primary, size: 20),
          const SizedBox(width: 8),
          Text(isVideo ? '영상 등록' : '사진 등록',
              style: const TextStyle(fontSize: 16)),
        ]),
        content: SingleChildScrollView(
          child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleCtrl,
              decoration: const InputDecoration(
                labelText: '제목 *',
                hintText: '예: 홍대 카페 투어',
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
                hintText: '예: 홍대입구역',
                border: OutlineInputBorder(),
              ),
              textInputAction: TextInputAction.done,
            ),
            if (gps != null) ...[
              const SizedBox(height: 10),
              Row(children: [
                const Icon(Icons.location_on,
                    size: 14, color: AppColors.primary),
                const SizedBox(width: 4),
                Text(
                  '${gps.lat.toStringAsFixed(7)}, ${gps.lng.toStringAsFixed(7)}',
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.textSecondary),
                ),
              ]),
            ] else ...[
              const SizedBox(height: 8),
              const Text('GPS 미수신 (위치 없이 등록)',
                  style: TextStyle(
                      fontSize: 12, color: AppColors.textSecondary)),
            ],
            // ── 카테고리 이모지 선택 ────────────────────────────────
            const SizedBox(height: 14),
            EmojiPickerRow(
              selected: selectedEmoji,
              onPick: (e) => setDialogState(() => selectedEmoji = e),
              suggestionText: '${titleCtrl.text} ${placeCtrl.text}',
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Text('공개 범위',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textSecondary)),
                const SizedBox(width: 8),
                VisibilityPickerChip(
                  selection: selectedVis,
                  onChanged: (v) =>
                      setDialogState(() => selectedVis = v),
                  dense: true,
                ),
              ],
            ),
          ],
        ),
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
            child: const Text('업로드'),
          ),
        ],
        ),
      ),
    );

    if (confirmed != true || !mounted) return;

    final title = titleCtrl.text.trim();
    final place = placeCtrl.text.trim();
    if (title.isEmpty || place.isEmpty) {
      _showErrorSnack('제목과 장소명을 입력해 주세요');
      return;
    }

    // 역지오코딩 (REST API 우선, 실패 시 기기 Geocoder fallback)
    String? address;
    if (!kIsWeb && gps != null) {
      address = await _reverseGeocodeRest(gps.lat, gps.lng);
      if (address == null) {
        try {
          final placemarks =
              await placemarkFromCoordinates(gps.lat, gps.lng);
          if (placemarks.isNotEmpty) {
            address = _buildAddress(placemarks.first);
          }
        } catch (e) {
          debugPrint('역지오코딩 fallback 실패 (무시): $e');
        }
      }
    }

    await _uploadAndRegister(
      xfile: xfile,
      isVideo: isVideo,
      gps: gps,
      gpsTrack: gpsTrack,
      title: title,
      placeName: place,
      durationSeconds: durationSeconds,
      markerColor: MarkerEmojis.colorOf(selectedEmoji).toARGB32(),
      markerEmoji: selectedEmoji,
      address: address,
      visibility: selectedVis,
    );
    } finally {
      titleCtrl.dispose();
      placeCtrl.dispose();
    }
  }

  /// Firebase Storage 업로드 → Firestore createVlog (웹/모바일 공용)
  ///
  /// 웹: xfile.readAsBytes() → putData
  /// 모바일: xfile.path → putFile (스트리밍, 메모리 절약)
  Future<void> _uploadAndRegister({
    required XFile xfile,
    required bool isVideo,
    required GpsPoint? gps,
    required String title,
    required String placeName,
    List<GpsPoint> gpsTrack = const [],
    int? durationSeconds,
    int? markerColor,
    String? markerEmoji,
    String? address,
    VisibilitySelection visibility = VisibilitySelection.public,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    final userId = user?.uid ?? 'anonymous';
    final authorName = user?.displayName ?? user?.email ?? '익명';

    bool hasError = false;

    if (!mounted) return;
    final navigator = Navigator.of(context, rootNavigator: true);

    // 실시간 진행률 ValueNotifier
    final progressNotifier = ValueNotifier<_UploadState>(
        const _UploadState(step: '준비 중...'));

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _UploadProgressDialog(
        notifier: progressNotifier,
        isVideo: isVideo,
      ),
    );

    String? mediaUrl;
    String? thumbnailUrl;
    try {
      final id = DateTime.now().millisecondsSinceEpoch.toString();

      // ── 1. 미디어 업로드 ────────────────────────────────────────────────────
      final ext = isVideo ? 'mp4' : 'jpg';
      final storagePath = isVideo
          ? FirebaseStorageService.videoPath(userId, '$id.$ext')
          : FirebaseStorageService.photoPath(userId, '$id.$ext');

      if (kIsWeb) {
        progressNotifier.value =
            const _UploadState(step: '업로드 중...', progress: null);
        final bytes = await xfile.readAsBytes();
        mediaUrl = await FirebaseStorageService.uploadBytes(
          bytes: bytes,
          path: storagePath,
          contentType: isVideo ? 'video/mp4' : 'image/jpeg',
        );
        thumbnailUrl = isVideo ? null : mediaUrl;
      } else if (!isVideo) {
        // 사진: EXIF 회전 교정 후 업로드
        progressNotifier.value =
            const _UploadState(step: '사진 처리 중...', progress: null);
        final corrected = await _correctPhotoRotation(xfile);
        progressNotifier.value =
            const _UploadState(step: '업로드 중...', progress: 0.1);
        mediaUrl = await FirebaseStorageService.uploadBytes(
          bytes: corrected,
          path: storagePath,
          contentType: 'image/jpeg',
          onProgress: (sent, total) {
            progressNotifier.value = _UploadState(
              step: '사진 업로드 중...',
              progress: 0.1 + (total > 0 ? sent / total * 0.85 : 0),
              detail: '${(sent / 1024).toStringAsFixed(0)} / '
                  '${(total / 1024).toStringAsFixed(0)} KB',
            );
          },
        );
        thumbnailUrl = mediaUrl;
      } else {
        // ── 동영상: 압축 → 업로드 ────────────────────────────────────────────
        String videoPath = xfile.path;

        // Step 1: 압축 (0% → 40%)
        progressNotifier.value = const _UploadState(
          step: '동영상 압축 중... (첫 실행 시 오래 걸릴 수 있어요)',
          progress: null,
        );
        var compressSub = VideoCompress.compressProgress$.subscribe((p) {
          progressNotifier.value = _UploadState(
            step: '동영상 압축 중... ${p.toInt()}%',
            progress: p / 100 * 0.4,
          );
        });
        try {
          final info = await VideoCompress.compressVideo(
            xfile.path,
            quality: VideoQuality.MediumQuality, // ~540p, 원본의 20~30%
            deleteOrigin: false,
            includeAudio: true,
          );
          if (info?.path != null) {
            videoPath = info!.path!;
            final origMb = (await xfile.length() / 1024 / 1024);
            final compMb =
                (info.filesize ?? 0) / 1024 / 1024;
            debugPrint('압축: ${origMb.toStringAsFixed(1)}MB'
                ' → ${compMb.toStringAsFixed(1)}MB');
          }
        } catch (e) {
          debugPrint('압축 실패 → 원본 업로드: $e');
        } finally {
          compressSub.unsubscribe();
        }

        // Step 2: 업로드 (40% → 95%)
        progressNotifier.value = const _UploadState(
          step: '업로드 중...',
          progress: 0.4,
        );
        mediaUrl = await FirebaseStorageService.uploadFile(
          localPath: videoPath,
          path: storagePath,
          contentType: 'video/mp4',
          onProgress: (sent, total) {
            final r = total > 0 ? sent / total : 0.0;
            progressNotifier.value = _UploadState(
              step: '업로드 중... ${(r * 100).toInt()}%',
              progress: 0.4 + r * 0.55,
              detail: '${(sent / 1024 / 1024).toStringAsFixed(1)} / '
                  '${(total / 1024 / 1024).toStringAsFixed(1)} MB',
            );
          },
        );

        // 압축 캐시 정리
        try { await VideoCompress.deleteAllCache(); } catch (_) {}
      }

      // ── 2. 동영상 썸네일 생성 & 업로드 ────────────────────────────────────
      if (isVideo && !kIsWeb) {
        try {
          final thumbBytes = await vt.VideoThumbnail.thumbnailData(
            video: xfile.path,
            imageFormat: vt.ImageFormat.JPEG,
            maxHeight: 480,
            quality: 80,
          );
          if (thumbBytes != null) {
            final thumbPath =
                FirebaseStorageService.thumbnailPath(userId, '${id}_thumb.jpg');
            thumbnailUrl = await FirebaseStorageService.uploadBytes(
              bytes: thumbBytes,
              path: thumbPath,
              contentType: 'image/jpeg',
            );
          }
        } catch (e) {
          debugPrint('썸네일 생성 실패 (무시): $e');
          // 썸네일 실패해도 영상 등록은 계속 진행
        }
      }

      // ── 3. Firestore 저장 (GPS 트랙 포함) ──────────────────────────────────
      await FirestoreService.createVlog(
        authorId: userId,
        authorName: authorName,
        authorPhotoUrl: user?.photoURL,
        title: title,
        placeName: placeName,
        lat: gps?.lat ?? 37.5665,
        lng: gps?.lng ?? 126.9780,
        videoUrl: isVideo ? mediaUrl : '',
        thumbnailUrl: thumbnailUrl ?? '',
        gpsTrack: gpsTrack,
        durationSeconds: durationSeconds,
        markerColor: markerColor,
        markerEmoji: markerEmoji,
        address: address,
        visibility: visibility.visibility,
        visibleGroupIds: visibility.groupIds,
        visibleUids: visibility.visibleUids,
      );
    } catch (e) {
      hasError = true;
      debugPrint('업로드 실패: $e');

      // Firebase Storage 실패 시 Firestore에 URL 없이 저장 (fallback)
      if (mediaUrl == null) {
        try {
          await FirestoreService.createVlog(
            authorId: userId,
            authorName: authorName,
            authorPhotoUrl: user?.photoURL,
            title: title,
            placeName: placeName,
            lat: gps?.lat ?? 37.5665,
            lng: gps?.lng ?? 126.9780,
            videoUrl: '',
            thumbnailUrl: '',
            gpsTrack: gpsTrack,
            durationSeconds: durationSeconds,
            markerColor: markerColor,
            markerEmoji: markerEmoji,
            address: address,
          );
          hasError = false;
        } catch (e2) {
          debugPrint('Firestore 저장도 실패: $e2');
        }
      }
    } finally {
      progressNotifier.dispose();
      navigator.pop();
    }

    if (!mounted) return;
    if (hasError) {
      _showErrorSnack('업로드 실패. 네트워크를 확인해 주세요.');
    } else {
      _showSuccessSnack(isVideo ? '🎬 영상이 홈 피드에 등록됐습니다!' : '📷 사진이 홈 피드에 등록됐습니다!');
    }
  }

  // ─── 헬퍼 ────────────────────────────────────────────────────────────────

  /// EXIF 회전 정보를 픽셀에 반영 — 가로 촬영 시 사진이 누워 보이는 문제 수정
  ///
  /// image 4.x의 decodeImage()는 EXIF를 내부 포맷으로 파싱하지 못해
  /// bakeOrientation()이 동작하지 않는 경우가 있음.
  /// → exif 패키지로 raw bytes에서 Orientation 태그를 직접 읽어 명시적으로 회전.
  static Future<Uint8List> _correctPhotoRotation(XFile xfile) async {
    final bytes = await xfile.readAsBytes();

    // 1. exif 패키지로 Orientation 태그 직접 읽기
    // exif의 IfdValues는 Dart int가 아닌 래퍼 타입이므로
    // `is int` 체크 대신 toString() 후 파싱
    int orientation = 1;
    try {
      final tags = await readExifFromBytes(bytes);
      final orientTag = tags['Image Orientation'];
      if (orientTag != null) {
        final vals = orientTag.values.toList();
        if (vals.isNotEmpty) {
          final raw = vals.first;
          if (raw is int) {
            orientation = raw;
          } else {
            orientation = int.tryParse(raw.toString()) ?? 1;
          }
        }
      }
    } catch (e) {
      debugPrint('EXIF 파싱 실패: $e');
    }

    // 정방향(1)이면 원본 바이트 그대로 반환 (재인코딩 불필요)
    if (orientation <= 1) return bytes;

    // 2. image 패키지로 디코딩 후 명시적 회전
    //    angle 단위: 도(°), 양수 = 반시계 방향 (수학적 관례)
    //    orientation 6 = 90° 시계 = angle -90
    //    orientation 8 = 90° 반시계 = angle 90
    //    orientation 3 = 180°   = angle 180
    //
    //    Samsung CameraX(Android 15+) 등은 픽셀에 회전을 미리 적용하면서
    //    EXIF orientation 태그를 그대로 유지하는 경우가 있음.
    //    → decoded 치수로 감지: orientation 6/8인데 이미 세로(height>width)면
    //      카메라가 이미 처리한 것 → 원본 바이트 그대로 반환 (재회전 방지)
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return bytes;

    img.Image? corrected;
    switch (orientation) {
      case 3:
        corrected = img.copyRotate(decoded, angle: 180);
      case 6:
        // 센서 원본은 가로(width>height)여야 함
        // 이미 세로(height>width)면 CameraX가 픽셀 회전을 처리 완료 → 건너뜀
        if (decoded.width > decoded.height) {
          corrected = img.copyRotate(decoded, angle: -90);
        }
      case 8:
        if (decoded.width > decoded.height) {
          corrected = img.copyRotate(decoded, angle: 90);
        }
    }

    if (corrected == null) return bytes;
    return Uint8List.fromList(img.encodeJpg(corrected, quality: 92));
  }

  /// OpenStreetMap Nominatim 역지오코딩 (도로명 주소 우선, API 키 불필요)
  ///
  /// 한국 도로명(route) 커버리지가 Android Geocoder·Google REST API보다 좋음.
  /// 오류 또는 road 필드 없으면 null 반환 → 다음 fallback.
  static Future<String?> _reverseGeocodeNominatim(double lat, double lng) async {
    if (kIsWeb) return null;
    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/reverse', {
        'lat': '$lat',
        'lon': '$lng',
        'format': 'json',
        'accept-language': 'ko',
        'zoom': '18',          // street-level
        'addressdetails': '1',
      });

      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 6);
      try {
        final request = await client.getUrl(uri);
        // OSM 이용 정책상 User-Agent 필수
        request.headers.set(
            'User-Agent', 'PinFlick/1.0 (https://pinflick.web.app)');
        final response = await request.close();
        if (response.statusCode != 200) return null;

        final body = await utf8.decoder.bind(response).join();
        final data = jsonDecode(body) as Map<String, dynamic>;
        if (data['error'] != null) return null;

        final addr = data['address'] as Map<String, dynamic>?;
        if (addr == null) return null;

        final road    = addr['road']         as String?;
        final houseNo = addr['house_number'] as String?;
        final city    = (addr['city']   ?? addr['county'] ?? addr['town'])
            as String?;
        final province = (addr['province'] ?? addr['state']) as String?;

        debugPrint('[Nominatim] road=$road | city=$city | province=$province');

        if (road == null || road.isEmpty) return null;

        final parts = <String>[];
        if (province != null && province.isNotEmpty) parts.add(province);
        if (city     != null && city.isNotEmpty)     parts.add(city);
        parts.add(road);
        if (houseNo  != null && houseNo.isNotEmpty)  parts.add(houseNo);

        final result = parts.join(' ');
        debugPrint('[Nominatim] → $result');
        return result;
      } finally {
        client.close(force: false);
      }
    } catch (e) {
      debugPrint('[Nominatim] 오류: $e');
      return null;
    }
  }

  /// Google Geocoding REST API 역지오코딩 (도로명 주소 우선)
  ///
  /// 결과 목록에서 address_components에 route(도로명) 컴포넌트가 있는 항목을
  /// 골라 "시/도 시/군/구 도로명 번지" 형태로 조합.
  /// route 없으면 첫 번째 결과 formatted_address 반환.
  /// API 키 제한·오류 시 null → 기기 Geocoder fallback.
  static Future<String?> _reverseGeocodeRest(double lat, double lng) async {
    if (kIsWeb) return null;
    try {
      final apiKey = dotenv.env['GOOGLE_MAPS_API_KEY'] ?? '';
      if (apiKey.isEmpty) return null;

      final uri = Uri.https('maps.googleapis.com', '/maps/api/geocode/json', {
        'latlng': '$lat,$lng',
        'key': apiKey,
        'language': 'ko',
      });

      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 6);
      try {
        final request  = await client.getUrl(uri);
        final response = await request.close();
        if (response.statusCode != 200) return null;

        final body = await utf8.decoder.bind(response).join();
        final data = jsonDecode(body) as Map<String, dynamic>;
        final status = data['status'] as String?;
        debugPrint('[Geocoding REST] status=$status');
        if (status != 'OK') return null;

        final results = data['results'] as List<dynamic>;
        if (results.isEmpty) return null;

        // ── 모든 결과를 순회하며 route(도로명) 컴포넌트가 있는 항목 찾기 ──
        for (final result in results) {
          final components =
              (result['address_components'] as List<dynamic>?) ?? [];

          String? adminArea1, adminArea2, locality, route, streetNumber;

          for (final comp in components) {
            final types = (comp['types'] as List<dynamic>?) ?? [];
            final name  = comp['long_name'] as String? ?? '';
            if (types.contains('administrative_area_level_1')) {
              adminArea1 = name;
            } else if (types.contains('administrative_area_level_2')) {
              adminArea2 = name;
            } else if (types.contains('locality')) {
              locality = name;
            } else if (types.contains('route')) {
              route = name;          // 도로명 (예: 양지편2로)
            } else if (types.contains('street_number')) {
              streetNumber = name;   // 건물번호 (예: 11)
            }
          }

          if (route != null && route.isNotEmpty) {
            // 도로명 주소 조합: 시/도 + 시/군/구 + 도로명 + 번지
            final parts = <String>[];
            if (adminArea1 != null) parts.add(adminArea1);
            final city = adminArea2 ?? locality;
            if (city != null) parts.add(city);
            parts.add(route);
            if (streetNumber != null) parts.add(streetNumber);
            final address = parts.join(' ');
            debugPrint('[Geocoding REST] 도로명 → $address');
            return address;
          }
        }

        // route가 없으면 첫 번째 결과의 formatted_address 사용
        String fallback =
            results.first['formatted_address'] as String? ?? '';
        fallback = fallback
            .replaceAll('대한민국 ', '')
            .replaceAll(' 대한민국', '')
            .trim();
        debugPrint('[Geocoding REST] formatted → $fallback');
        return fallback.isEmpty ? null : fallback;
      } finally {
        client.close(force: false);
      }
    } catch (e) {
      debugPrint('[Geocoding REST] 오류: $e');
      return null;
    }
  }

  /// Placemark → 한국 도로명 주소 문자열
  ///
  /// Android Geocoder 필드 매핑 전략:
  ///   1순위: thoroughfare (도로명) + subThoroughfare (건물번호)
  ///   2순위: name 필드 (도로명+번지가 통합돼 들어오는 경우)
  ///   3순위: subLocality (동) + subThoroughfare (번지) — 지번 fallback
  static String _buildAddress(Placemark p) {
    final admin    = (p.administrativeArea    ?? '').trim(); // 시/도
    final subAdmin = (p.subAdministrativeArea ?? '').trim(); // 시/군/구
    final locality = (p.locality              ?? '').trim(); // 구 (일부 기기)
    final road     = (p.thoroughfare          ?? '').trim(); // 도로명
    final building = (p.subThoroughfare       ?? '').trim(); // 건물번호
    final dong     = (p.subLocality           ?? '').trim(); // 동(지번용)
    final name     = (p.name                  ?? '').trim(); // 가장 세밀한 요소

    // 디버그: 실기기에서 필드 확인용 (출시 전 제거)
    debugPrint('[Geocoding] name=$name | road=$road | building=$building'
        ' | dong=$dong | locality=$locality'
        ' | subAdmin=$subAdmin | admin=$admin');

    final seen = <String>{};
    bool add(String s) => s.isNotEmpty ? seen.add(s) : false;

    final parts = <String>[];
    for (final s in [admin, subAdmin, locality]) {
      if (add(s)) parts.add(s);
    }

    if (road.isNotEmpty) {
      // ── 1순위: thoroughfare가 있으면 도로명주소 ───────────────────────
      parts.add(road);
      if (building.isNotEmpty) parts.add(building);
    } else if (name.isNotEmpty && !_isNumericOnly(name)) {
      // ── 2순위: name이 단순 번지수가 아닌 경우 → 도로명 포함 가능성
      // 예: "양지편2로 11", "양지편2로", "테헤란로 152"
      parts.add(name);
      // name 끝에 번지가 없으면 subThoroughfare 추가
      if (building.isNotEmpty && !name.endsWith(building)) {
        parts.add(building);
      }
    } else {
      // ── 3순위: 지번주소 fallback ──────────────────────────────────────
      if (add(dong)) parts.add(dong);
      if (building.isNotEmpty) parts.add(building);
    }

    return parts.join(' ');
  }

  /// "11", "123-4" 처럼 번지 형태의 숫자 문자열이면 true
  static bool _isNumericOnly(String s) =>
      RegExp(r'^\d+(-\d+)?$').hasMatch(s);

  /// 카메라 촬영 누적 미리보기 스트립 + 완료/취소 버튼
  Widget _buildCapturedStrip() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 썸네일 행
        SizedBox(
          height: 64,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            itemCount: _capturedPhotos.length,
            itemBuilder: (_, i) => Stack(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  margin: const EdgeInsets.only(right: 6),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    color: Colors.white12,
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: _capturedPreviews[i] != null
                      ? Image.memory(_capturedPreviews[i]!, fit: BoxFit.cover)
                      : const Icon(Icons.photo, color: Colors.white38),
                ),
                // 장 번호 뱃지
                Positioned(
                  bottom: 3,
                  left: 3,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(
                      '${i + 1}',
                      style: const TextStyle(
                          color: Colors.white, fontSize: 9),
                    ),
                  ),
                ),
                // × 삭제 버튼
                Positioned(
                  top: 0,
                  right: 6,
                  child: GestureDetector(
                    onTap: () => setState(() {
                      _capturedPhotos.removeAt(i);
                      _capturedPreviews.removeAt(i);
                      if (_capturedPhotos.isEmpty) _captureFirstGps = null;
                    }),
                    child: Container(
                      width: 16,
                      height: 16,
                      decoration: const BoxDecoration(
                        color: Colors.black54,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close,
                          color: Colors.white, size: 10),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        // 취소 / 완료 버튼 행
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextButton.icon(
              onPressed: () => setState(() {
                _capturedPhotos.clear();
                _capturedPreviews.clear();
                _captureFirstGps = null;
              }),
              icon: const Icon(Icons.close, size: 14, color: Colors.white60),
              label: const Text('취소',
                  style: TextStyle(color: Colors.white60, fontSize: 12)),
            ),
            const SizedBox(width: 12),
            ElevatedButton.icon(
              onPressed: _finishPhotoCapture,
              icon: const Icon(Icons.check, size: 15),
              label: Text('완료 (${_capturedPhotos.length}장)'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.secondary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 8),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20)),
                textStyle: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _showSuccessSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: AppColors.secondary,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showErrorSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: AppColors.error,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // ─── UI ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // 비로그인 2차 방어선 — 탭 진입 차단(_onTabTap)이 웹에서 실패할 때 대비
    if (FirebaseAuth.instance.currentUser == null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.lock_outline,
                  size: 64, color: AppColors.textDisabled),
              const SizedBox(height: 16),
              const Text(
                '로그인이 필요합니다',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                '촬영 기능은 로그인 후 이용할 수 있습니다.',
                style: TextStyle(
                    color: AppColors.textSecondary, fontSize: 14),
              ),
            ],
          ),
        ),
      );
    }
    return Scaffold(
      backgroundColor: Colors.black,
      body: kIsWeb ? _buildWebUi() : _buildMobileUi(),
    );
  }

  // ── 웹 UI ──────────────────────────────────────────────────────────────────
  Widget _buildWebUi() {
    return SafeArea(
      child: Column(
        children: [
          // 상단 GPS 바
          _GpsBar(gps: _currentGps),

          // 업로드 영역
          Expanded(
            child: _isModeVideo
                ? _buildWebVideoArea()
                : _buildWebPhotoDropZone(),
          ),

          // 모드 전환 + 하단 패딩
          _ModeToggle(
            isVideo: _isModeVideo,
            onChanged: _setVideoMode,
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  /// 웹 동영상 선택 영역
  Widget _buildWebVideoArea() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: AppColors.primary.withAlpha(25),
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.primary, width: 2),
            ),
            child: const Icon(Icons.videocam, size: 52, color: AppColors.primary),
          ),
          const SizedBox(height: 24),
          Text(
            '웹에서는 파일을 선택해 주세요',
            style: TextStyle(color: Colors.white.withAlpha(179), fontSize: 15),
          ),
          const SizedBox(height: 8),
          if (_currentGps != null) _GpsChip(gps: _currentGps!)
          else Text('GPS 수신 중...',
              style: TextStyle(
                  color: Colors.white.withAlpha(102), fontSize: 12)),
          const SizedBox(height: 32),
          ElevatedButton.icon(
            onPressed: _webPickMedia,
            icon: const Icon(Icons.video_library),
            label: const Text('영상 선택'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.full)),
            ),
          ),
        ],
      ),
    );
  }

  /// 웹 사진 드래그&드롭 영역 (클릭으로도 파일 선택 가능)
  Widget _buildWebPhotoDropZone() {
    final isDragging = _isWebDragging;
    return Stack(
      children: [
        // ── HTML 드롭존 (이벤트 수신 레이어) ────────────────────────────────
        DropzoneView(
          onCreated: (ctrl) => _dropzoneCtrl = ctrl,
          onDropFiles: (files) {
            if (files != null) _onWebFilesDropped(files);
          },
          onHover: () => setState(() => _isWebDragging = true),
          onLeave: () => setState(() => _isWebDragging = false),
          mime: const [
            'image/jpeg', 'image/png', 'image/gif',
            'image/webp', 'image/heic', 'image/heif',
          ],
          cursor: CursorType.grab,
        ),

        // ── Flutter 시각 레이어 ──────────────────────────────────────────────
        GestureDetector(
          onTap: _webPickMedia,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            margin: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: isDragging
                  ? AppColors.primary.withAlpha(30)
                  : Colors.white.withAlpha(8),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isDragging
                    ? AppColors.primary
                    : Colors.white.withAlpha(51),
                width: isDragging ? 2.5 : 1.5,
                // dashed 효과: Flutter에서 직접 지원 안 함 → 실선으로 표현
              ),
            ),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // 아이콘
                  AnimatedScale(
                    scale: isDragging ? 1.15 : 1.0,
                    duration: const Duration(milliseconds: 180),
                    child: Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withAlpha(
                            isDragging ? 40 : 20),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        isDragging
                            ? Icons.download_rounded
                            : Icons.add_photo_alternate_outlined,
                        size: 48,
                        color: AppColors.primary
                            .withAlpha(isDragging ? 255 : 200),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  // 메인 안내 텍스트
                  Text(
                    isDragging ? '여기에 놓으세요!' : '사진을 드래그하거나',
                    style: TextStyle(
                      color: isDragging
                          ? AppColors.primary
                          : Colors.white.withAlpha(210),
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (!isDragging) ...[
                    const SizedBox(height: 4),
                    Text(
                      '클릭해서 파일 선택',
                      style: TextStyle(
                        color: Colors.white.withAlpha(130),
                        fontSize: 13,
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  // GPS 정보
                  if (_currentGps != null)
                    _GpsChip(gps: _currentGps!)
                  else
                    Text('GPS 수신 중...',
                        style: TextStyle(
                            color: Colors.white.withAlpha(90), fontSize: 12)),
                  const SizedBox(height: 20),
                  // 파일 선택 버튼
                  if (!isDragging)
                    OutlinedButton.icon(
                      onPressed: _webPickMedia,
                      icon: const Icon(Icons.photo_library, size: 18),
                      label: const Text('파일 선택 (최대 5장)'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: BorderSide(
                            color: Colors.white.withAlpha(100), width: 1),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 10),
                        shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(AppRadius.full)),
                      ),
                    ),
                  if (isDragging)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withAlpha(30),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '최대 $_maxPhotos장까지 등록',
                        style: const TextStyle(
                            color: AppColors.primary,
                            fontSize: 13,
                            fontWeight: FontWeight.w500),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── 모바일 UI ──────────────────────────────────────────────────────────────
  // 카메라 화면은 세로 모드로 고정. 가로 레이아웃은 더 이상 사용 안 함.
  Widget _buildMobileUi() => _buildMobilePortraitUi();

  /// 세로 레이아웃 (사진 모드 / 세로 동영상)
  Widget _buildMobilePortraitUi() {
    return Stack(
      fit: StackFit.expand,
      children: [
        // 카메라 프리뷰 — lockCaptureOrientation으로 회전된 sensor 출력을
        // 사용자 시각으로 정상 표시되도록 반대로 회전 (RotatedBox는 레이아웃 차원도 함께 회전)
        _isCameraReady && _cameraController != null
            ? RotatedBox(
                quarterTurns: _quarterTurns,
                child: CameraPreview(_cameraController!),
              )
            : const _CameraPlaceholder(),

        // 상단 오버레이 (GPS + 녹화 시간)
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withAlpha(153),
                  Colors.transparent,
                ],
              ),
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    if (_currentGps != null)
                      _GpsChip(
                          gps: _currentGps!, quarterTurns: _quarterTurns),
                    const Spacer(),
                    if (_isRecording)
                      _RecordingBadge(
                          seconds: _recordSeconds,
                          quarterTurns: _quarterTurns),
                  ],
                ),
              ),
            ),
          ),
        ),

        // 하단 컨트롤
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [
                  Colors.black.withAlpha(204),
                  Colors.transparent,
                ],
              ),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // ── 연속 촬영 미리보기 스트립 ────────────────────────
                    if (_capturedPhotos.isNotEmpty) ...[
                      _buildCapturedStrip(),
                      const SizedBox(height: 12),
                    ],

                    // 모드 전환 탭
                    _ModeToggle(
                      isVideo: _isModeVideo,
                      onChanged: _isRecording ? null : _setVideoMode,
                      quarterTurns: _quarterTurns,
                    ),
                    const SizedBox(height: 20),

                    // 촬영 컨트롤 행
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        // 갤러리 버튼 (사진 모드: 멀티 선택)
                        _ControlButton(
                          icon: Icons.photo_library,
                          onTap: _isModeVideo || _isRecording
                              ? null
                              : _pickMultiPhoto,
                          size: 44,
                          quarterTurns: _quarterTurns,
                        ),

                        // 메인 촬영 버튼 (누적 장 수 뱃지 포함)
                        Stack(
                          alignment: Alignment.topRight,
                          clipBehavior: Clip.none,
                          children: [
                            _ShutterButton(
                              isVideo: _isModeVideo,
                              isRecording: _isRecording,
                              isProcessing: _isProcessing,
                              onTap: _isModeVideo
                                  ? (_isRecording
                                      ? _stopRecording
                                      : _startRecording)
                                  : _takePhoto,
                            ),
                            if (!_isModeVideo && _capturedPhotos.isNotEmpty)
                              Positioned(
                                top: -4,
                                right: -4,
                                child: Container(
                                  width: 22,
                                  height: 22,
                                  decoration: BoxDecoration(
                                    color: AppColors.secondary,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                        color: Colors.black, width: 2),
                                  ),
                                  child: Center(
                                    child: Text(
                                      '${_capturedPhotos.length}',
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),

                        // 카메라 전환 버튼
                        _ControlButton(
                          icon: Icons.flip_camera_ios,
                          onTap: _isRecording ? null : _flipCamera,
                          size: 44,
                          quarterTurns: _quarterTurns,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

}

// ─── 업로드 진행률 ────────────────────────────────────────────────────────────

/// 업로드 다이얼로그용 상태 모델
class _UploadState {
  final String step;       // 현재 단계 텍스트
  final double? progress;  // 0.0~1.0, null = 인디터미넌트
  final String? detail;    // 바이트/파일크기 등 부가 정보

  const _UploadState({required this.step, this.progress, this.detail});
}

/// 실시간 업로드 진행률 다이얼로그
class _UploadProgressDialog extends StatelessWidget {
  final ValueNotifier<_UploadState> notifier;
  final bool isVideo;
  const _UploadProgressDialog(
      {required this.notifier, required this.isVideo});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<_UploadState>(
      valueListenable: notifier,
      builder: (context, state, child) => AlertDialog(
        title: Row(children: [
          Icon(isVideo ? Icons.videocam : Icons.photo,
              color: AppColors.primary, size: 20),
          const SizedBox(width: 8),
          Text(isVideo ? '영상 업로드 중' : '사진 업로드 중',
              style: const TextStyle(fontSize: 16)),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LinearProgressIndicator(
              value: state.progress,
              color: AppColors.primary,
              backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
            ),
            const SizedBox(height: 10),
            Text(
              state.step,
              style: const TextStyle(
                  fontSize: 12, color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            if (state.detail != null) ...[
              const SizedBox(height: 4),
              Text(
                state.detail!,
                style: const TextStyle(
                    fontSize: 11, color: AppColors.textDisabled),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── 서브 위젯 ────────────────────────────────────────────────────────────────

class _GpsBar extends StatelessWidget {
  final GpsPoint? gps;
  const _GpsBar({required this.gps});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(
            Icons.location_on,
            size: 14,
            color: gps != null ? AppColors.secondary : Colors.white38,
          ),
          const SizedBox(width: 4),
          Text(
            gps != null
                ? '${gps!.lat.toStringAsFixed(5)}, ${gps!.lng.toStringAsFixed(5)}'
                : 'GPS 수신 중...',
            style: TextStyle(
              color: gps != null ? Colors.white : Colors.white38,
              fontSize: 12,
            ),
          ),
          if (gps?.accuracy != null) ...[
            const SizedBox(width: 8),
            Text(
              '±${gps!.accuracy!.toStringAsFixed(0)}m',
              style: const TextStyle(color: Colors.white38, fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }
}

class _GpsChip extends StatelessWidget {
  final GpsPoint gps;
  final int quarterTurns;
  const _GpsChip({required this.gps, this.quarterTurns = 0});

  @override
  Widget build(BuildContext context) {
    return AnimatedRotation(
      turns: quarterTurns / 4.0,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.secondary.withAlpha(153)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.gps_fixed, size: 12, color: AppColors.secondary),
            const SizedBox(width: 4),
            Text(
              '${gps.lat.toStringAsFixed(4)}, ${gps.lng.toStringAsFixed(4)}',
              style: const TextStyle(color: Colors.white, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecordingBadge extends StatefulWidget {
  final int seconds;
  final int quarterTurns;
  const _RecordingBadge({required this.seconds, this.quarterTurns = 0});

  @override
  State<_RecordingBadge> createState() => _RecordingBadgeState();
}

class _RecordingBadgeState extends State<_RecordingBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ac = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _ac.dispose();
    super.dispose();
  }

  String _fmt(int s) {
    final m = (s ~/ 60).toString().padLeft(2, '0');
    final sec = (s % 60).toString().padLeft(2, '0');
    return '$m:$sec';
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedRotation(
      turns: widget.quarterTurns / 4.0,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            FadeTransition(
              opacity: _ac,
              child: Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              _fmt(widget.seconds),
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModeToggle extends StatelessWidget {
  final bool isVideo;
  final ValueChanged<bool>? onChanged;
  final int quarterTurns;
  const _ModeToggle({
    required this.isVideo,
    required this.onChanged,
    this.quarterTurns = 0,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _Tab(
          label: '사진',
          selected: !isVideo,
          quarterTurns: quarterTurns,
          onTap: onChanged == null ? null : () => onChanged!(false),
        ),
        const SizedBox(width: 4),
        _Tab(
          label: '동영상',
          selected: isVideo,
          quarterTurns: quarterTurns,
          onTap: onChanged == null ? null : () => onChanged!(true),
        ),
      ],
    );
  }
}

class _Tab extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final int quarterTurns;
  const _Tab({
    required this.label,
    required this.selected,
    required this.onTap,
    this.quarterTurns = 0,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: AnimatedRotation(
          turns: quarterTurns / 4.0,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.black : Colors.white60,
              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }
}

class _ShutterButton extends StatelessWidget {
  final bool isVideo;
  final bool isRecording;
  final bool isProcessing;
  final VoidCallback? onTap;

  const _ShutterButton({
    required this.isVideo,
    required this.isRecording,
    required this.isProcessing,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final outerColor = isRecording ? Colors.red.withAlpha(51) : Colors.white24;
    final innerColor = isRecording ? Colors.red : Colors.white;

    return GestureDetector(
      onTap: isProcessing ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 76,
        height: 76,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: outerColor, width: 4),
        ),
        child: Center(
          child: isProcessing
              ? const SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2.5),
                )
              : AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: isRecording ? 28 : 58,
                  height: isRecording ? 28 : 58,
                  decoration: BoxDecoration(
                    color: innerColor,
                    borderRadius: BorderRadius.circular(isRecording ? 6 : 32),
                  ),
                ),
        ),
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final double size;
  final int quarterTurns;
  const _ControlButton({
    required this.icon,
    required this.onTap,
    required this.size,
    this.quarterTurns = 0,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: size,
        height: size,
        child: Center(
          child: AnimatedRotation(
            turns: quarterTurns / 4.0,
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
            child: Icon(
              icon,
              color: onTap != null ? Colors.white : Colors.white30,
              size: size * 0.6,
            ),
          ),
        ),
      ),
    );
  }
}

class _CameraPlaceholder extends StatelessWidget {
  const _CameraPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF1A1A1A),
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Colors.white38, strokeWidth: 2),
            SizedBox(height: 16),
            Text('카메라 초기화 중...',
                style: TextStyle(color: Colors.white38, fontSize: 14)),
          ],
        ),
      ),
    );
  }
}

