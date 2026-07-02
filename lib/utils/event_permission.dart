import 'package:firebase_auth/firebase_auth.dart';

import '../models/event.dart';

/// 이벤트 권한 3단계 — Super Master / Event Master / User.
/// - Super Master: 부트스트랩 오너(이메일 jaduck9) **또는** eventRole == 'super'.
///   전체 권한 + Event Master/Super Master 임명·해제.
/// - Event Master: users/{uid}.eventRole == 'event' + eventCategories(담당).
/// - User: 권한 없음.
class EventPermission {
  /// 부트스트랩 오너 — 항상 슈퍼(자기 자신을 강등할 수 없어 잠김 방지용).
  /// 추가 슈퍼는 eventRole == 'super' 로 부여한다.
  static const String superEmail = 'jaduck9@gmail.com';

  /// 이메일 기준 부트스트랩 슈퍼 여부(오너 본인).
  static bool get isBootstrapSuper =>
      FirebaseAuth.instance.currentUser?.email == superEmail;

  /// 역할 기반 슈퍼 판정 — 부트스트랩 오너이거나 eventRole == 'super'.
  /// [role] 은 현재 사용자의 users/{uid}.eventRole (watchEventRole 스트림값).
  static bool isSuperRole(String role) => isBootstrapSuper || role == 'super';

  /// 관리(등록/수정/삭제) 가능한 카테고리 목록
  static List<EventCategory> allowedCategories(String role, List<String> cats) {
    if (isSuperRole(role) || cats.contains('all')) {
      return EventCategory.adminCategories;
    }
    if (role != 'event') return const [];
    return EventCategory.adminCategories
        .where((c) => cats.contains(c.value))
        .toList();
  }

  /// 이벤트를 하나라도 관리할 수 있는가 (등록 버튼 노출 여부)
  static bool canManageAny(String role, List<String> cats) =>
      isSuperRole(role) || (role == 'event' && cats.isNotEmpty);

  static bool canManageCategory(
      String role, List<String> cats, EventCategory c) {
    if (isSuperRole(role)) return true;
    if (role != 'event') return false;
    return cats.contains('all') || cats.contains(c.value);
  }
}
