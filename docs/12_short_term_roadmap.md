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
| **1.5** | **지오펜스 알림** | 中 | P1 위에 구축. 친구 도착·안심존·자동 체크인 |
| **2** | 라이브 이벤트 맵 P1 | 大 | 차별화. 설계 완료(`docs/11`) |
| **3** | 출시 위생 + 그로스 | 中 | Play 내부테스트 · 푸시 다양화 · 초대 딥링크 |

### Phase 0 — 실사용 베타 운영 (상시·병행)
친구 초대 링크로 실테스터 확보 → 며칠 실사용 → Crashlytics 모니터링 + 피드백 즉시 수정.
산출물: 버그/UX 픽스 + "다음에 뭘 키울지" 데이터.

### Phase 1 — 백그라운드 위치 추적 〔리딩·Android〕
앱을 닫아도(opt-in 사용자) 포그라운드 서비스 + 상시 알림으로 위치 공유.
위치공유 앱의 본질 가치를 완성. 상세는 아래 "Phase 1 상세" 참조.

### Phase 1.5 — 지오펜스 알림 〔P1 위에 구축〕
지정 구역(집·회사·학교·이벤트장)에 친구/내가 진입·이탈할 때 **자동 알림·체크인**.
백그라운드 위치를 "점 이동"에서 **"먼저 알려주는 능동 알림"**으로 끌어올리는 킬러
유즈케이스. 상세는 아래 "Phase 1.5 상세" 참조.

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

### 현재 한계 / 정식배포 시 보완 ★결정 (2026-06)
- **현 구현(geolocator 포그라운드 서비스)은 "앱이 메모리에 살아있을 때"만 동작.**
  앱을 완전 종료(스와이프/OS kill)하면 Flutter 엔진과 함께 위치 서비스도 멈춤.
- **"앱 종료에도 유지"는 정식배포(Phase 3) 때 고려**하기로 결정(베타에선 현 수준 유지).
  - 보완안: `flutter_foreground_task` 별도 isolate sticky 포그라운드 서비스
    (isolate 안 Firebase 재초기화 → 주기적 위치 → Firestore 직접 기록).
  - 일부 OEM(삼성/샤오미)은 배터리 최적화 예외가 추가로 필요(최대한 자동 요청 동선 설계).

### 배포/정책 메모
베타 APK 단계라 당장 Play 심사 무관. 단, **Phase 3 Play 출시 전** 백그라운드 위치
선언 폼 + prominent disclosure 필수 → 지금부터 카피/동선을 정책 친화적으로 설계.

---

## Phase 1.5 상세 — 지오펜스 알림

### 목표
지정 구역(zone)에 **친구 또는 내가 진입/이탈**하면 자동 트리거(푸시 알림·자동 체크인).
**의존: Phase 1 백그라운드 위치 필수** — 앱이 꺼져도 위치가 흘러야 트리거 가능.

### 유즈케이스 (우선순위)
1. **안심존 / 친구 도착 알림** — "○○님이 [우리집] 근처 도착", "아이가 [학교] 도착/이탈". (가족 안심 = 킬러)
2. **장소 자동 체크인** — 저장한 장소 진입 시 체크인 제안/자동 생성.
3. **이벤트 근처 알림** — 진행 중 이벤트 반경 진입 시 푸시 (Phase 2 이벤트 맵과 결합).
4. **내 도착/출발 공유** — "방금 강남 도착".

### 접근 (추천: 서버사이드 지오펜스)
- 백그라운드 위치(P1)가 `users/{uid}.liveLocation` 갱신 → **Cloud Function**(onDocumentUpdated)에서
  사용자가 정의한 zone과 거리(`distanceBetween`) 비교 → in/out 상태가 바뀌면 **FCM 발송**.
- 장점: 기존 **FCM·Functions 재사용**, **보는 사람(다른 기기)에게 알림** 가능, 클라 배터리 부담 최소.
- 대안(클라 네이티브 `geofence_service`/`native_geofence`): OS가 앱 꺼져도 트리거(배터리 효율) 하나
  "내가 들어옴"만 로컬 감지 → 친구 도착 알림은 결국 서버 경유 필요 + 등록 개수 제한.
  → 친구 도착이 핵심이므로 **서버사이드** 우선.

### 데이터 모델 (예정)
- `users/{uid}/zones/{zoneId}`: `name, lat, lng, radius(m), watchTargets[](누구 진입을 알림받을지),
  notifyOn('enter'|'exit'|'both'), enabled`.
- 중복 알림 방지: zone별 마지막 in/out 상태 저장 (`users/{uid}/zoneStates` 또는 Function 메모리/문서).

### 프라이버시 (중요)
- **잠수(ice)** 친구는 위치가 안 흐르므로 지오펜스도 동작 안 함(설계 일관).
- **부끄럼(fog)**은 ~1km 마스킹이라 정밀 트리거 부정확 → **베프(정확) 관계에서만 정밀 지오펜스**.
- 친구 도착 알림은 그 친구가 나에게 위치를 공유(베프/부끄럼)하는 게 전제 — 일방 추적 불가.

### 재사용
- `cleanupExpiredCheckins`/`onCommentCreated` 등 **Functions 패턴**, `sendToUser`(FCM 발송),
  `Geolocator.distanceBetween`(클라) / 서버 distance 계산, `MapPickerSheet`(zone 위치 선택).

### 검증 (E2E)
1. zone 등록(집) → 친구가 백그라운드로 그 반경 진입 → 나에게 "도착" 푸시 1회(재진입 전까지 중복 X).
2. 이탈 시 'exit' 알림(설정 시).
3. 잠수 친구 → 트리거 안 됨. 부끄럼 친구 → 정밀 트리거 비활성(또는 대략).
4. 자동 체크인: 내 zone 진입 → 체크인 제안 동작.

### 로드맵 메모
- **Phase 1 직후** 착수(인프라 공유). 일부는 Phase 2(이벤트 근처)·Phase 3(푸시 그로스)와 합류.
- Functions onUpdate 트리거는 위치 갱신마다 호출 → **비용/호출량 점검**(부끄럼 그리드·throttle 고려).

---

## 결정 로그
- **시퀀스**: Phase 1 = 백그라운드 위치 → **Phase 1.5 = 지오펜스** → Phase 2 = 이벤트 맵
  → Phase 3 = 출시/그로스 (대표님 확정, 2026-06).
- 지오펜스는 백그라운드 위치(P1) 의존 → P1 직후 편입(서버사이드 권장).
- 이벤트 맵 P1 상세 계획·스펙은 `11_live_event_map.md`에 **보존**(삭제 금지).

*최종 수정: 2026-06*
