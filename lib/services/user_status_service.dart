import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/user_status.dart';

/// 사용자 상태·라이브 위치·프라이버시 관리 (Firestore `users` 컬렉션)
class UserStatusService {
  static final _db = FirebaseFirestore.instance;
  static final _users = _db.collection('users');

  /// 백그라운드 위치 공유 ON/OFF 를 Firestore 에 저장 (서버 스케줄러가 읽음)
  static Future<void> setBgLocationEnabled(String uid, bool enabled) async {
    await _users
        .doc(uid)
        .set({'bgLocationEnabled': enabled}, SetOptions(merge: true));
  }

  /// 모든 사용자의 라이브 정보 스트림 (위치 있는 사용자만)
  static Stream<List<LiveUser>> watchAllLiveUsers() {
    return _users
        .where('liveLocation', isNull: false)
        .snapshots()
        .map((snap) => snap.docs.map(LiveUser.fromDoc).toList());
  }

  /// 특정 사용자의 라이브 정보 스트림
  static Stream<LiveUser?> watchUser(String uid) {
    return _users.doc(uid).snapshots().map((doc) {
      if (!doc.exists) return null;
      return LiveUser.fromDoc(doc);
    });
  }

  /// 1회 조회
  static Future<LiveUser?> getUser(String uid) async {
    final doc = await _users.doc(uid).get();
    if (!doc.exists) return null;
    return LiveUser.fromDoc(doc);
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
      });
    }
  }

  /// 상태 설정 (이모지 + 라벨)
  static Future<void> setStatus({
    required String uid,
    required String emoji,
    required String label,
  }) async {
    await _users.doc(uid).set({
      'status': {
        'emoji': emoji,
        'label': label,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      'lastSeen': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// 상태 제거
  static Future<void> clearStatus(String uid) async {
    await _users.doc(uid).update({'status': FieldValue.delete()});
  }

  /// 프라이버시 모드 설정 (얼음 모드인 경우 현재 위치를 frozenLocation으로 저장)
  static Future<void> setPrivacyMode({
    required String uid,
    required PrivacyMode mode,
    double? currentLat,
    double? currentLng,
  }) async {
    final data = <String, dynamic>{
      'privacyMode': mode.value,
      'lastSeen': FieldValue.serverTimestamp(),
    };
    // 얼음 모드 진입 시 현재 위치를 동결
    if (mode == PrivacyMode.ice &&
        currentLat != null &&
        currentLng != null) {
      data['frozenLocation'] = {
        'lat': currentLat,
        'lng': currentLng,
        'frozenAt': FieldValue.serverTimestamp(),
      };
      // 동결 위치를 표시 위치로도 설정
      data['liveLocation'] = {
        'lat': currentLat,
        'lng': currentLng,
        'updatedAt': FieldValue.serverTimestamp(),
      };
    }
    await _users.doc(uid).set(data, SetOptions(merge: true));
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

    await _users.doc(uid).set({
      'liveLocation': {
        'lat': finalLat,
        'lng': finalLng,
        'updatedAt': FieldValue.serverTimestamp(),
        if (isMoving != null) 'isMoving': isMoving,
        if (batteryLevel != null) 'batteryLevel': batteryLevel,
      },
      'lastSeen': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
