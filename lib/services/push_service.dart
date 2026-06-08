import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';

import '../firebase_options.dart';
import '../screens/live_map/live_map_screen.dart';
import '../screens/vlog/vlog_player_screen.dart';
import '../services/firestore_service.dart';
import '../services/user_status_service.dart';
import '../utils/constants.dart';
import '../widgets/notifications_sheet.dart';

/// 전역 Navigator 키 — 알림 탭 시 어디서든 화면 이동에 사용.
/// MaterialApp.navigatorKey 에 연결됨.
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

/// 백그라운드/종료 상태 메시지 핸들러 — 반드시 top-level + vm:entry-point.
/// 시스템 트레이 알림 표시는 FCM 이 notification 페이로드로 자동 처리하므로
/// 여기서는 로깅만 한다. (필요 시 데이터 가공 가능)
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('[Push] background message: ${message.messageId}');
  // 위치 핑 — 서버 스케줄러가 깨운 경우: 백그라운드(앱 종료 포함)에서 위치 기록
  if (message.data['type'] == 'loc_ping') {
    await _handleLocPing(message.data);
  }
}

/// FCM로 깨어난 백그라운드 isolate에서 현재 위치를 측정해 Firestore에 기록.
/// 앱이 완전히 종료돼 있어도 OS가 이 핸들러를 실행한다(고우선순위 data 메시지).
@pragma('vm:entry-point')
Future<void> _handleLocPing(Map<String, dynamic> data) async {
  try {
    // 백그라운드 isolate — Firebase 재초기화 필요
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform);
    }
    final uid = data['uid'] as String?;
    if (uid == null || uid.isEmpty) return;
    final perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      return;
    }
    final pos = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium, timeLimit: Duration(seconds: 20)),
    );
    // privacyMode=ice(잠수)면 updateLocation 내부에서 기록 skip, fog면 마스킹
    await UserStatusService.updateLocation(
        uid: uid, lat: pos.latitude, lng: pos.longitude);
    debugPrint('[Push] loc_ping → 위치 기록 완료 ($uid)');
  } catch (e) {
    debugPrint('[Push] loc_ping error: $e');
  }
}

/// FCM 푸시 알림 서비스 (싱글톤)
///
/// - 로그인 후 [init] 호출 → 권한요청 + 토큰 저장 + 핸들러 등록
/// - 로그아웃 시 [unregister] 호출 → 토큰 삭제
///
/// 토큰 저장 위치: `users/{uid}/fcmTokens/{token}` { platform, updatedAt }
/// Cloud Functions 가 이 서브컬렉션을 읽어 멀티캐스트 발송한다.
class PushService {
  PushService._();
  static final PushService instance = PushService._();

  final FirebaseMessaging _fm = FirebaseMessaging.instance;
  bool _listenersAttached = false;
  String? _currentUid;

  /// 로그인 사용자 기준 초기화
  Future<void> init(String uid) async {
    _currentUid = uid;

    // 1) 권한 요청 (iOS / Web / Android 13+)
    try {
      await _fm.requestPermission(alert: true, badge: true, sound: true);
    } catch (e) {
      debugPrint('[Push] permission error: $e');
    }

    // 2) 포그라운드에서도 시스템 알림 표시 (iOS/web)
    try {
      await _fm.setForegroundNotificationPresentationOptions(
          alert: true, badge: true, sound: true);
    } catch (_) {}

    // 3) 토큰 발급 + 저장
    await _registerToken(uid);
    _fm.onTokenRefresh.listen((t) {
      if (_currentUid != null) _saveToken(_currentUid!, t);
    });

    // 4) 메시지 핸들러 (앱 생애 1회만 부착)
    if (!_listenersAttached) {
      _listenersAttached = true;
      FirebaseMessaging.onMessage.listen(_onForegroundMessage);
      FirebaseMessaging.onMessageOpenedApp.listen(
          (m) => _handleNavigation(m.data));
      // 종료 상태에서 알림 탭으로 콜드 스타트한 경우
      final initial = await _fm.getInitialMessage();
      if (initial != null) {
        WidgetsBinding.instance.addPostFrameCallback(
            (_) => _handleNavigation(initial.data));
      }
    }
  }

  Future<void> _registerToken(String uid) async {
    try {
      final token = await _getToken();
      if (token != null) await _saveToken(uid, token);
    } catch (e) {
      debugPrint('[Push] getToken error: $e');
    }
  }

  Future<String?> _getToken() {
    if (kIsWeb) {
      // 웹은 VAPID 키 필요 — 미설정 시 토큰 발급 생략
      if (kWebVapidKey.isEmpty) {
        debugPrint('[Push] kWebVapidKey 미설정 → 웹 토큰 생략');
        return Future.value(null);
      }
      return _fm.getToken(vapidKey: kWebVapidKey);
    }
    return _fm.getToken();
  }

  Future<void> _saveToken(String uid, String token) async {
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('fcmTokens')
          .doc(token)
          .set({
        'platform': kIsWeb ? 'web' : defaultTargetPlatform.name,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      debugPrint('[Push] token saved (${token.substring(0, 12)}…)');
    } catch (e) {
      debugPrint('[Push] saveToken error: $e');
    }
  }

  /// 로그아웃 시 호출 — 이 기기 토큰을 서버에서 제거하고 로컬 토큰 무효화
  Future<void> unregister(String uid) async {
    try {
      final token = await _getToken();
      if (token != null) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('fcmTokens')
            .doc(token)
            .delete();
      }
      await _fm.deleteToken();
    } catch (e) {
      debugPrint('[Push] unregister error: $e');
    }
    _currentUid = null;
  }

  // ── 포그라운드 인앱 배너 ──────────────────────────────────────────────────
  void _onForegroundMessage(RemoteMessage m) {
    final ctx = rootNavigatorKey.currentContext;
    if (ctx == null) return;
    final title = m.notification?.title ?? m.data['title'] ?? '알림';
    final body = m.notification?.body ?? m.data['body'] ?? '';
    final emoji = m.data['emoji'] as String?;
    HapticFeedback.mediumImpact();
    final messenger = ScaffoldMessenger.of(ctx);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 5),
        backgroundColor: Theme.of(ctx).colorScheme.surface,
        elevation: 6,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg)),
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 80),
        content: InkWell(
          onTap: () {
            messenger.hideCurrentSnackBar();
            _handleNavigation(m.data);
          },
          child: Row(
            children: [
              Text(emoji ?? '🔔', style: const TextStyle(fontSize: 24)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 13)),
                    if (body.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(body,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(ctx)
                                  .colorScheme
                                  .onSurfaceVariant)),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── 알림 탭 → 화면 이동 ───────────────────────────────────────────────────
  Future<void> _handleNavigation(Map<String, dynamic> data) async {
    final nav = rootNavigatorKey.currentState;
    if (nav == null) return;
    final type = data['type'] as String?;
    switch (type) {
      case 'ping':
        nav.push(MaterialPageRoute(builder: (_) => const LiveMapScreen()));
        break;
      case 'friend_request':
        nav.push(MaterialPageRoute(builder: (_) => const NotificationsScreen()));
        break;
      case 'comment':
        final vlogId = data['vlogId'] as String?;
        if (vlogId == null || vlogId.isEmpty) return;
        try {
          final vlog = await FirestoreService.getVlog(vlogId);
          if (vlog != null) {
            nav.push(MaterialPageRoute(
                builder: (_) => VlogPlayerScreen(vlog: vlog)));
          }
        } catch (e) {
          debugPrint('[Push] comment nav error: $e');
        }
        break;
      case 'eventComment':
        final eventId = data['eventId'] as String?;
        if (eventId == null || eventId.isEmpty) return;
        try {
          final ev = await FirestoreService.getEvent(eventId);
          if (ev != null) {
            nav.push(MaterialPageRoute(
                builder: (_) => LiveMapScreen(focusEvent: ev)));
          }
        } catch (e) {
          debugPrint('[Push] eventComment nav error: $e');
        }
        break;
    }
  }
}
