import 'dart:convert';

import 'gps_point.dart';

enum MediaType { photo, video }

/// 촬영 세션 — GPS 트랙 + 미디어 경로를 한 세트로 관리
class RecordingSession {
  final String id;
  final DateTime startTime;
  final DateTime? endTime;
  final MediaType mediaType;
  final String? mediaPath;      // 로컬 파일 경로
  final List<GpsPoint> gpsTrack;

  RecordingSession({
    required this.id,
    required this.startTime,
    this.endTime,
    required this.mediaType,
    this.mediaPath,
    List<GpsPoint>? gpsTrack,
  }) : gpsTrack = gpsTrack ?? [];

  /// 첫 번째 GPS 좌표 (대표 위치)
  GpsPoint? get firstPoint => gpsTrack.isEmpty ? null : gpsTrack.first;

  /// 전체 녹화 시간 (ms)
  int get durationMs => endTime == null
      ? 0
      : endTime!.difference(startTime).inMilliseconds;

  RecordingSession copyWith({
    DateTime? endTime,
    String? mediaPath,
    List<GpsPoint>? gpsTrack,
  }) =>
      RecordingSession(
        id: id,
        startTime: startTime,
        endTime: endTime ?? this.endTime,
        mediaType: mediaType,
        mediaPath: mediaPath ?? this.mediaPath,
        gpsTrack: gpsTrack ?? this.gpsTrack,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'startTime': startTime.toIso8601String(),
        if (endTime != null) 'endTime': endTime!.toIso8601String(),
        'mediaType': mediaType.name,
        if (mediaPath != null) 'mediaPath': mediaPath,
        'gpsTrack': gpsTrack.map((p) => p.toJson()).toList(),
      };

  String toJsonString() => jsonEncode(toJson());

  factory RecordingSession.fromJson(Map<String, dynamic> j) =>
      RecordingSession(
        id: j['id'] as String,
        startTime: DateTime.parse(j['startTime'] as String),
        endTime: j['endTime'] != null
            ? DateTime.parse(j['endTime'] as String)
            : null,
        mediaType: MediaType.values.byName(j['mediaType'] as String),
        mediaPath: j['mediaPath'] as String?,
        gpsTrack: (j['gpsTrack'] as List<dynamic>)
            .map((e) => GpsPoint.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
