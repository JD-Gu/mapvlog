import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/friend_group.dart';
import '../models/friendship.dart';
import '../services/friend_group_service.dart';
import '../services/friend_service.dart';
import '../utils/constants.dart';

/// 그룹 멤버 할당 시트
///
/// - 친구 목록(accepted)을 체크박스로 노출
/// - 현재 그룹 멤버는 미리 체크된 상태
/// - 저장 시 그룹의 memberUids 전체 교체
class GroupAssignmentSheet {
  static Future<void> open(BuildContext context, FriendGroup group) async {
    HapticFeedback.selectionClick();
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => _AssignmentView(group: group),
    );
  }
}

class _AssignmentView extends StatefulWidget {
  final FriendGroup group;
  const _AssignmentView({required this.group});

  @override
  State<_AssignmentView> createState() => _AssignmentViewState();
}

class _AssignmentViewState extends State<_AssignmentView> {
  late Set<String> _selectedUids;
  String _query = '';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _selectedUids = widget.group.memberUids.toSet();
  }

  bool _matches(Friendship f) {
    if (_query.isEmpty) return true;
    final q = _query.toLowerCase();
    return f.effectiveName.toLowerCase().contains(q) ||
        (f.displayName ?? '').toLowerCase().contains(q) ||
        (f.email ?? '').toLowerCase().contains(q);
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    HapticFeedback.mediumImpact();
    try {
      await FriendGroupService.setGroupMembers(
        groupId: widget.group.id,
        memberUids: _selectedUids.toList(),
      );
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('✅ "${widget.group.name}" 멤버 ${_selectedUids.length}명 저장'),
        backgroundColor: AppColors.secondary,
        duration: const Duration(seconds: 2),
      ));
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('저장 실패: $e'),
          backgroundColor: AppColors.error,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final mediaH = MediaQuery.of(context).size.height;
    return SizedBox(
      height: mediaH * 0.8,
      child: Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.textDisabled.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
            child: Row(
              children: [
                Text(widget.group.emoji,
                    style: const TextStyle(fontSize: 24)),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.group.name,
                          style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800)),
                      Text('${_selectedUids.length}명 선택',
                          style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // 검색
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: TextField(
              onChanged: (v) => setState(() => _query = v.trim()),
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(
                hintText: '친구 검색',
                hintStyle: const TextStyle(
                    fontSize: 13, color: AppColors.textSecondary),
                prefixIcon: const Icon(Icons.search,
                    size: 18, color: AppColors.textSecondary),
                filled: true,
                fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.full),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: StreamBuilder<List<Friendship>>(
              stream: FriendService.watchMyFriends(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(
                      child: CircularProgressIndicator(
                          color: AppColors.primary));
                }
                final all = snap.data ?? [];
                final accepted = all
                    .where((f) => f.status == FriendshipStatus.accepted)
                    .where(_matches)
                    .toList();
                if (accepted.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(AppSpacing.xl),
                      child: Text(
                        '추가할 친구가 없어요',
                        style: TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary),
                      ),
                    ),
                  );
                }
                return ListView.separated(
                  itemCount: accepted.length,
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1, indent: 60),
                  itemBuilder: (_, i) {
                    final f = accepted[i];
                    final checked = _selectedUids.contains(f.friendUid);
                    return CheckboxListTile(
                      value: checked,
                      onChanged: (v) {
                        setState(() {
                          if (v == true) {
                            _selectedUids.add(f.friendUid);
                          } else {
                            _selectedUids.remove(f.friendUid);
                          }
                        });
                      },
                      title: Text(f.effectiveName,
                          style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600)),
                      subtitle: (f.email != null && f.email!.isNotEmpty)
                          ? Text(f.email!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 11,
                                  color: AppColors.textSecondary))
                          : null,
                      controlAffinity: ListTileControlAffinity.trailing,
                      activeColor: AppColors.primary,
                      dense: true,
                    );
                  },
                );
              },
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _saving ? null : () => Navigator.pop(context),
                      child: const Text('취소'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      onPressed: _saving ? null : _save,
                      style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primary),
                      child: Text(_saving
                          ? '저장 중...'
                          : '${_selectedUids.length}명 저장'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
