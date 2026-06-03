import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

// dart:js_interop 은 웹 전용이므로 조건부 임포트로 분리
import 'utils/web_hash_stub.dart'
    if (dart.library.js_interop) 'utils/web_hash_web.dart';

import 'app.dart';
import 'firebase_options.dart';

/// 웹 딥링크 초기 fragment 값.
/// 예: '/vlog/jfrBmRxQqUcbSzomB9YJ'
/// 비-웹 플랫폼에서는 null.
String? initialWebFragment;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // index.html 의 JS 변수에서 읽어옴 (Flutter 엔진 초기화 영향 없음)
  if (kIsWeb) {
    initialWebFragment = getInitialWebFragment();
    debugPrint('[PinFlick] initialWebFragment="$initialWebFragment"');
  }

  await dotenv.load(fileName: '.env');

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  runApp(const MapVlogApp());
}
