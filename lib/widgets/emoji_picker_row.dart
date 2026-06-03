import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../utils/constants.dart';
import '../utils/marker_emojis.dart';

/// 카테고리 이모지 그리드 — 사진/영상 등록·수정 시트의 색상 picker 대체
///
/// MarkerEmojis.groups 8개 섹션 × 60종 이모지를 스크롤 가능한 ConstrainedBox에 표시.
/// 선택 시 상단에 "카테고리 · 라벨" 미리보기.
class EmojiPickerRow extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onPick;
  final double maxHeight;
  /// 추천 키워드 매칭에 사용할 텍스트 (제목+장소명). null이면 추천 미표시.
  final String? suggestionText;
  /// true(기본): 내부 ConstrainedBox+스크롤. false: 모든 그룹 인라인 렌더 (부모가 스크롤)
  final bool scrollable;

  const EmojiPickerRow({
    super.key,
    required this.selected,
    required this.onPick,
    this.maxHeight = 240,
    this.suggestionText,
    this.scrollable = true,
  });

  @override
  Widget build(BuildContext context) {
    final picked = MarkerEmojis.fromEmoji(selected);
    // 텍스트 기반 자동 추천 (현재 선택과 다를 때만 노출)
    final suggested = suggestionText == null
        ? null
        : MarkerEmojis.suggestFor(suggestionText!);
    final showSuggestion = suggested != null && suggested != selected;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 헤더 — 선택된 이모지 + 카테고리 + 라벨 (+추천)
        Row(children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: picked.color,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(picked.emoji,
                style: const TextStyle(fontSize: 13, height: 1.0)),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '${picked.category} · ${picked.label}',
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (showSuggestion) ...[
            const SizedBox(width: 6),
            GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                onPick(suggested);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppRadius.full),
                  border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.auto_awesome,
                        size: 11, color: AppColors.primary),
                    const SizedBox(width: 3),
                    Text('추천 $suggested',
                        style: const TextStyle(
                            fontSize: 10.5,
                            color: AppColors.primary,
                            fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            ),
          ],
        ]),
        const SizedBox(height: 8),
        if (scrollable)
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: SingleChildScrollView(
              child: _buildGroups(),
            ),
          )
        else
          _buildGroups(),
      ],
    );
  }

  Widget _buildGroups() {
    return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: MarkerEmojis.groups.map((g) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          '${g.hint}  ${g.name}',
                          style: const TextStyle(
                              fontSize: 10.5,
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.2),
                        ),
                      ),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: g.emojis.map((e) {
                          final isSelected = selected == e.emoji;
                          return GestureDetector(
                            onTap: () {
                              HapticFeedback.selectionClick();
                              onPick(e.emoji);
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 140),
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? e.color.withValues(alpha: 0.18)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: isSelected
                                      ? e.color
                                      : AppColors.textDisabled
                                          .withValues(alpha: 0.3),
                                  width: isSelected ? 2 : 1,
                                ),
                              ),
                              alignment: Alignment.center,
                              child: Text(e.emoji,
                                  style: const TextStyle(fontSize: 18)),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                );
              }).toList(),
    );
  }
}
