import 'gps_point.dart';

class Vlog {
  final String id;
  final String authorId;        // 등록자 UID (수정·삭제 권한 확인용)
  final String title;
  final String? thumbnailUrl;
  final String? videoUrl;       // CloudFront CDN URL
  final String authorName;
  final String placeName;
  final double lat;             // 대표 위치 (첫 번째 GPS 포인트)
  final double lng;
  final int likeCount;
  final int viewCount;
  final DateTime createdAt;
  final List<GpsPoint> gpsTrack; // GPS 타임스탬프 트랙
  final int? durationSeconds;   // 영상 길이 (초), 사진은 null
  final int? markerColor;       // 지도 마커 색상 (Color.value), null = 기본 파랑

  const Vlog({
    required this.id,
    required this.authorId,
    required this.title,
    this.thumbnailUrl,
    this.videoUrl,
    required this.authorName,
    required this.placeName,
    required this.lat,
    required this.lng,
    this.likeCount = 0,
    this.viewCount = 0,
    required this.createdAt,
    this.gpsTrack = const [],
    this.durationSeconds,
    this.markerColor,
  });

  bool get hasVideo => videoUrl != null && videoUrl!.isNotEmpty;
  bool get hasGpsTrack => gpsTrack.isNotEmpty;
  /// 영상 없이 사진만 있는 vlog (thumbnailUrl이 미디어 자체)
  bool get isPhoto =>
      !hasVideo && thumbnailUrl != null && thumbnailUrl!.isNotEmpty;
}
