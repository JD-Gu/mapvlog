import 'package:flutter/material.dart';

import '../utils/constants.dart';

/// 메인 FAB — 은은한 그라데이션 루프 (8초, ease-in-out)
///
/// CSS의 `background-position` shift를 Flutter에서 재현:
/// LinearGradient의 begin/end Alignment를 8초 주기로 부드럽게 이동시켜
/// 그라디언트가 흐르는 듯한 효과를 GPU 합성만으로 구현 (레이아웃 영향 없음).
class PulsingFab extends StatefulWidget {
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  const PulsingFab({
    super.key,
    required this.isSelected,
    required this.onTap,
    this.onLongPress,
  });

  @override
  State<PulsingFab> createState() => _PulsingFabState();
}

class _PulsingFabState extends State<PulsingFab>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<Alignment> _begin;
  late final Animation<Alignment> _end;

  // 브랜드 컬러 톤 — 시안~블루 (실시간 GPS 신호 느낌)
  static const _idleColors = [
    Color(0xFF1A73E8),
    Color(0xFF42A5F5),
    Color(0xFF6DD5ED),
    Color(0xFF2193B0),
  ];
  static const _activeColors = [
    Color(0xFF0D47A1),
    Color(0xFF1565C0),
    Color(0xFF1A73E8),
    Color(0xFF42A5F5),
  ];

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat(reverse: true);

    final curve = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
    _begin = AlignmentTween(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ).animate(curve);
    _end = AlignmentTween(
      begin: Alignment.bottomRight,
      end: Alignment.topLeft,
    ).animate(curve);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, child) {
          return Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              // 흐르는 그라데이션 (begin/end가 8초 주기로 이동)
              gradient: LinearGradient(
                begin: _begin.value,
                end: _end.value,
                colors: widget.isSelected ? _activeColors : _idleColors,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(
                      alpha: widget.isSelected ? 0.45 : 0.40),
                  blurRadius: widget.isSelected ? 18 : 14,
                  offset: const Offset(0, 6),
                ),
                BoxShadow(
                  color: AppColors.primary.withValues(
                      alpha: widget.isSelected ? 0.55 : 0.40),
                  blurRadius: widget.isSelected ? 24 : 18,
                  spreadRadius: widget.isSelected ? 1 : 0,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            padding: const EdgeInsets.all(7),
            child: child,
          );
        },
        // child는 애니메이션과 무관 — 매 프레임 재빌드 회피 (성능 최적화)
        child: Container(
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              center: Alignment(-0.3, -0.3),
              radius: 1.1,
              colors: [Color(0x33FFFFFF), Colors.transparent],
              stops: [0.0, 0.6],
            ),
          ),
          child: ClipOval(
            child: Image.asset(
              'assets/images/Pinflick_icon.png',
              fit: BoxFit.contain,
              width: double.infinity,
              height: double.infinity,
            ),
          ),
        ),
      ),
    );
  }
}
