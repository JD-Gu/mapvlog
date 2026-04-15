# 07. 환경설정 가이드

## 개요

MapVlog 개발 환경을 처음부터 세팅하는 단계별 가이드입니다.
외부 서비스(Firebase, Google Maps, AWS S3) 연동 설정을 포함합니다.

---

## 사전 조건

| 항목 | 버전 | 확인 명령어 |
|------|------|-----------|
| Flutter | 3.41.x stable | `flutter --version` |
| Dart | 3.x | `dart --version` |
| Node.js | 20.x LTS | `node --version` |
| Git | 최신 | `git --version` |

---

## 1. 프로젝트 클론 및 패키지 설치

```bash
# 레포 클론
git clone https://github.com/JD-Gu/mapvlog.git
cd mapvlog

# Flutter 패키지 설치
flutter pub get

# 의존성 확인
flutter doctor
```

---

## 2. 환경변수 파일 설정

프로젝트 루트에 `.env` 파일을 생성합니다. (`.gitignore`에 포함되어 있으므로 절대 커밋하지 않습니다.)

```bash
# .env 파일 생성
touch .env
```

`.env` 파일 내용:
```
# Google Maps
GOOGLE_MAPS_API_KEY=여기에_키_입력

# 카카오맵
KAKAO_MAP_API_KEY=여기에_키_입력

# Firebase
FIREBASE_PROJECT_ID=여기에_프로젝트_ID_입력
FIREBASE_WEB_API_KEY=여기에_키_입력

# AWS S3
AWS_S3_BUCKET=여기에_버킷명_입력
AWS_S3_REGION=ap-northeast-2
AWS_CLOUDFRONT_DOMAIN=여기에_CloudFront_도메인_입력

# 백엔드 API
API_BASE_URL=https://api.mapvlog.com/v1
```

Flutter에서 `.env` 파일을 읽기 위해 `flutter_dotenv` 패키지를 사용합니다.

```yaml
# pubspec.yaml에 추가
dependencies:
  flutter_dotenv: ^5.x

flutter:
  assets:
    - .env
```

---

## 3. Firebase 설정

### 3.1 Firebase 프로젝트 생성

1. [Firebase Console](https://console.firebase.google.com) 접속
2. **프로젝트 추가** 클릭
3. 프로젝트 이름: `mapvlog` 입력
4. Google Analytics 활성화 (권장)

### 3.2 앱 등록

**Android 앱 등록**
1. Android 앱 추가 클릭
2. Android 패키지 이름: `com.mapvlog.app`
3. `google-services.json` 다운로드
4. `android/app/` 폴더에 복사

**iOS 앱 등록**
1. iOS 앱 추가 클릭
2. Bundle ID: `com.mapvlog.app`
3. `GoogleService-Info.plist` 다운로드
4. `ios/Runner/` 폴더에 복사

**Web 앱 등록**
1. 웹 앱 추가 클릭
2. 앱 닉네임: `mapvlog-web`
3. Firebase SDK 설정값을 `web/index.html`에 추가

### 3.3 FlutterFire CLI로 자동 설정

```bash
# FlutterFire CLI 설치
dart pub global activate flutterfire_cli

# Firebase 자동 설정 (firebase_options.dart 자동 생성)
flutterfire configure --project=mapvlog
```

### 3.4 Firebase 서비스 활성화

Firebase Console에서 아래 서비스를 활성화합니다.

| 서비스 | 경로 | 설정 |
|--------|------|------|
| Authentication | 빌드 → Authentication → 시작하기 | Google, Apple 로그인 활성화 |
| Firestore | 빌드 → Firestore → 데이터베이스 만들기 | 프로덕션 모드, 리전: `asia-northeast3 (서울)` |
| Storage | 빌드 → Storage → 시작하기 | 기본 규칙 적용 후 커스텀 |

### 3.5 Firestore 보안 규칙 배포

```bash
# Firebase CLI 설치
npm install -g firebase-tools

# 로그인
firebase login

# 초기화
firebase init firestore

# 규칙 배포 (05_db_schema.md의 규칙 적용)
firebase deploy --only firestore:rules
```

---

## 4. Google Maps API 설정

### 4.1 API 키 발급

1. [Google Cloud Console](https://console.cloud.google.com) 접속
2. 프로젝트 선택 (Firebase와 동일 프로젝트 권장)
3. **API 및 서비스 → 사용자 인증 정보 → API 키 만들기**

### 4.2 활성화할 API

| API 이름 | 용도 |
|---------|------|
| Maps SDK for Android | Android 지도 |
| Maps SDK for iOS | iOS 지도 |
| Maps JavaScript API | Flutter Web 지도 |
| Places API | 장소 정보 조회 |
| Geocoding API | 좌표 → 주소 변환 |
| Directions API | 경로 안내 (Phase 2) |

### 4.3 API 키 제한 설정 (보안)

- Android: 앱 패키지명 + SHA-1 지문으로 제한
- iOS: Bundle ID로 제한
- Web: 허용 도메인으로 제한 (`mapvlog.vercel.app`)

### 4.4 Android에 API 키 적용

`android/app/src/main/AndroidManifest.xml`에 추가:
```xml
<meta-data
    android:name="com.google.android.geo.API_KEY"
    android:value="${GOOGLE_MAPS_API_KEY}"/>
```

`android/app/build.gradle`에 추가:
```groovy
defaultConfig {
    manifestPlaceholders = [GOOGLE_MAPS_API_KEY: System.getenv("GOOGLE_MAPS_API_KEY") ?: ""]
}
```

### 4.5 iOS에 API 키 적용

`ios/Runner/AppDelegate.swift`에 추가:
```swift
import GoogleMaps

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GMSServices.provideAPIKey("YOUR_API_KEY")
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
```

---

## 5. AWS S3 + CloudFront 설정

### 5.1 S3 버킷 생성

1. [AWS Console](https://console.aws.amazon.com) → S3 → 버킷 만들기
2. 버킷 이름: `mapvlog-media`
3. 리전: `ap-northeast-2 (서울)`
4. **퍼블릭 액세스 차단**: 모두 차단 (CloudFront로만 접근)

### 5.2 S3 폴더 구조

```
mapvlog-media/
├── videos/
│   └── {uid}/
│       └── {filename}.mp4
├── photos/
│   └── {uid}/
│       └── {filename}.jpg
└── thumbs/
    └── {uid}/
        └── {filename}.jpg
```

### 5.3 CloudFront 배포 생성

1. CloudFront → 배포 생성
2. Origin: S3 버킷 선택
3. **뷰어 프로토콜 정책**: HTTPS만 허용
4. **캐시 정책**: CachingOptimized 적용
5. 배포 도메인 → `.env`의 `AWS_CLOUDFRONT_DOMAIN`에 저장

### 5.4 IAM 사용자 생성 (백엔드용)

1. IAM → 사용자 → 사용자 추가
2. 사용자 이름: `mapvlog-backend`
3. 권한 정책: S3 Pre-signed URL 발급 전용 정책 연결

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:PutObject",
        "s3:GetObject",
        "s3:DeleteObject"
      ],
      "Resource": "arn:aws:s3:::mapvlog-media/*"
    }
  ]
}
```

4. Access Key / Secret Key 발급 → 백엔드 서버 환경변수에 저장

---

## 6. iOS 권한 설정

`ios/Runner/Info.plist`에 아래 항목 추가:

```xml
<!-- 위치 권한 -->
<key>NSLocationWhenInUseUsageDescription</key>
<string>GPS 연동 촬영을 위해 위치 정보가 필요합니다.</string>
<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
<string>촬영 중 백그라운드 GPS 기록을 위해 위치 정보가 필요합니다.</string>

<!-- 카메라 권한 -->
<key>NSCameraUsageDescription</key>
<string>브이로그 촬영을 위해 카메라 접근이 필요합니다.</string>

<!-- 마이크 권한 -->
<key>NSMicrophoneUsageDescription</key>
<string>영상 촬영 시 오디오 녹음이 필요합니다.</string>

<!-- 사진 라이브러리 권한 -->
<key>NSPhotoLibraryUsageDescription</key>
<string>촬영한 사진을 저장하기 위해 갤러리 접근이 필요합니다.</string>
```

---

## 7. Android 권한 설정

`android/app/src/main/AndroidManifest.xml`에 추가:

```xml
<!-- 위치 권한 -->
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>
<uses-permission android:name="android.permission.ACCESS_BACKGROUND_LOCATION"/>

<!-- 카메라 권한 -->
<uses-permission android:name="android.permission.CAMERA"/>
<uses-permission android:name="android.permission.RECORD_AUDIO"/>

<!-- 저장소 권한 -->
<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE"/>
<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE"/>

<!-- 인터넷 권한 -->
<uses-permission android:name="android.permission.INTERNET"/>
```

---

## 8. 개발 서버 실행

```bash
# Flutter Web (주요 개발 환경)
flutter run -d chrome

# Android 에뮬레이터 (Android Studio에서 에뮬레이터 실행 후)
flutter run -d android

# 특정 디바이스 확인
flutter devices

# 코드 분석
flutter analyze

# 테스트 실행
flutter test
```

---

## 9. Vercel 배포 설정

### 9.1 Flutter Web 빌드

```bash
flutter build web --release
```

빌드 결과물: `build/web/` 폴더

### 9.2 Vercel 연동

1. [Vercel](https://vercel.com) → GitHub 연동
2. `mapvlog` 레포 Import
3. Framework Preset: `Other`
4. Build Command: `flutter build web --release`
5. Output Directory: `build/web`
6. 환경변수 추가 (`.env` 항목 그대로)

### 9.3 자동 배포

`main` 브랜치에 push 시 Vercel이 자동으로 빌드 및 배포합니다.

---

## 10. 체크리스트

개발 시작 전 아래 항목을 모두 확인합니다.

- [ ] Flutter 3.41.x 설치 확인 (`flutter doctor` 이상 없음)
- [ ] `.env` 파일 생성 및 모든 키 입력
- [ ] `google-services.json` → `android/app/` 복사
- [ ] `GoogleService-Info.plist` → `ios/Runner/` 복사
- [ ] `firebase_options.dart` 생성 확인
- [ ] Google Maps API 키 발급 및 각 플랫폼 적용
- [ ] AWS S3 버킷 생성 및 CloudFront 연동
- [ ] iOS `Info.plist` 권한 항목 추가
- [ ] Android `AndroidManifest.xml` 권한 항목 추가
- [ ] `flutter pub get` 실행
- [ ] `flutter run -d chrome` 정상 실행 확인

---

*최종 수정: 2026-04-15*
