import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../screens/users/user_profile_screen.dart';
import '../utils/constants.dart';

/// 좋아요한 사용자 목록 시트 (vlog/댓글 공용)
///
/// stream: 각 항목 { uid, displayName, photoUrl, createdAt(DateTime?) }
class LikersSheet {
  static Future<void> open({
    required BuildContext context,
    required String title,
    required Stream<List<Map<String, dynamic>>> stream,
  }) async {
    HapticFeedback.selectionClick();
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.55,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        builder: (ctx, scrollCtrl) => Column(
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
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 10),
              child: Row(
                children: [
                  const Icon(Icons.favorite,
                      color: AppColors.error, size: 20),
                  const SizedBox(width: 8),
                  Text(title,
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800)),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: StreamBuilder<List<Map<String, dynamic>>>(
                stream: stream,
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(
                        child: CircularProgressIndicator(
                            color: AppColors.primary));
                  }
                  final list = snap.data ?? [];
                  if (list.isEmpty) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(AppSpacing.xl),
                        child: Text(
                          '아직 좋아요한 사람이 없어요',
                          style: TextStyle(
                              fontSize: 13,
                              color: AppColors.textSecondary),
                        ),
                      ),
                    );
                  }
                  return ListView.separated(
                    controller: scrollCtrl,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: list.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1, indent: 70),
                    itemBuilder: (_, i) => _LikerTile(user: list[i]),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LikerTile extends StatelessWidget {
  final Map<String, dynamic> user;
  const _LikerTile({required this.user});

  String _relative(DateTime? d) {
    if (d == null) return '';
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 1) return '방금';
    if (diff.inMinutes < 60) return '${diff.inMinutes}분 전';
    if (diff.inHours < 24) return '${diff.inHours}시간 전';
    if (diff.inDays < 7) return '${diff.inDays}일 전';
    return '${d.month}/${d.day}';
  }

  @override
  Widget build(BuildContext context) {
    final uid = user['uid'] as String;
    final name = (user['displayName'] as String?) ?? '익명';
    final photo = user['photoUrl'] as String?;
    final hasPhoto = photo != null && photo.isNotEmpty;
    final createdAt = user['createdAt'] as DateTime?;

    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        Navigator.pop(context);
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => UserProfileScreen(
              uid: uid,
              name: name,
              photoUrl: photo,
            ),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.sm),
        child: Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: AppColors.primary.withValues(alpha: 0.12),
              backgroundImage: hasPhoto ? NetworkImage(photo) : null,
              child: !hasPhoto
                  ? Text(
                      name.isNotEmpty ? name[0].toUpperCase() : '?',
                      style: const TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.bold,
                          fontSize: 16),
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600),
                  ),
                  if (createdAt != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      _relative(createdAt),
                      style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary),
                    ),
                  ],
                ],
              ),
            ),
            const Icon(Icons.chevron_right,
                size: 18, color: AppColors.textDisabled),
          ],
        ),
      ),
    );
  }
}
