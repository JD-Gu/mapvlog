import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app.dart';
import '../../providers/auth_provider.dart';
import '../../utils/constants.dart';
import '../../widgets/app_version_label.dart';
import '../legal/legal_screen.dart';
import '../../widgets/pwa_install_button.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    if (auth.isLoggedIn) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const MainShell()),
        );
      });
    }

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 로고
              Image.asset(
                'assets/images/Pinflick_icon.png',
                width: 90,
                height: 90,
              ),
              const SizedBox(height: AppSpacing.sm),
              const Text(
                'PinFlick',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: AppSpacing.xxl),

              // 에러 메시지
              if (auth.error != null)
                Container(
                  margin: const EdgeInsets.only(bottom: AppSpacing.md),
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Text(
                    '로그인 실패. 다시 시도해 주세요.',
                    style: const TextStyle(
                        color: AppColors.error, fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                ),

              // Google 로그인 — 유일한 로그인 수단
              _LoginButton(
                onPressed: auth.loading
                    ? null
                    : () => context.read<AuthProvider>().signInWithGoogle(),
                icon: Icons.g_mobiledata,
                label: 'Google로 로그인',
                backgroundColor: Colors.white,
                foregroundColor: AppColors.textPrimary,
                borderColor: AppColors.textDisabled,
              ),
              const SizedBox(height: AppSpacing.md),

              // 구글 계정 필수 안내
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.18)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.info_outline,
                        size: 16, color: AppColors.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: RichText(
                        text: TextSpan(
                          style: const TextStyle(
                              fontSize: 12,
                              height: 1.5,
                              color: AppColors.textSecondary),
                          children: [
                            const TextSpan(text: 'PinFlick은 '),
                            const TextSpan(
                                text: '구글(Gmail) 계정',
                                style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.primary)),
                            const TextSpan(
                                text: '으로만 가입·로그인할 수 있어요.\n계정이 없다면 '),
                            TextSpan(
                              text: '구글 계정 만들기',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  decoration: TextDecoration.underline,
                                  color: AppColors.primary),
                              recognizer: TapGestureRecognizer()
                                ..onTap = () async {
                                  final uri = Uri.parse(
                                      'https://accounts.google.com/signup');
                                  try {
                                    await launchUrl(uri,
                                        mode:
                                            LaunchMode.externalApplication);
                                  } catch (_) {}
                                },
                            ),
                            const TextSpan(text: ' 후 이용해 주세요.'),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),

              if (auth.loading)
                const CircularProgressIndicator(color: AppColors.primary),

              // ── Android 앱 베타 다운로드 (웹 전용, Play Store 정식 출시 전 임시 배포) ──
              if (kIsWeb) ...[
                const SizedBox(height: AppSpacing.lg),
                const _ApkDownloadCard(),
                const SizedBox(height: AppSpacing.sm),
                const PwaInstallButton(),
              ],

              const SizedBox(height: AppSpacing.lg),
              // 약관·개인정보 처리방침 동의 안내
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: RichText(
                  textAlign: TextAlign.center,
                  text: TextSpan(
                    style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                        height: 1.5),
                    children: [
                      const TextSpan(text: '로그인하면 PinFlick의 '),
                      TextSpan(
                        text: '이용약관',
                        style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            decoration: TextDecoration.underline,
                            color: AppColors.primary),
                        recognizer: TapGestureRecognizer()
                          ..onTap = () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const LegalScreen(
                                      type: LegalDocType.terms),
                                ),
                              ),
                      ),
                      const TextSpan(text: ' 및 '),
                      TextSpan(
                        text: '개인정보 처리방침',
                        style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            decoration: TextDecoration.underline,
                            color: AppColors.primary),
                        recognizer: TapGestureRecognizer()
                          ..onTap = () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const LegalScreen(
                                      type: LegalDocType.privacy),
                                ),
                              ),
                      ),
                      const TextSpan(text: '에\n동의하는 것으로 간주됩니다.'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              const AppVersionLabel(),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── APK 다운로드 카드 (베타 배포용) ──────────────────────────────────────────
class _ApkDownloadCard extends StatelessWidget {
  const _ApkDownloadCard();

  Future<void> _download(BuildContext context) async {
    HapticFeedback.mediumImpact();
    final uri = Uri.parse(apkDownloadUrl());
    final ok = await launchUrl(uri, webOnlyWindowName: '_self');
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('다운로드를 시작할 수 없습니다'),
        backgroundColor: AppColors.error,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primary.withValues(alpha: 0.06),
            const Color(0xFF34A853).withValues(alpha: 0.06),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
            color: AppColors.primary.withValues(alpha: 0.18), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.android, color: Color(0xFF34A853), size: 20),
              const SizedBox(width: 6),
              const Text(
                'Android 베타 앱',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'BETA',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Play 스토어 정식 출시 전까지 APK로 직접 설치할 수 있어요',
            style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.sm),
          ElevatedButton.icon(
            onPressed: () => _download(context),
            icon: const Icon(Icons.download_rounded, size: 18),
            label: const Text('APK 다운로드'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF34A853),
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 44),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              elevation: 0,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            '⚠ "출처를 알 수 없는 앱" 허용이 필요할 수 있어요',
            style: TextStyle(
                fontSize: 10.5,
                color: AppColors.textDisabled,
                fontStyle: FontStyle.italic),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _LoginButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final IconData icon;
  final String label;
  final Color backgroundColor;
  final Color foregroundColor;
  final Color? borderColor;

  const _LoginButton({
    required this.onPressed,
    required this.icon,
    required this.label,
    required this.backgroundColor,
    required this.foregroundColor,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: backgroundColor,
        foregroundColor: foregroundColor,
        disabledBackgroundColor: backgroundColor.withValues(alpha: 0.5),
        minimumSize: const Size(double.infinity, 52),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          side: borderColor != null
              ? BorderSide(color: borderColor!)
              : BorderSide.none,
        ),
        elevation: 1,
      ),
    );
  }
}
