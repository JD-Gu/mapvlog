# 12. 단기 개발 로드맵 (Short-term Roadmap) — v1

> 기준 버전: **v1.64.2 (BETA)** · 작성: 2026-06
> 상위 로드맵은 `09_roadmap.md`, 이벤트 맵 상세 스펙은 `11_live_event_map.md` 참조.

---

## Context (왜 지금)

PinFlick는 MVP + 소셜 + 위치공유 + 체크인에 더해 **안정화 묶음**을 마쳤다:
Crashlytics 크래시 모니터링 · 친구 초대/공유 · 위치 권한 엣지케이스 · 친구 필터 UX 정리.

기능은 충분히 갖춰졌다. 이제 **① 실사용자로 검증 → ② 핵심 완성도(백그라운드 위치)
→ ③ 차별화(이벤트 맵) → ④ 정식 출시** 순으로 간다. 본 문서가 그 순서를 정의한다.

---

## 현재 상태 스냅샷

- **플랫폼**: Web(PWA, pinflick.web.app) + Android APK 베타. iOS · Play Store 미출시.
- **완료**: 친구 실시간 위치(프라이버시 3모드), 체크인, 브이로그, 홈 피드/소셜, FCM,
  카드→지도앱 길찾기, 친구 필터 칩, 앱 전역 위치 추적, 크래시 모니터링.
- **핵심 한계**: **백그라운드 위치 미지원** — "친구가 앱을 켜야 실시간".
- **보류(설계 완료)**: 라이브 이벤트 맵 P1 (`11_live_event_map.md`).

---

## 단계 (확정 시퀀스)

| Phase | 테마 | 규모 | 비고 |
|-------|------|------|------|
| **0** | 실사용 베타 운영 (상시·병행) | 상시 | 초대 → 실사용 → Crashlytics·피드백 |
| **1** | **백그라운드 위치 추적** ★리딩 | 大 | Android. 본질 한계 해소 |
| **2** | 라이브 이벤트 맵 P1 | 大 | 차별화. 설계 완료(`docs/11`) |
| **3** | 출시 위생 + 그로스 | 中 | Play 내부테스트 · 푸시 다양화 · 초대 딥링크 |

### Phase 0 — 실사용 베타 운영 (상시·병행)
친구 초대 링크로 실테스터 확보 → 며칠 실사용 → Crashlytics 모니터링 + 피드백 즉시 수정.
산출물: 버그/UX 픽스 + "다음에 뭘 키울지" 데이터.

### Phase 1 — 백그라운드 위치 추적 〔리딩·Android〕
앱을 닫아도(opt-in 사용자) 포그라운드 서비스 + 상시 알림으로 위치 공유.
위치공유 앱의 본질 가치를 완성. 상세는 아래 "Phase 1 상세" 참조.

### Phase 2 — 라이브 이벤트 맵 P1 〔차별화〕
관리자 이벤트 등록 → 홈 피드/친구지도에 실시간 이벤트. "매일 열 이유" + 혼자 써도
콘텐츠가 채워짐. **상세 스펙·구현 계획은 `11_live_event_map.md` 에 그대로 보존**.
선결정: `docs/11`을 v1.0으로 마감, `kMasterUid` 확정.

### Phase 3 — 출시 위생 + 그로스 〔작은 단위 다수〕
- Play Store 내부 테스트 트랙 → 비공개 베타 (등록정보·스크린샷·위치/개인정보 정책 점검).
- 푸시 다양화: 새 체크인 · 이벤트 근처 · 친구 근처 도착 (`onComment` 패턴 복제).
- 초대 딥링크(초대자 자동 친구추천), 온보딩 코치마크에 이벤트/초대 단계 추가.

---

## Phase 1 상세 — 백그라운드 위치 추적 (Android)

### 목표
앱을 닫거나 다른 앱을 써도 — **opt-in으로 켠 사용자에 한해** — 배터리 친화 주기로
내 위치를 계속 공유. **웹은 불가(미적용), Android 전용.**

### 접근 (추천: geolocator 포그라운드 서비스)
신규 패키지 없이 **geolocator의 `AndroidSettings.foregroundNotificationConfig`** 로
`getPositionStream`을 포그라운드 서비스로 승격 → 백그라운드에서도 위치 업데이트 유지.
앱 프로세스가 살아있어 기존 Firebase / `UserStatusService.updateLocation` 그대로 재사용.

> 대안: `flutter_background_service`(별도 isolate, Firebase 재초기화 필요·복잡),
> `flutter_background_geolocation`(유료·범위 밖).

### 변경 (예정)
1. **opt-in 토글**(프로필/설정, 기본 OFF) — `users/{uid}.bgLocationEnabled` 저장.
   켤 때 **prominent disclosure 다이얼로그**(Play 정책) → 동의 시 권한 요청.
2. **권한**: 포그라운드 위치 → `ACCESS_BACKGROUND_LOCATION`("항상 허용").
3. **`LocationTrackingService` 확장**(`lib/services/location_tracking_service.dart`):
   토글 ON + 권한 OK면 `getPositionStream`(distanceFilter ~100m 또는 5분) 구독,
   각 업데이트마다 `updateLocation`(privacyMode=ice면 기존대로 skip).
   포그라운드/지도일 땐 현행 10초 로직, 백그라운드는 포그라운드-서비스 스트림이 담당.
4. **AndroidManifest**: `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_LOCATION`(API34+),
   `ACCESS_BACKGROUND_LOCATION` + geolocator 포그라운드 서비스 선언.
5. **상시 알림 카피**: "PinFlick이 위치를 공유 중입니다 · 끄려면 탭".
6. **끄기 동선**: 토글 OFF → 스트림/서비스 종료 + 알림 제거.

### 재사용
`LocationTrackingService`(전역 싱글톤, lifecycle/배터리/가속도 구현됨),
`UserStatusService.updateLocation`(privacy 마스킹 포함), 기존 권한 요청 패턴.

### 결정 필요
플러그인(추천 geolocator) · 갱신 정책(거리필터 100m vs 시간 5분) · 토글 기본 OFF ·
알림/디스클로저 카피.

### 검증 (E2E)
1. 토글 ON + "항상 허용" → 앱 백그라운드/종료 후 이동 → 다른 기기에서 내 위치 갱신 확인.
2. 상시 알림 표시 · 토글 OFF 시 알림/업데이트 중단.
3. 잠수(ice) 모드면 백그라운드여도 위치 미기록.
4. 배터리 영향 점검(거리필터/주기 조정).
5. 웹: 토글 미노출, 기존 동작 무변화.

### 배포/정책 메모
베타 APK 단계라 당장 Play 심사 무관. 단, **Phase 3 Play 출시 전** 백그라운드 위치
선언 폼 + prominent disclosure 필수 → 지금부터 카피/동선을 정책 친화적으로 설계.

---

## 결정 로그
- **시퀀스**: Phase 1 = 백그라운드 위치 → Phase 2 = 이벤트 맵 (대표님 확정, 2026-06).
- 이벤트 맵 P1 상세 계획·스펙은 `11_live_event_map.md`에 **보존**(삭제 금지).

*최종 수정: 2026-06*
