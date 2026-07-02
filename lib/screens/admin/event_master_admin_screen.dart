import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/event.dart';
import '../../services/friend_service.dart';
import '../../services/user_status_service.dart';
import '../../utils/constants.dart';

/// Super Master 전용 — 이벤트 마스터 임명/해제 + 담당 카테고리 지정.
class EventMasterAdminScreen extends StatefulWidget {
  const EventMasterAdminScreen({super.key});

  static Future<void> open(BuildContext context) => Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const EventMasterAdminScreen()));

  @override
  State<EventMasterAdminScreen> createState() => _EventMasterAdminScreenState();
}

class _EventMasterAdminScreenState extends State<EventMasterAdminScreen> {
  final _emailCtrl = TextEditingController();
  Map<String, dynamic>? _found;
  bool _searching = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  void _snack(String m) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(m)));

  Future<void> _search() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _searching = true;
      _found = null;
    });
    final u = await FriendService.findUserByEmail(email);
    if (!mounted) return;
    setState(() {
      _searching = false;
      _found = u;
    });
    if (u == null) _snack('해당 이메일 사용자가 없어요');
  }

  Future<List<String>?> _pickCategories(
      {List<String> initial = const ['all']}) async {
    bool all = initial.contains('all');
    final sel = <EventCategory>{
      for (final c in EventCategory.adminCategories)
        if (initial.contains(c.value)) c
    };
    return showDialog<List<String>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('담당 카테고리'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CheckboxListTile(
                value: all,
                title: const Text('🌐 전체 카테고리'),
                contentPadding: EdgeInsets.zero,
                onChanged: (v) => setS(() {
                  all = v ?? false;
                  if (all) sel.clear();
                }),
              ),
              const Divider(),
              for (final c in EventCategory.adminCategories)
                CheckboxListTile(
                  value: sel.contains(c),
                  title: Text('${c.emoji} ${c.label}'),
                  contentPadding: EdgeInsets.zero,
                  onChanged: all
                      ? null
                      : (v) => setS(() {
                            if (v == true) {
                              sel.add(c);
                            } else {
                              sel.remove(c);
                            }
                          }),
                ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('취소')),
            FilledButton(
              onPressed: () {
                if (all) {
                  Navigator.pop(ctx, ['all']);
                } else if (sel.isEmpty) {
                  ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                      content: Text('카테고리를 1개 이상 선택하세요')));
                } else {
                  Navigator.pop(ctx, sel.map((c) => c.value).toList());
                }
              },
              child: const Text('확인'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _appoint(Map<String, dynamic> u,
      {List<String> initial = const ['all']}) async {
    final cats = await _pickCategories(initial: initial);
    if (cats == null) return;
    HapticFeedback.selectionClick();
    await UserStatusService.setEventMaster(u['uid'] as String,
        enabled: true, categories: cats);
    if (!mounted) return;
    _snack('${u['displayName'] ?? '사용자'} 님을 이벤트 마스터로 지정했어요');
    setState(() {
      _found = null;
      _emailCtrl.clear();
    });
  }

  Future<void> _revoke(String uid, String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('이벤트 마스터 해제'),
        content: Text('"$name" 님의 이벤트 마스터 권한을 해제할까요?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('취소')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('해제'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await UserStatusService.setEventMaster(uid, enabled: false);
    if (mounted) _snack('해제됐어요');
  }

  Future<void> _appointSuper(Map<String, dynamic> u) async {
    final name = u['displayName']?.toString() ?? '사용자';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('슈퍼 마스터 지정'),
        content: Text('"$name" 님을 슈퍼 마스터로 지정할까요?\n\n'
            '슈퍼 마스터는 모든 카테고리의 이벤트를 관리하고, '
            '다른 이벤트 마스터·슈퍼 마스터를 임명·해제할 수 있어요. '
            '신뢰하는 사람에게만 부여하세요.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('취소')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            child: const Text('슈퍼로 지정'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    HapticFeedback.selectionClick();
    await UserStatusService.setSuperMaster(u['uid'] as String, enabled: true);
    if (!mounted) return;
    _snack('$name 님을 슈퍼 마스터로 지정했어요');
    setState(() {
      _found = null;
      _emailCtrl.clear();
    });
  }

  Future<void> _revokeSuper(String uid, String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('슈퍼 마스터 해제'),
        content: Text('"$name" 님의 슈퍼 마스터 권한을 해제할까요?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('취소')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('해제'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await UserStatusService.setSuperMaster(uid, enabled: false);
    if (mounted) _snack('해제됐어요');
  }

  String _catLabel(List<String> cats) {
    if (cats.contains('all')) return '🌐 전체';
    return cats
        .map((v) => EventCategory.fromString(v))
        .map((c) => '${c.emoji} ${c.label}')
        .join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('이벤트 마스터 관리'),
        backgroundColor: cs.surface,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          const Text('이메일로 회원을 찾아 이벤트 마스터로 지정하세요',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    hintText: '회원 이메일',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _search(),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _searching ? null : _search,
                style:
                    FilledButton.styleFrom(backgroundColor: AppColors.primary),
                child: _searching
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Text('검색'),
              ),
            ],
          ),
          if (_found != null) ...[
            const SizedBox(height: 10),
            Material(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
              child: ListTile(
                title: Text(_found!['displayName']?.toString() ?? '이름 없음',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(_found!['email']?.toString() ?? ''),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    OutlinedButton(
                      onPressed: () => _appoint(_found!),
                      style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.primary,
                          visualDensity: VisualDensity.compact),
                      child: const Text('마스터'),
                    ),
                    const SizedBox(width: 6),
                    FilledButton(
                      onPressed: () => _appointSuper(_found!),
                      style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          visualDensity: VisualDensity.compact),
                      child: const Text('👑 슈퍼'),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 20),
          const Divider(),
          const SizedBox(height: 8),
          const Text('현재 슈퍼 마스터',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text('오너(앱 제작자)는 항상 슈퍼이며 목록에 표시되지 않아요',
              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
          const SizedBox(height: 8),
          StreamBuilder<List<Map<String, dynamic>>>(
            stream: UserStatusService.watchSuperMasters(),
            builder: (context, snap) {
              final supers = snap.data ?? [];
              if (supers.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Center(
                    child: Text('아직 추가된 슈퍼 마스터가 없어요',
                        style: TextStyle(
                            fontSize: 12, color: cs.onSurfaceVariant)),
                  ),
                );
              }
              return Column(
                children: supers.map((m) {
                  final uid = m['uid'] as String;
                  final name = m['displayName']?.toString() ?? '이름 없음';
                  return Card(
                    elevation: 0,
                    color: cs.surfaceContainerHighest,
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: const Text('👑', style: TextStyle(fontSize: 20)),
                      title: Text(name,
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text(m['email']?.toString() ?? '',
                          style: TextStyle(
                              fontSize: 11.5, color: cs.onSurfaceVariant)),
                      trailing: IconButton(
                        icon: Icon(Icons.person_remove_outlined,
                            color: AppColors.error),
                        tooltip: '해제',
                        onPressed: () => _revokeSuper(uid, name),
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          ),
          const SizedBox(height: 20),
          const Divider(),
          const SizedBox(height: 8),
          const Text('현재 이벤트 마스터',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          StreamBuilder<List<Map<String, dynamic>>>(
            stream: UserStatusService.watchEventMasters(),
            builder: (context, snap) {
              final masters = snap.data ?? [];
              if (masters.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text('아직 지정된 이벤트 마스터가 없어요',
                        style: TextStyle(
                            fontSize: 12, color: cs.onSurfaceVariant)),
                  ),
                );
              }
              return Column(
                children: masters.map((m) {
                  final uid = m['uid'] as String;
                  final name = m['displayName']?.toString() ?? '이름 없음';
                  final cats = ((m['eventCategories'] as List<dynamic>?) ??
                          const [])
                      .map((e) => e.toString())
                      .toList();
                  return Card(
                    elevation: 0,
                    color: cs.surfaceContainerHighest,
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      title: Text(name,
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text(
                        '${m['email'] ?? ''}\n${_catLabel(cats)}',
                        style: TextStyle(
                            fontSize: 11.5, color: cs.onSurfaceVariant),
                      ),
                      isThreeLine: true,
                      onTap: () =>
                          _appoint(m, initial: cats), // 카테고리 재지정
                      trailing: IconButton(
                        icon: Icon(Icons.person_remove_outlined,
                            color: AppColors.error),
                        tooltip: '해제',
                        onPressed: () => _revoke(uid, name),
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}
