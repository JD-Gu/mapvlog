# MapVlog - Claude Code 개발 지침

## 📌 프로젝트 개요

- **서비스명**: MapVlog (맵브이로그)
- **목적**: 브이로그 영상·사진에 GPS 타임스탬프를 기록하여 지도와 실시간 연동하는 플랫폼
- **개발자**: 구자덕 (1인 개발, Claude Code와 협업)
- **GitHub**: https://github.com/JD-Gu/mapvlog

---

## 🛠 기술 스택

| 구분 | 기술 |
|------|------|
| 프레임워크 | Flutter 3.41.x stable (Dart 3.x) |
| 플랫폼 | Android (출시) / iOS · Web (예정) |
| 지도 | Google Maps API |
| 백엔드 | Firebase (별도 서버 없음) |
| 데이터베이스 | Firebase Firestore |
| 인증 | Firebase Auth (Google 로그인, 이메일) |
| 스토리지 | Firebase Storage |
| 웹 배포 | Firebase Hosting (예정) |
| CI/CD | GitHub → Firebase Hosting 자동 배포 (예정) |
| 상태관리 | Provider |

---

## 📁 프로젝트 폴더 구조

```
mapvlog/
├── lib/
│   ├── main.dart                        # 앱 진입점
│   ├── app.dart                         # 앱 설정, 라우팅, 뒤로가기 처리
│   ├── firebase_options.dart            # FlutterFire 자동 생성
│   ├── screens/
│   │   ├── home/                        # 메인 홈 피드 (실시간 스트림)
│   │   ├── map/                         # 전체 브이로그 지도 (클러스터링)
│   │   ├── camera/                      # 촬영·업로드 (GPS 연동, 영상 압축)
│   │   ├── gallery/                     # 그리드 + 포토맵 갤러리
│   │   ├── vlog/                        # 브이로그 플레이어 (영상+지도 동기화)
│   │   ├── profile/                     # 사용자 프로필 (이름 수정, 통계)
│   │   ├── auth/                        # 로그인 화면
│   │   ├── onboarding/                  # 온보딩
│   │   └── splash_screen.dart
│   ├── widgets/
│   │   ├── vlog_card.dart               # 공통 카드 위젯 (조회수, 좋아요 표시)
│   │   └── map_controls.dart            # 지도 레이어 + 스트리트뷰 버튼
│   ├── models/
│   │   ├── vlog.dart                    # Firestore 브이로그 모델
│   │   ├── gps_point.dart               # GPS 좌표 모델
│   │   ├── recording_session.dart       # 녹화 세션 모델
│   │   └── media_item.dart              # 로컬 미디어 캐시 모델
│   ├── services/
│   │   ├── firestore_service.dart       # Firestore CRUD + 실시간 스트림
│   │   ├── firebase_storage_service.dart# Firebase Storage 업로드 (웹/모바일)
│   │   ├── gps_tracking_service.dart    # GPS 1초 단위 추적
│   │   ├── gps_interpolator.dart        # GPS 보간 알고리즘
│   │   ├── location_service.dart        # 현재 위치 조회
│   │   ├── upload_manager.dart          # 로컬 캐시 + Firebase 업로드 유틸
│   │   └── media_storage_service.dart   # 로컬 SharedPreferences 캐시
│   ├── providers/
│   │   └── auth_provider.dart           # Firebase Auth 상태관리 + 이름 수정
│   └── utils/
│       ├── constants.dart               # 색상, 간격, 반지름 등 디자인 상수
│       └── marker_colors.dart           # 지도 마커 색상 유틸
├── android/
├── ios/
├── web/
├── .env                                 # API 키 (gitignore)
├── pubspec.yaml
└── CLAUDE.md                            # 이 파일
```

---

## 🗺 핵심 기능

### Phase 1 - MVP ✅ 완성 (2026.05)

1. **GPS 연동 촬영 모듈**
   - 동영상·사진 촬영 시 1초 단위 GPS 좌표 자동 기록
   - 업로드 전 `video_compress`로 영상 압축 (용량 ~80% 감소)
   - 실시간 압축·업로드 진행률 다이얼로그 (0~100%)
   - 모바일: `ResolutionPreset.medium` 고정 (블랙스크린 방지)

2. **동영상-지도 실시간 동기화 플레이어**
   - 영상 재생 타임코드 → GPS 보간 → 지도 마커 실시간 이동
   - 출발·현재·도착 마커 탭 시 좌표(7자리) + 역지오코딩 주소 표시
   - 버퍼링 인디케이터 + 버퍼링 중 지도 동기화 일시 중단
   - 좋아요 버튼 (낙관적 UI 업데이트, 1인 1좋아요)
   - 조회수 자동 증가

3. **지도 + 클러스터링**
   - 전체 브이로그 위치 마커 표시
   - zoom 레벨 기반 자동 클러스터링 (커스텀 구현)
   - 마커 탭 시 팝업 → 재생

4. **Firebase 연동**
   - Firebase Auth: 이메일/Google 로그인 (웹은 `signInWithPopup`)
   - Firebase Storage: 영상·사진 업로드 (웹=putData, 모바일=putFile)
   - Firestore: 브이로그 저장·조회·실시간 스트림
   - **삭제 시 Storage 파일(영상+썸네일) 동시 삭제**

5. **갤러리**
   - 그리드 탭: 전체 브이로그 썸네일 목록 (길게 누르면 삭제)
   - 포토맵 탭: GPS 기록된 브이로그를 썸네일 마커로 표시
   - 클러스터 탭 → 목록 시트 → 바로 재생
   - `NeverScrollableScrollPhysics`로 지도 제스처 충돌 해결

6. **프로필**
   - 이름 옆 ✏️ 탭 → 이름 수정 (Firebase Auth + Firestore + 기존 브이로그 일괄 반영)
   - 내 브이로그 수·좋아요·조회수 통계
   - 내 브이로그 목록 (길게 누르면 삭제)

7. **앱 UX**
   - 뒤로가기: 다른 탭 → 홈 탭 이동 / 홈 탭 → 종료 확인 다이얼로그
   - 홈 피드 VlogCard: 조회수·좋아요 표시

### Phase 2 - 확장 (예정)

8. **소셜 기능**
   - 팔로우 / 팔로워
   - 사용자별 피드 분리
   - 공유 링크

9. **Flutter Web + Firebase Hosting 배포**
   - GitHub → Firebase Hosting 자동 배포
   - 반응형 웹 UI

10. **iOS 출시**
    - `Info.plist` 권한 설정
    - App Store 등록

---

## 📦 주요 패키지

```yaml
dependencies:
  # 지도
  google_maps_flutter: ^2.5.3

  # GPS 위치
  geolocator: ^13.0.1

  # 카메라·사진
  camera: ^0.11.0
  image_picker: ^1.1.2
  exif: ^3.3.0
  image: ^4.3.0              # EXIF 회전 교정

  # 영상
  video_player: ^2.9.1
  video_compress: ^3.1.2     # 업로드 전 압축 (용량 ~80% 감소)
  video_thumbnail: ^0.5.3    # 동영상 썸네일 추출

  # Firebase
  firebase_core: ^3.6.0
  firebase_auth: ^5.3.1
  cloud_firestore: ^5.4.4
  firebase_storage: ^12.3.4

  # 상태관리
  provider: ^6.1.2

  # 공유 / URL 실행
  share_plus: ^10.0.0
  url_launcher: ^6.2.0       # 스트리트뷰 외부 열기

  # 로컬 저장
  shared_preferences: ^2.3.2
  sqflite: ^2.3.3+1

  # Google 로그인
  google_sign_in: ^6.2.1

  # 역지오코딩 (좌표 → 주소)
  geocoding: ^3.0.0

  # 환경변수
  flutter_dotenv: ^5.2.1

dependency_overrides:
  # Windows 한글 사용자명 경로 문제 우회
  # path_provider_android 2.3.x의 jni(C++) 빌드가 한글 경로 처리 불가
  path_provider_android: '>=2.2.0 <2.3.0'
```

---

## 🎨 UI/UX 가이드

### 디자인 원칙
- **심플하고 직관적**: 현장에서 빠르게 촬영·기록 가능한 UX
- **지도 중심**: 지도가 항상 메인 뷰에 위치
- **모바일 퍼스트**: 모바일 UX 기준으로 설계 후 웹 반응형 적용

### 컬러 팔레트
```dart
primary:         Color(0xFF1A73E8)  // Google Blue
secondary:       Color(0xFF34A853)  // Google Green
background:      Color(0xFFF8F9FA)  // Light Gray
surface:         Color(0xFFFFFFFF)  // White
surfaceVariant:  Color(0xFFF1F3F4)  // Subtle Gray
error:           Color(0xFFEA4335)  // Red
textPrimary:     Color(0xFF202124)
textSecondary:   Color(0xFF5F6368)
textDisabled:    Color(0xFFBDC1C6)
```

### 주요 화면
1. **홈** — Firestore 실시간 피드 (VlogCard 목록)
2. **지도** — 전체 브이로그 위치 클러스터 마커
3. **촬영** — GPS 연동 카메라 / 파일 선택 (웹)
4. **갤러리** — 그리드 탭 + 포토맵 탭
5. **플레이어** — 영상 + 동기화 지도 + 좋아요
6. **프로필** — 내 브이로그 관리 + 이름 수정

---

## 💻 개발 규칙

### 코드 스타일
- Dart 공식 스타일 가이드 준수
- 파일명: `snake_case.dart`
- 클래스명: `PascalCase`
- 변수·함수명: `camelCase`
- 상수: `kConstantName` 또는 `AppColors.xxx`

### 커밋 메시지 규칙
```
feat: 새 기능 추가
fix: 버그 수정
ui: UI/UX 변경
refactor: 코드 리팩토링
docs: 문서 수정
test: 테스트 추가
chore: 설정·빌드 변경
```

### 브랜치 전략
```
main        ← 배포용 (Firebase Hosting 자동 배포)
develop     ← 개발 통합
feature/*   ← 기능별 개발
fix/*       ← 버그 수정
```

### 개발 환경
- **OS**: Windows 11 Pro
- **IDE**: Visual Studio Code
- **Flutter**: 3.41.x stable
- **Dart**: 3.x
- **Android Studio**: SDK 관리 전용
- **실기기**: Samsung Galaxy S21 (SM G991N, Android 15)

---

## 🚀 실행 명령어

```bash
# 실기기 실행
flutter run -d <device-id>

# 웹으로 실행
flutter run -d chrome

# 빌드
flutter build web          # 웹 배포용
flutter build apk          # Android APK (테스트)
flutter build appbundle    # Google Play용

# 패키지 설치
flutter pub get

# 코드 분석
flutter analyze

# 빌드 캐시 초기화 (네이티브 플러그인 추가 후 필수)
flutter clean && flutter pub get
```

---

## 🔑 환경변수 관리

민감한 키는 `.env` 파일로 관리 (`.gitignore`에 반드시 포함)

```
GOOGLE_MAPS_API_KEY=
```

Firebase 설정 파일 (모두 gitignore):
- `android/app/google-services.json`
- `ios/Runner/GoogleService-Info.plist`
- `lib/firebase_options.dart`
- `android/local.properties` (GOOGLE_MAPS_API_KEY 포함)

---

## 🔄 현재 진행 상황

### Phase 1 MVP ✅ 완성 (2026.05)

- [x] 개발환경 세팅
- [x] 프로젝트 기반 설정 (라우팅, 상수, 테마)
- [x] 인증 화면 (이메일 로그인, Google 로그인)
- [x] 지도 화면 (클러스터링 마커, 팝업)
- [x] 홈 화면 (Firestore 실시간 피드, 조회수 표시)
- [x] GPS 연동 촬영 (영상 압축 + 실시간 진행률)
- [x] 영상·지도 동기화 플레이어 (역지오코딩, 버퍼링 처리)
- [x] 좋아요 기능 (낙관적 UI, 1인 1좋아요)
- [x] Firebase Storage 업로드 + 삭제 시 파일 연동 삭제
- [x] 갤러리 (그리드 + 포토맵 썸네일 마커 + 클러스터 직접 재생)
- [x] 프로필 (이름 수정, 통계, 내 브이로그 삭제)
- [x] 뒤로가기 UX (탭 이동 → 종료 확인)

### 다음 작업 (Phase 2)

1. **GitHub push** — 코드 백업
2. **Firebase Hosting 연동** — Flutter Web 배포
3. **소셜 기능** — 팔로우, 공유
4. **iOS 빌드** — Info.plist 권한 설정

---

## 📋 참고 리소스

- [Flutter 공식 문서](https://docs.flutter.dev)
- [FlutterFire 공식 문서](https://firebase.flutter.dev)
- [google_maps_flutter](https://pub.dev/packages/google_maps_flutter)
- [geolocator 사용 가이드](https://pub.dev/packages/geolocator)
- [Firebase Hosting Flutter 배포](https://firebase.google.com/docs/hosting)

---

## ⚠️ 주의사항

### 필수 규칙
- GPS 데이터는 항상 **null 체크** 후 사용
- API 키는 절대 **코드에 하드코딩 금지** (`.env` 또는 `local.properties` 사용)
- 새 네이티브 플러그인 추가 후 반드시 `flutter clean` 실행

### 플랫폼별
- Flutter Web에서는 `camera` 패키지 미지원 → 웹은 `image_picker`로 파일 선택
- Google 로그인: 웹은 `signInWithPopup`, 모바일은 `google_sign_in` 패키지
- Firebase Storage 업로드: 웹=`putData(bytes)`, 모바일=`putFile(File)`
- iOS 배포 시 `Info.plist`에 카메라·위치·마이크 권한 명시 필요

### 알려진 이슈 & 해결책
| 이슈 | 원인 | 해결 |
|------|------|------|
| Windows 한글 경로 빌드 실패 | `path_provider_android` 2.3.x jni 빌드 | `dependency_overrides`로 2.2.x 고정 |
| Firestore `where` + `orderBy` 쿼리 실패 | 복합 인덱스 미생성 | `orderBy` 제거 후 클라이언트 정렬 |
| 다이얼로그 닫힐 때 크래시 | `TextEditingController.dispose()` 타이밍 | dispose() 제거, GC에 위임 |
| 카메라 모드 전환 시 블랙스크린 | `_setVideoMode`에서 카메라 재초기화 | 재초기화 코드 제거, `medium` 프리셋 고정 |
| 갤러리 포토맵 제스처 충돌 | `TabBarView`가 터치 가로채기 | `NeverScrollableScrollPhysics` 적용 |
