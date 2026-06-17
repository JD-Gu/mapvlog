import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/user_status.dart';

/// 사용자 상태·라이브 위치·프라이버시 관리 (Firestore `users` 컬렉션)
class UserStatusService {
  static final _db = FirebaseFirestore.instance;
  static final _users = _db.collection('users');
  // 민감 좌표 분리 컬렉션 — visibleTo(친구)만 열람 (firestore.rules)
  static final _live = _db.collection('liveLocations');

  /// 백그라운드 위치 공유 ON/OFF 를 Firestore 에 저장 (서버 스케줄러가 읽음)
  static Future<void> setBgLocationEnabled(String uid, bool enabled) async {
    await _users
        .doc(uid)
        .set({'bgLocationEnabled': enabled}, SetOptions(merge: true));
  }

  // ── 이벤트 역할 (Event Master) ─────────────────────────────────────────────

  /// 이벤트 역할 + 담당 카테고리 스트림. role='' (없음) | 'event' | 'super'
  static Stream<({String role, List<String> cats})> watchEventRole(
      String uid) {
    return _users.doc(uid).snapshots().map((d) {
      final m = d.data() ?? <String, dynamic>{};
      return (
        role: (m['eventRole'] as String?) ?? '',
        cats: ((m['eventCategories'] as List<dynamic>?) ?? const [])
            .map((e) => e.toString())
            .toList(),
      );
    });
  }

  static Future<({String role, List<String> cats})> getEventRole(
      String uid) async {
    final d = await _users.doc(uid).get();
    final m = d.data() ?? <String, dynamic>{};
    return (
      role: (m['eventRole'] as String?) ?? '',
      cats: ((m['eventCategories'] as List<dynamic>?) ?? const [])
          .map((e) => e.toString())
          .toList(),
    );
  }

  /// 현재 이벤트 마스터 목록 (Super 관리 화면용)
  static Stream<List<Map<String, dynamic>>> watchEventMasters() {
    return _users
        .where('eventRole', isEqualTo: 'event')
        .snapshots()
        .map((s) => s.docs.map((d) => {'uid': d.id, ...d.data()}).toList());
  }

  /// Super 가 Event Master 임명/해제 (categories: ['all'] 또는 카테고리 코드들)
  static Future<void> setEventMaster(String uid,
      {required bool enabled, List<String> categories = const []}) async {
    if (enabled) {
      await _users.doc(uid).set(
          {'eventRole': 'event', 'eventCategories': categories},
          SetOptions(merge: true));
    } else {
      await _users.doc(uid).set({
        'eventRole': FieldValue.delete(),
        'eventCategories': FieldValue.delete(),
      }, SetOptions(merge: true));
    }
  }

  /// 나에게 공개된(visibleTo 에 내 uid 포함) 친구들의 라이브 위치 스트림.
  /// 규칙상 친구 것만 내려오며, 내 doc 도 자기 visibleTo 에 포함돼 함께 옴.
  static Stream<List<LiveUser>> watchVisibleLiveUsers(String myUid) {
    return _live
        .where('visibleTo', arrayContains: myUid)
        .snapshots()
        .map((snap) => snap.docs.map(LiveUser.fromDoc).toList());
  }

  /// 내 라이브 정보 스트림 (본인 doc — 카메라 이동/프라이버시 상태용)
  static Stream<LiveUser?> watchMyLive(String uid) {
    return _live.doc(uid).snapshots().map((doc) {
      if (!doc.exists) return null;
      return LiveUser.fromDoc(doc);
    });
  }

  /// 내 위치 공개 대상(visibleTo) 설정 — 수락된 친구 + 본인.
  /// 친구 목록 변경 시 호출(친구지도) + 앱 시작 시 reconcile(ensureUserDoc).
  static Future<void> setLocationAudience(
      String uid, List<String> friendUids) async {
    final audience = <String>{...friendUids, uid}.toList();
    await _live.doc(uid).set({'visibleTo': audience}, SetOptions(merge: true));
  }

  /// 사용자 문서 초기화 — 첫 로그인/접속 시 호출
  static Future<void> ensureUserDoc(User user) async {
    final ref = _users.doc(user.uid);
    final doc = await ref.get();
    if (!doc.exists) {
      await ref.set({
        'uid': user.uid,
        'displayName': user.displayName ?? user.email ?? '사용자',
        'photoUrl': user.photoURL,
        'privacyMode': PrivacyMode.fog.value, // 안전한 기본값
        'lastSeen': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
      });
    } else {
      // 이름·사진 변경 동기화 + lastSeen 갱신
      await ref.update({
        'displayName': user.displayName ?? user.email ?? '사용자',
        if (user.photoURL != null) 'photoUrl': user.photoURL,
        'lastSeen': FieldValue.serverTimestamp(),
        // 구 버전이 users 문서에 남긴 좌표 정리 (이제 liveLocations 로 분리)
        'liveLocation': FieldValue.delete(),
        'frozenLocation': FieldValue.delete(),
      });
    }

    // liveLocations 시드 + visibleTo reconcile (마이그레이션 자동 치유)
    await _reconcileLiveDoc(user);
  }

  /// liveLocations/{uid} 의 프로필 미러 + visibleTo(수락 친구+본인) 동기화.
  /// 좌표는 건드리지 않음(위치 업데이트가 채움).
  static Future<void> _reconcileLiveDoc(User user) async {
    try {
      final uid = user.uid;
      final uDoc = await _users.doc(uid).get();
      final ud = uDoc.data() ?? <String, dynamic>{};
      final friendsSnap = await _users
          .doc(uid)
          .collection('friends')
          .where('status', isEqualTo: 'accepted')
          .get();
      final friendUids = friendsSnap.docs.map((d) => d.id).toList();
      await _live.doc(uid).set({
        'displayName':
            (ud['displayName'] as String?) ?? user.displayName ?? '사용자',
        'photoUrl': (ud['photoUrl'] as String?) ?? user.photoURL,
        'privacyMode': (ud['privacyMode'] as String?) ?? PrivacyMode.fog.value,
        if (ud['status'] is Map) 'status': ud['status'],
        'visibleTo': <String>{...friendUids, uid}.toList(),
      }, SetOptions(merge: true));
    } catch (_) {
      // 친구 목록 권한/네트워크 일시 오류는 다음 호출에서 자가 치유
    }
  }

  /// 상태 설정 (이모지 + 라벨)
  static Future<void> setStatus({
    required String uid,
    required String emoji,
    required String label,
  }) async {
    final status = {
      'emoji': emoji,
      'label': label,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    await _users.doc(uid).set({
      'status': status,
      'lastSeen': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    // 지도 표시는 liveLocations 를 읽으므로 미러
    await _live.doc(uid).set({'status': status}, SetOptions(merge: true));
  }

  /// 상태 제거
  static Future<void> clearStatus(String uid) async {
    await _users.doc(uid).update({'status': FieldValue.delete()});
    await _live.doc(uid).set(
        {'status': FieldValue.delete()}, SetOptions(merge: true));
  }

  /// 프라이버시 모드 설정 (얼음 모드인 경우 현재 위치를 frozenLocation으로 저장)
  static Future<void> setPrivacyMode({
    required String uid,
    required PrivacyMode mode,
    double? currentLat,
    double? currentLng,
  }) async {
    // privacyMode 는 users 에 정본 보관(updateLocation 이 읽어 마스킹)
    await _users.doc(uid).set({
      'privacyMode': mode.value,
      'lastSeen': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    // 지도 표시·동결 좌표는 liveLocations 로
    final live = <String, dynamic>{
      'privacyMode': mode.value,
      'lastSeen': FieldValue.serverTimestamp(),
    };
    if (mode == PrivacyMode.ice &&
        currentLat != null &&
        currentLng != null) {
      live['frozenLocation'] = {
        'lat': currentLat,
        'lng': currentLng,
        'frozenAt': FieldValue.serverTimestamp(),
      };
      // 동결 위치를 표시 위치로도 설정
      live['liveLocation'] = {
        'lat': currentLat,
        'lng': currentLng,
        'updatedAt': FieldValue.serverTimestamp(),
      };
    }
    await _live.doc(uid).set(live, SetOptions(merge: true));
  }

  // ─── 친구 호출 (Ping) ────────────────────────────────────────────────────

  /// 다른 사용자에게 호출(ping) 전송
  static Future<void> sendPing({
    required String toUid,
    required String fromUid,
    required String fromName,
    required String emoji,
    required String message,
  }) async {
    await _users.doc(toUid).collection('pings').add({
      'fromUid': fromUid,
      'fromName': fromName,
      'emoji': emoji,
      'message': message,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// 내 호출함 스트림 (최근 1시간 이내 호출만)
  static Stream<List<Ping>> watchMyPings(String uid) {
    final cutoff = DateTime.now().subtract(const Duration(hours: 1));
    return _users
        .doc(uid)
        .collection('pings')
        .where('createdAt', isGreaterThan: Timestamp.fromDate(cutoff))
        .orderBy('createdAt', descending: true)
        .limit(10)
        .snapshots()
        .map((snap) => snap.docs.map(Ping.fromDoc).toList());
  }

  /// 호출 문서 삭제 (확인 완료 시)
  static Future<void> deletePing(String uid, String pingId) async {
    await _users.doc(uid).collection('pings').doc(pingId).delete();
  }

  /// 현재 위치 업데이트 — 프라이버시 모드에 따라 변형됨
  ///
  /// - precise: 정확한 좌표 저장
  /// - fog: ≈1km 반경으로 흐림 처리 후 저장
  /// - ice: 업데이트 무시 (frozenLocation 유지)
  static Future<void> updateLocation({
    required String uid,
    required double lat,
    required double lng,
    bool? isMoving,
    int? batteryLevel,
  }) async {
    final doc = await _users.doc(uid).get();
    final mode = doc.exists
        ? PrivacyMode.fromString(
            (doc.data() as Map<String, dynamic>)['privacyMode'] as String?)
        : PrivacyMode.fog;

    // 얼음 모드는 업데이트 안 함
    if (mode == PrivacyMode.ice) return;

    double finalLat = lat;
    double finalLng = lng;

    if (mode == PrivacyMode.fog) {
      // 안개 모드: 0.005도(≈500m) 그리드 + 무작위 오프셋(≤500m) → 약 1km 정밀도
      const grid = 0.005;
      finalLat = (lat / grid).round() * grid;
      finalLng = (lng / grid).round() * grid;
      // 그리드 안에서 자연스러운 무작위 분포
      final rnd = math.Random(uid.hashCode);
      finalLat += (rnd.nextDouble() - 0.5) * grid;
      finalLng += (rnd.nextDouble() - 0.5) * grid;
    }

    final ud = doc.exists
        ? (doc.data() as Map<String, dynamic>)
        : <String, dynamic>{};
    final auth = FirebaseAuth.instance.currentUser;
    await _live.doc(uid).set({
      'liveLocation': {
        'lat': finalLat,
        'lng': finalLng,
        'updatedAt': FieldValue.serverTimestamp(),
        if (isMoving != null) 'isMoving': isMoving,
        if (batteryLevel != null) 'batteryLevel': batteryLevel,
      },
      'lastSeen': FieldValue.serverTimestamp(),
      'privacyMode': mode.value,
      'displayName':
          (ud['displayName'] as String?) ?? auth?.displayName ?? '사용자',
      'photoUrl': (ud['photoUrl'] as String?) ?? auth?.photoURL,
      if (ud['status'] is Map) 'status': ud['status'],
      // 본인은 자기 지도에서 항상 보이도록 self-visibility 보장
      'visibleTo': FieldValue.arrayUnion([uid]),
    }, SetOptions(merge: true));
  }
}
