import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../models/friendship.dart';

/// 친구 관계 관리 서비스
///
/// 데이터 구조 (양방향 denormalize):
///   users/{myUid}/friends/{friendUid} ← 내가 본 관계
///   users/{friendUid}/friends/{myUid} ← 상대가 본 관계
///
/// status 값:
///   - pending: 내가 보낸 요청
///   - incoming: 상대가 나에게 보낸 요청
///   - accepted: 양방향 수락 완료
class FriendService {
  static final _db = FirebaseFirestore.instance;
  static final _users = _db.collection('users');

  static String? get _myUid => FirebaseAuth.instance.currentUser?.uid;

  // ─── 조회 ─────────────────────────────────────────────────────────────────

  /// 내 친구 목록 스트림 (status=accepted)
  static Stream<List<Friendship>> watchMyFriends() {
    final uid = _myUid;
    if (uid == null) return Stream.value([]);
    return _users
        .doc(uid)
        .collection('friends')
        .where('status', isEqualTo: 'accepted')
        .snapshots()
        .map((snap) {
      final list = snap.docs.map(Friendship.fromDoc).toList();
      list.sort((a, b) => (b.acceptedAt ?? b.createdAt)
          .compareTo(a.acceptedAt ?? a.createdAt));
      return list;
    });
  }

  /// 들어온 친구 요청 (status=incoming)
  static Stream<List<Friendship>> watchIncomingRequests() {
    final uid = _myUid;
    if (uid == null) return Stream.value([]);
    return _users
        .doc(uid)
        .collection('friends')
        .where('status', isEqualTo: 'incoming')
        .snapshots()
        .map((snap) {
      final list = snap.docs.map(Friendship.fromDoc).toList();
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return list;
    });
  }

  /// 내가 보낸 친구 요청 (status=pending)
  static Stream<List<Friendship>> watchOutgoingRequests() {
    final uid = _myUid;
    if (uid == null) return Stream.value([]);
    return _users
        .doc(uid)
        .collection('friends')
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .map((snap) {
      final list = snap.docs.map(Friendship.fromDoc).toList();
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return list;
    });
  }

  /// 내 친구 UID 목록 (피드 필터링용)
  static Future<List<String>> getMyFriendUids() async {
    final uid = _myUid;
    if (uid == null) return [];
    final snap = await _users
        .doc(uid)
        .collection('friends')
        .where('status', isEqualTo: 'accepted')
        .get();
    return snap.docs.map((d) => d.id).toList();
  }

  /// 특정 사용자와의 관계 단건 조회
  static Future<Friendship?> getFriendship(String otherUid) async {
    final uid = _myUid;
    if (uid == null) return null;
    final doc = await _users.doc(uid).collection('friends').doc(otherUid).get();
    if (!doc.exists) return null;
    return Friendship.fromDoc(doc);
  }

  // ─── 이메일로 사용자 검색 ───────────────────────────────────────────────

  static Future<Map<String, dynamic>?> findUserByEmail(String email) async {
    final trimmed = email.trim().toLowerCase();
    if (trimmed.isEmpty) return null;
    final snap = await _users
        .where('email', isEqualTo: trimmed)
        .limit(1)
        .get();
    if (snap.docs.isEmpty) {
      // 대소문자 다를 수 있으니 원본도 시도
      final snap2 = await _users
          .where('email', isEqualTo: email.trim())
          .limit(1)
          .get();
      if (snap2.docs.isEmpty) return null;
      final d = snap2.docs.first.data();
      return {'uid': snap2.docs.first.id, ...d};
    }
    final d = snap.docs.first.data();
    return {'uid': snap.docs.first.id, ...d};
  }

  // ─── 사용자 검색 (이름 prefix + 이메일 prefix) ────────────────────────────
  ///
  /// 본인은 결과에서 제외. limit 30.
  static Future<List<Map<String, dynamic>>> searchUsers(String query) async {
    final q = query.trim();
    if (q.isEmpty) return [];
    final me = _myUid;

    // displayName / email 두 필드를 prefix 매치 (Firestore range query)
    final upper = '$q';
    final results = await Future.wait([
      _users
          .where('displayName', isGreaterThanOrEqualTo: q)
          .where('displayName', isLessThan: upper)
          .limit(20)
          .get(),
      _users
          .where('email', isGreaterThanOrEqualTo: q.toLowerCase())
          .where('email', isLessThan: '${q.toLowerCase()}')
          .limit(20)
          .get(),
    ]);

    final seen = <String>{};
    final out = <Map<String, dynamic>>[];
    for (final snap in results) {
      for (final doc in snap.docs) {
        if (doc.id == me) continue;
        if (!seen.add(doc.id)) continue;
        out.add({'uid': doc.id, ...doc.data()});
      }
    }
    return out.take(30).toList();
  }

  // ─── 요청/수락/거절 ───────────────────────────────────────────────────────

  /// 친구 요청 보내기 (A → B)
  ///
  /// 양쪽 doc 동시 생성:
  ///   users/A/friends/B → status=pending
  ///   users/B/friends/A → status=incoming
  static Future<void> sendRequest({
    required String toUid,
    required String toName,
    String? toPhotoUrl,
    String? toEmail,
  }) async {
    final uid = _myUid;
    if (uid == null) throw Exception('로그인이 필요합니다');
    if (uid == toUid) throw Exception('자기 자신에게 요청할 수 없습니다');

    // 이미 친구이거나 요청 진행 중이면 중복 방지
    final existing = await getFriendship(toUid);
    if (existing != null) {
      throw Exception(switch (existing.status) {
        FriendshipStatus.accepted => '이미 친구입니다',
        FriendshipStatus.pending => '이미 요청을 보냈습니다',
        FriendshipStatus.incoming => '상대가 보낸 요청이 있습니다. 수락해 주세요',
      });
    }

    // 내 정보 가져오기 (상대 doc에 저장할 용도)
    final user = FirebaseAuth.instance.currentUser!;
    final myName = user.displayName ?? user.email ?? '익명';
    final myPhotoUrl = user.photoURL;
    final myEmail = user.email;

    final batch = _db.batch();
    final now = FieldValue.serverTimestamp();

    batch.set(_users.doc(uid).collection('friends').doc(toUid), {
      'status': FriendshipStatus.pending.value,
      'relType': FriendRelType.normal.value,
      'createdAt': now,
      'displayName': toName,
      'photoUrl': toPhotoUrl ?? '',
      if (toEmail != null) 'email': toEmail,
    });

    batch.set(_users.doc(toUid).collection('friends').doc(uid), {
      'status': FriendshipStatus.incoming.value,
      'relType': FriendRelType.normal.value,
      'createdAt': now,
      'displayName': myName,
      'photoUrl': myPhotoUrl ?? '',
      if (myEmail != null) 'email': myEmail,
    });

    await batch.commit();
  }

  /// 친구 요청 수락 (B가 A의 요청을 수락)
  static Future<void> acceptRequest(String fromUid) async {
    final uid = _myUid;
    if (uid == null) throw Exception('로그인이 필요합니다');

    final batch = _db.batch();
    final now = FieldValue.serverTimestamp();

    batch.update(_users.doc(uid).collection('friends').doc(fromUid), {
      'status': FriendshipStatus.accepted.value,
      'acceptedAt': now,
    });
    batch.update(_users.doc(fromUid).collection('friends').doc(uid), {
      'status': FriendshipStatus.accepted.value,
      'acceptedAt': now,
    });
    await batch.commit();
  }

  /// 요청 거절 또는 취소 또는 친구 삭제 — 양쪽 doc 모두 삭제
  static Future<void> removeFriendship(String otherUid) async {
    final uid = _myUid;
    if (uid == null) throw Exception('로그인이 필요합니다');

    final batch = _db.batch();
    batch.delete(_users.doc(uid).collection('friends').doc(otherUid));
    batch.delete(_users.doc(otherUid).collection('friends').doc(uid));
    await batch.commit();
  }

  /// 내 현재 위치 스냅샷 → 얼음 모드 진입 시 frozenLocation에 저장
  /// 브로드캐스터 우선순위: A가 B를 bad/ice로 설정하면 A의 현재 위치를 박제,
  /// B의 지도에서 A는 그 위치에 고정되어 표시됨
  static Future<Map<String, dynamic>?> _snapshotMyLocation() async {
    try {
      final uid = _myUid;
      if (uid == null) return null;
      // 좌표는 liveLocations 로 분리됨 (본인 doc — 규칙상 읽기 허용)
      final myDoc = await _db.collection('liveLocations').doc(uid).get();
      if (!myDoc.exists) return null;
      final liveLocation =
          myDoc.data()?['liveLocation'] as Map<String, dynamic>?;
      if (liveLocation == null) return null;
      return {
        'lat': liveLocation['lat'],
        'lng': liveLocation['lng'],
        'frozenAt': FieldValue.serverTimestamp(),
      };
    } catch (_) {
      return null;
    }
  }

  /// 관계 등급 변경 (그룹 — 단방향, 내 setting만)
  /// bad로 변경 시 친구 위치 스냅샷 → frozenLocation에 저장
  static Future<void> changeRelType(
      String friendUid, FriendRelType relType) async {
    final uid = _myUid;
    if (uid == null) return;
    try {
      final data = <String, dynamic>{'relType': relType.value};
      if (relType == FriendRelType.bad) {
        final snap = await _snapshotMyLocation();
        if (snap != null) data['frozenLocation'] = snap;
      }
      // bad → 다른 그룹으로 변경 시 (개별이 ice가 아니면) frozen 삭제
      // 보수적으로 유지 (다시 bad로 돌아갈 때 활용 가능)
      await _users
          .doc(uid)
          .collection('friends')
          .doc(friendUid)
          .update(data);
    } catch (e) {
      debugPrint('그룹 변경 실패: $e');
    }
  }

  /// 개별 오버라이드 변경 (단방향 — 내 setting만)
  /// ice로 변경 시 친구 위치 스냅샷 → frozenLocation에 저장
  static Future<void> changeIndividualMode(
      String friendUid, FriendIndividualMode mode) async {
    final uid = _myUid;
    if (uid == null) return;
    try {
      final data = <String, dynamic>{'individualMode': mode.value};
      if (mode == FriendIndividualMode.ice) {
        final snap = await _snapshotMyLocation();
        if (snap != null) data['frozenLocation'] = snap;
      }
      await _users
          .doc(uid)
          .collection('friends')
          .doc(friendUid)
          .update(data);
    } catch (e) {
      debugPrint('개별 모드 변경 실패: $e');
    }
  }

  /// 별명 설정 (내 setting만 변경)
  static Future<void> setNickname(String friendUid, String? nickname) async {
    final uid = _myUid;
    if (uid == null) return;
    try {
      await _users.doc(uid).collection('friends').doc(friendUid).update({
        'nicknameByMe': nickname ?? FieldValue.delete(),
      });
    } catch (e) {
      debugPrint('별명 설정 실패: $e');
    }
  }
}
