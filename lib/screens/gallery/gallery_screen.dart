import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geocoding/geocoding.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:geolocator/geolocator.dart';

import '../../models/friendship.dart';
import '../../models/vlog.dart';
import '../../screens/auth/login_screen.dart';
import '../../screens/friends/friend_list_screen.dart';
import '../../screens/vlog/vlog_player_screen.dart';
import '../../screens/vlog/vlog_player_swiper_screen.dart';
import '../../services/firestore_service.dart';
import '../../services/friend_service.dart';
import '../../services/location_service.dart';
import '../../utils/constants.dart';
import '../../utils/marker_emojis.dart';
import '../../widgets/map_controls.dart';

class GalleryScreen extends StatefulWidget {
  const GalleryScreen({super.key});

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl = TabController(length: 2, vsync: this);
  List<String>? _friendUids;
  StreamSubscription<List<Friendship>>? _friendsSub;
  String? _categoryFilter; // null = 전체

  @override
  void initState() {
    super.initState();
    _subscribeFriends();
  }

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

  @override
  void dispose() {
    _tabCtrl.dispose();
    _friendsSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: const Text(
          '갤러리',
          style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 18),
        ),
        bottom: TabBar(
          controller: _tabCtrl,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textSecondary,
          indicatorColor: AppColors.primary,
          tabs: const [
            Tab(icon: Icon(Icons.grid_on, size: 20), text: '그리드'),
            Tab(icon: Icon(Icons.map, size: 20), text: '포토맵'),
          ],
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    final me = FirebaseAuth.instance.currentUser;
    if (me == null) return const _GuestPanel();
    if (_friendUids == null) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.primary));
    }
    return StreamBuilder<List<Vlog>>(
      stream: FirestoreService.watchFriendsVlogs(
        friendUids: _friendUids!,
        myUid: me.uid,
        limit: 100,
      ),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
              child: CircularProgressIndicator(color: AppColors.primary));
        }
        final allVlogs = snapshot.data ?? [];
        // 카테고리 필터 적용
        final vlogs = _categoryFilter == null
            ? allVlogs
            : allVlogs.where((v) {
                if (v.markerEmoji == null) return _categoryFilter == '일반';
                return MarkerEmojis.fromEmoji(v.markerEmoji).category ==
                    _categoryFilter;
              }).toList();
        return Column(
          children: [
            // 카테고리 칩 행
            SizedBox(
              height: 42,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md, vertical: 6),
                children: [
                  _GalleryCategoryChip(
                    label: '전체',
                    emoji: '🌐',
                    selected: _categoryFilter == null,
                    onTap: () => setState(() => _categoryFilter = null),
                  ),
                  const SizedBox(width: 6),
                  ...MarkerEmojis.groups.map((g) => Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: _GalleryCategoryChip(
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
            const Divider(height: 1),
            Expanded(
              child: TabBarView(
                controller: _tabCtrl,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _GridView(vlogs: vlogs),
                  _PhotoMapView(
                      vlogs: vlogs
                          .where((v) => v.lat != 0 || v.lng != 0)
                          .toList()),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 비로그인 패널 (갤러리 빈 상태)
// ─────────────────────────────────────────────────────────────────────────────
class _GuestPanel extends StatelessWidget {
  const _GuestPanel();

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
              '로그인 후 친구 갤러리를 만나보세요',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              '친구를 추가하면 그들의 사진/영상이\n여기에 표시됩니다',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 8,
              children: [
                ElevatedButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                  ),
                  icon: const Icon(Icons.login, size: 18),
                  label: const Text('로그인'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(AppRadius.full)),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const FriendListScreen()),
                  ),
                  icon: const Icon(Icons.people_outline, size: 18),
                  label: const Text('친구'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 그리드 뷰
// ─────────────────────────────────────────────────────────────────────────────

enum _SortMode { byDate, byDistance, byLikes, byViews }
enum _SortOrder { asc, desc }

class _GridView extends StatefulWidget {
  final List<Vlog> vlogs;
  const _GridView({required this.vlogs});

  @override
  State<_GridView> createState() => _GridViewState();
}

class _GridViewState extends State<_GridView> {
  _SortMode _sortMode = _SortMode.byDate;
  _SortOrder _sortOrder = _SortOrder.desc; // 날짜 기본: 최신순
  Position? _position;

  List<Vlog> get _sorted {
    final list = List<Vlog>.from(widget.vlogs);
    switch (_sortMode) {
      case _SortMode.byDistance:
        if (_position != null) {
          list.sort((a, b) {
            final da = Geolocator.distanceBetween(
                _position!.latitude, _position!.longitude, a.lat, a.lng);
            final db = Geolocator.distanceBetween(
                _position!.latitude, _position!.longitude, b.lat, b.lng);
            return _sortOrder == _SortOrder.asc
                ? da.compareTo(db)
                : db.compareTo(da);
          });
        }
        break;
      case _SortMode.byLikes:
        list.sort((a, b) => _sortOrder == _SortOrder.asc
            ? a.likeCount.compareTo(b.likeCount)
            : b.likeCount.compareTo(a.likeCount));
        break;
      case _SortMode.byViews:
        list.sort((a, b) => _sortOrder == _SortOrder.asc
            ? a.viewCount.compareTo(b.viewCount)
            : b.viewCount.compareTo(a.viewCount));
        break;
      case _SortMode.byDate:
        list.sort((a, b) => _sortOrder == _SortOrder.asc
            ? a.createdAt.compareTo(b.createdAt)
            : b.createdAt.compareTo(a.createdAt));
        break;
    }
    return list;
  }

  /// 같은 모드 탭 → 오름/내림 토글 / 다른 모드 탭 → 모드 변경 + 기본 방향
  Future<void> _onSortTap(_SortMode mode) async {
    if (_sortMode == mode) {
      setState(() => _sortOrder =
          _sortOrder == _SortOrder.desc ? _SortOrder.asc : _SortOrder.desc);
      return;
    }
    final defaultOrder =
        mode == _SortMode.byDate ? _SortOrder.desc : _SortOrder.asc;
    if (mode == _SortMode.byDistance && _position == null) {
      final pos = await LocationService.getCurrentPosition(context);
      if (!mounted) return;
      setState(() {
        _position = pos;
        _sortMode = mode;
        _sortOrder = defaultOrder;
      });
    } else {
      setState(() {
        _sortMode = mode;
        _sortOrder = defaultOrder;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.vlogs.isEmpty) return const _EmptyState();

    return Column(
      children: [
        // 정렬 헤더
        _SortBar(
            current: _sortMode,
            order: _sortOrder,
            onChanged: _onSortTap),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(AppSpacing.sm),
            itemCount: _sorted.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 3,
              mainAxisSpacing: 3,
            ),
            itemBuilder: (_, i) =>
                _GridTile(vlog: _sorted[i], playlist: _sorted),
          ),
        ),
      ],
    );
  }
}

class _GridTile extends StatelessWidget {
  final Vlog vlog;
  final List<Vlog>? playlist;
  const _GridTile({required this.vlog, this.playlist});

  bool get _isVideo => (vlog.videoUrl ?? '').isNotEmpty;
  String get _thumbUrl => vlog.thumbnailUrl ?? '';

  Future<void> _onLongPress(BuildContext context) async {
    // 본인 브이로그만 삭제 가능
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid != vlog.authorId) return;

    HapticFeedback.mediumImpact();
    final ok = await showModalBottomSheet<bool>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (sheetCtx) => SafeArea(
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
            const SizedBox(height: 18),
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.delete_outline,
                  color: AppColors.error, size: 24),
            ),
            const SizedBox(height: 12),
            Text(
              '"${vlog.title}" 삭제',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 6),
            const Text(
              '영상·사진 파일도 함께 삭제됩니다.\n복구할 수 없습니다.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 22),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(sheetCtx, false),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: BorderSide(
                            color: AppColors.textDisabled
                                .withValues(alpha: 0.5)),
                        shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(AppRadius.full)),
                      ),
                      child: const Text('취소',
                          style: TextStyle(
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w600)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        HapticFeedback.mediumImpact();
                        Navigator.pop(sheetCtx, true);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.error,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(AppRadius.full)),
                        elevation: 2,
                      ),
                      child: const Text('삭제',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
    if (ok == true && context.mounted) {
      await FirestoreService.deleteVlog(vlog.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        VlogPlayerSwiperScreen.open(
          context,
          vlogs: playlist ?? [vlog],
          initial: vlog,
        );
      },
      onLongPress: () => _onLongPress(context),
      child: Hero(
        tag: 'vlog_media_${vlog.id}',
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 썸네일
            _thumbUrl.isNotEmpty
                ? Image.network(
                    _thumbUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stack) => _placeholderBox(),
                  )
                : _placeholderBox(),

            // 좌상단: 영상 ▶ 또는 멀티 사진 ▣
            if (_isVideo)
              Positioned(
                top: 4,
                left: 4,
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: Colors.black.withAlpha(140),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.play_arrow_rounded,
                      size: 14, color: Colors.white),
                ),
              )
            else if (vlog.photoUrls.length > 1)
              Positioned(
                top: 4,
                right: 4,
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: Colors.black.withAlpha(140),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.collections,
                      size: 13, color: Colors.white),
                ),
              ),

            // 우하단: 영상 길이 또는 GPS 배지
            if (_isVideo &&
                vlog.durationSeconds != null &&
                vlog.durationSeconds! > 0)
              Positioned(
                bottom: 4,
                right: 4,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black.withAlpha(150),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    _fmtDuration(vlog.durationSeconds!),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              )
            else if (vlog.hasGpsTrack)
              Positioned(
                bottom: 4,
                right: 4,
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: Colors.black.withAlpha(140),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.gps_fixed,
                      size: 10, color: AppColors.secondary),
                ),
              ),
          ],
        ),
      ),
    );
  }

  static String _fmtDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Widget _placeholderBox() {
    return Container(
      color: AppColors.surfaceVariant,
      child: Center(
        child: Icon(
          _isVideo ? Icons.videocam : Icons.photo,
          size: 28,
          color: AppColors.textDisabled,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 포토맵 뷰
// ─────────────────────────────────────────────────────────────────────────────

class _PhotoMapView extends StatefulWidget {
  final List<Vlog> vlogs;
  const _PhotoMapView({required this.vlogs});

  @override
  State<_PhotoMapView> createState() => _PhotoMapViewState();
}

class _PhotoMapViewState extends State<_PhotoMapView> {
  Vlog? _selected;
  Set<Marker> _markers = {};
  double _zoom = 13.0;
  /// 단일 vlog 썸네일 마커 캐시 (vlog.id → BitmapDescriptor)
  final Map<String, BitmapDescriptor> _iconCache = {};
  GoogleMapController? _mapController;
  MapType _mapType = MapType.normal;
  LatLng _mapCenter = const LatLng(37.5665, 126.9780);
  LatLng? _currentLatLng;   // 현재 위치 (null이면 vlog 평균)
  LatLng? _pendingLocation; // 지도 준비 전에 GPS 도착 시 임시 저장
  double _pixelRatio = 3.0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _pixelRatio = MediaQuery.of(context).devicePixelRatio;
  }

  @override
  void initState() {
    super.initState();
    _rebuildMarkers();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initLocation());
  }

  Future<void> _initLocation() async {
    final pos = await LocationService.getCurrentPosition(context);
    if (pos == null || !mounted) return;
    final latlng = LatLng(pos.latitude, pos.longitude);
    setState(() => _currentLatLng = latlng);
    if (_mapController != null) {
      _mapController!.animateCamera(CameraUpdate.newLatLng(latlng));
    } else {
      _pendingLocation = latlng;
    }
  }

  @override
  void didUpdateWidget(_PhotoMapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.vlogs != widget.vlogs) _rebuildMarkers();
  }

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }

  // ─── 클러스터링 ──────────────────────────────────────────────────────────

  List<_GalleryCluster> _computeClusters() {
    final vlogs = widget.vlogs;
    if (vlogs.isEmpty) return [];
    final radius = 0.6 / math.pow(2, _zoom - 8);
    final groups = <_GalleryCluster>[];
    final assigned = <String>{};

    for (final v in vlogs) {
      if (assigned.contains(v.id)) continue;
      final nearby = vlogs.where((o) {
        if (assigned.contains(o.id)) return false;
        return (v.lat - o.lat).abs() <= radius &&
            (v.lng - o.lng).abs() <= radius;
      }).toList();
      for (final n in nearby) { assigned.add(n.id); }
      groups.add(_GalleryCluster(nearby));
    }
    return groups;
  }

  Future<void> _rebuildMarkers() async {
    final groups = _computeClusters();
    final markers = await Future.wait(groups.map(_toMarker));
    if (mounted) setState(() => _markers = markers.toSet());
  }

  Future<Marker> _toMarker(_GalleryCluster group) async {
    BitmapDescriptor icon;

    if (group.isSingle) {
      final vlog = group.vlogs.first;
      // 캐시된 썸네일 마커가 있으면 재사용
      icon = _iconCache[vlog.id] ??= await _thumbnailMarkerBitmap(
        vlog.thumbnailUrl ?? '',
        vlog.hasVideo,
        _pixelRatio,
      );
    } else {
      icon = await _clusterBitmap(group.count, _pixelRatio);
    }

    return Marker(
      markerId: MarkerId(group.id),
      position: group.center,
      icon: icon,
      // 단일: 꼬리 끝(하단 중앙)이 좌표를 가리킴 / 클러스터: 원 중심
      anchor: group.isSingle
          ? const Offset(0.5, 1.0)
          : const Offset(0.5, 0.5),
      onTap: () {
        if (group.isSingle) {
          setState(() => _selected = group.vlogs.first);
        } else if (_wouldClusterAtMaxZoom(group)) {
          _showClusterList(group.vlogs);
        } else {
          // 한 번에 클러스터 멤버 전체 영역으로 줌 → 즉시 분기
          _fitToCluster(group);
        }
      },
    );
  }

  /// 클러스터 멤버 전체를 화면에 꽉 차게 줌 (한 번 탭으로 분기).
  void _fitToCluster(_GalleryCluster group) {
    final ctrl = _mapController;
    if (ctrl == null) return;
    double minLat = group.vlogs.first.lat, maxLat = minLat;
    double minLng = group.vlogs.first.lng, maxLng = minLng;
    for (final v in group.vlogs) {
      minLat = math.min(minLat, v.lat);
      maxLat = math.max(maxLat, v.lat);
      minLng = math.min(minLng, v.lng);
      maxLng = math.max(maxLng, v.lng);
    }
    // 너무 작은 범위는 약간 패딩(0 크기 bounds 방지)
    const eps = 0.0004;
    if ((maxLat - minLat).abs() < eps) {
      minLat -= eps;
      maxLat += eps;
    }
    if ((maxLng - minLng).abs() < eps) {
      minLng -= eps;
      maxLng += eps;
    }
    final bounds = LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );
    ctrl.animateCamera(CameraUpdate.newLatLngBounds(bounds, 90));
  }

  bool _wouldClusterAtMaxZoom(_GalleryCluster group) {
    const maxRadius = 0.6 / 4096.0;
    final lat0 = group.vlogs.first.lat;
    final lng0 = group.vlogs.first.lng;
    return group.vlogs.every(
      (v) =>
          (v.lat - lat0).abs() <= maxRadius &&
          (v.lng - lng0).abs() <= maxRadius,
    );
  }

  void _showClusterList(List<Vlog> vlogs) {
    final nav = Navigator.of(context); // async gap 전에 캡처
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => _GalleryClusterSheet(
        vlogs: vlogs,
        onSelect: (vlog) {
          nav.pop(); // 시트 닫기 (캡처한 nav 사용 - 웹 호환)
          nav.push(MaterialPageRoute(
              builder: (_) => VlogPlayerScreen(vlog: vlog)));
        },
      ),
    );
  }

  /// 클러스터 원형 마커 (숫자 표시)
  static Future<BitmapDescriptor> _clusterBitmap(int count, double r) async {
    final int size = (72 * r).ceil();
    final double c = size / 2.0;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    canvas.drawCircle(
      Offset(c, c + 3 * r), 28 * r,
      Paint()
        ..color = Colors.black.withAlpha(55)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 7 * r),
    );
    canvas.drawCircle(Offset(c, c), 34 * r, Paint()..color = Colors.white);
    canvas.drawCircle(Offset(c, c), 26 * r, Paint()..color = AppColors.primary);

    final label = count > 99 ? '99+' : '$count';
    final tp = TextPainter(textDirection: TextDirection.ltr)
      ..text = TextSpan(
        text: label,
        style: TextStyle(
          fontSize: (label.length > 2 ? 13.0 : 18.0) * r,
          color: Colors.white,
          fontWeight: FontWeight.bold,
        ),
      )
      ..layout();
    tp.paint(canvas, Offset(c - tp.width / 2, c - tp.height / 2));

    final img = await recorder.endRecording().toImage(size, size);
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.bytes(
      data!.buffer.asUint8List(),
      imagePixelRatio: r,
    );
  }

  /// 단일 vlog 썸네일 말풍선 마커
  /// - 네트워크 이미지를 Canvas에 그려 BitmapDescriptor 반환
  /// - 실패 시 아이콘 placeholder 사용
  static Future<BitmapDescriptor> _thumbnailMarkerBitmap(
      String url, bool isVideo, double r) async {
    final int imgSize = (64 * r).ceil();   // 이미지 영역 크기
    final double border  = 3 * r;
    final int tailH   = (14 * r).ceil();
    final int totalH  = imgSize + tailH;
    final double radius = 10.0 * r;
    final double cx = imgSize / 2.0;

    // ── 네트워크 이미지 로드 ──────────────────────────────────────────────
    ui.Image? netImage;
    if (url.isNotEmpty) {
      try {
        final completer = Completer<ui.Image>();
        final stream = NetworkImage(url).resolve(const ImageConfiguration());
        late ImageStreamListener listener;
        listener = ImageStreamListener(
          (info, _) {
            if (!completer.isCompleted) completer.complete(info.image);
            stream.removeListener(listener);
          },
          onError: (e, _) {
            if (!completer.isCompleted) completer.completeError(e);
            stream.removeListener(listener);
          },
        );
        stream.addListener(listener);
        netImage = await completer.future.timeout(const Duration(seconds: 6));
      } catch (_) {}
    }

    // ── Canvas 드로잉 ─────────────────────────────────────────────────────
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // 그림자
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(3 * r, 5 * r, imgSize - 3.0 * r, imgSize - 3.0 * r),
        Radius.circular(radius),
      ),
      Paint()
        ..color = Colors.black.withAlpha(65)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 6 * r),
    );

    // 흰 테두리
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, imgSize.toDouble(), imgSize.toDouble()),
        Radius.circular(radius),
      ),
      Paint()..color = Colors.white,
    );

    // 내부 이미지 영역
    final innerRect = Rect.fromLTWH(
      border, border,
      imgSize - border * 2, imgSize - border * 2,
    );
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(
      innerRect, Radius.circular(radius - border + r),
    ));

    if (netImage != null) {
      // cover-fit: 비율 유지하면서 꽉 채우기
      final srcW = netImage.width.toDouble();
      final srcH = netImage.height.toDouble();
      final scale = math.max(innerRect.width / srcW, innerRect.height / srcH);
      final takeW = innerRect.width / scale;
      final takeH = innerRect.height / scale;
      canvas.drawImageRect(
        netImage,
        Rect.fromLTWH(
            (srcW - takeW) / 2, (srcH - takeH) / 2, takeW, takeH),
        innerRect,
        Paint(),
      );
    } else {
      // 썸네일 없음 → 플레이스홀더
      canvas.drawRect(innerRect, Paint()..color = const Color(0xFFF1F3F4));
      final tp = TextPainter(textDirection: TextDirection.ltr)
        ..text = TextSpan(
          text: isVideo ? '▶' : '📷',
          style: TextStyle(fontSize: 22 * r),
        )
        ..layout();
      tp.paint(canvas, Offset(
        innerRect.center.dx - tp.width / 2,
        innerRect.center.dy - tp.height / 2,
      ));
    }
    canvas.restore();

    // 영상 배지 (우하단 반투명 원 + ▶)
    if (isVideo) {
      canvas.drawCircle(
        Offset(imgSize - 13.0 * r, imgSize - 13.0 * r), 10 * r,
        Paint()..color = Colors.black.withAlpha(170),
      );
      canvas.drawPath(
        Path()
          ..moveTo(imgSize - 17.5 * r, imgSize - 17.0 * r)
          ..lineTo(imgSize - 7.5 * r,  imgSize - 13.0 * r)
          ..lineTo(imgSize - 17.5 * r, imgSize - 9.0 * r)
          ..close(),
        Paint()..color = Colors.white,
      );
    }

    // 꼬리 삼각형 (하단 중앙)
    final double tailW = 14.0 * r;
    canvas.drawPath(
      Path()
        ..moveTo(cx - tailW / 2, imgSize - 1.0 * r)
        ..lineTo(cx + tailW / 2, imgSize - 1.0 * r)
        ..lineTo(cx, totalH.toDouble())
        ..close(),
      Paint()..color = Colors.white,
    );

    final img = await recorder.endRecording().toImage(imgSize, totalH);
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.bytes(
      data!.buffer.asUint8List(),
      imagePixelRatio: r,
    );
  }

  LatLng get _center {
    // 현재 위치 우선, 없으면 vlog 평균, 없으면 서울시청
    if (_currentLatLng != null) return _currentLatLng!;
    if (widget.vlogs.isEmpty) return const LatLng(37.5665, 126.9780);
    final lat = widget.vlogs.map((e) => e.lat).reduce((a, b) => a + b) /
        widget.vlogs.length;
    final lng = widget.vlogs.map((e) => e.lng).reduce((a, b) => a + b) /
        widget.vlogs.length;
    return LatLng(lat, lng);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.vlogs.isEmpty) {
      return const _EmptyState(message: 'GPS가 기록된 브이로그가 없습니다.');
    }

    return Stack(
      children: [
        GoogleMap(
          initialCameraPosition:
              CameraPosition(target: _center, zoom: 13),
          markers: _markers,
          mapType: _mapType,
          zoomControlsEnabled: false,
          myLocationEnabled: true,
          myLocationButtonEnabled: false,
          onMapCreated: (ctrl) {
            _mapController = ctrl;
            _mapCenter = _center;
            _rebuildMarkers();
            if (_pendingLocation != null) {
              ctrl.animateCamera(
                  CameraUpdate.newLatLng(_pendingLocation!));
              _pendingLocation = null;
            }
          },
          onCameraMove: (pos) {
            _zoom = pos.zoom;
            _mapCenter = pos.target;
          },
          onCameraIdle: _rebuildMarkers,
          onTap: (_) => setState(() => _selected = null),
        ),

        // 지도 레이어 + 스트리트뷰 컨트롤
        Positioned(
          right: 12,
          bottom: _selected != null ? 164 : 16,
          child: MapControls(
            mapType: _mapType,
            onMapTypeChanged: (t) => setState(() => _mapType = t),
            center: _mapCenter,
          ),
        ),

        // 범례
        Positioned(
          top: 12,
          right: 12,
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(230),
              borderRadius: BorderRadius.circular(8),
              boxShadow: AppShadow.card,
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _MapLegend(color: Color(0xFFFF6B9D), label: '사진'),
                SizedBox(height: 3),
                _MapLegend(color: AppColors.primary, label: '영상'),
              ],
            ),
          ),
        ),

        // 선택된 단일 vlog 팝업
        if (_selected != null)
          Positioned(
            bottom: 16,
            left: 16,
            right: 16,
            child: _MapPopup(
              vlog: _selected!,
              onClose: () => setState(() => _selected = null),
            ),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 공통 서브 위젯
// ─────────────────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final String message;
  const _EmptyState(
      {this.message = '아직 업로드한 브이로그가 없어요\n촬영 탭에서 사진·영상을 올려보세요'});

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
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFF7C4DFF).withValues(alpha: 0.10),
                    const Color(0xFF7C4DFF).withValues(alpha: 0.04),
                  ],
                ),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.photo_library_outlined,
                  size: 48, color: Color(0xFF7C4DFF)),
            ),
            const SizedBox(height: 18),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MapPopup extends StatefulWidget {
  final Vlog vlog;
  final VoidCallback onClose;
  // onPlay 제거: 팝업 자신의 context로 직접 내비게이션 (_VlogPopup 패턴)
  const _MapPopup({required this.vlog, required this.onClose});

  @override
  State<_MapPopup> createState() => _MapPopupState();
}

class _MapPopupState extends State<_MapPopup> {
  String? _address; // 역지오코딩 결과 (null = 로드 중 또는 웹)

  @override
  void initState() {
    super.initState();
    _loadAddress();
  }

  Future<void> _loadAddress() async {
    if (kIsWeb) return; // geocoding 패키지 웹 미지원
    try {
      final placemarks = await placemarkFromCoordinates(
          widget.vlog.lat, widget.vlog.lng);
      if (!mounted || placemarks.isEmpty) return;
      final p = placemarks.first;
      final parts = <String>[
        if ((p.administrativeArea ?? '').isNotEmpty) p.administrativeArea!,
        if ((p.subAdministrativeArea ?? '').isNotEmpty)
          p.subAdministrativeArea!,
        if ((p.subLocality ?? '').isNotEmpty) p.subLocality!,
        if ((p.thoroughfare ?? '').isNotEmpty) p.thoroughfare!,
      ];
      if (parts.isNotEmpty && mounted) {
        setState(() => _address = parts.join(' '));
      }
    } catch (_) {}
  }

  bool get _isVideo => (widget.vlog.videoUrl ?? '').isNotEmpty;
  String get _thumbUrl => widget.vlog.thumbnailUrl ?? '';

  @override
  Widget build(BuildContext context) {
    final coordText =
        '${widget.vlog.lat.toStringAsFixed(7)}, ${widget.vlog.lng.toStringAsFixed(7)}';

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: AppShadow.elevated,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 썸네일 박스
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            child: SizedBox(
              width: 56,
              height: 56,
              child: _thumbUrl.isNotEmpty
                  ? Image.network(_thumbUrl, fit: BoxFit.cover,
                      errorBuilder: (context, error, stack) => _iconBox())
                  : _iconBox(),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // 제목
                Text(
                  widget.vlog.title,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                // 장소명
                Row(children: [
                  const Icon(Icons.location_on,
                      size: 11, color: AppColors.primary),
                  const SizedBox(width: 2),
                  Expanded(
                    child: Text(
                      widget.vlog.placeName,
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.textSecondary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ]),
                const SizedBox(height: 2),
                // 좌표 (7자리)
                Text(
                  coordText,
                  style: const TextStyle(
                      fontSize: 9.5, color: AppColors.textDisabled),
                ),
                // 역지오코딩 주소 (로드 완료 시)
                if (_address != null) ...[
                  const SizedBox(height: 1),
                  Text(
                    _address!,
                    style: const TextStyle(
                        fontSize: 9.5, color: AppColors.textDisabled),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          // 닫기 + 보기 버튼
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.close,
                    size: 18, color: AppColors.textSecondary),
                onPressed: widget.onClose,
                padding: EdgeInsets.zero,
              ),
              ElevatedButton(
                // 팝업 자신의 context 사용 — 웹 호환(_VlogPopup과 동일 패턴)
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => VlogPlayerScreen(vlog: widget.vlog)),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm, vertical: 6),
                  minimumSize: Size.zero,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                ),
                child: const Text('▶ 보기', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _iconBox() => Container(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Center(
          child: Icon(
            _isVideo ? Icons.videocam : Icons.photo,
            color: AppColors.primary,
            size: 28,
          ),
        ),
      );
}

class _MapLegend extends StatelessWidget {
  final Color color;
  final String label;
  const _MapLegend({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(label,
            style: const TextStyle(
                fontSize: 10)),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 갤러리 포토맵 클러스터 그룹
// ─────────────────────────────────────────────────────────────────────────────

class _GalleryCluster {
  final List<Vlog> vlogs;
  _GalleryCluster(this.vlogs);

  String get id => vlogs.map((v) => v.id).join('_');
  int get count => vlogs.length;
  bool get isSingle => vlogs.length == 1;

  LatLng get center {
    if (isSingle) return LatLng(vlogs.first.lat, vlogs.first.lng);
    final lat =
        vlogs.map((v) => v.lat).reduce((a, b) => a + b) / vlogs.length;
    final lng =
        vlogs.map((v) => v.lng).reduce((a, b) => a + b) / vlogs.length;
    return LatLng(lat, lng);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 동일 위치 클러스터 목록 시트
// ─────────────────────────────────────────────────────────────────────────────

class _GalleryClusterSheet extends StatelessWidget {
  final List<Vlog> vlogs;
  final void Function(Vlog) onSelect;
  const _GalleryClusterSheet({required this.vlogs, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.85,
      builder: (_, scrollCtrl) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 10, bottom: 4),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.textDisabled,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
              child: Row(
                children: [
                  const Icon(Icons.location_on,
                      color: AppColors.primary, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    '같은 위치의 브이로그 ${vlogs.length}개',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.separated(
                controller: scrollCtrl,
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                itemCount: vlogs.length,
                separatorBuilder: (_, index) =>
                    const SizedBox(height: 8),
                itemBuilder: (_, i) =>
                    _GalleryVlogCard(vlog: vlogs[i], onSelect: onSelect),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 갤러리 클러스터 시트용 카드
class _GalleryVlogCard extends StatelessWidget {
  final Vlog vlog;
  final void Function(Vlog) onSelect;
  const _GalleryVlogCard({required this.vlog, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final thumb = vlog.thumbnailUrl ?? '';
    final isVideo = (vlog.videoUrl ?? '').isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(13),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 64,
              height: 64,
              child: thumb.isNotEmpty
                  ? Image.network(thumb,
                      fit: BoxFit.cover,
                      errorBuilder: (_, err, stack) => _thumb(isVideo))
                  : _thumb(isVideo),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  vlog.title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Row(children: [
                  const Icon(Icons.location_on,
                      size: 12, color: AppColors.primary),
                  const SizedBox(width: 2),
                  Expanded(
                    child: Text(
                      vlog.placeName,
                      style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ]),
                const SizedBox(height: 4),
                Row(children: [
                  const Icon(Icons.favorite,
                      size: 12, color: AppColors.error),
                  const SizedBox(width: 2),
                  Text('${vlog.likeCount}',
                      style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary)),
                  const SizedBox(width: 8),
                  const Icon(Icons.remove_red_eye,
                      size: 12, color: AppColors.textDisabled),
                  const SizedBox(width: 2),
                  Text('${vlog.viewCount}',
                      style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textDisabled)),
                ]),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: () => onSelect(vlog),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 6),
              minimumSize: Size.zero,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
            ),
            child: const Text('▶ 재생',
                style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _thumb(bool isVideo) => Container(
        color: AppColors.surfaceVariant,
        child: Center(
          child: Icon(
            isVideo ? Icons.videocam : Icons.photo,
            color: AppColors.primary,
            size: 22,
          ),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// 공통 정렬 바
// ─────────────────────────────────────────────────────────────────────────────

// ─────────────────────────────────────────────────────────────────────────────
// 공통 정렬 바 (날짜순 / 거리순 + 오름/내림 표시)
// ─────────────────────────────────────────────────────────────────────────────

class _SortBar extends StatelessWidget {
  final _SortMode current;
  final _SortOrder order;
  final void Function(_SortMode) onChanged;
  const _SortBar({
    required this.current,
    required this.order,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surface,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _SortChipG(
              label: '날짜순',
              icon: Icons.calendar_today_outlined,
              selected: current == _SortMode.byDate,
              ascending: order == _SortOrder.asc,
              onTap: () => onChanged(_SortMode.byDate),
            ),
            const SizedBox(width: 6),
            _SortChipG(
              label: '거리순',
              icon: Icons.near_me_outlined,
              selected: current == _SortMode.byDistance,
              ascending: order == _SortOrder.asc,
              onTap: () => onChanged(_SortMode.byDistance),
            ),
            const SizedBox(width: 6),
            _SortChipG(
              label: '좋아요순',
              icon: Icons.favorite,
              selected: current == _SortMode.byLikes,
              ascending: order == _SortOrder.asc,
              onTap: () => onChanged(_SortMode.byLikes),
            ),
            const SizedBox(width: 6),
            _SortChipG(
              label: '조회순',
              icon: Icons.visibility_outlined,
              selected: current == _SortMode.byViews,
              ascending: order == _SortOrder.asc,
              onTap: () => onChanged(_SortMode.byViews),
            ),
          ],
        ),
      ),
    );
  }
}

/// 갤러리 전용 정렬 칩 (_SortChip 과 동일 디자인, 파일 분리로 인해 별도 정의)
class _SortChipG extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final bool ascending;
  final VoidCallback onTap;
  const _SortChipG({
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

// ─── 갤러리 카테고리 필터 칩 ─────────────────────────────────────────────
class _GalleryCategoryChip extends StatelessWidget {
  final String label;
  final String emoji;
  final bool selected;
  final VoidCallback onTap;
  const _GalleryCategoryChip({
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
          color: selected ? AppColors.primary : Theme.of(context).colorScheme.surfaceContainerHighest,
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
            Text(emoji, style: const TextStyle(fontSize: 13)),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: selected ? Colors.white : AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
