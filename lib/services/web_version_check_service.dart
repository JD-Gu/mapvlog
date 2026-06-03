import 'dart:async';

import '../models/remote_version.dart';
import '../utils/constants.dart';
import 'web_cache_reload_stub.dart'
    if (dart.library.io) 'web_cache_reload_io.dart'
    if (dart.library.html) 'web_cache_reload_web.dart' as web;

/// 웹 캐시 자동 갱신 감지 서비스
///
/// 사용자가 페이지를 열어둔 상태에서 새 버전이 배포되면,
/// 주기적으로 /version.json 을 폴링하여 buildNumber 가 달라졌는지 감지한다.
///
/// 사용:
///   final svc = WebVersionCheckService(onNewVersion: () => ...);
///   svc.start();
class WebVersionCheckService {
  /// 새 버전 감지 시 호출되는 콜백 (UI 가 다이얼로그 표시)
  final void Function(RemoteVersion remote) onNewVersion;

  /// 폴링 주기 (기본 90초)
  final Duration interval;

  Timer? _timer;
  bool _notified = false;

  WebVersionCheckService({
    required this.onNewVersion,
    this.interval = const Duration(seconds: 90),
  });

  /// 폴링 시작 — 웹/모바일 모두 (모바일은 io 구현으로 HTTPS fetch)
  void start() {
    // 첫 체크는 약간 지연 (앱 로딩 방해 최소화)
    Future.delayed(const Duration(seconds: 30), _check);
    _timer = Timer.periodic(interval, (_) => _check());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _check() async {
    if (_notified) return; // 이미 알린 상태에서 중복 호출 안 함
    final remote = await web.fetchRemoteVersion();
    if (remote == null) return;
    if (remote.build == kAppBuildNumber) return;
    // remote 가 숫자라면 더 큰 경우에만 알림 (downgrade 무시)
    final remoteN = int.tryParse(remote.build);
    final currentN = int.tryParse(kAppBuildNumber);
    if (remoteN != null && currentN != null && remoteN <= currentN) return;
    _notified = true;
    onNewVersion(remote);
  }

  /// 사용자 확인 시 호출 — 서비스워커 해제 후 강제 reload
  static void reloadNow() {
    web.hardReload();
  }
}
