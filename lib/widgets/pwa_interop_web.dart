// 웹 전용 구현 — dart:html + dart:js 만 사용 (package 의존성 없음)

// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter

import 'dart:html' as html;
import 'dart:js' as js;

bool isInstalled() {
  try {
    return js.context.callMethod('pfIsInstalled') == true;
  } catch (_) {
    return false;
  }
}

/// index.html이 노출한 window.pfShowInstallPrompt() 호출.
/// 결과: 'accepted' | 'dismissed' | 'unavailable'
///
/// Promise/Future 변환 대신 polling 방식 사용 — package:js 의존성 회피
Future<String> showInstallPrompt() async {
  try {
    final triggered = js.context.callMethod('pfShowInstallPrompt');
    if (triggered != true) return 'unavailable';
    // 최대 30초 동안 0.5초 간격으로 outcome 폴링
    for (var i = 0; i < 60; i++) {
      await Future.delayed(const Duration(milliseconds: 500));
      final outcome = js.context.callMethod('pfLastOutcome');
      final s = outcome?.toString() ?? '';
      if (s == 'accepted' || s == 'dismissed') return s;
    }
    return 'dismissed';
  } catch (_) {
    return 'unavailable';
  }
}

String detectPlatform() {
  final ua = html.window.navigator.userAgent;
  if (ua.contains('iPhone') || ua.contains('iPad')) return 'iosSafari';
  if (ua.contains('Android')) return 'androidChrome';
  return 'desktopChrome';
}
