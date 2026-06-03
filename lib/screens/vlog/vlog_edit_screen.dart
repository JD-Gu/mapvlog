import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:image_picker/image_picker.dart';

import '../../models/vlog.dart';
import '../../services/firebase_storage_service.dart';
import '../../services/firestore_service.dart';
import '../../services/geocoding_service.dart';
import '../../services/location_service.dart';
import '../../utils/constants.dart';
import '../../utils/marker_emojis.dart';
import '../../utils/photo_utils.dart';
import '../../widgets/emoji_picker_row.dart';
import '../../widgets/map_picker_sheet.dart';
import '../../widgets/visibility_picker.dart';

/// 브이로그(사진·영상) 단일 화면 수정 — 마법사 컴포넌트 재사용.
/// 제목·장소·이모지·사진·위치·공개범위를 한 화면에서 편집.
class VlogEditScreen extends StatefulWidget {
  final Vlog vlog;
  const VlogEditScreen({super.key, required this.vlog});

  /// 수정 화면을 풀스크린으로 띄움 (저장 성공 시 true 반환)
  static Future<bool?> open(BuildContext context, Vlog vlog) {
    return Navigator.push<bool>(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => VlogEditScreen(vlog: vlog),
      ),
    );
  }

  @override
  State<VlogEditScreen> createState() => _VlogEditScreenState();
}

class _VlogEditScreenState extends State<VlogEditScreen> {
  static const int _maxPhotos = 5;

  late final TextEditingController _titleCtrl;
  late final TextEditingController _placeCtrl;
  late String _emoji;

  late final bool _isPhotoVlog;
  late final List<String> _originalUrls;
  late final List<String> _currentUrls;
  final List<XFile> _newPhotos = [];
  final List<Uint8List?> _newPreviews = [];

  Position? _position;
  String? _address;
  bool _locating = false;

  late VisibilitySelection _vis;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final v = widget.vlog;
    _titleCtrl = TextEditingController(text: v.title);
    _placeCtrl = TextEditingController(text: v.placeName);
    _emoji = v.markerEmoji ?? MarkerEmojis.defaultEmoji;
    _isPhotoVlog = v.isPhoto && !v.hasVideo;
    _originalUrls = List<String>.from(v.displayPhotoUrls);
    _currentUrls = List<String>.from(_originalUrls);
    _address = v.address;
    _position = Position(
      latitude: v.lat,
      longitude: v.lng,
      timestamp: DateTime.now(),
      accuracy: 0,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );
    _vis = VisibilitySelection(
      visibility: v.visibility,
      groupIds: v.visibleGroupIds,
      visibleUids: v.visibleUids,
    );
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _placeCtrl.dispose();
    super.dispose();
  }

  int get _totalPhotos => _currentUrls.length + _newPhotos.length;

  Future<void> _addPhotos() async {
    final picker = ImagePicker();
    try {
      final added =
          await picker.pickMultiImage(limit: _maxPhotos - _totalPhotos);
      if (added.isEmpty) return;
      final previews = await Future.wait(added.map((f) async {
        try {
          return await f.readAsBytes();
        } catch (_) {
          return null;
        }
      }));
      setState(() {
        _newPhotos.addAll(added);
        _newPreviews.addAll(previews);
      });
    } catch (_) {}
  }

  Future<void> _refreshLocation() async {
    if (_locating) return;
    HapticFeedback.selectionClick();
    setState(() {
      _locating = true;
      _address = null;
    });
    try {
      final pos = await LocationService.getCurrentPosition(context);
      if (!mounted) return;
      setState(() => _position = pos ?? _position);
      if (pos != null) await _resolveAddress(pos);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

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
      _address = null;
    });
    await _resolveAddress(_position!);
  }

  /// 좌표 → 주소 (웹/모바일 공용)
  Future<void> _resolveAddress(Position pos) async {
    try {
      final addr = await GeocodingService.reverseToRoadAddress(
          pos.latitude, pos.longitude);
      if (mounted && addr != null && addr.isNotEmpty) {
        setState(() => _address = addr);
        return;
      }
      if (!kIsWeb) {
        final places =
            await placemarkFromCoordinates(pos.latitude, pos.longitude);
        if (!mounted || places.isEmpty) return;
        final p = places.first;
        final parts = [
          if (p.administrativeArea?.isNotEmpty ?? false) p.administrativeArea,
          if (p.subLocality?.isNotEmpty ?? false) p.subLocality,
          if (p.thoroughfare?.isNotEmpty ?? false) p.thoroughfare,
        ].whereType<String>().toList();
        if (parts.isNotEmpty) setState(() => _address = parts.join(' '));
      }
    } catch (_) {}
  }

  void _toast(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? AppColors.error : AppColors.secondary,
      duration: const Duration(seconds: 2),
    ));
  }

  Future<void> _save() async {
    final title = _titleCtrl.text.trim();
    final place = _placeCtrl.text.trim();
    if (title.isEmpty || place.isEmpty) {
      _toast('제목과 장소명을 입력해 주세요', error: true);
      return;
    }
    if (_isPhotoVlog && _totalPhotos == 0) {
      _toast('사진은 최소 1장 이상 필요합니다', error: true);
      return;
    }
    setState(() => _saving = true);
    HapticFeedback.mediumImpact();
    try {
      List<String>? finalUrls;
      String? finalThumb;
      final hasPhotoChange = _isPhotoVlog &&
          (_newPhotos.isNotEmpty ||
              _currentUrls.length != _originalUrls.length);

      if (hasPhotoChange) {
        final userId = FirebaseAuth.instance.currentUser?.uid ?? 'anonymous';
        final id = DateTime.now().millisecondsSinceEpoch.toString();
        final uploaded = <String>[];
        for (int i = 0; i < _newPhotos.length; i++) {
          final bytes = await correctPhotoRotation(_newPhotos[i]);
          final path =
              FirebaseStorageService.photoPath(userId, '${id}_edit_${i + 1}.jpg');
          final url = await FirebaseStorageService.uploadBytes(
            bytes: bytes,
            path: path,
            contentType: 'image/jpeg',
          );
          uploaded.add(url);
        }
        finalUrls = [..._currentUrls, ...uploaded];
        finalThumb = finalUrls.isNotEmpty ? finalUrls.first : '';
        // 제거된 기존 사진 Storage 정리 (best effort)
        for (final url in _originalUrls.where((u) => !_currentUrls.contains(u))) {
          await FirestoreService.deletePhotoFromStorage(url);
        }
      }

      await FirestoreService.updateVlog(
        id: widget.vlog.id,
        title: title,
        placeName: place,
        markerColor: MarkerEmojis.colorOf(_emoji).toARGB32(),
        markerEmoji: _emoji,
        photoUrls: finalUrls,
        thumbnailUrl: finalThumb,
        lat: _position?.latitude,
        lng: _position?.longitude,
        address: _address,
        visibility: _vis.visibility,
        visibleGroupIds: _vis.groupIds,
        visibleUids: _vis.visibleUids,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
      _toast('✅ 수정됐습니다');
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _toast('수정 실패: $e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.edit, color: Color(0xFFF57C00), size: 20),
            const SizedBox(width: 8),
            const Text('기록 수정',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          ],
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          children: [
            // ── 사진 편집 (사진 vlog만) ─────────────────────────────
            if (_isPhotoVlog) ...[
              Text('사진 ($_totalPhotos/$_maxPhotos)',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurfaceVariant)),
              const SizedBox(height: 8),
              SizedBox(
                height: 84,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (int i = 0; i < _currentUrls.length; i++)
                      _PhotoTile(
                        index: i,
                        image: Image.network(_currentUrls[i], fit: BoxFit.cover),
                        showRemove: _totalPhotos > 1,
                        onRemove: () =>
                            setState(() => _currentUrls.removeAt(i)),
                      ),
                    for (int i = 0; i < _newPhotos.length; i++)
                      _PhotoTile(
                        index: _currentUrls.length + i,
                        isNew: true,
                        image: _newPreviews[i] != null
                            ? Image.memory(_newPreviews[i]!, fit: BoxFit.cover)
                            : const Icon(Icons.photo),
                        showRemove: _totalPhotos > 1,
                        onRemove: () => setState(() {
                          _newPhotos.removeAt(i);
                          _newPreviews.removeAt(i);
                        }),
                      ),
                    if (_totalPhotos < _maxPhotos)
                      GestureDetector(
                        onTap: _addPhotos,
                        child: Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            border: Border.all(
                                color: AppColors.primary.withValues(alpha: 0.5),
                                width: 1.5),
                            borderRadius: BorderRadius.circular(10),
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
                                      color: AppColors.primary,
                                      fontWeight: FontWeight.w700)),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
            ],

            // ── 제목 ─────────────────────────────────────────────────
            TextField(
              controller: _titleCtrl,
              decoration: const InputDecoration(
                  labelText: '제목 *', border: OutlineInputBorder()),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _placeCtrl,
              decoration: const InputDecoration(
                  labelText: '장소명 *', border: OutlineInputBorder()),
              textInputAction: TextInputAction.done,
            ),
            const SizedBox(height: 18),

            // ── 카테고리(이모지) ──────────────────────────────────────
            Text('카테고리',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurfaceVariant)),
            const SizedBox(height: 8),
            EmojiPickerRow(
              selected: _emoji,
              onPick: (e) => setState(() => _emoji = e),
              maxHeight: 200,
              suggestionText: '${_titleCtrl.text} ${_placeCtrl.text}',
            ),
            const SizedBox(height: 18),

            // ── 위치 ─────────────────────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: cs.secondary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: cs.secondary.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  if (_locating)
                    SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: cs.secondary))
                  else
                    Icon(Icons.place, size: 16, color: cs.secondary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _locating
                          ? '위치 확인 중…'
                          : (_address != null && _address!.isNotEmpty
                              ? _address!
                              : (_position != null
                                  ? '${_position!.latitude.toStringAsFixed(5)}, ${_position!.longitude.toStringAsFixed(5)}'
                                  : '위치를 확인할 수 없어요')),
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
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: LocationActionButton(
                    icon: Icons.my_location,
                    label: '현재위치 새로고침',
                    onTap: _refreshLocation,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: LocationActionButton(
                    icon: Icons.map_outlined,
                    label: '지도에서 선택',
                    onTap: _pickOnMap,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),

            // ── 공개 범위 ─────────────────────────────────────────────
            Row(
              children: [
                Text('공개 범위',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurfaceVariant)),
                const SizedBox(width: 8),
                VisibilityPickerChip(
                  selection: _vis,
                  onChanged: (v) => setState(() => _vis = v),
                  dense: true,
                ),
              ],
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.check, size: 18),
            label: Text(_saving ? '저장 중...' : '저장'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              minimumSize: const Size(double.infinity, 52),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md)),
            ),
          ),
        ),
      ),
    );
  }
}

/// 사진 편집 썸네일 (번호 + NEW 배지 + 제거)
class _PhotoTile extends StatelessWidget {
  final int index;
  final Widget image;
  final bool showRemove;
  final bool isNew;
  final VoidCallback onRemove;
  const _PhotoTile({
    required this.index,
    required this.image,
    required this.showRemove,
    required this.onRemove,
    this.isNew = false,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          width: 72,
          height: 72,
          margin: const EdgeInsets.only(right: 6),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            border: isNew
                ? Border.all(
                    color: AppColors.secondary.withValues(alpha: 0.7),
                    width: 1.5)
                : null,
          ),
          child: image,
        ),
        Positioned(
          bottom: 3,
          left: 3,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
                color: Colors.black54, borderRadius: BorderRadius.circular(4)),
            child: Text('${index + 1}',
                style: const TextStyle(color: Colors.white, fontSize: 9)),
          ),
        ),
        if (isNew)
          Positioned(
            top: 3,
            left: 3,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                  color: AppColors.secondary,
                  borderRadius: BorderRadius.circular(4)),
              child: const Text('NEW',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 8,
                      fontWeight: FontWeight.w700)),
            ),
          ),
        if (showRemove)
          Positioned(
            top: 0,
            right: 6,
            child: GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                onRemove();
              },
              child: Container(
                decoration: const BoxDecoration(
                    color: Colors.black54, shape: BoxShape.circle),
                padding: const EdgeInsets.all(2),
                child: const Icon(Icons.close, color: Colors.white, size: 14),
              ),
            ),
          ),
      ],
    );
  }
}
