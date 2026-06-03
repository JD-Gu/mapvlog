import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/friend_group.dart';
import '../models/vlog.dart';
import '../services/friend_group_service.dart';
import '../utils/constants.dart';

/// 게시글 공개 범위 선택 결과
class VisibilitySelection {
  final VlogVisibility visibility;
  final List<String> groupIds; // groups 모드일 때만
  final List<String> visibleUids; // 모든 선택 그룹의 멤버 UID 합집합 (작성자 본인 제외)

  const VisibilitySelection({
    required this.visibility,
    this.groupIds = const [],
    this.visibleUids = const [],
  });

  static const VisibilitySelection public =
      VisibilitySelection(visibility: VlogVisibility.public);
  static const VisibilitySelection private =
      VisibilitySelection(visibility: VlogVisibility.private);
}

/// 공개 범위 선택 칩 — 폼/시트 어디서나 재사용
///
/// 탭 시 시트 열림 → 선택 결과 콜백.
/// 작성자 본인의 그룹 목록을 미리 페치해서 멀티 선택 가능.
class VisibilityPickerChip extends StatelessWidget {
  final VisibilitySelection selection;
  final ValueChanged<VisibilitySelection> onChanged;
  final bool dense;

  const VisibilityPickerChip({
    super.key,
    required this.selection,
    required this.onChanged,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final v = selection.visibility;
    final label = switch (v) {
      VlogVisibility.public => '전체 공개',
      VlogVisibility.groups => selection.groupIds.isEmpty
          ? '그룹 선택'
          : '그룹 ${selection.groupIds.length}개',
      VlogVisibility.private => '나만 보기',
    };
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.full),
      onTap: () => _open(context),
      child: Container(
        padding: EdgeInsets.symmetric(
            horizontal: dense ? 10 : 14, vertical: dense ? 6 : 8),
        decoration: BoxDecoration(
          color: cs.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(AppRadius.full),
          border: Border.all(color: cs.primary.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(v.emoji, style: TextStyle(fontSize: dense ? 12 : 14)),
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(
                  fontSize: dense ? 11.5 : 13,
                  fontWeight: FontWeight.w700,
                  color: cs.primary,
                )),
            const SizedBox(width: 2),
            Icon(Icons.expand_more, size: dense ? 14 : 16, color: cs.primary),
          ],
        ),
      ),
    );
  }

  Future<void> _open(BuildContext context) async {
    HapticFeedback.selectionClick();
    final result = await showModalBottomSheet<VisibilitySelection>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => VisibilityPickerSheet(initial: selection),
    );
    if (result != null) onChanged(result);
  }
}

/// 공개 범위 선택 시트 — Chip 외부에서도 직접 띄울 때 사용
class VisibilityPickerSheet extends StatefulWidget {
  final VisibilitySelection initial;
  const VisibilityPickerSheet({super.key, required this.initial});

  @override
  State<VisibilityPickerSheet> createState() => _VisibilityPickerSheetState();
}

class _VisibilityPickerSheetState extends State<VisibilityPickerSheet> {
  late VlogVisibility _picked;
  late Set<String> _selectedGroupIds;
  List<FriendGroup> _groups = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _picked = widget.initial.visibility;
    _selectedGroupIds = widget.initial.groupIds.toSet();
    _loadGroups();
  }

  Future<void> _loadGroups() async {
    try {
      final groups = await FriendGroupService.getMyGroupsOnce();
      if (!mounted) return;
      setState(() {
        _groups = groups;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// 선택 결과 → 그룹 멤버 flat list 계산
  Future<VisibilitySelection> _build() async {
    if (_picked == VlogVisibility.public) {
      return VisibilitySelection.public;
    }
    if (_picked == VlogVisibility.private) {
      return VisibilitySelection.private;
    }
    // groups
    final myUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final selected = _groups
        .where((g) => _selectedGroupIds.contains(g.id))
        .toList();
    final uids = <String>{};
    for (final g in selected) {
      uids.addAll(g.memberUids);
    }
    uids.remove(myUid); // 본인은 어차피 author 권한으로 봄
    return VisibilitySelection(
      visibility: VlogVisibility.groups,
      groupIds: selected.map((g) => g.id).toList(),
      visibleUids: uids.toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final mediaH = MediaQuery.of(context).size.height;
    return Container(
      constraints: BoxConstraints(maxHeight: mediaH * 0.85),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
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
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
            child: Row(
              children: [
                Text('공개 범위',
                    style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: cs.onSurface)),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final v in VlogVisibility.values)
                    _VisibilityOption(
                      v: v,
                      selected: _picked == v,
                      onTap: () => setState(() => _picked = v),
                    ),
                  // 그룹 모드일 때 — 그룹 멀티 선택
                  if (_picked == VlogVisibility.groups) ...[
                    const SizedBox(height: 12),
                    const Padding(
                      padding: EdgeInsets.symmetric(
                          horizontal: 4, vertical: 6),
                      child: Text('공개할 그룹 선택',
                          style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w800)),
                    ),
                    if (_loading)
                      const Center(
                          child: Padding(
                        padding: EdgeInsets.all(20),
                        child: CircularProgressIndicator(),
                      ))
                    else if (_groups.isEmpty)
                      Container(
                        margin: const EdgeInsets.symmetric(vertical: 8),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerHighest,
                          borderRadius:
                              BorderRadius.circular(AppRadius.md),
                        ),
                        child: const Text(
                          '아직 만든 그룹이 없어요.\n친구 → 그룹 관리에서 만들어보세요.',
                          style: TextStyle(fontSize: 12.5, height: 1.5),
                        ),
                      )
                    else
                      ..._groups.map((g) {
                        final on = _selectedGroupIds.contains(g.id);
                        return InkWell(
                          borderRadius:
                              BorderRadius.circular(AppRadius.md),
                          onTap: () => setState(() {
                            if (on) {
                              _selectedGroupIds.remove(g.id);
                            } else {
                              _selectedGroupIds.add(g.id);
                            }
                          }),
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 6),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: on
                                  ? cs.primary.withValues(alpha: 0.1)
                                  : cs.surfaceContainerHighest,
                              borderRadius:
                                  BorderRadius.circular(AppRadius.md),
                              border: Border.all(
                                color: on ? cs.primary : cs.outlineVariant,
                                width: on ? 1.5 : 1,
                              ),
                            ),
                            child: Row(
                              children: [
                                Text(g.emoji,
                                    style: const TextStyle(fontSize: 18)),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(g.name,
                                          style: const TextStyle(
                                              fontSize: 14,
                                              fontWeight:
                                                  FontWeight.w700)),
                                      Text(
                                          '${g.memberUids.length}명',
                                          style: TextStyle(
                                              fontSize: 11.5,
                                              color: cs.onSurfaceVariant)),
                                    ],
                                  ),
                                ),
                                Icon(
                                    on
                                        ? Icons.check_circle
                                        : Icons.radio_button_unchecked,
                                    color: on ? cs.primary : cs.outline,
                                    size: 20),
                              ],
                            ),
                          ),
                        );
                      }),
                  ],
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: cs.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(AppRadius.md)),
                          textStyle: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w800),
                        ),
                        onPressed: () async {
                          if (_picked == VlogVisibility.groups &&
                              _selectedGroupIds.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('그룹을 한 개 이상 선택해주세요'),
                                duration: Duration(seconds: 2),
                              ),
                            );
                            return;
                          }
                          HapticFeedback.lightImpact();
                          final result = await _build();
                          if (!mounted) return;
                          Navigator.pop(context, result);
                        },
                        child: const Text('적용'),
                      ),
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

class _VisibilityOption extends StatelessWidget {
  final VlogVisibility v;
  final bool selected;
  final VoidCallback onTap;
  const _VisibilityOption({
    required this.v,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.md),
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? cs.primary.withValues(alpha: 0.1)
              : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: selected ? cs.primary : cs.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Text(v.emoji, style: const TextStyle(fontSize: 20)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(v.label,
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: cs.onSurface)),
                  Text(v.description,
                      style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurfaceVariant)),
                ],
              ),
            ),
            Icon(
              selected ? Icons.check_circle : Icons.radio_button_unchecked,
              color: selected ? cs.primary : cs.outline,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }
}

/// Pure ServerTimestamp helper for default sentinel
class _Unused {
  static FieldValue ts() => FieldValue.serverTimestamp();
}
