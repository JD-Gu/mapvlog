import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/friend_group.dart';
import '../../services/friend_group_service.dart';
import '../../utils/constants.dart';
import '../../utils/sheets.dart';
import '../../widgets/group_assignment_sheet.dart';

/// 그룹 관리 화면 — 친구그루핑정책.md
///
/// 사용자가 자유롭게 정의한 그룹을 모아 보고, 새 그룹을 추가하거나,
/// 각 그룹의 위치 권한 모드(인싸/부끄럼/불편)와 멤버를 관리할 수 있다.
class FriendGroupsScreen extends StatelessWidget {
  const FriendGroupsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.surface,
        elevation: 0,
        scrolledUnderElevation: 1,
        title: const Row(
          children: [
            Icon(Icons.group_work, color: AppColors.primary, size: 22),
            SizedBox(width: 8),
            Text('그룹 관리',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800)),
          ],
        ),
      ),
      body: StreamBuilder<List<FriendGroup>>(
        stream: FriendGroupService.watchMyGroups(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
                child: CircularProgressIndicator(color: AppColors.primary));
          }
          final groups = snap.data ?? [];
          return Column(
            children: [
              // 안내 배너
              Container(
                margin: const EdgeInsets.fromLTRB(
                    AppSpacing.md, AppSpacing.md, AppSpacing.md, 8),
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.18)),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('그룹별 위치 권한 모드',
                        style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800)),
                    SizedBox(height: 6),
                    Text('💖 베프 — 실시간 정확 위치 공유',
                        style: TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary)),
                    Text('🙈 부끄럼 — 동·반경 단위 대략 위치',
                        style: TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary)),
                    Text('🥷 잠수 — 숨김/고정 · 오프라인 및 마지막 위치 고정',
                        style: TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary)),
                  ],
                ),
              ),
              Expanded(
                child: groups.isEmpty
                    ? _EmptyGroups()
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        itemCount: groups.length,
                        separatorBuilder: (_, __) =>
                            const Divider(height: 1, indent: 76),
                        itemBuilder: (_, i) =>
                            _GroupTile(group: groups[i]),
                      ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _GroupEditSheet.create(context),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('새 그룹'),
      ),
    );
  }
}

// ─── 빈 상태 ───────────────────────────────────────────────────────────────
class _EmptyGroups extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.group_work_outlined,
                size: 60, color: AppColors.textDisabled),
            const SizedBox(height: 12),
            const Text(
              '아직 그룹이 없어요',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            const Text(
              '"가족", "동아리", "꽃꽂이 모임" 같은\n그룹을 만들고 친구를 할당해보세요',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 12.5, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── 그룹 타일 ─────────────────────────────────────────────────────────────
class _GroupTile extends StatelessWidget {
  final FriendGroup group;
  const _GroupTile({required this.group});

  Color _modeColor() {
    switch (group.mode) {
      case GroupMode.insider:
        return const Color(0xFFEC407A);
      case GroupMode.shy:
        return const Color(0xFFFFA726);
      case GroupMode.uneasy:
        return const Color(0xFF607D8B);
    }
  }

  @override
  Widget build(BuildContext context) {
    final modeColor = _modeColor();
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: 4),
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: modeColor.withValues(alpha: 0.12),
          shape: BoxShape.circle,
          border: Border.all(color: modeColor.withValues(alpha: 0.4)),
        ),
        alignment: Alignment.center,
        child: Text(group.emoji, style: const TextStyle(fontSize: 22)),
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              group.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 6),
          // 모드 배지
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: modeColor,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(group.mode.emoji,
                    style: const TextStyle(fontSize: 9)),
                const SizedBox(width: 3),
                Text(group.mode.label,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.3)),
              ],
            ),
          ),
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text(
          '${group.memberUids.length}명 · ${group.mode.description}',
          style: const TextStyle(
              fontSize: 11.5, color: AppColors.textSecondary),
        ),
      ),
      trailing: PopupMenuButton<String>(
        icon: const Icon(Icons.more_vert,
            size: 20, color: AppColors.textSecondary),
        onSelected: (v) {
          switch (v) {
            case 'edit':
              _GroupEditSheet.edit(context, group);
              break;
            case 'members':
              GroupAssignmentSheet.open(context, group);
              break;
            case 'delete':
              _confirmDelete(context, group);
              break;
          }
        },
        itemBuilder: (_) => const [
          PopupMenuItem(
            value: 'members',
            child: Row(children: [
              Icon(Icons.people_outline, size: 18),
              SizedBox(width: 8),
              Text('멤버 관리'),
            ]),
          ),
          PopupMenuItem(
            value: 'edit',
            child: Row(children: [
              Icon(Icons.edit_outlined, size: 18),
              SizedBox(width: 8),
              Text('편집'),
            ]),
          ),
          PopupMenuItem(
            value: 'delete',
            child: Row(children: [
              Icon(Icons.delete_outline, size: 18, color: AppColors.error),
              SizedBox(width: 8),
              Text('삭제', style: TextStyle(color: AppColors.error)),
            ]),
          ),
        ],
      ),
      onTap: () => GroupAssignmentSheet.open(context, group),
      onLongPress: () => _showQuickModeSheet(context, group),
    );
  }

  /// Long-press → 모드 빠른 토글 시트 (베프 / 부끄럼 / 불편)
  Future<void> _showQuickModeSheet(
      BuildContext context, FriendGroup g) async {
    HapticFeedback.mediumImpact();
    final picked = await showModalBottomSheet<GroupMode>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        final cs = Theme.of(sheetCtx).colorScheme;
        return Container(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: cs.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                children: [
                  Text(g.emoji, style: const TextStyle(fontSize: 22)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      g.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: cs.onSurface),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '이 그룹에 적용할 위치 모드를 선택해요',
                style: TextStyle(
                    fontSize: 12.5, color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 14),
              for (final m in GroupMode.values)
                _ModeOption(
                  mode: m,
                  selected: m == g.mode,
                  onTap: () => Navigator.pop(sheetCtx, m),
                ),
            ],
          ),
        );
      },
    );
    if (picked == null || picked == g.mode) return;
    try {
      await FriendGroupService.updateGroup(groupId: g.id, mode: picked);
      if (context.mounted) {
        HapticFeedback.lightImpact();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 2),
            content: Text(
                '"${g.name}" → ${picked.emoji} ${picked.label} 모드로 변경'),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('변경 실패: $e')),
        );
      }
    }
  }

  Future<void> _confirmDelete(BuildContext context, FriendGroup g) async {
    final ok = await AppSheets.confirm(
      context,
      icon: Icons.delete_outline,
      title: '"${g.name}" 그룹 삭제',
      message: '그룹만 삭제됩니다. 친구 관계는 유지돼요.',
      confirmLabel: '삭제',
      dangerous: true,
    );
    if (ok != true) return;
    try {
      await FriendGroupService.deleteGroup(g.id);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('삭제 실패: $e'),
              backgroundColor: AppColors.error),
        );
      }
    }
  }
}

// ─── 그룹 생성/편집 시트 ──────────────────────────────────────────────────
// ─── Long-press 모드 빠른 토글 옵션 행 ─────────────────────────────────
class _ModeOption extends StatelessWidget {
  final GroupMode mode;
  final bool selected;
  final VoidCallback onTap;
  const _ModeOption({
    required this.mode,
    required this.selected,
    required this.onTap,
  });

  Color _color() {
    switch (mode) {
      case GroupMode.insider:
        return const Color(0xFFEC407A);
      case GroupMode.shy:
        return const Color(0xFFFFA726);
      case GroupMode.uneasy:
        return const Color(0xFF607D8B);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final c = _color();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: selected ? c.withValues(alpha: 0.1) : cs.surface,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(
              color: selected ? c : cs.outlineVariant,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: c.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(mode.emoji,
                    style: const TextStyle(fontSize: 18)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(mode.label,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: cs.onSurface,
                        )),
                    Text(mode.description,
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurfaceVariant,
                        )),
                  ],
                ),
              ),
              if (selected)
                Icon(Icons.check_circle, color: c, size: 20)
              else
                Icon(Icons.radio_button_unchecked,
                    color: cs.outline, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _GroupEditSheet {
  static const _presetEmojis = [
    '👥', '👪', '🎓', '💼', '🏃', '☕', '🎨', '🎮', '🎵',
    '⛷️', '🍻', '🌸', '🏠', '✈️', '📚', '🎬',
  ];

  static Future<void> create(BuildContext context) =>
      _show(context, existing: null);

  static Future<void> edit(BuildContext context, FriendGroup g) =>
      _show(context, existing: g);

  static Future<void> _show(BuildContext context,
      {FriendGroup? existing}) async {
    final isEdit = existing != null;
    final nameCtrl =
        TextEditingController(text: isEdit ? existing.name : '');
    String emoji = isEdit ? existing.emoji : '👥';
    GroupMode mode = isEdit ? existing.mode : GroupMode.insider;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => Padding(
          padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 12,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
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
              const SizedBox(height: 14),
              Text(
                isEdit ? '그룹 편집' : '새 그룹 만들기',
                style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              // 이름
              TextField(
                controller: nameCtrl,
                maxLength: 16,
                decoration: const InputDecoration(
                  labelText: '그룹 이름',
                  hintText: '예: 가족, 동아리, 꽃꽂이 모임',
                  border: OutlineInputBorder(),
                  counterText: '',
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              // 이모지
              const Text('대표 이모지',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textSecondary)),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _presetEmojis.map((e) {
                  final sel = emoji == e;
                  return GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => emoji = e);
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 140),
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: sel
                            ? AppColors.primary.withValues(alpha: 0.18)
                            : Theme.of(context).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: sel
                              ? AppColors.primary
                              : Colors.transparent,
                          width: 2,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(e,
                          style: const TextStyle(fontSize: 18)),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 14),
              // 모드
              const Text('위치 권한 모드',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textSecondary)),
              const SizedBox(height: 4),
              Column(
                children: GroupMode.values.map((m) {
                  final sel = mode == m;
                  return InkWell(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => mode = m);
                    },
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 4),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: sel
                            ? AppColors.primary.withValues(alpha: 0.08)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                        border: Border.all(
                          color: sel
                              ? AppColors.primary
                              : AppColors.textDisabled
                                  .withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          Text(m.emoji,
                              style: const TextStyle(fontSize: 22)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(m.label,
                                    style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700)),
                                Text(m.description,
                                    style: const TextStyle(
                                        fontSize: 11,
                                        color: AppColors.textSecondary)),
                              ],
                            ),
                          ),
                          if (sel)
                            const Icon(Icons.check_circle,
                                color: AppColors.primary, size: 20),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('취소'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      onPressed: () async {
                        final name = nameCtrl.text.trim();
                        if (name.isEmpty) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            const SnackBar(content: Text('그룹 이름을 입력해 주세요')),
                          );
                          return;
                        }
                        try {
                          if (isEdit) {
                            await FriendGroupService.updateGroup(
                              groupId: existing.id,
                              name: name,
                              emoji: emoji,
                              mode: mode,
                            );
                          } else {
                            await FriendGroupService.createGroup(
                              name: name,
                              emoji: emoji,
                              mode: mode,
                            );
                          }
                          if (ctx.mounted) Navigator.pop(ctx);
                        } catch (e) {
                          if (ctx.mounted) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              SnackBar(
                                  content: Text('실패: $e'),
                                  backgroundColor: AppColors.error),
                            );
                          }
                        }
                      },
                      child: Text(isEdit ? '저장' : '만들기'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

