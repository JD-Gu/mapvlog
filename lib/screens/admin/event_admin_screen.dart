import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../models/event.dart';
import '../../services/firestore_service.dart';
import '../../services/user_status_service.dart';
import '../../utils/constants.dart';
import '../../utils/event_permission.dart';
import 'event_edit_screen.dart';

/// 이벤트 관리(목록·수정·삭제·추가) — Super=전체 / Event Master=담당 카테고리.
class EventAdminScreen extends StatelessWidget {
  const EventAdminScreen({super.key});

  static Future<void> open(BuildContext context) {
    return Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const EventAdminScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    return Scaffold(
      appBar: AppBar(
        title: const Text('이벤트 관리'),
        backgroundColor: cs.surface,
      ),
      body: StreamBuilder<({String role, List<String> cats})>(
        stream: UserStatusService.watchEventRole(uid),
        builder: (context, roleSnap) {
          final role = roleSnap.data?.role ?? '';
          final cats = roleSnap.data?.cats ?? const <String>[];
          final allowed = EventPermission.allowedCategories(role, cats);
          final isSuper = EventPermission.isSuper;
          return _buildBody(context, cs, allowed, isSuper);
        },
      ),
    );
  }

  Widget _buildBody(BuildContext context, ColorScheme cs,
      List<EventCategory> allowed, bool isSuper) {
    return Scaffold(
      floatingActionButton: allowed.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: () =>
                  EventEditScreen.open(context, allowedCategories: allowed),
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add),
              label: const Text('새 이벤트'),
            ),
      body: StreamBuilder<List<PinEvent>>(
        stream: FirestoreService.watchManageableEvents(
            categories: isSuper ? null : allowed.toSet()),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final events = snap.data ?? [];
          if (events.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('🎪', style: TextStyle(fontSize: 44)),
                    const SizedBox(height: 12),
                    const Text('등록한 이벤트가 없어요',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    Text('우측 하단 + 로 첫 이벤트를 등록하세요',
                        style: TextStyle(
                            fontSize: 12, color: cs.onSurfaceVariant)),
                  ],
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
            itemCount: events.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) =>
                _EventAdminTile(event: events[i], allowed: allowed),
          );
        },
      ),
    );
  }
}

class _EventAdminTile extends StatelessWidget {
  final PinEvent event;
  final List<EventCategory> allowed;
  const _EventAdminTile({required this.event, required this.allowed});

  Future<void> _delete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('이벤트 삭제'),
        content: Text('"${event.title}"을(를) 삭제할까요?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('취소')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await FirestoreService.deleteEvent(event.id);
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('삭제됐어요')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final c = event.category.color;
    final ended = event.isEnded();
    return Opacity(
      opacity: ended ? 0.55 : 1,
      child: Material(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => EventEditScreen.open(context,
              editing: event, allowedCategories: allowed),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: c.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                    image: (event.posterUrl != null &&
                            event.posterUrl!.isNotEmpty)
                        ? DecorationImage(
                            image: NetworkImage(event.posterUrl!),
                            fit: BoxFit.cover)
                        : null,
                  ),
                  alignment: Alignment.center,
                  child: (event.posterUrl == null || event.posterUrl!.isEmpty)
                      ? Text(event.category.emoji,
                          style: const TextStyle(fontSize: 24))
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          _badge(event.statusBadge(), ended ? Colors.grey : c),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(event.title,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w800, fontSize: 14),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${event.category.emoji} ${event.category.label} · 📍 ${event.placeName}',
                        style:
                            TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(_range(event),
                          style: TextStyle(
                              fontSize: 11, color: cs.onSurfaceVariant)),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.delete_outline,
                      size: 20, color: cs.onSurfaceVariant),
                  onPressed: () => _delete(context),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _badge(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(text,
            style: TextStyle(
                fontSize: 10, fontWeight: FontWeight.w800, color: color)),
      );

  String _range(PinEvent e) {
    String f(DateTime d) {
      final mm = d.month.toString().padLeft(2, '0');
      final dd = d.day.toString().padLeft(2, '0');
      if (e.allDay) return '$mm.$dd';
      final h = d.hour.toString().padLeft(2, '0');
      final m = d.minute.toString().padLeft(2, '0');
      return '$mm.$dd $h:$m';
    }

    return '📅 ${f(e.startAt)} ~ ${f(e.endAt)}';
  }
}
