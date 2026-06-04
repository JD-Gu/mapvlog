import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../models/friend_group.dart';
import '../../models/friendship.dart';
import '../../models/user_status.dart';
import '../../models/vlog.dart';
import '../../services/firestore_service.dart';
import '../../services/friend_group_service.dart';
import '../../services/friend_service.dart';
import '../../services/location_tracking_service.dart';
import '../../services/user_status_service.dart';
import '../../utils/constants.dart';
import '../../widgets/comments_sheet.dart';

const _defaultCenter = LatLng(37.5665, 126.9780); // 서울 시청

/// 친구 지도 — 라이브 위치 + 상태 이모지 공유
///
/// Zenly 감성:
///   - 아바타 마커 + 상태 이모지 버블 + 이름 라벨
///   - 5분마다 자동 위치 업데이트 (프라이버시 모드에 따라 정밀도 다름)
///   - 상단 상태 설정 칩 + 프라이버시 모드 토글
class LiveMapScreen extends StatefulWidget {
  /// 진입 시 카메라를 이 체크인 위치로 이동 + 임시 마커 표시 (옵션)
  /// 홈 피드에서 체크인 카드 탭 시 사용
  final Vlog? focusCheckIn;

  const LiveMapScreen({super.key, this.focusCheckIn});

  @override
  State<LiveMapScreen> createState() => _LiveMapScreenState();
}

class _LiveMapScreenState extends State<LiveMapScreen> {
  GoogleMapController? _mapController;
  Set<Marker> _markers = {};
  Set<Circle> _circles = {}; // 부끄럼 모드 친구 위치 노이즈 원
  List<LiveUser> _users = [];
  LiveUser? _me;
  Set<String> _friendUids = {};
  // 친구 그룹 (Phase 4)
  List<FriendGroup> _myGroups = [];
  StreamSubscription<List<FriendGroup>>? _groupsSub;
  String? _activeGroupFilter; // null = 전체
  /// 브로드캐스터 우선순위 — 친구가 나를 설정한 view (users/{friendUid}/friends/{myUid})
  /// 키: friendUid → 그 친구의 나에 대한 Friendship doc
  final Map<String, Friendship> _theirViewOfMe = {};
  final Map<String, StreamSubscription<DocumentSnapshot>> _theirViewSubs = {};
  /// 내 받은 호출 — 마커 배지 + 시트에 표시
  List<Ping> _myPings = [];
  StreamSubscription<List<Ping>>? _myPingsSub;
  StreamSubscription<List<LiveUser>>? _usersSub;
  StreamSubscription<LiveUser?>? _meSub;
  StreamSubscription<List<Friendship>>? _friendsSub;
  /// 최근 6시간 친구 체크인 — 지도에 자동 마커 표시
  List<Vlog> _recentCheckIns = [];
  StreamSubscription<List<Vlog>>? _recentCheckInsSub;
  // ping 구독은 MainShell에서 글로벌하게 처리 (라이브맵 밖에서도 알림 받음)
  // 위치 갱신(타이머·가속도·배터리·라이프사이클)은 LocationTrackingService가
  // 앱 전역에서 담당. 이 화면은 진입/이탈 시 setOnLiveMap()만 토글한다.
  /// "N분 전" 라벨 갱신용 — 위치 변화 없어도 1분마다 마커 재빌드
  Timer? _refreshTimer;

  /// 지도 생성 전에 GPS 위치가 들어오면 임시 저장 → onMapCreated에서 이동
  LatLng? _pendingCameraLocation;
  /// 첫 GPS 이동을 1회만 수행하기 위한 가드
  bool _didInitialCameraMove = false;
  /// 포커스 체크인 카드 자동 표시를 1회만 하기 위한 가드
  bool _focusSheetShown = false;
  /// 고해상도 마커용 — 디바이스 픽셀 비율
  double _pixelRatio = 3.0;
  /// 네트워크 사진 → ui.Image 캐시 (마커 그리기용)
  final Map<String, ui.Image?> _photoImageCache = {};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _pixelRatio = MediaQuery.of(context).devicePixelRatio;
  }

  String? get _currentUid => FirebaseAuth.instance.currentUser?.uid;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // 1) 사용자 doc 보장
    await UserStatusService.ensureUserDoc(user);

    // 2) 내 정보 구독
    _meSub = UserStatusService.watchUser(user.uid).listen((u) {
      if (mounted) setState(() => _me = u);
    });

    // 3) 친구 목록 구독 + 브로드캐스터 우선순위(친구가 나를 본 setting) 구독
    _friendsSub = FriendService.watchMyFriends().listen((list) async {
      if (!mounted) return;
      _friendUids = list.map((f) => f.friendUid).toSet();
      _updateTheirViewSubs(user.uid);
      _resubscribeRecentCheckIns(user.uid);
      await _rebuildMarkers();
    });

    // 4) 내 받은 호출 구독 — 마커 배지 + 시트
    _myPingsSub = UserStatusService.watchMyPings(user.uid).listen((pings) {
      if (!mounted) return;
      _myPings = pings;
      _rebuildMarkers();
    });

    // 4) 모든 사용자 구독 (친구 + 본인만 client-side 필터)
    _usersSub = UserStatusService.watchAllLiveUsers().listen((users) async {
      if (!mounted) return;
      _users = users;
      await _rebuildMarkers();
    });

    // 4-2) 내 친구 그룹 구독 (그룹 필터 칩 + 부끄럼 모드 마스킹용)
    _groupsSub = FriendGroupService.watchMyGroups().listen((groups) async {
      if (!mounted) return;
      _myGroups = groups;
      await _rebuildMarkers();
    });

    // 4) 친구지도 활성 → 전역 추적 서비스에 10초 고속 갱신 요청
    LocationTrackingService.instance.setOnLiveMap(true);
    // 5) 권한 확인·요청 후 내 위치로 카메라 이동 (첫 진입 즉시 표시)
    await _centerCameraOnMe();
    // 6) 위치 변화 없어도 1분마다 마커 갱신 → "N분 전" 라벨 최신화
    _refreshTimer = Timer.periodic(
        const Duration(minutes: 1), (_) => _rebuildMarkers());
  }

  /// 친구지도 진입 시 — 위치 권한을 요청하고 내 위치로 카메라를 이동한다.
  /// 마지막 위치를 먼저 반영(즉시)한 뒤 정확 위치로 보정.
  Future<void> _centerCameraOnMe() async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return; // 권한 없음
      }
      final svc = LocationTrackingService.instance;
      // ① 마지막 위치를 먼저 반영 (콜드 GPS 대기 없이 즉시 표시)
      final last = await svc.lastKnown();
      if (last != null) _moveCameraTo(last);
      // ② 정확한 현재 위치로 보정 + 기록
      final pos = await svc.updateNow();
      if (pos != null) _moveCameraTo(pos);
    } catch (_) {}
  }

  /// 위치로 카메라 이동 (첫 진입 1회만). 지도 준비 전이면 pending에 저장.
  void _moveCameraTo(Position pos) {
    if (_didInitialCameraMove) return;
    final latlng = LatLng(pos.latitude, pos.longitude);
    if (_mapController != null) {
      _didInitialCameraMove = true;
      _mapController!
          .animateCamera(CameraUpdate.newLatLngZoom(latlng, 15));
    } else {
      _pendingCameraLocation = latlng;
    }
  }

  /// 친구·내 체크인 vlog 구독 (만료 전까지 표시, 재구독 = 친구 목록 바뀔 때마다)
  void _resubscribeRecentCheckIns(String myUid) {
    _recentCheckInsSub?.cancel();
    final uids = _friendUids.toList();
    if (uids.isEmpty) {
      _recentCheckIns = [];
      return;
    }
    _recentCheckInsSub = FirestoreService.watchFriendsVlogs(
      friendUids: uids,
      myUid: myUid,
      limit: 100,
    ).listen((vlogs) {
      // 만료 시각(expiresAt) 이내의 체크인만 표시 — 내 체크인도 포함
      _recentCheckIns =
          vlogs.where((v) => v.isCheckIn && !v.isCheckInExpired).toList();
      _rebuildMarkers();
    });
  }

  /// 체크인 마커용 이모지 버블 비트맵 (+ 선택적 라벨: 남은시간·거리)
  /// — 흰 원 + 컬러 링 + 중앙 이모지, 그 아래 라벨. anchorY 는 버블 중심 비율.
  Future<({BitmapDescriptor icon, double anchorY})> _checkInMarkerBitmap(
      String emoji,
      {String? subtitle}) async {
    final r = _pixelRatio;
    final radius = 16.0 * r; // 13 → 16 (조금 키움)
    final pad = 6.0 * r; // 그림자 여백
    final bubbleD = radius * 2;

    // 라벨 (남은시간 · 거리)
    TextPainter? labelPainter;
    double labelW = 0, labelH = 0;
    const labelGap = 0.0;
    final gap = 4.0 * r;
    final labelPadH = 7.0 * r;
    final labelPadV = 3.0 * r;
    if (subtitle != null && subtitle.isNotEmpty) {
      labelPainter = TextPainter(textDirection: TextDirection.ltr)
        ..text = TextSpan(
            text: subtitle,
            style: TextStyle(
              fontSize: 10.5 * r,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF202124),
              letterSpacing: -0.2 * r,
            ))
        ..layout();
      labelW = labelPainter.width + labelPadH * 2;
      labelH = labelPainter.height + labelPadV * 2;
    }

    final bubbleBlockW = bubbleD + pad * 2;
    final totalW = math.max(bubbleBlockW, labelW).ceil();
    final hasLabel = labelPainter != null;
    final totalH =
        (pad + bubbleD + (hasLabel ? gap + labelH : 0) + pad).ceil();
    final cx = totalW / 2.0;
    final bubbleCY = pad + radius;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // 그림자
    canvas.drawCircle(
      Offset(cx, bubbleCY + 2 * r),
      radius,
      Paint()
        ..color = Colors.black.withAlpha(80)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 4 * r),
    );
    // 파란 링
    canvas.drawCircle(
        Offset(cx, bubbleCY), radius, Paint()..color = const Color(0xFF1A73E8));
    // 흰 내부
    canvas.drawCircle(
        Offset(cx, bubbleCY), radius - 2 * r, Paint()..color = Colors.white);
    // 이모지
    final emojiPainter = TextPainter(textDirection: TextDirection.ltr)
      ..text = TextSpan(text: emoji, style: TextStyle(fontSize: 17 * r))
      ..layout();
    emojiPainter.paint(canvas,
        Offset(cx - emojiPainter.width / 2, bubbleCY - emojiPainter.height / 2));

    // 라벨 (흰 배경 알약 + 텍스트)
    if (hasLabel) {
      final labelX = cx - labelW / 2;
      final labelY = pad + bubbleD + gap + labelGap;
      final rrect = RRect.fromRectAndRadius(
        Rect.fromLTWH(labelX, labelY, labelW, labelH),
        Radius.circular(labelH / 2),
      );
      canvas.drawRRect(
        rrect.shift(Offset(0, 1 * r)),
        Paint()
          ..color = Colors.black.withAlpha(45)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 3 * r),
      );
      canvas.drawRRect(rrect, Paint()..color = Colors.white);
      labelPainter.paint(canvas, Offset(labelX + labelPadH, labelY + labelPadV));
    }

    final picture = recorder.endRecording();
    final image = await picture.toImage(totalW, totalH);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return (
      icon: BitmapDescriptor.bytes(
        bytes!.buffer.asUint8List(),
        imagePixelRatio: r,
      ),
      anchorY: bubbleCY / totalH,
    );
  }

  /// 친구 체크인 상세 시트
  void _showCheckInSheet(Vlog v) {
    HapticFeedback.selectionClick();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        final emoji = v.markerEmoji ?? '📍';
        final title = v.title.isEmpty ? v.placeName : v.title;
        return Container(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: cs.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A73E8).withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: const Color(0xFF1A73E8), width: 2),
                    ),
                    alignment: Alignment.center,
                    child: Text(emoji, style: const TextStyle(fontSize: 22)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1A73E8),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: const Text('체크인',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              )),
                        ),
                        const SizedBox(height: 4),
                        Text(v.authorName,
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: cs.onSurface)),
                      ],
                    ),
                  ),
                  Text(
                    _formatTimeAgo(v.createdAt),
                    style: TextStyle(
                        fontSize: 12, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(title,
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: cs.onSurface,
                      height: 1.3)),
              if ((v.address ?? '').isNotEmpty) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(Icons.place,
                        size: 14, color: cs.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        v.address!,
                        style: TextStyle(
                            fontSize: 12.5,
                            color: cs.onSurfaceVariant),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 18),
              // 댓글 — 시트 닫고 댓글 시트 열기
              FilledButton.tonalIcon(
                onPressed: () {
                  Navigator.pop(ctx);
                  CommentsSheet.open(context, v);
                },
                icon: const Icon(Icons.mode_comment_outlined, size: 18),
                label: Text(
                  v.commentCount > 0 ? '댓글 ${v.commentCount}개' : '댓글 달기',
                ),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 46),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.md)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// 친구가 나를 본 setting 구독 갱신 — 브로드캐스터 우선순위 데이터 소스
  void _updateTheirViewSubs(String myUid) {
    // 1) 더 이상 친구 아닌 사용자 구독 해제
    for (final uid in _theirViewSubs.keys.toList()) {
      if (!_friendUids.contains(uid)) {
        _theirViewSubs[uid]?.cancel();
        _theirViewSubs.remove(uid);
        _theirViewOfMe.remove(uid);
      }
    }
    // 2) 새 친구마다 그들의 friends/{me} doc 구독
    for (final friendUid in _friendUids) {
      if (_theirViewSubs.containsKey(friendUid)) continue;
      _theirViewSubs[friendUid] = FirebaseFirestore.instance
          .collection('users')
          .doc(friendUid)
          .collection('friends')
          .doc(myUid)
          .snapshots()
          .listen((doc) {
        if (!mounted) return;
        if (doc.exists) {
          _theirViewOfMe[friendUid] = Friendship.fromDoc(doc);
        } else {
          _theirViewOfMe.remove(friendUid);
        }
        _rebuildMarkers();
      });
    }
  }

  /// 사용자 프로필 사진을 ui.Image로 로드 (캐시 사용)
  Future<ui.Image?> _loadUserPhoto(String? url) async {
    if (url == null || url.isEmpty) return null;
    if (_photoImageCache.containsKey(url)) return _photoImageCache[url];
    try {
      final completer = Completer<ui.Image>();
      late ImageStreamListener listener;
      final stream =
          NetworkImage(url).resolve(const ImageConfiguration());
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
      final img = await completer.future.timeout(const Duration(seconds: 6));
      _photoImageCache[url] = img;
      return img;
    } catch (_) {
      _photoImageCache[url] = null;
      return null;
    }
  }

  Future<void> _rebuildMarkers() async {
    final markers = <Marker>{};
    final circles = <Circle>{};

    // 활성 그룹 필터 — 선택된 그룹의 멤버 UID 집합
    Set<String>? filterUids;
    if (_activeGroupFilter != null) {
      final g = _myGroups.firstWhere(
        (g) => g.id == _activeGroupFilter,
        orElse: () => FriendGroup(
            id: '', name: '', emoji: '',
            mode: GroupMode.insider, memberUids: const [],
            createdAt: DateTime.now()),
      );
      filterUids = g.memberUids.toSet();
    }

    for (final u in _users) {
      if (u.location == null) continue;
      final isMe = u.uid == _currentUid;
      if (!isMe && !_friendUids.contains(u.uid)) continue;
      // 그룹 필터 적용 (본인은 항상 표시)
      if (!isMe && filterUids != null && !filterUids.contains(u.uid)) {
        continue;
      }

      // Phase 5 — 내가 친구를 어떤 그룹에 넣었는지 → shy 모드면 마스킹
      // (broadcaster-side 우선순위 + viewer-side group mode 중 더 보수적인 쪽)
      final myGroupMode = isMe
          ? null
          : FriendGroupService.modeForFriend(_myGroups, u.uid);

      // 브로드캐스터 우선순위 — 친구가 나를 본 setting 기반
      FriendEffectiveMode? effective;
      LatLng position = LatLng(u.location!.lat, u.location!.lng);
      if (!isMe) {
        final theirView = _theirViewOfMe[u.uid]; // 친구의 나에 대한 setting
        if (theirView != null) {
          effective = theirView.effectiveMode(u.privacyMode.value);
          if (effective == FriendEffectiveMode.ice &&
              theirView.frozenLat != null &&
              theirView.frozenLng != null) {
            position = LatLng(theirView.frozenLat!, theirView.frozenLng!);
          }
        }
      }

      // Phase 5 — 내가 친구를 uneasy 그룹에 넣었으면 마커 자체 숨김
      if (myGroupMode == GroupMode.uneasy) continue;

      // Phase 5 — shy 그룹: 위치는 ~500m 노이즈로 마스킹하되 마커는
      // 다른 친구와 동일한 아바타 스타일 (안개 후광) 유지
      if (myGroupMode == GroupMode.shy) {
        final seed = u.uid.hashCode;
        // ~500m offset (위도 1° ≈ 111km → 0.005° ≈ 555m)
        final dx = ((seed % 1000) / 1000.0 - 0.5) * 0.005;
        final dy = (((seed >> 10) % 1000) / 1000.0 - 0.5) * 0.005;
        position = LatLng(position.latitude + dy, position.longitude + dx);
        // 500m 반경 원은 제거 — 위치 마스킹(오프셋) + 안개 후광으로 대략 위치 표현
        effective = FriendEffectiveMode.fog;
      }

      final photo = await _loadUserPhoto(u.photoUrl);
      final marker = await _avatarMarkerBitmap(
        name: u.displayName,
        emoji: u.status?.emoji,
        privacyMode: u.privacyMode,
        effectiveMode: effective,
        isMe: isMe,
        photo: photo,
        updatedAt: u.location?.updatedAt,
        pingCount: isMe ? _myPings.length : 0,
        // 친구까지 거리 (표시 위치 기준 — 부끄럼/안개는 마스킹된 위치로 계산)
        distanceText:
            isMe ? null : _distanceTo(position.latitude, position.longitude),
      );
      markers.add(Marker(
        markerId: MarkerId(u.uid),
        position: position,
        icon: marker.icon,
        anchor: Offset(0.5, marker.anchorY),
        onTap: () {
          HapticFeedback.selectionClick();
          _showUserSheet(u);
        },
      ));
    }
    // 체크인 자동 표시 (만료 전까지, 작은 이모지 마커 — 내 체크인 포함)
    // 홈에서 진입한 포커스 체크인은 만료·필터로 빠졌어도 항상 표시 (중복 제거)
    final focus = widget.focusCheckIn;
    final checkInsToShow = <Vlog>[..._recentCheckIns];
    if (focus != null && !checkInsToShow.any((v) => v.id == focus.id)) {
      checkInsToShow.add(focus);
    }
    for (final v in checkInsToShow) {
      final isFocus = focus != null && v.id == focus.id;
      // 그룹 필터 활성 시 비멤버 친구의 체크인은 숨김 (단, 포커스 대상은 예외)
      if (!isFocus &&
          filterUids != null &&
          !filterUids.contains(v.authorId)) {
        continue;
      }
      // 라벨: 남은시간 · 거리
      final remaining = _checkInRemaining(v);
      final dist = _distanceTo(v.lat, v.lng);
      final subtitle = dist != null ? '$remaining · $dist' : remaining;
      final ci = await _checkInMarkerBitmap(v.markerEmoji ?? '📍',
          subtitle: subtitle);
      markers.add(Marker(
        markerId: MarkerId('checkin_${v.id}'),
        position: LatLng(v.lat, v.lng),
        icon: ci.icon,
        anchor: Offset(0.5, ci.anchorY),
        zIndexInt: isFocus ? 100 : 50,
        onTap: () => _showCheckInSheet(v),
      ));
    }

    // 포커스된 체크인 — 위치 강조 링만 (구글 기본 마커 없이 커스텀 아이콘 사용)
    if (focus != null) {
      circles.add(Circle(
        circleId: const CircleId('focus_checkin'),
        center: LatLng(focus.lat, focus.lng),
        radius: 70,
        fillColor: const Color(0xFF1A73E8).withValues(alpha: 0.10),
        strokeColor: const Color(0xFF1A73E8),
        strokeWidth: 2,
      ));
    }

    if (mounted) {
      setState(() {
        _markers = markers;
        _circles = circles;
      });
    }
  }

  void _showUserSheet(LiveUser u) {
    final isMe = u.uid == _currentUid;
    // 브로드캐스터 우선순위 — 친구가 나에게 적용 중인 effective mode 계산
    FriendEffectiveMode? effective;
    Friendship? theirView;
    if (!isMe) {
      theirView = _theirViewOfMe[u.uid];
      if (theirView != null) {
        effective = theirView.effectiveMode(u.privacyMode.value);
      }
    }
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _UserDetailSheet(
        user: u,
        isMe: isMe,
        effectiveMode: effective,
        theirView: theirView,
        pings: isMe ? _myPings : const [],
      ),
    );
  }

  /// 상태 설정 시트
  Future<void> _showStatusPicker() async {
    final uid = _currentUid;
    if (uid == null) return;
    HapticFeedback.selectionClick();
    final picked = await showModalBottomSheet<({String emoji, String label})?>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _StatusPickerSheet(current: _me?.status),
    );
    if (picked == null) return;
    // 상태 제거 (특수 케이스)
    if (picked.emoji.isEmpty) {
      await UserStatusService.clearStatus(uid);
    } else {
      await UserStatusService.setStatus(
          uid: uid, emoji: picked.emoji, label: picked.label);
    }
  }

  /// 프라이버시 모드 선택 시트
  Future<void> _showPrivacySheet() async {
    final uid = _currentUid;
    if (uid == null) return;
    HapticFeedback.selectionClick();
    final picked = await showModalBottomSheet<PrivacyMode>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _PrivacyModeSheet(current: _me?.privacyMode),
    );
    if (picked == null) return;
    double? lat;
    double? lng;
    if (picked == PrivacyMode.ice && _me?.location != null) {
      lat = _me!.location!.lat;
      lng = _me!.location!.lng;
    }
    await UserStatusService.setPrivacyMode(
      uid: uid,
      mode: picked,
      currentLat: lat,
      currentLng: lng,
    );
    if (picked != PrivacyMode.ice) {
      // 정확/안개로 전환 → 즉시 새 위치 업데이트
      await LocationTrackingService.instance.updateNow();
    }
  }

  /// 내 위치로 카메라 이동
  Future<void> _moveToMyLocation() async {
    HapticFeedback.lightImpact();
    if (_me?.location != null) {
      _mapController?.animateCamera(CameraUpdate.newLatLngZoom(
          LatLng(_me!.location!.lat, _me!.location!.lng), 15));
    } else {
      final pos = await LocationTrackingService.instance.updateNow();
      if (pos != null && _mapController != null) {
        _mapController!.animateCamera(CameraUpdate.newLatLngZoom(
            LatLng(pos.latitude, pos.longitude), 15));
      }
    }
  }

  /// 라이브 친구 목록 — 위치 있고 1시간 이내 갱신된 사용자
  /// (나 포함, 그룹 필터/uneasy 제외 적용)
  List<LiveUser> _liveFriends() {
    final now = DateTime.now();
    final filtered = <LiveUser>[];
    for (final u in _users) {
      if (u.location == null) continue;
      if (now.difference(u.location!.updatedAt).inHours >= 1) continue;
      // 그룹 필터 활성 시 멤버 + 나만 표시
      if (_activeGroupFilter != null) {
        final group = _myGroups.firstWhere(
          (g) => g.id == _activeGroupFilter,
          orElse: () => FriendGroup(
            id: '',
            name: '',
            emoji: '',
            mode: GroupMode.insider,
            memberUids: const [],
            createdAt: DateTime.now(),
          ),
        );
        final isMe = u.uid == FirebaseAuth.instance.currentUser?.uid;
        if (!isMe && !group.memberUids.contains(u.uid)) continue;
      }
      filtered.add(u);
    }
    // 라이브(60초 이내) 먼저, 그 다음 최근순
    filtered.sort((a, b) {
      final ta = a.location!.updatedAt;
      final tb = b.location!.updatedAt;
      return tb.compareTo(ta);
    });
    return filtered;
  }

  /// 라이브 친구 리스트 시트 열기 — 친구 탭 시 panTo
  void _showLiveFriendsSheet() {
    HapticFeedback.selectionClick();
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => _LiveFriendsSheet(
        friends: _liveFriends(),
        myUid: myUid,
        onTapFriend: (u) {
          Navigator.pop(sheetCtx);
          _panToFriend(u);
        },
      ),
    );
  }

  /// 친구 위치로 부드럽게 카메라 이동
  void _panToFriend(LiveUser u) {
    if (u.location == null) return;
    HapticFeedback.lightImpact();
    _mapController?.animateCamera(
      CameraUpdate.newLatLngZoom(
        LatLng(u.location!.lat, u.location!.lng),
        16,
      ),
    );
  }

  @override
  void dispose() {
    // 친구지도 이탈 → 전역 추적은 계속되되 고속(10초) 갱신 해제
    LocationTrackingService.instance.setOnLiveMap(false);
    _usersSub?.cancel();
    _meSub?.cancel();
    _friendsSub?.cancel();
    _recentCheckInsSub?.cancel();
    _myPingsSub?.cancel();
    _groupsSub?.cancel();
    for (final sub in _theirViewSubs.values) {
      sub.cancel();
    }
    _theirViewSubs.clear();
    _refreshTimer?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final initial = _me?.location != null
        ? LatLng(_me!.location!.lat, _me!.location!.lng)
        : _defaultCenter;

    return Scaffold(
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(target: initial, zoom: 15),
            markers: _markers,
            circles: _circles,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            onMapCreated: (c) {
              _mapController = c;
              // 홈에서 체크인 위치로 진입한 경우 — 우선 그 위치로 이동 + InfoWindow 표시
              final focus = widget.focusCheckIn;
              if (focus != null) {
                _didInitialCameraMove = true;
                c.animateCamera(CameraUpdate.newLatLngZoom(
                    LatLng(focus.lat, focus.lng), 16));
                // 아이콘 위치로 이동 후 체크인 카드 자동 표시 (아이콘+카드 함께)
                if (!_focusSheetShown) {
                  _focusSheetShown = true;
                  Future.delayed(const Duration(milliseconds: 650), () {
                    if (mounted) _showCheckInSheet(focus);
                  });
                }
              } else if (_pendingCameraLocation != null) {
                // 지도 준비 전에 도착한 GPS 위치가 있으면 즉시 이동
                _didInitialCameraMove = true;
                c.animateCamera(CameraUpdate.newLatLngZoom(
                    _pendingCameraLocation!, 15));
                _pendingCameraLocation = null;
              }
            },
          ),

          // 상단: 뒤로가기 + 사용자 수 칩
          Positioned(
            top: MediaQuery.of(context).padding.top + 10,
            left: 12,
            right: 12,
            child: Row(
              children: [
                const Spacer(),
                _CountChip(
                  count: _liveFriends().length,
                  onTap: () => _showLiveFriendsSheet(),
                ),
              ],
            ),
          ),

          // 그룹 필터 칩 (사용자가 그룹을 1개 이상 만든 경우에만 노출)
          if (_myGroups.isNotEmpty)
            Positioned(
              top: MediaQuery.of(context).padding.top + 62,
              left: 0,
              right: 0,
              child: SizedBox(
                height: 36,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: [
                    _GroupFilterChip(
                      label: '전체',
                      emoji: '🌐',
                      selected: _activeGroupFilter == null,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() => _activeGroupFilter = null);
                        _rebuildMarkers();
                      },
                    ),
                    const SizedBox(width: 6),
                    ..._myGroups.map((g) => Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: _GroupFilterChip(
                            label: '${g.name} ${g.memberUids.length}',
                            emoji: g.emoji,
                            selected: _activeGroupFilter == g.id,
                            mode: g.mode,
                            onTap: () {
                              HapticFeedback.selectionClick();
                              setState(() => _activeGroupFilter = g.id);
                              _rebuildMarkers();
                            },
                          ),
                        )),
                  ],
                ),
              ),
            ),

          // 우측 컨트롤
          Positioned(
            right: 12,
            bottom: 180,
            child: Column(
              children: [
                _RoundIconButton(
                  icon: Icons.my_location,
                  color: AppColors.primary,
                  onTap: _moveToMyLocation,
                ),
              ],
            ),
          ),

          // 하단: 상태 + 프라이버시 컨트롤 바
          Positioned(
            left: 12,
            right: 12,
            bottom: MediaQuery.of(context).padding.bottom + 16,
            child: _LiveControlBar(
              me: _me,
              onStatusTap: _showStatusPicker,
              onPrivacyTap: _showPrivacySheet,
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 아바타 마커 비트맵 생성
  // ═══════════════════════════════════════════════════════════════════════════

  /// 갱신 시간 → 텍스트 ("방금 전" / "N분 전" / "N시간 전" / "어제" / "오래전")
  static String _formatTimeAgo(DateTime? dt) {
    if (dt == null) return '';
    final diff = DateTime.now().difference(dt);
    if (diff.isNegative) return '방금 전';
    if (diff.inSeconds < 60) return '방금 전';
    if (diff.inMinutes < 60) return '${diff.inMinutes}분 전';
    if (diff.inHours < 24) return '${diff.inHours}시간 전';
    if (diff.inDays < 2) return '어제';
    return '오래전';
  }

  /// 내 현재 위치 (거리 계산용) — 실제 GPS 우선, 없으면 내 doc 위치
  ({double lat, double lng})? _myLatLng() {
    final p = LocationTrackingService.instance.lastPosition;
    if (p != null) return (lat: p.latitude, lng: p.longitude);
    final loc = _me?.location;
    if (loc != null) return (lat: loc.lat, lng: loc.lng);
    return null;
  }

  /// 내 위치 → 대상 좌표 거리 문자열 ("320m" / "1.2km"). 내 위치 없으면 null.
  String? _distanceTo(double lat, double lng) {
    final me = _myLatLng();
    if (me == null) return null;
    final meters = Geolocator.distanceBetween(me.lat, me.lng, lat, lng);
    if (meters < 1000) return '${meters.round()}m';
    final km = meters / 1000;
    return '${km.toStringAsFixed(km < 10 ? 1 : 0)}km';
  }

  /// 체크인 남은 시간 ("2시간 남음" / "45분 남음" / "곧 만료").
  String _checkInRemaining(Vlog v) {
    final exp = v.expiresAt ?? v.createdAt.add(const Duration(hours: 6));
    final diff = exp.difference(DateTime.now());
    if (diff.inMinutes < 1) return '곧 만료';
    if (diff.inMinutes < 60) return '${diff.inMinutes}분 남음';
    if (diff.inHours < 24) return '${diff.inHours}시간 남음';
    return '${diff.inDays}일 남음';
  }

  static const _avatarColors = [
    Color(0xFF1A73E8),
    Color(0xFF34A853),
    Color(0xFFFF6B6B),
    Color(0xFF7C4DFF),
    Color(0xFFFFA726),
    Color(0xFF00ACC1),
    Color(0xFFEC407A),
  ];

  /// 아바타 마커 비트맵 + 앵커 Y 반환.
  /// anchorY 는 "꼬리 꼭지점"의 세로 비율 → Marker.anchor 에 적용하면
  /// 꼭지점이 GPS 좌표에 정확히 위치하고 라벨은 그 아래로 매달림.
  Future<({BitmapDescriptor icon, double anchorY})> _avatarMarkerBitmap({
    required String name,
    String? emoji,
    required PrivacyMode privacyMode,
    FriendEffectiveMode? effectiveMode,
    required bool isMe,
    ui.Image? photo,
    DateTime? updatedAt,
    int pingCount = 0,
    String? distanceText,
  }) async {
    final r = _pixelRatio; // 고해상도 렌더링용 배수

    // 캔버스 크기 (모두 픽셀비율 적용)
    final double avatarR = 28.0 * r;
    final double ringW = 4.0 * r;
    final double tailH = 10.0 * r;
    final double labelGap = 4.0 * r;
    final double labelPadH = 8.0 * r;
    final double labelPadV = 4.0 * r;
    final double bubbleR = 16.0 * r;

    // 이름 + "N분 전" 라벨
    final shortName = name.length > 6 ? '${name.substring(0, 6)}…' : name;
    final timeAgo = _formatTimeAgo(updatedAt);
    final isLive = updatedAt != null &&
        DateTime.now().difference(updatedAt).inSeconds < 60;
    final namePainter = TextPainter(textDirection: TextDirection.ltr)
      ..text = TextSpan(
        style: TextStyle(
          fontSize: 11.5 * r,
          fontWeight: FontWeight.w700,
          color: const Color(0xFF202124),
          letterSpacing: -0.2 * r,
        ),
        children: [
          TextSpan(text: shortName),
          if (timeAgo.isNotEmpty) ...[
            TextSpan(
                text: '  ·  ',
                style: TextStyle(
                    fontSize: 10 * r,
                    color: const Color(0xFFBDC1C6),
                    fontWeight: FontWeight.w500)),
            if (isLive)
              TextSpan(
                  text: '● ',
                  style: TextStyle(
                      fontSize: 9 * r,
                      color: const Color(0xFF34A853),
                      fontWeight: FontWeight.w800)),
            TextSpan(
                text: timeAgo,
                style: TextStyle(
                    fontSize: 10.5 * r,
                    color: isLive
                        ? const Color(0xFF34A853)
                        : const Color(0xFF5F6368),
                    fontWeight: FontWeight.w600)),
          ],
          if (distanceText != null) ...[
            TextSpan(
                text: '  ·  ',
                style: TextStyle(
                    fontSize: 10 * r,
                    color: const Color(0xFFBDC1C6),
                    fontWeight: FontWeight.w500)),
            TextSpan(
                text: distanceText,
                style: TextStyle(
                    fontSize: 10.5 * r,
                    color: const Color(0xFF1A73E8),
                    fontWeight: FontWeight.w700)),
          ],
        ],
      )
      ..layout();

    final labelW = namePainter.width + labelPadH * 2;
    final labelH = namePainter.height + labelPadV * 2;

    final hasEmoji = emoji != null && emoji.isNotEmpty;
    final width =
        (avatarR * 2 + ringW * 2 + (hasEmoji ? 12.0 * r : 0)).ceil();
    final totalW = math.max(width, labelW.ceil()) + (12 * r).ceil();
    final avatarTop = hasEmoji ? bubbleR : 0.0;
    final avatarBottom = avatarTop + (avatarR + ringW) * 2;
    final totalH = (avatarBottom + tailH + labelGap + labelH).ceil();

    final cx = totalW / 2.0;
    final avatarCy = avatarTop + avatarR + ringW;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    final color = _avatarColors[name.hashCode.abs() % _avatarColors.length];

    // 우선순위 엔진 적용: effectiveMode가 있으면 그것이 우선 시각, 없으면 broadcaster의 privacyMode 적용
    final viewMode = effectiveMode;
    final showAsFog = viewMode == FriendEffectiveMode.fog ||
        (viewMode == null && privacyMode == PrivacyMode.fog);
    final showAsIce = viewMode == FriendEffectiveMode.ice ||
        (viewMode == null && privacyMode == PrivacyMode.ice);

    // 부끄럼 모드 (안개): 흐릿한 후광
    if (showAsFog) {
      canvas.drawCircle(
        Offset(cx, avatarCy),
        avatarR + ringW + 14 * r,
        Paint()
          ..color = color.withAlpha(50)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 10 * r),
      );
    }

    // 드롭 섀도우
    canvas.drawCircle(
      Offset(cx, avatarCy + 3 * r),
      avatarR + ringW - r,
      Paint()
        ..color = Colors.black.withAlpha(70)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 6 * r),
    );

    // 외곽 그라디언트 링
    canvas.drawCircle(
      Offset(cx, avatarCy),
      avatarR + ringW,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(cx - avatarR, avatarCy - avatarR),
          Offset(cx + avatarR, avatarCy + avatarR),
          [color, Color.lerp(color, Colors.black, 0.3) ?? color],
        ),
    );

    // 아바타 본체: 사진 있으면 사진, 없으면 첫 글자
    if (photo != null) {
      // 흰 배경 (사진 로딩 실패 대비)
      canvas.drawCircle(
        Offset(cx, avatarCy),
        avatarR,
        Paint()..color = Colors.white,
      );
      // 원형 클립으로 사진 그리기
      canvas.save();
      canvas.clipPath(Path()
        ..addOval(Rect.fromCircle(
            center: Offset(cx, avatarCy), radius: avatarR)));
      final srcW = photo.width.toDouble();
      final srcH = photo.height.toDouble();
      final dstSize = avatarR * 2;
      final scale = math.max(dstSize / srcW, dstSize / srcH);
      final takeW = dstSize / scale;
      final takeH = dstSize / scale;
      canvas.drawImageRect(
        photo,
        Rect.fromLTWH((srcW - takeW) / 2, (srcH - takeH) / 2, takeW, takeH),
        Rect.fromLTWH(cx - avatarR, avatarCy - avatarR, dstSize, dstSize),
        Paint(),
      );
      canvas.restore();

      // 잠수/얼음 모드: 사진 위에 반투명 흰 레이어
      if (showAsIce) {
        canvas.drawCircle(
          Offset(cx, avatarCy),
          avatarR,
          Paint()..color = Colors.white.withAlpha(140),
        );
      }
    } else {
      // 사진 없음 → 흰 배경 + 첫 글자
      canvas.drawCircle(
        Offset(cx, avatarCy),
        avatarR,
        Paint()..color = Colors.white,
      );
      if (showAsIce) {
        canvas.drawCircle(
          Offset(cx, avatarCy),
          avatarR,
          Paint()..color = Colors.white.withAlpha(180),
        );
      }
      final letter = (name.isNotEmpty ? name[0] : '?').toUpperCase();
      final letterPainter = TextPainter(textDirection: TextDirection.ltr)
        ..text = TextSpan(
          text: letter,
          style: TextStyle(
            fontSize: 22 * r,
            fontWeight: FontWeight.w800,
            color: showAsIce ? color.withAlpha(150) : color,
          ),
        )
        ..layout();
      letterPainter.paint(
          canvas,
          Offset(cx - letterPainter.width / 2,
              avatarCy - letterPainter.height / 2));
    }

    // 잠수/얼음 모드 표시 (좌하단 'Z')
    if (showAsIce) {
      final zCx = cx - avatarR + 2 * r;
      final zCy = avatarCy + avatarR - 4 * r;
      canvas.drawCircle(
          Offset(zCx, zCy), 10 * r, Paint()..color = Colors.white);
      canvas.drawCircle(Offset(zCx, zCy), 9 * r,
          Paint()..color = const Color(0xFF42A5F5));
      final zPainter = TextPainter(textDirection: TextDirection.ltr)
        ..text = TextSpan(
            text: 'Z',
            style: TextStyle(
                fontSize: 11 * r,
                fontWeight: FontWeight.w900,
                color: Colors.white))
        ..layout();
      zPainter.paint(canvas,
          Offset(zCx - zPainter.width / 2, zCy - zPainter.height / 2));
    }

    // 이모지 버블 (우상단)
    if (hasEmoji) {
      final bubbleCx = cx + avatarR - 4 * r;
      final bubbleCy = avatarTop + 4 * r;
      canvas.drawCircle(Offset(bubbleCx, bubbleCy), bubbleR + 1.5 * r,
          Paint()..color = Colors.white);
      canvas.drawCircle(
        Offset(bubbleCx, bubbleCy),
        bubbleR,
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(bubbleCx - bubbleR, bubbleCy - bubbleR),
            Offset(bubbleCx + bubbleR, bubbleCy + bubbleR),
            [const Color(0xFFFFF59D), const Color(0xFFFFB300)],
          ),
      );
      final emojiPainter = TextPainter(textDirection: TextDirection.ltr)
        ..text = TextSpan(text: emoji, style: TextStyle(fontSize: 18 * r))
        ..layout();
      emojiPainter.paint(
          canvas,
          Offset(bubbleCx - emojiPainter.width / 2,
              bubbleCy - emojiPainter.height / 2 + r));
    }

    // 꼬리 (아래)
    final tailPath = Path()
      ..moveTo(cx - 7 * r, avatarBottom - 2 * r)
      ..lineTo(cx + 7 * r, avatarBottom - 2 * r)
      ..lineTo(cx, avatarBottom + tailH)
      ..close();
    canvas.drawPath(
      tailPath,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(cx, avatarBottom),
          Offset(cx, avatarBottom + tailH),
          [color, Color.lerp(color, Colors.black, 0.3) ?? color],
        ),
    );

    // 이름 라벨 (아래)
    final labelY = avatarBottom + tailH + labelGap;
    final labelX = cx - labelW / 2;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(labelX, labelY, labelW, labelH),
        Radius.circular(10 * r),
      ),
      Paint()
        ..color = Colors.black.withAlpha(40)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 3 * r),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(labelX, labelY, labelW, labelH),
        Radius.circular(10 * r),
      ),
      Paint()..color = Colors.white,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(labelX, labelY, labelW, labelH),
        Radius.circular(10 * r),
      ),
      Paint()
        ..color = color.withAlpha(180)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5 * r,
    );
    namePainter.paint(canvas, Offset(labelX + labelPadH, labelY + labelPadV));

    // 호출 알림 배지 — pingCount > 0 일 때만 상단에 빨간 원 + 숫자
    if (pingCount > 0) {
      final badgeR = 10 * r;
      final badgeCx = cx + avatarR - 2 * r;
      final badgeCy = avatarTop + 2 * r;
      // 그림자
      canvas.drawCircle(
        Offset(badgeCx, badgeCy + 2 * r),
        badgeR,
        Paint()
          ..color = Colors.black.withAlpha(70)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 4 * r),
      );
      // 흰 테두리
      canvas.drawCircle(
          Offset(badgeCx, badgeCy), badgeR + 1.5 * r,
          Paint()..color = Colors.white);
      // 빨간 본체
      canvas.drawCircle(
          Offset(badgeCx, badgeCy), badgeR,
          Paint()..color = const Color(0xFFEA4335));
      // 숫자
      final label = pingCount > 99 ? '99+' : '$pingCount';
      final p = TextPainter(textDirection: TextDirection.ltr)
        ..text = TextSpan(
          text: label,
          style: TextStyle(
            color: Colors.white,
            fontSize: (pingCount > 9 ? 9.5 : 11) * r,
            fontWeight: FontWeight.w900,
          ),
        )
        ..layout();
      p.paint(canvas,
          Offset(badgeCx - p.width / 2, badgeCy - p.height / 2));
    }

    final img = await recorder.endRecording().toImage(totalW, totalH);
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    final icon = BitmapDescriptor.bytes(
      data!.buffer.asUint8List(),
      imagePixelRatio: r,
    );
    // 꼬리 꼭지점의 세로 위치 비율 (이 지점이 GPS 좌표에 오도록)
    final tailTipY = avatarBottom + tailH;
    final anchorY = (tailTipY / totalH).clamp(0.0, 1.0);
    return (icon: icon, anchorY: anchorY);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 하단 컨트롤 바 (내 상태 + 프라이버시 모드)
// ─────────────────────────────────────────────────────────────────────────────

class _LiveControlBar extends StatelessWidget {
  final LiveUser? me;
  final VoidCallback onStatusTap;
  final VoidCallback onPrivacyTap;
  const _LiveControlBar({
    required this.me,
    required this.onStatusTap,
    required this.onPrivacyTap,
  });

  @override
  Widget build(BuildContext context) {
    final status = me?.status;
    final mode = me?.privacyMode ?? PrivacyMode.fog;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.full),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(40),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          // 상태 칩
          Expanded(
            child: GestureDetector(
              onTap: onStatusTap,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  gradient: status != null
                      ? const LinearGradient(colors: [
                          Color(0xFFFFF8E1),
                          Color(0xFFFFE082),
                        ])
                      : null,
                  color: status == null ? AppColors.surfaceVariant : null,
                  borderRadius: BorderRadius.circular(AppRadius.full),
                ),
                child: Row(
                  children: [
                    Text(status?.emoji ?? '🙂',
                        style: const TextStyle(fontSize: 20)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        status?.label ?? '상태 설정',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: status != null
                              ? AppColors.textPrimary
                              : AppColors.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // 프라이버시 토글
          GestureDetector(
            onTap: onPrivacyTap,
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(AppRadius.full),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(mode.emoji, style: const TextStyle(fontSize: 18)),
                  const SizedBox(width: 4),
                  Text(
                    mode.label,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 상단 컨트롤
// ─────────────────────────────────────────────────────────────────────────────

class _RoundIconButton extends StatelessWidget {
  final IconData icon;
  final Color? color;
  final VoidCallback onTap;
  const _RoundIconButton({required this.icon, this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 4,
      shape: const CircleBorder(),
      color: Theme.of(context).colorScheme.surface,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(icon,
              color: color ?? AppColors.textPrimary, size: 22),
        ),
      ),
    );
  }
}

class _CountChip extends StatelessWidget {
  final int count;
  final VoidCallback? onTap;
  const _CountChip({required this.count, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(AppRadius.full),
      elevation: 2,
      shadowColor: Colors.black.withAlpha(60),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.full),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: Color(0xFF34A853),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '$count명 라이브',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (onTap != null) ...[
                const SizedBox(width: 4),
                const Icon(Icons.expand_more,
                    size: 16, color: AppColors.textSecondary),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 라이브 친구 리스트 시트
// ─────────────────────────────────────────────────────────────────────────────

class _LiveFriendsSheet extends StatelessWidget {
  final List<LiveUser> friends;
  final String? myUid;
  final ValueChanged<LiveUser> onTapFriend;

  const _LiveFriendsSheet({
    required this.friends,
    required this.myUid,
    required this.onTapFriend,
  });

  String _timeAgo(DateTime? t) {
    if (t == null) return '오프라인';
    final diff = DateTime.now().difference(t);
    if (diff.inSeconds < 60) return '방금 전';
    if (diff.inMinutes < 60) return '${diff.inMinutes}분 전';
    if (diff.inHours < 24) return '${diff.inHours}시간 전';
    return '${diff.inDays}일 전';
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        final cs = Theme.of(context).colorScheme;
        return Container(
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: cs.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 4),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Color(0xFF34A853),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '라이브 친구 ${friends.length}명',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: cs.onSurface,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                      iconSize: 20,
                      color: cs.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
              if (friends.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(40),
                  child: Column(
                    children: [
                      Icon(Icons.people_outline,
                          size: 48, color: cs.outline),
                      const SizedBox(height: 12),
                      Text(
                        '지금 라이브 중인 친구가 없어요',
                        style: TextStyle(
                            fontSize: 13, color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                )
              else
                Expanded(
                  child: ListView.separated(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(8, 4, 8, 24),
                    itemCount: friends.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 2),
                    itemBuilder: (_, i) {
                      final u = friends[i];
                      final isMe = u.uid == myUid;
                      final isLive = u.location != null &&
                          DateTime.now()
                                  .difference(u.location!.updatedAt)
                                  .inSeconds <
                              60;
                      return ListTile(
                        leading: Stack(
                          children: [
                            CircleAvatar(
                              radius: 22,
                              backgroundColor: cs.surfaceContainerHighest,
                              backgroundImage:
                                  (u.photoUrl != null && u.photoUrl!.isNotEmpty)
                                      ? NetworkImage(u.photoUrl!)
                                      : null,
                              child:
                                  (u.photoUrl == null || u.photoUrl!.isEmpty)
                                      ? Text(
                                          u.displayName.isNotEmpty
                                              ? u.displayName[0].toUpperCase()
                                              : '?',
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w800,
                                            color: cs.onSurface,
                                          ),
                                        )
                                      : null,
                            ),
                            if (isLive)
                              Positioned(
                                right: 0,
                                bottom: 0,
                                child: Container(
                                  width: 12,
                                  height: 12,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF34A853),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                        color: cs.surface, width: 2),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        title: Row(
                          children: [
                            Flexible(
                              child: Text(
                                u.displayName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w700,
                                  color: cs.onSurface,
                                ),
                              ),
                            ),
                            if (isMe) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 1),
                                decoration: BoxDecoration(
                                  color: cs.primary.withAlpha(40),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '나',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    color: cs.primary,
                                  ),
                                ),
                              ),
                            ],
                            if (u.status?.emoji != null) ...[
                              const SizedBox(width: 6),
                              Text(u.status!.emoji,
                                  style: const TextStyle(fontSize: 14)),
                            ],
                          ],
                        ),
                        subtitle: Row(
                          children: [
                            if (isLive)
                              const Padding(
                                padding: EdgeInsets.only(right: 4),
                                child: Text(
                                  '●',
                                  style: TextStyle(
                                    fontSize: 9,
                                    color: Color(0xFF34A853),
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            Text(
                              _timeAgo(u.location?.updatedAt),
                              style: TextStyle(
                                fontSize: 11.5,
                                color: isLive
                                    ? const Color(0xFF34A853)
                                    : cs.onSurfaceVariant,
                                fontWeight: isLive
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                            ),
                            if (u.status?.label != null &&
                                u.status!.label.isNotEmpty) ...[
                              Text('  ·  ',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: cs.outline)),
                              Flexible(
                                child: Text(
                                  u.status!.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        trailing: Icon(Icons.my_location,
                            size: 18, color: cs.primary),
                        onTap: () {
                          HapticFeedback.selectionClick();
                          onTapFriend(u);
                        },
                      );
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 상태 선택 시트
// ─────────────────────────────────────────────────────────────────────────────

class _StatusPickerSheet extends StatefulWidget {
  final UserStatus? current;
  const _StatusPickerSheet({this.current});

  @override
  State<_StatusPickerSheet> createState() => _StatusPickerSheetState();
}

class _StatusPickerSheetState extends State<_StatusPickerSheet> {
  late String _emoji;
  late TextEditingController _labelCtrl;

  @override
  void initState() {
    super.initState();
    _emoji = widget.current?.emoji ?? '☕';
    _labelCtrl = TextEditingController(
        text: widget.current?.label ?? '');
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
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
          const Text(
            '지금 뭐해?',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            '이모지 하나로 친구들에게 알려보세요',
            style: TextStyle(
                fontSize: 12, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 18),
          // 프리셋 그리드
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: StatusPresets.presets.map((p) {
                final selected = _emoji == p.emoji;
                return GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() {
                      _emoji = p.emoji;
                      _labelCtrl.text = p.label;
                    });
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 7),
                    decoration: BoxDecoration(
                      gradient: selected
                          ? const LinearGradient(colors: [
                              Color(0xFFFFF59D),
                              Color(0xFFFFB300),
                            ])
                          : null,
                      color: selected ? null : Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(p.emoji,
                            style: const TextStyle(fontSize: 18)),
                        const SizedBox(width: 5),
                        Text(
                          p.label,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: selected
                                ? AppColors.textPrimary
                                : AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 18),
          // 커스텀 라벨 입력
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _labelCtrl,
              maxLength: 14,
              decoration: InputDecoration(
                prefixIcon: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text(_emoji,
                      style: const TextStyle(fontSize: 22)),
                ),
                prefixIconConstraints:
                    const BoxConstraints(minWidth: 0, minHeight: 0),
                hintText: '직접 입력 (예: 점심 만끽 중)',
                counterText: '',
                filled: true,
                fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(
                        context, (emoji: '', label: '')),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: BorderSide(
                        color: AppColors.textDisabled
                            .withValues(alpha: 0.5),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(AppRadius.full),
                      ),
                    ),
                    child: const Text('상태 끄기',
                        style: TextStyle(
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      final label = _labelCtrl.text.trim();
                      Navigator.pop(
                          context, (emoji: _emoji, label: label));
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(AppRadius.full),
                      ),
                      elevation: 2,
                    ),
                    child: const Text('저장',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 프라이버시 모드 시트
// ─────────────────────────────────────────────────────────────────────────────

class _PrivacyModeSheet extends StatelessWidget {
  final PrivacyMode? current;
  const _PrivacyModeSheet({this.current});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
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
            const SizedBox(height: 16),
            const Text(
              '위치 공개 모드',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 14),
            ...PrivacyMode.values.map((m) => _PrivacyTile(
                  mode: m,
                  selected: current == m,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    Navigator.pop(context, m);
                  },
                )),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

class _PrivacyTile extends StatelessWidget {
  final PrivacyMode mode;
  final bool selected;
  final VoidCallback onTap;
  const _PrivacyTile({
    required this.mode,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.08)
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? AppColors.primary
                : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            Text(mode.emoji, style: const TextStyle(fontSize: 28)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    mode.label,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    mode.description,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            if (selected)
              const Icon(Icons.check_circle,
                  color: AppColors.primary, size: 22),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 사용자 상세 시트 (마커 탭 시)
// ─────────────────────────────────────────────────────────────────────────────

class _UserDetailSheet extends StatelessWidget {
  final LiveUser user;
  final bool isMe;
  final FriendEffectiveMode? effectiveMode; // 친구가 나에게 적용 중인 모드
  final Friendship? theirView;               // 친구의 나에 대한 setting
  final List<Ping> pings;
  const _UserDetailSheet({
    required this.user,
    required this.isMe,
    this.effectiveMode,
    this.theirView,
    this.pings = const [],
  });

  Future<void> _sendPing(
      BuildContext context, String emoji, String message) async {
    final me = FirebaseAuth.instance.currentUser;
    if (me == null) return;
    HapticFeedback.mediumImpact();
    Navigator.pop(context); // 시트 먼저 닫기
    try {
      await UserStatusService.sendPing(
        toUid: user.uid,
        fromUid: me.uid,
        fromName: me.displayName ?? me.email ?? '익명',
        emoji: emoji,
        message: message,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$emoji "${user.displayName}"님에게 "$message" 전송'),
            backgroundColor: AppColors.primary,
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('호출 실패: $e'),
              backgroundColor: AppColors.error),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = user.status;
    final color = _LiveMapScreenState
        ._avatarColors[user.displayName.hashCode.abs() %
            _LiveMapScreenState._avatarColors.length];

    return Container(
      margin: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg + 4),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withAlpha(50),
              blurRadius: 20,
              offset: const Offset(0, 8)),
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.textDisabled.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  // 아바타 — 사진 있으면 NetworkImage, 없으면 컬러 + 첫 글자
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: user.photoUrl == null ||
                              user.photoUrl!.isEmpty
                          ? LinearGradient(
                              colors: [
                                color,
                                Color.lerp(color, Colors.black, 0.3) ?? color,
                              ],
                            )
                          : null,
                      image: user.photoUrl != null && user.photoUrl!.isNotEmpty
                          ? DecorationImage(
                              image: NetworkImage(user.photoUrl!),
                              fit: BoxFit.cover,
                            )
                          : null,
                    ),
                    alignment: Alignment.center,
                    child: (user.photoUrl == null || user.photoUrl!.isEmpty)
                        ? Text(
                            user.displayName.isNotEmpty
                                ? user.displayName[0].toUpperCase()
                                : '?',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 26,
                              fontWeight: FontWeight.w800,
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                user.displayName,
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w800,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (isMe) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.primary,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text(
                                  '나',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        // 상태
                        if (status != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(colors: [
                                Color(0xFFFFF8E1),
                                Color(0xFFFFE082),
                              ]),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(status.emoji,
                                    style: const TextStyle(fontSize: 14)),
                                const SizedBox(width: 4),
                                Text(
                                  status.label.isEmpty
                                      ? '상태 없음'
                                      : status.label,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          )
                        else
                          Text(
                            '상태 없음',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary
                                  .withValues(alpha: 0.7),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // 프라이버시 + 위치 시간 정보
              // 친구: 친구가 나에게 적용 중인 effective mode 표시 (정확/흐릿/얼음)
              // 본인: 내 마스터 privacy mode 표시
              _PrivacyInfoCard(
                user: user,
                isMe: isMe,
                effectiveMode: effectiveMode,
                theirView: theirView,
              ),

              // 받은 호출 (본인 마커 + 미확인 호출 있을 때만)
              if (isMe && pings.isNotEmpty) ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Text(
                      '받은 호출',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 1),
                      decoration: BoxDecoration(
                        color: AppColors.error,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${pings.length}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: () async {
                        HapticFeedback.lightImpact();
                        final uid =
                            FirebaseAuth.instance.currentUser?.uid;
                        if (uid == null) return;
                        for (final p in pings) {
                          await UserStatusService.deletePing(uid, p.id);
                        }
                        if (context.mounted) Navigator.pop(context);
                      },
                      icon: const Icon(Icons.done_all,
                          size: 16, color: AppColors.primary),
                      label: const Text(
                        '모두 확인',
                        style: TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        minimumSize: Size.zero,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ...pings.map((p) => Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [
                          Color(0xFFFFF8E1),
                          Color(0xFFFFECB3),
                        ]),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Text(p.emoji,
                              style: const TextStyle(fontSize: 22)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '${p.fromName} · ${p.message}',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  _pingTime(p.createdAt),
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close,
                                size: 18,
                                color: AppColors.textSecondary),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                                minWidth: 28, minHeight: 28),
                            onPressed: () async {
                              HapticFeedback.lightImpact();
                              final uid = FirebaseAuth
                                  .instance.currentUser?.uid;
                              if (uid != null) {
                                await UserStatusService.deletePing(
                                    uid, p.id);
                              }
                            },
                          ),
                        ],
                      ),
                    )),
              ],

              // 호출 칩 (다른 사용자에게만 표시)
              if (!isMe) ...[
                const SizedBox(height: 16),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '호출하기',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: PingPresets.presets.map((p) {
                    return GestureDetector(
                      onTap: () => _sendPing(context, p.emoji, p.message),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Color(0xFFFFF59D),
                              Color(0xFFFFB300),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFFFA726)
                                  .withValues(alpha: 0.4),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(p.emoji,
                                style: const TextStyle(fontSize: 16)),
                            const SizedBox(width: 5),
                            Text(
                              p.message,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static String _pingTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return '방금 전';
    if (diff.inMinutes < 60) return '${diff.inMinutes}분 전';
    if (diff.inHours < 24) return '${diff.inHours}시간 전';
    return '${diff.inDays}일 전';
  }

}

// ─── 프라이버시 정보 카드 ─────────────────────────────────────────────────────
// 친구: effective mode (친구가 나에게 적용 중인 정확/흐릿/얼음)
// 본인: 내 마스터 privacy mode
// ─────────────────────────────────────────────────────────────────────────────
class _PrivacyInfoCard extends StatelessWidget {
  final LiveUser user;
  final bool isMe;
  final FriendEffectiveMode? effectiveMode;
  final Friendship? theirView;
  const _PrivacyInfoCard({
    required this.user,
    required this.isMe,
    this.effectiveMode,
    this.theirView,
  });

  String _modeEmoji() {
    if (!isMe && effectiveMode != null) {
      return switch (effectiveMode!) {
        FriendEffectiveMode.precise => '🔥',
        FriendEffectiveMode.fog => '☁️',
        FriendEffectiveMode.ice => '🤿',
      };
    }
    return user.privacyMode.emoji;
  }

  String _modeLabel() {
    if (!isMe && effectiveMode != null) {
      return switch (effectiveMode!) {
        FriendEffectiveMode.precise => '정확하게 공유 중',
        FriendEffectiveMode.fog => '흐릿하게 공유 중 (안개)',
        FriendEffectiveMode.ice => '위치 고정 (얼음)',
      };
    }
    return user.privacyMode.label;
  }

  String? _modeRationale() {
    if (isMe || theirView == null) return null;
    final name = user.displayName;
    // 개별 오버라이드 우선
    if (theirView!.individualMode == FriendIndividualMode.precise) {
      return '$name님이 당신만 정확히 보이게 설정함';
    }
    if (theirView!.individualMode == FriendIndividualMode.ice) {
      return '$name님이 당신만 위치 고정으로 설정함';
    }
    // 마스터가 제한적이면 그것이 적용된 것
    if (user.privacyMode == PrivacyMode.ice) {
      return '$name님이 잠수 모드 — 모두에게 위치 고정';
    }
    if (user.privacyMode == PrivacyMode.fog) {
      return '$name님이 부끄럼 모드 — 모두에게 흐릿하게';
    }
    // 그룹 적용
    return switch (theirView!.relType) {
      FriendRelType.best => '$name님이 당신을 베프 💖 그룹으로 설정',
      FriendRelType.normal => '$name님이 당신을 부끄럼 🙈 그룹으로 설정',
      FriendRelType.bad => '$name님이 당신을 잠수 🥷 그룹으로 설정',
    };
  }

  @override
  Widget build(BuildContext context) {
    final rationale = _modeRationale();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Text(_modeEmoji(), style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _modeLabel(),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (rationale != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    rationale,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                const SizedBox(height: 1),
                Text(
                  _relativeTimeStatic(user.location?.updatedAt),
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _relativeTimeStatic(DateTime? dt) {
    if (dt == null) return '위치 정보 없음';
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return '방금 전 업데이트';
    if (diff.inMinutes < 60) return '${diff.inMinutes}분 전 업데이트';
    if (diff.inHours < 24) return '${diff.inHours}시간 전 업데이트';
    return '${diff.inDays}일 전 업데이트';
  }
}

// ─── 그룹 필터 칩 (친구지도 상단) ──────────────────────────────────────────
class _GroupFilterChip extends StatelessWidget {
  final String label;
  final String emoji;
  final bool selected;
  final VoidCallback onTap;
  final GroupMode? mode;
  const _GroupFilterChip({
    required this.label,
    required this.emoji,
    required this.selected,
    required this.onTap,
    this.mode,
  });

  Color _modeAccent() {
    switch (mode) {
      case GroupMode.insider:
        return const Color(0xFFEC407A);
      case GroupMode.shy:
        return const Color(0xFFFFA726);
      case GroupMode.uneasy:
        return const Color(0xFF607D8B);
      case null:
        return AppColors.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = _modeAccent();
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? accent : AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.full),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(28),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
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
            if (mode != null && !selected) ...[
              const SizedBox(width: 4),
              Text(mode!.emoji, style: const TextStyle(fontSize: 10)),
            ],
          ],
        ),
      ),
    );
  }
}
