import 'package:cloud_firestore/cloud_firestore.dart';

/// vlog 또는 댓글에 추가되는 이모지 리액션
///
/// Firestore 경로:
///   vlogs/{vlogId}/reactions/{userId}_{emojiCode}
///
/// 한 사용자가 동일 vlog에 여러 이모지로 리액션 가능 (Slack 스타일).
class Reaction {
  /// docId = `{userId}_{emojiCode}` 형식
  final String id;
  final String userId;
  final String userName;
  final String? userPhotoUrl;
  final String emoji;
  final DateTime createdAt;

  const Reaction({
    required this.id,
    required this.userId,
    required this.userName,
    this.userPhotoUrl,
    required this.emoji,
    required this.createdAt,
  });

  factory Reaction.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return Reaction(
      id: doc.id,
      userId: d['userId'] as String? ?? '',
      userName: d['userName'] as String? ?? '익명',
      userPhotoUrl: d['userPhotoUrl'] as String?,
      emoji: d['emoji'] as String? ?? '👍',
      createdAt:
          (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() => {
        'userId': userId,
        'userName': userName,
        if (userPhotoUrl != null) 'userPhotoUrl': userPhotoUrl,
        'emoji': emoji,
        'createdAt': FieldValue.serverTimestamp(),
      };

  /// `userId_emoji` 형태의 docId 생성기 (이모지는 그대로 사용 — Firestore docId 허용 범위)
  static String makeId(String userId, String emoji) => '${userId}_$emoji';
}

/// 동일 이모지로 묶인 리액션 집계 — UI 표시용
class ReactionGroup {
  final String emoji;
  final List<Reaction> reactions;

  const ReactionGroup({required this.emoji, required this.reactions});

  int get count => reactions.length;
  bool didIReact(String? myUid) =>
      myUid != null && reactions.any((r) => r.userId == myUid);
}

/// Slack 스타일 리액션 팔레트 — 카테고리별로 묶어서 풍부하게
class ReactionCategory {
  final String label;
  final String hint;
  final List<String> emojis;
  const ReactionCategory(this.label, this.hint, this.emojis);
}

const List<ReactionCategory> kReactionCategories = [
  ReactionCategory('자주', '⭐', [
    '👍', '❤️', '😂', '😮', '🔥', '👏', '💯', '🎉',
  ]),
  ReactionCategory('감정', '😊', [
    '😀', '😍', '😘', '😎', '🤩', '🥰', '😇', '🤗',
    '🤔', '😅', '😭', '😡', '🥺', '😴', '🙄', '😬',
    '🤯', '🥳', '🤤', '😱',
  ]),
  ReactionCategory('손짓', '👋', [
    '👋', '🙌', '🤝', '👌', '🤞', '✌️', '🤟', '🙏',
    '💪', '🫶', '🫡', '🤘',
  ]),
  ReactionCategory('하트', '💖', [
    '❤️', '🧡', '💛', '💚', '💙', '💜', '🖤', '🤍',
    '💖', '💗', '💓', '💞', '💕', '❣️',
  ]),
  ReactionCategory('축하', '🎉', [
    '🎉', '🎊', '🎂', '🎁', '🎈', '🍾', '🥂', '🍻',
    '🏆', '🥇', '🎖️', '✨', '🌟', '⭐',
  ]),
  ReactionCategory('일상', '☕', [
    '☕', '🍵', '🍔', '🍕', '🍜', '🍣', '🍦', '🍪',
    '🍰', '🍻', '🚗', '✈️', '🌈', '🌸', '🌙', '☀️',
    '🎵', '📷', '📚', '⚽',
  ]),
  ReactionCategory('재미', '🤪', [
    '🤣', '😜', '🤪', '😝', '🤭', '😈', '👻', '👽',
    '🤖', '💩', '🎃', '🦄',
  ]),
];

/// 호환용 — 기존 코드가 단일 리스트로 참조하는 경우
const List<String> kQuickReactions = [
  '👍', '❤️', '😂', '😮', '🔥', '👏', '💯', '🎉',
];
