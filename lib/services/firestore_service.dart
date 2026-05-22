import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

import '../models/gps_point.dart';
import '../models/vlog.dart';

/// Firestore CRUD 서비스 — vlogs 컬렉션
class FirestoreService {
  static final _db = FirebaseFirestore.instance;
  static final _vlogs = _db.collection('vlogs');

  // ─── 읽기 ─────────────────────────────────────────────────────────────────

  /// 최신순 브이로그 스트림 (홈 피드용)
  static Stream<List<Vlog>> watchVlogs({int limit = 20}) {
    return _vlogs
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs.map(_docToVlog).toList());
  }

  /// 특정 사용자의 브이로그 스트림 (프로필용)
  /// orderBy 없이 where만 사용 → Firestore 복합 인덱스 불필요
  /// 클라이언트에서 createdAt 기준 내림차순 정렬
  static Stream<List<Vlog>> watchUserVlogs(String uid) {
    return _vlogs
        .where('authorId', isEqualTo: uid)
        .snapshots()
        .map((snap) {
          final list = snap.docs.map(_docToVlog).toList();
          list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return list;
        });
  }

  /// 단건 조회
  static Future<Vlog?> getVlog(String id) async {
    final doc = await _vlogs.doc(id).get();
    if (!doc.exists) return null;
    return _docToVlog(doc);
  }

  // ─── 쓰기 ─────────────────────────────────────────────────────────────────

  /// 브이로그 저장 (신규)
  static Future<String> createVlog({
    required String authorId,
    required String authorName,
    required String title,
    required String placeName,
    required double lat,
    required double lng,
    String? videoUrl,
    String? thumbnailUrl,
    List<GpsPoint> gpsTrack = const [],
    int? durationSeconds,
    int? markerColor,
  }) async {
    final ref = _vlogs.doc();
    await ref.set({
      'id': ref.id,
      'authorId': authorId,
      'authorName': authorName,
      'title': title,
      'placeName': placeName,
      'lat': lat,
      'lng': lng,
      'videoUrl': videoUrl ?? '',
      'thumbnailUrl': thumbnailUrl ?? '',
      'likeCount': 0,
      'viewCount': 0,
      'gpsTrack': gpsTrack.map((p) => p.toJson()).toList(),
      'durationSeconds': durationSeconds,
      'markerColor': markerColor,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  /// 조회수 증가
  static Future<void> incrementView(String id) async {
    await _vlogs.doc(id).update({
      'viewCount': FieldValue.increment(1),
    });
  }

  /// 현재 사용자의 좋아요 여부 조회
  static Future<bool> isLiked(String vlogId, String userId) async {
    final doc = await _vlogs
        .doc(vlogId)
        .collection('likes')
        .doc(userId)
        .get();
    return doc.exists;
  }

  /// 좋아요 토글
  static Future<void> toggleLike(String vlogId, String userId) async {
    final likeRef =
        _vlogs.doc(vlogId).collection('likes').doc(userId);
    final doc = await likeRef.get();
    if (doc.exists) {
      await likeRef.delete();
      await _vlogs
          .doc(vlogId)
          .update({'likeCount': FieldValue.increment(-1)});
    } else {
      await likeRef.set({'uid': userId, 'createdAt': FieldValue.serverTimestamp()});
      await _vlogs
          .doc(vlogId)
          .update({'likeCount': FieldValue.increment(1)});
    }
  }

  /// 제목·장소 수정 (등록자만 호출할 것)
  static Future<void> updateVlog({
    required String id,
    required String title,
    required String placeName,
  }) async {
    await _vlogs.doc(id).update({
      'title': title,
      'placeName': placeName,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// 삭제 (등록자만 호출할 것)
  /// Firestore 문서 삭제 전에 Storage 파일(영상·썸네일)도 함께 삭제합니다.
  static Future<void> deleteVlog(String id) async {
    // 1. 문서 조회 → videoUrl / thumbnailUrl 확보
    final doc = await _vlogs.doc(id).get();
    if (doc.exists) {
      final d = doc.data() as Map<String, dynamic>;
      final videoUrl     = d['videoUrl']     as String? ?? '';
      final thumbnailUrl = d['thumbnailUrl'] as String? ?? '';

      // 2. Storage 파일 삭제 (실패해도 Firestore 삭제는 계속 진행)
      for (final url in [videoUrl, thumbnailUrl]) {
        if (url.isNotEmpty) {
          try {
            await FirebaseStorage.instance.refFromURL(url).delete();
          } catch (e) {
            debugPrint('Storage 삭제 실패 (무시): $e');
          }
        }
      }
    }

    // 3. likes 서브컬렉션 삭제 (Firestore는 부모 삭제 시 서브컬렉션 자동 삭제 안 됨)
    final likesSnap = await _vlogs.doc(id).collection('likes').get();
    if (likesSnap.docs.isNotEmpty) {
      final batch = FirebaseFirestore.instance.batch();
      for (final likeDoc in likesSnap.docs) {
        batch.delete(likeDoc.reference);
      }
      await batch.commit();
    }

    // 4. Firestore 문서 삭제
    await _vlogs.doc(id).delete();
  }

  // ─── 초기 더미 데이터 시드 ──────────────────────────────────────────────────

  /// Firestore가 비어 있을 때 더미 데이터를 한 번만 씀
  static Future<void> seedDummyData() async {
    final snap = await _vlogs.limit(1).get();
    if (snap.docs.isNotEmpty) return; // 이미 데이터 있음

    final dummies = [
      {
        'authorId': 'demo',
        'authorName': '여행러',
        'title': '홍대 카페 투어',
        'placeName': '홍대입구역',
        'lat': 37.5563,
        'lng': 126.9236,
        'likeCount': 32,
        'viewCount': 152,
        'videoUrl': '',
        'thumbnailUrl': '',
        'gpsTrack': List.generate(20, (i) => {
          'lat': 37.5563 + i * 0.0002,
          'lng': 126.9236 + i * 0.0003,
          'accuracy': 5.0,
          'timestamp': DateTime(2026, 4, 10, 14, 0, i).toIso8601String(),
          'videoTimeMs': i * 1000,
        }),
      },
      {
        'authorId': 'demo',
        'authorName': '맵브이로거',
        'title': '서울숲 산책',
        'placeName': '서울숲',
        'lat': 37.5440,
        'lng': 127.0374,
        'likeCount': 18,
        'viewCount': 87,
        'videoUrl': '',
        'thumbnailUrl': '',
        'gpsTrack': List.generate(30, (i) => {
          'lat': 37.5440 + i * 0.0001,
          'lng': 127.0374 + (i % 2 == 0 ? i * 0.0002 : -i * 0.0001),
          'accuracy': 4.0,
          'timestamp': DateTime(2026, 4, 12, 10, 0, i).toIso8601String(),
          'videoTimeMs': i * 1000,
        }),
      },
      {
        'authorId': 'demo',
        'authorName': '여행러',
        'title': '남산타워 야경',
        'placeName': '남산서울타워',
        'lat': 37.5512,
        'lng': 126.9882,
        'likeCount': 54,
        'viewCount': 310,
        'videoUrl': '',
        'thumbnailUrl': '',
        'gpsTrack': List.generate(25, (i) => {
          'lat': 37.5512 + i * 0.00015,
          'lng': 126.9882 + i * 0.00010,
          'accuracy': 6.0,
          'timestamp': DateTime(2026, 4, 14, 20, 0, i).toIso8601String(),
          'videoTimeMs': i * 1000,
        }),
      },
    ];

    final batch = _db.batch();
    for (final data in dummies) {
      final ref = _vlogs.doc();
      batch.set(ref, {
        'id': ref.id,
        ...data,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }

  // ─── 변환 헬퍼 ────────────────────────────────────────────────────────────

  static Vlog _docToVlog(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    final rawTrack = d['gpsTrack'] as List<dynamic>? ?? [];
    return Vlog(
      id: doc.id,
      authorId: d['authorId'] as String? ?? '',
      title: d['title'] as String? ?? '',
      authorName: d['authorName'] as String? ?? '',
      placeName: d['placeName'] as String? ?? '',
      lat: (d['lat'] as num?)?.toDouble() ?? 0,
      lng: (d['lng'] as num?)?.toDouble() ?? 0,
      thumbnailUrl: d['thumbnailUrl'] as String?,
      videoUrl: d['videoUrl'] as String?,
      likeCount: (d['likeCount'] as num?)?.toInt() ?? 0,
      viewCount: (d['viewCount'] as num?)?.toInt() ?? 0,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      gpsTrack: rawTrack
          .map((e) => GpsPoint.fromJson(e as Map<String, dynamic>))
          .toList(),
      durationSeconds: (d['durationSeconds'] as num?)?.toInt(),
      markerColor: (d['markerColor'] as num?)?.toInt(),
    );
  }
}
