import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/app_update_info.dart';
import '../services/app_update_service.dart';
import '../utils/constants.dart';

/// 사용자 단말에 띄우는 신규 버전 안내 시트.
///
/// - mandatory==false 인 경우: 드래그/외부 탭으로 닫기 가능, "나중에" 버튼 노출
/// - mandatory==true 인 경우: 닫기 불가, 업데이트 강제
class UpdatePromptSheet {
  static Future<void> show(BuildContext context, AppUpdateInfo info) async {
    HapticFeedback.mediumImpact();
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: !info.mandatory,
      enableDrag: !info.mandatory,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _UpdateSheet(info: info),
    );
  }
}

class _UpdateSheet extends StatelessWidget {
  final AppUpdateInfo info;
  const _UpdateSheet({required this.info});

  Future<void> _download(BuildContext context) async {
    HapticFeedback.mediumImpact();
    final uri = Uri.parse(info.apkUrl);
    // 모바일 → 외부 브라우저로 열어 APK 다운로드, 웹 → 새 탭
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('다운로드를 시작할 수 없어요'),
        backgroundColor: AppColors.error,
      ));
    }
  }

  Future<void> _later(BuildContext context) async {
    HapticFeedback.selectionClick();
    await AppUpdateService.dismissUpdate(info.latestBuildNumber);
    if (context.mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
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
            // 헤더 — 🎉 + 새 버전 표기
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF1A73E8), Color(0xFF34A853)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: const Text('🎉',
                      style: TextStyle(fontSize: 22)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '새 버전이 나왔어요',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Text(
                            'v$kAppVersion → v${info.latestVersion}',
                            style: const TextStyle(
                              fontSize: 12.5,
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(width: 6),
                          if (info.mandatory)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 5, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.error,
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: const Text('필수',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold)),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            // 릴리스 노트
            if (info.releaseNotes.trim().isNotEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('이번 업데이트',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textSecondary,
                            letterSpacing: 0.5)),
                    const SizedBox(height: 6),
                    Text(
                      info.releaseNotes.trim(),
                      style: const TextStyle(
                        fontSize: 13.5,
                        height: 1.55,
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 18),
            // 액션 버튼
            ElevatedButton.icon(
              onPressed: () => _download(context),
              icon: Icon(kIsWeb ? Icons.open_in_new : Icons.download_rounded),
              label: Text(kIsWeb ? '새 버전 보기' : 'APK 다운로드'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                elevation: 0,
              ),
            ),
            if (!info.mandatory) ...[
              const SizedBox(height: 6),
              TextButton(
                onPressed: () => _later(context),
                child: const Text('나중에',
                    style: TextStyle(color: AppColors.textSecondary)),
              ),
            ],
            const SizedBox(height: 4),
            const Text(
              '⚠ Play 스토어 정식 출시 전 베타 배포 — APK 직접 설치',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 11,
                  color: AppColors.textDisabled,
                  fontStyle: FontStyle.italic),
            ),
          ],
        ),
      ),
    );
  }
}

/// 마스터 전용 — 새 버전 발행 다이얼로그
class PublishUpdateDialog {
  static Future<void> show(BuildContext context) async {
    final notesCtrl = TextEditingController();
    final mandatoryNotifier = ValueNotifier<bool>(false);

    // 현재 발행된 노트 미리 로드
    final current = await AppUpdateService.getCurrentPublished();
    if (current != null) notesCtrl.text = current.releaseNotes;

    if (!context.mounted) return;

    await showDialog<void>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.rocket_launch, color: AppColors.primary, size: 20),
            SizedBox(width: 8),
            Text('새 버전 발행'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '발행할 버전: v$kAppVersion (build $kAppBuildNumber)',
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              if (current != null)
                Text(
                  '※ 현재 발행: v${current.latestVersion} (build ${current.latestBuildNumber})',
                  style: const TextStyle(
                      fontSize: 11.5, color: AppColors.textSecondary),
                ),
              const SizedBox(height: 14),
              TextField(
                controller: notesCtrl,
                maxLines: 5,
                minLines: 3,
                decoration: const InputDecoration(
                  labelText: '릴리스 노트',
                  hintText: '• 댓글 좋아요 추가\n• 검색 기능 추가',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              ValueListenableBuilder<bool>(
                valueListenable: mandatoryNotifier,
                builder: (_, v, __) => CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  dense: true,
                  value: v,
                  onChanged: (b) => mandatoryNotifier.value = b ?? false,
                  title: const Text('필수 업데이트 (강제)',
                      style: TextStyle(fontSize: 13)),
                  subtitle: const Text(
                      '체크 시 사용자가 "나중에"로 닫지 못함',
                      style: TextStyle(fontSize: 11)),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dctx),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () async {
              final notes = notesCtrl.text.trim();
              if (notes.isEmpty) {
                ScaffoldMessenger.of(dctx).showSnackBar(const SnackBar(
                  content: Text('릴리스 노트를 입력해 주세요'),
                  backgroundColor: AppColors.error,
                ));
                return;
              }
              try {
                await AppUpdateService.publishUpdate(
                  version: kAppVersion,
                  buildNumber: int.tryParse(kAppBuildNumber) ?? 0,
                  releaseNotes: notes,
                  mandatory: mandatoryNotifier.value,
                );
                if (dctx.mounted) Navigator.pop(dctx);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(
                        '🚀 v$kAppVersion (build $kAppBuildNumber) 발행 완료'),
                    backgroundColor: AppColors.secondary,
                  ));
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text('발행 실패: $e'),
                    backgroundColor: AppColors.error,
                  ));
                }
              }
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white),
            child: const Text('발행'),
          ),
        ],
      ),
    );
  }
}
