import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/vlog.dart';
import '../../providers/auth_provider.dart' as ap;
import '../../screens/auth/login_screen.dart';
import '../../screens/friends/friend_list_screen.dart';
import '../../screens/vlog/vlog_player_swiper_screen.dart';
import '../../services/firebase_storage_service.dart';
import '../../services/firestore_service.dart';
import '../../services/location_tracking_service.dart';
import '../../providers/theme_provider.dart';
import '../../services/app_update_service.dart';
import '../../utils/marker_emojis.dart';
import '../../models/remote_version.dart';
import '../../widgets/app_version_label.dart';
import '../legal/legal_screen.dart';
import '../../services/web_cache_reload_stub.dart'
    if (dart.library.io) '../../services/web_cache_reload_io.dart'
    if (dart.library.html) '../../services/web_cache_reload_web.dart' as web;
import '../../services/web_version_check_service.dart';
import '../../widgets/update_prompt_sheet.dart';
import '../../utils/constants.dart';
import '../../utils/sheets.dart';
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
                  fontWeight: FontWeight.bold),
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
          body: CustomScrollView(
            slivers: [
              // 앱바
              SliverAppBar(
                backgroundColor: Theme.of(context).colorScheme.surface,
                floating: true,
                title: const Text(
                  '프로필',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18),
                ),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.people_outline,
                        color: AppColors.primary),
                    tooltip: '친구',
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const FriendListScreen()),
                      );
                    },
                  ),
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
                  color: Theme.of(context).colorScheme.surface,
                  padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.md),
                  child: Column(
                    children: [
                      // 그라디언트 링 아바타 (인스타 스타일, 탭하면 사진 등록)
                      GestureDetector(
                        onTap: () => _editAvatar(context, user),
                        child: Stack(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(3),
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: LinearGradient(
                                  colors: [
                                    Color(0xFF1A73E8),
                                    Color(0xFF7C4DFF),
                                    Color(0xFFEC407A),
                                  ],
                                ),
                              ),
                              child: Container(
                                padding: const EdgeInsets.all(3),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Theme.of(context).colorScheme.surface,
                                ),
                                child: CircleAvatar(
                                  radius: 44,
                                  backgroundColor:
                                      AppColors.primary.withAlpha(30),
                                  backgroundImage: user.photoURL != null
                                      ? NetworkImage(user.photoURL!)
                                      : null,
                                  child: user.photoURL == null
                                      ? Text(
                                          (user.displayName ??
                                                  user.email ??
                                                  'U')
                                              .substring(0, 1)
                                              .toUpperCase(),
                                          style: const TextStyle(
                                              fontSize: 32,
                                              color: AppColors.primary,
                                              fontWeight: FontWeight.bold),
                                        )
                                      : null,
                                ),
                              ),
                            ),
                            // 카메라 배지 (우하단)
                            Positioned(
                              right: 2,
                              bottom: 2,
                              child: Container(
                                width: 30,
                                height: 30,
                                decoration: BoxDecoration(
                                  color: AppColors.primary,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                      color: AppColors.surface, width: 2.5),
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppColors.primary
                                          .withValues(alpha: 0.4),
                                      blurRadius: 6,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: const Icon(
                                  Icons.photo_camera,
                                  color: Colors.white,
                                  size: 14,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),

                      // 이름 + 수정 버튼
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            user.displayName ?? '사용자',
                            style: const TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(width: 6),
                          GestureDetector(
                            onTap: () =>
                                _editName(context, user.displayName ?? ''),
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Icon(
                                Icons.edit_outlined,
                                size: 13,
                                color: AppColors.textSecondary,
                              ),
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

                      // 통계 칩 (3개 그리드)
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
                    ],
                  ),
                ),
              ),

              const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.md)),

              // ── 상단 영역: 발자취 + 테마 + 설정 (인스타·트위터 스타일) ────
              SliverToBoxAdapter(child: _LocationStatsCard(vlogs: vlogs)),
              const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.sm)),
              const SliverToBoxAdapter(child: _ThemeModeToggle()),
              const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.sm)),
              const SliverToBoxAdapter(child: _BgLocationToggle()),
              const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.sm)),
              SliverToBoxAdapter(child: _SavedVlogsButton(uid: user.uid)),
              const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xs)),
              const SliverToBoxAdapter(child: _CheckUpdateButton()),
              const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xs)),
              // 마스터 전용 — 새 버전 발행
              if (user.email == 'jaduck9@gmail.com')
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                        vertical: AppSpacing.xs),
                    child: OutlinedButton.icon(
                      onPressed: () => PublishUpdateDialog.show(context),
                      icon: const Icon(Icons.rocket_launch, size: 16),
                      label: const Text('🚀 새 버전 발행 (마스터)'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        side: BorderSide(
                            color: AppColors.primary
                                .withValues(alpha: 0.4)),
                        minimumSize:
                            const Size(double.infinity, 42),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                              AppRadius.md),
                        ),
                      ),
                    ),
                  ),
                ),

              const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.lg)),

              // ── 내 브이로그 목록 헤더 ─────────────────────────────────────
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                      AppSpacing.md, AppSpacing.sm, AppSpacing.md, 4),
                  child: Text(
                    '내 브이로그',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold),
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
                        onTap: () => VlogPlayerSwiperScreen.open(
                          context,
                          vlogs: vlogs,
                          initial: vlogs[i],
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

              const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.md)),
              // 약관·개인정보 처리방침 링크
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      TextButton(
                        onPressed: () {
                          HapticFeedback.selectionClick();
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const LegalScreen(
                                  type: LegalDocType.terms),
                            ),
                          );
                        },
                        child: const Text('이용약관',
                            style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary)),
                      ),
                      const Text(' · ',
                          style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textDisabled)),
                      TextButton(
                        onPressed: () {
                          HapticFeedback.selectionClick();
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const LegalScreen(
                                  type: LegalDocType.privacy),
                            ),
                          );
                        },
                        child: const Text('개인정보 처리방침',
                            style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                                fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ),
                ),
              ),
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  child: AppVersionLabel(),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xl)),
            ],
          ),
        );
      },
    );
  }

  /// 아바타 사진 등록/변경/제거
  Future<void> _editAvatar(BuildContext context, User user) async {
    HapticFeedback.selectionClick();
    final hasPhoto = user.photoURL != null && user.photoURL!.isNotEmpty;

    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.textDisabled.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              '프로필 사진',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.photo_library,
                    color: AppColors.primary, size: 20),
              ),
              title: const Text('갤러리에서 선택'),
              onTap: () => Navigator.pop(sheetCtx, 'pick'),
            ),
            if (hasPhoto)
              ListTile(
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.delete_outline,
                      color: AppColors.error, size: 20),
                ),
                title: const Text('현재 사진 제거',
                    style: TextStyle(color: AppColors.error)),
                onTap: () => Navigator.pop(sheetCtx, 'remove'),
              ),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );

    if (action == null || !context.mounted) return;

    if (action == 'remove') {
      final auth = context.read<ap.AuthProvider>();
      final ok = await auth.updatePhotoURL(null);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(ok ? '프로필 사진이 제거되었습니다' : '제거 실패'),
            backgroundColor: ok ? AppColors.secondary : AppColors.error,
          ),
        );
      }
      return;
    }

    // pick → 갤러리에서 선택 → 1:1 크롭 → 업로드
    try {
      final picker = ImagePicker();
      final xfile = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 90,
      );
      if (xfile == null || !context.mounted) return;

      // 크롭 단계 (정사각 1:1)
      Uint8List bytes;
      if (kIsWeb) {
        // 웹: image_cropper 웹 지원 제한 — 바이트 그대로 사용
        bytes = await xfile.readAsBytes();
      } else {
        final cropped = await ImageCropper().cropImage(
          sourcePath: xfile.path,
          compressFormat: ImageCompressFormat.jpg,
          compressQuality: 88,
          aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
          maxWidth: 1024,
          maxHeight: 1024,
          uiSettings: [
            AndroidUiSettings(
              toolbarTitle: '프로필 사진 자르기',
              toolbarColor: AppColors.primary,
              toolbarWidgetColor: Colors.white,
              activeControlsWidgetColor: AppColors.primary,
              backgroundColor: Colors.black,
              lockAspectRatio: true,
              hideBottomControls: false,
              cropStyle: CropStyle.circle,
              initAspectRatio: CropAspectRatioPreset.square,
            ),
            IOSUiSettings(
              title: '프로필 사진 자르기',
              aspectRatioLockEnabled: true,
              resetAspectRatioEnabled: false,
              cropStyle: CropStyle.circle,
            ),
          ],
        );
        if (cropped == null || !context.mounted) return;
        bytes = await File(cropped.path).readAsBytes();
      }
      if (!context.mounted) return;

      // 로딩 다이얼로그
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(
          child: SizedBox(
            width: 56,
            height: 56,
            child: CircularProgressIndicator(color: AppColors.primary),
          ),
        ),
      );

      final url = await FirebaseStorageService.uploadBytes(
        bytes: bytes,
        path: FirebaseStorageService.avatarPath(user.uid),
        contentType: 'image/jpeg',
      );

      if (!context.mounted) return;
      final auth = context.read<ap.AuthProvider>();
      final ok = await auth.updatePhotoURL(url);

      if (context.mounted) {
        Navigator.pop(context); // 로딩 닫기
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text(ok ? '✅ 프로필 사진이 변경되었습니다' : '프로필 사진 변경 실패'),
            backgroundColor:
                ok ? AppColors.secondary : AppColors.error,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context).pop(); // 로딩 닫기 (안전)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('업로드 실패: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _editName(BuildContext context, String current) async {
    final newName = await AppSheets.textInput(
      context,
      title: '프로필 이름 수정',
      hint: '표시될 이름을 입력하세요',
      initial: current,
      maxLength: 20,
      icon: Icons.person_outline,
    );

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
    final ok = await AppSheets.confirm(
      context,
      icon: Icons.delete_outline,
      title: '"${vlog.title}" 삭제',
      message: '영상·사진 파일도 함께 삭제됩니다.\n복구할 수 없습니다.',
      confirmLabel: '삭제',
      dangerous: true,
    );
    if (ok == true && context.mounted) {
      await FirestoreService.deleteVlog(vlog.id);
    }
  }

  Future<void> _confirmSignOut(BuildContext context) async {
    final ok = await AppSheets.confirm(
      context,
      icon: Icons.logout,
      title: '로그아웃 하시겠습니까?',
      message: '다시 로그인하면 모든 데이터를 확인할 수 있습니다.',
      confirmLabel: '로그아웃',
      dangerous: true,
    );
    if (ok == true && context.mounted) {
      await context.read<ap.AuthProvider>().signOut();
    }
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final String value;
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
        border: Border.all(color: color.withValues(alpha: 0.18), width: 1),
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

String _fmtCount(int n) {
  if (n < 1000) return '$n';
  if (n < 10000) return '${(n / 1000).toStringAsFixed(1)}K';
  return '${(n / 1000).toStringAsFixed(0)}K';
}

// ── 저장한 vlog 모달 시트 진입 버튼 ───────────────────────────────────────
class _SavedVlogsButton extends StatelessWidget {
  final String uid;
  const _SavedVlogsButton({required this.uid});

  void _openSheet(BuildContext context) {
    HapticFeedback.selectionClick();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => _SavedVlogsSheet(uid: uid),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.xs),
      child: OutlinedButton.icon(
        onPressed: () => _openSheet(context),
        icon: const Icon(Icons.bookmark_border, size: 16),
        label: const Text('저장한 브이로그'),
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFFE6A100),
          side: BorderSide(
              color: const Color(0xFFFFC107).withValues(alpha: 0.4)),
          minimumSize: const Size(double.infinity, 42),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
        ),
      ),
    );
  }
}

/// 저장한 vlog 시트 — 카테고리 필터 + 그리드
class _SavedVlogsSheet extends StatefulWidget {
  final String uid;
  const _SavedVlogsSheet({required this.uid});

  @override
  State<_SavedVlogsSheet> createState() => _SavedVlogsSheetState();
}

class _SavedVlogsSheetState extends State<_SavedVlogsSheet> {
  String? _filter;

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (_, scrollCtrl) => Column(
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
            padding: EdgeInsets.fromLTRB(20, 12, 20, 10),
            child: Row(
              children: [
                Icon(Icons.bookmark, color: Color(0xFFFFC107), size: 22),
                SizedBox(width: 8),
                Text('저장한 브이로그',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800)),
              ],
            ),
          ),
          // 카테고리 칩
          SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                _SavedFilterChip(
                  label: '전체',
                  emoji: '🌐',
                  selected: _filter == null,
                  onTap: () => setState(() => _filter = null),
                ),
                const SizedBox(width: 6),
                ...MarkerEmojis.groups.map((g) => Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: _SavedFilterChip(
                        label: g.name,
                        emoji: g.hint,
                        selected: _filter == g.name,
                        onTap: () => setState(() => _filter = g.name),
                      ),
                    )),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: StreamBuilder<List<Vlog>>(
              stream: FirestoreService.watchSavedVlogs(widget.uid),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(
                      child: CircularProgressIndicator(
                          color: AppColors.primary));
                }
                if (snap.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.xl),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.error_outline,
                              size: 40, color: AppColors.error),
                          const SizedBox(height: 10),
                          const Text('저장 목록을 불러오지 못했어요',
                              style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600)),
                          const SizedBox(height: 4),
                          Text(
                            '${snap.error}',
                            textAlign: TextAlign.center,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 11,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                final all = snap.data ?? [];
                final vlogs = _filter == null
                    ? all
                    : all.where((v) {
                        if (v.markerEmoji == null) {
                          return _filter == '일반';
                        }
                        return MarkerEmojis.fromEmoji(v.markerEmoji)
                                .category ==
                            _filter;
                      }).toList();
                if (all.isEmpty) {
                  final cs = Theme.of(context).colorScheme;
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.xl),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.bookmark_border,
                              size: 40, color: cs.outline),
                          const SizedBox(height: 10),
                          const Text('아직 저장한 브이로그가 없어요',
                              style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600)),
                          const SizedBox(height: 4),
                          Text(
                            '브이로그 재생 화면에서 🔖 저장 버튼을 눌러보세요',
                            style: TextStyle(
                                fontSize: 12,
                                color: cs.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                if (vlogs.isEmpty) {
                  return Center(
                    child: Text(
                      '이 카테고리에 저장한 브이로그가 없어요',
                      style: TextStyle(
                          fontSize: 13,
                          color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  );
                }
                return GridView.builder(
                  controller: scrollCtrl,
                  padding: const EdgeInsets.all(AppSpacing.md),
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: AppSpacing.sm,
                    mainAxisSpacing: AppSpacing.sm,
                    childAspectRatio: 0.75,
                  ),
                  itemCount: vlogs.length,
                  itemBuilder: (_, i) {
                    final captured = List<Vlog>.from(vlogs);
                    return VlogCard(
                      vlog: vlogs[i],
                      onTap: () {
                        Navigator.pop(context);
                        VlogPlayerSwiperScreen.open(
                          context,
                          vlogs: captured,
                          initial: captured[i],
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ── 저장 시트 카테고리 필터 칩 ────────────────────────────────────────────
class _SavedFilterChip extends StatelessWidget {
  final String label;
  final String emoji;
  final bool selected;
  final VoidCallback onTap;
  const _SavedFilterChip({
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
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFFFFC107)
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppRadius.full),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 13)),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: selected
                    ? Colors.white
                    : Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── "지금 업데이트 확인" 수동 버튼 ────────────────────────────────────────
/// 업데이트 다이얼로그 본문 — 버전 변화 + 내역
class _UpdateContent extends StatelessWidget {
  final RemoteVersion remote;
  final bool mobile;
  const _UpdateContent({required this.remote, required this.mobile});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasNotes = remote.notes != null && remote.notes!.trim().isNotEmpty;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('v$kAppVersion → v${remote.version}',
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: cs.primary)),
        if (hasNotes) ...[
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Text(
              remote.notes!.trim(),
              style: TextStyle(
                  fontSize: 12.5, height: 1.5, color: cs.onSurface),
            ),
          ),
        ],
        const SizedBox(height: 12),
        Text(
          mobile
              ? '최신 APK를 다운로드할까요? (브라우저로 이동)'
              : '새로고침해서 최신 화면으로 이동할까요?',
          style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _CheckUpdateButton extends StatefulWidget {
  const _CheckUpdateButton();

  @override
  State<_CheckUpdateButton> createState() => _CheckUpdateButtonState();
}

class _CheckUpdateButtonState extends State<_CheckUpdateButton> {
  bool _checking = false;

  Future<void> _check() async {
    if (_checking) return;
    HapticFeedback.selectionClick();
    setState(() => _checking = true);
    try {
      // 1순위 — /version.json 자동 배포 메타 확인 (배포할 때마다 갱신됨)
      final remote = await web.fetchRemoteVersion();
      final remoteN = int.tryParse(remote?.build ?? '');
      final currentN = int.tryParse(kAppBuildNumber) ?? 0;

      if (remote != null && remoteN != null && remoteN > currentN) {
        if (!mounted) return;
        if (kIsWeb) {
          await _showWebReloadDialog(remote);
        } else {
          await _showApkDownloadDialog(remote);
        }
        return;
      }

      // 2순위 — Firestore 마스터 발행 (강제 업데이트·릴리즈 노트 시나리오)
      final info = await AppUpdateService.checkForUpdate();
      if (!mounted) return;
      if (info != null) {
        await UpdatePromptSheet.show(context, info);
        return;
      }

      // 정말 최신
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            '✅ 최신 버전입니다 (v$kAppVersion build $kAppBuildNumber)'),
        backgroundColor: AppColors.secondary,
        duration: const Duration(seconds: 2),
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('확인 실패: $e'),
        backgroundColor: AppColors.error,
      ));
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  /// 웹: 새 버전 감지 → 강제 새로고침 다이얼로그
  Future<void> _showWebReloadDialog(RemoteVersion remote) async {
    HapticFeedback.mediumImpact();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Text('✨ ', style: TextStyle(fontSize: 22)),
            Expanded(
              child: Text(
                  remote.version.isNotEmpty
                      ? 'v${remote.version} 출시'
                      : '새 버전 출시',
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w800)),
            ),
          ],
        ),
        content: _UpdateContent(remote: remote, mobile: false),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('나중에'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white),
            child: const Text('지금 새로고침'),
          ),
        ],
      ),
    );
    if (ok == true) WebVersionCheckService.reloadNow();
  }

  /// 모바일: APK 다운로드 안내 다이얼로그
  Future<void> _showApkDownloadDialog(RemoteVersion remote) async {
    HapticFeedback.mediumImpact();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Text('📦 ', style: TextStyle(fontSize: 22)),
            Expanded(
              child: Text(
                  remote.version.isNotEmpty
                      ? 'v${remote.version} 출시'
                      : '새 APK 출시',
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w800)),
            ),
          ],
        ),
        content: _UpdateContent(remote: remote, mobile: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('나중에'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.download_rounded, size: 18),
            label: const Text('APK 다운로드'),
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white),
          ),
        ],
      ),
    );
    if (ok == true) {
      final uri = Uri.parse(apkDownloadUrl(remote.build));
      try {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.xs),
      child: OutlinedButton.icon(
        onPressed: _checking ? null : _check,
        icon: _checking
            ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppColors.primary),
              )
            : const Icon(Icons.system_update_alt, size: 16),
        label: Text(_checking ? '확인 중...' : '지금 업데이트 확인'),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          side: BorderSide(color: AppColors.primary.withValues(alpha: 0.4)),
          minimumSize: const Size(double.infinity, 42),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
        ),
      ),
    );
  }
}

// ── 위치 통계 카드 ─────────────────────────────────────────────────────────
class _LocationStatsCard extends StatelessWidget {
  final List<Vlog> vlogs;
  const _LocationStatsCard({required this.vlogs});

  Set<String> _uniqueRegions() {
    final regions = <String>{};
    for (final v in vlogs) {
      final addr = (v.address ?? '').trim();
      if (addr.isEmpty) continue;
      // 첫 토큰 (시/도 단위) — 예: "서울특별시", "경기도", "부산광역시"
      final first = addr.split(' ').first;
      if (first.isNotEmpty) regions.add(first);
    }
    return regions;
  }

  Set<String> _uniqueDistricts() {
    final districts = <String>{};
    for (final v in vlogs) {
      final addr = (v.address ?? '').trim();
      if (addr.isEmpty) continue;
      final parts = addr.split(' ');
      if (parts.length >= 2) {
        districts.add('${parts[0]} ${parts[1]}'); // 시/도 + 구/시
      }
    }
    return districts;
  }

  String _relative(DateTime? d) {
    if (d == null) return '-';
    final diff = DateTime.now().difference(d);
    if (diff.inDays < 1) return '오늘';
    if (diff.inDays < 7) return '${diff.inDays}일 전';
    if (diff.inDays < 30) return '${(diff.inDays / 7).floor()}주 전';
    if (diff.inDays < 365) return '${(diff.inDays / 30).floor()}달 전';
    return '${(diff.inDays / 365).floor()}년 전';
  }

  String _ymd(DateTime? d) {
    if (d == null) return '-';
    return '${d.year}.${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    if (vlogs.isEmpty) return const SizedBox.shrink();
    final regions = _uniqueRegions();
    final districts = _uniqueDistricts();
    final dates = vlogs.map((v) => v.createdAt).toList()..sort();
    final first = dates.isEmpty ? null : dates.first;
    final last = dates.isEmpty ? null : dates.last;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppColors.primary.withValues(alpha: 0.06),
              const Color(0xFF7C4DFF).withValues(alpha: 0.06),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.15)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('🗺️', style: TextStyle(fontSize: 16)),
                const SizedBox(width: 6),
                const Text('나의 발자취',
                    style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800)),
                const Spacer(),
                Text(
                  '${vlogs.length}개 기록',
                  style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                    child: _StatBlock(
                        label: '시/도',
                        value: '${regions.length}',
                        unit: '곳',
                        color: AppColors.primary)),
                const SizedBox(width: 6),
                Expanded(
                    child: _StatBlock(
                        label: '구/군',
                        value: '${districts.length}',
                        unit: '곳',
                        color: const Color(0xFF7C4DFF))),
                const SizedBox(width: 6),
                Expanded(
                    child: _StatBlock(
                        label: '최근',
                        value: _relative(last),
                        unit: '',
                        color: AppColors.secondary)),
              ],
            ),
            const SizedBox(height: 10),
            // 카테고리별 활동 breakdown
            _CategoryBreakdown(vlogs: vlogs),
            const SizedBox(height: 10),
            // 시간대별 활동 패턴
            _TimePattern(vlogs: vlogs),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.flag_outlined,
                    size: 12, color: AppColors.textSecondary),
                const SizedBox(width: 4),
                Text(
                  '첫 기록: ${_ymd(first)}',
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.textSecondary),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── 시간대별 활동 패턴 (4분할 — 아침/오후/저녁/야간) ─────────────────────
class _TimePattern extends StatelessWidget {
  final List<Vlog> vlogs;
  const _TimePattern({required this.vlogs});

  static const _buckets = [
    (label: '아침', emoji: '🌅', range: '06–12', start: 6, end: 12, color: Color(0xFFFF9800)),
    (label: '오후', emoji: '☀️', range: '12–18', start: 12, end: 18, color: Color(0xFF1A73E8)),
    (label: '저녁', emoji: '🌆', range: '18–22', start: 18, end: 22, color: Color(0xFF7C4DFF)),
    (label: '야간', emoji: '🌙', range: '22–06', start: 22, end: 30, color: Color(0xFF455A64)),
  ];

  @override
  Widget build(BuildContext context) {
    if (vlogs.isEmpty) return const SizedBox.shrink();
    final counts = List<int>.filled(_buckets.length, 0);
    for (final v in vlogs) {
      final hour = v.createdAt.hour;
      for (var i = 0; i < _buckets.length; i++) {
        final b = _buckets[i];
        final inBucket = b.end > 24
            ? (hour >= b.start || hour < (b.end - 24))
            : (hour >= b.start && hour < b.end);
        if (inBucket) {
          counts[i]++;
          break;
        }
      }
    }
    final max = counts.fold(1, (a, b) => b > a ? b : a);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 4, left: 2),
          child: Text(
            '시간대 패턴',
            style: TextStyle(
                fontSize: 10.5,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2),
          ),
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: List.generate(_buckets.length, (i) {
            final b = _buckets[i];
            final c = counts[i];
            final ratio = (c / max).clamp(0.03, 1.0);
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Column(
                  children: [
                    Text(
                      '$c',
                      style: TextStyle(
                          fontSize: 10,
                          color: c > 0 ? b.color : AppColors.textDisabled,
                          fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 2),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      height: 28 * ratio,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            b.color,
                            b.color.withValues(alpha: 0.5),
                          ],
                        ),
                        borderRadius:
                            const BorderRadius.vertical(top: Radius.circular(3)),
                      ),
                    ),
                    Container(
                      height: 1,
                      color: AppColors.textDisabled.withValues(alpha: 0.3),
                    ),
                    const SizedBox(height: 3),
                    Text(b.emoji, style: const TextStyle(fontSize: 12)),
                    Text(b.label,
                        style: const TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w600)),
                    Text(b.range,
                        style: const TextStyle(
                            fontSize: 8.5, color: AppColors.textSecondary)),
                  ],
                ),
              ),
            );
          }),
        ),
      ],
    );
  }
}

// ── 카테고리별 활동 breakdown ──────────────────────────────────────────────
class _CategoryBreakdown extends StatelessWidget {
  final List<Vlog> vlogs;
  const _CategoryBreakdown({required this.vlogs});

  @override
  Widget build(BuildContext context) {
    if (vlogs.isEmpty) return const SizedBox.shrink();

    // 카테고리별 카운트
    final counts = <String, int>{};
    final groupHints = <String, String>{};
    for (final g in MarkerEmojis.groups) {
      groupHints[g.name] = g.hint;
    }
    for (final v in vlogs) {
      final cat = v.markerEmoji == null
          ? '일반'
          : MarkerEmojis.fromEmoji(v.markerEmoji).category;
      counts[cat] = (counts[cat] ?? 0) + 1;
    }
    // 카운트 0인 카테고리 제거, 큰 순으로 정렬
    final entries = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top = entries.take(6).toList();
    if (top.isEmpty) return const SizedBox.shrink();

    final maxCount = top.first.value;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 4, left: 2),
          child: Text(
            '카테고리별 활동',
            style: TextStyle(
                fontSize: 10.5,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2),
          ),
        ),
        ...top.map((e) {
          final hint = groupHints[e.key] ?? '📍';
          final ratio = (e.value / maxCount).clamp(0.05, 1.0);
          return Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                SizedBox(
                  width: 64,
                  child: Row(
                    children: [
                      Text(hint, style: const TextStyle(fontSize: 12)),
                      const SizedBox(width: 3),
                      Expanded(
                        child: Text(
                          e.key,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Stack(
                    children: [
                      Container(
                        height: 6,
                        decoration: BoxDecoration(
                          color: AppColors.textDisabled.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                      FractionallySizedBox(
                        widthFactor: ratio,
                        child: Container(
                          height: 6,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                AppColors.primary,
                                AppColors.primary.withValues(alpha: 0.6),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '${e.value}',
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }
}

class _StatBlock extends StatelessWidget {
  final String label, value, unit;
  final Color color;
  const _StatBlock(
      {required this.label,
      required this.value,
      required this.unit,
      required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Column(
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 10,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                    text: value,
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: color)),
                if (unit.isNotEmpty)
                  TextSpan(
                      text: ' $unit',
                      style: TextStyle(
                          fontSize: 10,
                          color: color.withValues(alpha: 0.8))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── 백그라운드 위치 공유 토글 (opt-in, Android 전용) ──────────────────────────
class _BgLocationToggle extends StatefulWidget {
  const _BgLocationToggle();

  @override
  State<_BgLocationToggle> createState() => _BgLocationToggleState();
}

class _BgLocationToggleState extends State<_BgLocationToggle> {
  bool _on = LocationTrackingService.instance.backgroundEnabled;
  bool _busy = false;

  Future<void> _toggle(bool want) async {
    if (_busy) return;
    if (!want) {
      setState(() => _on = false);
      await LocationTrackingService.instance.setBackgroundEnabled(false);
      return;
    }
    // 켜기: prominent disclosure → 권한 → 활성화
    final agreed = await _showDisclosure();
    if (agreed != true) return;
    setState(() => _busy = true);
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('위치 권한이 필요해요. 설정에서 허용해 주세요.')));
        if (perm == LocationPermission.deniedForever) {
          await Geolocator.openAppSettings();
        }
        return;
      }
      await LocationTrackingService.instance.setBackgroundEnabled(true);
      if (mounted) setState(() => _on = true);
      // 포그라운드만 허용된 경우 '항상 허용' 권장
      if (perm == LocationPermission.whileInUse && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("더 안정적인 공유를 위해 위치 권한을 '항상 허용'으로 바꿔주세요"),
          duration: Duration(seconds: 4),
        ));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool?> _showDisclosure() {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('백그라운드 위치 공유'),
        content: const Text(
          'PinFlick은 앱을 사용하지 않을 때(백그라운드)에도 친구에게 내 실시간 위치를 '
          '공유하기 위해 위치 정보를 수집합니다.\n\n'
          '• 켜져 있는 동안 "위치 공유 중" 알림이 계속 표시됩니다.\n'
          '• 잠수 모드인 친구·관계에는 공유되지 않습니다.\n'
          '• 언제든 이 설정에서 끌 수 있습니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('동의하고 켜기'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) return const SizedBox.shrink(); // 웹 미지원
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      child: Material(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(14),
        child: SwitchListTile(
          value: _on,
          onChanged: _busy ? null : _toggle,
          activeThumbColor: AppColors.primary,
          secondary: Icon(Icons.my_location,
              color: _on ? AppColors.primary : cs.onSurfaceVariant),
          title: const Text('백그라운드 위치 공유',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          subtitle: Text(
            _on
                ? '앱을 닫아도 친구에게 위치를 공유 중 (상시 알림)'
                : '앱을 닫으면 위치 공유가 멈춰요. 켜면 계속 공유',
            style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant),
          ),
        ),
      ),
    );
  }
}

// ── 다크모드 토글 (3-mode segmented) ──────────────────────────────────────
class _ThemeModeToggle extends StatelessWidget {
  const _ThemeModeToggle();

  @override
  Widget build(BuildContext context) {
    final themeProv = context.watch<ThemeProvider>();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Row(
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Text('🎨',
                  style: TextStyle(fontSize: 16)),
            ),
            const Expanded(
              child: Text('테마',
                  style: TextStyle(
                      fontSize: 13.5, fontWeight: FontWeight.w600)),
            ),
            SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(
                    value: ThemeMode.system,
                    icon: Icon(Icons.settings_suggest, size: 16),
                    tooltip: '시스템'),
                ButtonSegment(
                    value: ThemeMode.light,
                    icon: Icon(Icons.light_mode, size: 16),
                    tooltip: '라이트'),
                ButtonSegment(
                    value: ThemeMode.dark,
                    icon: Icon(Icons.dark_mode, size: 16),
                    tooltip: '다크'),
              ],
              selected: {themeProv.mode},
              onSelectionChanged: (s) {
                HapticFeedback.selectionClick();
                themeProv.setMode(s.first);
              },
              showSelectedIcon: false,
              style: const ButtonStyle(
                visualDensity:
                    VisualDensity(horizontal: -2, vertical: -2),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
