# 06. 디자인 가이드

## 개요

MapVlog의 UI/UX 디자인 원칙과 Flutter 구현을 위한 디자인 시스템을 정의합니다.

---

## 1. 디자인 원칙

**심플하고 직관적인 UX**
현장에서 빠르게 촬영하고 기록할 수 있도록 핵심 액션을 최소 탭으로 도달 가능하게 설계합니다.

**지도 중심 UI**
지도가 항상 메인 뷰에 위치하며, 콘텐츠는 지도 위 오버레이 또는 하단 시트로 표현합니다.

**모바일 퍼스트**
모바일 UX를 기준으로 설계하고, Flutter Web은 반응형으로 확장합니다.

**일관된 컴포넌트**
공통 위젯을 재사용하여 화면 간 시각적 일관성을 유지합니다.

---

## 2. 컬러 팔레트

### 메인 컬러

| 이름 | Color Code | Dart 코드 | 용도 |
|------|-----------|-----------|------|
| Primary | `#1A73E8` | `Color(0xFF1A73E8)` | 버튼, 링크, 강조 |
| Secondary | `#34A853` | `Color(0xFF34A853)` | 성공, GPS 활성, 녹화 상태 |
| Error | `#EA4335` | `Color(0xFFEA4335)` | 오류, 경고, 삭제 |
| Warning | `#FBBC04` | `Color(0xFFFBBC04)` | 주의, GPS 약신호 |

### 배경 / 서피스

| 이름 | Color Code | Dart 코드 | 용도 |
|------|-----------|-----------|------|
| Background | `#F8F9FA` | `Color(0xFFF8F9FA)` | 앱 전체 배경 |
| Surface | `#FFFFFF` | `Color(0xFFFFFFFF)` | 카드, 바텀시트 |
| Surface Variant | `#F1F3F4` | `Color(0xFFF1F3F4)` | 입력창 배경 |

### 텍스트

| 이름 | Color Code | Dart 코드 | 용도 |
|------|-----------|-----------|------|
| Text Primary | `#202124` | `Color(0xFF202124)` | 본문, 제목 |
| Text Secondary | `#5F6368` | `Color(0xFF5F6368)` | 부제목, 설명 |
| Text Disabled | `#BDC1C6` | `Color(0xFFBDC1C6)` | 비활성 텍스트 |

### 다크모드 대응 (Phase 2)

다크모드는 Phase 2에서 구현하며, Flutter ThemeData의 `ColorScheme.dark()`를 활용합니다.

---

## 3. 타이포그래피

Flutter `TextStyle` 기준으로 정의합니다. 기본 폰트는 시스템 기본값 사용 (Korean: Noto Sans KR 권장).

| 스타일명 | fontSize | fontWeight | color | 용도 |
|---------|----------|-----------|-------|------|
| headlineLarge | 28 | Bold (700) | Text Primary | 페이지 제목 |
| headlineMedium | 22 | SemiBold (600) | Text Primary | 섹션 제목 |
| titleLarge | 18 | SemiBold (600) | Text Primary | 카드 제목, 앱바 |
| titleMedium | 16 | Medium (500) | Text Primary | 리스트 항목 제목 |
| bodyLarge | 16 | Regular (400) | Text Primary | 본문 텍스트 |
| bodyMedium | 14 | Regular (400) | Text Secondary | 설명, 부연 |
| labelLarge | 14 | Medium (500) | Primary | 버튼 텍스트 |
| labelSmall | 12 | Regular (400) | Text Secondary | 태그, 타임스탬프 |

---

## 4. 간격 시스템 (Spacing)

8dp 기반 간격 시스템을 사용합니다.

```dart
// utils/constants.dart
class AppSpacing {
  static const double xs  = 4.0;
  static const double sm  = 8.0;
  static const double md  = 16.0;
  static const double lg  = 24.0;
  static const double xl  = 32.0;
  static const double xxl = 48.0;
}
```

---

## 5. 모서리 반경 (Border Radius)

```dart
class AppRadius {
  static const double sm   = 8.0;   // 작은 버튼, 태그
  static const double md   = 12.0;  // 카드, 입력창
  static const double lg   = 16.0;  // 바텀시트, 다이얼로그
  static const double full = 999.0; // 원형 버튼
}
```

---

## 6. 그림자 (Shadow)

```dart
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
```

---

## 7. 아이콘

Material Icons를 기본으로 사용하며, 커스텀 아이콘 필요 시 SVG 에셋으로 추가합니다.

| 기능 | 아이콘 | Material Icon 이름 |
|------|--------|-------------------|
| 홈 | 🏠 | `Icons.home` |
| 지도 | 🗺 | `Icons.map` |
| 촬영 | 📷 | `Icons.videocam` |
| 갤러리 | 🖼 | `Icons.photo_library` |
| 프로필 | 👤 | `Icons.person` |
| 위치 마커 | 📍 | `Icons.location_on` |
| 재생 | ▶ | `Icons.play_arrow` |
| 좋아요 | ♥ | `Icons.favorite` |
| 공유 | 📤 | `Icons.share` |
| GPS 활성 | 🛰 | `Icons.gps_fixed` |
| GPS 비활성 | | `Icons.gps_not_fixed` |

---

## 8. 버튼 스타일

### Primary Button

```dart
ElevatedButton(
  style: ElevatedButton.styleFrom(
    backgroundColor: Color(0xFF1A73E8),
    foregroundColor: Colors.white,
    minimumSize: Size(double.infinity, 52),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
    ),
  ),
)
```

### Secondary Button (Outlined)

```dart
OutlinedButton(
  style: OutlinedButton.styleFrom(
    foregroundColor: Color(0xFF1A73E8),
    side: BorderSide(color: Color(0xFF1A73E8)),
    minimumSize: Size(double.infinity, 52),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
    ),
  ),
)
```

### FAB (촬영 버튼)

```dart
FloatingActionButton.large(
  backgroundColor: Color(0xFFEA4335),  // 녹화 시작 전: Primary
  // 녹화 중: Color(0xFFEA4335) 빨강
  shape: CircleBorder(),
)
```

---

## 9. 지도 스타일

Google Maps API 커스텀 스타일을 적용하여 MapVlog 브랜드와 어울리는 지도를 제공합니다.

```dart
// 지도 마커 크기 기준
const double kVlogMarkerSize = 48.0;   // 브이로그 마커
const double kPhotoMarkerSize = 36.0;  // 사진 마커 (미니 썸네일)

// 경로 폴리라인 스타일
const Color kPolylineColor = Color(0xFF1A73E8);
const int kPolylineWidth = 4;
```

---

## 10. 애니메이션 가이드

Flutter 공식 애니메이션 가이드 기반으로 자연스럽고 빠른 전환을 사용합니다.

| 유형 | Duration | Curve | 용도 |
|------|----------|-------|------|
| 페이지 전환 | 300ms | easeInOut | 화면 전환 |
| 마커 이동 | 150ms | easeOut | 지도 마커 이동 |
| 바텀시트 | 250ms | easeOut | 바텀시트 표시 |
| 팝업 | 200ms | easeIn | 팝업 등장 |
| 좋아요 | 100ms | bounceOut | 좋아요 아이콘 |

---

## 11. 반응형 레이아웃 (Flutter Web)

| 브레이크포인트 | 너비 | 레이아웃 |
|--------------|------|---------|
| Mobile | < 600px | 단일 컬럼, 하단 탭바 |
| Tablet | 600px ~ 900px | 2컬럼 그리드, 사이드 탭 |
| Desktop | > 900px | 좌측 사이드바 + 메인 + 지도 |

플레이어 화면에서 데스크탑 이상은 좌우 분할(영상 + 지도) 레이아웃을 기본으로 적용합니다.

---

## 12. 접근성 (Accessibility)

- 모든 이미지에 `semanticLabel` 제공
- 버튼 최소 터치 영역: 48 × 48 dp
- 텍스트 대비율: WCAG AA 기준 (4.5:1) 이상
- 다이나믹 폰트 크기 대응 (Flutter `MediaQuery.textScaleFactor`)

---

*최종 수정: 2026-04-15*
