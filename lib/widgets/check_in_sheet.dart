import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../models/vlog.dart';
import '../services/firestore_service.dart';
import '../services/geocoding_service.dart';
import '../services/location_service.dart';
import '../utils/constants.dart';
import '../utils/marker_emojis.dart';
import 'map_picker_sheet.dart';
import 'visibility_picker.dart';

/// 빠른 체크인 시트 — 이모지 + 한 줄 메시지 + 현재 GPS를 즉시 vlog로 저장
///
/// 미디어 없이 위치만 기록. `Vlog.isCheckIn=true` 로 표시되어 피드/지도에서
/// 다르게 렌더링 가능. 일반 vlog와 동일하게 좋아요·댓글 가능.
class CheckInSheet {
  static const _presetEmojis = ['📍', '🍕', '☕', '🍻', '🏃', '📚', '🚗', '🎉', '💼', '🏠'];

  /// 새 체크인은 [editing] null, 기존 체크인 수정은 [editing] 에 해당 Vlog 전달.
  static Future<void> open(BuildContext context, {Vlog? editing}) async {
    HapticFeedback.mediumImpact();
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _CheckInView(editing: editing),
    );
  }
}

class _CheckInView extends StatefulWidget {
  final Vlog? editing;
  const _CheckInView({this.editing});

  @override
  State<_CheckInView> createState() => _CheckInViewState();
}

class _CheckInViewState extends State<_CheckInView> {
  final _msgCtrl = TextEditingController();
  String _emoji = '📍';
  VisibilitySelection _vis = VisibilitySelection.public;
  String _expiry = '6시간'; // 지도 표시·자동삭제 기준 시간
  bool _expiryTouched = false; // 수정 시 사용자가 표시시간을 바꿨는지
  bool _emojiManuallyPicked = false; // 사용자가 직접 고른 후엔 자동 추천 중단
  Position? _position;
  String? _address;
  bool _locating = true;
  bool _saving = false;
  String? _error;

  bool get _isEdit => widget.editing != null;

  @override
  void initState() {
    super.initState();
    final edit = widget.editing;
    if (edit != null) {
      // 수정 모드 — 기존 값 프리필 (현재 위치 자동 조회 안 함)
      _emoji = edit.markerEmoji ?? '📍';
      _emojiManuallyPicked = true;
      _msgCtrl.text = _messageFromTitle(edit);
      _address = edit.address;
      _position = Position(
        latitude: edit.lat,
        longitude: edit.lng,
        timestamp: DateTime.now(),
        accuracy: 0,
        altitude: 0,
        altitudeAccuracy: 0,
        heading: 0,
        headingAccuracy: 0,
        speed: 0,
        speedAccuracy: 0,
      );
      _locating = false;
      _vis = VisibilitySelection(
        visibility: edit.visibility,
        groupIds: edit.visibleGroupIds,
        visibleUids: edit.visibleUids,
      );
    } else {
      _fetchLocation();
    }
    _msgCtrl.addListener(_onMessageChanged);
  }

  /// 저장된 title("$emoji $msg" 또는 "$emoji 여기 있어요")에서 메시지만 복원
  String _messageFromTitle(Vlog v) {
    var t = v.title;
    final e = v.markerEmoji ?? '';
    if (e.isNotEmpty && t.startsWith(e)) t = t.substring(e.length);
    t = t.trim();
    if (t == '여기 있어요') return '';
    return t;
  }

  @override
  void dispose() {
    _msgCtrl.removeListener(_onMessageChanged);
    _msgCtrl.dispose();
    super.dispose();
  }

  /// 메시지에서 키워드 추출 → 이모지 자동 변경 (사용자 수동 선택 전)
  void _onMessageChanged() {
    if (_emojiManuallyPicked) return;
    final suggested = MarkerEmojis.suggestFor(_msgCtrl.text);
    if (suggested != null && suggested != _emoji) {
      setState(() => _emoji = suggested);
    }
  }

  Future<void> _fetchLocation() async {
    try {
      final pos = await LocationService.getCurrentPosition(context);
      if (!mounted) return;
      setState(() {
        _position = pos;
        _locating = false;
        if (pos == null) _error = '위치 권한이 필요해요';
      });
      if (pos != null) _reverseGeocode(pos);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _locating = false;
        _error = '위치를 가져올 수 없어요';
      });
    }
  }

  /// 좌표 → 주소 변환 (실패해도 무시 — 좌표만 있어도 체크인 가능)
  /// 웹/모바일 공용: Nominatim(GeocodingService) 우선, 모바일은 기기 Geocoder fallback.
  Future<void> _reverseGeocode(Position pos) async {
    try {
      // 1) Nominatim 도로명 주소 (웹 포함 동작)
      final addr = await GeocodingService.reverseToRoadAddress(
          pos.latitude, pos.longitude);
      if (mounted && addr != null && addr.isNotEmpty) {
        setState(() => _address = addr);
        return;
      }
      // 2) 모바일 fallback — 기기 Geocoder
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
        if (parts.isEmpty) return;
        setState(() => _address = parts.join(' '));
      }
    } catch (_) {
      // 실패 무시
    }
  }

  static const _expiryOptions = ['1시간', '6시간', '오늘 종료', '24시간'];

  /// 선택된 표시 시간 → 만료 시각 계산.
  /// 수정 모드에서 사용자가 표시시간을 안 건드렸으면 기존 만료시각 유지.
  DateTime _computeExpiry() {
    if (_isEdit && !_expiryTouched && widget.editing!.expiresAt != null) {
      return widget.editing!.expiresAt!;
    }
    final now = DateTime.now();
    switch (_expiry) {
      case '1시간':
        return now.add(const Duration(hours: 1));
      case '오늘 종료':
        return DateTime(now.year, now.month, now.day, 23, 59, 59);
      case '24시간':
        return now.add(const Duration(hours: 24));
      case '6시간':
      default:
        return now.add(const Duration(hours: 6));
    }
  }

  /// 현재 위치 다시 가져오기
  Future<void> _refreshLocation() async {
    if (_locating) return;
    HapticFeedback.selectionClick();
    setState(() {
      _locating = true;
      _address = null;
      _error = null;
    });
    await _fetchLocation();
  }

  /// 지도에서 위치 직접 선택
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
      _error = null;
    });
    _reverseGeocode(_position!);
  }

  Future<void> _save() async {
    final user = FirebaseAuth.instance.currentUser;
    final pos = _position;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('체크인은 로그인 후 가능해요'),
        backgroundColor: AppColors.error,
      ));
      return;
    }
    if (pos == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('위치를 먼저 가져와야 해요'),
        backgroundColor: AppColors.error,
      ));
      return;
    }
    setState(() => _saving = true);
    HapticFeedback.mediumImpact();
    try {
      final msg = _msgCtrl.text.trim();
      final title = msg.isEmpty ? '$_emoji 여기 있어요' : '$_emoji $msg';
      final placeName = msg.isEmpty ? (_address ?? '체크인') : msg;
      if (_isEdit) {
        await FirestoreService.updateVlog(
          id: widget.editing!.id,
          title: title,
          placeName: placeName,
          markerColor: MarkerEmojis.colorOf(_emoji).toARGB32(),
          markerEmoji: _emoji,
          lat: pos.latitude,
          lng: pos.longitude,
          address: _address,
          expiresAt: _computeExpiry(),
          visibility: _vis.visibility,
          visibleGroupIds: _vis.groupIds,
          visibleUids: _vis.visibleUids,
        );
      } else {
        await FirestoreService.createVlog(
          authorId: user.uid,
          authorName: user.displayName ?? user.email ?? '익명',
          authorPhotoUrl: user.photoURL,
          title: title,
          placeName: placeName,
          lat: pos.latitude,
          lng: pos.longitude,
          address: _address,
          markerEmoji: _emoji,
          isCheckIn: true,
          expiresAt: _computeExpiry(),
          visibility: _vis.visibility,
          visibleGroupIds: _vis.groupIds,
          visibleUids: _vis.visibleUids,
        );
      }
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_isEdit ? '✅ 수정됐어요' : '✅ $title — 체크인 완료'),
        backgroundColor: AppColors.secondary,
        duration: const Duration(seconds: 2),
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_isEdit ? '수정 실패: $e' : '체크인 실패: $e'),
        backgroundColor: AppColors.error,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 12,
            bottom: MediaQuery.of(context).viewInsets.bottom + 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.textDisabled.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  transitionBuilder: (child, anim) =>
                      ScaleTransition(scale: anim, child: child),
                  child: Text(
                    _emoji,
                    key: ValueKey(_emoji),
                    style: const TextStyle(fontSize: 28),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _isEdit ? '체크인 수정' : '빠른 체크인',
                    style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800),
                  ),
                ),
                if (!_emojiManuallyPicked &&
                    MarkerEmojis.suggestFor(_msgCtrl.text) != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(AppRadius.full),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.auto_awesome,
                            size: 11, color: AppColors.primary),
                        SizedBox(width: 3),
                        Text('자동',
                            style: TextStyle(
                                fontSize: 10,
                                color: AppColors.primary,
                                fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              '지금 어디 있는지 친구들에게 한번에 알려요',
              style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 16),
            // 이모지 선택
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: CheckInSheet._presetEmojis.map((e) {
                  final isSelected = _emoji == e;
                  return GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() {
                        _emoji = e;
                        _emojiManuallyPicked = true; // 자동 추천 중단
                      });
                    },
                    child: Container(
                      width: 44,
                      height: 44,
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppColors.primary.withValues(alpha: 0.15)
                            : Theme.of(context).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                        border: isSelected
                            ? Border.all(
                                color: AppColors.primary, width: 1.5)
                            : null,
                      ),
                      alignment: Alignment.center,
                      child: Text(e, style: const TextStyle(fontSize: 22)),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 14),
            // 빠른 입력 preset 메시지
            const Padding(
              padding: EdgeInsets.only(bottom: 4),
              child: Text(
                '빠른 입력',
                style: TextStyle(
                    fontSize: 10.5,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2),
              ),
            ),
            SizedBox(
              height: 32,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final t in const [
                    '점심중', '저녁중', '카페', '회식', '운동중',
                    '공부중', '쇼핑중', '데이트', '여행중', '드라이브', '집'
                  ])
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: GestureDetector(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          _msgCtrl.text = t;
                          _msgCtrl.selection = TextSelection.fromPosition(
                              TextPosition(offset: t.length));
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surfaceContainerHighest,
                            borderRadius:
                                BorderRadius.circular(AppRadius.full),
                            border: Border.all(
                                color: AppColors.textDisabled
                                    .withValues(alpha: 0.3)),
                          ),
                          child: Text(t,
                              style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600)),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            // 메시지 입력
            TextField(
              controller: _msgCtrl,
              maxLength: 40,
              decoration: InputDecoration(
                hintText: '한 줄 메시지 (선택)',
                hintStyle: const TextStyle(
                    fontSize: 13, color: AppColors.textDisabled),
                filled: true,
                fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  borderSide: BorderSide.none,
                ),
                counterText: '',
              ),
            ),
            const SizedBox(height: 14),
            // 위치 표시 (좌표 + 주소)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.my_location,
                          size: 16, color: AppColors.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _locating
                            ? const Text('현재 위치를 가져오는 중...',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textSecondary))
                            : _position == null
                                ? Text(_error ?? '위치 확인 실패',
                                    style: const TextStyle(
                                        fontSize: 12,
                                        color: AppColors.error))
                                : Text(
                                    '${_position!.latitude.toStringAsFixed(5)}, ${_position!.longitude.toStringAsFixed(5)}',
                                    style: const TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w500),
                                  ),
                      ),
                      if (_locating)
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: AppColors.primary),
                        ),
                    ],
                  ),
                  if (_address != null && _address!.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.place,
                            size: 13, color: AppColors.textSecondary),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            _address!,
                            style: const TextStyle(
                                fontSize: 11.5,
                                color: AppColors.textSecondary),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 10),
            // 위치 보정 — 새로고침 / 지도에서 선택 (마법사와 동일 UI)
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
            const SizedBox(height: 14),
            // 표시 시간(만료) 선택
            Row(
              children: [
                const Icon(Icons.timer_outlined,
                    size: 15, color: AppColors.textSecondary),
                const SizedBox(width: 6),
                const Text('지도 표시 시간',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textSecondary)),
                const Spacer(),
                Text(
                  '이 시간이 지나면 자동으로 사라져요',
                  style: TextStyle(
                      fontSize: 10,
                      color: AppColors.textDisabled,
                      fontStyle: FontStyle.italic),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: _expiryOptions.map((opt) {
                final selected = _expiry == opt;
                return Expanded(
                  child: GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() {
                        _expiry = opt;
                        _expiryTouched = true;
                      });
                    },
                    child: Container(
                      margin: const EdgeInsets.only(right: 6),
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      decoration: BoxDecoration(
                        color: selected
                            ? AppColors.primary.withValues(alpha: 0.12)
                            : Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                        border: selected
                            ? Border.all(
                                color: AppColors.primary, width: 1.5)
                            : null,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        opt,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight:
                              selected ? FontWeight.w800 : FontWeight.w600,
                          color: selected
                              ? AppColors.primary
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 14),
            // 공개 범위 선택 칩
            Row(
              children: [
                const Text('공개 범위',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textSecondary)),
                const SizedBox(width: 8),
                VisibilityPickerChip(
                  selection: _vis,
                  onChanged: (v) => setState(() => _vis = v),
                  dense: true,
                ),
              ],
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: (_saving || _locating || _position == null)
                  ? null
                  : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : Icon(_isEdit ? Icons.check : Icons.push_pin, size: 18),
              label: Text(_saving
                  ? (_isEdit ? '저장 중...' : '체크인 중...')
                  : (_isEdit ? '저장' : '체크인')),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              '체크인은 일반 피드와 친구지도에 표시됩니다',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 11,
                  color: AppColors.textDisabled,
                  fontStyle: FontStyle.italic),
            ),
          ],
        ),
      ),
    );
  }
}
