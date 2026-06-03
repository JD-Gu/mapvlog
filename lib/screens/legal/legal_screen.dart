import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../utils/constants.dart';
import 'legal_documents.dart';

enum LegalDocType { privacy, terms }

/// 개인정보 처리방침 / 이용약관 표시 화면
///
/// 마크다운 비슷한 단순 포맷:
///   # 제목 → 큰 헤더
///   ## 소제목 → 중간 헤더
///   • / 숫자. → 리스트 라인
///   일반 문장 → 본문
class LegalScreen extends StatelessWidget {
  final LegalDocType type;
  const LegalScreen({super.key, required this.type});

  String get _title => switch (type) {
        LegalDocType.privacy => '개인정보 처리방침',
        LegalDocType.terms => '이용약관',
      };

  String get _body => switch (type) {
        LegalDocType.privacy => kPrivacyPolicy,
        LegalDocType.terms => kTermsOfService,
      };

  String get _effective => switch (type) {
        LegalDocType.privacy => kPrivacyPolicyEffective,
        LegalDocType.terms => kTermsOfServiceEffective,
      };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(_title,
            style: const TextStyle(
                fontSize: 17, fontWeight: FontWeight.w700)),
        backgroundColor: Theme.of(context).colorScheme.surface,
        elevation: 0,
        scrolledUnderElevation: 1,
        actions: [
          IconButton(
            icon: const Icon(Icons.copy_outlined, size: 20),
            tooltip: '전문 복사',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _body));
              HapticFeedback.lightImpact();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  duration: const Duration(seconds: 2),
                  content: Text('$_title 전문이 클립보드에 복사됐어요'),
                ),
              );
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.xl),
        children: [
          // 시행일 안내
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(
                  color: cs.primary.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                Icon(Icons.event_outlined,
                    size: 16, color: cs.primary),
                const SizedBox(width: 6),
                Text('시행일 $_effective',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: cs.primary)),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          ..._renderLines(context),
        ],
      ),
    );
  }

  List<Widget> _renderLines(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final widgets = <Widget>[];
    for (final raw in _body.split('\n')) {
      final line = raw.trimRight();
      if (line.isEmpty) {
        widgets.add(const SizedBox(height: 8));
        continue;
      }
      if (line.startsWith('# ')) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 4),
          child: Text(
            line.substring(2),
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: cs.onSurface,
              height: 1.3,
            ),
          ),
        ));
        continue;
      }
      if (line.startsWith('## ')) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 4),
          child: Text(
            line.substring(3),
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: cs.primary,
              height: 1.4,
            ),
          ),
        ));
        continue;
      }
      // 본문 — 리스트는 들여쓰기 유지하고 그대로 출력
      widgets.add(Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Text(
          line,
          style: TextStyle(
            fontSize: 13.5,
            color: cs.onSurface,
            height: 1.55,
          ),
        ),
      ));
    }
    return widgets;
  }
}
