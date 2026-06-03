import 'package:cloud_firestore/cloud_firestore.dart';

/// 브이로그 댓글
class Comment {
  final String id;
  final String authorId;
  final String authorName;
  final String? authorPhotoUrl;
  final String content;
  final DateTime createdAt;
  final int likeCount;
  final String? parentId; // null = 최상위 댓글, 있으면 해당 부모 댓글의 답글

  const Comment({
    required this.id,
    required this.authorId,
    required this.authorName,
    this.authorPhotoUrl,
    required this.content,
    required this.createdAt,
    this.likeCount = 0,
    this.parentId,
  });

  bool get isReply => parentId != null;

  factory Comment.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    final pid = d['parentId'] as String?;
    return Comment(
      id: doc.id,
      authorId: d['authorId'] as String? ?? '',
      authorName: d['authorName'] as String? ?? '익명',
      authorPhotoUrl: d['authorPhotoUrl'] as String?,
      content: d['content'] as String? ?? '',
      createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      likeCount: (d['likeCount'] as num?)?.toInt() ?? 0,
      parentId: (pid == null || pid.isEmpty) ? null : pid,
    );
  }
}
