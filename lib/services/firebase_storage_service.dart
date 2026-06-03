import 'dart:io';
import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

/// Firebase Storage 업로드 서비스 (웹 + 모바일 공용)
class FirebaseStorageService {
  static final _storage = FirebaseStorage.instance;

  /// 바이트 배열을 Firebase Storage에 업로드하고 다운로드 URL 반환 (웹)
  static Future<String> uploadBytes({
    required Uint8List bytes,
    required String path,
    required String contentType,
    void Function(int sent, int total)? onProgress,
  }) async {
    final ref = _storage.ref(path);
    final metadata = SettableMetadata(contentType: contentType);
    final task = ref.putData(bytes, metadata);

    if (onProgress != null) {
      task.snapshotEvents.listen((snap) {
        onProgress(snap.bytesTransferred, snap.totalBytes);
      });
    }

    await task;
    return await ref.getDownloadURL();
  }

  /// 로컬 파일을 Firebase Storage에 업로드하고 다운로드 URL 반환 (모바일)
  ///
  /// 영상처럼 큰 파일도 스트리밍으로 처리해 메모리를 절약합니다.
  static Future<String> uploadFile({
    required String localPath,
    required String path,
    required String contentType,
    void Function(int sent, int total)? onProgress,
  }) async {
    final ref = _storage.ref(path);
    final metadata = SettableMetadata(contentType: contentType);
    final task = ref.putFile(File(localPath), metadata);

    if (onProgress != null) {
      task.snapshotEvents.listen((snap) {
        onProgress(snap.bytesTransferred, snap.totalBytes);
      });
    }

    await task;
    return await ref.getDownloadURL();
  }

  /// XFile을 플랫폼에 맞게 업로드 (웹=bytes, 모바일=file 스트리밍)
  ///
  /// XFile은 camera / image_picker 패키지 어디서 왔든 동일하게 사용 가능합니다.
  static Future<String> uploadXFile({
    required dynamic xfile, // XFile (cross_file)
    required String path,
    required String contentType,
    void Function(int sent, int total)? onProgress,
  }) async {
    if (kIsWeb) {
      final bytes = await (xfile.readAsBytes() as Future<Uint8List>);
      return uploadBytes(
          bytes: bytes,
          path: path,
          contentType: contentType,
          onProgress: onProgress);
    } else {
      return uploadFile(
          localPath: xfile.path as String,
          path: path,
          contentType: contentType,
          onProgress: onProgress);
    }
  }

  // ─── 경로 헬퍼 ──────────────────────────────────────────────────────────────

  static String photoPath(String userId, String filename) =>
      'photos/$userId/$filename';

  static String videoPath(String userId, String filename) =>
      'videos/$userId/$filename';

  static String thumbnailPath(String userId, String filename) =>
      'thumbnails/$userId/$filename';

  static String avatarPath(String userId) =>
      'avatars/$userId.jpg';
}
