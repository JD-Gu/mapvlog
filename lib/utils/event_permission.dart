import 'package:firebase_auth/firebase_auth.dart';

import '../models/event.dart';

/// 이벤트 권한 3단계 — Super Master / Event Master / User.
/// - Super Master: 이메일 기준(jaduck9). 전체 권한 + Event Master 임명/해제.
/// - Event Master: users/{uid}.eventRole == 'event' + eventCategories(담당).
/// - User: 권한 없음.
class EventPermission {
  static const String superEmail = 'jaduck9@gmail.com';

  static bool get isSuper =>
      FirebaseAuth.instance.currentUser?.email == superEmail;

  /// 관리(등록/수정/삭제) 가능한 카테고리 목록
  static List<EventCategory> allowedCategories(String role, List<String> cats) {
    if (isSuper || cats.contains('all')) return EventCategory.adminCategories;
    if (role != 'event') return const [];
    return EventCategory.adminCategories
        .where((c) => cats.contains(c.value))
        .toList();
  }

  /// 이벤트를 하나라도 관리할 수 있는가 (등록 버튼 노출 여부)
  static bool canManageAny(String role, List<String> cats) =>
      isSuper || (role == 'event' && cats.isNotEmpty);

  static bool canManageCategory(
      String role, List<String> cats, EventCategory c) {
    if (isSuper) return true;
    if (role != 'event') return false;
    return cats.contains('all') || cats.contains(c.value);
  }
}
