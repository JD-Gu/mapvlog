import 'dart:async';

import 'package:camera/camera.dart';
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

import '../../models/gps_point.dart';
import '../../models/recording_session.dart';
import '../../services/firebase_storage_service.dart';
import '../../services/firestore_service.dart';
import '../../services/gps_tracking_service.dart';
import '../../utils/constants.dart';
import '../../utils/marker_colors.dart';

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

  GpsPoint? _currentGps;
  StreamSubscription<GpsPoint?>? _gpsSub;
  final GpsTrackingService _gpsService = GpsTrackingService();

  // 녹화 타이머
  int _recordSeconds = 0;
  Timer? _recordTimer;

  // ─── 초기화 ───────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 초기 모드는 사진 → 세로 고정
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    // Android는 동시 권한 요청 불가 → GPS 먼저, 카메라 나중
    _initPermissionsAndStart();
  }

  /// 촬영 모드 전환 + 회전 잠금 제어
  ///
  /// 사진 모드: 세로 고정 (EXIF 회전 교정이 가로 촬영을 처리)
  /// 동영상 모드: 가로/세로 모두 허용 (가로 영상 자연스럽게 촬영 가능)
  void _setVideoMode(bool isVideo) {
    setState(() => _isModeVideo = isVideo);
    // 카메라 재초기화 없음 — 모드 전환 시 재초기화하면 Android에서
    // 프리뷰가 까맣게 되거나 카메라 자원 충돌이 발생함
    SystemChrome.setPreferredOrientations(
      isVideo
          ? [
              DeviceOrientation.portraitUp,
              DeviceOrientation.landscapeLeft,
              DeviceOrientation.landscapeRight,
            ]
          : [DeviceOrientation.portraitUp],
    );
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
    // medium(720p) 고정: 사진·영상 모두 충분한 품질
    // 영상은 업로드 전 video_compress 가 추가 압축함
    const preset = ResolutionPreset.medium;
    final ctrl = CameraController(
      desc,
      preset,
      enableAudio: true,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );
    try {
      await ctrl.initialize();
      if (!mounted) return;
      _cameraController?.dispose();
      setState(() {
        _cameraController = ctrl;
        _isCameraReady = true;
      });
    } catch (e) {
      debugPrint('카메라 시작 실패: $e');
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
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }
    if (state == AppLifecycleState.inactive) {
      _cameraController?.dispose();
      setState(() => _isCameraReady = false);
    } else if (state == AppLifecycleState.resumed) {
      _startCamera(_cameras[_cameraIndex]);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
    if (_cameras.length < 2) return;
    _cameraIndex = (_cameraIndex + 1) % _cameras.length;
    await _startCamera(_cameras[_cameraIndex]);
  }

  Future<void> _takePhoto() async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);

    try {
      final gps = await GpsTrackingService.getCurrentPoint();
      final file = await _cameraController!.takePicture();

      // 사진은 단일 좌표 트랙 (videoTimeMs=0)
      final track = gps != null ? [gps] : <GpsPoint>[];

      if (!mounted) return;
      await _showUploadDialog(
          xfile: file, isVideo: false, gps: gps, gpsTrack: track);
    } catch (e) {
      _showErrorSnack('사진 촬영 실패: $e');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
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

    XFile? xfile;
    if (_isModeVideo) {
      xfile = await picker.pickVideo(source: ImageSource.gallery);
    } else {
      xfile = await picker.pickImage(source: ImageSource.gallery);
    }

    if (xfile == null || !mounted) return;

    // 웹/갤러리 선택은 단일 좌표 트랙
    final track = gps != null ? [gps] : <GpsPoint>[];
    await _showUploadDialog(
        xfile: xfile, isVideo: _isModeVideo, gps: gps, gpsTrack: track);
  }

  /// 제목·장소 입력 다이얼로그 → 업로드 실행 (웹/모바일 공용)
  Future<void> _showUploadDialog({
    required XFile xfile,
    required bool isVideo,
    required GpsPoint? gps,
    List<GpsPoint> gpsTrack = const [],
    int? durationSeconds,
  }) async {
    final titleCtrl = TextEditingController();
    final placeCtrl = TextEditingController();
    // 기본 선택 색상 = 파랑
    int selectedColor = MarkerColors.options.first.toARGB32();

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
            // ── 마커 색상 선택 ──────────────────────────────────────
            const SizedBox(height: 14),
            Row(children: [
              Icon(Icons.location_on, size: 14,
                  color: Color(selectedColor)),
              const SizedBox(width: 4),
              const Text('지도 마커 색상',
                  style: TextStyle(
                      fontSize: 12, color: AppColors.textSecondary)),
            ]),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: MarkerColors.options.map((color) {
                final isSelected = selectedColor == color.toARGB32();
                return GestureDetector(
                  onTap: () =>
                      setDialogState(() => selectedColor = color.toARGB32()),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isSelected
                            ? Colors.white
                            : Colors.transparent,
                        width: 3,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: color.withAlpha(isSelected ? 180 : 80),
                          blurRadius: isSelected ? 8 : 4,
                          spreadRadius: isSelected ? 1 : 0,
                        ),
                      ],
                    ),
                    child: isSelected
                        ? const Icon(Icons.check,
                            color: Colors.white, size: 16)
                        : null,
                  ),
                );
              }).toList(),
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

    await _uploadAndRegister(
      xfile: xfile,
      isVideo: isVideo,
      gps: gps,
      gpsTrack: gpsTrack,
      title: title,
      placeName: place,
      durationSeconds: durationSeconds,
      markerColor: selectedColor,
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
        title: title,
        placeName: placeName,
        lat: gps?.lat ?? 37.5665,
        lng: gps?.lng ?? 126.9780,
        videoUrl: isVideo ? mediaUrl : '',
        thumbnailUrl: thumbnailUrl ?? '',
        gpsTrack: gpsTrack,
        durationSeconds: durationSeconds,
        markerColor: markerColor,
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
            title: title,
            placeName: placeName,
            lat: gps?.lat ?? 37.5665,
            lng: gps?.lng ?? 126.9780,
            videoUrl: '',
            thumbnailUrl: '',
            gpsTrack: gpsTrack,
            durationSeconds: durationSeconds,
            markerColor: markerColor,
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
    //    angle 단위: 도(°), 양수 = 반시계 방향
    //    orientation 6 = 90° 시계 = angle -90
    //    orientation 8 = 90° 반시계 = angle 90
    //    orientation 3 = 180° = angle 180
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return bytes;

    final img.Image corrected;
    switch (orientation) {
      case 3:
        corrected = img.copyRotate(decoded, angle: 180);
      case 6:
        corrected = img.copyRotate(decoded, angle: -90);
      case 8:
        corrected = img.copyRotate(decoded, angle: 90);
      default:
        corrected = decoded;
    }

    return Uint8List.fromList(img.encodeJpg(corrected, quality: 92));
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

          // 안내 영역
          Expanded(
            child: Center(
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
                    child: Icon(
                      _isModeVideo ? Icons.videocam : Icons.photo_camera,
                      size: 52,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    '웹에서는 파일을 선택해 주세요',
                    style: TextStyle(
                        color: Colors.white.withAlpha(179), fontSize: 15),
                  ),
                  const SizedBox(height: 8),
                  if (_currentGps != null)
                    _GpsChip(gps: _currentGps!)
                  else
                    Text(
                      'GPS 수신 중...',
                      style: TextStyle(
                          color: Colors.white.withAlpha(102), fontSize: 12),
                    ),
                  const SizedBox(height: 32),
                  ElevatedButton.icon(
                    onPressed: _webPickMedia,
                    icon: Icon(_isModeVideo
                        ? Icons.video_library
                        : Icons.photo_library),
                    label: Text(_isModeVideo ? '영상 선택' : '사진 선택'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.full)),
                    ),
                  ),
                ],
              ),
            ),
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

  // ── 모바일 UI ──────────────────────────────────────────────────────────────
  Widget _buildMobileUi() {
    return OrientationBuilder(
      builder: (context, orientation) {
        // 동영상 모드이고 실제로 가로 회전한 경우만 가로 레이아웃 사용
        if (_isModeVideo && orientation == Orientation.landscape) {
          return _buildMobileLandscapeUi();
        }
        return _buildMobilePortraitUi();
      },
    );
  }

  /// 세로 레이아웃 (사진 모드 / 세로 동영상)
  Widget _buildMobilePortraitUi() {
    return Stack(
      fit: StackFit.expand,
      children: [
        // 카메라 프리뷰
        _isCameraReady && _cameraController != null
            ? CameraPreview(_cameraController!)
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
                    if (_currentGps != null) _GpsChip(gps: _currentGps!),
                    const Spacer(),
                    if (_isRecording)
                      _RecordingBadge(seconds: _recordSeconds),
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
                    // 모드 전환 탭
                    _ModeToggle(
                      isVideo: _isModeVideo,
                      onChanged: _isRecording ? null : _setVideoMode,
                    ),
                    const SizedBox(height: 20),

                    // 촬영 컨트롤 행
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        // 갤러리 버튼 (미구현 → 비활성)
                        _ControlButton(
                          icon: Icons.photo_library,
                          onTap: () {},
                          size: 44,
                        ),

                        // 메인 촬영 버튼
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

                        // 카메라 전환 버튼
                        _ControlButton(
                          icon: Icons.flip_camera_ios,
                          onTap: _isRecording ? null : _flipCamera,
                          size: 44,
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

  /// 가로 레이아웃 (동영상 모드 + 가로 회전 시)
  ///
  /// 컨트롤을 오른쪽에 세로로 배치 → 프리뷰 영역 극대화
  Widget _buildMobileLandscapeUi() {
    return Stack(
      fit: StackFit.expand,
      children: [
        // 카메라 프리뷰 (전체 화면)
        _isCameraReady && _cameraController != null
            ? CameraPreview(_cameraController!)
            : const _CameraPlaceholder(),

        // 상단 오버레이 (GPS + 녹화 시간) — 가로에서도 동일
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
                    if (_currentGps != null) _GpsChip(gps: _currentGps!),
                    const Spacer(),
                    if (_isRecording)
                      _RecordingBadge(seconds: _recordSeconds),
                  ],
                ),
              ),
            ),
          ),
        ),

        // 우측 컨트롤 패널
        Positioned(
          right: 0,
          top: 0,
          bottom: 0,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerRight,
                end: Alignment.centerLeft,
                colors: [
                  Colors.black.withAlpha(204),
                  Colors.transparent,
                ],
              ),
            ),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 20, 16),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // 카메라 전환
                    _ControlButton(
                      icon: Icons.flip_camera_ios,
                      onTap: _isRecording ? null : _flipCamera,
                      size: 44,
                    ),
                    const SizedBox(height: 24),

                    // 메인 촬영 버튼
                    _ShutterButton(
                      isVideo: true,
                      isRecording: _isRecording,
                      isProcessing: _isProcessing,
                      onTap: _isRecording ? _stopRecording : _startRecording,
                    ),
                    const SizedBox(height: 24),

                    // 모드 전환 (녹화 중 비활성)
                    _ControlButton(
                      icon: Icons.photo_camera,
                      onTap: _isRecording
                          ? null
                          : () => _setVideoMode(false),
                      size: 44,
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
              backgroundColor: AppColors.surfaceVariant,
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
  const _GpsChip({required this.gps});

  @override
  Widget build(BuildContext context) {
    return Container(
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
    );
  }
}

class _RecordingBadge extends StatefulWidget {
  final int seconds;
  const _RecordingBadge({required this.seconds});

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
    return Container(
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
                color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _ModeToggle extends StatelessWidget {
  final bool isVideo;
  final ValueChanged<bool>? onChanged;
  const _ModeToggle({required this.isVideo, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _Tab(
          label: '사진',
          selected: !isVideo,
          onTap: onChanged == null ? null : () => onChanged!(false),
        ),
        const SizedBox(width: 4),
        _Tab(
          label: '동영상',
          selected: isVideo,
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
  const _Tab(
      {required this.label, required this.selected, required this.onTap});

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
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.black : Colors.white60,
            fontWeight:
                selected ? FontWeight.bold : FontWeight.normal,
            fontSize: 13,
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
  const _ControlButton(
      {required this.icon, required this.onTap, required this.size});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: size,
        height: size,
        child: Icon(
          icon,
          color: onTap != null ? Colors.white : Colors.white30,
          size: size * 0.6,
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
