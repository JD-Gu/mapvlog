import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart' show FirebaseAuth;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models/user_status.dart';
import 'models/vlog.dart';
import 'providers/auth_provider.dart';
import 'providers/theme_provider.dart';
import 'screens/auth/login_screen.dart';
import 'screens/camera/camera_screen.dart';
import 'screens/camera/vlog_upload_wizard.dart';
import 'screens/gallery/gallery_screen.dart';
import 'screens/home/home_screen.dart';
import 'screens/live_map/live_map_screen.dart';
import 'screens/friends/friend_list_screen.dart';
import 'screens/splash_screen.dart';
import 'screens/vlog/vlog_player_screen.dart';
import 'services/location_tracking_service.dart';
import 'services/push_service.dart';
import 'services/user_status_service.dart';
import 'services/web_version_check_service.dart';
import 'utils/constants.dart';
import 'services/app_update_service.dart';
import 'utils/sheets.dart';
import 'widgets/new_version_banner.dart';
import 'widgets/check_in_sheet.dart';
import 'widgets/first_run_coachmarks.dart';
import 'widgets/notifications_sheet.dart';
import 'widgets/pulsing_fab.dart';
import 'widgets/update_prompt_sheet.dart';

class MapVlogApp extends StatelessWidget {
  const MapVlogApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProv, _) => MaterialApp(
          title: 'PinFlick',
          navigatorKey: rootNavigatorKey,
          debugShowCheckedModeBanner: false,
          themeMode: themeProv.mode,
          theme: _lightTheme,
          darkTheme: _darkTheme,
          home: const SplashScreen(),
        ),
      ),
    );
  }

  static final ThemeData _lightTheme = ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      primary: AppColors.primary,
      secondary: AppColors.secondary,
      error: AppColors.error,
      surface: AppColors.surface,
      brightness: Brightness.light,
    ),
    scaffoldBackgroundColor: AppColors.background,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.surface,
      foregroundColor: AppColors.textPrimary,
      elevation: 0,
      scrolledUnderElevation: 1,
    ),
    cardTheme: const CardThemeData(
      color: AppColors.surface,
      elevation: 0,
    ),
    dividerColor: const Color(0xFFE5E7EB),
    useMaterial3: true,
  );

  // 다크 모드 — 자연스러운 회색 계열 (순흑 X)
  static const _darkBg = Color(0xFF121316);          // scaffold bg
  static const _darkSurface = Color(0xFF1C1D21);     // card / appbar
  static const _darkSurfaceVariant = Color(0xFF26282E);

  static final ThemeData _darkTheme = ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      primary: AppColors.primary,
      secondary: AppColors.secondary,
      error: AppColors.error,
      surface: _darkSurface,
      surfaceContainerHighest: _darkSurfaceVariant,
      brightness: Brightness.dark,
    ),
    scaffoldBackgroundColor: _darkBg,
    appBarTheme: const AppBarTheme(
      backgroundColor: _darkSurface,
      foregroundColor: Colors.white,
      elevation: 0,
      scrolledUnderElevation: 1,
    ),
    cardTheme: const CardThemeData(
      color: _darkSurface,
      elevation: 0,
    ),
    dividerColor: const Color(0xFF2E3035),
    useMaterial3: true,
  );
}

class MainShell extends StatefulWidget {
  const MainShell({super.key, this.initialVlog});

  /// 딥링크 진입 시 바로 열 브이로그 (null이면 일반 홈 진입)
  final Vlog? initialVlog;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;
  AuthProvider? _authProvider;

  late final List<Widget> _screens;

  // ── 글로벌 호출(Ping) 알림 ──────────────────────────────────────────────────
  StreamSubscription<List<Ping>>? _pingsSub;
  final Set<String> _shownPingIds = {};
  bool _isFirstPingEmission = true;

  // ── 웹 캐시 자동 갱신 감지 ─────────────────────────────────────────────
  WebVersionCheckService? _versionCheck;

  // ── 첫 로그인 코치마크 ────────────────────────────────────────────────────
  final GlobalKey _navBarKey = GlobalKey();
  final GlobalKey _fabKey = GlobalKey();
  final GlobalKey _mapTabKey = GlobalKey();
  bool _coachmarksShown = false;

  @override
  void initState() {
    super.initState();
    _screens = [
      const HomeScreen(),
      const LiveMapScreen(),
      const CameraScreen(),
      const GalleryScreen(),
      const FriendListScreen(), // 프로필은 상단 헤더 아바타로 이동
    ];
    // 딥링크 vlog가 있으면 MainShell이 완전히 빌드된 후 플레이어를 올림
    if (widget.initialVlog != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => VlogPlayerScreen(vlog: widget.initialVlog!),
        ));
      });
    }
    _subscribeGlobalPings();
    _checkForAppUpdate();
    _startWebVersionCheck();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _maybeShowCoachmarks());
  }

  /// 위젯의 화면상 사각형 영역 (글로벌 좌표)
  Rect? _rectOf(GlobalKey key) {
    final ctx = key.currentContext;
    if (ctx == null) return null;
    final box = ctx.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return null;
    final offset = box.localToGlobal(Offset.zero);
    return offset & box.size;
  }

  /// 첫 로그인 사용자에게 3단계 사용 가이드 표시 (1회성)
  Future<void> _maybeShowCoachmarks() async {
    if (_coachmarksShown) return;
    final auth = context.read<AuthProvider>();
    if (!auth.isLoggedIn) return; // 로그인 후에만
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('coachmarks_done_v1') ?? false) {
      _coachmarksShown = true;
      return;
    }
    // 레이아웃 안정화 대기 (탭바·FAB 렌더 완료)
    await Future.delayed(const Duration(milliseconds: 700));
    if (!mounted || _coachmarksShown) return;

    final navRect = _rectOf(_navBarKey);
    final fabRect = _rectOf(_fabKey);
    final mapRect = _rectOf(_mapTabKey);
    if (navRect == null || fabRect == null) return; // 안전장치

    _coachmarksShown = true;
    FirstRunCoachmarks.show(
      context,
      steps: [
        CoachStep(
          target: navRect,
          radius: 18,
          emoji: '🧭',
          title: '하단 메뉴로 한눈에',
          body: '홈 피드 · 친구 지도 · 갤러리 · 친구를\n'
              '아래 탭으로 자유롭게 오가요.',
        ),
        CoachStep(
          target: fabRect,
          radius: 40,
          emoji: '➕',
          title: '가운데 버튼으로 기록',
          body: '➕ 를 누르면 사진·영상 브이로그를 올리고,\n'
              '길게 누르면 지금 위치로 빠른 체크인!',
        ),
        CoachStep(
          target: mapRect,
          radius: 18,
          emoji: '🔒',
          title: '내 위치, 내가 정해요',
          body: '친구 지도에선 공개 범위를 친구마다 골라요.\n'
              '베프(정확)·부끄럼(대략)·잠수(숨김) — '
              '원치 않으면 잠수로 가려서 안심!',
        ),
      ],
      onDone: () {
        prefs.setBool('coachmarks_done_v1', true);
      },
    );
  }

  /// 웹 캐시 자동 갱신 — 새 빌드 배포 감지 시 상단 배너 표시
  void _startWebVersionCheck() {
    _versionCheck = WebVersionCheckService(
      onNewVersion: (remote) {
        if (!mounted) return;
        NewVersionBanner.show(context, remote);
      },
    )..start();
  }

  /// 신규 버전 발행 여부 확인 → 안내 시트 표시
  Future<void> _checkForAppUpdate() async {
    // 첫 화면 렌더 후 약간 대기 (사용자 시야 방해 최소화)
    await Future.delayed(const Duration(seconds: 3));
    if (!mounted) return;
    final info = await AppUpdateService.checkForUpdate();
    if (info == null || !mounted) return;
    await UpdatePromptSheet.show(context, info);
  }

  /// 어디서나 호출 받기 — 로그인 시 ping 구독
  Future<void> _subscribeGlobalPings() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      await UserStatusService.ensureUserDoc(user);
    } catch (_) {}
    // 앱 전역 위치 추적 시작 (어느 탭에 있든 동적 주기로 내 위치 기록)
    LocationTrackingService.instance.start(user.uid);
    // FCM 푸시 초기화 (권한요청 + 토큰 저장)
    try {
      await PushService.instance.init(user.uid);
    } catch (_) {}
    _pingsSub = UserStatusService.watchMyPings(user.uid).listen(_onPingsUpdate);
  }

  void _resubscribePings() {
    _pingsSub?.cancel();
    _pingsSub = null;
    _shownPingIds.clear();
    _isFirstPingEmission = true;
    _subscribeGlobalPings();
  }

  void _onPingsUpdate(List<Ping> pings) {
    if (!mounted) return;
    // 첫 emission은 기존 ping (재진입 등) → 표시 스킵
    if (_isFirstPingEmission) {
      _isFirstPingEmission = false;
      for (final p in pings) {
        _shownPingIds.add(p.id);
      }
      return;
    }
    for (final ping in pings) {
      if (_shownPingIds.contains(ping.id)) continue;
      _shownPingIds.add(ping.id);
      _showPingSnackbar(ping);
    }
  }

  /// 강화된 ping 햅틱 패턴 — 3번 진동 + 시스템 알림음
  void _playPingAlert() {
    HapticFeedback.heavyImpact();
    SystemSound.play(SystemSoundType.alert);
    Future.delayed(const Duration(milliseconds: 220), () {
      if (mounted) HapticFeedback.heavyImpact();
    });
    Future.delayed(const Duration(milliseconds: 440), () {
      if (mounted) HapticFeedback.mediumImpact();
    });
  }

  void _showPingSnackbar(Ping ping) {
    if (!mounted) return;
    _playPingAlert();
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 7),
        backgroundColor: AppColors.surface,
        elevation: 6,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg)),
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 80),
        content: Row(
          children: [
            Text(ping.emoji, style: const TextStyle(fontSize: 26)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${ping.fromName}님이 호출했어요',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '"${ping.message}"',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: () {
                messenger.hideCurrentSnackBar();
                // 알림 시트 열기 (메시지 내용 확인 + 친구 지도 이동 가능)
                NotificationsSheet.open(context);
              },
              child: const Text(
                '보기',
                style: TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // AuthProvider 리스너 등록 — 로그아웃 시 보호 탭이면 홈으로 이동
    final newAuth = context.read<AuthProvider>();
    if (_authProvider != newAuth) {
      _authProvider?.removeListener(_onAuthChanged);
      _authProvider = newAuth;
      _authProvider!.addListener(_onAuthChanged);
    }
  }

  void _onAuthChanged() {
    if (!mounted) return;
    final loggedIn = _authProvider?.isLoggedIn ?? false;
    // 로그아웃 후 보호 탭(촬영=2, 프로필=4)이면 홈으로 리셋
    if (!loggedIn &&
        (_currentIndex == 2 || _currentIndex == 4)) {
      setState(() => _currentIndex = 0);
    }
    // ping 구독 갱신 — 로그인 시 새로 구독, 로그아웃 시 해제
    if (loggedIn) {
      _resubscribePings();
      _maybeShowCoachmarks(); // 로그인 직후 첫 가이드
    } else {
      _pingsSub?.cancel();
      _pingsSub = null;
      _shownPingIds.clear();
      _isFirstPingEmission = true;
      LocationTrackingService.instance.stop(); // 로그아웃 → 추적 정지
    }
  }

  @override
  void dispose() {
    _authProvider?.removeListener(_onAuthChanged);
    _pingsSub?.cancel();
    _versionCheck?.stop();
    LocationTrackingService.instance.stop();
    super.dispose();
  }

  /// 탭 전환 — 로그인 필요 탭(촬영=2, 프로필=4)은 비로그인 시 로그인 유도
  void _onTabTap(int index) {
    // 동기 체크: async onTap은 웹에서 Future가 무시될 수 있어 동기로 처리
    if (index == 2 || index == 4) {
      final auth = context.read<AuthProvider>();
      if (!auth.isLoggedIn) {
        _showLoginRequired(index == 2 ? '촬영' : '프로필');
        return; // setState 호출 없이 리턴 → 탭 전환 차단
      }
    }
    setState(() => _currentIndex = index);
  }

  /// 로그인 유도 시트
  Future<void> _showLoginRequired(String feature) async {
    final nav = Navigator.of(context);
    final goLogin = await AppSheets.confirm(
      context,
      icon: Icons.lock_outline,
      title: '로그인이 필요해요',
      message: '$feature 기능은 로그인 후 이용할 수 있습니다.',
      confirmLabel: '로그인',
    );
    if (goLogin == true && mounted) {
      nav.push(MaterialPageRoute(builder: (_) => const LoginScreen()));
    }
  }

  /// 뒤로가기 처리
  /// - 홈 탭이 아닌 경우: 홈 탭으로 이동
  /// - 홈 탭인 경우: 종료 확인 시트
  Future<bool> _onWillPop() async {
    if (_currentIndex != 0) {
      setState(() => _currentIndex = 0);
      return false; // pop 차단
    }
    // 홈 탭 → 종료 확인
    final shouldExit = await AppSheets.confirm(
      context,
      icon: Icons.exit_to_app,
      title: '앱을 종료할까요?',
      confirmLabel: '종료',
      dangerous: true,
    );
    if (shouldExit == true) {
      SystemNavigator.pop();
    }
    return false;
  }

  // ── 중앙 FAB (브이로그 등록 마법사) — 롱프레스 = 체크인 ─────────────
  Widget _buildFab() {
    return KeyedSubtree(
      key: _fabKey,
      child: _buildFabInner(),
    );
  }

  Widget _buildFabInner() {
    return PulsingFab(
      isSelected: false, // 마법사는 push 라우트라서 탭 인디케이터 사용 안 함
      onTap: () {
        HapticFeedback.selectionClick();
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const VlogUploadWizard()),
        );
      },
      onLongPress: () => CheckInSheet.open(context),
    );
  }

  // ── 탭별 고유 색상 ────────────────────────────────────────────────────
  static const _navColors = [
    Color(0xFF1A73E8), // 0: 홈  — 블루
    Color(0xFF00ACC1), // 1: 지도 — 시안
    Colors.transparent, // 2: FAB (사용 안 함)
    Color(0xFF7C4DFF), // 3: 갤러리 — 퍼플
    Color(0xFFEC407A), // 4: 친구 — 핑크
  ];

  // ── 하단 탭 아이템 (라벨 없음, 컬러 아이콘 + 점 인디케이터) ──────────
  Widget _buildNavItem(int index, IconData outlined, IconData filled,
      {Key? itemKey}) {
    final isSelected = _currentIndex == index;
    final activeColor = _navColors[index];
    // 다크모드 대응: 비활성 색상을 Theme의 outline으로
    final iconColor = isSelected
        ? activeColor
        : Theme.of(context).colorScheme.outline;

    return InkWell(
      key: itemKey,
      onTap: () => _onTabTap(index),
      borderRadius: BorderRadius.circular(AppRadius.full),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        // 선택 시 탭 컬러 알약 배경 — 밋밋함 제거 + 현재 탭 직관 표시
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOut,
          padding: EdgeInsets.symmetric(
            horizontal: isSelected ? 18 : 12,
            vertical: 7,
          ),
          decoration: BoxDecoration(
            color: isSelected
                ? activeColor.withValues(alpha: 0.15)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.full),
          ),
          child: AnimatedScale(
            scale: isSelected ? 1.0 : 0.9,
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutBack,
            child: Icon(
              isSelected ? filled : outlined,
              color: iconColor,
              size: 25,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) => _onWillPop(),
      child: Scaffold(
        body: _screens[_currentIndex],
        floatingActionButton: _buildFab(),
        floatingActionButtonLocation:
            FloatingActionButtonLocation.centerDocked,
        bottomNavigationBar: BottomAppBar(
          shape: const CircularNotchedRectangle(),
          notchMargin: 8.0,
          color: Theme.of(context).colorScheme.surface,
          elevation: 8,
          shadowColor: Colors.black26,
          child: SizedBox(
            key: _navBarKey,
            height: 56,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildNavItem(0, Icons.home_outlined, Icons.home),
                _buildNavItem(1, Icons.map_outlined, Icons.map,
                    itemKey: _mapTabKey),
                const SizedBox(width: 56), // FAB 공간
                _buildNavItem(
                    3, Icons.photo_library_outlined, Icons.photo_library),
                _buildNavItem(4, Icons.people_outline, Icons.people),
              ],
            ),
          ),
        ),
      ), // Scaffold
    ); // PopScope
  }
}
