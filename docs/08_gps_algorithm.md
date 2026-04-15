# 08. GPS 보간 알고리즘 명세

## 개요

MapVlog의 핵심 기술인 **타임코드 ↔ GPS 좌표 변환 알고리즘**을 정의합니다.
영상 재생 중 현재 타임코드에 해당하는 GPS 좌표를 실시간으로 계산하여 지도 마커를 동기화합니다.

---

## 1. GPS 데이터 수집 (촬영 단계)

### 1.1 수집 주기

- 촬영 중 **1초 단위**로 GPS 좌표 기록
- 각 포인트: `{ t: 타임코드(초), lat: 위도, lng: 경도 }`

### 1.2 수집 예시

```json
[
  { "t": 0,  "lat": 37.5561, "lng": 126.9231 },
  { "t": 1,  "lat": 37.5562, "lng": 126.9232 },
  { "t": 2,  "lat": 37.5563, "lng": 126.9234 },
  { "t": 3,  "lat": 37.5565, "lng": 126.9237 },
  { "t": 5,  "lat": 37.5568, "lng": 126.9241 },
  { "t": 10, "lat": 37.5580, "lng": 126.9255 }
]
```

> **주의**: GPS 신호 불안정 시 일부 타임코드가 누락될 수 있습니다 (t=4, t=6~9 없음).
> 이 경우 보간법으로 추정 좌표를 계산합니다.

---

## 2. 선형 보간 (Linear Interpolation)

### 2.1 기본 원리

두 알려진 GPS 포인트 사이의 임의 타임코드 `t`에 대한 좌표를 **직선 보간**으로 추정합니다.

```
P(t) = P0 + (P1 - P0) × ratio
ratio = (t - t0) / (t1 - t0)
```

### 2.2 위도/경도 보간 공식

```
lat(t) = lat0 + (lat1 - lat0) × (t - t0) / (t1 - t0)
lng(t) = lng0 + (lng1 - lng0) × (t - t0) / (t1 - t0)
```

### 2.3 예시 계산

t=4 좌표 추정 (t0=3, t1=5 데이터 사용):

```
ratio = (4 - 3) / (5 - 3) = 0.5

lat(4) = 37.5565 + (37.5568 - 37.5565) × 0.5
       = 37.5565 + 0.00015
       = 37.55665

lng(4) = 126.9237 + (126.9241 - 126.9237) × 0.5
       = 126.9237 + 0.0002
       = 126.9239
```

---

## 3. Flutter 구현 코드

### 3.1 GPS 포인트 모델

```dart
// models/gps_point.dart
class GpsPoint {
  final int t;       // 타임코드 (초)
  final double lat;  // 위도
  final double lng;  // 경도
  final double? alt; // 고도 (선택)

  const GpsPoint({
    required this.t,
    required this.lat,
    required this.lng,
    this.alt,
  });

  factory GpsPoint.fromJson(Map<String, dynamic> json) {
    return GpsPoint(
      t: json['t'] as int,
      lat: (json['lat'] as num).toDouble(),
      lng: (json['lng'] as num).toDouble(),
      alt: json['alt'] != null ? (json['alt'] as num).toDouble() : null,
    );
  }

  Map<String, dynamic> toJson() => {
    't': t,
    'lat': lat,
    'lng': lng,
    if (alt != null) 'alt': alt,
  };
}
```

### 3.2 GPS 인덱서 (핵심 클래스)

```dart
// services/gps_indexer.dart
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../models/gps_point.dart';

class GpsIndexer {
  final List<GpsPoint> _track;

  GpsIndexer(List<GpsPoint> track)
      : _track = List.unmodifiable(track..sort((a, b) => a.t.compareTo(b.t)));

  /// 타임코드(초)로 GPS 좌표 조회 (보간 적용)
  LatLng? getPosition(double currentTime) {
    if (_track.isEmpty) return null;

    final t = currentTime.toInt();

    // 정확히 일치하는 포인트 탐색
    final exactIndex = _binarySearch(t);
    if (exactIndex >= 0) {
      return LatLng(_track[exactIndex].lat, _track[exactIndex].lng);
    }

    // 보간 처리
    final insertionPoint = -(exactIndex + 1);

    // 범위 초과 처리
    if (insertionPoint == 0) {
      return LatLng(_track.first.lat, _track.first.lng);
    }
    if (insertionPoint >= _track.length) {
      return LatLng(_track.last.lat, _track.last.lng);
    }

    // 선형 보간
    final p0 = _track[insertionPoint - 1];
    final p1 = _track[insertionPoint];
    return _interpolate(p0, p1, currentTime);
  }

  /// 선형 보간 계산
  LatLng _interpolate(GpsPoint p0, GpsPoint p1, double t) {
    final ratio = (t - p0.t) / (p1.t - p0.t);
    final lat = p0.lat + (p1.lat - p0.lat) * ratio;
    final lng = p0.lng + (p1.lng - p0.lng) * ratio;
    return LatLng(lat, lng);
  }

  /// 이진 탐색으로 타임코드 인덱스 반환
  int _binarySearch(int t) {
    int low = 0, high = _track.length - 1;
    while (low <= high) {
      final mid = (low + high) >> 1;
      final cmp = _track[mid].t.compareTo(t);
      if (cmp < 0) low = mid + 1;
      else if (cmp > 0) high = mid - 1;
      else return mid;
    }
    return -(low + 1);
  }

  /// 전체 이동 거리 계산 (미터)
  double get totalDistance {
    if (_track.length < 2) return 0;
    double total = 0;
    for (int i = 1; i < _track.length; i++) {
      total += _haversine(_track[i - 1], _track[i]);
    }
    return total;
  }

  /// Haversine 공식으로 두 좌표 간 거리 계산 (미터)
  double _haversine(GpsPoint p0, GpsPoint p1) {
    const r = 6371000.0; // 지구 반경 (미터)
    final dLat = _toRad(p1.lat - p0.lat);
    final dLng = _toRad(p1.lng - p0.lng);
    final a = _sin2(dLat / 2) +
        Math.cos(_toRad(p0.lat)) * Math.cos(_toRad(p1.lat)) * _sin2(dLng / 2);
    final c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
    return r * c;
  }

  double _toRad(double deg) => deg * (Math.pi / 180);
  double _sin2(double x) => Math.sin(x) * Math.sin(x);
}
```

> `Math` 는 `dart:math` 패키지의 `import 'dart:math' as Math;` 로 사용합니다.

### 3.3 플레이어에서 사용 예시

```dart
// screens/vlog/vlog_player_screen.dart (일부)

late GpsIndexer _gpsIndexer;
GoogleMapController? _mapController;

@override
void initState() {
  super.initState();
  _gpsIndexer = GpsIndexer(widget.vlog.gpsTrack);

  // 영상 재생 위치 변화 감지
  _videoController.addListener(_onVideoPositionChanged);
}

void _onVideoPositionChanged() {
  final position = _videoController.value.position;
  final seconds = position.inMilliseconds / 1000.0;

  final latLng = _gpsIndexer.getPosition(seconds);
  if (latLng != null) {
    setState(() => _currentPosition = latLng);
    _mapController?.animateCamera(
      CameraUpdate.newLatLng(latLng),
    );
  }
}
```

---

## 4. GPS 데이터 품질 처리

### 4.1 이상치(Outlier) 제거

GPS 신호 순간 오류로 비정상적인 좌표가 수집될 수 있습니다.
이전 포인트 대비 **속도가 비현실적(시속 300km 초과)** 이면 해당 포인트를 제거합니다.

```dart
List<GpsPoint> filterOutliers(List<GpsPoint> track) {
  const maxSpeedMs = 83.3; // 시속 300km → 초속 83.3m
  final filtered = <GpsPoint>[track.first];

  for (int i = 1; i < track.length; i++) {
    final prev = filtered.last;
    final curr = track[i];
    final dt = (curr.t - prev.t).toDouble();
    if (dt <= 0) continue;

    final dist = _haversine(prev, curr);
    final speed = dist / dt;

    if (speed <= maxSpeedMs) {
      filtered.add(curr);
    }
    // 이상치는 무시 (다음 포인트에서 보간으로 처리됨)
  }
  return filtered;
}
```

### 4.2 GPS 신호 없는 구간 처리

연속으로 10초 이상 GPS 데이터가 없으면 해당 구간을 **정지 상태**로 처리합니다.
(마지막 수신 좌표를 유지하고 마커를 움직이지 않음)

```dart
bool isStationary(double t) {
  final idx = _binarySearch(t.toInt());
  final insertionPoint = idx < 0 ? -(idx + 1) : idx;

  if (insertionPoint >= _track.length) return true;

  final p0 = insertionPoint > 0 ? _track[insertionPoint - 1] : _track[0];
  final p1 = _track[min(insertionPoint, _track.length - 1)];
  final gap = (p1.t - p0.t).abs();

  return gap > 10; // 10초 이상 공백 → 정지 처리
}
```

---

## 5. 성능 최적화

### 5.1 이진 탐색 적용

GPS 트랙이 수천 개 포인트일 때 선형 탐색(O(n)) 대신 **이진 탐색(O(log n))** 을 사용합니다.
(위 `_binarySearch` 메서드 참조)

### 5.2 청크 로딩

Firestore에서 GPS 트랙을 500개 단위 청크로 분할 저장하며, 재생 시작 전 전체 로드합니다.
(05_db_schema.md 참조)

### 5.3 마커 업데이트 최적화

영상 프레임마다 마커를 업데이트하면 성능 저하가 발생합니다.
**0.5초 간격**으로 갱신을 제한합니다.

```dart
DateTime _lastMarkerUpdate = DateTime.now();

void _onVideoPositionChanged() {
  final now = DateTime.now();
  if (now.difference(_lastMarkerUpdate).inMilliseconds < 500) return;
  _lastMarkerUpdate = now;

  // 마커 업데이트 수행
  // ...
}
```

---

## 6. 알고리즘 정확도 평가

| 조건 | 예상 오차 | 비고 |
|------|---------|------|
| GPS 1초 수집, 도보 | ±2~5m | 일반적 이동 |
| GPS 1초 수집, 차량 | ±10~20m | 빠른 이동 구간 |
| GPS 공백 5초 이내 | ±5~15m | 보간 적용 |
| GPS 공백 10초 초과 | 정지 처리 | 신호 불량 구간 |

---

*최종 수정: 2026-04-15*
