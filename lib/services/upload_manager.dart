import 'package:flutter/foundation.dart';

import '../models/gps_point.dart';
import '../models/media_item.dart';
import '../models/recording_session.dart';
import 'firebase_storage_service.dart';
import 'media_storage_service.dart';

/// 업로드 진행 상태
class UploadProgress {
  final int bytesSent;
  final int bytesTotal;
  final bool isDone;
  final String? error;
  final String? remoteUrl;

  const UploadProgress({
    this.bytesSent = 0,
    this.bytesTotal = 0,
    this.isDone = false,
    this.error,
    this.remoteUrl,
  });

  double get ratio =>
      bytesTotal > 0 ? bytesSent / bytesTotal : 0.0;

  bool get hasError => error != null;
}

/// Firebase Storage 업로드 + 로컬 메타데이터 저장 통합 매니저
///
/// Firestore createVlog 등록은 상위 레이어(camera_screen)에서 직접 수행합니다.
class UploadManager {
  /// 사진 업로드 → Firebase Storage (모바일: putFile, 웹: putData)
  static Future<MediaItem> uploadPhoto({
    required String localPath,
    required GpsPoint? gps,
    required String userId,
    void Function(UploadProgress)? onProgress,
  }) async {
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final filename = '$id.jpg';
    final path = FirebaseStorageService.photoPath(userId, filename);

    // 로컬에 먼저 저장 (업로드 전 오프라인 캐시)
    final item = MediaItem(
      id: id,
      localPath: localPath,
      type: 'photo',
      lat: gps?.lat,
      lng: gps?.lng,
      accuracy: gps?.accuracy,
      createdAt: DateTime.now(),
    );
    await MediaStorageService.save(item);

    onProgress?.call(const UploadProgress(bytesSent: 0, bytesTotal: 1));

    if (kIsWeb) {
      // 웹은 camera_screen의 _webPickMedia → _uploadAndRegister에서 처리됨
      return item;
    }

    try {
      final remoteUrl = await FirebaseStorageService.uploadFile(
        localPath: localPath,
        path: path,
        contentType: 'image/jpeg',
        onProgress: (sent, total) =>
            onProgress?.call(UploadProgress(bytesSent: sent, bytesTotal: total)),
      );

      final uploaded = item.copyWith(remoteUrl: remoteUrl);
      await MediaStorageService.update(uploaded);
      onProgress?.call(UploadProgress(
          bytesSent: 1, bytesTotal: 1, isDone: true, remoteUrl: remoteUrl));
      return uploaded;
    } catch (e) {
      onProgress?.call(UploadProgress(error: e.toString()));
      return item;
    }
  }

  /// 영상 업로드 → Firebase Storage
  static Future<MediaItem> uploadVideo({
    required String localPath,
    required RecordingSession session,
    required String userId,
    void Function(UploadProgress)? onProgress,
  }) async {
    final id = session.id;
    final filename = '$id.mp4';
    final path = FirebaseStorageService.videoPath(userId, filename);

    final gps = session.firstPoint;
    final item = MediaItem(
      id: id,
      localPath: localPath,
      type: 'video',
      lat: gps?.lat,
      lng: gps?.lng,
      accuracy: gps?.accuracy,
      durationMs: session.durationMs,
      createdAt: session.startTime,
    );
    await MediaStorageService.save(item);

    onProgress?.call(const UploadProgress(bytesSent: 0, bytesTotal: 1));

    if (kIsWeb) {
      return item;
    }

    try {
      final remoteUrl = await FirebaseStorageService.uploadFile(
        localPath: localPath,
        path: path,
        contentType: 'video/mp4',
        onProgress: (sent, total) =>
            onProgress?.call(UploadProgress(bytesSent: sent, bytesTotal: total)),
      );

      final uploaded = item.copyWith(remoteUrl: remoteUrl);
      await MediaStorageService.update(uploaded);
      onProgress?.call(UploadProgress(
          bytesSent: 1, bytesTotal: 1, isDone: true, remoteUrl: remoteUrl));
      return uploaded;
    } catch (e) {
      onProgress?.call(UploadProgress(error: e.toString()));
      return item;
    }
  }
}
