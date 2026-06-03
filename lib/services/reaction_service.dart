import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/reaction.dart';

/// vlog 이모지 리액션 CRUD + 실시간 스트림
class ReactionService {
  static final _db = FirebaseFirestore.instance;

  static CollectionReference<Map<String, dynamic>> _col(String vlogId) =>
      _db.collection('vlogs').doc(vlogId).collection('reactions');

  /// 내가 해당 vlog에 [emoji] 로 리액션을 토글한다.
  /// 이미 같은 이모지로 리액션돼 있으면 제거, 없으면 추가.
  static Future<void> toggle({
    required String vlogId,
    required String emoji,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('로그인이 필요합니다');
    final docId = Reaction.makeId(user.uid, emoji);
    final ref = _col(vlogId).doc(docId);
    final snap = await ref.get();
    if (snap.exists) {
      await ref.delete();
      return;
    }
    await ref.set({
      'userId': user.uid,
      'userName': user.displayName ?? user.email ?? '사용자',
      if (user.photoURL != null) 'userPhotoUrl': user.photoURL,
      'emoji': emoji,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// 실시간 리액션 스트림 (이모지별로 그룹핑된 리스트 반환)
  static Stream<List<ReactionGroup>> watchGroups(String vlogId) {
    return _col(vlogId).snapshots().map((s) {
      final reactions =
          s.docs.map(Reaction.fromDoc).toList(growable: false);
      final byEmoji = <String, List<Reaction>>{};
      for (final r in reactions) {
        byEmoji.putIfAbsent(r.emoji, () => []).add(r);
      }
      final groups = byEmoji.entries
          .map((e) => ReactionGroup(emoji: e.key, reactions: e.value))
          .toList();
      // 가장 많이 받은 이모지부터 표시
      groups.sort((a, b) => b.count.compareTo(a.count));
      return groups;
    });
  }
}
