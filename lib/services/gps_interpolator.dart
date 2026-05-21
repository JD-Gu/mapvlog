import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../models/gps_point.dart';

/// GPS 보간기 — 영상 타임코드(ms)에 대응하는 지도 좌표를 계산
///
/// 1초 간격 GPS 포인트 사이를 선형 보간(Linear Interpolation)하여
/// 영상 재생 위치에 따라 부드럽게 마커가 이동하도록 함
class GpsInterpolator {
  /// 현재 영상 재생 위치(ms)에 해당하는 보간 좌표 반환
  /// GPS 트랙이 비어 있거나 매핑 불가 시 null
  static LatLng? interpolate(List<GpsPoint> track, int videoTimeMs) {
    if (track.isEmpty) return null;

    // 범위 밖 → 첫/마지막 포인트 반환
    if (videoTimeMs <= track.first.videoTimeMs) {
      return LatLng(track.first.lat, track.first.lng);
    }
    if (videoTimeMs >= track.last.videoTimeMs) {
      return LatLng(track.last.lat, track.last.lng);
    }

    // 이진 탐색으로 앞뒤 포인트 찾기
    int lo = 0, hi = track.length - 1;
    while (lo < hi - 1) {
      final mid = (lo + hi) ~/ 2;
      if (track[mid].videoTimeMs <= videoTimeMs) {
        lo = mid;
      } else {
        hi = mid;
      }
    }

    final p1 = track[lo];
    final p2 = track[hi];
    final span = p2.videoTimeMs - p1.videoTimeMs;
    if (span == 0) return LatLng(p1.lat, p1.lng);

    // 선형 보간 (0.0 ~ 1.0)
    final t = (videoTimeMs - p1.videoTimeMs) / span;
    return LatLng(
      p1.lat + t * (p2.lat - p1.lat),
      p1.lng + t * (p2.lng - p1.lng),
    );
  }

  /// 트랙 전체를 LatLng 목록으로 변환 (폴리라인 그리기용)
  static List<LatLng> toPolyline(List<GpsPoint> track) =>
      track.map((p) => LatLng(p.lat, p.lng)).toList();

  /// 트랙 중심 좌표 (지도 초기 카메라 위치용)
  static LatLng? centerOf(List<GpsPoint> track) {
    if (track.isEmpty) return null;
    final lat = track.map((p) => p.lat).reduce((a, b) => a + b) / track.length;
    final lng = track.map((p) => p.lng).reduce((a, b) => a + b) / track.length;
    return LatLng(lat, lng);
  }

  /// 트랙 전체를 감싸는 경계 박스 (fitBounds용)
  static ({double south, double west, double north, double east})?
      boundsOf(List<GpsPoint> track) {
    if (track.isEmpty) return null;
    final lats = track.map((p) => p.lat);
    final lngs = track.map((p) => p.lng);
    return (
      south: lats.reduce((a, b) => a < b ? a : b),
      north: lats.reduce((a, b) => a > b ? a : b),
      west: lngs.reduce((a, b) => a < b ? a : b),
      east: lngs.reduce((a, b) => a > b ? a : b),
    );
  }
}
