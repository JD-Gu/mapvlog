import 'package:flutter/material.dart';

class AppColors {
  static const Color primary = Color(0xFF1A73E8);
  static const Color secondary = Color(0xFF34A853);
  static const Color error = Color(0xFFEA4335);
  static const Color warning = Color(0xFFFBBC04);
  static const Color background = Color(0xFFF8F9FA);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceVariant = Color(0xFFF1F3F4);
  static const Color textPrimary = Color(0xFF202124);
  static const Color textSecondary = Color(0xFF5F6368);
  static const Color textDisabled = Color(0xFFBDC1C6);
}

class AppSpacing {
  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 16.0;
  static const double lg = 24.0;
  static const double xl = 32.0;
  static const double xxl = 48.0;
}

class AppRadius {
  static const double sm = 8.0;
  static const double md = 12.0;
  static const double lg = 16.0;
  static const double full = 999.0;
}

class AppShadow {
  static const List<BoxShadow> card = [
    BoxShadow(
      color: Color(0x1A000000),
      blurRadius: 8,
      offset: Offset(0, 2),
    ),
  ];

  static const List<BoxShadow> elevated = [
    BoxShadow(
      color: Color(0x26000000),
      blurRadius: 16,
      offset: Offset(0, 4),
    ),
  ];
}

// 지도 관련 상수
const double kVlogMarkerSize = 48.0;
const double kPhotoMarkerSize = 36.0;
const Color kPolylineColor = Color(0xFF1A73E8);
const int kPolylineWidth = 4;

// 앱 버전 — pubspec.yaml 의 version 필드와 동기화 유지 (수동)
const String kAppVersion = '1.48.0';
const String kAppBuildNumber = '69';
const String kAppChannel = 'beta'; // 'beta' | 'stable'

/// APK 다운로드 URL — 빌드번호 쿼리로 브라우저/다운로드매니저 캐시 우회
/// remoteBuild 가 있으면 그 값을, 없으면 내장 빌드번호를 붙임
String apkDownloadUrl([String? remoteBuild]) =>
    'https://pinflick.web.app/downloads/pinflick.apk?v=${remoteBuild ?? kAppBuildNumber}';
