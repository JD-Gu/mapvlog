import 'dart:js_interop';

@JS('__pf_initial_hash')
external JSString? get _jsInitialHash;

/// index.html 에서 Flutter 시작 전에 저장한 window.__pf_initial_hash 값을 읽음.
/// '#/vlog/abc' → '/vlog/abc' (# 제거)
String? getInitialWebFragment() {
  try {
    final raw = _jsInitialHash?.toDart ?? '';
    return raw.startsWith('#') ? raw.substring(1) : raw;
  } catch (_) {
    // JS interop 실패 시 Uri.base 폴백
    return Uri.base.fragment;
  }
}
