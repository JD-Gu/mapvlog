import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../services/push_service.dart';

class AuthProvider extends ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  User? _user;
  bool _loading = false;
  String? _error;

  User? get user => _user;
  bool get isLoggedIn => _user != null;
  bool get loading => _loading;
  String? get error => _error;

  AuthProvider() {
    try {
      _auth.authStateChanges().listen((user) {
        _user = user;
        notifyListeners();
      });
    } catch (e) {
      // Firebase 미초기화 상태 (flutterfire configure 전)
      debugPrint('AuthProvider: Firebase 미초기화 상태 $e');
    }
  }

  Future<void> signInWithGoogle() async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      UserCredential result;

      if (kIsWeb) {
        // 웹: Firebase Auth 팝업 방식 (clientId 메타 태그 불필요)
        final provider = GoogleAuthProvider();
        result = await _auth.signInWithPopup(provider);
      } else {
        // 모바일: google_sign_in 패키지 방식
        final googleUser = await GoogleSignIn().signIn();
        if (googleUser == null) {
          _loading = false;
          notifyListeners();
          return; // 사용자가 취소
        }
        final googleAuth = await googleUser.authentication;
        final credential = GoogleAuthProvider.credential(
          accessToken: googleAuth.accessToken,
          idToken: googleAuth.idToken,
        );
        result = await _auth.signInWithCredential(credential);
      }

      if (result.user != null) {
        await _saveUserToFirestore(result.user!);
      }
    } catch (e) {
      _error = e.toString();
      debugPrint('Google 로그인 실패: $e');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// 프로필 이름 변경
  /// Firebase Auth + Firestore users 컬렉션 + 내 브이로그의 authorName 일괄 반영
  Future<bool> updateDisplayName(String newName) async {
    if (_user == null || newName.trim().isEmpty) return false;
    _loading = true;
    notifyListeners();
    try {
      // 1. Firebase Auth 업데이트
      await _user!.updateDisplayName(newName.trim());
      await _user!.reload();
      _user = _auth.currentUser;

      // 2. Firestore users 컬렉션 업데이트
      await _firestore.collection('users').doc(_user!.uid).set(
        {
          'displayName': newName.trim(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      // 3. 내 브이로그 authorName 일괄 업데이트
      final snap = await _firestore
          .collection('vlogs')
          .where('authorId', isEqualTo: _user!.uid)
          .get();
      if (snap.docs.isNotEmpty) {
        final batch = _firestore.batch();
        for (final doc in snap.docs) {
          batch.update(doc.reference, {'authorName': newName.trim()});
        }
        await batch.commit();
      }

      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('이름 변경 실패: $e');
      return false;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// 프로필 사진 URL 변경
  /// Firebase Auth + Firestore users + 본인 vlogs.authorPhotoUrl 일괄 동기화
  Future<bool> updatePhotoURL(String? newUrl) async {
    if (_user == null) return false;
    _loading = true;
    notifyListeners();
    try {
      // 1. Firebase Auth
      await _user!.updatePhotoURL(newUrl);
      await _user!.reload();
      _user = _auth.currentUser;

      // 2. users 컬렉션
      await _firestore.collection('users').doc(_user!.uid).set(
        {
          'photoURL': newUrl ?? '',
          'photoUrl': newUrl ?? '',  // LiveMap 호환
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      // 3. 본인 vlogs의 authorPhotoUrl 일괄 갱신 (피드 카드 동기화)
      final snap = await _firestore
          .collection('vlogs')
          .where('authorId', isEqualTo: _user!.uid)
          .get();
      if (snap.docs.isNotEmpty) {
        final batch = _firestore.batch();
        for (final doc in snap.docs) {
          if (newUrl == null || newUrl.isEmpty) {
            batch.update(doc.reference,
                {'authorPhotoUrl': FieldValue.delete()});
          } else {
            batch.update(doc.reference, {'authorPhotoUrl': newUrl});
          }
        }
        await batch.commit();
      }

      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('프로필 사진 변경 실패: $e');
      return false;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> signOut() async {
    try {
      // 로그아웃 전 이 기기의 FCM 토큰 제거 (다른 사람 알림 수신 방지)
      final uid = _auth.currentUser?.uid;
      if (uid != null) {
        await PushService.instance.unregister(uid);
      }
      if (!kIsWeb) {
        await GoogleSignIn().signOut();
      }
      await _auth.signOut();
    } catch (e) {
      debugPrint('로그아웃 실패: $e');
    }
  }

  Future<void> _saveUserToFirestore(User user) async {
    try {
      final doc = _firestore.collection('users').doc(user.uid);
      final existing = await doc.get();
      if (!existing.exists) {
        await doc.set({
          'uid': user.uid,
          'email': user.email ?? '',
          'displayName': user.displayName ?? '',
          'photoURL': user.photoURL ?? '',
          'bio': '',
          'vlogCount': 0,
          'followerCount': 0,
          'followingCount': 0,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      debugPrint('Firestore 저장 실패: $e');
    }
  }
}
