import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/friendship.dart';
import '../models/user_status.dart';
import '../screens/live_map/live_map_screen.dart';
import '../services/friend_service.dart';
import '../services/user_status_service.dart';
import '../utils/constants.dart';

/// 알림 통합 시트 — 받은 호출(ping) + 들어온 친구 요청
///
/// `NotificationsSheet.open()` → 시트 (deprecated, NotificationsScreen 사용 권장)
/// `NotificationsScreen()` → 전체화면 (인스타·트위터 스타일)
class NotificationsSheet extends StatelessWidget {
  const NotificationsSheet({super.key});

  /// 전체화면 페이지로 push (sheet 대체 — 더 넓은 영역에서 알림 관리)
  static Future<void> open(BuildContext context) {
    HapticFeedback.selectionClick();
    return Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const NotificationsScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (_, scrollCtrl) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
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
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: Row(
                children: [
                  Icon(Icons.notifications_outlined,
                      color: AppColors.primary, size: 22),
                  SizedBox(width: 10),
                  Text(
                    '알림',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: uid == null
                  ? const _EmptyState(
                      icon: Icons.login,
                      title: '로그인이 필요해요',
                      message: '로그인하면 호출/요청을 받을 수 있어요',
                    )
                  : _NotificationsList(uid: uid, scrollCtrl: scrollCtrl),
            ),
          ],
        ),
      ),
    );
  }
}

/// 알림 전체화면 페이지 — 벨 아이콘 탭 시 push (TabBar로 호출/요청 분리)
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl = TabController(length: 2, vsync: this);

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('알림')),
        body: const _EmptyState(
          icon: Icons.login,
          title: '로그인이 필요해요',
          message: '로그인하면 호출/요청을 받을 수 있어요',
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.surface,
        elevation: 0,
        scrolledUnderElevation: 1,
        title: const Row(
          children: [
            Icon(Icons.notifications_outlined,
                color: AppColors.primary, size: 22),
            SizedBox(width: 10),
            Text('알림',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800)),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: StreamBuilder<List<Ping>>(
            stream: UserStatusService.watchMyPings(uid),
            builder: (context, pingSnap) {
              final pingCount = (pingSnap.data ?? []).length;
              return StreamBuilder<List<Friendship>>(
                stream: FriendService.watchIncomingRequests(),
                builder: (context, reqSnap) {
                  final reqCount = (reqSnap.data ?? []).length;
                  return TabBar(
                    controller: _tabCtrl,
                    labelColor: AppColors.primary,
                    unselectedLabelColor: AppColors.textSecondary,
                    indicatorColor: AppColors.primary,
                    indicatorWeight: 2.5,
                    labelStyle: const TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w700),
                    tabs: [
                      Tab(
                        icon: const Icon(Icons.notifications_active,
                            size: 18),
                        text: pingCount > 0 ? '호출 $pingCount' : '호출',
                      ),
                      Tab(
                        icon: const Icon(Icons.person_add_outlined,
                            size: 18),
                        text:
                            reqCount > 0 ? '친구 요청 $reqCount' : '친구 요청',
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [
          _PingsTab(uid: uid),
          _RequestsTab(),
        ],
      ),
    );
  }
}

class _PingsTab extends StatelessWidget {
  final String uid;
  const _PingsTab({required this.uid});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Ping>>(
      stream: UserStatusService.watchMyPings(uid),
      builder: (context, snap) {
        final pings = snap.data ?? [];
        if (pings.isEmpty) {
          return const _EmptyState(
            icon: Icons.notifications_off_outlined,
            title: '받은 호출이 없어요',
            message: '친구가 호출하면 여기에 표시됩니다',
          );
        }
        return ListView(
          padding: const EdgeInsets.symmetric(vertical: 6),
          children: pings.map((p) => _PingTile(ping: p, uid: uid)).toList(),
        );
      },
    );
  }
}

class _RequestsTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Friendship>>(
      stream: FriendService.watchIncomingRequests(),
      builder: (context, snap) {
        final requests = snap.data ?? [];
        if (requests.isEmpty) {
          return const _EmptyState(
            icon: Icons.person_off_outlined,
            title: '받은 요청이 없어요',
            message: '누군가 친구 요청하면 여기에 표시됩니다',
          );
        }
        return ListView(
          padding: const EdgeInsets.symmetric(vertical: 6),
          children:
              requests.map((r) => _FriendRequestTile(friendship: r)).toList(),
        );
      },
    );
  }
}

class _NotificationsList extends StatelessWidget {
  final String uid;
  final ScrollController scrollCtrl;
  const _NotificationsList({required this.uid, required this.scrollCtrl});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Ping>>(
      stream: UserStatusService.watchMyPings(uid),
      builder: (context, pingSnap) {
        return StreamBuilder<List<Friendship>>(
          stream: FriendService.watchIncomingRequests(),
          builder: (context, reqSnap) {
            final pings = pingSnap.data ?? [];
            final requests = reqSnap.data ?? [];

            if (pings.isEmpty && requests.isEmpty) {
              return const _EmptyState(
                icon: Icons.inbox_outlined,
                title: '받은 알림이 없어요',
                message: '친구가 호출하거나 요청하면 여기에 표시됩니다',
              );
            }

            return ListView(
              controller: scrollCtrl,
              padding: const EdgeInsets.symmetric(vertical: 6),
              children: [
                if (requests.isNotEmpty) ...[
                  _SectionTitle(
                    icon: Icons.person_add_outlined,
                    title: '친구 요청',
                    count: requests.length,
                  ),
                  ...requests.map((r) => _FriendRequestTile(friendship: r)),
                  const SizedBox(height: 12),
                ],
                if (pings.isNotEmpty) ...[
                  _SectionTitle(
                    icon: Icons.notifications_active_outlined,
                    title: '받은 호출',
                    count: pings.length,
                  ),
                  ...pings.map((p) => _PingTile(ping: p, uid: uid)),
                ],
                const SizedBox(height: 16),
              ],
            );
          },
        );
      },
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final IconData icon;
  final String title;
  final int count;
  const _SectionTitle({
    required this.icon,
    required this.title,
    required this.count,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppColors.textSecondary),
          const SizedBox(width: 6),
          Text(
            title,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: AppColors.textSecondary,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '$count',
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: AppColors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── 호출(Ping) 타일 — 큰 이모지 + 메시지 + 받은 시간 + 확인 액션 ─────────

class _PingTile extends StatelessWidget {
  final Ping ping;
  final String uid;
  const _PingTile({required this.ping, required this.uid});

  String _relativeTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return '방금 전';
    if (diff.inHours < 1) return '${diff.inMinutes}분 전';
    if (diff.inHours < 24) return '${diff.inHours}시간 전';
    return '${diff.inDays}일 전';
  }

  Future<void> _open(BuildContext context) async {
    HapticFeedback.selectionClick();
    Navigator.pop(context); // 시트 닫기
    // 친구지도로 이동
    if (context.mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const LiveMapScreen()),
      );
    }
  }

  Future<void> _dismiss(BuildContext context) async {
    HapticFeedback.lightImpact();
    try {
      await UserStatusService.deletePing(uid, ping.id);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 4, 14, 4),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFFFF8E1),
            Color(0xFFFFECB3),
          ],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: const Color(0xFFFFB300).withValues(alpha: 0.4),
            width: 1),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _open(context),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Text(ping.emoji,
                      style: const TextStyle(fontSize: 28)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${ping.fromName}님의 호출',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '"${ping.message}"',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _relativeTime(ping.createdAt),
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textDisabled,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close,
                      color: AppColors.textSecondary, size: 20),
                  tooltip: '확인',
                  onPressed: () => _dismiss(context),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── 친구 요청 타일 — 수락/거절 버튼 ─────────────────────────────────────

class _FriendRequestTile extends StatelessWidget {
  final Friendship friendship;
  const _FriendRequestTile({required this.friendship});

  Future<void> _accept(BuildContext context) async {
    HapticFeedback.mediumImpact();
    try {
      await FriendService.acceptRequest(friendship.friendUid);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('🎉 ${friendship.effectiveName}님과 친구가 됐습니다'),
            backgroundColor: AppColors.secondary,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('수락 실패: $e'),
              backgroundColor: AppColors.error),
        );
      }
    }
  }

  Future<void> _reject(BuildContext context) async {
    HapticFeedback.selectionClick();
    try {
      await FriendService.removeFriendship(friendship.friendUid);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final name = friendship.effectiveName;
    final letter = (name.isNotEmpty ? name[0] : '?').toUpperCase();
    final hasPhoto =
        friendship.photoUrl != null && friendship.photoUrl!.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 8, 4),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.primary.withValues(alpha: 0.12),
              image: hasPhoto
                  ? DecorationImage(
                      image: NetworkImage(friendship.photoUrl!),
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
            alignment: Alignment.center,
            child: hasPhoto
                ? null
                : Text(letter,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primary,
                    )),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(name,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    )),
                if (friendship.email != null &&
                    friendship.email!.isNotEmpty)
                  Text(
                    friendship.email!,
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textSecondary),
                  ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => _reject(context),
            child: const Text('거절',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () => _accept(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 8),
              minimumSize: Size.zero,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.full)),
            ),
            child: const Text('수락',
                style:
                    TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primary.withValues(alpha: 0.08),
              ),
              child: Icon(icon, size: 38, color: AppColors.primary),
            ),
            const SizedBox(height: 14),
            Text(title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                )),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
