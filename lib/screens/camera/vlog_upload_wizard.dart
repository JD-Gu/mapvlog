// PinFlick 브이로그 등록 마법사 — 4단계 PageView
//   1. 미디어 선택 + 4:3 강제 크롭
//   2. 카테고리 이모지 선택 (단일)
//   3. 한 줄 스토리 + 장소 + GPS 칩
//   4. 공개 범위 + 프리뷰 + 발행

import 'dart:async';
import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_compress/video_compress.dart';
import 'package:video_thumbnail/video_thumbnail.dart' as vt;

import '../../models/gps_point.dart';
import '../../models/vlog.dart';
import '../../services/firebase_storage_service.dart';
import '../../services/firestore_service.dart';
import '../../services/geocoding_service.dart';
import '../../services/location_service.dart';
import '../../utils/constants.dart';
import '../../utils/marker_emojis.dart';
import '../../widgets/emoji_picker_row.dart';
import '../../widgets/map_picker_sheet.dart';
import '../../widgets/visibility_picker.dart';

class VlogUploadWizard extends StatefulWidget {
  const VlogUploadWizard({super.key});

  @override
  State<VlogUploadWizard> createState() => _VlogUploadWizardState();
}

class _VlogUploadWizardState extends State<VlogUploadWizard> {
  final _pageCtrl = PageController();
  int _step = 0;
  static const _totalSteps = 4;

  // 마법사 상태
  // ── Step 1: 미디어 ─────────────────────────────────────────
  // 모드는 photos 모드 (최대 5장) 또는 video 모드 (1개) 중 하나
  final List<XFile> _photos = [];
  final List<Uint8List> _photoBytes = [];
  /// 각 사진의 표시 aspect ratio (가로 4/3 ≈ 1.333, 세로 3/4 = 0.75)
  final List<double> _photoAspects = [];
  XFile? _video;
  Uint8List? _videoThumb;
  int? _videoDurationSec;
  static const int _maxPhotos = 5;

  // ── 동영상 업로드 가드 임계값 ──────────────────────────────────────
  static const int _maxVideoSeconds = 60; // 녹화/길이 제한
  static const int _webWarnMB = 60;       // 웹(압축 미지원) 경고 기준
  static const int _hardWarnMB = 150;     // 최종 업로드 용량 경고 기준
  bool get _hasMedia => _photos.isNotEmpty || _video != null;
  bool get _isVideoMode => _video != null;

  String _emoji = MarkerEmojis.defaultEmoji; // Step 2
  final _titleCtrl = TextEditingController(); // Step 3
  final _placeCtrl = TextEditingController();
  Position? _position;
  String? _address; // 도로명 상세 주소 (표시용)
  String? _dong; // 행정동 (placeName fallback 용)
  VisibilitySelection _vis = VisibilitySelection.public; // Step 4

  bool _uploading = false;
  double _uploadProgress = 0; // 0~1 (0이면 비결정 인디케이터)
  String _uploadStatus = '';  // "영상 압축 중...", "업로드 45%" 등

  @override
  void initState() {
    super.initState();
    _initLocation();
  }

  bool _locating = false;

  Future<void> _initLocation() async {
    await _refreshLocation();
  }

  /// 현재 위치 새로고침 + 도로명 주소 역지오코딩 (웹/모바일 공용)
  Future<void> _refreshLocation() async {
    if (_locating) return;
    setState(() {
      _locating = true;
      _address = null;
    });
    try {
      final pos = await LocationService.getCurrentPosition(context);
      if (!mounted) return;
      setState(() => _position = pos);
      if (pos != null) await _resolveAddress(pos);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  /// 좌표 → 도로명 주소 + 동 단위. Nominatim(웹/모바일) 우선.
  Future<void> _resolveAddress(Position pos) async {
    String? addr =
        await GeocodingService.reverseToRoadAddress(pos.latitude, pos.longitude);
    String? dong =
        await GeocodingService.reverseToNeighbourhood(pos.latitude, pos.longitude);
    // 모바일 fallback — 기기 Geocoder
    if ((addr == null || addr.isEmpty) && !kIsWeb) {
      try {
        final p = await placemarkFromCoordinates(pos.latitude, pos.longitude);
        if (p.isNotEmpty) {
          final pm = p.first;
          final parts = [
            pm.administrativeArea,
            pm.locality,
            pm.subLocality,
            pm.thoroughfare,
            pm.subThoroughfare,
          ].where((s) => s != null && s.isNotEmpty).toList();
          addr = parts.join(' ');
          dong ??= pm.subLocality;
        }
      } catch (_) {}
    }
    if (mounted) {
      setState(() {
        _address = addr;
        _dong = dong;
      });
    }
  }

  /// 주소 검색 시트 → 선택한 결과(위경도 포함)를 즉시 적용
  Future<void> _registerByAddress() async {
    final hit = await showModalBottomSheet<
        ({double lat, double lng, String display})>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _AddressSearchSheet(),
    );
    if (hit == null || !mounted) return;
    setState(() {
      _locating = true;
      _position = Position(
        latitude: hit.lat,
        longitude: hit.lng,
        timestamp: DateTime.now(),
        accuracy: 0,
        altitude: 0,
        altitudeAccuracy: 0,
        heading: 0,
        headingAccuracy: 0,
        speed: 0,
        speedAccuracy: 0,
      );
    });
    try {
      await _resolveAddress(_position!);
      _toast('📍 주소로 위치를 설정했어요');
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  /// 지도에서 위치 선택 — 미니 지도 시트
  Future<void> _pickOnMap() async {
    final start = _position != null
        ? LatLng(_position!.latitude, _position!.longitude)
        : const LatLng(37.5665, 126.9780);
    final picked = await MapPickerSheet.open(context, initial: start);
    if (picked == null || !mounted) return;
    setState(() {
      _position = Position(
        latitude: picked.latitude,
        longitude: picked.longitude,
        timestamp: DateTime.now(),
        accuracy: 0,
        altitude: 0,
        altitudeAccuracy: 0,
        heading: 0,
        headingAccuracy: 0,
        speed: 0,
        speedAccuracy: 0,
      );
    });
    await _resolveAddress(_position!);
    _toast('🗺️ 지도에서 위치를 선택했어요');
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    _titleCtrl.dispose();
    _placeCtrl.dispose();
    super.dispose();
  }

  bool get _canGoNext {
    switch (_step) {
      case 0:
        return _hasMedia;
      case 1:
        return _emoji.isNotEmpty;
      case 2:
        return _titleCtrl.text.trim().isNotEmpty;
      case 3:
        return true;
      default:
        return false;
    }
  }

  void _next() {
    HapticFeedback.selectionClick();
    if (_step < _totalSteps - 1) {
      _pageCtrl.nextPage(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _back() {
    HapticFeedback.selectionClick();
    if (_step == 0) {
      Navigator.pop(context);
    } else {
      _pageCtrl.previousPage(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    }
  }

  /// 사진 1장 촬영(카메라) 또는 갤러리 멀티 선택
  /// - 영상 모드 활성 시 영상 자동 제거 (모드 전환)
  /// - photos 모드는 최대 5장
  Future<void> _pickPhotos({required ImageSource source}) async {
    HapticFeedback.selectionClick();
    final picker = ImagePicker();
    try {
      final List<XFile> picked = [];
      if (source == ImageSource.camera) {
        final one =
            await picker.pickImage(source: source, imageQuality: 90);
        if (one != null) picked.add(one);
      } else {
        final remaining = _maxPhotos - _photos.length;
        if (remaining <= 0) {
          _toast('사진은 최대 $_maxPhotos장까지 추가할 수 있어요');
          return;
        }
        final multi =
            await picker.pickMultiImage(limit: remaining, imageQuality: 90);
        picked.addAll(multi);
      }
      if (picked.isEmpty || !mounted) return;

      // 각 사진 크롭 — 가로는 4:3, 세로는 3:4 자동 판별
      // 웹은 image_cropper 호환성 이슈로 스킵 — 원본 사용
      final List<XFile> cropped = [];
      final List<Uint8List> bytes = [];
      final List<double> aspects = [];
      for (final p in picked) {
        XFile? finalFile;
        final origBytes = await p.readAsBytes();
        // 원본 가로/세로 판별
        final decoded = await decodeImageFromList(origBytes);
        final isPortrait = decoded.height > decoded.width;
        final aspectRatio =
            isPortrait ? (3.0 / 4.0) : (4.0 / 3.0);

        if (kIsWeb) {
          finalFile = p;
        } else {
          try {
            final c = await ImageCropper().cropImage(
              sourcePath: p.path,
              aspectRatio: isPortrait
                  ? const CropAspectRatio(ratioX: 3, ratioY: 4)
                  : const CropAspectRatio(ratioX: 4, ratioY: 3),
              compressQuality: 88,
              uiSettings: [
                AndroidUiSettings(
                  toolbarTitle: isPortrait ? '3:4 비율로 자르기' : '4:3 비율로 자르기',
                  toolbarColor: AppColors.primary,
                  toolbarWidgetColor: Colors.white,
                  // 세로는 ratio3x4 preset 이 없어 original 사용
                  // (aspectRatio 파라미터로 실제 비율은 잠금돼있음)
                  initAspectRatio: isPortrait
                      ? CropAspectRatioPreset.original
                      : CropAspectRatioPreset.ratio4x3,
                  lockAspectRatio: true,
                  hideBottomControls: false,
                ),
                IOSUiSettings(
                  title: isPortrait ? '3:4 비율로 자르기' : '4:3 비율로 자르기',
                  aspectRatioLockEnabled: true,
                  resetAspectRatioEnabled: false,
                ),
              ],
            );
            if (c != null) finalFile = XFile(c.path);
          } catch (e) {
            debugPrint('크롭 실패 → 원본 사용: $e');
            finalFile = p;
          }
        }
        if (finalFile == null) continue; // 사용자가 한 장 취소
        cropped.add(finalFile);
        // 크롭된 파일 우선 사용, 안 됐으면 원본 bytes
        final finalBytes = finalFile.path != p.path
            ? await finalFile.readAsBytes()
            : origBytes;
        bytes.add(finalBytes);
        aspects.add(aspectRatio);
      }
      if (cropped.isEmpty || !mounted) return;

      setState(() {
        // 모드 전환: 영상 모드였으면 영상 비움
        _video = null;
        _videoThumb = null;
        _videoDurationSec = null;
        _photos.addAll(cropped);
        _photoBytes.addAll(bytes);
        _photoAspects.addAll(aspects);
      });

      // 폰 갤러리 저장 (카메라 촬영본만, 모바일)
      if (!kIsWeb && source == ImageSource.camera && cropped.isNotEmpty) {
        await _saveToGallery(imagePath: cropped.first.path);
      }
    } catch (e) {
      if (mounted) _toast('사진 처리 실패: $e');
    }
  }

  /// 영상 한 개 선택 — 카메라 녹화 또는 갤러리에서
  Future<void> _pickVideo({required ImageSource source}) async {
    HapticFeedback.selectionClick();
    final picker = ImagePicker();
    try {
      final picked = await picker.pickVideo(
        source: source,
        // 녹화/길이 제한 — 용량 폭증 방지 (카메라 녹화 한정)
        maxDuration: const Duration(seconds: _maxVideoSeconds),
      );
      if (picked == null || !mounted) return;
      // 사진 모드 비움
      _photoAspects.clear();

      // 썸네일 추출 (web 제외)
      Uint8List? thumb;
      int? durationSec;
      if (!kIsWeb) {
        try {
          thumb = await vt.VideoThumbnail.thumbnailData(
            video: picked.path,
            imageFormat: vt.ImageFormat.JPEG,
            maxHeight: 480,
            quality: 80,
          );
        } catch (_) {}
        try {
          final info = await VideoCompress.getMediaInfo(picked.path);
          if (info.duration != null) {
            durationSec = (info.duration! / 1000).round();
          }
        } catch (_) {}
      }
      // 원본 용량 측정 (웹/모바일 공용)
      int? sizeBytes;
      try {
        sizeBytes = await picked.length();
      } catch (_) {}
      if (!mounted) return;

      setState(() {
        _photos.clear();
        _photoBytes.clear();
        _video = picked;
        _videoThumb = thumb;
        _videoDurationSec = durationSec;
      });

      if (!kIsWeb && source == ImageSource.camera) {
        await _saveToGallery(videoPath: picked.path);
      }

      // 업로드 전 용량/시간 가드
      _guardVideo(durationSec: durationSec, sizeBytes: sizeBytes);
    } catch (e) {
      if (mounted) _toast('영상 처리 실패: $e');
    }
  }

  Future<void> _saveToGallery({String? imagePath, String? videoPath}) async {
    try {
      final ok = await Gal.hasAccess(toAlbum: true);
      if (!ok && !(await Gal.requestAccess(toAlbum: true))) return;
      if (imagePath != null) {
        await Gal.putImage(imagePath, album: 'PinFlick');
      } else if (videoPath != null) {
        await Gal.putVideo(videoPath, album: 'PinFlick');
      }
      if (mounted) _toast('📸 폰 갤러리에 저장됐어요');
    } catch (e) {
      debugPrint('갤러리 저장 실패 (무시): $e');
    }
  }

  void _removePhotoAt(int idx) {
    HapticFeedback.lightImpact();
    setState(() {
      _photos.removeAt(idx);
      _photoBytes.removeAt(idx);
      if (idx < _photoAspects.length) _photoAspects.removeAt(idx);
    });
  }

  void _clearVideo() {
    HapticFeedback.lightImpact();
    setState(() {
      _video = null;
      _videoThumb = null;
      _videoDurationSec = null;
    });
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 2),
        content: Text(msg),
      ),
    );
  }

  String _fmtMB(int? bytes) =>
      bytes == null ? '?' : '${(bytes / 1024 / 1024).toStringAsFixed(0)}MB';

  /// 업로드 전 용량/시간 가드 — 너무 크거나 길면 경고 (차단하진 않음)
  void _guardVideo({int? durationSec, int? sizeBytes}) {
    final mb = sizeBytes == null ? 0 : sizeBytes / 1024 / 1024;
    String? msg;
    if (durationSec != null && durationSec > _maxVideoSeconds) {
      msg = '영상이 길어요(${durationSec}초). $_maxVideoSeconds초 이하를 권장해요 — 업로드가 느릴 수 있어요.';
    } else if (kIsWeb && mb > _webWarnMB) {
      msg = '웹은 영상 압축을 못 해 그대로 올라가요(${_fmtMB(sizeBytes)}). '
          '더 짧은 영상이나 앱(APK)에서 등록을 권장해요.';
    } else if (mb > _hardWarnMB) {
      msg = '영상 용량이 커요(${_fmtMB(sizeBytes)}). 업로드에 시간이 걸릴 수 있어요.';
    }
    if (msg != null) _toast('⚠️ $msg');
  }

  Future<void> _publish() async {
    if (_uploading) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _toast('로그인 후 등록 가능합니다');
      return;
    }
    if (!_hasMedia) return;

    setState(() {
      _uploading = true;
      _uploadProgress = 0;
      _uploadStatus = '준비 중...';
    });
    HapticFeedback.mediumImpact();
    try {
      String? videoUrl;
      String? thumbnailUrl;
      List<String> photoUrls = [];

      final title = _titleCtrl.text.trim();
      final ts = DateTime.now().millisecondsSinceEpoch;

      if (_isVideoMode) {
        // ─── 영상 모드 ─────────────────────────────────────
        // 1) 영상 압축 (모바일만) — 긴 영상은 더 강하게 압축
        String videoPath = _video!.path;
        if (!kIsWeb) {
          setState(() {
            _uploadProgress = 0;
            _uploadStatus = '영상 압축 중...';
          });
          try {
            // 30초 초과 영상은 LowQuality 로 더 강하게 압축
            final quality = (_videoDurationSec ?? 0) > 30
                ? VideoQuality.LowQuality
                : VideoQuality.MediumQuality;
            final info = await VideoCompress.compressVideo(
              videoPath,
              quality: quality,
              deleteOrigin: false,
              includeAudio: true,
            );
            if (info?.path != null) videoPath = info!.path!;
          } catch (e) {
            debugPrint('영상 압축 실패 → 원본 업로드: $e');
          }
          // 압축 후 최종 용량 경고
          try {
            final finalBytes = await XFile(videoPath).length();
            if (finalBytes / 1024 / 1024 > _hardWarnMB) {
              _toast('⚠️ 압축 후에도 ${_fmtMB(finalBytes)} 로 커요 — 업로드가 오래 걸릴 수 있어요.');
            }
          } catch (_) {}
        }
        // 2) 영상 업로드 (진행률 표시)
        final vFile = XFile(videoPath);
        final vName = '${ts}_${title.hashCode}.mp4';
        setState(() => _uploadStatus = '영상 업로드 중...');
        videoUrl = await FirebaseStorageService.uploadXFile(
          xfile: vFile,
          path: FirebaseStorageService.videoPath(user.uid, vName),
          contentType: 'video/mp4',
          onProgress: _onUploadProgress,
        );
        // 3) 썸네일 업로드
        if (_videoThumb != null) {
          setState(() => _uploadStatus = '썸네일 업로드 중...');
          thumbnailUrl = await FirebaseStorageService.uploadBytes(
            bytes: _videoThumb!,
            path: FirebaseStorageService.thumbnailPath(
                user.uid, '${ts}_thumb.jpg'),
            contentType: 'image/jpeg',
          );
        }
        // 캐시 정리
        try {
          await VideoCompress.deleteAllCache();
        } catch (_) {}
      } else {
        // ─── 사진 모드 (1~5장) ─────────────────────────────
        for (int i = 0; i < _photos.length; i++) {
          setState(() {
            _uploadStatus = '사진 업로드 중 (${i + 1}/${_photos.length})';
            _uploadProgress = 0;
          });
          final filename = '${ts}_${i}_${title.hashCode}.jpg';
          final url = await FirebaseStorageService.uploadXFile(
            xfile: _photos[i],
            path: FirebaseStorageService.photoPath(user.uid, filename),
            contentType: 'image/jpeg',
            onProgress: _onUploadProgress,
          );
          photoUrls.add(url);
        }
        thumbnailUrl = photoUrls.first;
      }
      if (mounted) setState(() => _uploadStatus = '등록 마무리 중...');

      // 4) Firestore 저장
      await FirestoreService.createVlog(
        authorId: user.uid,
        authorName: user.displayName ?? user.email ?? '익명',
        authorPhotoUrl: user.photoURL,
        title: title,
        // 사용자 입력 우선, 없으면 동 단위만 (예: "청계동")
        placeName: _placeCtrl.text.trim().isNotEmpty
            ? _placeCtrl.text.trim()
            : (_dong ?? ''),
        lat: _position?.latitude ?? 37.5665,
        lng: _position?.longitude ?? 126.9780,
        videoUrl: videoUrl ?? '',
        thumbnailUrl: thumbnailUrl ?? '',
        gpsTrack: _position == null
            ? const []
            : [
                GpsPoint(
                  lat: _position!.latitude,
                  lng: _position!.longitude,
                  timestamp: DateTime.now(),
                  videoTimeMs: 0,
                )
              ],
        durationSeconds: _videoDurationSec,
        markerColor: MarkerEmojis.colorOf(_emoji).toARGB32(),
        markerEmoji: _emoji,
        address: _address,
        photoUrls: photoUrls,
        visibility: _vis.visibility,
        visibleGroupIds: _vis.groupIds,
        visibleUids: _vis.visibleUids,
      );
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('✅ "$title" 등록 완료!'),
        backgroundColor: AppColors.secondary,
        duration: const Duration(seconds: 2),
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _uploading = false;
        _uploadProgress = 0;
        _uploadStatus = '';
      });
      // 미디어는 그대로 보존 — '핀 올리기'를 다시 누르면 재시도됨
      _toast('업로드에 실패했어요 😢 잠시 후 "핀 올리기"로 다시 시도해 주세요.');
      debugPrint('publish 실패: $e');
    }
  }

  /// 업로드 진행률 콜백 (1% 단위 throttle)
  void _onUploadProgress(int sent, int total) {
    if (!mounted || total <= 0) return;
    final p = sent / total;
    if (p > _uploadProgress + 0.01 || p >= 1.0) {
      setState(() => _uploadProgress = p);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('브이로그 등록',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _back,
        ),
        backgroundColor: cs.surface,
        elevation: 0,
        scrolledUnderElevation: 1,
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Center(
              child: Text(
                '${_step + 1} / $_totalSteps',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: cs.primary,
                ),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            _StepIndicator(step: _step, total: _totalSteps),
            Expanded(
              child: PageView(
                controller: _pageCtrl,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (i) => setState(() => _step = i),
                children: [
                  _Step1Media(
                    photoBytes: _photoBytes,
                    firstPhotoAspect: _photoAspects.isNotEmpty
                        ? _photoAspects.first
                        : 4 / 3,
                    videoThumb: _videoThumb,
                    videoDurationSec: _videoDurationSec,
                    isVideoMode: _isVideoMode,
                    maxPhotos: _maxPhotos,
                    onPickCamera: () =>
                        _pickPhotos(source: ImageSource.camera),
                    onPickGallery: () =>
                        _pickPhotos(source: ImageSource.gallery),
                    onPickVideo: () =>
                        _pickVideo(source: ImageSource.gallery),
                    onRecordVideo: () =>
                        _pickVideo(source: ImageSource.camera),
                    onRemovePhoto: _removePhotoAt,
                    onClearVideo: _clearVideo,
                  ),
                  _Step2Category(
                    selected: _emoji,
                    onPick: (e) => setState(() => _emoji = e),
                    suggestionText: '${_titleCtrl.text} ${_placeCtrl.text}',
                  ),
                  _Step3Story(
                    titleCtrl: _titleCtrl,
                    placeCtrl: _placeCtrl,
                    emoji: _emoji,
                    address: _address,
                    locating: _locating,
                    onChanged: () => setState(() {}),
                    onRefreshLocation: _refreshLocation,
                    onPickOnMap: _pickOnMap,
                    onRegisterByAddress: _registerByAddress,
                  ),
                  _Step4Publish(
                    photoBytes: _photoBytes,
                    firstPhotoAspect: _photoAspects.isNotEmpty
                        ? _photoAspects.first
                        : 4 / 3,
                    videoThumb: _videoThumb,
                    isVideoMode: _isVideoMode,
                    emoji: _emoji,
                    title: _titleCtrl.text.trim(),
                    place: _placeCtrl.text.trim().isNotEmpty
                        ? _placeCtrl.text.trim()
                        : (_dong ?? _address),
                    address: _address,
                    visibility: _vis,
                    onVisibilityChanged: (v) => setState(() => _vis = v),
                    uploading: _uploading,
                    uploadProgress: _uploadProgress,
                    uploadStatus: _uploadStatus,
                    onPublish: _publish,
                  ),
                ],
              ),
            ),
            // 하단 다음 버튼 (Step 4는 자체 발행 버튼 사용)
            if (_step < _totalSteps - 1)
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _canGoNext ? _next : null,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        minimumSize: const Size(double.infinity, 50),
                        shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(AppRadius.md)),
                      ),
                      child: const Text('다음',
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w800)),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─── 상단 단계 인디케이터 ─────────────────────────────────────────────
class _StepIndicator extends StatelessWidget {
  final int step;
  final int total;
  const _StepIndicator({required this.step, required this.total});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        children: List.generate(total, (i) {
          final active = i <= step;
          return Expanded(
            child: Container(
              height: 4,
              margin: EdgeInsets.only(right: i < total - 1 ? 6 : 0),
              decoration: BoxDecoration(
                color: active ? cs.primary : cs.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ─── Step 1 — 미디어 (멀티 사진 + 영상) ─────────────────────────────
class _Step1Media extends StatelessWidget {
  final List<Uint8List> photoBytes;
  final double firstPhotoAspect;
  final Uint8List? videoThumb;
  final int? videoDurationSec;
  final bool isVideoMode;
  final int maxPhotos;
  final VoidCallback onPickCamera;
  final VoidCallback onPickGallery;
  final VoidCallback onPickVideo;
  final VoidCallback onRecordVideo;
  final ValueChanged<int> onRemovePhoto;
  final VoidCallback onClearVideo;

  const _Step1Media({
    required this.photoBytes,
    required this.firstPhotoAspect,
    required this.videoThumb,
    required this.videoDurationSec,
    required this.isVideoMode,
    required this.maxPhotos,
    required this.onPickCamera,
    required this.onPickGallery,
    required this.onPickVideo,
    required this.onRecordVideo,
    required this.onRemovePhoto,
    required this.onClearVideo,
  });

  bool get _empty => photoBytes.isEmpty && videoThumb == null && !isVideoMode;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('📸 미디어를 선택해주세요',
              style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: cs.onSurface)),
          const SizedBox(height: 6),
          Text('가로 4:3 / 세로 3:4 자동 정돈. 사진 최대 ${maxPhotos}장. 영상은 1개',
              style: TextStyle(
                  fontSize: 12.5, color: cs.onSurfaceVariant)),
          const SizedBox(height: 18),
          // 프리뷰 영역 (사진 모드 = 첫 사진 비율, 영상/빈 상태 = 4:3)
          AspectRatio(
            aspectRatio:
                isVideoMode || photoBytes.isEmpty ? 4 / 3 : firstPhotoAspect,
            child: Container(
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(AppRadius.lg),
                border: Border.all(color: cs.outlineVariant, width: 1.5),
              ),
              child: _empty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_photo_alternate_outlined,
                              size: 40, color: cs.outline),
                          const SizedBox(height: 8),
                          Text('4:3 미디어 프리뷰',
                              style: TextStyle(
                                  fontSize: 12.5,
                                  color: cs.onSurfaceVariant)),
                        ],
                      ),
                    )
                  : isVideoMode
                      ? Stack(
                          fit: StackFit.expand,
                          children: [
                            ClipRRect(
                              borderRadius:
                                  BorderRadius.circular(AppRadius.lg),
                              child: videoThumb != null
                                  ? Image.memory(videoThumb!,
                                      fit: BoxFit.cover)
                                  : Container(color: Colors.black),
                            ),
                            const Center(
                              child: Icon(Icons.play_circle_fill,
                                  size: 64, color: Colors.white),
                            ),
                            Positioned(
                              top: 6,
                              right: 6,
                              child: _RemoveBtn(onTap: onClearVideo),
                            ),
                            if (videoDurationSec != null)
                              Positioned(
                                bottom: 6,
                                right: 6,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.black54,
                                    borderRadius:
                                        BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    _fmtDuration(videoDurationSec!),
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700),
                                  ),
                                ),
                              ),
                          ],
                        )
                      : Stack(
                          fit: StackFit.expand,
                          children: [
                            ClipRRect(
                              borderRadius:
                                  BorderRadius.circular(AppRadius.lg),
                              child: Image.memory(photoBytes.first,
                                  fit: BoxFit.cover),
                            ),
                            if (photoBytes.length > 1)
                              Positioned(
                                top: 6,
                                left: 6,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.black54,
                                    borderRadius:
                                        BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    '1 / ${photoBytes.length}',
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700),
                                  ),
                                ),
                              ),
                          ],
                        ),
            ),
          ),
          // 멀티 사진 썸네일 리스트
          if (!isVideoMode && photoBytes.isNotEmpty) ...[
            const SizedBox(height: 12),
            SizedBox(
              height: 64,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: photoBytes.length,
                separatorBuilder: (_, __) => const SizedBox(width: 6),
                itemBuilder: (_, i) => SizedBox(
                  width: 64,
                  height: 64,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.memory(photoBytes[i],
                            fit: BoxFit.cover),
                      ),
                      Positioned(
                        top: -2,
                        right: -2,
                        child: _RemoveBtn(
                            small: true,
                            onTap: () => onRemovePhoto(i)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 20),
          // 액션 버튼 4개 (2x2 그리드)
          Row(
            children: [
              Expanded(
                child: _PickButton(
                  icon: Icons.photo_camera_outlined,
                  label: '사진 촬영',
                  onTap: onPickCamera,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _PickButton(
                  icon: Icons.photo_library_outlined,
                  label: '사진 추가',
                  onTap: onPickGallery,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _PickButton(
                  icon: Icons.videocam_outlined,
                  label: '영상 촬영',
                  onTap: onRecordVideo,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _PickButton(
                  icon: Icons.video_library_outlined,
                  label: '영상 추가',
                  onTap: onPickVideo,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _fmtDuration(int sec) {
    final m = sec ~/ 60;
    final s = sec % 60;
    return '${m}:${s.toString().padLeft(2, '0')}';
  }
}

class _RemoveBtn extends StatelessWidget {
  final VoidCallback onTap;
  final bool small;
  const _RemoveBtn({required this.onTap, this.small = false});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.7),
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: small ? 22 : 28,
          height: small ? 22 : 28,
          child: Icon(Icons.close,
              size: small ? 13 : 16, color: Colors.white),
        ),
      ),
    );
  }
}

class _PickButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _PickButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.primary.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            children: [
              Icon(icon, size: 30, color: cs.primary),
              const SizedBox(height: 6),
              Text(label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: cs.primary,
                  )),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Step 2 — 카테고리 이모지 ──────────────────────────────────────────
class _Step2Category extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onPick;
  final String suggestionText;
  const _Step2Category({
    required this.selected,
    required this.onPick,
    required this.suggestionText,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('🏷️ 어떤 순간인가요?',
              style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: cs.onSurface)),
          const SizedBox(height: 6),
          Text('카테고리를 골라주세요. 지도 마커 컬러로 적용됩니다',
              style: TextStyle(
                  fontSize: 12.5, color: cs.onSurfaceVariant)),
          const SizedBox(height: 18),
          // scrollable:false → 8개 그룹 모두 인라인 렌더, 페이지가 통째로 스크롤
          Expanded(
            child: SingleChildScrollView(
              child: EmojiPickerRow(
                selected: selected,
                onPick: onPick,
                suggestionText: suggestionText,
                scrollable: false,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Step 3 — 스토리 ───────────────────────────────────────────────────
class _Step3Story extends StatelessWidget {
  final TextEditingController titleCtrl;
  final TextEditingController placeCtrl;
  final String emoji;
  final String? address;
  final bool locating;
  final VoidCallback onChanged;
  final VoidCallback onRefreshLocation;
  final VoidCallback onPickOnMap;
  final VoidCallback onRegisterByAddress;
  const _Step3Story({
    required this.titleCtrl,
    required this.placeCtrl,
    required this.emoji,
    required this.address,
    required this.locating,
    required this.onChanged,
    required this.onRefreshLocation,
    required this.onPickOnMap,
    required this.onRegisterByAddress,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('✏️ 한 줄로 표현해주세요',
                style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: cs.onSurface)),
            const SizedBox(height: 16),
            // 이모지 프리뷰 + 제목 입력 (2줄 가능)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: cs.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      border: Border.all(
                          color: cs.primary.withValues(alpha: 0.3)),
                    ),
                    alignment: Alignment.center,
                    child: Text(emoji,
                        style: const TextStyle(fontSize: 22)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: titleCtrl,
                    onChanged: (_) => onChanged(),
                    maxLength: 50,
                    minLines: 2,
                    maxLines: 2,
                    textInputAction: TextInputAction.newline,
                    keyboardType: TextInputType.multiline,
                    decoration: const InputDecoration(
                      labelText: '한 줄 스토리 *',
                      hintText: '예: 가족과 함께한 경복궁 나들이\n날씨가 정말 좋았던 하루',
                      border: OutlineInputBorder(),
                      alignLabelWithHint: true,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            TextField(
              controller: placeCtrl,
              onChanged: (_) => onChanged(),
              maxLength: 30,
              decoration: const InputDecoration(
                labelText: '장소·브랜드',
                hintText: '예: 경복궁, 메가커피 종로점',
                border: OutlineInputBorder(),
                helperText: '선택 — 비워두면 현재 위치로 자동 채워져요',
              ),
            ),
            const SizedBox(height: 12),
            // 현재 위치 칩
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: cs.secondary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(
                    color: cs.secondary.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  if (locating)
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: cs.secondary),
                    )
                  else
                    Icon(Icons.place, size: 16, color: cs.secondary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      locating
                          ? '위치 확인 중…'
                          : (address != null && address!.isNotEmpty
                              ? address!
                              : '위치를 확인할 수 없어요'),
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: cs.secondary,
                          height: 1.3),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            // 위치 보정 섹션
            Text('💡 현재 위치가 부정확한가요?',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: cs.onSurface)),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: LocationActionButton(
                    icon: Icons.my_location,
                    label: '현재위치\n새로고침',
                    onTap: onRefreshLocation,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: LocationActionButton(
                    icon: Icons.map_outlined,
                    label: '지도에서\n선택',
                    onTap: onPickOnMap,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: LocationActionButton(
                    icon: Icons.home_outlined,
                    label: '주소로\n등록',
                    onTap: onRegisterByAddress,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Step 4 — 공개 범위 + 프리뷰 + 발행 ───────────────────────────────
class _Step4Publish extends StatelessWidget {
  final List<Uint8List> photoBytes;
  final double firstPhotoAspect;
  final Uint8List? videoThumb;
  final bool isVideoMode;
  final String emoji;
  final String title;
  final String? place;
  final String? address;
  final VisibilitySelection visibility;
  final ValueChanged<VisibilitySelection> onVisibilityChanged;
  final bool uploading;
  final double uploadProgress;
  final String uploadStatus;
  final VoidCallback onPublish;
  const _Step4Publish({
    required this.photoBytes,
    required this.firstPhotoAspect,
    required this.videoThumb,
    required this.isVideoMode,
    required this.emoji,
    required this.title,
    required this.place,
    required this.address,
    required this.visibility,
    required this.onVisibilityChanged,
    required this.uploading,
    required this.uploadProgress,
    required this.uploadStatus,
    required this.onPublish,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('🔒 누구에게 보일지 골라주세요',
              style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: cs.onSurface)),
          const SizedBox(height: 16),
          VisibilityPickerChip(
            selection: visibility,
            onChanged: onVisibilityChanged,
          ),
          const SizedBox(height: 18),
          Text('🪞 프리뷰',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: cs.onSurfaceVariant)),
          const SizedBox(height: 8),
          // 프리뷰 카드
          Expanded(
            child: SingleChildScrollView(
              child: Container(
                decoration: BoxDecoration(
                  color: cs.surface,
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  border: Border.all(color: cs.outlineVariant),
                  boxShadow: AppShadow.card,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (isVideoMode && videoThumb != null)
                      ClipRRect(
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(AppRadius.lg)),
                        child: AspectRatio(
                          aspectRatio: 4 / 3,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Image.memory(videoThumb!,
                                  fit: BoxFit.cover),
                              const Center(
                                child: Icon(Icons.play_circle_fill,
                                    size: 56, color: Colors.white),
                              ),
                            ],
                          ),
                        ),
                      )
                    else if (photoBytes.isNotEmpty)
                      ClipRRect(
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(AppRadius.lg)),
                        child: AspectRatio(
                          aspectRatio: firstPhotoAspect,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Image.memory(photoBytes.first,
                                  fit: BoxFit.cover),
                              if (photoBytes.length > 1)
                                Positioned(
                                  bottom: 6,
                                  right: 6,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.black54,
                                      borderRadius:
                                          BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      '${photoBytes.length}장',
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(emoji,
                                  style: const TextStyle(fontSize: 18)),
                              const SizedBox(width: 6),
                              if (visibility.visibility !=
                                  VlogVisibility.public)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 5, vertical: 1.5),
                                  decoration: BoxDecoration(
                                    color: cs.surfaceContainerHighest,
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(
                                        color: cs.outlineVariant),
                                  ),
                                  child: Text(
                                    '${visibility.visibility.emoji} ${visibility.visibility.label}',
                                    style: TextStyle(
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w700,
                                      color: cs.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(title.isEmpty ? '(제목 미입력)' : title,
                              style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  color: cs.onSurface)),
                          const SizedBox(height: 2),
                          Text(place ?? address ?? '',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: cs.onSurfaceVariant)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          // 업로드 진행 상태 (압축/업로드 % + 막대)
          if (uploading) ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    uploadStatus.isEmpty ? '등록 중...' : uploadStatus,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ),
                if (uploadProgress > 0)
                  Text('${(uploadProgress * 100).round()}%',
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: AppColors.primary)),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: uploadProgress > 0 ? uploadProgress : null,
                minHeight: 6,
                backgroundColor:
                    Theme.of(context).colorScheme.surfaceContainerHighest,
                valueColor:
                    const AlwaysStoppedAnimation<Color>(AppColors.primary),
              ),
            ),
            const SizedBox(height: 12),
          ],
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: uploading ? null : onPublish,
              icon: uploading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.push_pin, size: 18),
              label: Text(uploading ? '등록 중...' : '핀 올리기'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                minimumSize: const Size(double.infinity, 52),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.md)),
                textStyle: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── 주소 검색 시트 (자동완성 리스트) ───────────────────────────────
class _AddressSearchSheet extends StatefulWidget {
  const _AddressSearchSheet();

  @override
  State<_AddressSearchSheet> createState() => _AddressSearchSheetState();
}

class _AddressSearchSheetState extends State<_AddressSearchSheet> {
  final _ctrl = TextEditingController();
  Timer? _debounce;
  bool _searching = false;
  List<({double lat, double lng, String display})> _results = [];

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    final q = v.trim();
    if (q.length < 2) {
      setState(() => _results = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 500), () => _search(q));
  }

  Future<void> _search(String q) async {
    setState(() => _searching = true);
    final hits = await GeocodingService.searchAddresses(q);
    if (!mounted) return;
    setState(() {
      _results = hits;
      _searching = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final h = MediaQuery.of(context).size.height;
    final kb = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: kb),
      child: Container(
        height: h * 0.7,
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(22)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: cs.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                controller: _ctrl,
                autofocus: true,
                onChanged: _onChanged,
                textInputAction: TextInputAction.search,
                onSubmitted: (v) {
                  final q = v.trim();
                  if (q.length >= 2) _search(q);
                },
                decoration: InputDecoration(
                  hintText: '주소·동·도로명 검색 (예: 종로구 사직로)',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searching
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2),
                          ),
                        )
                      : null,
                  filled: true,
                  fillColor: cs.surfaceContainerHighest,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            Expanded(
              child: _results.isEmpty
                  ? Center(
                      child: Text(
                        _searching
                            ? '검색 중…'
                            : (_ctrl.text.trim().length < 2
                                ? '2글자 이상 입력해주세요'
                                : '검색 결과가 없어요'),
                        style: TextStyle(
                            fontSize: 13, color: cs.onSurfaceVariant),
                      ),
                    )
                  : ListView.separated(
                      itemCount: _results.length,
                      separatorBuilder: (_, __) =>
                          const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final r = _results[i];
                        return ListTile(
                          leading: Icon(Icons.place_outlined,
                              color: cs.primary),
                          title: Text(
                            r.display,
                            style: const TextStyle(
                                fontSize: 13, height: 1.3),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () {
                            HapticFeedback.selectionClick();
                            Navigator.pop(context, r); // 위경도 포함 결과 반환
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

