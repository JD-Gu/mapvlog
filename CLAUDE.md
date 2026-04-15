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
| 프레임워크 | Flutter 3.x (Dart) |
| 플랫폼 | Android / iOS / Web (Flutter Web) |
| 지도 | Google Maps API / 카카오맵 API |
| 장소 정보 | Google Places API / 카카오 로컬 API |
| 백엔드 | Node.js + Express (AWS EC2 또는 NCP) |
| 데이터베이스 | Firebase Firestore |
| 인증 | Firebase Auth |
| 스토리지 | AWS S3 + CloudFront CDN |
| 웹 배포 | Vercel (Flutter Web) |
| CI/CD | GitHub → Vercel 자동 배포 |
| 상태관리 | Provider 또는 Riverpod |

---

## 📁 프로젝트 폴더 구조

```
mapvlog/
├── lib/
│   ├── main.dart              # 앱 진입점
│   ├── app.dart               # 앱 설정, 라우팅
│   ├── screens/               # 화면 단위 UI
│   │   ├── home/              # 메인 홈 화면
│   │   ├── map/               # 지도 화면
│   │   ├── camera/            # 촬영 화면 (영상+사진)
│   │   ├── gallery/           # 포토맵 갤러리
│   │   ├── vlog/              # 브이로그 플레이어
│   │   └── profile/           # 사용자 프로필
│   ├── widgets/               # 공통 위젯
│   ├── models/                # 데이터 모델
│   ├── services/              # API, GPS, 카메라 서비스
│   ├── providers/             # 상태관리
│   └── utils/                 # 유틸리티, 상수
├── android/
├── ios/
├── web/
├── test/
├── pubspec.yaml
└── CLAUDE.md                  # 이 파일
```

---

## 🗺 핵심 기능 (개발 우선순위 순)

### Phase 1 - MVP (1~6개월)
1. **GPS 연동 촬영 모듈**
   - 동영상·사진 촬영 시 1초 단위 GPS 좌표 자동 기록
   - 사진 EXIF에 GPS 메타데이터 자동 삽입
   - GPS 타임스탬프를 JSON으로 로컬 저장

2. **동영상-지도 실시간 동기화 플레이어**
   - 영상 재생 타임코드와 지도 마커 실시간 연동
   - 보간법 적용한 GPS 좌표 인덱스 변환 알고리즘

3. **장소 정보 팝업 및 경로 표시**
   - GPS 좌표 기반 Places API 자동 질의
   - 이동 경로 폴리라인 표시
   - 포토맵 갤러리 (사진+지도 마커 연동)

### Phase 2 - 확장 (7~12개월)
4. **클라우드 백엔드 및 소셜 기능**
   - Firebase Auth 사용자 인증
   - AWS S3 영상·사진 업로드
   - 브이로그 공유 링크 생성
   - 친구 공유·팔로우 기능

5. **Flutter Web 배포**
   - Vercel 연동 자동 배포
   - 반응형 웹 UI

---

## 📦 주요 패키지 (pubspec.yaml)

```yaml
dependencies:
  flutter:
    sdk: flutter
  
  # 지도
  google_maps_flutter: ^2.x
  
  # GPS 위치
  geolocator: ^13.x
  
  # 카메라·사진
  camera: ^0.11.x
  image_picker: ^1.x
  exif: ^4.x
  
  # 영상 플레이어
  video_player: ^2.x
  
  # Firebase
  firebase_core: ^3.x
  firebase_auth: ^5.x
  cloud_firestore: ^5.x
  firebase_storage: ^12.x
  
  # 네트워크
  dio: ^5.x
  
  # 상태관리
  provider: ^6.x
  
  # 공유
  share_plus: ^10.x
  
  # 로컬 저장
  shared_preferences: ^2.x
  sqflite: ^2.x
```

---

## 🎨 UI/UX 가이드

### 디자인 원칙
- **심플하고 직관적**: 현장에서 빠르게 촬영·기록 가능한 UX
- **지도 중심**: 지도가 항상 메인 뷰에 위치
- **모바일 퍼스트**: 모바일 UX 기준으로 설계 후 웹 반응형 적용

### 컬러 팔레트
```dart
// 메인 컬러
primary: Color(0xFF1A73E8)      // Google Blue
secondary: Color(0xFF34A853)    // Google Green
background: Color(0xFFF8F9FA)   // Light Gray
surface: Color(0xFFFFFFFF)      // White
error: Color(0xFFEA4335)        // Red
```

### 주요 화면
1. **홈** - 최근 브이로그 피드 + 지도 미리보기
2. **지도** - 전체 브이로그 위치 마커 표시
3. **촬영** - GPS 연동 카메라 (영상/사진 전환)
4. **플레이어** - 영상 + 동기화 지도 (좌우 분할 또는 PIP)
5. **갤러리** - 포토맵 (사진 클릭 시 지도 마커 연동)
6. **프로필** - 내 브이로그 관리

---

## 💻 개발 규칙

### 코드 스타일
- Dart 공식 스타일 가이드 준수
- 파일명: `snake_case.dart`
- 클래스명: `PascalCase`
- 변수·함수명: `camelCase`
- 상수: `kConstantName`

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
main        ← 배포용 (Vercel 자동 배포)
develop     ← 개발 통합
feature/*   ← 기능별 개발
fix/*       ← 버그 수정
```

### 개발 환경
- **IDE**: Visual Studio Code
- **Flutter**: 3.41.x stable
- **Dart**: 3.x
- **Android Studio**: SDK 관리 전용
- **에뮬레이터**: Chrome (웹), Android 에뮬레이터

---

## 🚀 실행 명령어

```bash
# 웹으로 실행 (개발 중 주로 사용)
flutter run -d chrome

# Android 에뮬레이터로 실행
flutter run -d android

# 빌드
flutter build web          # 웹 배포용
flutter build apk          # Android APK
flutter build appbundle    # Google Play용

# 패키지 설치
flutter pub get

# 코드 분석
flutter analyze

# 테스트
flutter test
```

---

## 🔑 환경변수 관리

민감한 키는 `.env` 파일로 관리 (`.gitignore`에 반드시 포함)

```
GOOGLE_MAPS_API_KEY=
KAKAO_MAP_API_KEY=
FIREBASE_PROJECT_ID=
AWS_S3_BUCKET=
```

---

## 🔄 현재 진행 상황

### 개발환경 세팅 완료
- OS: Windows 11 Pro
- Flutter: 3.41.6 stable
- Android Studio: 설치 완료 (Android SDK 36.1.0)
- VScode: Flutter 확장 설치 완료
- Claude Code: VScode 연동 완료

### 프로젝트 현황
- 프로젝트 생성: `C:\projects\mapvlog` ✅
- GitHub 레포: https://github.com/JD-Gu/mapvlog (연동 진행 중)
- Vercel 연동: 예정

### 현재 단계
- [x] 개발환경 세팅
- [x] CLAUDE.md 초안 작성
- [ ] **docs/ 기획·설계 문서 작성 중** ← 현재 여기
- [ ] pubspec.yaml 패키지 설정
- [ ] Phase 1 MVP 개발 시작

### 다음 작업
1. `docs/` 폴더 생성 및 기획·설계 문서 작성
   - 01_system_architecture.md
   - 02_scenario.md
   - 03_wireframe.md
   - 04_api_spec.md
   - 05_db_schema.md
   - 06_design_guide.md
2. GitHub push
3. Vercel 연동

### 개발 방향
- 기획·설계 완료 후 구현 단계 진입
- 1인 개발 (구자덕 대표 + Claude AI 협업)
- Flutter Web은 Vercel로 배포, 모바일은 앱스토어 출시 목표

---

## 📋 참고 리소스

### 공식 문서
- [Flutter 공식 문서](https://docs.flutter.dev)
- [Dart 언어 가이드](https://dart.dev/guides)
- [pub.dev 패키지 저장소](https://pub.dev)

### 지도·위치
- [google_maps_flutter 예제](https://pub.dev/packages/google_maps_flutter)
- [geolocator 사용 가이드](https://pub.dev/packages/geolocator)
- [카카오맵 Flutter 연동](https://pub.dev/packages/kakao_map_plugin)

### 카메라·미디어
- [camera 패키지 공식 예제](https://pub.dev/packages/camera)
- [video_player 예제](https://pub.dev/packages/video_player)
- [image_picker 가이드](https://pub.dev/packages/image_picker)

### Firebase 연동
- [FlutterFire 공식 문서](https://firebase.flutter.dev)
- [Firebase Auth 가이드](https://firebase.flutter.dev/docs/auth/overview)
- [Cloud Firestore 가이드](https://firebase.flutter.dev/docs/firestore/overview)

### 오픈소스 참고 프로젝트
- [Flutter samples (공식)](https://github.com/flutter/samples)
- [Flutter gallery](https://github.com/flutter/gallery)
- [geolocator 공식 예제](https://pub.dev/packages/geolocator/example)

---

## ⚠️ 주의사항

- GPS 데이터는 항상 **null 체크** 후 사용
- 영상 파일은 용량이 크므로 **압축 후 업로드**
- API 키는 절대 **코드에 하드코딩 금지**
- Flutter Web에서는 `camera` 패키지 미지원 → 웹은 **업로드 방식**으로 대체
- iOS 배포 시 `Info.plist`에 카메라·위치 권한 명시 필요
