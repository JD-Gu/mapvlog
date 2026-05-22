import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'providers/auth_provider.dart';
import 'screens/auth/login_screen.dart';
import 'screens/camera/camera_screen.dart';
import 'screens/gallery/gallery_screen.dart';
import 'screens/home/home_screen.dart';
import 'screens/map/map_screen.dart';
import 'screens/profile/profile_screen.dart';
import 'screens/splash_screen.dart';
import 'utils/constants.dart';

class MapVlogApp extends StatelessWidget {
  const MapVlogApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
      ],
      child: MaterialApp(
        title: 'MapVlog',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: AppColors.primary,
            primary: AppColors.primary,
            secondary: AppColors.secondary,
            error: AppColors.error,
            surface: AppColors.surface,
          ),
          scaffoldBackgroundColor: AppColors.background,
          useMaterial3: true,
        ),
        home: const SplashScreen(),
      ),
    );
  }
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;

  final List<Widget> _screens = const [
    HomeScreen(),
    MapScreen(),
    CameraScreen(),
    GalleryScreen(),
    ProfileScreen(),
  ];

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

  /// 로그인 유도 다이얼로그
  Future<void> _showLoginRequired(String feature) async {
    final nav = Navigator.of(context); // async gap 전에 캡처
    final goLogin = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('로그인 필요'),
        content: Text('$feature 기능은 로그인 후 이용할 수 있습니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              '로그인',
              style: TextStyle(color: AppColors.primary),
            ),
          ),
        ],
      ),
    );
    if (goLogin == true && mounted) {
      nav.push(MaterialPageRoute(builder: (_) => const LoginScreen()));
    }
  }

  /// 뒤로가기 처리
  /// - 홈 탭이 아닌 경우: 홈 탭으로 이동
  /// - 홈 탭인 경우: 종료 확인 다이얼로그
  Future<bool> _onWillPop() async {
    if (_currentIndex != 0) {
      setState(() => _currentIndex = 0);
      return false; // pop 차단
    }
    // 홈 탭 → 종료 확인
    final shouldExit = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('앱 종료'),
        content: const Text('앱을 종료할까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              '종료',
              style: TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
    if (shouldExit == true) {
      SystemNavigator.pop(); // 앱 종료
    }
    return false; // pop은 항상 차단, 종료는 SystemNavigator로 직접 처리
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) => _onWillPop(),
      child: Scaffold(
      body: _screens[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: _onTabTap,
        type: BottomNavigationBarType.fixed,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: AppColors.textDisabled,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: '홈'),
          BottomNavigationBarItem(icon: Icon(Icons.map), label: '지도'),
          BottomNavigationBarItem(icon: Icon(Icons.videocam), label: '촬영'),
          BottomNavigationBarItem(
              icon: Icon(Icons.photo_library), label: '갤러리'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: '프로필'),
        ],
      ),
    ),   // Scaffold
    );   // PopScope
  }
}
