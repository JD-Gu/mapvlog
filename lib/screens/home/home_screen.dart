import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/friend_group.dart';
import '../../models/vlog.dart';
import '../../screens/auth/login_screen.dart';
import '../../screens/friends/friend_list_screen.dart';
import '../../screens/live_map/live_map_screen.dart';
import '../../screens/map/map_screen.dart';
import '../../screens/profile/profile_screen.dart';
import '../../screens/search/search_screen.dart';
import '../../screens/vlog/vlog_edit_screen.dart';
import '../../screens/vlog/vlog_player_swiper_screen.dart';
import '../../services/firestore_service.dart';
import '../../services/friend_group_service.dart';
import '../../services/friend_service.dart';
import '../../services/location_service.dart';
import '../../utils/constants.dart';
import '../../utils/marker_emojis.dart';
import '../../widgets/check_in_sheet.dart';
import '../../utils/sheets.dart';
import '../../widgets/marquee_slogan.dart';
import '../../widgets/notifications_sheet.dart';
import '../../widgets/visibility_picker.dart';
import '../../widgets/vlog_card.dart';

enum _SortMode { byDate, byDistance }
enum _SortOrder { asc, desc }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  /// 1 = 1열 가로 카드 (기본값), 2 = 2열 그리드
  int _crossAxisCount = 1;
  _SortMode _sortMode = _SortMode.byDate;
  String? _categoryFilter; // null = 전체
  _SortOrder _sortOrder = _SortOrder.desc; // 날짜 기본: 최신순
  Position? _position;
  /// 친구 UID 캐시 (피드 필터링용) — null이면 로딩 중
  List<String>? _friendUids;
  StreamSubscription<List<dynamic>>? _friendsSub;
  /// 내가 만든 친구 그룹 — null이면 로딩 중
  List<FriendGroup>? _myGroups;
  StreamSubscription<List<FriendGroup>>? _groupsSub;
  /// 선택된 그룹 ID — null = 전체 친구
  String? _activeGroupId;

  /// 그룹 필터 적용 후 effective 친구 UID 목록
  /// — _activeGroupId == null 이면 전체 친구 반환
  List<String> get _effectiveFriendUids {
    final all = _friendUids ?? [];
    if (_activeGroupId == null) return all;
    final group = _myGroups
        ?.firstWhere(
          (g) => g.id == _activeGroupId,
          orElse: () => FriendGroup(
            id: '',
            name: '',
            emoji: '',
            mode: GroupMode.insider,
            memberUids: const [],
            createdAt: DateTime.now(),
          ),
        );
    if (group == null || group.id.isEmpty) return all;
    final memberSet = group.memberUids.toSet();
    return all.where(memberSet.contains).toList();
  }
  /// 거리 정렬용 위치 페치 중 → 스켈레톤 표시
  bool _fetchingPosition = false;
  /// 마지막으로 확인한 시점 (이 이후의 vlog는 "새 vlog")
  DateTime? _lastSeenAt;

  static const _lastSeenKey = 'home_last_seen_vlog_at';

  Future<void> _loadLastSeen() async {
    final prefs = await SharedPreferences.getInstance();
    final ms = prefs.getInt(_lastSeenKey);
    if (mounted) {
      setState(() {
        _lastSeenAt = ms == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(ms);
      });
    }
  }

  Future<void> _markAllSeen(List<Vlog> vlogs) async {
    if (vlogs.isEmpty) return;
    HapticFeedback.selectionClick();
    final newest = vlogs
        .map((v) => v.createdAt)
        .reduce((a, b) => a.isAfter(b) ? a : b);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_lastSeenKey, newest.millisecondsSinceEpoch);
    if (mounted) setState(() => _lastSeenAt = newest);
  }

  int _newCount(List<Vlog> vlogs) {
    if (_lastSeenAt == null) return 0;
    final me = FirebaseAuth.instance.currentUser?.uid;
    // 자기 vlog는 카운트에서 제외
    return vlogs
        .where((v) =>
            v.createdAt.isAfter(_lastSeenAt!) && v.authorId != me)
        .length;
  }

  List<Vlog> _sorted(List<Vlog> vlogs) {
    Iterable<Vlog> src = vlogs;

    // 그룹 필터 활성 시 — 내 글은 "그 그룹에 공개한 글"만 노출.
    // (친구 글은 watchFriendsVlogs 의 author 쿼리로 이미 그룹 멤버만 들어옴.
    //  내 글은 항상 포함되므로 여기서 그룹 공개 여부로 한 번 더 거른다.)
    if (_activeGroupId != null) {
      final me = FirebaseAuth.instance.currentUser?.uid;
      src = src.where((v) =>
          v.authorId != me || v.visibleGroupIds.contains(_activeGroupId));
    }

    // 카테고리 필터 적용
    final source = _categoryFilter == null
        ? src.toList()
        : src.where((v) {
            if (v.markerEmoji == null) return _categoryFilter == '일반';
            return MarkerEmojis.fromEmoji(v.markerEmoji).category ==
                _categoryFilter;
          }).toList();
    final list = List<Vlog>.from(source);
    if (_sortMode == _SortMode.byDistance && _position != null) {
      list.sort((a, b) {
        final da = Geolocator.distanceBetween(
            _position!.latitude, _position!.longitude, a.lat, a.lng);
        final db = Geolocator.distanceBetween(
            _position!.latitude, _position!.longitude, b.lat, b.lng);
        return _sortOrder == _SortOrder.asc
            ? da.compareTo(db)
            : db.compareTo(da);
      });
    } else {
      // 날짜순
      list.sort((a, b) => _sortOrder == _SortOrder.asc
          ? a.createdAt.compareTo(b.createdAt)
          : b.createdAt.compareTo(a.createdAt));
    }
    return list;
  }

  /// 같은 모드 탭 → 오름/내림 토글
  /// 다른 모드 탭 → 모드 변경 + 기본 방향 설정
  Future<void> _onSortTap(_SortMode mode) async {
    if (_sortMode == mode) {
      setState(() => _sortOrder =
          _sortOrder == _SortOrder.desc ? _SortOrder.asc : _SortOrder.desc);
      return;
    }
    final defaultOrder =
        mode == _SortMode.byDate ? _SortOrder.desc : _SortOrder.asc;
    if (mode == _SortMode.byDistance && _position == null) {
      // 위치 페치 중에는 스켈레톤 표시
      setState(() {
        _fetchingPosition = true;
        _sortMode = mode;
        _sortOrder = defaultOrder;
      });
      final pos = await LocationService.getCurrentPosition(context);
      if (!mounted) return;
      setState(() {
        _position = pos;
        _fetchingPosition = false;
      });
    } else {
      setState(() {
        _sortMode = mode;
        _sortOrder = defaultOrder;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _subscribeFriends();
    _subscribeGroups();
    _loadLastSeen();
    _primeDistance();
  }

  /// 카드에 거리를 항상 표시하기 위해 진입 시 위치를 미리 확보.
  /// 권한 프롬프트는 띄우지 않음(마지막 위치 → 이미 허용된 경우만 현재 위치).
  Future<void> _primeDistance() async {
    if (_position != null) return;
    try {
      Position? pos = await Geolocator.getLastKnownPosition();
      if (pos == null) {
        final perm = await Geolocator.checkPermission();
        if (perm == LocationPermission.always ||
            perm == LocationPermission.whileInUse) {
          pos = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
                accuracy: LocationAccuracy.medium,
                timeLimit: Duration(seconds: 5)),
          );
        }
      }
      if (pos != null && mounted && _position == null) {
        setState(() => _position = pos);
      }
    } catch (_) {}
  }

  /// 친구 목록 구독 — 친구가 바뀌면 자동으로 피드도 갱신
  void _subscribeFriends() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _friendUids = [];
      return;
    }
    _friendsSub = FriendService.watchMyFriends().listen((list) {
      if (!mounted) return;
      setState(() => _friendUids = list.map((f) => f.friendUid).toList());
    });
  }

  /// 친구 그룹 목록 구독 — 그룹 가로 탭에 표시
  void _subscribeGroups() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _myGroups = [];
      return;
    }
    _groupsSub = FriendGroupService.watchMyGroups().listen((list) {
      if (!mounted) return;
      setState(() {
        _myGroups = list;
        // 선택돼있던 그룹이 삭제된 경우 전체로 되돌림
        if (_activeGroupId != null &&
            !list.any((g) => g.id == _activeGroupId)) {
          _activeGroupId = null;
        }
      });
    });
  }

  @override
  void dispose() {
    _friendsSub?.cancel();
    _groupsSub?.cancel();
    super.dispose();
  }

  /// vlog 카드 탭 라우팅
  /// - 체크인: 친구지도(LiveMap) 진입 + 임시 마커로 위치 표시
  /// - 일반 vlog: 플레이어 화면 (좌우 스와이프 가능 — 피드 내 인접 vlog로 이동)
  void _openVlog(Vlog vlog, List<Vlog> feed) {
    HapticFeedback.selectionClick();
    if (vlog.isCheckIn) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => LiveMapScreen(focusCheckIn: vlog),
        ),
      );
      return;
    }
    VlogPlayerSwiperScreen.open(context, vlogs: feed, initial: vlog);
  }

  // ─── 등록자 전용 수정·삭제 메뉴 ──────────────────────────────────────────

  void _showVlogMenu(BuildContext ctx, Vlog vlog) {
    showModalBottomSheet(
      context: ctx,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      // sheetCtx: 바텀시트 자체 context — pop 전용으로만 사용
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36, height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(
                vlog.title,
                style: const TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 15),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.edit, color: AppColors.primary),
              title: const Text('수정'),
              subtitle: const Text('제목·장소명 변경'),
              onTap: () {
                Navigator.pop(sheetCtx); // 바텀시트 닫기
                _showEditDialog(vlog);   // 이후는 State 자신의 context 사용
              },
            ),
            // 공개 범위 변경
            ListTile(
              leading: Icon(
                vlog.visibility == VlogVisibility.private
                    ? Icons.lock_outline
                    : vlog.visibility == VlogVisibility.groups
                        ? Icons.group_outlined
                        : Icons.public,
                color: AppColors.primary,
              ),
              title: const Text('공개 범위 변경'),
              subtitle: Text(
                  '${vlog.visibility.emoji} ${vlog.visibility.label}'),
              onTap: () {
                Navigator.pop(sheetCtx);
                _changeVisibility(vlog);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: AppColors.error),
              title: const Text('삭제',
                  style: TextStyle(color: AppColors.error)),
              subtitle: const Text('이 기록을 영구 삭제합니다'),
              onTap: () {
                Navigator.pop(sheetCtx);
                _confirmDelete(vlog);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// 공개 범위 변경 시트 + Firestore 갱신
  Future<void> _changeVisibility(Vlog vlog) async {
    final initial = VisibilitySelection(
      visibility: vlog.visibility,
      groupIds: vlog.visibleGroupIds,
      visibleUids: vlog.visibleUids,
    );
    final picked = await showModalBottomSheet<VisibilitySelection>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => VisibilityPickerSheet(initial: initial),
    );
    if (picked == null || !mounted) return;
    try {
      await FirestoreService.updateVisibility(
        vlogId: vlog.id,
        visibility: picked.visibility,
        visibleGroupIds: picked.groupIds,
        visibleUids: picked.visibleUids,
      );
      if (!mounted) return;
      HapticFeedback.lightImpact();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            '${picked.visibility.emoji} ${picked.visibility.label} (으)로 변경됐어요'),
        duration: const Duration(seconds: 2),
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('변경 실패: $e'),
        backgroundColor: AppColors.error,
      ));
    }
  }

  Future<void> _showEditDialog(Vlog vlog) async {
    // 체크인은 전용 체크인 시트(수정 모드)로 — 위치·표시시간·공개범위까지 일관 편집
    if (vlog.isCheckIn) {
      await CheckInSheet.open(context, editing: vlog);
      return;
    }
    // 일반 사진·영상 브이로그는 단일 화면 수정 (마법사 컴포넌트 재사용)
    await VlogEditScreen.open(context, vlog);
  }

  Future<void> _confirmDelete(Vlog vlog) async {
    final ok = await AppSheets.confirm(
      context,
      icon: Icons.delete_outline,
      title: '"${vlog.title}" 삭제',
      message: '이 기록을 영구 삭제합니다.\n복구할 수 없습니다.',
      confirmLabel: '삭제',
      dangerous: true,
    );

    if (ok != true) return;

    try {
      await FirestoreService.deleteVlog(vlog.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🗑️ 삭제됐습니다'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('삭제 실패: $e'),
              backgroundColor: AppColors.error),
        );
      }
    }
  }

  Future<void> _onRefresh() async {
    HapticFeedback.lightImpact();
    // Firestore 스트림은 실시간이라 별도 재요청 불필요 — UX용 짧은 지연
    await Future.delayed(const Duration(milliseconds: 700));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: _onRefresh,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            // ── 앱바 ──────────────────────────────────────────────────────
            SliverAppBar(
              backgroundColor: Theme.of(context).colorScheme.surface,
              // 홈은 탭 루트 — 아래에 라우트가 남아도 뒤로가기 버튼 표시 안 함
              automaticallyImplyLeading: false,
              floating: true,
              snap: true,
              elevation: 0,
              scrolledUnderElevation: 1,
              titleSpacing: 12,
              title: Row(
                children: [
                  Image.asset(
                    'assets/images/Pinflick_icon.png',
                    width: 30,
                    height: 30,
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'PinFlick',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.bold,
                      fontSize: 22,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(width: 10),
                  // 마퀴 슬로건 — 뉴스 자막 스타일, 우→좌 끊김 없는 흐름
                  // Expanded로 폭을 명시 바운드 (AppBar.title 안에서 더 안정적)
                  const Expanded(child: MarqueeSlogan()),
                ],
              ),
              actions: [
                _NotificationBell(),
                IconButton(
                  icon: const Icon(Icons.search),
                  tooltip: '검색',
                  onPressed: () {
                    HapticFeedback.selectionClick();
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const SearchScreen(),
                      ),
                    );
                  },
                ),
                // 프로필 아바타 (헤더 우측 끝) — 탭 시 프로필 화면 push
                const _HeaderProfileAvatar(),
                const SizedBox(width: 6),
              ],
            ),

            // ── 새 vlog 배너 (last seen 이후 새 vlog 있을 때만) ─────────
            if (_friendUids != null)
              SliverToBoxAdapter(
                child: StreamBuilder<List<Vlog>>(
                  stream: FirestoreService.watchFriendsVlogs(
                    friendUids: _effectiveFriendUids,
                    myUid: FirebaseAuth.instance.currentUser?.uid ?? '',
                  ),
                  builder: (context, snap) {
                    final vlogs = snap.data ?? [];
                    final count = _newCount(vlogs);
                    if (count <= 0) return const SizedBox.shrink();
                    return _NewVlogBanner(
                      count: count,
                      onTap: () => _markAllSeen(vlogs),
                    );
                  },
                ),
              ),

            // ── 친구 그룹 가로 탭 (전체 + 사용자가 만든 그룹) ──────────
            if (_myGroups != null)
              SliverToBoxAdapter(
                child: _FriendGroupTabBar(
                  groups: _myGroups!,
                  activeGroupId: _activeGroupId,
                  onSelect: (gid) {
                    HapticFeedback.selectionClick();
                    setState(() => _activeGroupId = gid);
                  },
                ),
              ),

            // ── 카테고리 칩 필터 (가로 스크롤) ───────────────────────────
            SliverToBoxAdapter(
              child: SizedBox(
                height: 40,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(
                      AppSpacing.md, 6, AppSpacing.md, 4),
                  children: [
                    _HomeCategoryChip(
                      label: '전체',
                      emoji: '🌐',
                      selected: _categoryFilter == null,
                      onTap: () => setState(() => _categoryFilter = null),
                    ),
                    const SizedBox(width: 6),
                    ...MarkerEmojis.groups.map((g) => Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: _HomeCategoryChip(
                            label: g.name,
                            emoji: g.hint,
                            selected: _categoryFilter == g.name,
                            onTap: () =>
                                setState(() => _categoryFilter = g.name),
                          ),
                        )),
                  ],
                ),
              ),
            ),

            // ── 컴팩트 "지도 탐색" CTA + 정렬/뷰 토글 (한 줄) ─────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md, 4, AppSpacing.md, 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _SortChip(
                      label: '날짜순',
                      icon: Icons.calendar_today_outlined,
                      selected: _sortMode == _SortMode.byDate,
                      ascending: _sortOrder == _SortOrder.asc,
                      onTap: () => _onSortTap(_SortMode.byDate),
                    ),
                    const SizedBox(width: 6),
                    _SortChip(
                      label: '거리순',
                      icon: Icons.near_me_outlined,
                      selected: _sortMode == _SortMode.byDistance,
                      ascending: _sortOrder == _SortOrder.asc,
                      onTap: () => _onSortTap(_SortMode.byDistance),
                    ),
                    const SizedBox(width: 6),
                    _MapCtaChip(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const MapScreen(),
                          ),
                        );
                      },
                    ),
                    const Spacer(),
                    _ViewToggleBtn(
                      icon: Icons.view_stream,
                      active: _crossAxisCount == 1,
                      tooltip: '1열 보기',
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() => _crossAxisCount = 1);
                      },
                    ),
                    _ViewToggleBtn(
                      icon: Icons.grid_view,
                      active: _crossAxisCount == 2,
                      tooltip: '2열 보기',
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() => _crossAxisCount = 2);
                      },
                    ),
                  ],
                ),
              ),
            ),

            // ── 친구 + 본인 피드 스트림 (익명 보기 차단) ─────────────────
            _buildFeedSliver(),
          ],
        ),
      ),
    );
  }

  /// 친구 + 본인 피드 sliver — 비로그인 시 로그인 유도
  Widget _buildFeedSliver() {
    final me = FirebaseAuth.instance.currentUser;
    if (me == null) {
      return const SliverFillRemaining(
        hasScrollBody: false,
        child: _GuestState(),
      );
    }
    // 친구 목록 로딩 전 또는 거리순 전환 위치 페치 중이면 스켈레톤
    if (_friendUids == null || _fetchingPosition) {
      return _SkeletonSliver(isGrid: _crossAxisCount == 2);
    }
    return StreamBuilder<List<Vlog>>(
      stream: FirestoreService.watchFriendsVlogs(
        friendUids: _effectiveFriendUids,
        myUid: me.uid,
      ),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _SkeletonSliver(isGrid: _crossAxisCount == 2);
        }
        if (snapshot.hasError) {
          return SliverFillRemaining(
            hasScrollBody: false,
            child: _ErrorState(error: snapshot.error.toString()),
          );
        }
        final vlogs = _sorted(snapshot.data ?? []);
        if (vlogs.isEmpty) {
          return SliverFillRemaining(
            hasScrollBody: false,
            child: _FriendsEmptyState(hasFriends: _friendUids!.isNotEmpty),
          );
        }

        // 그리드 / 리스트
        final isGrid = _crossAxisCount == 2;

        // 1열 + 날짜순일 때만 날짜 헤더 삽입 (혼합 아이템 리스트)
        final showDateHeaders =
            !isGrid && _sortMode == _SortMode.byDate;
        final mixed = showDateHeaders ? _withDateHeaders(vlogs) : null;

        SliverChildBuilderDelegate buildDelegate(bool grid) =>
            SliverChildBuilderDelegate(
              (context, index) {
                final vlog = vlogs[index];
                final isAuthor =
                    FirebaseAuth.instance.currentUser?.uid == vlog.authorId;
                final card = VlogCard(
                  vlog: vlog,
                  singleColumn: !grid,
                  currentPosition: _position,
                  onTap: () => _openVlog(vlog, vlogs),
                  onLongPress:
                      isAuthor ? () => _showVlogMenu(context, vlog) : null,
                );
                return grid
                    ? card
                    : Padding(
                        padding:
                            const EdgeInsets.only(bottom: AppSpacing.md),
                        child: card,
                      );
              },
              childCount: vlogs.length,
            );

        SliverChildBuilderDelegate buildMixedDelegate() =>
            SliverChildBuilderDelegate(
              (context, index) {
                final item = mixed![index];
                if (item is String) {
                  return _DateSectionHeader(label: item);
                }
                final vlog = item as Vlog;
                final isAuthor =
                    FirebaseAuth.instance.currentUser?.uid == vlog.authorId;
                return Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.md),
                  child: VlogCard(
                    vlog: vlog,
                    singleColumn: true,
                    currentPosition: _position,
                    onTap: () => _openVlog(vlog, vlogs),
                    onLongPress: isAuthor
                        ? () => _showVlogMenu(context, vlog)
                        : null,
                  ),
                );
              },
              childCount: mixed!.length,
            );

        return SliverPadding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.md, 6, AppSpacing.md, AppSpacing.xl),
          sliver: isGrid
              ? SliverGrid(
                  delegate: buildDelegate(true),
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: AppSpacing.sm,
                    mainAxisSpacing: AppSpacing.sm,
                    childAspectRatio: 0.72,
                  ),
                )
              : SliverList(
                  delegate: showDateHeaders
                      ? buildMixedDelegate()
                      : buildDelegate(false)),
        );
      },
    );
  }

  /// 정렬된 vlogs(날짜 desc)를 dateLabel 헤더로 묶어 mixed 리스트로 반환
  List<dynamic> _withDateHeaders(List<Vlog> vlogs) {
    final out = <dynamic>[];
    String? lastLabel;
    for (final v in vlogs) {
      final label = _dateLabel(v.createdAt);
      if (label != lastLabel) {
        out.add(label);
        lastLabel = label;
      }
      out.add(v);
    }
    return out;
  }

  String _dateLabel(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final vd = DateTime(d.year, d.month, d.day);
    final diff = today.difference(vd).inDays;
    if (diff == 0) return '오늘';
    if (diff == 1) return '어제';
    if (diff < 7) return '$diff일 전';
    if (now.year == d.year) return '${d.month}월 ${d.day}일';
    return '${d.year}.${d.month}.${d.day}';
  }
}

// ─── 알림 벨 (배지 + 시트 트리거) ──────────────────────────────────────────
class _NotificationBell extends StatelessWidget {
  Stream<int> _watchUnreadCount() async* {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      yield 0;
      return;
    }
    // 호출 개수 + 친구 요청 개수
    await for (final _ in Stream.periodic(const Duration(seconds: 8))) {
      try {
        final pings = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('pings')
            .where('createdAt',
                isGreaterThan: Timestamp.fromDate(
                    DateTime.now().subtract(const Duration(hours: 1))))
            .count()
            .get();
        final reqs = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('friends')
            .where('status', isEqualTo: 'incoming')
            .count()
            .get();
        yield (pings.count ?? 0) + (reqs.count ?? 0);
      } catch (_) {
        yield 0;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: _watchUnreadCount(),
      builder: (context, snap) {
        final count = snap.data ?? 0;
        return Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            IconButton(
              icon: Icon(
                count > 0
                    ? Icons.notifications_active
                    : Icons.notifications_outlined,
                color: count > 0
                    ? AppColors.primary
                    : Theme.of(context).colorScheme.onSurface,
              ),
              onPressed: () => NotificationsSheet.open(context),
            ),
            if (count > 0)
              Positioned(
                right: 6,
                top: 6,
                child: Container(
                  constraints:
                      const BoxConstraints(minWidth: 16, minHeight: 16),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: AppColors.error,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                  child: Text(
                    count > 99 ? '99+' : '$count',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

// ─── 컴팩트 "지도 탐색" 칩 ──────────────────────────────────────────────────
class _MapCtaChip extends StatelessWidget {
  final VoidCallback? onTap;
  const _MapCtaChip({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap?.call();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: AppColors.primary.withValues(alpha: 0.35),
            width: 1.2,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.map_outlined,
                size: 13, color: AppColors.primary),
            const SizedBox(width: 4),
            Text(
              '지도보기',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── 비로그인 상태 ────────────────────────────────────────────────────────────
class _GuestState extends StatelessWidget {
  const _GuestState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primary.withValues(alpha: 0.08),
              ),
              child: const Icon(Icons.lock_outline,
                  size: 48, color: AppColors.primary),
            ),
            const SizedBox(height: 18),
            const Text(
              '로그인 후 친구 피드를 만나보세요',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              '친구를 추가하면 그들의 브이로그가\n여기에 표시됩니다',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 18),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                );
              },
              icon: const Icon(Icons.login, size: 18),
              label: const Text('로그인'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                    horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(AppRadius.full)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── 친구 없음/친구는 있는데 피드 비어있음 ─────────────────────────────────
class _FriendsEmptyState extends StatelessWidget {
  final bool hasFriends;
  const _FriendsEmptyState({required this.hasFriends});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primary.withValues(alpha: 0.08),
              ),
              child: Icon(
                hasFriends ? Icons.movie_outlined : Icons.people_outline,
                size: 48,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              hasFriends ? '아직 올라온 브이로그가 없어요' : '친구를 추가해서 피드를 채워보세요',
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              hasFriends
                  ? '나와 친구들이 브이로그를 올리면\n여기에 표시됩니다'
                  : '이메일로 친구를 검색하고\n요청을 보내보세요',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
                height: 1.5,
              ),
            ),
            if (!hasFriends) ...[
              const SizedBox(height: 18),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const FriendListScreen()),
                  );
                },
                icon: const Icon(Icons.person_add_outlined, size: 18),
                label: const Text('친구 추가'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(AppRadius.full)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── 오류 상태 ───────────────────────────────────────────────────────────────
class _ErrorState extends StatelessWidget {
  final String error;
  const _ErrorState({required this.error});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.error.withValues(alpha: 0.08),
              ),
              child: const Icon(Icons.cloud_off_outlined,
                  size: 38, color: AppColors.error),
            ),
            const SizedBox(height: 14),
            const Text('데이터를 불러올 수 없습니다',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                )),
            const SizedBox(height: 6),
            Text(
              error,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 12, color: AppColors.textSecondary),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── 스켈레톤 로딩 ───────────────────────────────────────────────────────────
class _SkeletonSliver extends StatelessWidget {
  final bool isGrid;
  const _SkeletonSliver({required this.isGrid});

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.md, 6, AppSpacing.md, AppSpacing.xl),
      sliver: isGrid
          ? SliverGrid(
              delegate: SliverChildBuilderDelegate(
                (_, __) => const _SkeletonCard(grid: true),
                childCount: 6,
              ),
              gridDelegate:
                  const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: AppSpacing.sm,
                mainAxisSpacing: AppSpacing.sm,
                childAspectRatio: 0.72,
              ),
            )
          : SliverList(
              delegate: SliverChildBuilderDelegate(
                (_, __) => const Padding(
                  padding: EdgeInsets.only(bottom: AppSpacing.md),
                  child: _SkeletonCard(grid: false),
                ),
                childCount: 3,
              ),
            ),
    );
  }
}

class _SkeletonCard extends StatefulWidget {
  final bool grid;
  const _SkeletonCard({required this.grid});

  @override
  State<_SkeletonCard> createState() => _SkeletonCardState();
}

class _SkeletonCardState extends State<_SkeletonCard>
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

  Widget _box({double? width, double? height, double radius = 6}) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
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
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(
            widget.grid ? AppRadius.md : AppRadius.lg),
        boxShadow: AppShadow.card,
      ),
      clipBehavior: Clip.antiAlias,
      child: widget.grid
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _box(width: double.infinity)),
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _box(width: 120, height: 12),
                      const SizedBox(height: 6),
                      _box(width: 80, height: 10),
                      const SizedBox(height: 6),
                      _box(width: 100, height: 10),
                    ],
                  ),
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      _box(width: 36, height: 36, radius: 18),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _box(width: 100, height: 12),
                          const SizedBox(height: 4),
                          _box(width: 70, height: 10),
                        ],
                      ),
                    ],
                  ),
                ),
                AspectRatio(
                    aspectRatio: 4 / 3,
                    child: _box(width: double.infinity, radius: 0)),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _box(width: 180, height: 12),
                      const SizedBox(height: 6),
                      _box(width: 140, height: 10),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

// ─── 정렬 칩 ─────────────────────────────────────────────────────────────────
// ─── 헤더 우측 프로필 아바타 (탭 → ProfileScreen push) ───────────────────
class _HeaderProfileAvatar extends StatelessWidget {
  const _HeaderProfileAvatar();

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final photoUrl = user?.photoURL;
    final name = user?.displayName ?? user?.email ?? '?';
    final hasPhoto = photoUrl != null && photoUrl.isNotEmpty;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ProfileScreen()),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              colors: [Color(0xFF1A73E8), Color(0xFF7C4DFF), Color(0xFFEC407A)],
            ),
          ),
          padding: const EdgeInsets.all(1.5),
          child: CircleAvatar(
            backgroundColor:
                Theme.of(context).colorScheme.surface,
            backgroundImage: hasPhoto ? NetworkImage(photoUrl) : null,
            child: !hasPhoto
                ? Text(
                    name[0].toUpperCase(),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  )
                : null,
          ),
        ),
      ),
    );
  }
}

// ─── 날짜 섹션 헤더 (1열 모드 + 날짜순) ──────────────────────────────────
class _DateSectionHeader extends StatelessWidget {
  final String label;
  const _DateSectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 4, 0, 10),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 14,
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              height: 1,
              color: AppColors.textDisabled.withValues(alpha: 0.3),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── 친구 그룹 가로 탭 바 (전체 + 사용자 정의 그룹) ─────────────────────
class _FriendGroupTabBar extends StatelessWidget {
  final List<FriendGroup> groups;
  final String? activeGroupId; // null = 전체
  final ValueChanged<String?> onSelect;

  const _FriendGroupTabBar({
    required this.groups,
    required this.activeGroupId,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(AppSpacing.md, 6, AppSpacing.md, 6),
        children: [
          _GroupTab(
            emoji: '🌐',
            label: '전체',
            selected: activeGroupId == null,
            onTap: () => onSelect(null),
          ),
          const SizedBox(width: 6),
          ...groups.map((g) => Padding(
                padding: const EdgeInsets.only(right: 6),
                child: _GroupTab(
                  emoji: g.emoji,
                  label: g.name,
                  modeEmoji: g.mode.emoji,
                  selected: activeGroupId == g.id,
                  onTap: () => onSelect(g.id),
                ),
              )),
        ],
      ),
    );
  }
}

class _GroupTab extends StatelessWidget {
  final String emoji;
  final String label;
  final String? modeEmoji;
  final bool selected;
  final VoidCallback onTap;

  const _GroupTab({
    required this.emoji,
    required this.label,
    required this.selected,
    required this.onTap,
    this.modeEmoji,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bg = selected ? cs.primary : cs.surfaceContainerHighest;
    final fg = selected ? cs.onPrimary : cs.onSurface;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(AppRadius.full),
          border: Border.all(
            color: selected ? cs.primary : cs.outlineVariant,
            width: 1,
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
                color: fg,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                letterSpacing: -0.2,
              ),
            ),
            if (modeEmoji != null) ...[
              const SizedBox(width: 4),
              Text(modeEmoji!, style: const TextStyle(fontSize: 11)),
            ],
          ],
        ),
      ),
    );
  }
}


// ─── 새 vlog 배너 ─────────────────────────────────────────────────────────
class _NewVlogBanner extends StatelessWidget {
  final int count;
  final VoidCallback onTap;
  const _NewVlogBanner({required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.md, 6, AppSpacing.md, 0),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.full),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF1A73E8), Color(0xFF34A853)],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
              borderRadius: BorderRadius.circular(AppRadius.full),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.3),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.arrow_upward,
                    size: 14, color: Colors.white),
                const SizedBox(width: 6),
                Text(
                  '✨ 새 브이로그 $count개 — 탭하여 확인',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── 홈 카테고리 필터 칩 ──────────────────────────────────────────────────
class _HomeCategoryChip extends StatelessWidget {
  final String label;
  final String emoji;
  final bool selected;
  final VoidCallback onTap;
  const _HomeCategoryChip({
    required this.label,
    required this.emoji,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // Outlined 스타일 — 그룹탭(solid 캡슐)과 시각 계층 구분
    // 미선택: 투명 배경 + 테두리만 / 선택: primary 연한 채움 + primary 테두리
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.full),
          border: Border.all(
            color: selected ? AppColors.primary : cs.outlineVariant,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 13)),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                color: selected ? AppColors.primary : cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SortChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final bool ascending; // 선택된 칩에만 의미 있음
  final VoidCallback onTap;
  const _SortChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.ascending,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(20),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.35),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  )
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 13,
                color: selected ? Colors.white : AppColors.textSecondary),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : AppColors.textSecondary,
              ),
            ),
            if (selected) ...[
              const SizedBox(width: 3),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                transitionBuilder: (child, anim) =>
                    ScaleTransition(scale: anim, child: child),
                child: Icon(
                  ascending ? Icons.arrow_upward : Icons.arrow_downward,
                  key: ValueKey(ascending),
                  size: 11,
                  color: Colors.white,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── 마커 색상 피커 ───────────────────────────────────────────────────────────
// ─── 1열/2열 토글 버튼 ───────────────────────────────────────────────────────
class _ViewToggleBtn extends StatelessWidget {
  final IconData icon;
  final bool active;
  final String tooltip;
  final VoidCallback onTap;
  const _ViewToggleBtn({
    required this.icon,
    required this.active,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 32,
          height: 32,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active
                ? AppColors.primary.withValues(alpha: 0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            size: 20,
            color: active ? AppColors.primary : AppColors.textDisabled,
          ),
        ),
      ),
    );
  }
}
