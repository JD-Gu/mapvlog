import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/reaction.dart';
import '../models/vlog.dart';
import '../services/reaction_service.dart';
import '../utils/constants.dart';

/// Slack 스타일 리액션 바
///
/// vlog 카드 / vlog player 하단에 표시:
///   [😂 3] [❤️ 5] [🔥 2]  +
///
/// - 칩 탭 → 내 리액션 토글 (이미 한 이모지면 제거)
/// - 끝의 + 버튼 → 빠른 이모지 팔레트 시트
/// - 내가 리액션한 칩은 primary 보더로 강조
class ReactionBar extends StatelessWidget {
  final Vlog vlog;
  final bool compact;
  const ReactionBar({super.key, required this.vlog, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    return StreamBuilder<List<ReactionGroup>>(
      stream: ReactionService.watchGroups(vlog.id),
      builder: (context, snap) {
        final groups = snap.data ?? const <ReactionGroup>[];
        return Wrap(
          spacing: 6,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ...groups.map((g) => _ReactionChip(
                  group: g,
                  selected: g.didIReact(myUid),
                  compact: compact,
                  onTap: () => _toggle(context, g.emoji),
                )),
            _AddReactionButton(
              compact: compact,
              onPick: (e) => _toggle(context, e),
            ),
          ],
        );
      },
    );
  }

  Future<void> _toggle(BuildContext context, String emoji) async {
    HapticFeedback.lightImpact();
    try {
      await ReactionService.toggle(vlogId: vlog.id, emoji: emoji);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              duration: const Duration(seconds: 2),
              content: Text('리액션 실패: $e')),
        );
      }
    }
  }
}

class _ReactionChip extends StatelessWidget {
  final ReactionGroup group;
  final bool selected;
  final bool compact;
  final VoidCallback onTap;
  const _ReactionChip({
    required this.group,
    required this.selected,
    required this.compact,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bg = selected
        ? cs.primary.withValues(alpha: 0.12)
        : cs.surfaceContainerHighest;
    final borderColor = selected ? cs.primary : cs.outlineVariant;
    final fg = selected ? cs.primary : cs.onSurfaceVariant;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.full),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: EdgeInsets.symmetric(
            horizontal: compact ? 8 : 10,
            vertical: compact ? 3 : 4),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(AppRadius.full),
          border: Border.all(color: borderColor, width: selected ? 1.5 : 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(group.emoji,
                style: TextStyle(fontSize: compact ? 13 : 14)),
            const SizedBox(width: 5),
            Text('${group.count}',
                style: TextStyle(
                  fontSize: compact ? 11 : 12,
                  fontWeight: FontWeight.w800,
                  color: fg,
                )),
          ],
        ),
      ),
    );
  }
}

class _AddReactionButton extends StatelessWidget {
  final bool compact;
  final ValueChanged<String> onPick;
  const _AddReactionButton({required this.compact, required this.onPick});

  Future<void> _openPalette(BuildContext context) async {
    HapticFeedback.selectionClick();
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetCtx) => const _ReactionPaletteSheet(),
    );
    if (picked != null) onPick(picked);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () => _openPalette(context),
      borderRadius: BorderRadius.circular(AppRadius.full),
      child: Container(
        padding: EdgeInsets.symmetric(
            horizontal: compact ? 8 : 10,
            vertical: compact ? 3 : 4),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppRadius.full),
          border: Border.all(
              color: cs.outlineVariant,
              style: BorderStyle.solid),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add_reaction_outlined,
                size: compact ? 13 : 15, color: cs.onSurfaceVariant),
            const SizedBox(width: 3),
            Text('+',
                style: TextStyle(
                  fontSize: compact ? 12 : 13,
                  fontWeight: FontWeight.w800,
                  color: cs.onSurfaceVariant,
                )),
          ],
        ),
      ),
    );
  }
}

// ─── Slack 스타일 이모지 팔레트 시트 (카테고리 탭) ───────────────────────
class _ReactionPaletteSheet extends StatefulWidget {
  const _ReactionPaletteSheet();

  @override
  State<_ReactionPaletteSheet> createState() =>
      _ReactionPaletteSheetState();
}

class _ReactionPaletteSheetState extends State<_ReactionPaletteSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl = TabController(
      length: kReactionCategories.length, vsync: this);

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final mediaH = MediaQuery.of(context).size.height;
    return Container(
      height: mediaH * 0.6,
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: Column(
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
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Text('리액션 추가',
                    style: TextStyle(
                        fontSize: 16,
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
          TabBar(
            controller: _tabCtrl,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelColor: cs.primary,
            unselectedLabelColor: cs.onSurfaceVariant,
            indicatorColor: cs.primary,
            labelStyle: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w700),
            tabs: kReactionCategories
                .map((c) => Tab(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(c.hint,
                              style: const TextStyle(fontSize: 14)),
                          const SizedBox(width: 4),
                          Text(c.label),
                        ],
                      ),
                    ))
                .toList(),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabCtrl,
              children: kReactionCategories
                  .map((category) => GridView.builder(
                        padding: const EdgeInsets.fromLTRB(
                            16, 12, 16, 24),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 6,
                          mainAxisSpacing: 8,
                          crossAxisSpacing: 8,
                          childAspectRatio: 1,
                        ),
                        itemCount: category.emojis.length,
                        itemBuilder: (_, i) {
                          final e = category.emojis[i];
                          return InkWell(
                            borderRadius:
                                BorderRadius.circular(AppRadius.lg),
                            onTap: () {
                              HapticFeedback.selectionClick();
                              Navigator.pop(context, e);
                            },
                            child: Container(
                              decoration: BoxDecoration(
                                color: cs.surfaceContainerHighest,
                                borderRadius:
                                    BorderRadius.circular(AppRadius.lg),
                                border: Border.all(
                                    color: cs.outlineVariant),
                              ),
                              alignment: Alignment.center,
                              child: Text(e,
                                  style: const TextStyle(fontSize: 26)),
                            ),
                          );
                        },
                      ))
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }
}
