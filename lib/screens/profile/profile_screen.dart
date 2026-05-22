import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/vlog.dart';
import '../../providers/auth_provider.dart' as ap;
import '../../screens/auth/login_screen.dart';
import '../../screens/vlog/vlog_player_screen.dart';
import '../../services/firestore_service.dart';
import '../../utils/constants.dart';
import '../../widgets/vlog_card.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<ap.AuthProvider>();
    final user = auth.user;

    if (user == null) return _GuestView();
    return _UserView(user: user);
  }
}

// ─── 비로그인 뷰 ──────────────────────────────────────────────────────────────
class _GuestView extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.person_outline,
                size: 72, color: AppColors.textDisabled),
            const SizedBox(height: 16),
            const Text(
              '로그인이 필요합니다',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary),
            ),
            const SizedBox(height: 8),
            const Text(
              '로그인하고 내 브이로그를 관리하세요',
              style: TextStyle(
                  color: AppColors.textSecondary, fontSize: 14),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const LoginScreen())),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                    horizontal: 32, vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(AppRadius.full)),
              ),
              child: const Text('로그인'),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── 로그인 뷰 ────────────────────────────────────────────────────────────────
class _UserView extends StatelessWidget {
  final User user;
  const _UserView({required this.user});

  @override
  Widget build(BuildContext context) {
    // 단일 StreamBuilder로 통계 + 목록 모두 처리 (Firestore 구독 1개)
    return StreamBuilder<List<Vlog>>(
      stream: FirestoreService.watchUserVlogs(user.uid),
      builder: (context, snapshot) {
        final isLoading = snapshot.connectionState == ConnectionState.waiting;
        final vlogs = snapshot.data ?? [];
        final totalLikes = vlogs.fold<int>(0, (sum, v) => sum + v.likeCount);
        final totalViews = vlogs.fold<int>(0, (sum, v) => sum + v.viewCount);

        return Scaffold(
          backgroundColor: AppColors.background,
          body: CustomScrollView(
            slivers: [
              // 앱바
              SliverAppBar(
                backgroundColor: AppColors.surface,
                floating: true,
                title: const Text(
                  '프로필',
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 18),
                ),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.logout,
                        color: AppColors.textSecondary),
                    onPressed: () => _confirmSignOut(context),
                  ),
                ],
              ),

              // 프로필 헤더 + 통계
              SliverToBoxAdapter(
                child: Container(
                  color: AppColors.surface,
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Column(
                    children: [
                      // 아바타
                      CircleAvatar(
                        radius: 40,
                        backgroundColor: AppColors.primary.withAlpha(30),
                        backgroundImage: user.photoURL != null
                            ? NetworkImage(user.photoURL!)
                            : null,
                        child: user.photoURL == null
                            ? Text(
                                (user.displayName ?? user.email ?? 'U')
                                    .substring(0, 1)
                                    .toUpperCase(),
                                style: const TextStyle(
                                    fontSize: 32,
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.bold),
                              )
                            : null,
                      ),
                      const SizedBox(height: AppSpacing.sm),

                      // 이름 + 수정 버튼
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            user.displayName ?? '사용자',
                            style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary),
                          ),
                          const SizedBox(width: 6),
                          GestureDetector(
                            onTap: () =>
                                _editName(context, user.displayName ?? ''),
                            child: const Icon(
                              Icons.edit_outlined,
                              size: 16,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        user.email ?? '',
                        style: const TextStyle(
                            fontSize: 13, color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: AppSpacing.md),

                      // 통계 행
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _Stat(label: '브이로그', value: '${vlogs.length}'),
                          _Divider(),
                          _Stat(label: '좋아요', value: '$totalLikes'),
                          _Divider(),
                          _Stat(label: '조회수', value: '$totalViews'),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.sm)),

              // 내 브이로그 목록 헤더
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                      AppSpacing.md, AppSpacing.sm, AppSpacing.md, 4),
                  child: Text(
                    '내 브이로그',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary),
                  ),
                ),
              ),

              // 내 브이로그 목록
              if (isLoading)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(AppSpacing.xl),
                    child: Center(
                        child: CircularProgressIndicator(
                            color: AppColors.primary)),
                  ),
                )
              else if (vlogs.isEmpty)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(AppSpacing.xl),
                    child: Center(
                      child: Text(
                        '아직 업로드한 브이로그가 없습니다.',
                        style: TextStyle(
                            color: AppColors.textSecondary, fontSize: 14),
                      ),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md),
                  sliver: SliverGrid(
                    delegate: SliverChildBuilderDelegate(
                      (_, i) => VlogCard(
                        vlog: vlogs[i],
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) =>
                                  VlogPlayerScreen(vlog: vlogs[i])),
                        ),
                        onLongPress: () =>
                            _confirmDelete(context, vlogs[i]),
                      ),
                      childCount: vlogs.length,
                    ),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: AppSpacing.sm,
                      mainAxisSpacing: AppSpacing.sm,
                      childAspectRatio: 0.75,
                    ),
                  ),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xl)),
            ],
          ),
        );
      },
    );
  }

  Future<void> _editName(BuildContext context, String current) async {
    final ctrl = TextEditingController(text: current);
    final newName = await showDialog<String>(
      context: context,
      builder: (dlgCtx) => AlertDialog(
        title: const Text('프로필 이름 수정'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLength: 20,
          decoration: const InputDecoration(
            labelText: '이름',
            hintText: '표시될 이름을 입력하세요',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (v) => Navigator.pop(dlgCtx, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dlgCtx),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dlgCtx, ctrl.text.trim()),
            child: const Text('저장',
                style: TextStyle(color: AppColors.primary)),
          ),
        ],
      ),
    );
    // ctrl.dispose()를 여기서 호출하면 다이얼로그 fade-out 중
    // TextField 포커스 해제 이벤트가 이미 disposed된 컨트롤러를 참조해 크래시.
    // 로컬 변수이므로 GC에 맡기는 것이 안전함.

    if (newName == null || newName.isEmpty || !context.mounted) return;
    final auth = context.read<ap.AuthProvider>();
    final ok = await auth.updateDisplayName(newName);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ok ? '이름이 "$newName"으로 변경되었습니다.' : '이름 변경에 실패했습니다.'),
          backgroundColor: ok ? AppColors.secondary : AppColors.error,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _confirmDelete(BuildContext context, Vlog vlog) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dlgCtx) => AlertDialog(
        title: const Text('브이로그 삭제'),
        content: Text(
          '"${vlog.title}"을(를) 삭제하시겠습니까?\n영상·사진 파일도 함께 삭제됩니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dlgCtx, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dlgCtx, true),
            child: const Text(
              '삭제',
              style: TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      await FirestoreService.deleteVlog(vlog.id);
    }
  }

  Future<void> _confirmSignOut(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dlgCtx) => AlertDialog(
        title: const Text('로그아웃'),
        content: const Text('로그아웃 하시겠습니까?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dlgCtx, false),
              child: const Text('취소')),
          TextButton(
              onPressed: () => Navigator.pop(dlgCtx, true),
              child: const Text('로그아웃',
                  style: TextStyle(color: AppColors.error))),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      await context.read<ap.AuthProvider>().signOut();
    }
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  const _Stat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value,
            style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary)),
        const SizedBox(height: 2),
        Text(label,
            style: const TextStyle(
                fontSize: 12, color: AppColors.textSecondary)),
      ],
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(width: 1, height: 32, color: AppColors.surfaceVariant);
  }
}
