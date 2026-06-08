import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

import '../models/comment.dart';
import '../models/event.dart';
import '../models/gps_point.dart';
import '../models/vlog.dart';

/// Firestore CRUD 서비스 — vlogs 컬렉션
class FirestoreService {
  static final _db = FirebaseFirestore.instance;
  static final _vlogs = _db.collection('vlogs');
  static final _events = _db.collection('events');

  // ─── 이벤트 (라이브 이벤트 맵) ─────────────────────────────────────────────

  /// 활성 이벤트 스트림. P1 은 전체 active 를 받아 클라이언트에서
  /// 카테고리/기간/무료 필터 (데이터 적음, 복합 인덱스 불필요).
  /// 종료된(endAt < now) 이벤트는 클라이언트에서도 숨김.
  static Stream<List<PinEvent>> watchEvents() {
    return _events.where('status', isEqualTo: 'active').snapshots().map((snap) {
      final now = DateTime.now();
      final list = snap.docs
          .map(PinEvent.fromDoc)
          .where((e) => e.endAt.isAfter(now))
          .toList();
      // 진행 중(곧 끝나는 순) → 예정(시작 가까운 순)
      list.sort((a, b) {
        final ao = a.isOngoing(now), bo = b.isOngoing(now);
        if (ao != bo) return ao ? -1 : 1;
        if (ao && bo) return a.endAt.compareTo(b.endAt);
        return a.startAt.compareTo(b.startAt);
      });
      return list;
    });
  }

  /// 관리 화면용 — 종료 포함 전체(최신순). [categories]==null 이면 전부(Super),
  /// 지정하면 해당 카테고리만(Event Master 담당 범위).
  static Stream<List<PinEvent>> watchManageableEvents(
      {Set<EventCategory>? categories}) {
    return _events.snapshots().map((snap) {
      var list = snap.docs.map(PinEvent.fromDoc).toList();
      if (categories != null) {
        list = list.where((e) => categories.contains(e.category)).toList();
      }
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return list;
    });
  }

  static Future<PinEvent?> getEvent(String id) async {
    final doc = await _events.doc(id).get();
    if (!doc.exists) return null;
    return PinEvent.fromDoc(doc);
  }

  /// 이벤트 생성 → 문서 ID 반환
  static Future<String> createEvent(PinEvent e) async {
    final ref = await _events.add({
      ...e.toMap(),
      'viewCount': 0,
      'likeCount': 0,
      'saveCount': 0,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  static Future<void> updateEvent(String id, PinEvent e) async {
    await _events.doc(id).update({
      ...e.toMap(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> deleteEvent(String id) async {
    await _events.doc(id).delete();
  }

  /// 조회수 +1 (세션당 1회 호출 권장)
  static Future<void> incrementEventView(String id) async {
    try {
      await _events.doc(id).update({'viewCount': FieldValue.increment(1)});
    } catch (_) {}
  }

  static Stream<bool> watchEventLiked(String eventId, String uid) => _events
      .doc(eventId)
      .collection('likes')
      .doc(uid)
      .snapshots()
      .map((d) => d.exists);

  static Future<void> setEventLiked(
      String eventId, String uid, bool liked) async {
    final ref = _events.doc(eventId).collection('likes').doc(uid);
    if (liked) {
      await ref.set({'createdAt': FieldValue.serverTimestamp()});
      await _events.doc(eventId).update({'likeCount': FieldValue.increment(1)});
    } else {
      await ref.delete();
      await _events.doc(eventId).update({'likeCount': FieldValue.increment(-1)});
    }
  }

  static Stream<bool> watchEventSaved(String eventId, String uid) => _events
      .doc(eventId)
      .collection('saves')
      .doc(uid)
      .snapshots()
      .map((d) => d.exists);

  static Future<void> setEventSaved(
      String eventId, String uid, bool saved) async {
    final ref = _events.doc(eventId).collection('saves').doc(uid);
    if (saved) {
      await ref.set({'uid': uid, 'createdAt': FieldValue.serverTimestamp()});
      await _events.doc(eventId).update({'saveCount': FieldValue.increment(1)});
    } else {
      await ref.delete();
      await _events.doc(eventId).update({'saveCount': FieldValue.increment(-1)});
    }
  }

  // ─── 읽기 ─────────────────────────────────────────────────────────────────

  /// 최신순 브이로그 스트림 (검색 등) — visibility 필터 적용
  static Stream<List<Vlog>> watchVlogs({int limit = 20}) {
    final myUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    return _vlogs
        .orderBy('createdAt', descending: true)
        .limit(limit * 3)
        .snapshots()
        .map((snap) => snap.docs
            .map(_docToVlog)
            .where((v) => _isVisibleToMe(v, myUid))
            .take(limit)
            .toList());
  }

  /// 친구 + 본인의 브이로그만 스트림 (친구 한정 피드)
  ///
  /// Firestore whereIn은 최대 30개 → 친구 30명 초과 시 batch 처리.
  /// orderBy는 서버에서 하지 않고 클라이언트에서 처리 → 복합 인덱스 불필요.
  /// 클라이언트에서 visibility 기반 필터 적용 (private/groups 권한 enforce).
  static Stream<List<Vlog>> watchFriendsVlogs({
    required List<String> friendUids,
    required String myUid,
    int limit = 50,
  }) {
    // 본인 + 친구 UID 합집합
    final allUids = <String>{myUid, ...friendUids}.toList();
    if (allUids.isEmpty) return Stream.value([]);

    // 서버 limit은 넉넉히 (정렬 전에 잘리는 경우 대비)
    final fetchLimit = (limit * 3).clamp(50, 300);

    // 30명 이하 → 단일 whereIn 쿼리 + 클라이언트 정렬
    if (allUids.length <= 30) {
      return _vlogs
          .where('authorId', whereIn: allUids)
          .limit(fetchLimit)
          .snapshots()
          .map((snap) {
        final list = snap.docs.map(_docToVlog).toList();
        final visible =
            list.where((v) => _isVisibleToMe(v, myUid)).toList();
        visible.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        return visible.take(limit).toList();
      });
    }

    // 30명 초과 → 청크 단위로 분할 후 merge (정렬도 클라이언트)
    final chunks = <List<String>>[];
    for (int i = 0; i < allUids.length; i += 30) {
      chunks.add(allUids.sublist(i, (i + 30).clamp(0, allUids.length)));
    }
    final streams = chunks.map((c) => _vlogs
        .where('authorId', whereIn: c)
        .limit(fetchLimit)
        .snapshots()
        .map((s) => s.docs
            .map(_docToVlog)
            .where((v) => _isVisibleToMe(v, myUid))
            .toList()));

    // 다중 스트림 병합 + 정렬
    return _combineLatestVlogs(streams.toList(), limit);
  }

  /// 현재 사용자가 vlog 를 볼 수 있는지 visibility 기반으로 판정
  /// (Firestore 룰로 enforce 안 하는 대신 클라이언트에서 일관 처리)
  static bool _isVisibleToMe(Vlog v, String myUid) {
    if (v.authorId == myUid) return true; // 작성자는 항상
    switch (v.visibility) {
      case VlogVisibility.public:
        return true;
      case VlogVisibility.private:
        return false; // 작성자 본인만 (위에서 체크됨)
      case VlogVisibility.groups:
        return v.visibleUids.contains(myUid);
    }
  }

  /// 여러 vlog 스트림을 가장 최근 emission 기준으로 병합 + 정렬
  static Stream<List<Vlog>> _combineLatestVlogs(
      List<Stream<List<Vlog>>> streams, int limit) async* {
    if (streams.isEmpty) {
      yield <Vlog>[];
      return;
    }
    final latest = List<List<Vlog>?>.filled(streams.length, null);
    final controller = StreamController<List<Vlog>>();
    final subs = <StreamSubscription>[];
    for (int i = 0; i < streams.length; i++) {
      final idx = i;
      subs.add(streams[i].listen((data) {
        latest[idx] = data;
        if (latest.every((e) => e != null)) {
          final merged = <Vlog>[];
          for (final l in latest) {
            merged.addAll(l!);
          }
          // ID 중복 제거 (drop) + 최신순
          final seen = <String>{};
          final dedup = <Vlog>[];
          for (final v in merged) {
            if (seen.add(v.id)) dedup.add(v);
          }
          dedup.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          controller.add(dedup.take(limit).toList());
        }
      }, onError: controller.addError));
    }
    yield* controller.stream;
    for (final s in subs) {
      await s.cancel();
    }
  }

  /// 특정 사용자의 브이로그 스트림 (프로필용) — visibility 필터 적용
  /// orderBy 없이 where만 사용 → Firestore 복합 인덱스 불필요
  /// 클라이언트에서 createdAt 기준 내림차순 정렬
  static Stream<List<Vlog>> watchUserVlogs(String uid) {
    final myUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    return _vlogs
        .where('authorId', isEqualTo: uid)
        .snapshots()
        .map((snap) {
          final list = snap.docs
              .map(_docToVlog)
              .where((v) => _isVisibleToMe(v, myUid))
              .toList();
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
    String? authorPhotoUrl,
    required String title,
    required String placeName,
    required double lat,
    required double lng,
    String? videoUrl,
    String? thumbnailUrl,
    List<GpsPoint> gpsTrack = const [],
    int? durationSeconds,
    int? markerColor,
    String? markerEmoji,
    String? address,
    List<String> photoUrls = const [],
    bool isCheckIn = false,
    DateTime? expiresAt,
    VlogVisibility visibility = VlogVisibility.public,
    List<String> visibleGroupIds = const [],
    List<String> visibleUids = const [],
  }) async {
    final ref = _vlogs.doc();
    await ref.set({
      'id': ref.id,
      'authorId': authorId,
      'authorName': authorName,
      if (authorPhotoUrl != null && authorPhotoUrl.isNotEmpty)
        'authorPhotoUrl': authorPhotoUrl,
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
      if (markerEmoji != null && markerEmoji.isNotEmpty) 'markerEmoji': markerEmoji,
      if (address != null && address.isNotEmpty) 'address': address,
      if (photoUrls.isNotEmpty) 'photoUrls': photoUrls,
      if (isCheckIn) 'isCheckIn': true,
      if (expiresAt != null) 'expiresAt': Timestamp.fromDate(expiresAt),
      // 공개 범위 (per-post)
      'visibility': visibility.value,
      if (visibleGroupIds.isNotEmpty) 'visibleGroupIds': visibleGroupIds,
      if (visibleUids.isNotEmpty) 'visibleUids': visibleUids,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  /// 공개 범위만 변경 (편집)
  static Future<void> updateVisibility({
    required String vlogId,
    required VlogVisibility visibility,
    List<String> visibleGroupIds = const [],
    List<String> visibleUids = const [],
  }) async {
    final data = <String, dynamic>{
      'visibility': visibility.value,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (visibility == VlogVisibility.groups) {
      data['visibleGroupIds'] = visibleGroupIds;
      data['visibleUids'] = visibleUids;
    } else {
      data['visibleGroupIds'] = FieldValue.delete();
      data['visibleUids'] = FieldValue.delete();
    }
    await _vlogs.doc(vlogId).update(data);
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

  // ─── 즐겨찾기 (Bookmark) ──────────────────────────────────────────────────
  /// 토글: vlogs/{vlogId}/saves/{userId} doc 생성/삭제
  /// 좋아요와 별개 — 본인만 보는 개인 컬렉션
  static Future<void> toggleSave(String vlogId, String userId) async {
    final col = _vlogs.doc(vlogId).collection('saves');
    // 존재 확인은 단일 doc get 대신 uid 필드 쿼리로 (규칙이 필드 기반 인가라
    // 없는 doc 을 get 하면 permission-denied 가 남)
    final existing =
        await col.where('uid', isEqualTo: userId).limit(1).get();
    if (existing.docs.isNotEmpty) {
      await col.doc(userId).delete();
    } else {
      await col.doc(userId).set({
        'uid': userId,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
  }

  static Future<bool> isSaved(String vlogId, String userId) async {
    final snap = await _vlogs
        .doc(vlogId)
        .collection('saves')
        .where('uid', isEqualTo: userId)
        .limit(1)
        .get();
    return snap.docs.isNotEmpty;
  }

  // ─── Like Users (vlog 좋아요한 사용자) ────────────────────────────────────
  /// vlogs/{vlogId}/likes 의 docId(=uid) 목록 → users 컬렉션에서 displayName/photo 조회
  static Stream<List<Map<String, dynamic>>> watchVlogLikers(
      String vlogId) async* {
    final likesStream = _vlogs
        .doc(vlogId)
        .collection('likes')
        .orderBy('createdAt', descending: true)
        .limit(100)
        .snapshots();
    await for (final snap in likesStream) {
      if (snap.docs.isEmpty) {
        yield [];
        continue;
      }
      final uids = snap.docs.map((d) => d.id).toList();
      final userDocs = await Future.wait(uids.map(
          (uid) => FirebaseFirestore.instance.doc('users/$uid').get()));
      yield List.generate(uids.length, (i) {
        final ud = userDocs[i];
        final data = ud.data() ?? {};
        final likeData = snap.docs[i].data();
        return {
          'uid': uids[i],
          'displayName':
              (data['displayName'] as String?) ?? '익명',
          'photoUrl': data['photoUrl'] as String?,
          'createdAt':
              (likeData['createdAt'] as Timestamp?)?.toDate(),
        };
      });
    }
  }

  /// 댓글 좋아요 — 동일 패턴
  static Stream<List<Map<String, dynamic>>> watchCommentLikers(
      String vlogId, String commentId,
      {String collection = 'vlogs'}) async* {
    final likesStream = _db
        .collection(collection)
        .doc(vlogId)
        .collection('comments')
        .doc(commentId)
        .collection('likes')
        .orderBy('createdAt', descending: true)
        .limit(100)
        .snapshots();
    await for (final snap in likesStream) {
      if (snap.docs.isEmpty) {
        yield [];
        continue;
      }
      final uids = snap.docs.map((d) => d.id).toList();
      final userDocs = await Future.wait(uids.map(
          (uid) => FirebaseFirestore.instance.doc('users/$uid').get()));
      yield List.generate(uids.length, (i) {
        final ud = userDocs[i];
        final data = ud.data() ?? {};
        final likeData = snap.docs[i].data();
        return {
          'uid': uids[i],
          'displayName':
              (data['displayName'] as String?) ?? '익명',
          'photoUrl': data['photoUrl'] as String?,
          'createdAt':
              (likeData['createdAt'] as Timestamp?)?.toDate(),
        };
      });
    }
  }

  /// 내가 저장한 vlog 목록 (collection group query)
  /// Firestore 인덱스: collectionGroup('saves') where uid==me orderBy createdAt desc
  static Stream<List<Vlog>> watchSavedVlogs(String userId) async* {
    // collection group으로 내가 저장한 saves doc 찾기
    final query = FirebaseFirestore.instance
        .collectionGroup('saves')
        .where('uid', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .limit(100);
    await for (final snap in query.snapshots()) {
      // saves doc의 parent.parent = vlog 문서 ref
      final vlogRefs = snap.docs
          .map((d) => d.reference.parent.parent)
          .whereType<DocumentReference<Object?>>()
          .toList();
      if (vlogRefs.isEmpty) {
        yield [];
        continue;
      }
      final vlogDocs = await Future.wait(vlogRefs.map((r) => r.get()));
      final vlogs = <Vlog>[];
      for (final d in vlogDocs) {
        if (!d.exists) continue;
        try {
          vlogs.add(_docToVlog(d));
        } catch (e) {
          // 손상된 vlog 1건이 전체 목록을 막지 않도록 스킵
          debugPrint('저장한 vlog 파싱 실패 (스킵) ${d.id}: $e');
        }
      }
      yield vlogs;
    }
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

  // ─── 댓글 ─────────────────────────────────────────────────────────────────

  /// 댓글 스트림 (오래된→최신, 인스타 스타일)
  static Stream<List<Comment>> watchComments(String vlogId,
      {String collection = 'vlogs'}) {
    return _db
        .collection(collection)
        .doc(vlogId)
        .collection('comments')
        .orderBy('createdAt', descending: false)
        .snapshots()
        .map((snap) => snap.docs.map(Comment.fromDoc).toList());
  }

  /// 댓글 추가 (vlog.commentCount +1)
  ///
  /// [parentId] 가 non-null이면 해당 댓글의 답글로 저장됨.
  /// commentCount는 답글 포함 전체 카운트.
  static Future<void> addComment({
    required String vlogId,
    required String authorId,
    required String authorName,
    String? authorPhotoUrl,
    required String content,
    String? parentId,
    String collection = 'vlogs',
  }) async {
    final ref =
        _db.collection(collection).doc(vlogId).collection('comments').doc();
    await ref.set({
      'id': ref.id,
      'authorId': authorId,
      'authorName': authorName,
      if (authorPhotoUrl != null && authorPhotoUrl.isNotEmpty)
        'authorPhotoUrl': authorPhotoUrl,
      'content': content,
      'createdAt': FieldValue.serverTimestamp(),
      'likeCount': 0,
      if (parentId != null && parentId.isNotEmpty) 'parentId': parentId,
    });
    await _db.collection(collection).doc(vlogId).update({
      'commentCount': FieldValue.increment(1),
    });
  }

  /// 댓글 삭제 (작성자/마스터/등록자)
  static Future<void> deleteComment(String vlogId, String commentId,
      {String collection = 'vlogs'}) async {
    await _db
        .collection(collection)
        .doc(vlogId)
        .collection('comments')
        .doc(commentId)
        .delete();
    await _db.collection(collection).doc(vlogId).update({
      'commentCount': FieldValue.increment(-1),
    });
  }

  /// 가장 최신 댓글 1개 (없으면 null) — 카드 미리보기용
  static Future<Comment?> getLatestComment(String vlogId,
      {String collection = 'vlogs'}) async {
    final snap = await _db
        .collection(collection)
        .doc(vlogId)
        .collection('comments')
        .orderBy('createdAt', descending: true)
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    return Comment.fromDoc(snap.docs.first);
  }

  // ─── 댓글 좋아요 (인스타 스타일) ────────────────────────────────────────────
  /// 토글: 좋아요 doc 있으면 삭제 + count -1, 없으면 생성 + count +1
  static Future<void> toggleCommentLike({
    required String vlogId,
    required String commentId,
    required String userId,
    String collection = 'vlogs',
  }) async {
    final commentRef = _db
        .collection(collection)
        .doc(vlogId)
        .collection('comments')
        .doc(commentId);
    final likeRef = commentRef.collection('likes').doc(userId);
    final snap = await likeRef.get();
    if (snap.exists) {
      await likeRef.delete();
      await commentRef.update({'likeCount': FieldValue.increment(-1)});
    } else {
      await likeRef.set({
        'userId': userId,
        'createdAt': FieldValue.serverTimestamp(),
      });
      await commentRef.update({'likeCount': FieldValue.increment(1)});
    }
  }

  /// 현재 사용자가 이 댓글에 좋아요를 눌렀는지 확인 (단건 조회)
  static Future<bool> isCommentLikedByMe({
    required String vlogId,
    required String commentId,
    required String userId,
    String collection = 'vlogs',
  }) async {
    final doc = await _db
        .collection(collection)
        .doc(vlogId)
        .collection('comments')
        .doc(commentId)
        .collection('likes')
        .doc(userId)
        .get();
    return doc.exists;
  }

  /// 제목·장소·마커색상·사진 수정 (등록자만 호출할 것)
  ///
  /// [photoUrls] / [thumbnailUrl]를 함께 넘기면 사진 목록도 갱신됨.
  /// 사진 갱신 시 Storage 파일은 별도로 정리해야 함 (호출자 책임).
  static Future<void> updateVlog({
    required String id,
    required String title,
    required String placeName,
    int? markerColor,
    String? markerEmoji,
    List<String>? photoUrls,
    String? thumbnailUrl,
    double? lat,
    double? lng,
    String? address,
    DateTime? expiresAt,
    VlogVisibility? visibility,
    List<String>? visibleGroupIds,
    List<String>? visibleUids,
  }) async {
    final data = <String, dynamic>{
      'title': title,
      'placeName': placeName,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (markerColor != null) data['markerColor'] = markerColor;
    if (markerEmoji != null) data['markerEmoji'] = markerEmoji;
    if (photoUrls != null) data['photoUrls'] = photoUrls;
    if (thumbnailUrl != null) data['thumbnailUrl'] = thumbnailUrl;
    if (lat != null) data['lat'] = lat;
    if (lng != null) data['lng'] = lng;
    if (address != null) data['address'] = address;
    if (expiresAt != null) data['expiresAt'] = Timestamp.fromDate(expiresAt);
    // 공개 범위 (지정 시에만 갱신)
    if (visibility != null) {
      data['visibility'] = visibility.value;
      if (visibility == VlogVisibility.groups) {
        data['visibleGroupIds'] = visibleGroupIds ?? const [];
        data['visibleUids'] = visibleUids ?? const [];
      } else {
        data['visibleGroupIds'] = FieldValue.delete();
        data['visibleUids'] = FieldValue.delete();
      }
    }
    await _vlogs.doc(id).update(data);
  }

  /// 편집 시 제거된 사진을 Storage에서 삭제
  static Future<void> deletePhotoFromStorage(String url) async {
    if (url.isEmpty) return;
    try {
      await FirebaseStorage.instance.refFromURL(url).delete();
    } catch (e) {
      debugPrint('사진 Storage 삭제 실패 (무시): $e');
    }
  }

  /// 썸네일(사진) URL 단독 업데이트 — 회전 저장 등에 사용
  static Future<void> updateThumbnail({
    required String id,
    required String thumbnailUrl,
  }) async {
    await _vlogs.doc(id).update({
      'thumbnailUrl': thumbnailUrl,
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
      final photoUrlList = (d['photoUrls'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [];

      // 2. Storage 파일 삭제 (실패해도 Firestore 삭제는 계속 진행)
      final allUrls = {videoUrl, thumbnailUrl, ...photoUrlList}
          .where((u) => u.isNotEmpty)
          .toList();
      for (final url in allUrls) {
        try {
          await FirebaseStorage.instance.refFromURL(url).delete();
        } catch (e) {
          debugPrint('Storage 삭제 실패 (무시): $e');
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
      authorPhotoUrl: d['authorPhotoUrl'] as String?,
      placeName: d['placeName'] as String? ?? '',
      lat: (d['lat'] as num?)?.toDouble() ?? 0,
      lng: (d['lng'] as num?)?.toDouble() ?? 0,
      thumbnailUrl: d['thumbnailUrl'] as String?,
      videoUrl: d['videoUrl'] as String?,
      likeCount: (d['likeCount'] as num?)?.toInt() ?? 0,
      commentCount: (d['commentCount'] as num?)?.toInt() ?? 0,
      viewCount: (d['viewCount'] as num?)?.toInt() ?? 0,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      gpsTrack: rawTrack
          .map((e) => GpsPoint.fromJson(e as Map<String, dynamic>))
          .toList(),
      durationSeconds: (d['durationSeconds'] as num?)?.toInt(),
      markerColor: (d['markerColor'] as num?)?.toInt(),
      markerEmoji: d['markerEmoji'] as String?,
      address: d['address'] as String?,
      photoUrls: (d['photoUrls'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      isCheckIn: d['isCheckIn'] as bool? ?? false,
      expiresAt: (d['expiresAt'] as Timestamp?)?.toDate(),
      visibility: VlogVisibility.fromValue(d['visibility'] as String?),
      visibleGroupIds: (d['visibleGroupIds'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      visibleUids: (d['visibleUids'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
    );
  }
}
