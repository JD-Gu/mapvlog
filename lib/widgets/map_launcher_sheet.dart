import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// 좌표를 국내외 주요 지도 앱으로 길찾기/열기 하는 바텀시트.
///
/// - 구글 지도: 유니버설 https 링크(앱/웹 모두 동작)
/// - 네이버 지도 / 카카오맵 / TMAP: 앱 스킴 우선, 미설치/웹이면 웹 폴백
///
/// Android 는 AndroidManifest 의 <queries> 에 각 스킴/패키지가 등록돼 있어야
/// canLaunchUrl 이 true 를 반환한다.
class MapLauncherSheet {
  static const _appName = 'com.mapvlog.app'; // 네이버 nmap appname 파라미터

  /// 길찾기 시트 표시
  static Future<void> show(
    BuildContext context, {
    required double lat,
    required double lng,
    String? name,
  }) {
    final place = (name == null || name.trim().isEmpty) ? '목적지' : name.trim();
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _MapLauncherSheetBody(lat: lat, lng: lng, name: place),
    );
  }

  // ── 각 앱 실행 ────────────────────────────────────────────────────────────

  static Future<void> _launch(
    BuildContext context, {
    required Uri appUri,
    Uri? webFallback,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (await canLaunchUrl(appUri)) {
        final ok =
            await launchUrl(appUri, mode: LaunchMode.externalApplication);
        if (ok) return;
      }
    } catch (_) {}
    if (webFallback != null) {
      try {
        final ok = await launchUrl(webFallback,
            mode: LaunchMode.externalApplication);
        if (ok) return;
      } catch (_) {}
    }
    messenger.showSnackBar(
      const SnackBar(content: Text('지도 앱을 열 수 없어요. 앱이 설치돼 있는지 확인해 주세요.')),
    );
  }

  static Future<void> google(BuildContext c, double lat, double lng) =>
      _launch(c,
          appUri: Uri.parse(
              'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng'));

  static Future<void> naver(
          BuildContext c, double lat, double lng, String name) =>
      _launch(c,
          appUri: Uri.parse('nmap://route/car?dlat=$lat&dlng=$lng'
              '&dname=${Uri.encodeComponent(name)}&appname=$_appName'),
          webFallback: Uri.parse(
              'https://map.naver.com/p/search/${Uri.encodeComponent(name)}'));

  static Future<void> kakao(
          BuildContext c, double lat, double lng, String name) =>
      _launch(c,
          appUri: Uri.parse('kakaomap://route?ep=$lat,$lng&by=CAR'),
          webFallback: Uri.parse(
              'https://map.kakao.com/link/to/${Uri.encodeComponent(name)},$lat,$lng'));

  static Future<void> tmap(
          BuildContext c, double lat, double lng, String name) =>
      _launch(c,
          appUri: Uri.parse('tmap://route?goalname=${Uri.encodeComponent(name)}'
              '&goalx=$lng&goaly=$lat'),
          webFallback: Uri.parse(
              'https://play.google.com/store/apps/details?id=com.skt.tmap.ku'));
}

class _MapLauncherSheetBody extends StatelessWidget {
  final double lat;
  final double lng;
  final String name;
  const _MapLauncherSheetBody(
      {required this.lat, required this.lng, required this.name});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(8),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: cs.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              children: [
                Icon(Icons.directions, size: 20, color: cs.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    name,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w800),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text('길찾기로 열 지도 앱을 선택하세요',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
            const SizedBox(height: 12),
            _AppTile(
              asset: 'assets/images/map_google.png',
              emoji: '🗺️',
              bg: const Color(0xFF34A853),
              label: '구글 지도',
              onTap: () {
                Navigator.pop(context);
                MapLauncherSheet.google(context, lat, lng);
              },
            ),
            _AppTile(
              asset: 'assets/images/map_naver.png',
              emoji: '🟢',
              bg: const Color(0xFF03C75A),
              label: '네이버 지도',
              onTap: () {
                Navigator.pop(context);
                MapLauncherSheet.naver(context, lat, lng, name);
              },
            ),
            _AppTile(
              asset: 'assets/images/map_kakao.png',
              emoji: '💛',
              bg: const Color(0xFFFEE500),
              label: '카카오맵',
              onTap: () {
                Navigator.pop(context);
                MapLauncherSheet.kakao(context, lat, lng, name);
              },
            ),
            _AppTile(
              asset: 'assets/images/map_tmap.png',
              emoji: '🧭',
              bg: const Color(0xFF1A4DE6),
              label: 'TMAP',
              onTap: () {
                Navigator.pop(context);
                MapLauncherSheet.tmap(context, lat, lng, name);
              },
            ),
            const SizedBox(height: 4),
            TextButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: '$lat, $lng'));
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('좌표를 복사했어요')),
                  );
                }
              },
              icon: const Icon(Icons.copy, size: 16),
              label: const Text('좌표 복사'),
            ),
          ],
        ),
      ),
    );
  }
}

class _AppTile extends StatelessWidget {
  final String asset; // 공식 아이콘 PNG (없으면 emoji 로 폴백)
  final String emoji;
  final Color bg;
  final String label;
  final VoidCallback onTap;
  const _AppTile({
    required this.asset,
    required this.emoji,
    required this.bg,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.asset(
                    asset,
                    width: 38,
                    height: 38,
                    fit: BoxFit.cover,
                    // 아이콘 파일이 없으면 색상 + 이모지로 폴백
                    errorBuilder: (_, __, ___) => Container(
                      width: 38,
                      height: 38,
                      alignment: Alignment.center,
                      color: bg,
                      child:
                          Text(emoji, style: const TextStyle(fontSize: 18)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface),
                  ),
                ),
                Icon(Icons.north_east,
                    size: 16, color: cs.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
