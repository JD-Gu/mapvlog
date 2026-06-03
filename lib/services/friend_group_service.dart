import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/friend_group.dart';

/// 친구 그룹(친구그루핑정책.md) CRUD + 멤버 관리
///
/// 모든 그룹은 본인이 소유 — `users/{myUid}/friendGroups/{groupId}`
class FriendGroupService {
  static String? get _myUid => FirebaseAuth.instance.currentUser?.uid;
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static CollectionReference<Map<String, dynamic>> _col(String uid) =>
      _db.collection('users').doc(uid).collection('friendGroups');

  // ─── CRUD ─────────────────────────────────────────────────────────────────

  static Stream<List<FriendGroup>> watchMyGroups() {
    final uid = _myUid;
    if (uid == null) return const Stream.empty();
    return _col(uid)
        .orderBy('createdAt', descending: false)
        .snapshots()
        .map((s) => s.docs.map(FriendGroup.fromDoc).toList());
  }

  static Future<List<FriendGroup>> getMyGroupsOnce() async {
    final uid = _myUid;
    if (uid == null) return [];
    final snap = await _col(uid).orderBy('createdAt').get();
    return snap.docs.map(FriendGroup.fromDoc).toList();
  }

  static Future<String> createGroup({
    required String name,
    required String emoji,
    required GroupMode mode,
    List<String> memberUids = const [],
  }) async {
    final uid = _myUid;
    if (uid == null) throw Exception('로그인이 필요합니다');
    final ref = _col(uid).doc();
    await ref.set({
      'name': name,
      'emoji': emoji,
      'mode': mode.value,
      'memberUids': memberUids,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  static Future<void> updateGroup({
    required String groupId,
    String? name,
    String? emoji,
    GroupMode? mode,
  }) async {
    final uid = _myUid;
    if (uid == null) return;
    final data = <String, dynamic>{};
    if (name != null) data['name'] = name;
    if (emoji != null) data['emoji'] = emoji;
    if (mode != null) data['mode'] = mode.value;
    if (data.isEmpty) return;
    await _col(uid).doc(groupId).update(data);
  }

  static Future<void> deleteGroup(String groupId) async {
    final uid = _myUid;
    if (uid == null) return;
    await _col(uid).doc(groupId).delete();
  }

  // ─── 멤버 관리 ───────────────────────────────────────────────────────────

  /// 그룹의 멤버 전체 교체 (multi-select sheet에서 호출)
  static Future<void> setGroupMembers({
    required String groupId,
    required List<String> memberUids,
  }) async {
    final uid = _myUid;
    if (uid == null) return;
    await _col(uid).doc(groupId).update({'memberUids': memberUids});
  }

  /// 친구 한 명 추가
  static Future<void> addMember({
    required String groupId,
    required String friendUid,
  }) async {
    final uid = _myUid;
    if (uid == null) return;
    await _col(uid).doc(groupId).update({
      'memberUids': FieldValue.arrayUnion([friendUid]),
    });
  }

  /// 친구 한 명 제거
  static Future<void> removeMember({
    required String groupId,
    required String friendUid,
  }) async {
    final uid = _myUid;
    if (uid == null) return;
    await _col(uid).doc(groupId).update({
      'memberUids': FieldValue.arrayRemove([friendUid]),
    });
  }

  // ─── 친구별 그룹 조회 (M:N 역참조) ────────────────────────────────────────

  /// 특정 친구가 속한 모든 그룹 (반환은 그룹 객체 리스트)
  static Future<List<FriendGroup>> getGroupsForFriend(
      String friendUid) async {
    final all = await getMyGroupsOnce();
    return all.where((g) => g.memberUids.contains(friendUid)).toList();
  }

  /// 친구의 effectiveMode 계산 — 그룹들 중 "가장 관대한" 모드 반환
  /// 인싸 > 부끄럼 > 불편 (인싸가 있으면 인싸)
  /// 그룹 없으면 null (호출자가 기존 relType/individualMode fallback)
  static GroupMode? resolveGroupMode(List<FriendGroup> groups) {
    if (groups.isEmpty) return null;
    if (groups.any((g) => g.mode == GroupMode.insider)) {
      return GroupMode.insider;
    }
    if (groups.any((g) => g.mode == GroupMode.shy)) {
      return GroupMode.shy;
    }
    return GroupMode.uneasy;
  }

  /// allGroups 전체에서 friendUid가 속한 그룹들을 필터링한 뒤 [resolveGroupMode] 적용
  static GroupMode? modeForFriend(
      List<FriendGroup> allGroups, String friendUid) {
    final inGroups =
        allGroups.where((g) => g.memberUids.contains(friendUid)).toList();
    return resolveGroupMode(inGroups);
  }
}
