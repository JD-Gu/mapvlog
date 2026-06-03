// Non-web (mobile/desktop) 빌드 시 사용되는 더미 구현.
// kIsWeb 가드 덕분에 실제로 호출될 일이 없지만 컴파일 가능해야 함.

bool isInstalled() => false;

/// 'accepted' | 'dismissed' | 'unavailable'
Future<String> showInstallPrompt() async => 'unavailable';

/// 'iosSafari' | 'androidChrome' | 'desktopChrome' | 'other'
String detectPlatform() => 'other';
