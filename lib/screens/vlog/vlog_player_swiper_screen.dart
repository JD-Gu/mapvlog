import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/vlog.dart';
import 'vlog_player_screen.dart';

/// 좌우 스와이프로 다음/이전 vlog 로 이동하는 플레이어 래퍼
///
/// 인스타·틱톡식 가로 PageView. 각 페이지는 독립된 VlogPlayerScreen 으로,
/// 페이지 전환 시 이전 플레이어의 영상·지도 컨트롤러가 자동 dispose 된다.
class VlogPlayerSwiperScreen extends StatefulWidget {
  final List<Vlog> vlogs;
  final int initialIndex;

  const VlogPlayerSwiperScreen({
    super.key,
    required this.vlogs,
    required this.initialIndex,
  });

  /// Convenience launcher — playlist 에서 체크인 제외 후 initialIndex 계산.
  /// 1개 이하 또는 인덱스 못 찾으면 단일 플레이어로 fallback.
  static Future<void> open(
    BuildContext context, {
    required List<Vlog> vlogs,
    required Vlog initial,
  }) {
    final playlist = vlogs
        .where((v) => !v.isCheckIn)
        .toList(growable: false);
    final idx = playlist.indexWhere((v) => v.id == initial.id);
    if (playlist.length <= 1 || idx < 0) {
      return Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => VlogPlayerScreen(vlog: initial),
        ),
      );
    }
    return Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VlogPlayerSwiperScreen(
          vlogs: playlist,
          initialIndex: idx,
        ),
      ),
    );
  }

  @override
  State<VlogPlayerSwiperScreen> createState() =>
      _VlogPlayerSwiperScreenState();
}

class _VlogPlayerSwiperScreenState extends State<VlogPlayerSwiperScreen> {
  late final PageController _controller;
  late int _index;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, widget.vlogs.length - 1);
    _controller = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PageView.builder(
      controller: _controller,
      itemCount: widget.vlogs.length,
      // 한 번에 한 페이지만 빌드 (메모리 절약)
      allowImplicitScrolling: false,
      onPageChanged: (i) {
        HapticFeedback.selectionClick();
        setState(() => _index = i);
      },
      itemBuilder: (_, i) {
        final v = widget.vlogs[i];
        // ValueKey 로 각 페이지 상태 격리 → 스와이프 시 컨트롤러 재초기화
        return VlogPlayerScreen(key: ValueKey(v.id), vlog: v);
      },
    );
  }
}
