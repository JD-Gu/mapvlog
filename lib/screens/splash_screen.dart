import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app.dart';
import '../main.dart' show initialWebFragment;
import '../models/event.dart';
import '../models/vlog.dart';
import '../services/firestore_service.dart';
import '../utils/constants.dart';
import 'auth/login_screen.dart';
import 'onboarding/onboarding_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _logoCtrl;
  late final AnimationController _textCtrl;
  late final Animation<double> _logoScale;
  late final Animation<double> _logoFade;
  late final Animation<double> _textFade;
  late final Animation<Offset> _textSlide;

  @override
  void initState() {
    super.initState();
    _logoCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _textCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _logoScale = CurvedAnimation(
            parent: _logoCtrl, curve: Curves.elasticOut)
        .drive(Tween(begin: 0.5, end: 1.0));
    _logoFade = CurvedAnimation(parent: _logoCtrl, curve: Curves.easeIn);
    _textFade = CurvedAnimation(parent: _textCtrl, curve: Curves.easeOut);
    _textSlide = Tween<Offset>(
            begin: const Offset(0, 0.3), end: Offset.zero)
        .animate(CurvedAnimation(
            parent: _textCtrl, curve: Curves.easeOutCubic));

    _logoCtrl.forward();
    Future.delayed(const Duration(milliseconds: 400),
        () => mounted ? _textCtrl.forward() : null);
    _navigate();
  }

  @override
  void dispose() {
    _logoCtrl.dispose();
    _textCtrl.dispose();
    super.dispose();
  }

  Future<void> _navigate() async {
    // 스플래시 최소 표시 시간 + Firebase Auth 초기 상태 확정을 동시에 대기
    // 웹에서는 localStorage 세션 복원이 비동기로 진행되어 먼저 체크하면
    // 로그인 상태가 null로 잘못 판단되는 race condition이 발생함
    User? user;
    await Future.wait([
      Future.delayed(const Duration(seconds: 2)),
      FirebaseAuth.instance
          .authStateChanges()
          .first
          .then((u) => user = u),
    ]);

    if (!mounted) return;

    // ── 웹 딥링크 감지 ──────────────────────────────────────────────────────
    if (kIsWeb) {
      final fragment = initialWebFragment ?? '';
      debugPrint('[PinFlick] splash fragment="$fragment"');
      if (fragment.startsWith('/vlog/')) {
        final vlogId = fragment.substring('/vlog/'.length).split('?').first;
        debugPrint('[PinFlick] deeplink vlogId="$vlogId"');
        if (vlogId.isNotEmpty) {
          await _openDeepLink(vlogId, user);
          return;
        }
      } else if (fragment.startsWith('/event/')) {
        final eventId = fragment.substring('/event/'.length).split('?').first;
        debugPrint('[PinFlick] deeplink eventId="$eventId"');
        if (eventId.isNotEmpty) {
          await _openEventDeepLink(eventId);
          return;
        }
      }
    }

    // ── 일반 진입 분기 ───────────────────────────────────────────────────────
    final prefs = await SharedPreferences.getInstance();
    final onboardingDone = prefs.getBool('onboarding_done') ?? false;

    if (!mounted) return;

    if (user != null) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const MainShell()),
      );
    } else if (!onboardingDone) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const OnboardingScreen()),
      );
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    }
  }

  /// 딥링크로 특정 vlog 직접 진입
  ///
  /// 로그인 여부와 무관하게 MainShell 위에 VlogPlayerScreen 을 올림.
  /// vlog ID가 유효하지 않으면 일반 홈으로 진입.
  Future<void> _openDeepLink(String vlogId, User? user) async {
    final nav = Navigator.of(context);

    // 딥링크 진입 시 온보딩 완료 처리
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_done', true);

    Vlog? vlog;
    try {
      vlog = await FirestoreService.getVlog(vlogId);
      debugPrint('[PinFlick] getVlog result: ${vlog == null ? "null" : vlog.title}');
    } catch (e) {
      debugPrint('[PinFlick] getVlog error: $e');
    }

    if (!mounted) return;

    // MainShell 에 initialVlog 를 전달 → MainShell.initState 에서 플레이어 push
    nav.pushReplacement(
      MaterialPageRoute(builder: (_) => MainShell(initialVlog: vlog)),
    );
  }

  /// 딥링크로 특정 이벤트 직접 진입 → MainShell 위에 친구지도(이벤트 포커스)
  Future<void> _openEventDeepLink(String eventId) async {
    final nav = Navigator.of(context);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_done', true);
    PinEvent? event;
    try {
      event = await FirestoreService.getEvent(eventId);
    } catch (e) {
      debugPrint('[PinFlick] getEvent error: $e');
    }
    if (!mounted) return;
    nav.pushReplacement(
      MaterialPageRoute(builder: (_) => MainShell(initialEvent: event)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        // 그라디언트 배경 (브랜드 블루 → 시안)
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF1A73E8),
              Color(0xFF1565C0),
              Color(0xFF0D47A1),
            ],
          ),
        ),
        child: Stack(
          children: [
            // 배경 글로우 원들
            Positioned(
              top: -80,
              right: -60,
              child: _BgCircle(
                  size: 220,
                  color: Colors.white.withValues(alpha: 0.08)),
            ),
            Positioned(
              bottom: -100,
              left: -80,
              child: _BgCircle(
                  size: 280,
                  color: const Color(0xFF42A5F5)
                      .withValues(alpha: 0.18)),
            ),
            // 중앙 콘텐츠
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // 로고 (elastic scale + fade)
                  AnimatedBuilder(
                    animation: _logoCtrl,
                    builder: (_, __) => Opacity(
                      opacity: _logoFade.value,
                      child: Transform.scale(
                        scale: _logoScale.value,
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.white
                                    .withValues(alpha: 0.4),
                                blurRadius: 40,
                                spreadRadius: 4,
                              ),
                            ],
                          ),
                          child: Image.asset(
                            'assets/images/Pinflick_icon.png',
                            width: 130,
                            height: 130,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  // 텍스트 (slide + fade)
                  SlideTransition(
                    position: _textSlide,
                    child: FadeTransition(
                      opacity: _textFade,
                      child: Column(
                        children: [
                          const Text(
                            'PinFlick',
                            style: TextStyle(
                              fontSize: 38,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              letterSpacing: -1.0,
                              shadows: [
                                Shadow(
                                  color: Color(0x33000000),
                                  blurRadius: 12,
                                  offset: Offset(0, 4),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.15),
                              borderRadius:
                                  BorderRadius.circular(20),
                              border: Border.all(
                                  color: Colors.white
                                      .withValues(alpha: 0.25)),
                            ),
                            child: const Text(
                              '📍 친구의 위치로 핀(Pin), 친구의 일상을 플릭(Flick)',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.white,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // 하단 로딩 인디케이터
            Positioned(
              left: 0,
              right: 0,
              bottom: 40,
              child: FadeTransition(
                opacity: _textFade,
                child: const Center(
                  child: SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                          Colors.white70),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BgCircle extends StatelessWidget {
  final double size;
  final Color color;
  const _BgCircle({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
      ),
    );
  }
}
