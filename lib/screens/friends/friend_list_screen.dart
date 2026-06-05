import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/friend_group.dart';
import '../../models/friendship.dart';
import '../../models/vlog.dart';
import '../../services/firestore_service.dart';
import '../../services/friend_group_service.dart';
import '../../services/friend_service.dart';
import '../../utils/constants.dart';
import '../../utils/invite.dart';
import '../../utils/marker_emojis.dart';
import '../../utils/sheets.dart';
import 'friend_groups_screen.dart';
import 'friend_search_screen.dart';

/// 친구 목록 화면 — 친구 / 받은 요청 / 보낸 요청 3탭
class FriendListScreen extends StatefulWidget {
  const FriendListScreen({super.key});

  @override
  State<FriendListScreen> createState() => _FriendListScreenState();
}

class _FriendListScreenState extends State<FriendListScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl = TabController(length: 3, vsync: this);
  int _incomingCount = 0;

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.surface,
        elevation: 0,
        scrolledUnderElevation: 1,
        title: const Text(
          '친구',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.ios_share, color: AppColors.primary),
            tooltip: '친구 초대',
            onPressed: AppInvite.share,
          ),
          IconButton(
            icon: const Icon(Icons.group_work_outlined,
                color: AppColors.primary),
            tooltip: '그룹 관리',
            onPressed: () {
              HapticFeedback.selectionClick();
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const FriendGroupsScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.person_add_outlined,
                color: AppColors.primary),
            tooltip: '친구 추가',
            onPressed: () {
              HapticFeedback.selectionClick();
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const FriendSearchScreen()),
              );
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabCtrl,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textSecondary,
          indicatorColor: AppColors.primary,
          labelStyle:
              const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          tabs: [
            const Tab(text: '친구'),
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('요청'),
                  if (_incomingCount > 0) ...[
                    const SizedBox(width: 5),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.error,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '$_incomingCount',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const Tab(text: '보낸 요청'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [
          _AcceptedFriendsTab(),
          _IncomingTab(onCount: (n) {
            if (mounted && n != _incomingCount) {
              setState(() => _incomingCount = n);
            }
          }),
          _OutgoingTab(),
        ],
      ),
    );
  }
}

// ─── 친구 탭 ──────────────────────────────────────────────────────────────────

class _AcceptedFriendsTab extends StatefulWidget {
  @override
  State<_AcceptedFriendsTab> createState() => _AcceptedFriendsTabState();
}

class _AcceptedFriendsTabState extends State<_AcceptedFriendsTab> {
  String _query = '';
  String? _groupFilter; // FriendGroup id, null = 전체
  FriendRelType? _modeFilter; // 위치 모드, null = 전체
  List<FriendGroup> _groups = [];
  StreamSubscription<List<FriendGroup>>? _groupsSub;

  static const _hintKey = 'friend_group_longpress_hint_dismissed_v1';
  bool _hintDismissed = true; // 기본 true → 로드 전 깜빡임 방지

  @override
  void initState() {
    super.initState();
    _loadHint();
    _groupsSub = FriendGroupService.watchMyGroups().listen((g) {
      if (!mounted) return;
      setState(() {
        _groups = g;
        // 선택한 그룹이 삭제됐으면 전체로 복귀
        if (_groupFilter != null && !g.any((e) => e.id == _groupFilter)) {
          _groupFilter = null;
        }
      });
    });
  }

  Future<void> _loadHint() async {
    final prefs = await SharedPreferences.getInstance();
    final dismissed = prefs.getBool(_hintKey) ?? false;
    if (mounted) setState(() => _hintDismissed = dismissed);
  }

  Future<void> _dismissHint() async {
    setState(() => _hintDismissed = true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_hintKey, true);
  }

  @override
  void dispose() {
    _groupsSub?.cancel();
    super.dispose();
  }

  bool _matches(Friendship f) {
    if (_query.isEmpty) return true;
    final q = _query.toLowerCase();
    final name = f.effectiveName.toLowerCase();
    final orig = (f.displayName ?? '').toLowerCase();
    final email = (f.email ?? '').toLowerCase();
    return name.contains(q) || orig.contains(q) || email.contains(q);
  }

  FriendGroup? get _activeGroup {
    if (_groupFilter == null) return null;
    for (final g in _groups) {
      if (g.id == _groupFilter) return g;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Friendship>>(
      stream: FriendService.watchMyFriends(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(
              child: CircularProgressIndicator(color: AppColors.primary));
        }
        final all = snap.data ?? [];
        if (all.isEmpty) {
          return _EmptyState(
            icon: Icons.people_outline,
            title: '아직 친구가 없어요',
            message: '이메일로 친구를 검색하거나,\n링크로 친구를 초대해보세요',
            actionLabel: '친구 추가',
            onAction: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const FriendSearchScreen()),
              );
            },
            secondaryLabel: '친구 초대하기',
            onSecondary: AppInvite.share,
          );
        }

        // 1) 검색 → 2) 그룹 필터
        var list = all.where(_matches).toList();
        final grp = _activeGroup;
        if (grp != null) {
          final members = grp.memberUids.toSet();
          list = list.where((f) => members.contains(f.friendUid)).toList();
        }

        // 위치 모드별 분리 (그룹 필터 적용 후 기준)
        final best =
            list.where((f) => f.relType == FriendRelType.best).toList();
        final normal =
            list.where((f) => f.relType == FriendRelType.normal).toList();
        final bad =
            list.where((f) => f.relType == FriendRelType.bad).toList();

        // 모드 필터 적용된 섹션 구성
        final sections = <Widget>[];
        void addSection(FriendRelType t, List<Friendship> fs) {
          if (fs.isEmpty) return;
          if (_modeFilter != null && _modeFilter != t) return;
          sections.add(_GroupSection(relType: t, friends: fs));
        }

        addSection(FriendRelType.best, best);
        addSection(FriendRelType.normal, normal);
        addSection(FriendRelType.bad, bad);

        return Column(
          children: [
            // 검색바
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: TextField(
                onChanged: (v) => setState(() => _query = v.trim()),
                style: const TextStyle(fontSize: 14),
                decoration: InputDecoration(
                  hintText: '${all.length}명의 친구 검색',
                  hintStyle: const TextStyle(
                      fontSize: 13, color: AppColors.textSecondary),
                  prefixIcon: const Icon(Icons.search,
                      size: 18, color: AppColors.textSecondary),
                  filled: true,
                  fillColor:
                      Theme.of(context).colorScheme.surfaceContainerHighest,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.full),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            // 위치 모드 필터 칩 (베프/부끄럼/잠수)
            _ModeFilterBar(
              selected: _modeFilter,
              bestCount: best.length,
              normalCount: normal.length,
              badCount: bad.length,
              onSelect: (m) {
                HapticFeedback.selectionClick();
                setState(() => _modeFilter = m);
              },
            ),
            // 그룹 필터 칩 (사용자가 만든 그룹이 있을 때만)
            if (_groups.isNotEmpty)
              _GroupFilterBar(
                groups: _groups,
                allFriends: all,
                selected: _groupFilter,
                onSelect: (id) {
                  HapticFeedback.selectionClick();
                  setState(() => _groupFilter = id);
                },
              ),
            // 멤버 편집 발견성 힌트 (그룹 있을 때 1회, 닫으면 다시 안 뜸)
            if (_groups.isNotEmpty && !_hintDismissed)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF7C4DFF).withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(AppRadius.full),
                  ),
                  child: Row(
                    children: [
                      const Text('💡', style: TextStyle(fontSize: 12)),
                      const SizedBox(width: 6),
                      const Expanded(
                        child: Text(
                          '그룹 칩을 길게 누르면 멤버를 편집할 수 있어요',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF7C4DFF),
                          ),
                        ),
                      ),
                      InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: _dismissHint,
                        child: const Padding(
                          padding: EdgeInsets.all(4),
                          child: Icon(Icons.close,
                              size: 15, color: Color(0xFF7C4DFF)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            Expanded(
              child: sections.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.xl),
                        child: Text(
                          _query.isNotEmpty
                              ? '검색 결과가 없어요'
                              : '이 필터에 해당하는 친구가 없어요',
                          style: const TextStyle(
                              fontSize: 13, color: AppColors.textSecondary),
                        ),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      children: [
                        ...sections,
                        const SizedBox(height: 24),
                      ],
                    ),
            ),
          ],
        );
      },
    );
  }
}

// ─── 위치 모드 필터 바 (전체 / 베프 / 부끄럼 / 잠수) ──────────────────────────
class _ModeFilterBar extends StatelessWidget {
  final FriendRelType? selected;
  final int bestCount;
  final int normalCount;
  final int badCount;
  final ValueChanged<FriendRelType?> onSelect;
  const _ModeFilterBar({
    required this.selected,
    required this.bestCount,
    required this.normalCount,
    required this.badCount,
    required this.onSelect,
  });

  static Color _colorOf(FriendRelType t) => switch (t) {
        FriendRelType.best => const Color(0xFFEC407A),
        FriendRelType.normal => const Color(0xFF1A73E8),
        FriendRelType.bad => const Color(0xFF42A5F5),
      };

  @override
  Widget build(BuildContext context) {
    final total = bestCount + normalCount + badCount;
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        children: [
          _FriendFilterChip(
            label: '전체 $total',
            selected: selected == null,
            color: AppColors.primary,
            onTap: () => onSelect(null),
          ),
          const SizedBox(width: 6),
          for (final t in FriendRelType.values) ...[
            _FriendFilterChip(
              emoji: t.emoji,
              label:
                  '${t.label} ${switch (t) { FriendRelType.best => bestCount, FriendRelType.normal => normalCount, FriendRelType.bad => badCount }}',
              selected: selected == t,
              color: _colorOf(t),
              onTap: () => onSelect(selected == t ? null : t),
            ),
            const SizedBox(width: 6),
          ],
        ],
      ),
    );
  }
}

// ─── 그룹 필터 바 (전체 / 사용자 정의 그룹들) ────────────────────────────────
class _GroupFilterBar extends StatelessWidget {
  final List<FriendGroup> groups;
  final List<Friendship> allFriends; // 멤버 편집 picker 용
  final String? selected; // group id
  final ValueChanged<String?> onSelect;
  const _GroupFilterBar({
    required this.groups,
    required this.allFriends,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        children: [
          _FriendFilterChip(
            emoji: '👥',
            label: '전체 그룹',
            selected: selected == null,
            color: const Color(0xFF7C4DFF),
            onTap: () => onSelect(null),
          ),
          const SizedBox(width: 6),
          for (final g in groups) ...[
            _FriendFilterChip(
              emoji: g.emoji,
              label: '${g.name} ${g.memberUids.length}',
              selected: selected == g.id,
              color: const Color(0xFF7C4DFF),
              onTap: () => onSelect(selected == g.id ? null : g.id),
              // 길게 누르면 멤버 일괄 편집 시트
              onLongPress: () {
                HapticFeedback.mediumImpact();
                _GroupMemberPicker.show(context, g, allFriends);
              },
            ),
            const SizedBox(width: 6),
          ],
        ],
      ),
    );
  }
}

// ─── 그룹 멤버 일괄 편집 시트 (그룹 칩 롱프레스) ──────────────────────────────
class _GroupMemberPicker {
  static Future<void> show(
    BuildContext context,
    FriendGroup group,
    List<Friendship> friends,
  ) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => _GroupMemberPickerBody(group: group, friends: friends),
    );
  }
}

class _GroupMemberPickerBody extends StatefulWidget {
  final FriendGroup group;
  final List<Friendship> friends;
  const _GroupMemberPickerBody({required this.group, required this.friends});

  @override
  State<_GroupMemberPickerBody> createState() => _GroupMemberPickerBodyState();
}

class _GroupMemberPickerBodyState extends State<_GroupMemberPickerBody> {
  late final Set<String> _selected =
      widget.group.memberUids.toSet();
  bool _saving = false;

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await FriendGroupService.setGroupMembers(
        groupId: widget.group.id,
        memberUids: _selected.toList(),
      );
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${widget.group.name} 멤버 ${_selected.length}명으로 저장했어요')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('저장 실패: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final h = MediaQuery.of(context).size.height;
    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: h * 0.8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.textDisabled.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
              child: Row(
                children: [
                  Text(widget.group.emoji,
                      style: const TextStyle(fontSize: 20)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${widget.group.name} 멤버 편집',
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w800),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text('${_selected.length}명',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: cs.primary)),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: widget.friends.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(32),
                      child: Text('친구가 없어요',
                          style: TextStyle(
                              color: AppColors.textSecondary, fontSize: 13)),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: widget.friends.length,
                      itemBuilder: (_, i) {
                        final f = widget.friends[i];
                        final on = _selected.contains(f.friendUid);
                        return CheckboxListTile(
                          value: on,
                          activeColor: cs.primary,
                          controlAffinity: ListTileControlAffinity.trailing,
                          onChanged: (v) {
                            HapticFeedback.selectionClick();
                            setState(() {
                              if (v == true) {
                                _selected.add(f.friendUid);
                              } else {
                                _selected.remove(f.friendUid);
                              }
                            });
                          },
                          secondary: _FriendAvatar(
                            name: f.effectiveName,
                            photoUrl: f.photoUrl,
                            size: 38,
                          ),
                          title: Text(
                            f.effectiveName,
                            style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w600),
                          ),
                          subtitle: f.email != null
                              ? Text(f.email!,
                                  style: const TextStyle(fontSize: 11),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis)
                              : null,
                        );
                      },
                    ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _saving ? null : _save,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Text('저장',
                            style: TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w700)),
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

// ─── 친구 필터 칩 (공용) ──────────────────────────────────────────────────────
class _FriendFilterChip extends StatelessWidget {
  final String label;
  final String? emoji;
  final bool selected;
  final Color color;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  const _FriendFilterChip({
    required this.label,
    this.emoji,
    required this.selected,
    required this.color,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? color.withValues(alpha: 0.15)
              : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppRadius.full),
          border: Border.all(
            color: selected ? color : Colors.transparent,
            width: 1.2,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (emoji != null) ...[
              Text(emoji!, style: const TextStyle(fontSize: 13)),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: selected ? color : cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── 그룹 섹션 (헤더 + 친구 목록) ───────────────────────────────────────────

class _GroupSection extends StatelessWidget {
  final FriendRelType relType;
  final List<Friendship> friends;
  const _GroupSection({required this.relType, required this.friends});

  Color get _color => switch (relType) {
        FriendRelType.best => const Color(0xFFEC407A),
        FriendRelType.normal => const Color(0xFF1A73E8),
        FriendRelType.bad => const Color(0xFF42A5F5),
      };

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
          child: Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: _color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: _color.withValues(alpha: 0.4), width: 0.8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(relType.emoji,
                        style: const TextStyle(fontSize: 12)),
                    const SizedBox(width: 4),
                    Text(
                      relType.label,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: _color,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '${friends.length}명',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        ...friends.expand((f) => [
              _FriendTile(
                friendship: f,
                mode: _FriendTileMode.accepted,
              ),
              if (f != friends.last)
                const Divider(
                    height: 1,
                    indent: 76,
                    endIndent: 16,
                    color: AppColors.surfaceVariant),
            ]),
      ],
    );
  }
}

// ─── 받은 요청 탭 ──────────────────────────────────────────────────────────────

class _IncomingTab extends StatelessWidget {
  final ValueChanged<int> onCount;
  const _IncomingTab({required this.onCount});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Friendship>>(
      stream: FriendService.watchIncomingRequests(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(
              child: CircularProgressIndicator(color: AppColors.primary));
        }
        final list = snap.data ?? [];
        WidgetsBinding.instance.addPostFrameCallback((_) => onCount(list.length));
        if (list.isEmpty) {
          return const _EmptyState(
            icon: Icons.inbox_outlined,
            title: '받은 요청 없음',
            message: '누군가 친구 요청을 보내면 여기에 표시됩니다',
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: list.length,
          separatorBuilder: (_, __) => const Divider(
              height: 1,
              indent: 76,
              endIndent: 16,
              color: AppColors.surfaceVariant),
          itemBuilder: (_, i) => _FriendTile(
            friendship: list[i],
            mode: _FriendTileMode.incoming,
          ),
        );
      },
    );
  }
}

// ─── 보낸 요청 탭 ──────────────────────────────────────────────────────────────

class _OutgoingTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Friendship>>(
      stream: FriendService.watchOutgoingRequests(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(
              child: CircularProgressIndicator(color: AppColors.primary));
        }
        final list = snap.data ?? [];
        if (list.isEmpty) {
          return const _EmptyState(
            icon: Icons.outbox_outlined,
            title: '보낸 요청 없음',
            message: '친구 추가 버튼으로 요청을 보내보세요',
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: list.length,
          separatorBuilder: (_, __) => const Divider(
              height: 1,
              indent: 76,
              endIndent: 16,
              color: AppColors.surfaceVariant),
          itemBuilder: (_, i) => _FriendTile(
            friendship: list[i],
            mode: _FriendTileMode.outgoing,
          ),
        );
      },
    );
  }
}

// ─── 친구 타일 ────────────────────────────────────────────────────────────────

enum _FriendTileMode { accepted, incoming, outgoing }

class _FriendTile extends StatelessWidget {
  final Friendship friendship;
  final _FriendTileMode mode;
  const _FriendTile({required this.friendship, required this.mode});

  Future<void> _accept(BuildContext context) async {
    HapticFeedback.lightImpact();
    try {
      await FriendService.acceptRequest(friendship.friendUid);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('🎉 ${friendship.effectiveName}님과 친구가 되었습니다'),
            backgroundColor: AppColors.secondary,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('수락 실패: $e'),
              backgroundColor: AppColors.error),
        );
      }
    }
  }

  Future<void> _reject(BuildContext context) async {
    HapticFeedback.selectionClick();
    final ok = await AppSheets.confirm(
      context,
      icon: Icons.close,
      title: '요청 거절',
      message: '${friendship.effectiveName}님의 요청을 거절합니다',
      confirmLabel: '거절',
      dangerous: true,
    );
    if (ok != true) return;
    try {
      await FriendService.removeFriendship(friendship.friendUid);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('거절 실패: $e'),
              backgroundColor: AppColors.error),
        );
      }
    }
  }

  Future<void> _cancel(BuildContext context) async {
    HapticFeedback.selectionClick();
    final ok = await AppSheets.confirm(
      context,
      icon: Icons.undo,
      title: '요청 취소',
      message: '${friendship.effectiveName}님에게 보낸 요청을 취소합니다',
      confirmLabel: '취소하기',
      dangerous: true,
    );
    if (ok != true) return;
    try {
      await FriendService.removeFriendship(friendship.friendUid);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('취소 실패: $e'),
              backgroundColor: AppColors.error),
        );
      }
    }
  }

  Future<void> _remove(BuildContext context) async {
    HapticFeedback.mediumImpact();
    final ok = await AppSheets.confirm(
      context,
      icon: Icons.person_remove_outlined,
      title: '${friendship.effectiveName} 친구 삭제',
      message: '친구 관계가 해제되며 서로의 위치/피드가 더 이상 보이지 않습니다',
      confirmLabel: '삭제',
      dangerous: true,
    );
    if (ok != true) return;
    try {
      await FriendService.removeFriendship(friendship.friendUid);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('삭제 실패: $e'),
              backgroundColor: AppColors.error),
        );
      }
    }
  }

  /// 타일 서브타이틀 — 별명 있으면 원래이름+email, 없으면 email
  /// accepted 친구는 하단에 좋아요/댓글 활동 미리보기도 함께 표시
  Widget? _buildTileSubtitle() {
    final hasNickname = friendship.nicknameByMe != null &&
        friendship.nicknameByMe!.isNotEmpty;
    final hasEmail =
        friendship.email != null && friendship.email!.isNotEmpty;
    final showActivity = mode == _FriendTileMode.accepted;

    Widget? infoRow;
    if (hasNickname && friendship.displayName != null) {
      infoRow = Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              friendship.displayName!,
              style: const TextStyle(
                fontSize: 10,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (hasEmail) ...[
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                friendship.email!,
                style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textDisabled),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      );
    } else if (hasEmail) {
      infoRow = Text(friendship.email!,
          style: const TextStyle(
              fontSize: 12, color: AppColors.textSecondary),
          maxLines: 1,
          overflow: TextOverflow.ellipsis);
    }

    if (!showActivity) return infoRow;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (infoRow != null) ...[
          infoRow,
          const SizedBox(height: 2),
        ],
        _FriendActivityStats(friendUid: friendship.friendUid),
      ],
    );
  }

  /// 별명 입력 시트
  Future<void> _editNickname(BuildContext context) async {
    HapticFeedback.selectionClick();
    final newName = await AppSheets.textInput(
      context,
      title: friendship.nicknameByMe == null ||
              friendship.nicknameByMe!.isEmpty
          ? '별명 설정'
          : '별명 변경',
      hint: '예: 우리오빠, 자기, 김대리',
      initial: friendship.nicknameByMe ?? '',
      maxLength: 20,
      icon: Icons.edit_outlined,
    );
    if (newName == null || !context.mounted) return;
    try {
      final trimmed = newName.trim();
      await FriendService.setNickname(
        friendship.friendUid,
        trimmed.isEmpty ? null : trimmed,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(trimmed.isEmpty
                ? '🔄 별명을 초기화했습니다'
                : '✏️ 별명을 "$trimmed"(으)로 변경했습니다'),
            backgroundColor: AppColors.secondary,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('별명 변경 실패: $e'),
            backgroundColor: AppColors.error));
      }
    }
  }

  /// 그룹/개별/삭제 메뉴 (우선순위: 개별 > 마스터 > 그룹)
  Future<void> _showMenu(BuildContext context) async {
    HapticFeedback.selectionClick();
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.textDisabled.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 14),
              // 친구 정보 헤더
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    _FriendAvatar(
                      name: friendship.effectiveName,
                      photoUrl: friendship.photoUrl,
                      size: 44,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(friendship.effectiveName,
                              style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800)),
                          if (friendship.email != null &&
                              friendship.email!.isNotEmpty)
                            Text(friendship.email!,
                                style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textSecondary)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              // ── 그룹 변경 ────────────────────────────────────────
              const _SectionLabel(
                title: '그룹 변경',
                subtitle: '관계의 기본 베이스라인',
              ),
              ...FriendRelType.values.map((t) => _RelTypeTile(
                    relType: t,
                    selected: friendship.relType == t,
                    onTap: () => Navigator.pop(sheetCtx, 'group:${t.value}'),
                  )),
              const SizedBox(height: 16),
              // ── 개별 오버라이드 ───────────────────────────────────
              const _SectionLabel(
                title: '이 친구만 특별 관리',
                subtitle: '그룹/마스터 설정보다 우선 적용 (최상위)',
              ),
              ...FriendIndividualMode.values.map((m) => _IndividualTile(
                    mode: m,
                    selected: friendship.individualMode == m,
                    onTap: () =>
                        Navigator.pop(sheetCtx, 'indiv:${m.value}'),
                  )),
              const SizedBox(height: 14),
              // ── 별명 변경 ────────────────────────────────────────
              const Divider(height: 1),
              ListTile(
                leading: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.edit_outlined,
                      color: AppColors.primary, size: 18),
                ),
                title: Text(
                    friendship.nicknameByMe != null &&
                            friendship.nicknameByMe!.isNotEmpty
                        ? '별명 변경'
                        : '별명 설정',
                    style:
                        const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: friendship.nicknameByMe != null &&
                        friendship.nicknameByMe!.isNotEmpty
                    ? Text(
                        '현재: ${friendship.nicknameByMe}',
                        style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary),
                      )
                    : null,
                onTap: () => Navigator.pop(sheetCtx, 'nickname'),
              ),
              if (friendship.nicknameByMe != null &&
                  friendship.nicknameByMe!.isNotEmpty)
                ListTile(
                  leading: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.textDisabled
                          .withValues(alpha: 0.20),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.refresh,
                        color: AppColors.textSecondary, size: 18),
                  ),
                  title: const Text('별명 초기화',
                      style: TextStyle(
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w500)),
                  subtitle: Text(
                    '원래 이름(${friendship.displayName ?? "사용자"})으로 되돌리기',
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textSecondary),
                  ),
                  onTap: () => Navigator.pop(sheetCtx, 'clear_nickname'),
                ),
              // ── 친구 삭제 ────────────────────────────────────────
              const Divider(height: 1),
              ListTile(
                leading: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.person_remove_outlined,
                      color: AppColors.error, size: 18),
                ),
                title: const Text('친구 삭제',
                    style: TextStyle(
                        color: AppColors.error,
                        fontWeight: FontWeight.w600)),
                onTap: () => Navigator.pop(sheetCtx, 'remove'),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );

    if (action == null || !context.mounted) return;

    if (action == 'remove') {
      await _remove(context);
      return;
    }

    if (action == 'nickname') {
      await _editNickname(context);
      return;
    }

    if (action == 'clear_nickname') {
      HapticFeedback.lightImpact();
      try {
        await FriendService.setNickname(friendship.friendUid, null);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  '🔄 별명을 원래 이름(${friendship.displayName ?? "사용자"})으로 되돌렸습니다'),
              backgroundColor: AppColors.secondary,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('초기화 실패: $e'),
              backgroundColor: AppColors.error));
        }
      }
      return;
    }

    if (action.startsWith('group:')) {
      final newType = FriendRelType.fromString(action.substring(6));
      if (newType == friendship.relType) return;
      HapticFeedback.lightImpact();
      try {
        await FriendService.changeRelType(friendship.friendUid, newType);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  '${newType.emoji} ${friendship.effectiveName}님을 ${newType.label} 그룹으로 변경'),
              backgroundColor: AppColors.secondary,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('그룹 변경 실패: $e'),
              backgroundColor: AppColors.error));
        }
      }
      return;
    }

    if (action.startsWith('indiv:')) {
      final newMode = FriendIndividualMode.fromString(action.substring(6));
      if (newMode == friendship.individualMode) return;
      HapticFeedback.lightImpact();
      try {
        await FriendService.changeIndividualMode(
            friendship.friendUid, newMode);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  '${newMode.emoji} ${friendship.effectiveName}님 개별 설정: ${newMode.label}'),
              backgroundColor: AppColors.secondary,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('개별 설정 실패: $e'),
              backgroundColor: AppColors.error));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: _FriendAvatar(
        name: friendship.effectiveName,
        photoUrl: friendship.photoUrl,
        size: 48,
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              friendship.effectiveName,
              style: const TextStyle(
                  fontWeight: FontWeight.w700),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // 개별 오버라이드 배지 (있을 때만, 그룹보다 우선되므로 강조)
          if (mode == _FriendTileMode.accepted &&
              friendship.individualMode != FriendIndividualMode.inherit) ...[
            const SizedBox(width: 6),
            _IndividualBadge(mode: friendship.individualMode),
          ],
          // 주요 카테고리 배지 (accepted 친구만)
          if (mode == _FriendTileMode.accepted) ...[
            const SizedBox(width: 6),
            _TopCategoryBadge(friendUid: friendship.friendUid),
          ],
        ],
      ),
      subtitle: _buildTileSubtitle(),
      trailing: switch (mode) {
        _FriendTileMode.incoming => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton(
                onPressed: () => _reject(context),
                child: const Text('거절',
                    style: TextStyle(color: AppColors.textSecondary)),
              ),
              const SizedBox(width: 4),
              ElevatedButton(
                onPressed: () => _accept(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 8),
                  minimumSize: Size.zero,
                  shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(AppRadius.full)),
                ),
                child: const Text('수락',
                    style: TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        _FriendTileMode.outgoing => TextButton.icon(
            onPressed: () => _cancel(context),
            icon: const Icon(Icons.schedule, size: 14,
                color: AppColors.textSecondary),
            label: const Text('요청 중',
                style: TextStyle(
                    fontSize: 12, color: AppColors.textSecondary)),
          ),
        _FriendTileMode.accepted => IconButton(
            icon: const Icon(Icons.more_horiz,
                color: AppColors.textSecondary),
            onPressed: () => _showMenu(context),
          ),
      },
    );
  }
}

// ─── 시트 섹션 라벨 ─────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String title;
  final String subtitle;
  const _SectionLabel({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── 개별 오버라이드 배지 (타일에 표시) ────────────────────────────────

class _IndividualBadge extends StatelessWidget {
  final FriendIndividualMode mode;
  const _IndividualBadge({required this.mode});

  Color get _color => switch (mode) {
        FriendIndividualMode.precise => const Color(0xFF34A853),
        FriendIndividualMode.ice => const Color(0xFF42A5F5),
        FriendIndividualMode.inherit => AppColors.textDisabled,
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [
          _color.withValues(alpha: 0.18),
          _color.withValues(alpha: 0.08),
        ]),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _color.withValues(alpha: 0.5), width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(mode.emoji, style: const TextStyle(fontSize: 11)),
          const SizedBox(width: 3),
          Text(
            mode == FriendIndividualMode.precise
                ? '정확'
                : (mode == FriendIndividualMode.ice ? '얼림' : '기본'),
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: _color,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── 개별 오버라이드 시트 옵션 타일 ──────────────────────────────────────

class _IndividualTile extends StatelessWidget {
  final FriendIndividualMode mode;
  final bool selected;
  final VoidCallback onTap;
  const _IndividualTile({
    required this.mode,
    required this.selected,
    required this.onTap,
  });

  Color get _color => switch (mode) {
        FriendIndividualMode.precise => const Color(0xFF34A853),
        FriendIndividualMode.ice => const Color(0xFF42A5F5),
        FriendIndividualMode.inherit => AppColors.textSecondary,
      };

  String get _description => switch (mode) {
        FriendIndividualMode.precise =>
          '내 마스터/그룹 설정과 무관하게 항상 정확한 위치 공유',
        FriendIndividualMode.ice =>
          '내 마스터/그룹 설정과 무관하게 항상 얼린 위치만 보임',
        FriendIndividualMode.inherit =>
          '그룹 + 마스터 스위치 설정을 그대로 따름 (권장)',
      };

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected
              ? _color.withValues(alpha: 0.10)
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? _color : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            Text(mode.emoji, style: const TextStyle(fontSize: 22)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    mode.label,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _description,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            if (selected) Icon(Icons.check_circle, color: _color, size: 20),
          ],
        ),
      ),
    );
  }
}

// ─── 그룹 (베프/일반/불편) 시트 옵션 타일 ────────────────────────────────

class _RelTypeTile extends StatelessWidget {
  final FriendRelType relType;
  final bool selected;
  final VoidCallback onTap;
  const _RelTypeTile({
    required this.relType,
    required this.selected,
    required this.onTap,
  });

  Color get _color => switch (relType) {
        FriendRelType.best => const Color(0xFFEC407A),
        FriendRelType.normal => const Color(0xFF1A73E8),
        FriendRelType.bad => const Color(0xFF42A5F5),
      };

  String get _description => switch (relType) {
        FriendRelType.best => '실시간 정확 위치 공유',
        FriendRelType.normal => '동·반경 단위 대략 위치 (기본)',
        FriendRelType.bad => '오프라인 / 마지막 위치 고정',
      };

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected
              ? _color.withValues(alpha: 0.10)
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? _color : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            Text(relType.emoji, style: const TextStyle(fontSize: 26)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    relType.label,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _description,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            if (selected)
              Icon(Icons.check_circle, color: _color, size: 22),
          ],
        ),
      ),
    );
  }
}

// ─── 빈 상태 ────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.secondaryLabel,
    this.onSecondary,
  });

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
              child: Icon(icon, size: 48, color: AppColors.primary),
            ),
            const SizedBox(height: 18),
            Text(title,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                )),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 13, color: AppColors.textSecondary),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 18),
              ElevatedButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.person_add_outlined, size: 18),
                label: Text(actionLabel!),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(AppRadius.full)),
                ),
              ),
            ],
            if (secondaryLabel != null && onSecondary != null) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: onSecondary,
                icon: const Icon(Icons.ios_share, size: 18),
                label: Text(secondaryLabel!),
                style: TextButton.styleFrom(
                    foregroundColor: AppColors.primary),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── 공용 친구 아바타 (FriendList + FriendSearch 등에서 사용) ────────────────

class _FriendAvatar extends StatelessWidget {
  final String name;
  final String? photoUrl;
  final double size;
  const _FriendAvatar({
    required this.name,
    this.photoUrl,
    this.size = 48,
  });

  @override
  Widget build(BuildContext context) {
    final hasPhoto = photoUrl != null && photoUrl!.isNotEmpty;
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
    final letter = (name.isNotEmpty ? name[0] : '?').toUpperCase();

    if (hasPhoto) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          image: DecorationImage(
            image: NetworkImage(photoUrl!),
            fit: BoxFit.cover,
          ),
        ),
      );
    }
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [color, Color.lerp(color, Colors.black, 0.25) ?? color],
        ),
      ),
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

// ─── 친구의 주요 카테고리 배지 ────────────────────────────────────────────
/// 친구의 최근 vlog 30개에서 가장 많이 나온 카테고리 1개를 작은 칩으로 노출.
// ─── 친구 활동 미리보기 (subtitle 하단 라인) ─────────────────────────
/// 친구의 vlog 합계 ❤️ 좋아요 + 💬 댓글 + 📸 vlog 수 표시
class _FriendActivityStats extends StatefulWidget {
  final String friendUid;
  const _FriendActivityStats({required this.friendUid});

  @override
  State<_FriendActivityStats> createState() => _FriendActivityStatsState();
}

class _FriendActivityStatsState extends State<_FriendActivityStats> {
  int _totalLikes = 0;
  int _totalComments = 0;
  int _vlogCount = 0;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final vlogs = await FirestoreService.watchUserVlogs(widget.friendUid)
          .first
          .timeout(const Duration(seconds: 4),
              onTimeout: () => <Vlog>[]);
      if (!mounted) return;
      int likes = 0, comments = 0;
      for (final v in vlogs) {
        likes += v.likeCount;
        comments += v.commentCount;
      }
      setState(() {
        _totalLikes = likes;
        _totalComments = comments;
        _vlogCount = vlogs.length;
        _loaded = true;
      });
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded || _vlogCount == 0) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.movie_outlined,
            size: 12, color: AppColors.textSecondary),
        const SizedBox(width: 3),
        Text('$_vlogCount',
            style: const TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600)),
        const SizedBox(width: 8),
        const Icon(Icons.favorite,
            size: 11, color: Color(0xFFEC407A)),
        const SizedBox(width: 3),
        Text('$_totalLikes',
            style: TextStyle(
                fontSize: 11,
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w600)),
        const SizedBox(width: 8),
        const Icon(Icons.mode_comment_outlined,
            size: 11, color: AppColors.textSecondary),
        const SizedBox(width: 3),
        Text('$_totalComments',
            style: TextStyle(
                fontSize: 11,
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w600)),
      ],
    );
  }
}

class _TopCategoryBadge extends StatefulWidget {
  final String friendUid;
  const _TopCategoryBadge({required this.friendUid});

  @override
  State<_TopCategoryBadge> createState() => _TopCategoryBadgeState();
}

class _TopCategoryBadgeState extends State<_TopCategoryBadge> {
  MarkerEmoji? _top;
  int _count = 0;
  DateTime? _lastActivity;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final vlogs = await FirestoreService.watchUserVlogs(widget.friendUid)
          .first
          .timeout(const Duration(seconds: 4),
              onTimeout: () => <Vlog>[]);
      if (!mounted) return;
      if (vlogs.isEmpty) {
        setState(() => _loaded = true);
        return;
      }
      // 가장 최근 활동 시간 (정렬 없으면 max로)
      final newest = vlogs
          .map((v) => v.createdAt)
          .reduce((a, b) => a.isAfter(b) ? a : b);
      final counts = <String, int>{};
      for (final v in vlogs.take(30)) {
        final emoji = v.markerEmoji;
        if (emoji == null || emoji.isEmpty) continue;
        counts[emoji] = (counts[emoji] ?? 0) + 1;
      }
      if (counts.isEmpty) {
        setState(() {
          _lastActivity = newest;
          _loaded = true;
        });
        return;
      }
      final topEntry =
          counts.entries.reduce((a, b) => a.value >= b.value ? a : b);
      setState(() {
        _top = MarkerEmojis.fromEmoji(topEntry.key);
        _count = topEntry.value;
        _lastActivity = newest;
        _loaded = true;
      });
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  String _shortRelative(DateTime d) {
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 60) return '${diff.inMinutes}분';
    if (diff.inHours < 24) return '${diff.inHours}시간';
    if (diff.inDays < 7) return '${diff.inDays}일';
    return '${d.month}/${d.day}';
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded || _top == null) return const SizedBox.shrink();
    final t = _top!;
    final time = _lastActivity == null ? '' : ' · ${_shortRelative(_lastActivity!)}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: t.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.full),
        border: Border.all(color: t.color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(t.emoji, style: const TextStyle(fontSize: 10.5, height: 1.0)),
          const SizedBox(width: 3),
          Text(
            '${t.label} $_count$time',
            style: TextStyle(
              fontSize: 9.5,
              color: t.color,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}
