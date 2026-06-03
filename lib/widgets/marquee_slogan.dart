import 'package:flutter/material.dart';

/// 뉴스 자막/주식 전광판 스타일의 마퀴 슬로건.
///
/// - 텍스트가 우→좌로 매우 느리게 흐름 (기본 22 px/s)
/// - 끊김 없는 무한 루프 (텍스트 2개를 간격을 두고 이어 붙여 seamless)
/// - 폭이 충분해서 텍스트가 다 들어가면 자동으로 정적 표시 (animation off)
/// - GPU 합성만 사용 (Transform.translate + ClipRect)
class MarqueeSlogan extends StatefulWidget {
  final String text;
  final TextStyle style;
  final double pixelsPerSecond;
  final double gap; // 두 번째 텍스트 시작점까지의 간격

  const MarqueeSlogan({
    super.key,
    this.text = '📍 친구의 위치로 핀(Pin), 친구의 일상을 플릭(Flick). 지도를 넘겨(Flick) 친구를 만나다, PinFlick',
    this.style = const TextStyle(
      fontSize: 11.5,
      color: Color(0xFF8E8E93),
      fontWeight: FontWeight.w500,
      height: 1.2,
      letterSpacing: -0.1,
    ),
    this.pixelsPerSecond = 22, // "아주 천천히" — 편안한 읽기 속도
    this.gap = 60,
  });

  @override
  State<MarqueeSlogan> createState() => _MarqueeSloganState();
}

class _MarqueeSloganState extends State<MarqueeSlogan>
    with SingleTickerProviderStateMixin {
  AnimationController? _ctrl;
  double _textWidth = 0;

  @override
  void initState() {
    super.initState();
    _setup();
  }

  @override
  void didUpdateWidget(covariant MarqueeSlogan oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text ||
        oldWidget.pixelsPerSecond != widget.pixelsPerSecond ||
        oldWidget.gap != widget.gap ||
        oldWidget.style != widget.style) {
      _setup();
    }
  }

  void _setup() {
    final tp = TextPainter(
      text: TextSpan(text: widget.text, style: widget.style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    _textWidth = tp.width;

    // 한 사이클 = 텍스트 폭 + 간격 → 두 번째 텍스트가 첫 번째 위치에 도달하면 reset
    final cyclePx = _textWidth + widget.gap;
    final ms = (cyclePx / widget.pixelsPerSecond * 1000).round();

    _ctrl?.dispose();
    _ctrl = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: ms.clamp(1000, 120000)),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  Widget _fallbackText() => Text(
        widget.text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        softWrap: false,
        style: widget.style,
      );

  @override
  Widget build(BuildContext context) {
    final ctrl = _ctrl;
    if (ctrl == null || _textWidth == 0) {
      return _fallbackText();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth;
        // 방어: 부모가 무한 폭을 주거나 폭이 0이면 정적 fallback
        // (AppBar.title의 Flexible 안에서 일시적으로 발생 가능)
        if (!maxW.isFinite || maxW <= 0) {
          return _fallbackText();
        }

        // 폭이 충분하면 마퀴 불필요 — 정적 표시
        if (_textWidth <= maxW) {
          return _fallbackText();
        }

        return ClipRect(
          child: SizedBox(
            width: maxW,
            height: widget.style.fontSize != null
                ? widget.style.fontSize! * (widget.style.height ?? 1.4)
                : 18,
            child: AnimatedBuilder(
              animation: ctrl,
              builder: (context, child) {
                final offset = -(_textWidth + widget.gap) * ctrl.value;
                return OverflowBox(
                  alignment: Alignment.centerLeft,
                  maxWidth: double.infinity,
                  child: Transform.translate(
                    offset: Offset(offset, 0),
                    child: child,
                  ),
                );
              },
              // child는 매 프레임 재빌드되지 않음 — 성능 최적화
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(widget.text,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.visible,
                      style: widget.style),
                  SizedBox(width: widget.gap),
                  // seamless 루프를 위한 두 번째 사본
                  Text(widget.text,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.visible,
                      style: widget.style),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
