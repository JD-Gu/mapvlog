import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/event.dart';
import '../services/firestore_service.dart';
import '../utils/constants.dart';
import 'map_launcher_sheet.dart';

/// 라이브 이벤트 카드 — 포스터 + 카테고리/비용칩 + 제목 + 일정 + 상태배지 +
/// 장소 + 좋아요/저장/조회 + (길찾기 / 예매·상세).
class EventCard extends StatefulWidget {
  final PinEvent event;
  final Position? currentPosition;

  /// 카드(버튼 외 영역) 탭 시 콜백 — 홈 피드에서 친구지도 이벤트 위치로 이동
  final VoidCallback? onTap;
  const EventCard(
      {super.key, required this.event, this.currentPosition, this.onTap});

  @override
  State<EventCard> createState() => _EventCardState();
}

class _EventCardState extends State<EventCard> {
  /// 세션당 이벤트별 조회수 1회만 증가
  static final Set<String> _viewedSession = {};
  static const _wd = ['월', '화', '수', '목', '금', '토', '일'];

  String? _uid;
  bool _liked = false;
  bool _saved = false;
  late int _likeCount;
  late int _saveCount;

  PinEvent get _e => widget.event;

  @override
  void initState() {
    super.initState();
    _uid = FirebaseAuth.instance.currentUser?.uid;
    _likeCount = _e.likeCount;
    _saveCount = _e.saveCount;
    // 조회수 +1 (세션당 1회)
    if (!_viewedSession.contains(_e.id)) {
      _viewedSession.add(_e.id);
      FirestoreService.incrementEventView(_e.id);
    }
    if (_uid != null) _loadState();
  }

  Future<void> _loadState() async {
    try {
      final likedSnap = await FirestoreService.watchEventLiked(_e.id, _uid!)
          .first;
      final savedSnap = await FirestoreService.watchEventSaved(_e.id, _uid!)
          .first;
      if (mounted) {
        setState(() {
          _liked = likedSnap;
          _saved = savedSnap;
        });
      }
    } catch (_) {}
  }

  Future<void> _toggleLike() async {
    if (_uid == null) return;
    final next = !_liked;
    setState(() {
      _liked = next;
      _likeCount += next ? 1 : -1;
    });
    try {
      await FirestoreService.setEventLiked(_e.id, _uid!, next);
    } catch (_) {}
  }

  Future<void> _toggleSave() async {
    if (_uid == null) return;
    final next = !_saved;
    setState(() {
      _saved = next;
      _saveCount += next ? 1 : -1;
    });
    try {
      await FirestoreService.setEventSaved(_e.id, _uid!, next);
    } catch (_) {}
  }

  String _fmtDt(DateTime t) {
    final w = _wd[t.weekday - 1];
    final base = '${t.month}.${t.day}($w)';
    if (_e.allDay) return base;
    final hh = t.hour.toString().padLeft(2, '0');
    final mm = t.minute.toString().padLeft(2, '0');
    return '$base $hh:$mm';
  }

  String _fmtRange() {
    final s = _e.startAt, e = _e.endAt;
    final sameDay = s.year == e.year && s.month == e.month && s.day == e.day;
    if (sameDay && !_e.allDay) {
      final hh = e.hour.toString().padLeft(2, '0');
      final mm = e.minute.toString().padLeft(2, '0');
      return '${_fmtDt(s)} ~ $hh:$mm';
    }
    return '${_fmtDt(s)} ~ ${_fmtDt(e)}';
  }

  String? _distanceLabel() {
    final p = widget.currentPosition;
    if (p == null || (_e.lat == 0 && _e.lng == 0)) return null;
    final m =
        Geolocator.distanceBetween(p.latitude, p.longitude, _e.lat, _e.lng);
    return m < 1000 ? '${m.round()}m' : '${(m / 1000).toStringAsFixed(1)}km';
  }

  Future<void> _openLink() async {
    final url = _e.link;
    if (url == null || url.isEmpty) return;
    final uri = Uri.tryParse(url.startsWith('http') ? url : 'https://$url');
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('링크를 열 수 없어요')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final c = _e.category.color;
    final badge = _e.statusBadge();
    Color badgeColor = _e.isOngoing() ? const Color(0xFF34A853) : c;
    if (badge == '오늘 종료') badgeColor = const Color(0xFFFB8C00);
    final dist = _distanceLabel();
    final hasPoster = _e.posterUrl != null && _e.posterUrl!.isNotEmpty;

    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
      margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: AppShadow.card,
        border: Border.all(color: c.withValues(alpha: 0.25), width: 1.2),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasPoster)
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.network(_e.posterUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          Container(color: c.withValues(alpha: 0.12))),
                  Positioned(
                    top: 8,
                    left: 8,
                    child: _chip('${_e.category.emoji} ${_e.category.label}',
                        Colors.black.withValues(alpha: 0.55), Colors.white),
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: _chip(
                        _e.costType == EventCostType.free ? '🎁 무료' : '🎫 유료',
                        Colors.black.withValues(alpha: 0.55),
                        Colors.white),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!hasPoster)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(children: [
                      _chip('${_e.category.emoji} ${_e.category.label}',
                          c.withValues(alpha: 0.14), c),
                      const SizedBox(width: 6),
                      _chip(
                          _e.costType == EventCostType.free ? '🎁 무료' : '🎫 유료',
                          cs.surfaceContainerHighest,
                          cs.onSurfaceVariant),
                    ]),
                  ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      margin: const EdgeInsets.only(top: 2, right: 6),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: badgeColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(badge,
                          style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                              color: badgeColor)),
                    ),
                    Expanded(
                      child: Text(_e.title,
                          style: const TextStyle(
                              fontSize: 15.5,
                              fontWeight: FontWeight.w800,
                              height: 1.25),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _infoRow(Icons.calendar_today_rounded, _fmtRange(), cs),
                const SizedBox(height: 4),
                _infoRow(
                    Icons.place_rounded,
                    [
                      if (_e.placeName.isNotEmpty) _e.placeName,
                      if (_e.address != null && _e.address!.isNotEmpty)
                        _e.address!,
                    ].join(' · '),
                    cs,
                    trailing: dist),
                if (_e.description.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(_e.description,
                      style: TextStyle(
                          fontSize: 12.5,
                          height: 1.35,
                          color: cs.onSurfaceVariant),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                ],
                if (_e.costType == EventCostType.paid &&
                    _e.price != null &&
                    _e.price!.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text('💳 ${_e.price}',
                      style: const TextStyle(
                          fontSize: 12.5, fontWeight: FontWeight.w700)),
                ],
                const SizedBox(height: 8),
                // 좋아요 / 저장 / 조회수
                Row(
                  children: [
                    _statBtn(
                      _liked ? Icons.favorite : Icons.favorite_border,
                      _liked ? AppColors.error : cs.onSurfaceVariant,
                      '$_likeCount',
                      _toggleLike,
                    ),
                    const SizedBox(width: 4),
                    _statBtn(
                      _saved ? Icons.bookmark : Icons.bookmark_border,
                      _saved ? const Color(0xFFFFC107) : cs.onSurfaceVariant,
                      _saveCount > 0 ? '$_saveCount' : '저장',
                      _toggleSave,
                    ),
                    const Spacer(),
                    Icon(Icons.visibility_outlined,
                        size: 15, color: cs.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Text('${_e.viewCount}',
                        style: TextStyle(
                            fontSize: 12, color: cs.onSurfaceVariant)),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => MapLauncherSheet.show(
                          context,
                          lat: _e.lat,
                          lng: _e.lng,
                          name: _e.placeName.isNotEmpty
                              ? _e.placeName
                              : _e.title,
                        ),
                        icon: const Icon(Icons.directions, size: 18),
                        label: const Text('길찾기'),
                        style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.primary,
                            side: BorderSide(
                                color: AppColors.primary
                                    .withValues(alpha: 0.4))),
                      ),
                    ),
                    if (_e.link != null && _e.link!.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _openLink,
                          icon: const Icon(Icons.open_in_new, size: 18),
                          label: const Text('예매·상세'),
                          style: FilledButton.styleFrom(backgroundColor: c),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
      ),
    );
  }

  Widget _statBtn(
      IconData icon, Color color, String label, VoidCallback onTap) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.full),
      onTap: _uid == null ? null : onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: color)),
          ],
        ),
      ),
    );
  }

  Widget _chip(String text, Color bg, Color fg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration:
            BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
        child: Text(text,
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w700, color: fg)),
      );

  Widget _infoRow(IconData icon, String text, ColorScheme cs,
      {String? trailing}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1.5),
          child: Icon(icon, size: 13, color: cs.onSurfaceVariant),
        ),
        const SizedBox(width: 5),
        Expanded(
          child: Text(text,
              style: TextStyle(
                  fontSize: 12.5,
                  height: 1.3,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface),
              maxLines: 2,
              overflow: TextOverflow.ellipsis),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 6),
          Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.near_me_rounded,
                size: 11, color: AppColors.primary),
            const SizedBox(width: 2),
            Text(trailing,
                style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary)),
          ]),
        ],
      ],
    );
  }
}
