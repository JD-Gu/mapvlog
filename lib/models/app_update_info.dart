import 'package:cloud_firestore/cloud_firestore.dart';

/// `config/app_version` 문서 → 신규 버전 메타데이터
///
/// Build Number (정수)로 비교 — semver 파싱 회피.
class AppUpdateInfo {
  final String latestVersion;       // 예: '1.2.1'
  final int latestBuildNumber;      // 예: 5  (build number 단조증가)
  final String apkUrl;              // 다운로드 URL
  final String releaseNotes;        // 릴리스 노트 (멀티라인)
  final bool mandatory;             // 강제 업데이트 여부
  final DateTime? publishedAt;

  const AppUpdateInfo({
    required this.latestVersion,
    required this.latestBuildNumber,
    required this.apkUrl,
    required this.releaseNotes,
    this.mandatory = false,
    this.publishedAt,
  });

  factory AppUpdateInfo.fromMap(Map<String, dynamic> m) => AppUpdateInfo(
        latestVersion: m['latestVersion'] as String? ?? '',
        latestBuildNumber:
            (m['latestBuildNumber'] as num?)?.toInt() ?? 0,
        apkUrl: m['apkUrl'] as String? ?? '',
        releaseNotes: m['releaseNotes'] as String? ?? '',
        mandatory: m['mandatory'] as bool? ?? false,
        publishedAt: (m['publishedAt'] as Timestamp?)?.toDate(),
      );

  /// 현재 build > latestBuild 가 더 크면 업데이트 필요
  bool isNewerThan(int currentBuildNumber) =>
      latestBuildNumber > currentBuildNumber;
}
