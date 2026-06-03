import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/vlog.dart';
import '../../services/firestore_service.dart';
import '../../services/friend_service.dart';
import '../../utils/constants.dart';
import '../../utils/marker_emojis.dart';
import '../users/user_profile_screen.dart';
import '../vlog/vlog_player_swiper_screen.dart';

/// 통합 검색 화면 — 브이로그(제목/작성자/주소) + 사용자(이름/이메일 prefix)
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

enum _SearchSort { recent, likes, views }

class _SearchScreenState extends State<SearchScreen>
    with SingleTickerProviderStateMixin {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  late final TabController _tabCtrl;

  Timer? _debounce;
  String _query = '';
  String? _categoryFilter; // null = 전체, 그 외 = MarkerEmojiGroup.name
  _SearchSort _sort = _SearchSort.recent;

  // 브이로그: 한 번 받아둔 캐시에서 client-side 필터
  final List<Vlog> _vlogCache = [];
  StreamSubscription<List<Vlog>>? _vlogSub;
  bool _vlogsLoaded = false;

  // 사용자: 검색마다 fetch
  List<Map<String, dynamic>> _userResults = [];
  bool _userLoading = false;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    // 200개까지 받아 client-side filter
    _vlogSub = FirestoreService.watchVlogs(limit: 200).listen((data) {
      if (!mounted) return;
      setState(() {
        _vlogCache
          ..clear()
          ..addAll(data);
        _vlogsLoaded = true;
      });
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _vlogSub?.cancel();
    _ctrl.dispose();
    _focus.dispose();
    _tabCtrl.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      setState(() => _query = value.trim());
      _searchUsers(value.trim());
    });
  }

  Future<void> _searchUsers(String q) async {
    if (q.isEmpty) {
      setState(() {
        _userResults = [];
        _userLoading = false;
      });
      return;
    }
    setState(() => _userLoading = true);
    try {
      final hits = await FriendService.searchUsers(q);
      if (!mounted) return;
      setState(() {
        _userResults = hits;
        _userLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _userLoading = false);
    }
  }

  List<Vlog> get _filteredVlogs {
    Iterable<Vlog> list = _vlogCache;

    // 카테고리 필터 (이모지 그룹)
    if (_categoryFilter != null) {
      list = list.where((v) {
        if (v.markerEmoji == null) return _categoryFilter == '일반';
        return MarkerEmojis.fromEmoji(v.markerEmoji).category ==
            _categoryFilter;
      });
    }

    // 키워드 필터
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      list = list.where((v) {
        return v.title.toLowerCase().contains(q) ||
            v.authorName.toLowerCase().contains(q) ||
            (v.address ?? '').toLowerCase().contains(q) ||
            v.placeName.toLowerCase().contains(q);
      });
    }
    // 정렬
    final out = list.toList();
    switch (_sort) {
      case _SearchSort.recent:
        out.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        break;
      case _SearchSort.likes:
        out.sort((a, b) => b.likeCount.compareTo(a.likeCount));
        break;
      case _SearchSort.views:
        out.sort((a, b) => b.viewCount.compareTo(a.viewCount));
        break;
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.surface,
        elevation: 0,
        scrolledUnderElevation: 1,
        titleSpacing: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: TextField(
          controller: _ctrl,
          focusNode: _focus,
          onChanged: _onQueryChanged,
          textInputAction: TextInputAction.search,
          style: const TextStyle(
              fontSize: 15),
          decoration: InputDecoration(
            hintText: '제목, 친구 이름, 장소를 검색',
            hintStyle: const TextStyle(
                color: AppColors.textDisabled, fontSize: 14),
            border: InputBorder.none,
            isDense: true,
            suffixIcon: _query.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    color: AppColors.textSecondary,
                    onPressed: () {
                      _ctrl.clear();
                      _onQueryChanged('');
                    },
                  ),
          ),
        ),
        bottom: TabBar(
          controller: _tabCtrl,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textSecondary,
          indicatorColor: AppColors.primary,
          indicatorWeight: 2.5,
          labelStyle: const TextStyle(
              fontSize: 13.5, fontWeight: FontWeight.w700),
          unselectedLabelStyle:
              const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500),
          tabs: [
            Tab(text: '브이로그${(_query.isEmpty && _categoryFilter == null) ? '' : ' ${_filteredVlogs.length}'}'),
            Tab(text: '사용자${_userResults.isEmpty ? '' : ' ${_userResults.length}'}'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [
          _buildVlogTab(),
          _buildUserTab(),
        ],
      ),
    );
  }

  // ─── 브이로그 탭 ────────────────────────────────────────────────────────
  Widget _buildVlogTab() {
    if (!_vlogsLoaded) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.primary));
    }
    final list = _filteredVlogs;
    final hasAnyFilter = _query.isNotEmpty || _categoryFilter != null;

    return Column(
      children: [
        // 카테고리 칩 필터 (항상 표시)
        SizedBox(
          height: 38,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md, vertical: 4),
            children: [
              _CategoryChip(
                label: '전체',
                emoji: '🌐',
                selected: _categoryFilter == null,
                onTap: () => setState(() => _categoryFilter = null),
              ),
              const SizedBox(width: 6),
              ...MarkerEmojis.groups.map((g) => Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: _CategoryChip(
                      label: g.name,
                      emoji: g.hint,
                      selected: _categoryFilter == g.name,
                      onTap: () => setState(() => _categoryFilter = g.name),
                    ),
                  )),
            ],
          ),
        ),
        // 정렬 토글
        SizedBox(
          height: 36,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md, vertical: 4),
            children: [
              _SortToggle(
                label: '최신순',
                icon: Icons.access_time,
                selected: _sort == _SearchSort.recent,
                onTap: () => setState(() => _sort = _SearchSort.recent),
              ),
              const SizedBox(width: 6),
              _SortToggle(
                label: '좋아요순',
                icon: Icons.favorite,
                selected: _sort == _SearchSort.likes,
                onTap: () => setState(() => _sort = _SearchSort.likes),
              ),
              const SizedBox(width: 6),
              _SortToggle(
                label: '조회순',
                icon: Icons.visibility_outlined,
                selected: _sort == _SearchSort.views,
                onTap: () => setState(() => _sort = _SearchSort.views),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: !hasAnyFilter
              ? _emptyHint(
                  icon: Icons.search,
                  title: '키워드 또는 카테고리를 선택해 보세요',
                  sub: '제목·작성자·장소로 검색하거나 위에서 카테고리를 골라요',
                )
              : list.isEmpty
                  ? _emptyHint(
                      icon: Icons.movie_filter_outlined,
                      title: '검색 결과가 없어요',
                      sub: '다른 조건으로 시도해 보세요',
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: list.length,
                      separatorBuilder: (_, __) =>
                          const Divider(height: 1, indent: 80),
                      itemBuilder: (_, i) => _VlogResultTile(
                          vlog: list[i],
                          playlist: list,
                          query: _query),
                    ),
        ),
      ],
    );
  }

  // ─── 사용자 탭 ────────────────────────────────────────────────────────
  Widget _buildUserTab() {
    if (_query.isEmpty) {
      return _emptyHint(
        icon: Icons.person_search,
        title: '이름·이메일로 친구를 찾아보세요',
        sub: '※ 이름은 앞부분이 일치할 때 검색돼요',
      );
    }
    if (_userLoading) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.primary));
    }
    if (_userResults.isEmpty) {
      return _emptyHint(
        icon: Icons.person_off_outlined,
        title: '일치하는 사용자가 없어요',
        sub: '이름의 앞부분(예: "구")으로 시도해 보세요',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _userResults.length,
      separatorBuilder: (_, __) => const Divider(height: 1, indent: 76),
      itemBuilder: (_, i) => _UserResultTile(user: _userResults[i]),
    );
  }

  Widget _emptyHint({
    required IconData icon,
    required String title,
    required String sub,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: AppColors.textDisabled),
            const SizedBox(height: AppSpacing.md),
            Text(title,
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(sub,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 12.5, color: AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }
}

// ─── 검색 정렬 토글 ──────────────────────────────────────────────────────
class _SortToggle extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  const _SortToggle({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.full),
          border: Border.all(
            color: selected
                ? AppColors.primary
                : AppColors.textDisabled.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12,
                color: selected
                    ? AppColors.primary
                    : AppColors.textSecondary),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: selected
                    ? AppColors.primary
                    : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── 카테고리 칩 ─────────────────────────────────────────────────────────
class _CategoryChip extends StatelessWidget {
  final String label;
  final String emoji;
  final bool selected;
  final VoidCallback onTap;
  const _CategoryChip({
    required this.label,
    required this.emoji,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppRadius.full),
          border: Border.all(
            color: selected
                ? AppColors.primary
                : AppColors.textDisabled.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 14)),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── 브이로그 검색 결과 타일 ─────────────────────────────────────────────
class _VlogResultTile extends StatelessWidget {
  final Vlog vlog;
  final List<Vlog> playlist;
  final String query;
  const _VlogResultTile({
    required this.vlog,
    required this.playlist,
    required this.query,
  });

  @override
  Widget build(BuildContext context) {
    final thumb = vlog.thumbnailUrl ?? '';
    final isVideo = vlog.hasVideo;
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        VlogPlayerSwiperScreen.open(
          context,
          vlogs: playlist,
          initial: vlog,
        );
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.sm),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              child: Stack(
                children: [
                  SizedBox(
                    width: 56,
                    height: 56,
                    child: thumb.isNotEmpty
                        ? Image.network(thumb,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                _thumbPlaceholder(isVideo))
                        : _thumbPlaceholder(isVideo),
                  ),
                  if (isVideo)
                    const Positioned(
                      bottom: 2,
                      right: 2,
                      child: Icon(Icons.play_circle_fill,
                          size: 16, color: Colors.white),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    vlog.title.isEmpty ? '제목 없음' : vlog.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      const Icon(Icons.person,
                          size: 12, color: AppColors.textDisabled),
                      const SizedBox(width: 2),
                      Flexible(
                        child: Text(
                          vlog.authorName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.textSecondary),
                        ),
                      ),
                      if ((vlog.address ?? '').isNotEmpty) ...[
                        const SizedBox(width: 6),
                        const Icon(Icons.place,
                            size: 11, color: AppColors.textDisabled),
                        const SizedBox(width: 1),
                        Expanded(
                          child: Text(
                            vlog.address!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 11.5,
                                color: AppColors.textSecondary),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right,
                size: 18, color: AppColors.textDisabled),
          ],
        ),
      ),
    );
  }

  Widget _thumbPlaceholder(bool isVideo) => Container(
        color: AppColors.surfaceVariant,
        child: Icon(
          isVideo ? Icons.videocam : Icons.photo,
          color: AppColors.textDisabled,
          size: 20,
        ),
      );
}

// ─── 사용자 검색 결과 타일 ─────────────────────────────────────────────
class _UserResultTile extends StatelessWidget {
  final Map<String, dynamic> user;
  const _UserResultTile({required this.user});

  @override
  Widget build(BuildContext context) {
    final uid = user['uid'] as String;
    final name = (user['displayName'] as String?) ?? '익명';
    final email = user['email'] as String?;
    final photo = user['photoUrl'] as String?;
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => UserProfileScreen(
              uid: uid,
              name: name,
              photoUrl: photo,
              email: email,
            ),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.sm),
        child: Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: AppColors.primary.withValues(alpha: 0.12),
              backgroundImage: (photo != null && photo.isNotEmpty)
                  ? NetworkImage(photo)
                  : null,
              child: (photo == null || photo.isEmpty)
                  ? Text(
                      name.isNotEmpty ? name[0].toUpperCase() : '?',
                      style: const TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.bold,
                          fontSize: 16),
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600),
                  ),
                  if (email != null && email.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right,
                size: 18, color: AppColors.textDisabled),
          ],
        ),
      ),
    );
  }
}
