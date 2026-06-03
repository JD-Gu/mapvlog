import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/remote_version.dart';
import '../services/web_version_check_service.dart';
import '../utils/constants.dart';

/// 새 버전 감지 시 화면 상단에 슬라이드 다운으로 나타나는 안내 배너.
/// 사용자가 탭하면 (웹) 강제 새로고침 / (모바일) APK 다운로드.
///
/// 토스/당근 스타일 — 작업 흐름 방해 없이 자연스럽게 안내.
class NewVersionBanner extends StatelessWidget {
  final RemoteVersion remote;
  final VoidCallback onDismiss;

  const NewVersionBanner({
    super.key,
    required this.remote,
    required this.onDismiss,
  });

  /// 화면 상단에 슬라이드 다운으로 띄움
  static void show(BuildContext context, RemoteVersion remote) {
    HapticFeedback.mediumImpact();
    final overlay = Overlay.of(context);
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (ctx) => Positioned(
        top: MediaQuery.of(ctx).padding.top + 12,
        left: 12,
        right: 12,
        child: NewVersionBanner(
          remote: remote,
          onDismiss: () => entry.remove(),
        ),
      ),
    );
    overlay.insert(entry);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return _AnimatedSlideDown(
      child: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        color: cs.primary,
        shadowColor: Colors.black.withValues(alpha: 0.4),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          onTap: () async {
            HapticFeedback.lightImpact();
            if (kIsWeb) {
              // 웹: 캐시 삭제 + cache-bust reload
              WebVersionCheckService.reloadNow();
            } else {
              // 모바일: APK 다운로드 URL 열기
              try {
                await launchUrl(
                  Uri.parse(apkDownloadUrl(remote.build)),
                  mode: LaunchMode.externalApplication,
                );
              } catch (_) {}
            }
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: const Text('✨', style: TextStyle(fontSize: 18)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        remote.version.isNotEmpty
                            ? 'v${remote.version} 새 버전이 나왔어요'
                            : '새 버전이 출시됐어요',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      // 업데이트 내역 (있으면) — 최대 2줄
                      if (remote.notes != null &&
                          remote.notes!.trim().isNotEmpty)
                        Text(
                          remote.notes!.trim(),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.92),
                            fontSize: 11.5,
                            fontWeight: FontWeight.w500,
                            height: 1.3,
                          ),
                        ),
                      const SizedBox(height: 2),
                      Text(
                        kIsWeb
                            ? '탭하면 최신 화면으로 새로고침'
                            : '탭하면 최신 APK 다운로드',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.8),
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: onDismiss,
                  icon: const Icon(Icons.close,
                      color: Colors.white, size: 18),
                  tooltip: '닫기',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 위에서 슬라이드 다운으로 진입하는 래퍼
class _AnimatedSlideDown extends StatefulWidget {
  final Widget child;
  const _AnimatedSlideDown({required this.child});

  @override
  State<_AnimatedSlideDown> createState() => _AnimatedSlideDownState();
}

class _AnimatedSlideDownState extends State<_AnimatedSlideDown>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
  )..forward();

  late final Animation<Offset> _slide = Tween<Offset>(
    begin: const Offset(0, -1.2),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));

  late final Animation<double> _fade = CurvedAnimation(
    parent: _ctrl,
    curve: Curves.easeOut,
  );

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}
