// 웹 전용 — version.json 폴링 + 강제 캐시 + SW 무효화 + 새로고침
//
// 토스/당근 방식의 신뢰성 있는 PWA 업데이트:
//   1) /version.json (no-cache) 폴링 → 새 빌드 감지
//   2) Service Worker 에 skipWaiting postMessage → 대기 중 새 SW 활성화
//   3) Cache Storage 전체 삭제 (Promise 완료까지 대기)
//   4) 등록된 SW 전부 unregister
//   5) cache-bust query 로 navigate (location.href 사용)

// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter

import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:js' as js;

import '../models/remote_version.dart';

/// /version.json?t=<ts> 페치 (캐시 우회) → "build" 필드
Future<String?> fetchRemoteBuildNumber() async {
  try {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final res = await html.HttpRequest.request(
      '/version.json?t=$ts',
      method: 'GET',
      requestHeaders: const {
        'Cache-Control': 'no-cache, no-store, must-revalidate',
        'Pragma': 'no-cache',
      },
    );
    final body = res.responseText ?? '';
    if (body.isEmpty) return null;
    final data = jsonDecode(body) as Map<String, dynamic>;
    return data['build']?.toString();
  } catch (_) {
    return null;
  }
}

/// version.json 전체(버전+빌드+내역) 페치
Future<RemoteVersion?> fetchRemoteVersion() async {
  try {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final res = await html.HttpRequest.request(
      '/version.json?t=$ts',
      method: 'GET',
      requestHeaders: const {
        'Cache-Control': 'no-cache, no-store, must-revalidate',
        'Pragma': 'no-cache',
      },
    );
    final body = res.responseText ?? '';
    if (body.isEmpty) return null;
    return RemoteVersion.fromJson(
        jsonDecode(body) as Map<String, dynamic>);
  } catch (_) {
    return null;
  }
}

/// 강력 새로고침 — PWA / SW 환경에서도 확실히 새 빌드 로드
void hardReload() {
  _doHardReload();
}

Future<void> _doHardReload() async {
  // ── 0~2) 모든 캐시 정리·SW 해제 작업을 단일 async JS 블록으로 실행 ─────
  //
  // dart:js_util 없이도 안정적으로 Promise.all() 을 처리하기 위해
  // window.__pfReady = true; 플래그를 두고 완료를 폴링.
  try {
    js.context.callMethod('eval', [
      r"""
window.__pfReady = false;
(async () => {
  try {
    // SW 에게 skipWaiting 신호 전달 (Flutter SW + 일반 SW 모두)
    try {
      const reg = await navigator.serviceWorker.getRegistration();
      if (reg && reg.waiting) reg.waiting.postMessage('skipWaiting');
      if (reg && reg.waiting) reg.waiting.postMessage({type: 'SKIP_WAITING'});
      if (navigator.serviceWorker.controller) {
        navigator.serviceWorker.controller.postMessage('skipWaiting');
        navigator.serviceWorker.controller.postMessage({type: 'SKIP_WAITING'});
      }
    } catch (e) {}

    // Cache Storage 전체 삭제
    if (window.caches) {
      try {
        const keys = await caches.keys();
        await Promise.all(keys.map(k => caches.delete(k)));
      } catch (e) {}
    }

    // 모든 SW 등록 해제
    if (navigator.serviceWorker) {
      try {
        const regs = await navigator.serviceWorker.getRegistrations();
        await Promise.all(regs.map(r => r.unregister().catch(() => {})));
      } catch (e) {}
    }
  } catch (e) {}
  window.__pfReady = true;
})();
""",
    ]);
  } catch (_) {}

  // JS 비동기 작업 완료를 폴링 (최대 3초)
  for (int i = 0; i < 30; i++) {
    await Future.delayed(const Duration(milliseconds: 100));
    try {
      final ready = js.context['__pfReady'];
      if (ready == true) break;
    } catch (_) {}
  }
  // 안정성 위해 추가 대기
  await Future.delayed(const Duration(milliseconds: 300));

  // ── 4) 강제 navigate (cache-bust query) ──────────────────────────────
  try {
    final loc = html.window.location;
    final hrefNoQuery = loc.href.split('?').first.split('#').first;
    final hash = loc.hash;
    final bust = DateTime.now().millisecondsSinceEpoch;
    loc.assign('$hrefNoQuery?v=$bust$hash');
  } catch (_) {
    try {
      html.window.location.reload();
    } catch (_) {}
  }
}
