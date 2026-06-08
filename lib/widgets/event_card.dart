import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/event.dart';
import '../utils/constants.dart';
import 'map_launcher_sheet.dart';

/// 라이브 이벤트 카드 — 포스터 + 카테고리/비용칩 + 제목 + 일정 + 상태배지 +
/// 장소 + (길찾기 / 예매·상세) 액션.
class EventCard extends StatelessWidget {
  final PinEvent event;
  final Position? currentPosition;
  const EventCard({super.key, required this.event, this.currentPosition});

  static const _wd = ['월', '화', '수', '목', '금', '토', '일'];

  String _fmtDt(DateTime t) {
    final w = _wd[t.weekday - 1];
    final base = '${t.month}.${t.day}($w)';
    if (event.allDay) return base;
    final hh = t.hour.toString().padLeft(2, '0');
    final mm = t.minute.toString().padLeft(2, '0');
    return '$base $hh:$mm';
  }

  String _fmtRange() {
    final s = event.startAt, e = event.endAt;
    final sameDay =
        s.year == e.year && s.month == e.month && s.day == e.day;
    if (sameDay && !event.allDay) {
      final hh = e.hour.toString().padLeft(2, '0');
      final mm = e.minute.toString().padLeft(2, '0');
      return '${_fmtDt(s)} ~ $hh:$mm';
    }
    return '${_fmtDt(s)} ~ ${_fmtDt(e)}';
  }

  String? _distanceLabel() {
    final p = currentPosition;
    if (p == null || (event.lat == 0 && event.lng == 0)) return null;
    final m = Geolocator.distanceBetween(
        p.latitude, p.longitude, event.lat, event.lng);
    return m < 1000 ? '${m.round()}m' : '${(m / 1000).toStringAsFixed(1)}km';
  }

  Future<void> _openLink(BuildContext context) async {
    final url = event.link;
    if (url == null || url.isEmpty) return;
    final uri = Uri.tryParse(url.startsWith('http') ? url : 'https://$url');
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('링크를 열 수 없어요')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final c = event.category.color;
    final badge = event.statusBadge();
    Color badgeColor = event.isOngoing() ? const Color(0xFF34A853) : c;
    if (badge == '오늘 종료') badgeColor = const Color(0xFFFB8C00);
    final dist = _distanceLabel();
    final hasPoster =
        event.posterUrl != null && event.posterUrl!.isNotEmpty;

    return Container(
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
          // 포스터
          if (hasPoster)
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.network(event.posterUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          Container(color: c.withValues(alpha: 0.12))),
                  Positioned(
                    top: 8,
                    left: 8,
                    child: _chip('${event.category.emoji} ${event.category.label}',
                        Colors.black.withValues(alpha: 0.55), Colors.white),
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: _chip(
                        event.costType == EventCostType.free ? '🎁 무료' : '🎫 유료',
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
                // 포스터 없을 때 카테고리/비용 칩 (텍스트 위)
                if (!hasPoster)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(children: [
                      _chip(
                          '${event.category.emoji} ${event.category.label}',
                          c.withValues(alpha: 0.14),
                          c),
                      const SizedBox(width: 6),
                      _chip(
                          event.costType == EventCostType.free
                              ? '🎁 무료'
                              : '🎫 유료',
                          cs.surfaceContainerHighest,
                          cs.onSurfaceVariant),
                    ]),
                  ),
                // 상태배지 + 제목
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
                      child: Text(event.title,
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
                      if (event.placeName.isNotEmpty) event.placeName,
                      if (event.address != null && event.address!.isNotEmpty)
                        event.address!,
                    ].join(' · '),
                    cs,
                    trailing: dist),
                if (event.description.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(event.description,
                      style: TextStyle(
                          fontSize: 12.5,
                          height: 1.35,
                          color: cs.onSurfaceVariant),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                ],
                if (event.costType == EventCostType.paid &&
                    event.price != null &&
                    event.price!.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text('💳 ${event.price}',
                      style: const TextStyle(
                          fontSize: 12.5, fontWeight: FontWeight.w700)),
                ],
                const SizedBox(height: 12),
                // 액션
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => MapLauncherSheet.show(
                          context,
                          lat: event.lat,
                          lng: event.lng,
                          name: event.placeName.isNotEmpty
                              ? event.placeName
                              : event.title,
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
                    if (event.link != null && event.link!.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () => _openLink(context),
                          icon: const Icon(Icons.open_in_new, size: 18),
                          label: const Text('예매·상세'),
                          style: FilledButton.styleFrom(
                              backgroundColor: c),
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
