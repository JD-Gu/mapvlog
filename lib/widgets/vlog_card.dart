import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart' show PointerDeviceKind, PointerScrollEvent;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../models/vlog.dart';
import '../screens/users/user_profile_screen.dart';
import '../services/firestore_service.dart';
import '../utils/constants.dart';
import '../utils/location_format.dart';
import '../utils/marker_colors.dart';
import '../models/comment.dart';
import 'comments_sheet.dart';
import 'reaction_bar.dart';

/// 인스타그램·유튜브 스타일 vlog 카드
///
/// - 1열(`singleColumn=true`) : 인스타 포스트 스타일 (헤더→미디어→액션→캡션)
/// - 2열(`singleColumn=false`): 컴팩트 그리드 카드 (미디어 위주, 캡션 오버레이)
///
/// 공통 인터랙션:
///   • 더블탭 → 좋아요 (♥ 버스트 애니메이션)
///   • 좋아요 토글 (낙관적 업데이트 + 햅틱)
///   • 공유 (share_plus)
///   • 길게 누르기 → onLongPress 콜백 (등록자 메뉴)
class VlogCard extends StatefulWidget {
  final Vlog vlog;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool singleColumn;
  /// 현재 위치 — 주소 옆에 거리 표시 (null이면 거리 숨김)
  final Position? currentPosition;

  const VlogCard({
    super.key,
    required this.vlog,
    this.onTap,
    this.onLongPress,
    this.singleColumn = false,
    this.currentPosition,
  });

  @override
  State<VlogCard> createState() => _VlogCardState();
}

class _VlogCardState extends State<VlogCard> with TickerProviderStateMixin {
  bool _isLiked = false;
  bool _isSaved = false;
  bool _saveBusy = false;
  late int _likeCount;
  bool _showHeartBurst = false;
  late final AnimationController _burstCtrl;

  // ── 멀티 사진 캐러셀 ──────────────────────────────────────────────────────
  PageController? _photoPageController;
  int _photoPageIndex = 0;
  DateTime? _lastWheelTime;

  @override
  void initState() {
    super.initState();
    _likeCount = widget.vlog.likeCount;
    _burstCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    if (widget.vlog.photoUrls.length > 1) {
      _photoPageController = PageController();
    }
    _checkLiked();
  }

  @override
  void didUpdateWidget(VlogCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Firestore 스트림이 갱신되면 vlog 인스턴스가 새로 생성되므로
    // identity 체크 — 같은 ID라도 다른 인스턴스면 좋아요 상태 재확인
    if (oldWidget.vlog.likeCount != widget.vlog.likeCount) {
      _likeCount = widget.vlog.likeCount;
    }
    if (!identical(oldWidget.vlog, widget.vlog)) {
      _checkLiked();
    }
  }

  @override
  void dispose() {
    _burstCtrl.dispose();
    _photoPageController?.dispose();
    super.dispose();
  }

  /// 마우스 휠로 사진 페이지 이동 (350ms 디바운스)
  void _handlePhotoWheel(PointerScrollEvent event) {
    final ctrl = _photoPageController;
    final urls = widget.vlog.photoUrls;
    if (ctrl == null || urls.length <= 1) return;
    final now = DateTime.now();
    if (_lastWheelTime != null &&
        now.difference(_lastWheelTime!).inMilliseconds < 350) {
      return;
    }
    _lastWheelTime = now;
    final delta = event.scrollDelta.dy + event.scrollDelta.dx;
    if (delta > 0 && _photoPageIndex < urls.length - 1) {
      ctrl.nextPage(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOut,
      );
    } else if (delta < 0 && _photoPageIndex > 0) {
      ctrl.previousPage(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _checkLiked() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final liked = await FirestoreService.isLiked(widget.vlog.id, uid);
      if (mounted) setState(() => _isLiked = liked);
    } catch (_) {}
    try {
      final saved = await FirestoreService.isSaved(widget.vlog.id, uid);
      if (mounted) setState(() => _isSaved = saved);
    } catch (_) {}
  }

  Future<void> _toggleSave() async {
    if (_saveBusy) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('로그인이 필요합니다'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    HapticFeedback.selectionClick();
    setState(() {
      _isSaved = !_isSaved;
      _saveBusy = true;
    });
    try {
      await FirestoreService.toggleSave(widget.vlog.id, uid);
      if (mounted && _isSaved) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🔖 저장했어요'),
            duration: Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _isSaved = !_isSaved); // rollback
    } finally {
      if (mounted) setState(() => _saveBusy = false);
    }
  }

  Future<void> _toggleLike() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('로그인이 필요합니다'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    HapticFeedback.lightImpact();
    final wasLiked = _isLiked;
    setState(() {
      _isLiked = !wasLiked;
      _likeCount += wasLiked ? -1 : 1;
    });
    try {
      await FirestoreService.toggleLike(widget.vlog.id, uid);
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLiked = wasLiked;
          _likeCount += wasLiked ? 1 : -1;
        });
      }
    }
  }

  Future<void> _onDoubleTap() async {
    if (!_isLiked) {
      await _toggleLike();
    } else {
      HapticFeedback.lightImpact();
    }
    setState(() => _showHeartBurst = true);
    _burstCtrl.forward(from: 0);
    Future.delayed(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _showHeartBurst = false);
    });
  }

  Future<void> _share() async {
    HapticFeedback.selectionClick();
    const baseUrl = 'https://pinflick.web.app';
    final url = '$baseUrl/#/vlog/${widget.vlog.id}';
    final v = widget.vlog;
    final title = v.title.isNotEmpty ? v.title : v.placeName;
    final text =
        '📍 $title\n🗺️ ${v.placeName}\n\nPinFlick에서 확인하기 👇\n$url';
    try {
      if (kIsWeb) {
        await Clipboard.setData(ClipboardData(text: url));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Row(
                children: [
                  Icon(Icons.link, color: Colors.white, size: 16),
                  SizedBox(width: 8),
                  Text('링크가 복사됐습니다'),
                ],
              ),
              backgroundColor: AppColors.secondary,
              duration: Duration(seconds: 2),
            ),
          );
        }
      } else {
        await Share.share(text, subject: title);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    // 체크인은 미디어 없이 1줄 컴팩트 카드로 표시
    if (widget.vlog.isCheckIn) return _buildCheckInCard();
    return widget.singleColumn ? _buildPost() : _buildGridCard();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 체크인 컴팩트 카드 (미디어 없음, 한 줄)
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildCheckInCard() {
    final v = widget.vlog;
    final emoji = v.markerEmoji ?? '📍';
    final color = MarkerColors.fromValue(v.markerColor);

    return GestureDetector(
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: Container(
        margin: const EdgeInsets.symmetric(
            horizontal: 2, vertical: 4),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          boxShadow: AppShadow.card,
          border: Border.all(
              color: color.withValues(alpha: 0.25), width: 1.2),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // 큰 이모지 (마커 색상 링)
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                shape: BoxShape.circle,
                border: Border.all(
                    color: color.withValues(alpha: 0.6), width: 1.5),
              ),
              alignment: Alignment.center,
              child: Text(emoji, style: const TextStyle(fontSize: 22)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 헤더: [이름] [체크인 배지] [공개범위] ·· [시간]
                  // 일반 카드와 동일한 [이름 → 위치 → 시간] 구조로 통일
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          v.authorName,
                          style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.2),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          '체크인',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 8.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.4),
                        ),
                      ),
                      if (v.visibility != VlogVisibility.public) ...[
                        const SizedBox(width: 5),
                        _VisibilityBadge(visibility: v.visibility),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  // 메시지(제목) — 이모지는 좌측 원에 이미 있으므로 텍스트만
                  Text(
                    v.title.isEmpty ? v.placeName : v.title,
                    style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        height: 1.3),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  // 위치(장소명+주소) · 거리 · 시간
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Row(
                      children: [
                        const Icon(Icons.place,
                            size: 11, color: AppColors.textDisabled),
                        const SizedBox(width: 2),
                        Flexible(
                          child: Text(
                            combinedLocation(v.placeName, v.address),
                            style: const TextStyle(
                                fontSize: 11,
                                height: 1.3,
                                color: AppColors.textSecondary),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        // 거리 — 주소 옆에 항상 노출
                        if (_distanceChip() != null) ...[
                          const SizedBox(width: 5),
                          _distanceChip()!,
                        ],
                        const SizedBox(width: 5),
                        Text(
                          _relativeTime(v.createdAt),
                          style: const TextStyle(
                              fontSize: 11, color: AppColors.textDisabled),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
            // ── 좋아요/댓글 액션 행 ───────────────────────────────────
            const SizedBox(height: 6),
            Container(
              height: 1,
              color: color.withValues(alpha: 0.1),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                _CheckInActionBtn(
                  icon: _isLiked
                      ? Icons.favorite
                      : Icons.favorite_outline,
                  iconColor: _isLiked
                      ? AppColors.error
                      : Theme.of(context).colorScheme.onSurface,
                  count: _likeCount,
                  onTap: _toggleLike,
                ),
                const SizedBox(width: 4),
                _CheckInActionBtn(
                  icon: Icons.mode_comment_outlined,
                  iconColor:
                      Theme.of(context).colorScheme.onSurface,
                  count: v.commentCount,
                  onTap: () => CommentsSheet.open(context, v),
                ),
              ],
            ),
            // 이모지 리액션 바
            const SizedBox(height: 4),
            ReactionBar(vlog: v, compact: true),
            // 최신 댓글 1개 미리보기
            if (v.commentCount > 0) ...[
              const SizedBox(height: 4),
              _LatestCommentPreview(vlog: v),
            ],
          ],
        ),
      ),
    );
  }

  String _relativeTime(DateTime d) {
    final diff = DateTime.now().difference(d);
    if (diff.inSeconds < 60) return '방금';
    if (diff.inMinutes < 60) return '${diff.inMinutes}분 전';
    if (diff.inHours < 24) return '${diff.inHours}시간 전';
    if (diff.inDays < 7) return '${diff.inDays}일 전';
    return '${d.month}/${d.day}';
  }

  /// 장소명 + 주소 결합 — utils/location_format.dart 로 위임 (하위 호환)
  static String combinedLocation(String placeName, String? address) =>
      combinedLocationLabel(placeName, address);

  // ═══════════════════════════════════════════════════════════════════════════
  // 1열 (인스타 포스트 스타일)
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildPost() {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: AppShadow.card,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildPostHeader(),
          _buildMedia(aspectRatio: 4 / 3),
          _buildActionsBar(),
          _buildCaption(),
        ],
      ),
    );
  }

  Widget _buildPostHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 4, 10),
      child: Row(
        children: [
          GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => UserProfileScreen(
                    uid: widget.vlog.authorId,
                    name: widget.vlog.authorName,
                    photoUrl: widget.vlog.authorPhotoUrl,
                  ),
                ),
              );
            },
            child: _AuthorAvatar(
              name: widget.vlog.authorName,
              photoUrl: widget.vlog.authorPhotoUrl,
              size: 34,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        widget.vlog.authorName,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.2,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (widget.vlog.visibility != VlogVisibility.public) ...[
                      const SizedBox(width: 5),
                      _VisibilityBadge(visibility: widget.vlog.visibility),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 1.5),
                      child: (widget.vlog.markerEmoji != null &&
                              widget.vlog.markerEmoji!.isNotEmpty)
                          ? Text(
                              widget.vlog.markerEmoji!,
                              style:
                                  const TextStyle(fontSize: 11.5, height: 1.0),
                            )
                          : Icon(
                              Icons.location_on,
                              size: 10.5,
                              color: MarkerColors.fromValue(
                                  widget.vlog.markerColor),
                            ),
                    ),
                    const SizedBox(width: 3),
                    // 장소명 + 주소 결합 (직관적 위치 정보)
                    Expanded(
                      child: Text(
                        combinedLocation(
                            widget.vlog.placeName, widget.vlog.address),
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w500,
                          height: 1.3,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    // 거리 — 주소 옆에 항상 노출 (정렬과 무관)
                    if (_distanceChip() != null) ...[
                      const SizedBox(width: 6),
                      Padding(
                        padding: const EdgeInsets.only(top: 1.5),
                        child: _distanceChip()!,
                      ),
                    ],
                    Padding(
                      padding: const EdgeInsets.only(left: 6, top: 1.5),
                      child: Text(
                        _relativeDate(widget.vlog.createdAt),
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textDisabled,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (widget.onLongPress != null)
            IconButton(
              icon: const Icon(Icons.more_horiz,
                  size: 20, color: AppColors.textSecondary),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(
                  minWidth: 36, minHeight: 36),
              onPressed: () {
                HapticFeedback.selectionClick();
                widget.onLongPress?.call();
              },
            ),
        ],
      ),
    );
  }

  Widget _buildActionsBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 4, 14, 0),
      child: Row(
        children: [
          _ActionIconButton(
            icon: _isLiked ? Icons.favorite : Icons.favorite_outline,
            color: _isLiked
                ? AppColors.error
                : Theme.of(context).colorScheme.onSurface,
            onTap: _toggleLike,
          ),
          const SizedBox(width: 2),
          // 댓글 아이콘 + 카운트
          GestureDetector(
            onTap: () => CommentsSheet.open(context, widget.vlog),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 4, 8),
              child: Row(
                children: [
                  const Icon(
                    Icons.chat_bubble_outline_rounded,
                    size: 24,
                                      ),
                  if (widget.vlog.commentCount > 0) ...[
                    const SizedBox(width: 4),
                    Text(
                      _fmtCount(widget.vlog.commentCount),
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(width: 2),
          _ActionIconButton(
            icon: Icons.send_outlined,
            color: Theme.of(context).colorScheme.onSurface,
            onTap: _share,
          ),
          const Spacer(),
          // 🔖 저장 (북마크) — 우측 정렬 (인스타 컨벤션)
          _ActionIconButton(
            icon: _isSaved ? Icons.bookmark : Icons.bookmark_border,
            color: _isSaved
                ? const Color(0xFFFFC107)
                : Theme.of(context).colorScheme.onSurface,
            onTap: _toggleSave,
          ),
          const SizedBox(width: 4),
          Row(
            children: [
              const Icon(Icons.visibility_outlined,
                  size: 15, color: AppColors.textDisabled),
              const SizedBox(width: 4),
              Text(
                _fmtCount(widget.vlog.viewCount),
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCaption() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_likeCount > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Text(
                '좋아요 $_likeCount개',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                                    letterSpacing: -0.2,
                ),
              ),
            ),
          // Slack 스타일 이모지 리액션 바
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: ReactionBar(vlog: widget.vlog, compact: true),
          ),
          // 제목 (작성자명은 헤더에 이미 있으므로 중복 제거)
          Text(
            widget.vlog.title,
            style: const TextStyle(
              fontSize: 13.5,
                            fontWeight: FontWeight.w600,
              height: 1.35,
              letterSpacing: -0.2,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          // 거리는 헤더(주소 옆)로 이동 — 하단 칩 제거
          // 최신 댓글 1개 미리보기 (commentCount > 0 일 때만)
          if (widget.vlog.commentCount > 0) ...[
            const SizedBox(height: 6),
            _LatestCommentPreview(vlog: widget.vlog),
          ],
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 2열 (컴팩트 그리드)
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildGridCard() {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        boxShadow: AppShadow.card,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: _buildMedia(aspectRatio: null)),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.vlog.title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                                        height: 1.3,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Icon(
                      Icons.location_on,
                      size: 11,
                      color: MarkerColors.fromValue(widget.vlog.markerColor),
                    ),
                    const SizedBox(width: 2),
                    Expanded(
                      child: Text(
                        widget.vlog.placeName,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(
                      _isLiked ? Icons.favorite : Icons.favorite_outline,
                      size: 13,
                      color: _isLiked
                          ? AppColors.error
                          : AppColors.textSecondary,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      _fmtCount(_likeCount),
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.textSecondary),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.visibility_outlined,
                        size: 12, color: AppColors.textDisabled),
                    const SizedBox(width: 2),
                    Text(
                      _fmtCount(widget.vlog.viewCount),
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.textSecondary),
                    ),
                    const Spacer(),
                    Text(
                      _relativeDate(widget.vlog.createdAt),
                      style: const TextStyle(
                          fontSize: 10, color: AppColors.textDisabled),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 공통: 미디어 영역 (탭 + 더블탭 + Hero + 배지)
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildMedia({double? aspectRatio}) {
    final isMultiPhoto =
        !widget.vlog.hasVideo && widget.vlog.photoUrls.length > 1;
    // 미디어 본체 — 분기
    Widget mediaContent;
    if (widget.vlog.hasVideo &&
        widget.vlog.videoUrl != null &&
        widget.vlog.videoUrl!.isNotEmpty) {
      // 비디오: Inview/Hover 자동 미리보기
      mediaContent = _VideoPreviewArea(
        videoUrl: widget.vlog.videoUrl!,
        thumbnailWidget: Hero(
          tag: 'vlog_media_${widget.vlog.id}',
          child: _buildThumbnail(),
        ),
        visibilityKey: 'vlog_${widget.vlog.id}',
      );
    } else if (isMultiPhoto) {
      // 멀티 사진 캐러셀
      mediaContent = _buildPhotoCarousel();
    } else {
      // 단일 사진
      mediaContent = Hero(
        tag: 'vlog_media_${widget.vlog.id}',
        child: _buildThumbnail(),
      );
    }

    final media = GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        widget.onTap?.call();
      },
      onDoubleTap: _onDoubleTap,
      onLongPress: widget.onLongPress == null
          ? null
          : () {
              HapticFeedback.mediumImpact();
              widget.onLongPress?.call();
            },
      child: Stack(
        fit: StackFit.expand,
        children: [
          mediaContent,
          Positioned(
            top: 8,
            left: 8,
            child: _MediaTypeBadge(isVideo: widget.vlog.hasVideo),
          ),
          if (widget.vlog.hasVideo &&
              widget.vlog.durationSeconds != null &&
              widget.vlog.durationSeconds! > 0)
            Positioned(
              bottom: 8,
              right: 8,
              child: _DurationBadge(seconds: widget.vlog.durationSeconds!),
            )
          else if (isMultiPhoto)
            Positioned(
              bottom: 8,
              right: 8,
              child: _PhotoCountBadge(
                current: _photoPageIndex + 1,
                total: widget.vlog.photoUrls.length,
              ),
            ),
          if (_showHeartBurst)
            Center(
              child: AnimatedBuilder(
                animation: _burstCtrl,
                builder: (_, __) {
                  final v = _burstCtrl.value;
                  final scale = v < 0.4 ? 0.4 + v * 2.0 : 1.2 - (v - 0.4) * 0.3;
                  final opacity = v < 0.4 ? v * 2.5 : (1 - (v - 0.4) / 0.6);
                  return Opacity(
                    opacity: opacity.clamp(0.0, 1.0),
                    child: Transform.scale(
                      scale: scale.clamp(0.0, 1.4),
                      child: const Icon(
                        Icons.favorite,
                        color: Colors.white,
                        size: 110,
                        shadows: [
                          Shadow(
                              color: Color(0x66000000),
                              blurRadius: 24,
                              offset: Offset(0, 4)),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );

    return aspectRatio != null
        ? AspectRatio(aspectRatio: aspectRatio, child: media)
        : media;
  }

  /// 멀티 사진 캐러셀 — PageView + 마우스 드래그/휠 + 닷 인디케이터
  Widget _buildPhotoCarousel() {
    final urls = widget.vlog.photoUrls;
    return Stack(
      fit: StackFit.expand,
      children: [
        Listener(
          onPointerSignal: (event) {
            if (event is PointerScrollEvent) _handlePhotoWheel(event);
          },
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(
              dragDevices: {
                PointerDeviceKind.touch,
                PointerDeviceKind.mouse,
              },
            ),
            child: PageView.builder(
              controller: _photoPageController,
              itemCount: urls.length,
              onPageChanged: (i) {
                setState(() => _photoPageIndex = i);
                HapticFeedback.selectionClick();
              },
              itemBuilder: (_, i) => Image.network(
                urls[i],
                fit: BoxFit.cover,
                loadingBuilder: (context, child, progress) {
                  if (progress == null) return child;
                  return _ShimmerPlaceholder();
                },
                errorBuilder: (_, __, ___) => _placeholder(),
              ),
            ),
          ),
        ),
        // 하단 중앙 닷 인디케이터
        Positioned(
          bottom: 10,
          left: 0,
          right: 0,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(urls.length, (i) {
              final active = i == _photoPageIndex;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: active ? 16 : 6,
                height: 6,
                decoration: BoxDecoration(
                  color: active ? Colors.white : Colors.white60,
                  borderRadius: BorderRadius.circular(3),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x55000000),
                      blurRadius: 3,
                      offset: Offset(0, 1),
                    ),
                  ],
                ),
              );
            }),
          ),
        ),
      ],
    );
  }

  Widget _buildThumbnail() {
    final url = widget.vlog.thumbnailUrl ?? '';
    if (url.isNotEmpty) {
      return Image.network(
        url,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return _ShimmerPlaceholder();
        },
        errorBuilder: (_, __, ___) => _placeholder(),
      );
    }
    return _placeholder();
  }

  Widget _placeholder() {
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Center(
        child: Icon(
          widget.vlog.hasVideo ? Icons.videocam : Icons.photo,
          size: 36,
          color: AppColors.textDisabled,
        ),
      ),
    );
  }

  // ─── 헬퍼 ────────────────────────────────────────────────────────────────

  static String _relativeDate(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return '방금 전';
    if (diff.inHours < 1) return '${diff.inMinutes}분 전';
    if (diff.inHours < 24) return '${diff.inHours}시간 전';
    if (diff.inDays < 7) return '${diff.inDays}일 전';
    return '${dt.year}.${dt.month.toString().padLeft(2, '0')}.${dt.day.toString().padLeft(2, '0')}';
  }

  static String _fmtCount(int n) {
    if (n < 1000) return '$n';
    if (n < 10000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '${(n / 1000).toStringAsFixed(0)}K';
  }

  /// 거리 포맷 — 1km 미만은 m 단위, 이상은 km 소수 1자리
  static String _fmtDistance(double meters) {
    if (meters < 1000) return '${meters.round()}m';
    return '${(meters / 1000).toStringAsFixed(1)}km';
  }

  /// 현재 위치 기반 거리 (없으면 null)
  String? _distanceLabel() {
    final pos = widget.currentPosition;
    if (pos == null) return null;
    if (widget.vlog.lat == 0 && widget.vlog.lng == 0) return null;
    final m = Geolocator.distanceBetween(
      pos.latitude,
      pos.longitude,
      widget.vlog.lat,
      widget.vlog.lng,
    );
    return _fmtDistance(m);
  }

  /// 거리 칩(아이콘+km, primary 강조) — 헤더 주소 옆에 항상 노출. 없으면 null.
  Widget? _distanceChip() {
    final label = _distanceLabel();
    if (label == null) return null;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.near_me_rounded, size: 10.5, color: AppColors.primary),
        const SizedBox(width: 2),
        Text(label,
            style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: AppColors.primary)),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// 서브 위젯
// ═════════════════════════════════════════════════════════════════════════════

/// 작성자 아바타 — photoUrl 있으면 네트워크 이미지, 없으면 이름 첫 글자 컬러 원
class _AuthorAvatar extends StatelessWidget {
  final String name;
  final String? photoUrl;
  final double size;
  const _AuthorAvatar({required this.name, this.photoUrl, this.size = 36});

  @override
  Widget build(BuildContext context) {
    final hasPhoto = photoUrl != null && photoUrl!.isNotEmpty;
    final letter = (name.isNotEmpty ? name[0] : '?').toUpperCase();
    const palette = [
      Color(0xFF1A73E8),
      Color(0xFF34A853),
      Color(0xFFFF6B6B),
      Color(0xFF7C4DFF),
      Color(0xFFFFA726),
      Color(0xFF00ACC1),
      Color(0xFFEC407A),
    ];
    final color = palette[name.hashCode.abs() % palette.length];

    // 사진이 있으면 네트워크 이미지 + 미세한 그라디언트 링
    if (hasPhoto) {
      return Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            colors: [
              Color(0xFF1A73E8),
              Color(0xFF7C4DFF),
              Color(0xFFEC407A),
            ],
          ),
        ),
        padding: const EdgeInsets.all(1.5),
        child: Container(
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
          ),
          padding: const EdgeInsets.all(1.2),
          child: ClipOval(
            child: Image.network(
              photoUrl!,
              fit: BoxFit.cover,
              width: size,
              height: size,
              errorBuilder: (_, __, ___) => _fallbackLetter(letter, color),
              loadingBuilder: (ctx, child, prog) {
                if (prog == null) return child;
                return Container(color: color.withValues(alpha: 0.2));
              },
            ),
          ),
        ),
      );
    }

    return _fallbackLetter(letter, color);
  }

  Widget _fallbackLetter(String letter, Color color) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color,
            Color.lerp(color, Colors.black, 0.25) ?? color,
          ],
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        letter,
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.42,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

/// 액션 아이콘 버튼 (♥, 공유 등)
class _ActionIconButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _ActionIconButton({
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: onTap,
      radius: 22,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Icon(icon, size: 26, color: color),
      ),
    );
  }
}

/// 좌상단 사진/영상 타입 칩
class _MediaTypeBadge extends StatelessWidget {
  final bool isVideo;
  const _MediaTypeBadge({required this.isVideo});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(140),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isVideo ? Icons.play_arrow_rounded : Icons.photo_camera_outlined,
            color: Colors.white,
            size: 13,
          ),
          const SizedBox(width: 3),
          Text(
            isVideo ? '영상' : '사진',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// 우하단 멀티 사진 카운터 — 현재 인덱스/전체
class _PhotoCountBadge extends StatelessWidget {
  final int current;
  final int total;
  const _PhotoCountBadge({required this.current, required this.total});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(160),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.collections_outlined,
              color: Colors.white, size: 12),
          const SizedBox(width: 3),
          Text(
            '$current/$total',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── 동영상 미리보기 (Inview/Hover 자동 재생) ────────────────────────────────

class _VideoPreviewArea extends StatefulWidget {
  final String videoUrl;
  final Widget thumbnailWidget;
  final String visibilityKey;
  const _VideoPreviewArea({
    required this.videoUrl,
    required this.thumbnailWidget,
    required this.visibilityKey,
  });

  @override
  State<_VideoPreviewArea> createState() => _VideoPreviewAreaState();
}

class _VideoPreviewAreaState extends State<_VideoPreviewArea> {
  VideoPlayerController? _controller;
  bool _isPlaying = false;
  bool _muted = true;
  bool _initializing = false;
  Timer? _visibilityTimer;
  Timer? _hoverTimer;

  Future<void> _startPreview() async {
    if (!mounted) return;
    if (_initializing) return;
    if (_controller != null) {
      await _controller!.play();
      if (mounted) setState(() => _isPlaying = true);
      return;
    }
    _initializing = true;
    try {
      final ctrl = VideoPlayerController.networkUrl(
          Uri.parse(widget.videoUrl));
      await ctrl.initialize();
      await ctrl.setLooping(true);
      await ctrl.setVolume(_muted ? 0 : 1);
      if (!mounted) {
        await ctrl.dispose();
        return;
      }
      _controller = ctrl;
      await ctrl.play();
      if (mounted) setState(() => _isPlaying = true);
    } catch (_) {
      // 비디오 로드 실패 → thumbnail 그대로 유지
    } finally {
      _initializing = false;
    }
  }

  Future<void> _stopPreview() async {
    final ctrl = _controller;
    if (ctrl == null) return;
    try {
      await ctrl.pause();
      await ctrl.seekTo(Duration.zero);
    } catch (_) {}
    if (mounted) setState(() => _isPlaying = false);
  }

  void _toggleMute() {
    if (_controller == null) return;
    HapticFeedback.selectionClick();
    setState(() => _muted = !_muted);
    _controller!.setVolume(_muted ? 0 : 1);
  }

  @override
  void dispose() {
    _visibilityTimer?.cancel();
    _hoverTimer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return VisibilityDetector(
      key: Key(widget.visibilityKey),
      onVisibilityChanged: (info) {
        _visibilityTimer?.cancel();
        if (info.visibleFraction > 0.5) {
          // 50% 이상 보이면 1초 후 재생 (잠깐 스쳐 가는 카드는 무시)
          _visibilityTimer = Timer(const Duration(seconds: 1), () {
            if (mounted) _startPreview();
          });
        } else {
          _stopPreview();
        }
      },
      child: MouseRegion(
        onEnter: (_) {
          _hoverTimer?.cancel();
          _hoverTimer = Timer(const Duration(milliseconds: 200), () {
            if (mounted) _startPreview();
          });
        },
        onExit: (_) {
          _hoverTimer?.cancel();
          _stopPreview();
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 썸네일 항상 (재생 안 할 때 + 로딩 중 표시)
            widget.thumbnailWidget,
            // 재생 중인 VideoPlayer 오버레이 (cover-fit으로 채우기)
            if (_isPlaying &&
                _controller != null &&
                _controller!.value.isInitialized)
              ClipRect(
                child: FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: _controller!.value.size.width,
                    height: _controller!.value.size.height,
                    child: VideoPlayer(_controller!),
                  ),
                ),
              ),
            // 음소거 토글 (재생 중일 때 우하단)
            if (_isPlaying)
              Positioned(
                bottom: 8,
                right: 50, // 길이 배지(우하단)와 겹치지 않게
                child: GestureDetector(
                  onTap: _toggleMute,
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: Colors.black.withAlpha(160),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _muted ? Icons.volume_off : Icons.volume_up,
                      color: Colors.white,
                      size: 15,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 우하단 영상 길이 (YouTube 스타일)
class _DurationBadge extends StatelessWidget {
  final int seconds;
  const _DurationBadge({required this.seconds});

  @override
  Widget build(BuildContext context) {
    final m = seconds ~/ 60;
    final s = (seconds % 60).toString().padLeft(2, '0');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(160),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '$m:$s',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// 이미지 로딩 중 시머 효과 (TikTok/IG 스타일 스켈레톤)
class _ShimmerPlaceholder extends StatefulWidget {
  @override
  State<_ShimmerPlaceholder> createState() => _ShimmerPlaceholderState();
}

class _ShimmerPlaceholderState extends State<_ShimmerPlaceholder>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment(-1.0 + _ctrl.value * 2, 0),
              end: Alignment(0.0 + _ctrl.value * 2, 0),
              colors: const [
                Color(0xFFE8EAED),
                Color(0xFFF5F6F8),
                Color(0xFFE8EAED),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ─── 최신 댓글 1개 미리보기 ────────────────────────────────────────────────
class _LatestCommentPreview extends StatefulWidget {
  final Vlog vlog;
  const _LatestCommentPreview({required this.vlog});

  @override
  State<_LatestCommentPreview> createState() => _LatestCommentPreviewState();
}

class _LatestCommentPreviewState extends State<_LatestCommentPreview> {
  Comment? _comment;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _LatestCommentPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.vlog.id != widget.vlog.id ||
        oldWidget.vlog.commentCount != widget.vlog.commentCount) {
      _load();
    }
  }

  Future<void> _load() async {
    try {
      final c = await FirestoreService.getLatestComment(widget.vlog.id)
          .timeout(const Duration(seconds: 5),
              onTimeout: () => null);
      if (!mounted) return;
      setState(() {
        _comment = c;
        _loaded = true;
      });
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded || _comment == null) return const SizedBox.shrink();
    final c = _comment!;
    final count = widget.vlog.commentCount;
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () => CommentsSheet.open(context, widget.vlog),
      behavior: HitTestBehavior.opaque,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (count > 1) ...[
            Text(
              '댓글 $count개 모두 보기',
              style: TextStyle(
                fontSize: 12,
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 2),
          ],
          // RichText 는 DefaultTextStyle 상속이 안 돼서 color 가 transparent 로
          // 렌더되는 환경이 있음 → Text.rich 로 사용하거나 explicit color 지정 필요.
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: c.authorName,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const TextSpan(text: '  '),
                TextSpan(text: c.content),
              ],
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.35,
              color: cs.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── 체크인 카드용 컴팩트 액션 버튼 ──────────────────────────────────────
class _CheckInActionBtn extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final int count;
  final VoidCallback onTap;
  const _CheckInActionBtn({
    required this.icon,
    required this.iconColor,
    required this.count,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.full),
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Padding(
        padding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: iconColor),
            if (count > 0) ...[
              const SizedBox(width: 4),
              Text(
                '$count',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: iconColor,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── 공개 범위 작은 배지 (작성자 옆) ─────────────────────────────────
class _VisibilityBadge extends StatelessWidget {
  final VlogVisibility visibility;
  const _VisibilityBadge({required this.visibility});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Text(
        '${visibility.emoji} ${visibility.label}',
        style: TextStyle(
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
          color: cs.onSurfaceVariant,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}
