// 모바일·데스크톱(VM) 구현 — HTTPS 로 version.json 직접 페치
// 웹 캐시 reload 는 모바일에선 의미 없음 → no-op (호출자가 APK URL launchUrl 처리)

import 'dart:convert';
import 'dart:io';

import '../models/remote_version.dart';

const _versionJsonUrl = 'https://pinflick.web.app/version.json';

Future<Map<String, dynamic>?> _fetchJson() async {
  HttpClient? client;
  try {
    client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 6)
      ..idleTimeout = const Duration(seconds: 6);
    final ts = DateTime.now().millisecondsSinceEpoch;
    final uri = Uri.parse('$_versionJsonUrl?t=$ts');
    final req = await client.getUrl(uri);
    req.headers.set('Cache-Control', 'no-cache, no-store, must-revalidate');
    req.headers.set('Pragma', 'no-cache');
    final res = await req.close();
    if (res.statusCode != 200) return null;
    final body = await res.transform(utf8.decoder).join();
    if (body.isEmpty) return null;
    return jsonDecode(body) as Map<String, dynamic>;
  } catch (_) {
    return null;
  } finally {
    try {
      client?.close();
    } catch (_) {}
  }
}

Future<String?> fetchRemoteBuildNumber() async {
  final data = await _fetchJson();
  return data?['build']?.toString();
}

Future<RemoteVersion?> fetchRemoteVersion() async {
  final data = await _fetchJson();
  if (data == null) return null;
  return RemoteVersion.fromJson(data);
}

/// 모바일에선 의미 없음 — 호출자가 APK URL 을 launchUrl 처리해야 한다.
void hardReload() {
  // no-op
}
