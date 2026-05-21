import 'dart:convert';

/// 촬영된 사진 또는 영상 한 건
class MediaItem {
  final String id;
  final String? localPath;   // 기기 내 로컬 경로
  final String? remoteUrl;   // CloudFront CDN URL (업로드 완료 시)
  final String type;         // 'photo' | 'video'
  final double? lat;
  final double? lng;
  final double? accuracy;
  final int? durationMs;     // 영상 길이 (ms)
  final DateTime createdAt;
  final String? placeName;   // 역지오코딩 결과 (옵션)

  const MediaItem({
    required this.id,
    this.localPath,
    this.remoteUrl,
    required this.type,
    this.lat,
    this.lng,
    this.accuracy,
    this.durationMs,
    required this.createdAt,
    this.placeName,
  });

  bool get isVideo => type == 'video';
  bool get isPhoto => type == 'photo';
  bool get hasGps => lat != null && lng != null;
  bool get isUploaded => remoteUrl != null && remoteUrl!.isNotEmpty;

  MediaItem copyWith({
    String? remoteUrl,
    String? placeName,
    int? durationMs,
  }) =>
      MediaItem(
        id: id,
        localPath: localPath,
        remoteUrl: remoteUrl ?? this.remoteUrl,
        type: type,
        lat: lat,
        lng: lng,
        accuracy: accuracy,
        durationMs: durationMs ?? this.durationMs,
        createdAt: createdAt,
        placeName: placeName ?? this.placeName,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        if (localPath != null) 'localPath': localPath,
        if (remoteUrl != null) 'remoteUrl': remoteUrl,
        'type': type,
        if (lat != null) 'lat': lat,
        if (lng != null) 'lng': lng,
        if (accuracy != null) 'accuracy': accuracy,
        if (durationMs != null) 'durationMs': durationMs,
        'createdAt': createdAt.toIso8601String(),
        if (placeName != null) 'placeName': placeName,
      };

  String toJsonString() => jsonEncode(toJson());

  factory MediaItem.fromJson(Map<String, dynamic> j) => MediaItem(
        id: j['id'] as String,
        localPath: j['localPath'] as String?,
        remoteUrl: j['remoteUrl'] as String?,
        type: j['type'] as String,
        lat: (j['lat'] as num?)?.toDouble(),
        lng: (j['lng'] as num?)?.toDouble(),
        accuracy: (j['accuracy'] as num?)?.toDouble(),
        durationMs: j['durationMs'] as int?,
        createdAt: DateTime.parse(j['createdAt'] as String),
        placeName: j['placeName'] as String?,
      );
}
