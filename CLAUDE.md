# PinFlick — Claude Code 개발 지침

## 📌 프로젝트 개요

* **서비스명**: PinFlick (핀플릭)
* **슬로건**: 📍 친구의 위치로 핀(Pin), 친구의 일상을 플릭(Flick)
* **목적**: 친구의 실시간 위치를 지도에서 공유하고, 위치 기반 브이로그·체크인을 남기는 소셜 위치 플랫폼
* **개발자**: 구자덕 (1인 개발, Claude Code와 협업)
* **배포**: https://pinflick.web.app (Firebase Hosting) · Android APK 베타 · PWA
* **레포 경로**: `C:\projects\mapvlog` (구 MapVlog → PinFlick 리브랜딩, 폴더명은 유지)

> ⚠️ Firebase 프로젝트 ID는 `mapvlog-1f06d` 이지만 서비스명/도메인은 **PinFlick / pinflick.web.app** 입니다.

---

## 🛠 기술 스택

| 구분 | 기술 |
|------|------|
| 프레임워크 | Flutter 3.41.x (Dart 3.x) |
| 플랫폼 | Android · Web(PWA). iOS는 미대응 |
| 지도 | Google Maps (`google_maps_flutter`) |
| 백엔드 | Firebase only (별도 서버 없음) |
| 인증 | Firebase Auth — **Google 로그인 전용** |
| DB | Cloud Firestore |
| 스토리지 | Firebase Storage |
| 푸시 | Firebase Cloud Messaging (FCM) + Cloud Functions |
| 서버리스 | Cloud Functions 2nd gen (Node 22, asia-northeast3) |
| 웹 배포 | Firebase Hosting (`firebase deploy --only hosting`) |
| 상태관리 | Provider |
| 역지오코딩 | Nominatim(OSM) HTTP + 모바일 기기 Geocoder fallback |

---

## 📁 프로젝트 폴더 구조

```
mapvlog/  (서비스명은 PinFlick)
├── lib/
│   ├── main.dart                      # 진입점 (Firebase init, FCM 백그라운드 핸들러)
│   ├── app.dart                       # MaterialApp, 라우팅, MainShell(하단탭+FAB), 코치마크
│   ├── firebase_options.dart          # FlutterFire 자동 생성
│   ├── screens/
│   │   ├── splash_screen.dart         # 스플래시 + 진입 분기(딥링크/온보딩/로그인)
│   │   ├── onboarding/                # 온보딩 슬라이드
│   │   ├── auth/                      # 로그인 (Google 전용)
│   │   ├── home/                      # 홈 피드 (친구 vlog/체크인 스트림)
│   │   ├── live_map/                  # 친구 실시간 위치 지도 ★핵심
│   │   ├── camera/                    # 브이로그 등록 마법사 (vlog_upload_wizard)
│   │   ├── gallery/                   # 그리드 + 포토맵 갤러리
│   │   ├── vlog/                      # 플레이어, 스와이퍼, 수정 화면(vlog_edit_screen)
│   │   ├── friends/                   # 친구 목록·검색·QR·그룹
│   │   ├── search/ · users/           # 검색 / 사용자 프로필
│   │   ├── profile/                   # 마이페이지 (저장한 vlog 등)
│   │   └── legal/                     # 약관·개인정보 처리방침
│   ├── widgets/
│   │   ├── vlog_card.dart             # 피드 카드
│   │   ├── check_in_sheet.dart        # 체크인 등록·수정 시트 (공용)
│   │   ├── comments_sheet.dart        # 댓글·답글·멘션
│   │   ├── map_picker_sheet.dart      # 지도에서 위치 선택 (공용) + LocationActionButton
│   │   ├── visibility_picker.dart     # 공개 범위 선택
│   │   ├── new_version_banner.dart    # 웹 OTA 갱신 배너
│   │   ├── first_run_coachmarks.dart  # 첫 로그인 3단계 가이드
│   │   └── ... (reaction_bar, likers_sheet, notifications_sheet 등)
│   ├── models/
│   │   ├── vlog.dart                  # 브이로그/체크인 (isCheckIn, expiresAt, visibility)
│   │   ├── friendship.dart            # 친구 관계 (relType, individualMode)
│   │   ├── friend_group.dart          # 친구 그룹 (GroupMode)
│   │   ├── user_status.dart           # 위치/프라이버시 모드, 상태, Ping
│   │   ├── comment.dart · reaction.dart · gps_point.dart
│   │   └── remote_version.dart        # version.json 파싱 (OTA)
│   ├── services/
│   │   ├── firestore_service.dart     # Firestore CRUD + 실시간 스트림
│   │   ├── firebase_storage_service.dart
│   │   ├── friend_service.dart · friend_group_service.dart
│   │   ├── user_status_service.dart   # 위치 업데이트·프라이버시·Ping
│   │   ├── reaction_service.dart
│   │   ├── push_service.dart          # FCM 토큰/권한/포그라운드·탭 핸들러
│   │   ├── geocoding_service.dart     # Nominatim 역지오코딩
│   │   ├── gps_tracking_service.dart · gps_interpolator.dart · location_service.dart
│   │   ├── web_version_check_service.dart  # version.json 폴링 (OTA)
│   │   └── web_cache_reload_(stub|io|web).dart  # 조건부 임포트
│   ├── providers/  (auth_provider, theme_provider)
│   └── utils/      (constants ← 버전·색상·VAPID키, marker_emojis, location_format 등)
├── functions/                         # Cloud Functions (FCM 발송 + 만료 체크인 정리)
│   └── index.js
├── android/ · web/                    # web/downloads/pinflick.apk (베타 APK)
├── tools/killswitch_sw.js             # 레거시 SW 자폭 스크립트
├── firestore.rules · firestore.indexes.json · firebase.json
├── web/version.json                   # OTA 버전 정보 (version/build/notes)
└── docs/                              # 설계·정책 문서
```

---

## 🗺 핵심 기능 (현재 구현 상태)

### 1. 친구 실시간 위치 지도 (Live Map) ★핵심
* 친구들의 현재 위치를 지도에 아바타 마커로 표시 (꼭지점이 실제 좌표)
* **프라이버시 3모드** (그룹 베이스라인):
  * 💖 **베프** — 실시간 정확 위치
  * 🙈 **부끄럼** — 동·반경(≈500m) 단위 대략 위치(안개)
  * 🥷 **잠수** — 숨김/오프라인·마지막 위치 고정
* **친구별 개별 오버라이드** (그룹보다 우선): 🎯 항상 정확히 · 🥷 항상 잠수 · 🔗 그룹 설정 따름
* 친구 그룹(커스텀 분류), 절전 로직(가속도계 이동감지 + 배터리 기반 위치 갱신 주기)
* 호출(Ping), 상태 설정

### 2. 체크인
* 위치 + 이모지 + 한 줄 메시지 (미디어 없음, `isCheckIn=true`)
* **표시 시간 선택**(1시간/6시간/오늘 종료/24시간) → 지도에서 만료 후 숨김 + 서버 자동 삭제
* 등록·수정 모두 동일한 `CheckInSheet` UI (위치 새로고침/지도선택/주소, 공개범위)

### 3. 브이로그
* **등록 마법사**(`vlog_upload_wizard`): 멀티 사진/영상, 압축, 폰 갤러리 자동저장, 카테고리 이모지, 2줄 스토리, 위치 보정(새로고침/지도/주소)
* **수정**(`vlog_edit_screen`): 단일 화면에서 사진·제목·장소·카테고리·위치·공개범위 편집
* **플레이어**: 영상 재생 ↔ 지도 마커 GPS 보간 동기화

### 4. 소셜
* 홈 피드(친구 vlog/체크인), 댓글·답글·@멘션, 좋아요, 저장(북마크), 이모지 리액션
* 친구 추가(검색·QR), 친구 요청 수락/거절
* 공개 범위: 🌐 전체공개 · 👥 그룹공개 · 🔒 나만보기

### 5. 알림 (FCM)
* 호출(Ping) · 친구 요청 · 댓글/답글 → 푸시 (Cloud Functions가 발송)
* 토큰: `users/{uid}/fcmTokens/{token}` (web=data-only, android=notification)

### 6. 인프라/UX
* 첫 로그인 3단계 코치마크 가이드
* 웹 OTA 갱신: `version.json` 폴링 → killswitch SW로 캐시 무효화 + 새 빌드 로드
* 갤러리(그리드 + 포토맵)

---

## ☁️ Cloud Functions (functions/index.js)

리전 `asia-northeast3`, Node 22, 2nd gen. **Blaze 플랜 필요.**

| 함수 | 트리거 | 동작 |
|------|--------|------|
| `onPingCreated` | `users/{uid}/pings/{id}` onCreate | 호출 푸시 |
| `onFriendDocCreated` | `users/{uid}/friends/{id}` onCreate (status=incoming) | 친구요청 푸시 |
| `onCommentCreated` | `vlogs/{vlogId}/comments/{id}` onCreate | 댓글/답글 푸시(스레드 참여자 전원) |
| `cleanupExpiredCheckins` | 스케줄 (매시간) | 만료 체크인 recursiveDelete |

배포: `firebase deploy --only functions` (functions/ 에서 `npm install` 선행)

---

## 🔥 Firestore 데이터 모델 (요약)

```
users/{uid}                      # 프로필, status, privacyMode, location
  ├── friends/{friendUid}        # 관계 (status, relType, individualMode)
  ├── friendGroups/{groupId}     # 커스텀 친구 그룹
  ├── pings/{pingId}             # 받은 호출 (1시간 이내)
  └── fcmTokens/{token}          # FCM 토큰 {platform, updatedAt}
vlogs/{vlogId}                   # 브이로그 + 체크인(isCheckIn, expiresAt)
  ├── comments/{commentId}       # 댓글/답글(parentId)
  ├── likes/{uid} · saves/{uid} · reactions/{uid_emoji}
config/{configId}                # 앱 설정
```
* `saves` 컬렉션그룹 쿼리는 **`uid` 필드 기반 규칙**으로 인가 (문서ID 아님).
* 자세한 스키마: `docs/05_db_schema.md`

---

## 🎨 UI/UX 가이드

### 컬러 팔레트 (`lib/utils/constants.dart` AppColors)
```dart
primary:        Color(0xFF1A73E8)  // Google Blue
secondary:      Color(0xFF34A853)  // Green
error:          Color(0xFFEA4335)  // Red
background:     Color(0xFFF8F9FA)
surface:        Color(0xFFFFFFFF)
textPrimary:    Color(0xFF202124)
textSecondary:  Color(0xFF5F6368)
textDisabled:   Color(0xFFBDC1C6)
```
* **다크모드 지원** — 색상은 가급적 `Theme.of(context).colorScheme.*` 사용. 고정 `AppColors.textPrimary` 등을 텍스트/아이콘 색에 쓰면 다크모드에서 안 보이므로 주의.
* 하단 탭별 색: 홈(블루)·친구지도(시안)·갤러리(퍼플)·친구(핑크). 가운데 FAB = 등록 마법사(롱프레스=체크인).

---

## 💻 개발 규칙

### 코드 스타일
* 파일 `snake_case.dart` · 클래스 `PascalCase` · 변수/함수 `camelCase` · 상수 `kXxx` / `AppColors.xxx`
* 공용 위젯은 `lib/widgets/` 로 추출해 등록·수정에서 재사용 (예: `CheckInSheet`, `MapPickerSheet`, `EmojiPickerRow`).

### 커밋 메시지
```
feat: 새 기능   fix: 버그수정   ui: UI/UX   refactor: 리팩토링
docs: 문서   chore: 설정·빌드
```

### Git
* `main` ← 배포용. 기능은 작업 후 main 커밋(현재 1인 개발이라 main 직접 사용).
* 커밋 끝에 `Co-Authored-By: Claude ...` 포함.

---

## 🚀 빌드 & 배포 절차 (중요)

웹은 **`--pwa-strategy=none`** 로 빌드하고, 캐시 무효화용 **killswitch SW를 주입**한 뒤 배포한다.

```bash
# 1) 버전 올리기 (3곳 동기화 필수)
#    - pubspec.yaml         version: X.Y.Z+B
#    - lib/utils/constants.dart  kAppVersion / kAppBuildNumber
#    - web/version.json     version / build / notes(업데이트 내역)

# 2) 웹 빌드 + killswitch SW 주입
flutter build web --release --pwa-strategy=none
cp tools/killswitch_sw.js build/web/flutter_service_worker.js

# 3) APK 빌드 → 다운로드 폴더로 복사
flutter build apk --release
cp build/app/outputs/flutter-apk/app-release.apk build/web/downloads/pinflick.apk

# 4) 배포
firebase deploy --only hosting              # 웹 + APK
firebase deploy --only firestore:rules      # 규칙 변경 시
firebase deploy --only functions            # 함수 변경 시
```

* `web/version.json` 의 `build` 가 `kAppBuildNumber` 보다 크면 실행 중인 앱에 OTA 갱신 배너가 뜬다.
* APK 는 `?v={build}` 캐시버스트로 받게 되어 있음.

### 자주 쓰는 명령
```bash
flutter run -d chrome      # 개발
flutter analyze            # 분석 (커밋 전 필수)
flutter pub get
```

---

## 🔑 환경변수 / 키

* `.env` (gitignore): `GOOGLE_MAPS_API_KEY`
* Firebase: `google-services.json`(Android), `firebase_options.dart`(Web/Flutter)
* **웹 FCM VAPID 키**: `lib/utils/constants.dart` 의 `kWebVapidKey` (콘솔 → Cloud Messaging → 웹 푸시 인증서)

---

## ⚠️ 주의사항

* GPS·위치 데이터는 항상 **null 체크**.
* 색상은 다크모드 대응 위해 **colorScheme 우선** (고정색 지양).
* Flutter Web은 `camera` 미지원 → 웹은 `image_picker` 파일 선택.
* 역지오코딩은 `GeocodingService`(Nominatim, 웹 동작) 우선 — `geocoding` 패키지의 `placemarkFromCoordinates` 는 웹 미지원이라 모바일 fallback 용으로만.
* 바텀시트/스와이퍼 안의 `GoogleMap` 은 제스처 경합 방지를 위해 `EagerGestureRecognizer` 지정.
* FCM 발송은 Cloud Functions(Blaze)에서만 — 클라이언트에서 직접 발송 불가.
* 체크인 만료 삭제는 정시 배치(최대 ~1시간 지연), 지도 표시는 즉시 숨김.

---

## 📦 주요 패키지

```yaml
google_maps_flutter, geolocator, geocoding        # 지도·위치
camera, image_picker, image_cropper, exif         # 촬영·사진
video_player, video_compress, gal                 # 영상·갤러리저장
firebase_core/auth/firestore/storage/messaging    # Firebase + FCM
google_sign_in                                    # 구글 로그인
provider                                          # 상태관리
share_plus, url_launcher                          # 공유/외부열기
shared_preferences, sqflite, path_provider        # 로컬
qr_flutter, mobile_scanner                        # 친구 QR
sensors_plus, battery_plus                        # 라이브맵 절전
visibility_detector, flutter_dropzone             # 피드 자동재생/웹 드롭
http, flutter_dotenv                              # 네트워크/환경변수
```

---

## 🔄 현재 상태

* **버전**: 1.56.2+83 (BETA)
* **Phase 1 MVP + 소셜·위치공유·FCM·체크인 완료**, Firebase Hosting 운영 중
* 개발 환경: Windows 11 / Flutter 3.41.x / VS Code

### 다음 후보
* iOS 대응(APNs), Play Store 정식 출시, 검색·해시태그 고도화
