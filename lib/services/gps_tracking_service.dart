import 'dart:async';
import 'dart:convert';

import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/gps_point.dart';
import '../models/recording_session.dart';

/// 1초 간격 GPS 트래킹 서비스
///
/// 사용 예:
/// ```dart
/// final svc = GpsTrackingService();
/// await svc.start(mediaType: MediaType.video);
/// // ... 촬영 중 ...
/// final session = await svc.stop(mediaPath: '/path/to/video.mp4');
/// ```
class GpsTrackingService {
  static const _sessionsKey = 'gps_sessions';

  Timer? _timer;
  DateTime? _startTime;
  MediaType? _mediaType;
  final List<GpsPoint> _points = [];

  bool get isTracking => _timer != null;

  /// 현재 수집된 GPS 포인트 수
  int get pointCount => _points.length;

  /// 가장 최근 GPS 포인트
  GpsPoint? get latestPoint => _points.isEmpty ? null : _points.last;

  // 실시간 위치 스트림 (UI 업데이트용)
  final _positionController = StreamController<GpsPoint?>.broadcast();
  Stream<GpsPoint?> get positionStream => _positionController.stream;

  /// 트래킹 시작
  Future<void> start({required MediaType mediaType}) async {
    if (_timer != null) return; // 이미 실행 중

    _startTime = DateTime.now();
    _mediaType = mediaType;
    _points.clear();

    // 즉시 첫 위치 수집
    await _collectPoint();

    // 1초 간격으로 반복 수집
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _collectPoint());
  }

  /// 트래킹 종료 → RecordingSession 반환
  Future<RecordingSession> stop({String? mediaPath}) async {
    _timer?.cancel();
    _timer = null;

    final session = RecordingSession(
      id: _startTime!.millisecondsSinceEpoch.toString(),
      startTime: _startTime!,
      endTime: DateTime.now(),
      mediaType: _mediaType!,
      mediaPath: mediaPath,
      gpsTrack: List.unmodifiable(_points),
    );

    await _saveSession(session);

    _startTime = null;
    _mediaType = null;
    _points.clear();

    return session;
  }

  /// 트래킹 취소 (저장 안 함)
  void cancel() {
    _timer?.cancel();
    _timer = null;
    _startTime = null;
    _mediaType = null;
    _points.clear();
    _positionController.add(null);
  }

  /// GPS 포인트 수집 (내부)
  Future<void> _collectPoint() async {
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 3),
        ),
      );

      final videoTimeMs = _startTime == null
          ? 0
          : DateTime.now().difference(_startTime!).inMilliseconds;

      final point = GpsPoint(
        lat: pos.latitude,
        lng: pos.longitude,
        altitude: pos.altitude,
        accuracy: pos.accuracy,
        speed: pos.speed,
        timestamp: DateTime.now(),
        videoTimeMs: videoTimeMs,
      );

      _points.add(point);
      _positionController.add(point);
    } catch (_) {
      // GPS 오류 시 건너뜀 (영상 촬영은 계속)
    }
  }

  // ─── 로컬 저장 ────────────────────────────────────────────────────────────

  Future<void> _saveSession(RecordingSession session) async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getStringList(_sessionsKey) ?? [];
    existing.add(session.toJsonString());
    await prefs.setStringList(_sessionsKey, existing);
  }

  /// 저장된 세션 목록 불러오기
  static Future<List<RecordingSession>> loadSessions() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_sessionsKey) ?? [];
    return raw
        .map((s) => RecordingSession.fromJson(
            jsonDecode(s) as Map<String, dynamic>))
        .toList()
      ..sort((a, b) => b.startTime.compareTo(a.startTime));
  }

  /// 현재 위치만 단발성으로 가져오기 (사진 촬영용)
  static Future<GpsPoint?> getCurrentPoint() async {
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 5),
        ),
      );
      return GpsPoint(
        lat: pos.latitude,
        lng: pos.longitude,
        altitude: pos.altitude,
        accuracy: pos.accuracy,
        speed: pos.speed,
        timestamp: DateTime.now(),
        videoTimeMs: 0,
      );
    } catch (_) {
      return null;
    }
  }

  void dispose() {
    _timer?.cancel();
    _positionController.close();
  }
}
