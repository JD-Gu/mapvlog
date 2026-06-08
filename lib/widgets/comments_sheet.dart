import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/comment.dart';
import '../models/friendship.dart';
import '../models/vlog.dart';
import '../services/firestore_service.dart';
import '../services/friend_service.dart';
import '../utils/constants.dart';
import '../utils/sheets.dart';
import 'likers_sheet.dart';

/// 인스타 스타일 댓글 시트 (드래그 가능 + 입력창 하단 고정).
/// vlogs/events 등 임의 컬렉션 문서에 재사용 — collection/docId/ownerId 기반.
class CommentsSheet extends StatelessWidget {
  final String collection; // 'vlogs' | 'events' ...
  final String docId;
  final String ownerId; // 등록자(삭제 권한) UID
  const CommentsSheet({
    super.key,
    required this.collection,
    required this.docId,
    required this.ownerId,
  });

  /// 브이로그 댓글 (기존 호환)
  static Future<void> open(BuildContext context, Vlog vlog) => _show(context,
      collection: 'vlogs', docId: vlog.id, ownerId: vlog.authorId);

  /// 임의 문서(이벤트 등) 댓글
  static Future<void> openFor(BuildContext context,
          {required String collection,
          required String docId,
          required String ownerId}) =>
      _show(context, collection: collection, docId: docId, ownerId: ownerId);

  static Future<void> _show(BuildContext context,
      {required String collection,
      required String docId,
      required String ownerId}) {
    HapticFeedback.selectionClick();
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => CommentsSheet(
          collection: collection, docId: docId, ownerId: ownerId),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (_, scrollCtrl) => _CommentsView(
        collection: collection,
        docId: docId,
        ownerId: ownerId,
        scrollCtrl: scrollCtrl,
      ),
    );
  }
}

class _CommentsView extends StatefulWidget {
  final String collection;
  final String docId;
  final String ownerId;
  final ScrollController scrollCtrl;
  const _CommentsView({
    required this.collection,
    required this.docId,
    required this.ownerId,
    required this.scrollCtrl,
  });

  @override
  State<_CommentsView> createState() => _CommentsViewState();
}

class _CommentsViewState extends State<_CommentsView> {
  final TextEditingController _inputCtrl = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool _sending = false;
  bool _newestFirst = false; // 기본: 오래된순 (인스타 스타일)

  // 답글 모드 상태
  Comment? _replyingTo;
  // 펼쳐진 부모 댓글 ID (답글 N개 보기 토글)
  final Set<String> _expandedParents = {};

  // ── 멘션 자동완성 ─────────────────────────────────────────────────────────
  List<Friendship> _friends = [];
  StreamSubscription<List<Friendship>>? _friendsSub;
  /// 현재 입력 중인 멘션 prefix (@ 직후의 부분 문자열) — null 이면 멘션 모드 아님
  String? _mentionQuery;
  /// 멘션 시작 위치 (@ 의 인덱스)
  int _mentionStart = -1;

  @override
  void initState() {
    super.initState();
    _friendsSub = FriendService.watchMyFriends().listen((list) {
      if (mounted) setState(() => _friends = list);
    });
    _inputCtrl.addListener(_onInputChanged);
  }

  @override
  void dispose() {
    _inputCtrl.removeListener(_onInputChanged);
    _friendsSub?.cancel();
    _inputCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  /// 입력 변경 감지 — 커서 직전의 마지막 @ 토큰을 멘션 prefix 로 인식
  void _onInputChanged() {
    final text = _inputCtrl.text;
    final sel = _inputCtrl.selection;
    if (!sel.isValid || sel.baseOffset != sel.extentOffset) {
      _clearMention();
      return;
    }
    final cursor = sel.baseOffset;
    if (cursor <= 0) {
      _clearMention();
      return;
    }
    // 커서로부터 역방향으로 공백/줄바꿈/시작 만날 때까지 스캔
    int i = cursor - 1;
    while (i >= 0) {
      final ch = text[i];
      if (ch == '@') {
        final query = text.substring(i + 1, cursor);
        // @ 직후에 공백/개행이 있으면 종료된 멘션
        if (query.contains(RegExp(r'\s'))) {
          _clearMention();
          return;
        }
        setState(() {
          _mentionQuery = query;
          _mentionStart = i;
        });
        return;
      }
      if (ch == ' ' || ch == '\n') break;
      i--;
    }
    _clearMention();
  }

  void _clearMention() {
    if (_mentionQuery != null) {
      setState(() {
        _mentionQuery = null;
        _mentionStart = -1;
      });
    }
  }

  List<Friendship> get _mentionSuggestions {
    if (_mentionQuery == null) return const [];
    final q = _mentionQuery!.toLowerCase();
    return _friends
        .where((f) => f.effectiveName.toLowerCase().contains(q))
        .take(5)
        .toList();
  }

  /// 선택된 친구 이름을 @이름 으로 입력창에 삽입
  void _insertMention(Friendship f) {
    HapticFeedback.selectionClick();
    final text = _inputCtrl.text;
    final cursor = _inputCtrl.selection.baseOffset;
    if (_mentionStart < 0 || cursor < _mentionStart) return;
    final before = text.substring(0, _mentionStart);
    final after = text.substring(cursor);
    // 공백이 이미 있으면 추가 공백 안 붙임
    final needsSpace = after.isEmpty || !after.startsWith(' ');
    final mention = '@${f.effectiveName}${needsSpace ? ' ' : ''}';
    final newText = '$before$mention$after';
    final newCursor = before.length + mention.length;
    _inputCtrl.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newCursor),
    );
    _clearMention();
  }

  void _startReply(Comment target) {
    HapticFeedback.selectionClick();
    setState(() {
      _replyingTo = target;
      // 답글이 펼쳐진 상태가 되도록 보장
      final parentId = target.parentId ?? target.id;
      _expandedParents.add(parentId);
      // 대화창 prefill — 빠른 멘션
      _inputCtrl.text = '@${target.authorName} ';
      _inputCtrl.selection = TextSelection.fromPosition(
          TextPosition(offset: _inputCtrl.text.length));
    });
    _focusNode.requestFocus();
  }

  void _cancelReply() {
    HapticFeedback.selectionClick();
    setState(() {
      _replyingTo = null;
      _inputCtrl.clear();
    });
  }

  void _toggleExpand(String parentId) {
    HapticFeedback.selectionClick();
    setState(() {
      if (_expandedParents.contains(parentId)) {
        _expandedParents.remove(parentId);
      } else {
        _expandedParents.add(parentId);
      }
    });
  }

  Future<void> _send() async {
    final user = FirebaseAuth.instance.currentUser;
    final text = _inputCtrl.text.trim();
    if (user == null || text.isEmpty || _sending) return;
    setState(() => _sending = true);
    HapticFeedback.selectionClick();
    // 답글 모드면 부모 ID 부착 (depth=1 평탄화 — 답글의 답글도 같은 부모 아래)
    final parentId = _replyingTo == null
        ? null
        : (_replyingTo!.parentId ?? _replyingTo!.id);
    try {
      await FirestoreService.addComment(
        vlogId: widget.docId,
        collection: widget.collection,
        authorId: user.uid,
        authorName: user.displayName ?? user.email ?? '익명',
        authorPhotoUrl: user.photoURL,
        content: text,
        parentId: parentId,
      );
      _inputCtrl.clear();
      if (mounted) setState(() => _replyingTo = null);
      // 답글이 아니면 새 댓글로 자동 스크롤
      if (parentId == null) {
        await Future.delayed(const Duration(milliseconds: 100));
        if (widget.scrollCtrl.hasClients) {
          widget.scrollCtrl.animateTo(
            widget.scrollCtrl.position.maxScrollExtent + 100,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('댓글 작성 실패: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  /// 최상위 + 답글 묶음 리스트로 변환
  /// 결과: [최상위1, 답글1-1, 답글1-2, 최상위2, ...]  단, 펼친 부모만 답글 노출
  List<_CommentRow> _buildRows(List<Comment> all) {
    final tops = all.where((c) => !c.isReply).toList();
    // 정렬 적용 — 최신순이면 새것 먼저, 아니면 오래된 먼저
    tops.sort((a, b) => _newestFirst
        ? b.createdAt.compareTo(a.createdAt)
        : a.createdAt.compareTo(b.createdAt));
    final repliesByParent = <String, List<Comment>>{};
    for (final c in all.where((c) => c.isReply)) {
      repliesByParent.putIfAbsent(c.parentId!, () => []).add(c);
    }
    // 답글은 항상 시간순 (오래된 → 새것) — 대화 흐름 유지
    for (final list in repliesByParent.values) {
      list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    }
    final rows = <_CommentRow>[];
    for (final top in tops) {
      rows.add(_CommentRow.top(top));
      final replies = repliesByParent[top.id] ?? const [];
      if (replies.isEmpty) continue;
      if (_expandedParents.contains(top.id)) {
        for (final r in replies) {
          rows.add(_CommentRow.reply(r));
        }
        rows.add(_CommentRow.collapse(top.id, replies.length));
      } else {
        rows.add(_CommentRow.expand(top.id, replies.length));
      }
    }
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      // 키보드 인셋 처리
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        children: [
          // 드래그 핸들
          const SizedBox(height: 10),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.textDisabled.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 12, 10),
            child: Row(
              children: [
                const Text(
                  '댓글',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                                      ),
                ),
                const Spacer(),
                // 정렬 토글
                InkWell(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _newestFirst = !_newestFirst);
                  },
                  borderRadius: BorderRadius.circular(AppRadius.full),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    child: Row(
                      children: [
                        Icon(
                          _newestFirst
                              ? Icons.arrow_downward
                              : Icons.arrow_upward,
                          size: 13,
                          color: AppColors.textSecondary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _newestFirst ? '최신순' : '오래된순',
                          style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // 댓글 리스트
          Expanded(
            child: StreamBuilder<List<Comment>>(
              stream: FirestoreService.watchComments(widget.docId,
                  collection: widget.collection),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(
                      child: CircularProgressIndicator(
                          color: AppColors.primary));
                }
                final comments = snap.data ?? [];
                if (comments.isEmpty) {
                  return const _EmptyComments();
                }
                final rows = _buildRows(comments);
                return ListView.builder(
                  controller: widget.scrollCtrl,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: rows.length,
                  itemBuilder: (_, i) {
                    final row = rows[i];
                    switch (row.kind) {
                      case _RowKind.top:
                      case _RowKind.reply:
                        return _CommentTile(
                          comment: row.comment!,
                          collection: widget.collection,
                          docId: widget.docId,
                          ownerId: widget.ownerId,
                          myUid: myUid,
                          isReply: row.kind == _RowKind.reply,
                          onReply: myUid == null
                              ? null
                              : () => _startReply(row.comment!),
                        );
                      case _RowKind.expand:
                        return _ReplyToggle(
                          parentId: row.parentId!,
                          replyCount: row.replyCount!,
                          expanded: false,
                          onTap: () => _toggleExpand(row.parentId!),
                        );
                      case _RowKind.collapse:
                        return _ReplyToggle(
                          parentId: row.parentId!,
                          replyCount: row.replyCount!,
                          expanded: true,
                          onTap: () => _toggleExpand(row.parentId!),
                        );
                    }
                  },
                );
              },
            ),
          ),
          // 답글 모드 인디케이터
          if (_replyingTo != null)
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 8),
              color: AppColors.primary.withValues(alpha: 0.08),
              child: Row(
                children: [
                  const Icon(Icons.reply,
                      size: 14, color: AppColors.primary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '${_replyingTo!.authorName}님에게 답글 다는 중',
                      style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                  InkWell(
                    onTap: _cancelReply,
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(Icons.close,
                          size: 16, color: AppColors.primary),
                    ),
                  ),
                ],
              ),
            ),
          const Divider(height: 1),
          // 멘션 자동완성 추천 (입력창 바로 위)
          if (_mentionSuggestions.isNotEmpty)
            _MentionSuggestionsBar(
              suggestions: _mentionSuggestions,
              query: _mentionQuery ?? '',
              onTap: _insertMention,
            ),
          // 입력창
          _InputBar(
            controller: _inputCtrl,
            focusNode: _focusNode,
            sending: _sending,
            onSend: _send,
            canPost: myUid != null,
            hintOverride:
                _replyingTo != null ? '답글 달기...' : null,
          ),
        ],
      ),
    );
  }
}

// ─── 리스트 행 구조 ───────────────────────────────────────────────────────
enum _RowKind { top, reply, expand, collapse }

class _CommentRow {
  final _RowKind kind;
  final Comment? comment;
  final String? parentId;
  final int? replyCount;
  const _CommentRow._(
      {required this.kind, this.comment, this.parentId, this.replyCount});

  factory _CommentRow.top(Comment c) =>
      _CommentRow._(kind: _RowKind.top, comment: c);
  factory _CommentRow.reply(Comment c) =>
      _CommentRow._(kind: _RowKind.reply, comment: c);
  factory _CommentRow.expand(String parentId, int count) => _CommentRow._(
      kind: _RowKind.expand, parentId: parentId, replyCount: count);
  factory _CommentRow.collapse(String parentId, int count) => _CommentRow._(
      kind: _RowKind.collapse, parentId: parentId, replyCount: count);
}

// ─── 답글 펼치기 토글 행 ──────────────────────────────────────────────────
class _ReplyToggle extends StatelessWidget {
  final String parentId;
  final int replyCount;
  final bool expanded;
  final VoidCallback onTap;
  const _ReplyToggle({
    required this.parentId,
    required this.replyCount,
    required this.expanded,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(60, 4, 16, 10),
        child: Row(
          children: [
            Container(
              width: 24,
              height: 1,
              color: AppColors.textDisabled,
            ),
            const SizedBox(width: 8),
            Text(
              expanded ? '답글 숨기기' : '답글 $replyCount개 보기',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
              size: 14,
              color: AppColors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── 댓글 한 줄 ─────────────────────────────────────────────────────────────

class _CommentTile extends StatefulWidget {
  final Comment comment;
  final String collection;
  final String docId;
  final String ownerId;
  final String? myUid;
  final bool isReply;
  final VoidCallback? onReply;
  const _CommentTile({
    required this.comment,
    required this.collection,
    required this.docId,
    required this.ownerId,
    required this.myUid,
    this.isReply = false,
    this.onReply,
  });

  @override
  State<_CommentTile> createState() => _CommentTileState();
}

class _CommentTileState extends State<_CommentTile> {
  bool _liked = false;
  bool _likeChecked = false;
  bool _likeBusy = false;
  late int _likeCount;

  @override
  void initState() {
    super.initState();
    _likeCount = widget.comment.likeCount;
    _checkInitialLike();
  }

  @override
  void didUpdateWidget(covariant _CommentTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Stream에서 likeCount 갱신 시 반영 (단, 토글 중이면 옵티미스틱 값 유지)
    if (!_likeBusy &&
        oldWidget.comment.likeCount != widget.comment.likeCount) {
      _likeCount = widget.comment.likeCount;
    }
  }

  Future<void> _checkInitialLike() async {
    if (widget.myUid == null) {
      setState(() => _likeChecked = true);
      return;
    }
    try {
      final liked = await FirestoreService.isCommentLikedByMe(
        vlogId: widget.docId,
        collection: widget.collection,
        commentId: widget.comment.id,
        userId: widget.myUid!,
      );
      if (!mounted) return;
      setState(() {
        _liked = liked;
        _likeChecked = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _likeChecked = true);
    }
  }

  Future<void> _toggleLike() async {
    if (widget.myUid == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('좋아요는 로그인 후 가능해요'),
        duration: Duration(seconds: 2),
      ));
      return;
    }
    if (_likeBusy) return;
    HapticFeedback.lightImpact();
    final prev = _liked;
    setState(() {
      _liked = !prev;
      _likeCount += prev ? -1 : 1;
      _likeBusy = true;
    });
    try {
      await FirestoreService.toggleCommentLike(
        vlogId: widget.docId,
        collection: widget.collection,
        commentId: widget.comment.id,
        userId: widget.myUid!,
      );
      if (mounted) setState(() => _likeBusy = false);
    } catch (e) {
      // 롤백
      if (!mounted) return;
      setState(() {
        _liked = prev;
        _likeCount += prev ? 1 : -1;
        _likeBusy = false;
      });
    }
  }

  bool get _canDelete =>
      widget.myUid != null &&
      (widget.myUid == widget.comment.authorId ||
          widget.myUid == widget.ownerId);

  /// 본문에서 @로 시작하는 토큰을 컬러 span으로 분리
  /// 예: "안녕 @방랑자 잘 지내?" → ["안녕 ", "@방랑자", " 잘 지내?"]
  List<InlineSpan> _buildMentionSpans(String text) {
    if (!text.contains('@')) return [TextSpan(text: text)];
    final spans = <InlineSpan>[];
    final re = RegExp(r'@[\w가-힣]+');
    int last = 0;
    for (final m in re.allMatches(text)) {
      if (m.start > last) {
        spans.add(TextSpan(text: text.substring(last, m.start)));
      }
      spans.add(TextSpan(
        text: m.group(0),
        style: const TextStyle(
          color: AppColors.primary,
          fontWeight: FontWeight.w700,
        ),
      ));
      last = m.end;
    }
    if (last < text.length) {
      spans.add(TextSpan(text: text.substring(last)));
    }
    return spans;
  }

  String _relativeTime() {
    final diff = DateTime.now().difference(widget.comment.createdAt);
    if (diff.inSeconds < 60) return '방금';
    if (diff.inMinutes < 60) return '${diff.inMinutes}분';
    if (diff.inHours < 24) return '${diff.inHours}시간';
    if (diff.inDays < 7) return '${diff.inDays}일';
    final d = widget.comment.createdAt;
    return '${d.month}/${d.day}';
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final ok = await AppSheets.confirm(
      context,
      icon: Icons.delete_outline,
      title: '댓글 삭제',
      message: '이 댓글을 삭제할까요?',
      confirmLabel: '삭제',
      dangerous: true,
    );
    if (ok != true) return;
    try {
      await FirestoreService.deleteComment(widget.docId, widget.comment.id,
          collection: widget.collection);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('삭제 실패: $e'),
          backgroundColor: AppColors.error,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.comment;
    final hasPhoto = c.authorPhotoUrl != null && c.authorPhotoUrl!.isNotEmpty;
    final letter =
        (c.authorName.isNotEmpty ? c.authorName[0] : '?').toUpperCase();
    const palette = [
      Color(0xFF1A73E8),
      Color(0xFF34A853),
      Color(0xFFFF6B6B),
      Color(0xFF7C4DFF),
      Color(0xFFFFA726),
      Color(0xFF00ACC1),
      Color(0xFFEC407A),
    ];
    final color = palette[c.authorName.hashCode.abs() % palette.length];

    final isReply = widget.isReply;
    final avatarSize = isReply ? 26.0 : 34.0;
    final fontSize = isReply ? 12.5 : 13.0;
    // 답글은 왼쪽 들여쓰기 (인스타 스타일)
    final leftPad = isReply ? 60.0 : 16.0;

    return Padding(
      padding: EdgeInsets.fromLTRB(leftPad, isReply ? 6 : 10, 8, isReply ? 6 : 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 아바타
          Container(
            width: avatarSize,
            height: avatarSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.2),
              image: hasPhoto
                  ? DecorationImage(
                      image: NetworkImage(c.authorPhotoUrl!),
                      fit: BoxFit.cover)
                  : null,
            ),
            alignment: Alignment.center,
            child: hasPhoto
                ? null
                : Text(
                    letter,
                    style: TextStyle(
                      fontSize: isReply ? 11 : 14,
                      fontWeight: FontWeight.w800,
                      color: color,
                    ),
                  ),
          ),
          const SizedBox(width: 10),
          // 본문 (이름 + 내용 + 시간 + 좋아요 메타 + 답글)
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                RichText(
                  text: TextSpan(
                    style: TextStyle(
                      fontSize: fontSize,
                      height: 1.4,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                    children: [
                      TextSpan(
                        text: c.authorName,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const TextSpan(text: '  '),
                      ..._buildMentionSpans(c.content),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      _relativeTime(),
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textDisabled,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (_likeCount > 0) ...[
                      const SizedBox(width: 12),
                      InkWell(
                        onTap: () => LikersSheet.open(
                          context: context,
                          title: '좋아요 $_likeCount명',
                          stream:
                              FirestoreService.watchCommentLikers(
                                  widget.docId, widget.comment.id,
                                  collection: widget.collection),
                        ),
                        child: Text(
                          '좋아요 $_likeCount개',
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                    if (widget.onReply != null) ...[
                      const SizedBox(width: 12),
                      InkWell(
                        onTap: widget.onReply,
                        child: const Text(
                          '답글 달기',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                    if (_canDelete) ...[
                      const SizedBox(width: 12),
                      InkWell(
                        onTap: () => _confirmDelete(context),
                        child: const Text(
                          '삭제',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          // 좋아요 ♥ (인스타 스타일 — 우측 컬럼)
          GestureDetector(
            onTap: _toggleLike,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              child: AnimatedScale(
                scale: _liked ? 1.0 : 0.95,
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutBack,
                child: Icon(
                  _liked ? Icons.favorite : Icons.favorite_border,
                  size: 16,
                  color: _liked
                      ? AppColors.error
                      : (_likeChecked
                          ? AppColors.textSecondary
                          : AppColors.textDisabled),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── 멘션 자동완성 추천 바 ─────────────────────────────────────────────────

class _MentionSuggestionsBar extends StatelessWidget {
  final List<Friendship> suggestions;
  final String query;
  final ValueChanged<Friendship> onTap;
  const _MentionSuggestionsBar({
    required this.suggestions,
    required this.query,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(maxHeight: 220),
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(
          bottom: BorderSide(color: cs.outlineVariant, width: 1),
        ),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemCount: suggestions.length,
        separatorBuilder: (_, __) => const SizedBox(height: 0),
        itemBuilder: (_, i) {
          final f = suggestions[i];
          final photo = f.photoUrl;
          return InkWell(
            onTap: () => onTap(f),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 8),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: cs.surfaceContainerHighest,
                    backgroundImage:
                        (photo != null && photo.isNotEmpty)
                            ? NetworkImage(photo)
                            : null,
                    child: (photo == null || photo.isEmpty)
                        ? Text(
                            f.effectiveName.isNotEmpty
                                ? f.effectiveName[0].toUpperCase()
                                : '?',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: cs.onSurface,
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '@${f.effectiveName}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface,
                      ),
                    ),
                  ),
                  Icon(Icons.alternate_email,
                      size: 14, color: cs.primary),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ─── 입력창 ─────────────────────────────────────────────────────────────────

class _InputBar extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool sending;
  final bool canPost;
  final VoidCallback onSend;
  final String? hintOverride;
  const _InputBar({
    required this.controller,
    required this.focusNode,
    required this.sending,
    required this.canPost,
    required this.onSend,
    this.hintOverride,
  });

  @override
  Widget build(BuildContext context) {
    if (!canPost) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        color: Theme.of(context).colorScheme.surface,
        child: const Center(
          child: Text(
            '댓글을 쓰려면 로그인이 필요합니다',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
        ),
      );
    }
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => onSend(),
                minLines: 1,
                maxLines: 4,
                decoration: InputDecoration(
                  hintText: hintOverride ?? '댓글 달기...',
                  hintStyle: const TextStyle(
                      fontSize: 13, color: AppColors.textSecondary),
                  filled: true,
                  fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(AppRadius.full),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            sending
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.primary),
                    ),
                  )
                : IconButton(
                    icon: const Icon(Icons.send_rounded,
                        color: AppColors.primary, size: 24),
                    tooltip: '게시',
                    onPressed: onSend,
                  ),
          ],
        ),
      ),
    );
  }
}

class _EmptyComments extends StatelessWidget {
  const _EmptyComments();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primary.withValues(alpha: 0.08),
              ),
              child: const Icon(Icons.chat_bubble_outline,
                  size: 38, color: AppColors.primary),
            ),
            const SizedBox(height: 14),
            const Text(
              '아직 댓글이 없어요',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                              ),
            ),
            const SizedBox(height: 4),
            const Text(
              '첫 댓글의 주인공이 되어보세요',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
