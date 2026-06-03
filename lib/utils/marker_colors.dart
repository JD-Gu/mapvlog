import 'package:flutter/material.dart';

/// 지도 마커 선택 가능 색상 팔레트
///
/// Firestore에는 int 값(Color.value)으로 저장.
/// null 이면 기본색(파랑) 사용.
class MarkerColors {
  MarkerColors._();

  static const List<Color> options = [
    Color(0xFF1A73E8), // 파랑 (기본)
    Color(0xFFE53935), // 빨강
    Color(0xFF34A853), // 초록
    Color(0xFFFF6D00), // 주황
    Color(0xFF9C27B0), // 보라
    Color(0xFFFFD600), // 노랑
    Color(0xFFE91E63), // 분홍
    Color(0xFF212121), // 검정
    Color(0xFF00BCD4), // 시안
    Color(0xFF26A69A), // 민트(틸)
    Color(0xFF7C4DFF), // 라벤더(딥퍼플)
    Color(0xFF3F51B5), // 인디고
    Color(0xFFFF5252), // 코랄
    Color(0xFFC0CA33), // 라임
    Color(0xFF795548), // 갈색
    Color(0xFF607D8B), // 블루그레이
  ];

  /// int? → Color (null 이면 기본 파랑)
  // ignore: deprecated_member_use
  static Color fromValue(int? value) =>
      value != null ? Color(value) : options.first;
}
