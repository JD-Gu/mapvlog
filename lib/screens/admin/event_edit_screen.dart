import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:image_picker/image_picker.dart';

import '../../models/event.dart';
import '../../services/firebase_storage_service.dart';
import '../../services/firestore_service.dart';
import '../../services/geocoding_service.dart';
import '../../utils/constants.dart';
import '../../widgets/map_picker_sheet.dart';

/// 마스터 전용 — 이벤트 등록/수정 폼.
class EventEditScreen extends StatefulWidget {
  final PinEvent? editing;
  const EventEditScreen({super.key, this.editing});

  static Future<bool?> open(BuildContext context, {PinEvent? editing}) {
    return Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => EventEditScreen(editing: editing)),
    );
  }

  @override
  State<EventEditScreen> createState() => _EventEditScreenState();
}

class _EventEditScreenState extends State<EventEditScreen> {
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _placeCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _linkCtrl = TextEditingController();

  EventCategory _category = EventCategory.festival;
  double? _lat;
  double? _lng;
  String? _address;
  late DateTime _startAt;
  late DateTime _endAt;
  bool _allDay = false;
  EventCostType _costType = EventCostType.free;
  XFile? _posterFile;
  Uint8List? _posterBytes; // 미리보기용 (웹·모바일 공용)
  String? _existingPosterUrl;
  bool _saving = false;

  bool get _isEdit => widget.editing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.editing;
    final now = DateTime.now();
    if (e != null) {
      _titleCtrl.text = e.title;
      _descCtrl.text = e.description;
      _placeCtrl.text = e.placeName;
      _priceCtrl.text = e.price ?? '';
      _linkCtrl.text = e.link ?? '';
      _category = e.category == EventCategory.daily
          ? EventCategory.festival
          : e.category;
      _lat = e.lat;
      _lng = e.lng;
      _address = e.address;
      _startAt = e.startAt;
      _endAt = e.endAt;
      _allDay = e.allDay;
      _costType = e.costType;
      _existingPosterUrl = e.posterUrl;
    } else {
      _startAt = DateTime(now.year, now.month, now.day, now.hour + 1);
      _endAt = _startAt.add(const Duration(hours: 3));
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _placeCtrl.dispose();
    _priceCtrl.dispose();
    _linkCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickPoster() async {
    final x = await ImagePicker()
        .pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (x == null) return;
    final bytes = await x.readAsBytes();
    if (mounted) {
      setState(() {
        _posterFile = x;
        _posterBytes = bytes;
      });
    }
  }

  Future<void> _pickLocation() async {
    final init = LatLng(_lat ?? 37.5665, _lng ?? 126.9780);
    final picked = await MapPickerSheet.open(context, initial: init);
    if (picked == null) return;
    setState(() {
      _lat = picked.latitude;
      _lng = picked.longitude;
    });
    final addr =
        await GeocodingService.reverseToRoadAddress(picked.latitude, picked.longitude);
    if (mounted && addr != null) setState(() => _address = addr);
  }

  Future<void> _pickDateTime({required bool isStart}) async {
    final base = isStart ? _startAt : _endAt;
    final date = await showDatePicker(
      context: context,
      initialDate: base,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 730)),
    );
    if (date == null || !mounted) return;
    TimeOfDay? time = TimeOfDay.fromDateTime(base);
    if (!_allDay) {
      time = await showTimePicker(
          context: context, initialTime: TimeOfDay.fromDateTime(base));
      if (time == null) return;
    }
    final dt = DateTime(date.year, date.month, date.day,
        _allDay ? 0 : time.hour, _allDay ? 0 : time.minute);
    setState(() {
      if (isStart) {
        _startAt = dt;
        if (_endAt.isBefore(_startAt)) {
          _endAt = _startAt.add(const Duration(hours: 2));
        }
      } else {
        _endAt = dt;
      }
    });
  }

  String _fmtDt(DateTime d) {
    final mm = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    if (_allDay) return '$mm.$dd';
    final h = d.hour.toString().padLeft(2, '0');
    final m = d.minute.toString().padLeft(2, '0');
    return '$mm.$dd $h:$m';
  }

  Future<void> _save() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    if (_titleCtrl.text.trim().isEmpty) {
      _snack('제목을 입력하세요');
      return;
    }
    if (_lat == null || _lng == null) {
      _snack('지도에서 위치를 선택하세요');
      return;
    }
    if (_endAt.isBefore(_startAt)) {
      _snack('종료가 시작보다 빠릅니다');
      return;
    }
    setState(() => _saving = true);
    try {
      String? posterUrl = _existingPosterUrl;
      if (_posterFile != null) {
        final path =
            'events/${DateTime.now().millisecondsSinceEpoch}_poster.jpg';
        posterUrl = await FirebaseStorageService.uploadXFile(
          xfile: _posterFile,
          path: path,
          contentType: 'image/jpeg',
        );
      }
      final e = PinEvent(
        id: widget.editing?.id ?? '',
        title: _titleCtrl.text.trim(),
        category: _category,
        description: _descCtrl.text.trim(),
        posterUrl: posterUrl,
        lat: _lat!,
        lng: _lng!,
        placeName: _placeCtrl.text.trim(),
        address: _address,
        startAt: _startAt,
        endAt: _endAt,
        allDay: _allDay,
        costType: _costType,
        price: _costType == EventCostType.paid
            ? (_priceCtrl.text.trim().isEmpty ? null : _priceCtrl.text.trim())
            : null,
        link: _linkCtrl.text.trim().isEmpty ? null : _linkCtrl.text.trim(),
        createdBy: uid,
        createdAt: widget.editing?.createdAt ?? DateTime.now(),
      );
      if (_isEdit) {
        await FirestoreService.updateEvent(widget.editing!.id, e);
      } else {
        await FirestoreService.createEvent(e);
      }
      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_isEdit ? '이벤트가 수정됐어요' : '이벤트가 등록됐어요')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        _snack('저장 실패: $e');
      }
    }
  }

  void _snack(String m) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? '이벤트 수정' : '이벤트 등록'),
        backgroundColor: cs.surface,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          _label('카테고리'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: EventCategory.adminCategories.map((c) {
              final sel = _category == c;
              return GestureDetector(
                onTap: () => setState(() => _category = c),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: sel
                        ? c.color.withValues(alpha: 0.15)
                        : cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(AppRadius.full),
                    border: Border.all(
                        color: sel ? c.color : Colors.transparent, width: 1.4),
                  ),
                  child: Text('${c.emoji} ${c.label}',
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: sel ? c.color : cs.onSurfaceVariant)),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          _label('제목'),
          TextField(
            controller: _titleCtrl,
            decoration: _dec('예: 한강 불꽃축제'),
            maxLength: 50,
          ),
          _label('설명'),
          TextField(
            controller: _descCtrl,
            decoration: _dec('이벤트 소개 (선택)'),
            maxLines: 3,
            maxLength: 300,
          ),
          const SizedBox(height: 8),
          _label('포스터 (선택)'),
          GestureDetector(
            onTap: _pickPoster,
            child: Container(
              height: 160,
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
                image: _posterPreview(),
              ),
              alignment: Alignment.center,
              child: (_posterFile == null &&
                      (_existingPosterUrl == null ||
                          _existingPosterUrl!.isEmpty))
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.add_photo_alternate_outlined,
                            size: 32, color: cs.onSurfaceVariant),
                        const SizedBox(height: 6),
                        Text('포스터 이미지 선택',
                            style: TextStyle(
                                fontSize: 12, color: cs.onSurfaceVariant)),
                      ],
                    )
                  : null,
            ),
          ),
          const SizedBox(height: 16),
          _label('위치'),
          OutlinedButton.icon(
            onPressed: _pickLocation,
            icon: const Icon(Icons.map_outlined, size: 18),
            label: Text(_lat == null
                ? '지도에서 위치 선택'
                : '위치 선택됨 (${_lat!.toStringAsFixed(4)}, ${_lng!.toStringAsFixed(4)})'),
            style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 44)),
          ),
          if (_address != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('📍 $_address',
                  style:
                      TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
            ),
          const SizedBox(height: 8),
          _label('장소명'),
          TextField(
            controller: _placeCtrl,
            decoration: _dec('예: 여의도 한강공원'),
            maxLength: 40,
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            value: _allDay,
            onChanged: (v) => setState(() => _allDay = v),
            title: const Text('종일 (시간 없이 날짜만)'),
            contentPadding: EdgeInsets.zero,
          ),
          Row(
            children: [
              Expanded(
                  child: _dateTile('시작', _startAt,
                      () => _pickDateTime(isStart: true))),
              const SizedBox(width: 10),
              Expanded(
                  child: _dateTile(
                      '종료', _endAt, () => _pickDateTime(isStart: false))),
            ],
          ),
          const SizedBox(height: 16),
          _label('비용'),
          Row(
            children: EventCostType.values.map((t) {
              final sel = _costType == t;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(t == EventCostType.free ? '🎁 무료' : '🎫 유료'),
                  selected: sel,
                  onSelected: (_) => setState(() => _costType = t),
                ),
              );
            }).toList(),
          ),
          if (_costType == EventCostType.paid) ...[
            const SizedBox(height: 8),
            TextField(
              controller: _priceCtrl,
              decoration: _dec('예: 성인 15,000원'),
              maxLength: 40,
            ),
          ],
          const SizedBox(height: 8),
          _label('예매·상세 링크 (선택)'),
          TextField(
            controller: _linkCtrl,
            decoration: _dec('https://...'),
            keyboardType: TextInputType.url,
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _saving ? null : _save,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              minimumSize: const Size(double.infinity, 50),
            ),
            child: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : Text(_isEdit ? '수정 저장' : '이벤트 등록',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  DecorationImage? _posterPreview() {
    if (_posterBytes != null) {
      return DecorationImage(
          image: MemoryImage(_posterBytes!), fit: BoxFit.cover);
    }
    if (_existingPosterUrl != null && _existingPosterUrl!.isNotEmpty) {
      return DecorationImage(
          image: NetworkImage(_existingPosterUrl!), fit: BoxFit.cover);
    }
    return null;
  }

  Widget _dateTile(String label, DateTime dt, VoidCallback onTap) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
            const SizedBox(height: 2),
            Text(_fmtDt(dt),
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(top: 10, bottom: 4),
        child: Text(t,
            style: const TextStyle(
                fontSize: 12, fontWeight: FontWeight.w700)),
      );

  InputDecoration _dec(String hint) => InputDecoration(
        hintText: hint,
        isDense: true,
        border: const OutlineInputBorder(),
        counterText: '',
      );
}
