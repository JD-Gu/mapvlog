import 'gps_point.dart';

/// 게시글 공개 범위 (per-post visibility)
///
/// - public  🌐 친구로 등록된 모든 사용자에게 공개 (기본값)
/// - groups  👥 선택한 그룹의 멤버에게만 공개 (visibleUids 에 flat-list 캐시)
/// - private 🔒 작성자 본인만 (마이페이지 타임라인에서만)
enum VlogVisibility {
  public,
  groups,
  private;

  static VlogVisibility fromValue(String? v) {
    switch (v) {
      case 'groups':
        return VlogVisibility.groups;
      case 'private':
        return VlogVisibility.private;
      default:
        return VlogVisibility.public;
    }
  }

  String get value => name;

  String get label => switch (this) {
        VlogVisibility.public => '전체 공개',
        VlogVisibility.groups => '그룹 공개',
        VlogVisibility.private => '나만 보기',
      };

  String get emoji => switch (this) {
        VlogVisibility.public => '🌐',
        VlogVisibility.groups => '👥',
        VlogVisibility.private => '🔒',
      };

  String get description => switch (this) {
        VlogVisibility.public => '친구로 등록된 모든 사용자에게 공개',
        VlogVisibility.groups => '선택한 그룹 멤버만 볼 수 있음',
        VlogVisibility.private => '나만 마이페이지에서 볼 수 있음',
      };
}

class Vlog {
  final String id;
  final String authorId;        // 등록자 UID (수정·삭제 권한 확인용)
  final String title;
  final String? thumbnailUrl;
  final String? videoUrl;       // CloudFront CDN URL
  final String authorName;
  final String? authorPhotoUrl;
  final String placeName;
  final double lat;             // 대표 위치 (첫 번째 GPS 포인트)
  final double lng;
  final int likeCount;
  final int commentCount;
  final int viewCount;
  final DateTime createdAt;
  final List<GpsPoint> gpsTrack; // GPS 타임스탬프 트랙
  final int? durationSeconds;   // 영상 길이 (초), 사진은 null
  final int? markerColor;       // 지도 마커 색상 (markerEmoji에서 자동 파생)
  final String? markerEmoji;    // 카테고리 이모지 (📍🍕☕ 등) — null이면 기본 📍
  final String? address;        // 역지오코딩 주소 (예: 서울특별시 동작구 사당동 127)
  final List<String> photoUrls; // 멀티 사진 URL 목록 (단사진·영상은 빈 리스트)
  final bool isCheckIn; // 체크인 (미디어 없이 위치+이모지+메시지만)

  // ── 공개 범위 (per-post visibility) ───────────────────────────────────
  final VlogVisibility visibility;
  /// groups 모드에서 선택된 그룹 ID 목록 (편집 시 복원용)
  final List<String> visibleGroupIds;
  /// 실제 권한 체크용 flat UID 목록 — public 이면 빈 리스트, private 이면 빈 리스트
  /// groups 일 때만 의미 있음 (= 모든 선택 그룹 멤버 UID 의 합집합)
  final List<String> visibleUids;

  const Vlog({
    required this.id,
    required this.authorId,
    required this.title,
    this.thumbnailUrl,
    this.videoUrl,
    required this.authorName,
    this.authorPhotoUrl,
    required this.placeName,
    required this.lat,
    required this.lng,
    this.likeCount = 0,
    this.commentCount = 0,
    this.viewCount = 0,
    required this.createdAt,
    this.gpsTrack = const [],
    this.durationSeconds,
    this.markerColor,
    this.markerEmoji,
    this.address,
    this.photoUrls = const [],
    this.isCheckIn = false,
    this.visibility = VlogVisibility.public,
    this.visibleGroupIds = const [],
    this.visibleUids = const [],
  });

  bool get hasVideo => videoUrl != null && videoUrl!.isNotEmpty;
  bool get hasGpsTrack => gpsTrack.isNotEmpty;
  /// 영상 없이 사진만 있는 vlog
  bool get isPhoto =>
      !hasVideo &&
      (thumbnailUrl != null && thumbnailUrl!.isNotEmpty ||
          photoUrls.isNotEmpty);
  /// 표시할 사진 URL 목록 (멀티 or 단일 썸네일 fallback)
  List<String> get displayPhotoUrls =>
      photoUrls.isNotEmpty
          ? photoUrls
          : (thumbnailUrl?.isNotEmpty == true ? [thumbnailUrl!] : []);
}
