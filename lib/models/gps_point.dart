/// GPS 좌표 한 점 — 촬영 중 1초 간격으로 기록
class GpsPoint {
  final double lat;
  final double lng;
  final double? altitude;   // 고도 (m)
  final double? accuracy;   // 수평 정확도 (m)
  final double? speed;      // 속도 (m/s)
  final DateTime timestamp;

  /// 영상 기준 타임코드 (ms) — 녹화 시작 시각과의 차이
  final int videoTimeMs;

  const GpsPoint({
    required this.lat,
    required this.lng,
    this.altitude,
    this.accuracy,
    this.speed,
    required this.timestamp,
    required this.videoTimeMs,
  });

  Map<String, dynamic> toJson() => {
        'lat': lat,
        'lng': lng,
        if (altitude != null) 'altitude': altitude,
        if (accuracy != null) 'accuracy': accuracy,
        if (speed != null) 'speed': speed,
        'timestamp': timestamp.toIso8601String(),
        'videoTimeMs': videoTimeMs,
      };

  factory GpsPoint.fromJson(Map<String, dynamic> j) => GpsPoint(
        lat: (j['lat'] as num).toDouble(),
        lng: (j['lng'] as num).toDouble(),
        altitude: (j['altitude'] as num?)?.toDouble(),
        accuracy: (j['accuracy'] as num?)?.toDouble(),
        speed: (j['speed'] as num?)?.toDouble(),
        timestamp: DateTime.parse(j['timestamp'] as String),
        videoTimeMs: j['videoTimeMs'] as int,
      );
}
