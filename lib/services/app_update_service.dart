import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_update_info.dart';
import '../utils/constants.dart';

/// 신규 버전 발행 + 사용자 단말 업데이트 감지 서비스
///
/// Firestore: `config/app_version` 문서를 단일 소스로 사용
/// - 마스터가 [publishUpdate] 호출로 새 빌드 발행
/// - 모든 클라이언트가 앱 시작 시 [checkForUpdate] 호출
/// - 사용자가 "나중에" 선택하면 해당 buildNumber를 로컬에 기억해 다시 띄우지 않음
class AppUpdateService {
  static const _docPath = 'config/app_version';
  static const _dismissedKey = 'dismissed_update_buildNumber';

  static DocumentReference<Map<String, dynamic>> get _doc =>
      FirebaseFirestore.instance.doc(_docPath);

  /// 현재 빌드가 outdated이고, 사용자가 이번 버전을 dismiss 하지 않았으면 정보 반환.
  /// 그 외에는 null.
  static Future<AppUpdateInfo?> checkForUpdate() async {
    try {
      final doc = await _doc.get();
      if (!doc.exists) return null;
      final info = AppUpdateInfo.fromMap(doc.data()!);
      final currentBuild = int.tryParse(kAppBuildNumber) ?? 0;
      if (!info.isNewerThan(currentBuild)) return null;

      // 사용자가 이번 신규 버전을 이미 dismiss 했으면 표시 안 함 (강제 업데이트는 예외)
      if (!info.mandatory) {
        final prefs = await SharedPreferences.getInstance();
        final dismissed = prefs.getInt(_dismissedKey) ?? 0;
        if (dismissed >= info.latestBuildNumber) return null;
      }
      return info;
    } catch (e) {
      debugPrint('[AppUpdate] check 실패: $e');
      return null;
    }
  }

  /// 이 빌드번호의 업데이트 안내를 다시 표시하지 않음
  static Future<void> dismissUpdate(int buildNumber) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_dismissedKey, buildNumber);
  }

  /// 마스터 전용 — 새 버전 발행
  ///
  /// Firestore 규칙에서 마스터 UID만 write 허용
  static Future<void> publishUpdate({
    required String version,
    required int buildNumber,
    required String releaseNotes,
    String apkUrl = 'https://pinflick.web.app/downloads/pinflick.apk',
    bool mandatory = false,
  }) async {
    await _doc.set({
      'latestVersion': version,
      'latestBuildNumber': buildNumber,
      'apkUrl': apkUrl,
      'releaseNotes': releaseNotes,
      'mandatory': mandatory,
      'publishedAt': FieldValue.serverTimestamp(),
    });
  }

  /// 현재 발행된 버전 조회 (마스터 UI 미리 표시용)
  static Future<AppUpdateInfo?> getCurrentPublished() async {
    try {
      final doc = await _doc.get();
      if (!doc.exists) return null;
      return AppUpdateInfo.fromMap(doc.data()!);
    } catch (e) {
      debugPrint('[AppUpdate] getCurrentPublished 실패: $e');
      return null;
    }
  }
}
