import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/friendship.dart';
import '../../models/vlog.dart';
import '../../services/firestore_service.dart';
import '../../services/friend_service.dart';
import '../../utils/constants.dart';
import '../../utils/marker_colors.dart';
import '../../utils/marker_emojis.dart';
import '../vlog/vlog_player_swiper_screen.dart';

/// 다른 사용자(또는 본인)의 프로필 화면 — 헤더 + 친구 관계 액션 + 그들의 vlog 그리드
class UserProfileScreen extends StatelessWidget {
  final String uid;
  final String name;
  final String? photoUrl;
  final String? email;

  const UserProfileScreen({
    super.key,
    required this.uid,
    required this.name,
    this.photoUrl,
    this.email,
  });

  @override
  Widget build(BuildContext context) {
    final isMe = FirebaseAuth.instance.currentUser?.uid == uid;
    return Scaffold(
      body: StreamBuilder<List<Vlog>>(
        stream: FirestoreService.watchUserVlogs(uid),
        builder: (context, snap) {
          final vlogs = snap.data ?? [];
          final totalLikes =
              vlogs.fold<int>(0, (sum, v) => sum + v.likeCount);
          final totalViews =
              vlogs.fold<int>(0, (sum, v) => sum + v.viewCount);

          return CustomScrollView(
            slivers: [
              SliverAppBar(
                backgroundColor: Theme.of(context).colorScheme.surface,
                elevation: 0,
                scrolledUnderElevation: 1,
                pinned: true,
                title: Text(
                  name,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 17),
                ),
              ),
              // 헤더 — 아바타 + 통계 + 친구 액션
              SliverToBoxAdapter(
                child: Container(
                  color: Theme.of(context).colorScheme.surface,
                  padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.md),
                  child: Column(
                    children: [
                      _Avatar(
                          name: name, photoUrl: photoUrl, isLarge: true),
                      const SizedBox(height: AppSpacing.md),
                      Text(name,
                          style: const TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.bold)),
                      if (email != null && email!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(email!,
                            style: const TextStyle(
                                fontSize: 13,
                                color: AppColors.textSecondary)),
                      ],
                      const SizedBox(height: AppSpacing.md),
                      // 통계 타일 3개
                      Row(
                        children: [
                          Expanded(
                              child: _StatTile(
                                  label: '브이로그',
                                  value: '${vlogs.length}',
                                  icon: Icons.movie_outlined,
                                  color: AppColors.primary)),
                          const SizedBox(width: 8),
                          Expanded(
                              child: _StatTile(
                                  label: '좋아요',
                                  value: '$totalLikes',
                                  icon: Icons.favorite,
                                  color: AppColors.error)),
                          const SizedBox(width: 8),
                          Expanded(
                              child: _StatTile(
                                  label: '조회수',
                                  value: _fmtCount(totalViews),
                                  icon: Icons.visibility_outlined,
                                  color: const Color(0xFF7C4DFF))),
                        ],
                      ),
                      if (!isMe) ...[
                        const SizedBox(height: AppSpacing.md),
                        _FriendActionButton(
                          friendUid: uid,
                          friendName: name,
                          friendPhotoUrl: photoUrl,
                          friendEmail: email,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SliverToBoxAdapter(
                  child: SizedBox(height: AppSpacing.sm)),
              // 최근 활동 카드 (가장 최근 vlog 1개)
              if (vlogs.isNotEmpty)
                SliverToBoxAdapter(child: _RecentActivityCard(vlog: vlogs.first)),
              const SliverToBoxAdapter(
                  child: SizedBox(height: AppSpacing.sm)),
              // 최근 활동 타임라인 (최근 5 vlog 가로 스크롤)
              if (vlogs.length >= 2)
                SliverToBoxAdapter(
                    child: _RecentTimeline(vlogs: vlogs.take(8).toList())),
              const SliverToBoxAdapter(
                  child: SizedBox(height: AppSpacing.sm)),
              // 브이로그 헤더 + 카테고리 필터 + 그리드 (필터 가능 섹션)
              if (snap.connectionState == ConnectionState.waiting)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(AppSpacing.xl),
                    child: Center(
                        child: CircularProgressIndicator(
                            color: AppColors.primary)),
                  ),
                )
              else if (vlogs.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Padding(
                      padding: EdgeInsets.all(AppSpacing.xl),
                      child: Text('아직 올린 브이로그가 없어요',
                          style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 14)),
                    ),
                  ),
                )
              else
                SliverToBoxAdapter(
                  child: _UserVlogsGridSection(vlogs: vlogs),
                ),

              const SliverToBoxAdapter(
                  child: SizedBox(height: AppSpacing.xl)),
            ],
          );
        },
      ),
    );
  }

  static String _fmtCount(int n) {
    if (n < 1000) return '$n';
    if (n < 10000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '${(n / 1000).toStringAsFixed(0)}K';
  }
}

// ─── 친구 액션 버튼 ───────────────────────────────────────────────────────────
class _FriendActionButton extends StatelessWidget {
  final String friendUid;
  final String friendName;
  final String? friendPhotoUrl;
  final String? friendEmail;
  const _FriendActionButton({
    required this.friendUid,
    required this.friendName,
    this.friendPhotoUrl,
    this.friendEmail,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Friendship?>(
      future: FriendService.getFriendship(friendUid),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const SizedBox(
            height: 38,
            child: Center(
                child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppColors.primary))),
          );
        }
        final f = snap.data;
        if (f == null) {
          return SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () async {
                HapticFeedback.mediumImpact();
                try {
                  await FriendService.sendRequest(
                    toUid: friendUid,
                    toName: friendName,
                    toPhotoUrl: friendPhotoUrl,
                    toEmail: friendEmail,
                  );
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text('✉️ $friendName님에게 친구 요청을 보냈습니다'),
                      backgroundColor: AppColors.secondary,
                      duration: const Duration(seconds: 2),
                    ));
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(e.toString().replaceAll(
                          'Exception: ', '')),
                      backgroundColor: AppColors.error,
                    ));
                  }
                }
              },
              icon: const Icon(Icons.person_add, size: 18),
              label: const Text('친구 추가'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(AppRadius.full)),
              ),
            ),
          );
        }
        // 이미 친구 관계 있음 — 상태 표시
        String label;
        IconData icon;
        Color color;
        switch (f.status) {
          case FriendshipStatus.accepted:
            label = '친구';
            icon = Icons.check;
            color = AppColors.secondary;
            break;
          case FriendshipStatus.pending:
            label = '요청 보냄';
            icon = Icons.schedule;
            color = AppColors.textSecondary;
            break;
          case FriendshipStatus.incoming:
            label = '요청 받음';
            icon = Icons.inbox_outlined;
            color = AppColors.primary;
            break;
        }
        return SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: null,
            icon: Icon(icon, size: 18, color: color),
            label: Text(label, style: TextStyle(color: color)),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: color.withValues(alpha: 0.4)),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.full)),
            ),
          ),
        );
      },
    );
  }
}

// ─── 통계 타일 ────────────────────────────────────────────────────────────────
class _StatTile extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;
  const _StatTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(height: 4),
          Text(value,
              style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: color)),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

// ─── 아바타 + 그라디언트 링 ──────────────────────────────────────────────────
class _Avatar extends StatelessWidget {
  final String name;
  final String? photoUrl;
  final bool isLarge;
  const _Avatar({required this.name, this.photoUrl, this.isLarge = false});

  @override
  Widget build(BuildContext context) {
    final radius = isLarge ? 44.0 : 22.0;
    final hasPhoto = photoUrl != null && photoUrl!.isNotEmpty;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(colors: [
          Color(0xFF1A73E8),
          Color(0xFF7C4DFF),
          Color(0xFFEC407A),
        ]),
      ),
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Theme.of(context).colorScheme.surface,
        ),
        child: CircleAvatar(
          radius: radius,
          backgroundColor: AppColors.primary.withAlpha(30),
          backgroundImage: hasPhoto ? NetworkImage(photoUrl!) : null,
          child: !hasPhoto
              ? Text(
                  name.isNotEmpty ? name[0].toUpperCase() : '?',
                  style: TextStyle(
                      fontSize: isLarge ? 32 : 18,
                      color: AppColors.primary,
                      fontWeight: FontWeight.bold),
                )
              : null,
        ),
      ),
    );
  }
}

// ─── 그리드 썸네일 ────────────────────────────────────────────────────────────
class _GridThumb extends StatelessWidget {
  final Vlog vlog;
  final List<Vlog>? playlist;
  const _GridThumb({required this.vlog, this.playlist});

  @override
  Widget build(BuildContext context) {
    final thumb = vlog.thumbnailUrl ?? '';
    final isVideo = (vlog.videoUrl ?? '').isNotEmpty;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        VlogPlayerSwiperScreen.open(
          context,
          vlogs: playlist ?? [vlog],
          initial: vlog,
        );
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          thumb.isNotEmpty
              ? Image.network(thumb,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _placeholder(isVideo))
              : _placeholder(isVideo),
          if (isVideo)
            Positioned(
              top: 4,
              left: 4,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: Colors.black.withAlpha(140),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.play_arrow_rounded,
                    size: 14, color: Colors.white),
              ),
            )
          else if (vlog.photoUrls.length > 1)
            Positioned(
              top: 4,
              right: 4,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: Colors.black.withAlpha(140),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.collections,
                    size: 13, color: Colors.white),
              ),
            ),
        ],
      ),
    );
  }

  Widget _placeholder(bool isVideo) {
    return Container(
      color: AppColors.surfaceVariant,
      child: Center(
          child: Icon(
        isVideo ? Icons.videocam : Icons.photo,
        size: 26,
        color: AppColors.textDisabled,
      )),
    );
  }
}

// ─── 최근 활동 타임라인 (가로 스크롤 카드) ──────────────────────────────
class _RecentTimeline extends StatelessWidget {
  final List<Vlog> vlogs;
  const _RecentTimeline({required this.vlogs});

  String _short(DateTime d) {
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 60) return '${diff.inMinutes}분';
    if (diff.inHours < 24) return '${diff.inHours}시';
    if (diff.inDays < 7) return '${diff.inDays}일';
    return '${d.month}/${d.day}';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, 4, 0, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 6, right: AppSpacing.md),
            child: Row(
              children: [
                Text('📍', style: TextStyle(fontSize: 13)),
                SizedBox(width: 4),
                Text(
                  '최근 활동 타임라인',
                  style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textSecondary,
                      letterSpacing: 0.2),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 88,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(right: AppSpacing.md),
              itemCount: vlogs.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final v = vlogs[i];
                final emoji = v.markerEmoji ?? '📍';
                final color = MarkerColors.fromValue(v.markerColor);
                return GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    VlogPlayerSwiperScreen.open(
                      context,
                      vlogs: vlogs,
                      initial: v,
                    );
                  },
                  child: Container(
                    width: 110,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      border:
                          Border.all(color: color.withValues(alpha: 0.25)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(emoji,
                                style: const TextStyle(fontSize: 18)),
                            const Spacer(),
                            Text(_short(v.createdAt),
                                style: const TextStyle(
                                    fontSize: 10,
                                    color: AppColors.textSecondary,
                                    fontWeight: FontWeight.w600)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Expanded(
                          child: Text(
                            v.title.isEmpty ? v.placeName : v.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                height: 1.3),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ─── 최근 활동 카드 ───────────────────────────────────────────────────────
class _RecentActivityCard extends StatelessWidget {
  final Vlog vlog;
  const _RecentActivityCard({required this.vlog});

  String _relative(DateTime d) {
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 1) return '방금';
    if (diff.inMinutes < 60) return '${diff.inMinutes}분 전';
    if (diff.inHours < 24) return '${diff.inHours}시간 전';
    if (diff.inDays < 7) return '${diff.inDays}일 전';
    final m = d.month.toString();
    final dd = d.day.toString();
    return '$m/$dd';
  }

  @override
  Widget build(BuildContext context) {
    final emoji = vlog.markerEmoji ?? '📍';
    final cat = MarkerEmojis.fromEmoji(vlog.markerEmoji);
    final color = MarkerColors.fromValue(vlog.markerColor);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          VlogPlayerSwiperScreen.open(
            context,
            vlogs: [vlog],
            initial: vlog,
          );
        },
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                color.withValues(alpha: 0.08),
                color.withValues(alpha: 0.02),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: color.withValues(alpha: 0.25)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Text('최근 활동',
                      style: TextStyle(
                          fontSize: 10.5,
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.4)),
                  const Spacer(),
                  Text(_relative(vlog.createdAt),
                      style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w600)),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(emoji, style: const TextStyle(fontSize: 30)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 5, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: color,
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: Text(
                                cat.category,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.4),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                cat.label,
                                style: const TextStyle(
                                    fontSize: 11.5,
                                    color: AppColors.textSecondary,
                                    fontWeight: FontWeight.w600),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          vlog.title.isEmpty
                              ? vlog.placeName
                              : vlog.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700),
                        ),
                        if ((vlog.address ?? '').isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              const Icon(Icons.place,
                                  size: 11,
                                  color: AppColors.textDisabled),
                              const SizedBox(width: 2),
                              Expanded(
                                child: Text(
                                  vlog.address!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 11,
                                      color: AppColors.textSecondary),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right,
                      size: 18, color: AppColors.textDisabled),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── 유저 vlog 그리드 + 카테고리 필터 섹션 ────────────────────────────────
class _UserVlogsGridSection extends StatefulWidget {
  final List<Vlog> vlogs;
  const _UserVlogsGridSection({required this.vlogs});

  @override
  State<_UserVlogsGridSection> createState() =>
      _UserVlogsGridSectionState();
}

class _UserVlogsGridSectionState extends State<_UserVlogsGridSection> {
  String? _filter;

  @override
  Widget build(BuildContext context) {
    final all = widget.vlogs;
    final filtered = _filter == null
        ? all
        : all.where((v) {
            if (v.markerEmoji == null) return _filter == '일반';
            return MarkerEmojis.fromEmoji(v.markerEmoji).category ==
                _filter;
          }).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.md, AppSpacing.sm, AppSpacing.md, 4),
          child: Row(
            children: [
              const Text('브이로그',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold)),
              const SizedBox(width: 6),
              Text('${filtered.length}',
                  style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ),
        SizedBox(
          height: 34,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md, vertical: 4),
            children: [
              _UserCatChip(
                label: '전체',
                emoji: '🌐',
                selected: _filter == null,
                onTap: () => setState(() => _filter = null),
              ),
              const SizedBox(width: 6),
              ...MarkerEmojis.groups.map((g) => Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: _UserCatChip(
                      label: g.name,
                      emoji: g.hint,
                      selected: _filter == g.name,
                      onTap: () => setState(() => _filter = g.name),
                    ),
                  )),
            ],
          ),
        ),
        const SizedBox(height: 4),
        if (filtered.isEmpty)
          const Padding(
            padding: EdgeInsets.all(AppSpacing.xl),
            child: Center(
              child: Text('이 카테고리에 해당하는 vlog가 없어요',
                  style: TextStyle(
                      fontSize: 12.5, color: AppColors.textSecondary)),
            ),
          )
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.all(2),
            gridDelegate:
                const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 2,
              mainAxisSpacing: 2,
            ),
            itemCount: filtered.length,
            itemBuilder: (_, i) =>
                _GridThumb(vlog: filtered[i], playlist: filtered),
          ),
      ],
    );
  }
}

class _UserCatChip extends StatelessWidget {
  final String label;
  final String emoji;
  final bool selected;
  final VoidCallback onTap;
  const _UserCatChip({
    required this.label,
    required this.emoji,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppRadius.full),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 12)),
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: selected
                      ? Colors.white
                      : Theme.of(context).colorScheme.onSurface,
                )),
          ],
        ),
      ),
    );
  }
}
