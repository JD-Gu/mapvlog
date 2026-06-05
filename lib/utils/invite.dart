import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

/// 친구 초대 — 앱 링크 + 안내 메시지를 네이티브 공유 시트로 전달.
///
/// 웹앱 링크(설치 없이 바로 사용)를 공유한다. Android 는 카톡 등 네이티브
/// 공유 시트, 웹은 Web Share API(미지원 시 share_plus 폴백).
class AppInvite {
  static const String webUrl = 'https://pinflick.web.app';

  static Future<void> share() async {
    HapticFeedback.selectionClick();
    final me = FirebaseAuth.instance.currentUser;
    final name =
        me?.displayName ?? me?.email?.split('@').first ?? '친구';
    final text = '📍 $name 님이 PinFlick에 초대했어요!\n\n'
        '친구의 실시간 위치를 지도에서 보고,\n'
        '일상을 핀(Pin)으로 남기는 위치 소셜 앱이에요.\n\n'
        '👉 설치 없이 바로 시작:\n$webUrl';
    await Share.share(text, subject: 'PinFlick 초대');
  }
}
