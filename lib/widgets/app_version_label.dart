import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../utils/constants.dart';

/// 앱 버전 표시 — 프로필/로그인 화면 푸터에 사용
///
/// 형식: `v1.1.0 (2) · BETA · Android`
/// 길게 누르면 클립보드에 풀버전 문자열 복사 (버그 리포트용)
class AppVersionLabel extends StatelessWidget {
  /// true → 화면 중앙 정렬, false → 좌측 정렬
  final bool centered;
  final Color? color;

  const AppVersionLabel({
    super.key,
    this.centered = true,
    this.color,
  });

  String get _platformLabel {
    if (kIsWeb) return 'Web';
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'Android';
      case TargetPlatform.iOS:
        return 'iOS';
      case TargetPlatform.macOS:
        return 'macOS';
      case TargetPlatform.windows:
        return 'Windows';
      case TargetPlatform.linux:
        return 'Linux';
      default:
        return '';
    }
  }

  String get _full =>
      'PinFlick v$kAppVersion ($kAppBuildNumber) · ${kAppChannel.toUpperCase()} · $_platformLabel';

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.textDisabled;
    return GestureDetector(
      onLongPress: () async {
        HapticFeedback.mediumImpact();
        await Clipboard.setData(ClipboardData(text: _full));
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('📋 복사됨: $_full'),
            duration: const Duration(seconds: 2),
            backgroundColor: AppColors.textPrimary,
          ));
        }
      },
      child: Row(
        mainAxisAlignment:
            centered ? MainAxisAlignment.center : MainAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.info_outline, size: 11, color: c),
          const SizedBox(width: 4),
          Text(
            'v$kAppVersion',
            style: TextStyle(
                fontSize: 11.5,
                color: c,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.2),
          ),
          Text(
            ' ($kAppBuildNumber)',
            style: TextStyle(fontSize: 11, color: c),
          ),
          const SizedBox(width: 6),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              kAppChannel.toUpperCase(),
              style: const TextStyle(
                  fontSize: 9,
                  color: AppColors.primary,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.4),
            ),
          ),
          const SizedBox(width: 6),
          Text('· $_platformLabel',
              style: TextStyle(fontSize: 10.5, color: c)),
        ],
      ),
    );
  }
}
