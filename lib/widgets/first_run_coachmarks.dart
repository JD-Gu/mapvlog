import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../utils/constants.dart';

/// 코치마크 한 단계 정의
class CoachStep {
  /// 스포트라이트로 강조할 위젯 영역 (null 이면 중앙 안내 카드만 표시)
  final Rect? target;
  final String emoji;
  final String title;
  final String body;

  /// 스포트라이트 모서리 둥글기
  final double radius;

  const CoachStep({
    this.target,
    required this.emoji,
    required this.title,
    required this.body,
    this.radius = 16,
  });
}

/// 첫 로그인 사용자용 3단계 스포트라이트 가이드 오버레이.
///
/// 사용:
/// ```dart
/// FirstRunCoachmarks.show(context, steps: [...], onDone: () {...});
/// ```
class FirstRunCoachmarks extends StatefulWidget {
  final List<CoachStep> steps;
  final VoidCallback onDone;

  const FirstRunCoachmarks({
    super.key,
    required this.steps,
    required this.onDone,
  });

  /// 오버레이로 띄움 (rootOverlay 사용 → 탭바 위에도 표시)
  static void show(
    BuildContext context, {
    required List<CoachStep> steps,
    required VoidCallback onDone,
  }) {
    if (steps.isEmpty) {
      onDone();
      return;
    }
    final overlay = Overlay.of(context, rootOverlay: true);
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => FirstRunCoachmarks(
        steps: steps,
        onDone: () {
          entry.remove();
          onDone();
        },
      ),
    );
    overlay.insert(entry);
  }

  @override
  State<FirstRunCoachmarks> createState() => _FirstRunCoachmarksState();
}

class _FirstRunCoachmarksState extends State<FirstRunCoachmarks>
    with SingleTickerProviderStateMixin {
  int _i = 0;
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  )..forward();

  CoachStep get _step => widget.steps[_i];
  bool get _isLast => _i == widget.steps.length - 1;

  @override
  void initState() {
    super.initState();
    HapticFeedback.mediumImpact();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _next() {
    if (_isLast) {
      widget.onDone();
      return;
    }
    HapticFeedback.selectionClick();
    setState(() => _i++);
    _ctrl
      ..reset()
      ..forward();
  }

  void _skip() {
    HapticFeedback.lightImpact();
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final target = _step.target;

    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          // 1) 딤 + 스포트라이트 — 탭하면 다음
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _next,
              child: AnimatedBuilder(
                animation: _ctrl,
                builder: (context, _) => CustomPaint(
                  painter: _SpotlightPainter(
                    hole: target,
                    radius: _step.radius,
                    pulse: _ctrl.value,
                  ),
                ),
              ),
            ),
          ),

          // 2) 안내 카드
          _buildCard(size, target),
        ],
      ),
    );
  }

  Widget _buildCard(Size size, Rect? target) {
    final cs = Theme.of(context).colorScheme;
    const cardMargin = 20.0;

    // 타깃이 화면 상단이면 카드를 아래에, 하단이면 위에 배치
    final bool placeBelow =
        target != null && target.center.dy < size.height * 0.5;

    final card = FadeTransition(
      opacity: _ctrl,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: Offset(0, placeBelow ? -0.06 : 0.06),
          end: Offset.zero,
        ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut)),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: cardMargin),
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.28),
                blurRadius: 28,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(_step.emoji, style: const TextStyle(fontSize: 26)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _step.title,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: cs.onSurface,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                _step.body,
                style: TextStyle(
                  fontSize: 13.5,
                  height: 1.5,
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  // 단계 점 인디케이터
                  Row(
                    children: List.generate(widget.steps.length, (k) {
                      final active = k == _i;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        margin: const EdgeInsets.only(right: 6),
                        width: active ? 18 : 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: active
                              ? AppColors.primary
                              : cs.outlineVariant,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      );
                    }),
                  ),
                  const Spacer(),
                  if (!_isLast)
                    TextButton(
                      onPressed: _skip,
                      style: TextButton.styleFrom(
                        foregroundColor: cs.onSurfaceVariant,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        minimumSize: Size.zero,
                      ),
                      child: const Text('건너뛰기',
                          style: TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600)),
                    ),
                  const SizedBox(width: 4),
                  ElevatedButton(
                    onPressed: _next,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 9),
                      minimumSize: Size.zero,
                      shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(AppRadius.full)),
                    ),
                    child: Text(
                      _isLast ? '시작하기' : '다음',
                      style: const TextStyle(
                          fontSize: 13.5, fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    // 위치 계산
    if (target == null) {
      return Center(child: card);
    }
    final safeBottom = MediaQuery.of(context).padding.bottom;
    if (placeBelow) {
      return Positioned(
        top: target.bottom + 18,
        left: 0,
        right: 0,
        child: card,
      );
    }
    return Positioned(
      bottom: (size.height - target.top) + 18 - safeBottom,
      left: 0,
      right: 0,
      child: card,
    );
  }
}

/// 전체를 어둡게 덮되 타깃 영역만 투명하게 뚫는 스포트라이트 페인터.
class _SpotlightPainter extends CustomPainter {
  final Rect? hole;
  final double radius;

  /// 등장 펄스(0→1) — 강조 링 굵기 애니메이션
  final double pulse;

  _SpotlightPainter({
    required this.hole,
    required this.radius,
    required this.pulse,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final dim = Paint()..color = Colors.black.withValues(alpha: 0.74);
    final full = Path()..addRect(Offset.zero & size);

    if (hole == null) {
      canvas.drawPath(full, dim);
      return;
    }

    final r = hole!.inflate(8);
    final rrect = RRect.fromRectAndRadius(r, Radius.circular(radius));
    final holePath = Path()..addRRect(rrect);
    final dimmed =
        Path.combine(PathOperation.difference, full, holePath);
    canvas.drawPath(dimmed, dim);

    // 강조 링 (펄스로 살짝 퍼졌다 모임)
    final ringInflate = 8 + (1 - pulse) * 6;
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..color = Colors.white.withValues(alpha: 0.85 * pulse);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          hole!.inflate(ringInflate), Radius.circular(radius + 4)),
      ring,
    );
  }

  @override
  bool shouldRepaint(covariant _SpotlightPainter old) =>
      old.hole != hole || old.pulse != pulse;
}
