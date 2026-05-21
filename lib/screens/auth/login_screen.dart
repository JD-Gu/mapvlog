import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app.dart';
import '../../providers/auth_provider.dart';
import '../../utils/constants.dart';

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
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 로고
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                ),
                child: const Icon(Icons.map, size: 48, color: Colors.white),
              ),
              const SizedBox(height: AppSpacing.md),
              const Text(
                'MapVlog',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
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

              // Google 로그인
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
              const SizedBox(height: AppSpacing.sm),

              // Apple 로그인 — iOS / macOS 전용
              if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS)
                _LoginButton(
                  onPressed: null, // TODO: sign_in_with_apple 연동 (마일스톤 2+)
                  icon: Icons.apple,
                  label: 'Apple로 로그인',
                  backgroundColor: Colors.black,
                  foregroundColor: Colors.white,
                ),

              // 카카오 로그인 — TODO: kakao_flutter_sdk 연동
              const SizedBox(height: AppSpacing.sm),
              _LoginButton(
                onPressed: null,
                icon: Icons.chat_bubble,
                label: '카카오로 로그인',
                backgroundColor: const Color(0xFFFEE500),
                foregroundColor: Colors.black87,
              ),

              const SizedBox(height: AppSpacing.xl),

              if (auth.loading)
                const CircularProgressIndicator(color: AppColors.primary),

              // 로그인 없이 둘러보기
              TextButton(
                onPressed: auth.loading
                    ? null
                    : () => Navigator.of(context).pushReplacement(
                          MaterialPageRoute(
                              builder: (_) => const MainShell()),
                        ),
                child: const Text(
                  '로그인 없이 둘러보기',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ),
            ],
          ),
        ),
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
