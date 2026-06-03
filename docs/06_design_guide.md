# 06. 디자인 가이드

PinFlick의 UI/UX 디자인 시스템입니다. 상수는 `lib/utils/constants.dart`(`AppColors`/`AppSpacing`/`AppRadius`/`AppShadow`) 기준.

---

## 1. 디자인 원칙

- **친구·지도 중심**: 친구의 실시간 위치 지도가 핵심. 콘텐츠는 지도 오버레이 + 하단 시트로.
- **빠른 액션**: 체크인/등록은 가운데 ➕ FAB로 최소 탭 도달 (탭=등록, 롱프레스=체크인).
- **모바일 퍼스트 + 웹 반응형**: 동일 코드로 Android·Web(PWA).
- **다크모드 우선 색상**: 텍스트/아이콘 색은 `Theme.of(context).colorScheme.*` 사용. 고정 `AppColors.textPrimary` 등을 직접 쓰면 다크모드에서 안 보이므로 지양.
- **컴포넌트 재사용**: `CheckInSheet`·`MapPickerSheet`·`EmojiPickerRow`·`VisibilityPickerChip` 등 공용화.

---

## 2. 컬러 팔레트 (AppColors)

| 이름 | Code | 용도 |
|------|------|------|
| primary | `#1A73E8` | 버튼·링크·강조 |
| secondary | `#34A853` | 성공·체크인 완료 |
| error | `#EA4335` | 오류·삭제·좋아요(채움) |
| background | `#F8F9FA` | 라이트 배경 |
| surface | `#FFFFFF` | 카드·시트 |
| textPrimary | `#202124` | 본문 |
| textSecondary | `#5F6368` | 부연 |
| textDisabled | `#BDC1C6` | 비활성 |

### 다크모드 (정식 지원)
`ThemeProvider` + `ColorScheme.dark` 기반. 다크 배경 `#121316`, 서피스 `#1C1D21`, surfaceVariant `#26282E`.
→ 색상은 반드시 `colorScheme.onSurface / onSurfaceVariant / surface / outline` 등을 사용.

### 위치 공개 모드 팔레트 (브랜드 요소)
| 모드 | 이모지 | 의미 |
|------|--------|------|
| 베프 | 💖 | 실시간 정확 위치 |
| 부끄럼 | 🙈 | 동·반경 대략(안개) |
| 잠수 | 🥷 | 숨김/고정 |
| (개별) 항상 정확 / 항상 잠수 / 그룹 따름 | 🎯 / 🥷 / 🔗 | 친구별 오버라이드 |

### 하단 탭 컬러 (탭별)
홈 `#1A73E8`(블루) · 친구지도 `#00ACC1`(시안) · 갤러리 `#7C4DFF`(퍼플) · 친구 `#EC407A`(핑크).
선택 탭은 **해당 컬러 알약(alpha 0.15) 배경 + 확대** 로 강조.

---

## 3. 간격 / 반경 / 그림자 (constants.dart)

```dart
class AppSpacing { xs=4, sm=8, md=16, lg=24, xl=32, xxl=48 }
class AppRadius  { sm=8, md=12, lg=16, full=999 }   // 카드=md, 시트=lg, 알약/원형=full
class AppShadow  { card(blur8 y2), elevated(blur16 y4) }
```

---

## 4. 타이포그래피

시스템 기본 폰트(Noto Sans KR 권장). 제목 `w800`, 카드 제목 `w700`, 본문 14~16 `w400~500`, 메타/타임스탬프 11~12 `textSecondary`.

---

## 5. 아이콘 (하단 네비 등)

| 기능 | Material Icon |
|------|---------------|
| 홈 | `home` / `home_outlined` |
| 친구지도 | `map` / `map_outlined` ← (구 groups, 친구 아이콘과 혼동되어 변경) |
| 등록(FAB) | `add` (➕, 중앙 docked) |
| 갤러리 | `photo_library` / `_outlined` |
| 친구 | `people` / `people_outline` |
| 좋아요 | `favorite` / `favorite_outline` (채움=error) |
| 저장 | `bookmark` / `bookmark_border` (채움=`#FFC107`) |
| 댓글·공유 | `mode_comment_outlined` · `send_outlined` |
| 호출 | `notifications_active` |

---

## 6. 버튼 / FAB

- **Primary**: `FilledButton`/`ElevatedButton` — bg `primary`, 흰 글씨, 높이 50~52, radius `md`.
- **중앙 FAB**: `PulsingFab` (centerDocked) — 탭=등록 마법사, 롱프레스=체크인. BottomAppBar 노치와 결합.
- 지도 위 칩/버튼: surface 배경 + 그림자, radius `full`.

---

## 7. 지도 스타일

```dart
// 친구 아바타 마커: 커스텀 비트맵(아바타 + 컬러 링 + 꼬리 꼭지점) — anchor 가 꼭지점=실좌표
// 체크인 마커: 작은 이모지 버블 (anchor 중앙)
// 폴리라인(플레이어 이동경로): primary, width 4
// 바텀시트/스와이퍼 내부 GoogleMap 은 EagerGestureRecognizer 로 제스처 우선 점유
```

---

## 8. 애니메이션

| 유형 | Duration | Curve |
|------|----------|-------|
| 페이지 전환 | 300ms | easeInOut |
| 바텀시트 | 250ms | easeOut |
| 탭 알약/선택 | 220~240ms | easeOut / easeOutBack |
| 좋아요·리액션 | 120~180ms | easeOutBack |
| 마커 펄스/코치마크 | 260ms | easeOut |

---

## 9. 반응형 (Web)

| 브레이크포인트 | 레이아웃 |
|--------------|---------|
| Mobile < 600 | 단일 컬럼 + 하단 탭 |
| Tablet 600~900 | 넓은 카드/그리드 |
| Desktop > 900 | 중앙 정렬 컨테이너 |

---

## 10. 접근성

- 터치 영역 최소 48×48
- 텍스트 대비 WCAG AA(4.5:1) 이상 — 다크모드 colorScheme 준수
- 이미지 `semanticLabel`, 동적 폰트 크기 대응

---

*최종 수정: 2026-06 (PinFlick 기준)*
