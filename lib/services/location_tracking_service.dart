import 'dart:async';
import 'dart:math' as math;

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';

import 'user_status_service.dart';

/// 앱 전역 위치 추적 서비스 (싱글톤).
///
/// 기존엔 친구지도 화면이 떠 있을 때만 위치를 갱신했지만, 이제 MainShell이
/// 살아있는 동안(= 앱이 켜진 동안, 어느 탭에서든) 동적 주기로 내 위치를 기록한다.
///
/// 갱신 주기:
///  - 친구지도 활성 + 포그라운드 : 10초 (거의 실시간)
///  - 배터리 ≤ 15%             : 30분 (강제 절전)
///  - 이동 중                  : 1분
///  - 그 외(다른 화면/정지)    : 5분 (앱 내 전역 기본)
///
/// ⚠️ Dart 타이머는 OS가 앱을 백그라운드로 내리면 멈춘다. 즉 "앱이 켜진 동안"
///    동작하며, 앱을 완전히 닫으면 추적이 멈춘다(진짜 OS 백그라운드 추적은 별도).
/// ⚠️ 권한 프롬프트는 띄우지 않는다(이미 허용된 경우에만 기록). 권한 요청은
///    친구지도 진입 시 화면에서 처리한다.
class LocationTrackingService with WidgetsBindingObserver {
  LocationTrackingService._();
  static final LocationTrackingService instance = LocationTrackingService._();

  String? _uid;
  bool _onLiveMap = false;
  AppLifecycleState _appState = AppLifecycleState.resumed;
  bool _isMoving = false;
  int _batteryLevel = 100;

  Timer? _locationTimer;
  StreamSubscription? _accelSub;
  Timer? _batteryTimer;
  final Battery _battery = Battery();

  // 가속도 누적 (이동 감지) — 30초 윈도우
  double _accelAccum = 0;
  int _accelSamples = 0;

  /// 최근 측정 위치 (카메라 초기화용 캐시)
  Position? lastPosition;

  bool get isRunning => _uid != null;

  /// 로그인 후 MainShell에서 호출 — 전역 추적 시작
  void start(String uid) {
    if (_uid == uid && _locationTimer != null) return; // 이미 동작 중
    _uid = uid;
    WidgetsBinding.instance.addObserver(this);
    _startAccelMonitor();
    _startBatteryMonitor();
    _scheduleTimer();
    updateNow(); // 즉시 1회 (권한 있으면)
  }

  /// 로그아웃·앱 종료 시 호출 — 추적 정지 + 리소스 정리
  void stop() {
    _uid = null;
    _onLiveMap = false;
    WidgetsBinding.instance.removeObserver(this);
    _locationTimer?.cancel();
    _locationTimer = null;
    _accelSub?.cancel();
    _accelSub = null;
    _batteryTimer?.cancel();
    _batteryTimer = null;
    _accelAccum = 0;
    _accelSamples = 0;
    _isMoving = false;
  }

  /// 친구지도 진입/이탈 시 호출 — 활성 중엔 10초 고속 갱신
  void setOnLiveMap(bool active) {
    if (_onLiveMap == active) return;
    _onLiveMap = active;
    _scheduleTimer();
    if (active) updateNow(); // 지도 진입 즉시 갱신
  }

  /// 마지막으로 알려진 위치 (권한 프롬프트 없음, 즉시 반환). 웹은 null.
  Future<Position?> lastKnown() async {
    try {
      return await Geolocator.getLastKnownPosition();
    } catch (_) {
      return null;
    }
  }

  /// 현재 위치 측정 → Firestore 기록. 반환: 측정 위치(권한 없음/실패 시 null).
  /// 권한 프롬프트는 띄우지 않는다(이미 허용된 경우에만).
  Future<Position?> updateNow() async {
    final uid = _uid;
    if (uid == null) return null;
    try {
      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return null; // 미허용 — 프롬프트 없이 조용히 건너뜀
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.medium,
            timeLimit: Duration(seconds: 12)),
      );
      lastPosition = pos;
      await UserStatusService.updateLocation(
        uid: uid,
        lat: pos.latitude,
        lng: pos.longitude,
        isMoving: _isMoving,
        batteryLevel: _batteryLevel,
      );
      return pos;
    } catch (_) {
      return null;
    }
  }

  /// 현재 상태에 맞는 갱신 주기
  Duration _interval() {
    if (_appState == AppLifecycleState.resumed && _onLiveMap) {
      return const Duration(seconds: 10); // 친구지도 활성(거의 실시간)
    }
    if (_batteryLevel <= 15) {
      return const Duration(minutes: 30); // 배터리 절전
    }
    if (_isMoving) {
      return const Duration(minutes: 1); // 이동 중
    }
    return const Duration(minutes: 5); // 앱 내 전역 기본(정지/다른 화면)
  }

  void _scheduleTimer() {
    if (_uid == null) return;
    _locationTimer?.cancel();
    final interval = _interval();
    debugPrint('[Tracking] 주기 → $interval'
        ' (onMap=$_onLiveMap, state=$_appState,'
        ' moving=$_isMoving, battery=$_batteryLevel%)');
    _locationTimer = Timer.periodic(interval, (_) => updateNow());
  }

  /// 가속도계 — 1초 샘플링, 30개(≈30초)마다 이동 여부 판정
  void _startAccelMonitor() {
    _accelSub?.cancel();
    _accelSub = accelerometerEventStream(
            samplingPeriod: const Duration(seconds: 1))
        .listen((e) {
      final magnitude = math.sqrt(e.x * e.x + e.y * e.y + e.z * e.z);
      _accelAccum += (magnitude - 9.8).abs();
      _accelSamples++;
      if (_accelSamples >= 30) {
        final avg = _accelAccum / _accelSamples;
        final wasMoving = _isMoving;
        _isMoving = avg > 0.5; // 임계값 0.5 m/s²
        _accelAccum = 0;
        _accelSamples = 0;
        if (wasMoving != _isMoving) _scheduleTimer();
      }
    }, onError: (_) {});
  }

  /// 배터리 — 초기 1회 + 5분마다 갱신
  Future<void> _startBatteryMonitor() async {
    try {
      _batteryLevel = await _battery.batteryLevel;
    } catch (_) {}
    _batteryTimer?.cancel();
    _batteryTimer = Timer.periodic(const Duration(minutes: 5), (_) async {
      try {
        final level = await _battery.batteryLevel;
        final wasLow = _batteryLevel <= 15;
        final isLow = level <= 15;
        _batteryLevel = level;
        if (wasLow != isLow) _scheduleTimer();
      } catch (_) {}
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final prev = _appState;
    _appState = state;
    if (state == AppLifecycleState.resumed) {
      updateNow(); // 포그라운드 복귀 → 즉시 갱신
    }
    if (prev != state) _scheduleTimer();
  }
}
