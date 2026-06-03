import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../utils/constants.dart';
import 'pwa_interop_stub.dart'
    if (dart.library.html) 'pwa_interop_web.dart' as pwa;

/// 웹 사용자에게 노출되는 "앱처럼 설치" 버튼.
///
/// - Chrome/Edge: `beforeinstallprompt` 캡처되어 있으면 한 번에 설치
/// - iOS Safari / 기타: 플랫폼별 수동 가이드 모달 표시
/// - 이미 설치된 경우 / 모바일 앱에서: 자동 숨김
class PwaInstallButton extends StatefulWidget {
  const PwaInstallButton({super.key});

  @override
  State<PwaInstallButton> createState() => _PwaInstallButtonState();
}

class _PwaInstallButtonState extends State<PwaInstallButton> {
  bool _isInstalled = false;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      _isInstalled = pwa.isInstalled();
    }
  }

  Future<void> _onTap() async {
    HapticFeedback.selectionClick();
    final outcome = await pwa.showInstallPrompt();
    if (!mounted) return;

    if (outcome == 'accepted') {
      setState(() => _isInstalled = true);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('🎉 PinFlick 설치 완료!'),
        backgroundColor: AppColors.secondary,
        duration: Duration(seconds: 2),
      ));
    } else if (outcome == 'unavailable') {
      // 자동 프롬프트가 안 뜨는 환경 → 가이드 모달
      await _showGuide(pwa.detectPlatform());
    }
    // 'dismissed'는 무시 — 사용자가 명시적으로 거절
  }

  Future<void> _showGuide(String platform) async {
    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _InstallGuideSheet(platform: platform),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb || _isInstalled) return const SizedBox.shrink();
    return OutlinedButton.icon(
      onPressed: _onTap,
      icon: const Icon(Icons.install_mobile, size: 18),
      label: const Text('PinFlick을 앱처럼 설치'),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.primary,
        side: BorderSide(color: AppColors.primary.withValues(alpha: 0.4)),
        minimumSize: const Size(double.infinity, 44),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
      ),
    );
  }
}

/// 플랫폼별 설치 가이드 시트
class _InstallGuideSheet extends StatelessWidget {
  final String platform;
  const _InstallGuideSheet({required this.platform});

  @override
  Widget build(BuildContext context) {
    final steps = _stepsFor(platform);
    final title = _titleFor(platform);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.textDisabled.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Icon(Icons.install_mobile,
                    color: AppColors.primary, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(title,
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800)),
                ),
              ],
            ),
            const SizedBox(height: 14),
            ...List.generate(steps.length, (i) {
              final s = steps[i];
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 22,
                      height: 22,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                      ),
                      child: Text('${i + 1}',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w800)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(s,
                          style: const TextStyle(
                              fontSize: 13.5,
                              height: 1.55)),
                    ),
                  ],
                ),
              );
            }),
            const SizedBox(height: 4),
            const Text(
              '설치하면 홈 화면 아이콘 + 풀스크린으로 더 빠르게 접근할 수 있어요',
              style: TextStyle(
                  fontSize: 11.5,
                  color: AppColors.textSecondary,
                  fontStyle: FontStyle.italic),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                minimumSize: const Size(double.infinity, 46),
              ),
              child: const Text('확인'),
            ),
          ],
        ),
      ),
    );
  }

  String _titleFor(String p) {
    switch (p) {
      case 'iosSafari':
        return 'iPhone Safari — 홈 화면에 추가';
      case 'androidChrome':
        return 'Android Chrome — 앱 설치';
      case 'desktopChrome':
        return '데스크톱 — 앱 설치';
      default:
        return '브라우저에서 앱 설치';
    }
  }

  List<String> _stepsFor(String p) {
    switch (p) {
      case 'iosSafari':
        return [
          '하단 가운데의 공유 버튼 ⬆️ 을 탭하세요',
          '메뉴에서 "홈 화면에 추가"를 탭하세요',
          '우상단의 "추가"를 탭하면 완료',
        ];
      case 'androidChrome':
        return [
          '우상단의 ⋮ 메뉴를 탭하세요',
          '"앱 설치" 또는 "홈 화면에 추가"를 선택하세요',
          '"설치"를 탭하면 완료',
        ];
      case 'desktopChrome':
        return [
          '주소창 오른쪽 끝의 ⊕ 또는 💻 아이콘을 클릭하세요',
          '"PinFlick 설치" 버튼을 클릭하세요',
          '브라우저 창과 별도의 앱으로 실행됩니다',
        ];
      default:
        return [
          '브라우저 메뉴를 여세요',
          '"홈 화면에 추가" 또는 "앱 설치" 옵션을 찾으세요',
          '안내에 따라 설치를 완료하세요',
        ];
    }
  }
}
