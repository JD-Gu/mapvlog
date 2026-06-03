import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../auth/login_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with SingleTickerProviderStateMixin {
  final PageController _controller = PageController();
  int _currentPage = 0;
  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

  static const _pages = [
    _OnboardingPage(
      emoji: '📍',
      title: '친구의 위치로\n핀(Pin)',
      desc: '베프/부끄럼/잠수 — 등급별로 정밀도 조절\n친구가 지금 어디 있는지 한눈에',
    ),
    _OnboardingPage(
      emoji: '🎬',
      title: '친구의 일상을\n플릭(Flick)',
      desc: '사진과 영상으로 친구의 순간을\n좋아요·댓글로 즉시 반응',
    ),
    _OnboardingPage(
      emoji: '🗺️',
      title: '지도를 넘겨\n친구를 만나다',
      desc: '한 번의 핀으로 만남이 시작돼요\n어디야? 호출은 1초면 끝',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeIn);
    _fadeCtrl.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    _fadeCtrl.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_done', true);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ── 배경 히어로 이미지 ───────────────────────────────────────────
          FadeTransition(
            opacity: _fadeAnim,
            child: Image.asset(
              'assets/images/intro_hero.png',
              fit: BoxFit.cover,
              // 이미지 로드 실패 시 색상 폴백
              errorBuilder: (context, error, stack) => Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF1565C0), Color(0xFF0D47A1)],
                  ),
                ),
              ),
            ),
          ),

          // ── 그라디언트 오버레이 ──────────────────────────────────────────
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: [0.0, 0.30, 0.60, 1.0],
                colors: [
                  Color(0xAA000000), // 상단 67%
                  Color(0x33000000), // 중간 투명
                  Color(0xCC000000), // 하단부터 어두워짐
                  Color(0xF5000000), // 최하단 96%
                ],
              ),
            ),
          ),

          // ── 투명 PageView (스와이프 제스처 캡처, 웹 마우스 드래그 지원) ──
          ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(
              dragDevices: {
                PointerDeviceKind.touch,
                PointerDeviceKind.mouse,
              },
            ),
            child: PageView.builder(
              controller: _controller,
              onPageChanged: (i) => setState(() => _currentPage = i),
              itemCount: _pages.length,
              itemBuilder: (context, index) => const SizedBox.expand(),
            ),
          ),

          // ── UI 콘텐츠 ────────────────────────────────────────────────────
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 상단 로고 + 건너뛰기
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
                  child: Row(
                    children: [
                      _Logo(),
                      const Spacer(),
                      TextButton(
                        onPressed: _finish,
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white70,
                        ),
                        child: const Text('건너뛰기',
                            style: TextStyle(fontSize: 14)),
                      ),
                    ],
                  ),
                ),

                const Spacer(),

                // 하단 콘텐츠 영역
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 인디케이터 dots
                      Row(
                        children: List.generate(
                          _pages.length,
                          (i) => AnimatedContainer(
                            duration: const Duration(milliseconds: 250),
                            margin: const EdgeInsets.only(right: 6),
                            width: _currentPage == i ? 24 : 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: _currentPage == i
                                  ? Colors.white
                                  : Colors.white38,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // 이모지
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        child: Text(
                          _pages[_currentPage].emoji,
                          key: ValueKey('emoji_$_currentPage'),
                          style: const TextStyle(fontSize: 38),
                        ),
                      ),
                      const SizedBox(height: 10),

                      // 타이틀
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        transitionBuilder: (child, anim) => FadeTransition(
                          opacity: anim,
                          child: SlideTransition(
                            position: Tween<Offset>(
                              begin: const Offset(0.05, 0),
                              end: Offset.zero,
                            ).animate(anim),
                            child: child,
                          ),
                        ),
                        child: Text(
                          _pages[_currentPage].title,
                          key: ValueKey('title_$_currentPage'),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 30,
                            fontWeight: FontWeight.bold,
                            height: 1.3,
                            letterSpacing: -0.5,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // 설명
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        transitionBuilder: (child, anim) => FadeTransition(
                          opacity: anim,
                          child: child,
                        ),
                        child: Text(
                          _pages[_currentPage].desc,
                          key: ValueKey('desc_$_currentPage'),
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 15,
                            height: 1.65,
                          ),
                        ),
                      ),
                      const SizedBox(height: 30),

                      // 버튼
                      SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: ElevatedButton(
                          onPressed: () {
                            if (_currentPage < _pages.length - 1) {
                              _controller.nextPage(
                                duration: const Duration(milliseconds: 350),
                                curve: Curves.easeInOut,
                              );
                            } else {
                              _finish();
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1A73E8),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shadowColor: Colors.transparent,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: Text(
                            _currentPage < _pages.length - 1
                                ? '다음 →'
                                : '시작하기  🚀',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── PinFlick 로고 위젯 ──────────────────────────────────────────────────────
class _Logo extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Image.asset(
          'assets/images/Pinflick_icon.png',
          width: 36,
          height: 36,
        ),
        const SizedBox(width: 9),
        const Text(
          'PinFlick',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 21,
            letterSpacing: -0.3,
            shadows: [
              Shadow(
                color: Colors.black54,
                blurRadius: 8,
                offset: Offset(0, 2),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── 페이지 데이터 ────────────────────────────────────────────────────────────
class _OnboardingPage {
  final String emoji;
  final String title;
  final String desc;
  const _OnboardingPage({
    required this.emoji,
    required this.title,
    required this.desc,
  });
}
