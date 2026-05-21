import 'package:flutter/material.dart';

import '../models/vlog.dart';
import '../utils/constants.dart';

class VlogCard extends StatelessWidget {
  final Vlog vlog;
  final VoidCallback? onTap;
  /// 등록자인 경우 부모에서 수정/삭제 메뉴를 표시하도록 넘겨주는 콜백
  final VoidCallback? onLongPress;

  const VlogCard({super.key, required this.vlog, this.onTap, this.onLongPress});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          boxShadow: AppShadow.card,
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── 썸네일 + 오버레이 배지
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _buildThumbnail(),

                  // 사진/영상 타입 배지 (좌상단)
                  Positioned(
                    top: 6,
                    left: 6,
                    child: _MediaTypeBadge(isVideo: vlog.hasVideo),
                  ),

                  // 영상 길이 배지 (우하단) — YouTube 스타일
                  if (vlog.hasVideo &&
                      vlog.durationSeconds != null &&
                      vlog.durationSeconds! > 0)
                    Positioned(
                      bottom: 6,
                      right: 6,
                      child: _DurationBadge(seconds: vlog.durationSeconds!),
                    ),
                ],
              ),
            ),

            // ── 텍스트 정보 영역
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 7, 8, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 제목
                  Text(
                    vlog.title,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),

                  // 장소
                  Row(
                    children: [
                      const Icon(Icons.location_on,
                          size: 11, color: AppColors.primary),
                      const SizedBox(width: 2),
                      Expanded(
                        child: Text(
                          vlog.placeName,
                          style: const TextStyle(
                              fontSize: 11, color: AppColors.textSecondary),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),

                  // 등록일 + (영상이면 길이)
                  Row(
                    children: [
                      const Icon(Icons.calendar_today,
                          size: 10, color: AppColors.textDisabled),
                      const SizedBox(width: 2),
                      Text(
                        _relativeDate(vlog.createdAt),
                        style: const TextStyle(
                            fontSize: 10, color: AppColors.textDisabled),
                      ),
                      if (vlog.hasVideo &&
                          vlog.durationSeconds != null &&
                          vlog.durationSeconds! > 0) ...[
                        const SizedBox(width: 6),
                        const Icon(Icons.timer_outlined,
                            size: 10, color: AppColors.textDisabled),
                        const SizedBox(width: 2),
                        Text(
                          _fmtDuration(vlog.durationSeconds!),
                          style: const TextStyle(
                              fontSize: 10, color: AppColors.textDisabled),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),

                  // 좋아요 + 조회수 + 작성자
                  Row(
                    children: [
                      const Icon(Icons.favorite, size: 11, color: AppColors.error),
                      const SizedBox(width: 2),
                      Text(
                        '${vlog.likeCount}',
                        style: const TextStyle(
                            fontSize: 11, color: AppColors.textSecondary),
                      ),
                      const SizedBox(width: 6),
                      const Icon(Icons.visibility_outlined,
                          size: 11, color: AppColors.textDisabled),
                      const SizedBox(width: 2),
                      Text(
                        _fmtCount(vlog.viewCount),
                        style: const TextStyle(
                            fontSize: 11, color: AppColors.textSecondary),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          vlog.authorName,
                          style: const TextStyle(
                              fontSize: 11, color: AppColors.textSecondary),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
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

  Widget _buildThumbnail() {
    final url = vlog.thumbnailUrl ?? '';
    if (url.isNotEmpty) {
      return Image.network(
        url,
        fit: BoxFit.cover,
        width: double.infinity,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return Container(
            color: AppColors.surfaceVariant,
            child: const Center(
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: AppColors.primary),
            ),
          );
        },
        errorBuilder: (context, error, stack) => _placeholder(),
      );
    }
    return _placeholder();
  }

  Widget _placeholder() {
    return Container(
      color: AppColors.surfaceVariant,
      child: Center(
        child: Icon(
          vlog.hasVideo ? Icons.videocam : Icons.photo,
          size: 36,
          color: AppColors.textDisabled,
        ),
      ),
    );
  }

  /// 상대 날짜 ("방금 전" / "3시간 전" / "5일 전" / "2026.05.21")
  static String _relativeDate(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return '방금 전';
    if (diff.inHours < 1) return '${diff.inMinutes}분 전';
    if (diff.inHours < 24) return '${diff.inHours}시간 전';
    if (diff.inDays < 7) return '${diff.inDays}일 전';
    return '${dt.year}.${dt.month.toString().padLeft(2, '0')}.${dt.day.toString().padLeft(2, '0')}';
  }

  /// 조회수 포맷 (999 이하 → "999", 1000 이상 → "1.2K")
  static String _fmtCount(int n) {
    if (n < 1000) return '$n';
    return '${(n / 1000).toStringAsFixed(1)}K';
  }

  /// "1:23" 형식 (분:초)
  static String _fmtDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

// ─── 서브 위젯 ────────────────────────────────────────────────────────────────

/// 좌상단 사진/영상 타입 칩
class _MediaTypeBadge extends StatelessWidget {
  final bool isVideo;
  const _MediaTypeBadge({required this.isVideo});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(160),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isVideo ? Icons.videocam : Icons.photo_camera,
            color: Colors.white,
            size: 11,
          ),
          const SizedBox(width: 3),
          Text(
            isVideo ? '영상' : '사진',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

/// 우하단 영상 길이 (YouTube 스타일)
class _DurationBadge extends StatelessWidget {
  final int seconds;
  const _DurationBadge({required this.seconds});

  @override
  Widget build(BuildContext context) {
    final m = seconds ~/ 60;
    final s = (seconds % 60).toString().padLeft(2, '0');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(180),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '$m:$s',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
