# 10. Claude Code 단계별 지시문

## 사용법

- 각 마일스톤 시작 시 VSCode Claude Code 채팅창에 지시문을 **그대로 복사·붙여넣기** 합니다.
- 지시문 안의 `[대괄호]` 항목은 실제 값으로 교체하세요.
- 검증 항목을 모두 통과해야 다음 마일스톤으로 진행합니다.

---

## ✅ Phase 0 — 완료

개발환경 세팅 및 기획·설계 문서 작성 완료.

---

## 🚀 마일스톤 1 — 프로젝트 기반 설정

### Claude Code 지시문

```
다음 문서를 읽고 작업해줘:
- docs/01_system_architecture.md
- docs/06_design_guide.md
- docs/07_setup_guide.md

[마일스톤 1] 프로젝트 기반 설정을 진행해줘.

작업 목록:
1. pubspec.yaml에 아래 패키지를 모두 추가해줘.
   - google_maps_flutter, geolocator, camera, image_picker, exif
   - video_player, firebase_core, firebase_auth, cloud_firestore
   - firebase_storage, dio, provider, share_plus
   - shared_preferences, sqflite, flutter_dotenv

2. lib/ 폴더 구조를 아래처럼 만들어줘. (빈 파일 포함)
   lib/
   ├── main.dart
   ├── app.dart
   ├── screens/home/, map/, camera/, gallery/, vlog/, profile/
   ├── widgets/
   ├── models/
   ├── services/
   ├── providers/
   └── utils/constants.dart

3. main.dart에 Firebase 초기화 코드 작성해줘. (firebase_options.dart 참조)

4. app.dart에 MaterialApp 설정, 라우팅, ThemeData를 작성해줘.
   - 컬러: Primary #1A73E8, Secondary #34A853, Background #F8F9FA
   - 폰트: 시스템 기본값

5. utils/constants.dart에 AppSpacing, AppRadius, AppShadow, AppColors 상수 정의해줘.
   (docs/06_design_guide.md 기준)

6. .env 파일을 pubspec.yaml assets에 등록하고, flutter_dotenv 초기화 코드를 main.dart에 추가해줘.

flutter pub get 실행 후 flutter analyze 오류 없는지 확인해줘.
```

### 검증 방법

```bash
flutter pub get
flutter analyze       # 오류 0개 확인
flutter run -d chrome # 빈 앱이 크롬에서 정상 실행되면 OK
```

**통과 기준**
- [ ] `flutter analyze` 오류 없음
- [ ] Chrome에서 흰 화면 또는 기본 앱 정상 실행
- [ ] `lib/` 폴더 구조 생성 확인

---

## 🚀 마일스톤 2 — 인증 화면

### Claude Code 지시문

```
다음 문서를 읽고 작업해줘:
- docs/02_scenario.md  (시나리오 1 — 온보딩/로그인)
- docs/03_wireframe.md (화면 1, 화면 2)
- docs/06_design_guide.md

[마일스톤 2] 인증 화면을 구현해줘.

작업 목록:
1. screens/splash_screen.dart
   - MapVlog 로고 + 앱 이름 표시
   - 2초 후 온보딩 또는 홈으로 자동 이동 (로그인 상태 체크)

2. screens/onboarding/onboarding_screen.dart
   - PageView로 슬라이드 3장 구현
   - 슬라이드 내용: "GPS와 함께 기록하세요" / "지도 위에서 다시 보세요" / "여행을 공유하세요"
   - 인디케이터 dots + [건너뛰기] + [다음] 버튼

3. screens/auth/login_screen.dart
   - Google 로그인 버튼 (firebase_auth google sign-in)
   - Apple 로그인 버튼 (iOS 전용, 웹·Android에서는 숨김)
   - "로그인 없이 둘러보기" 텍스트 버튼

4. providers/auth_provider.dart
   - 로그인 상태 관리 (ChangeNotifier)
   - 로그인/로그아웃 메서드
   - Firestore users 컬렉션에 사용자 자동 저장

5. app.dart 라우팅에 splash → onboarding → login → home 흐름 추가

디자인은 docs/06_design_guide.md 컬러·버튼 스타일 기준으로 해줘.
```

### 검증 방법

```bash
flutter run -d chrome
```

**통과 기준**
- [ ] 앱 실행 시 스플래시 → 온보딩 화면 자동 이동
- [ ] 온보딩 슬라이드 3장 스와이프 동작
- [ ] [건너뛰기] 버튼 → 로그인 화면 이동
- [ ] Google 로그인 버튼 클릭 시 Google 인증 팝업 표시
- [ ] 로그인 성공 후 홈 화면으로 이동
- [ ] Firebase Console → Authentication에 사용자 등록 확인
- [ ] Firebase Console → Firestore → users 컬렉션 문서 생성 확인

---

## 🚀 마일스톤 3 — 지도 + 홈 화면

### Claude Code 지시문

```
다음 문서를 읽고 작업해줘:
- docs/03_wireframe.md (화면 3, 화면 4)
- docs/06_design_guide.md

[마일스톤 3] 홈 피드 화면과 지도 화면을 구현해줘.

작업 목록:
1. widgets/bottom_tab_bar.dart
   - 하단 탭 5개: 홈(home), 지도(map), 촬영(videocam), 갤러리(photo_library), 프로필(person)
   - 촬영 탭은 Primary 컬러로 강조
   - 현재 탭 인디케이터 표시

2. widgets/vlog_card.dart
   - 썸네일 이미지 + 제목 + 위치명 + 시간 + 작성자
   - 카드 그림자, 모서리 반경 12dp (docs/06_design_guide.md 기준)

3. screens/home/home_screen.dart
   - 상단 앱바: MapVlog 로고 + 알림·검색 아이콘
   - 지도 미리보기 배너 (현재 위치 기준 Google Maps 축소 뷰)
   - VlogCard 그리드 (2열) — 현재는 더미 데이터로 표시

4. screens/map/map_screen.dart
   - Google Maps 전체화면
   - 현재 위치 버튼
   - 더미 마커 3~5개 표시 (나중에 실제 데이터로 교체)
   - 마커 클릭 시 하단 팝업: 썸네일 + 제목 + [재생] 버튼

5. services/location_service.dart
   - geolocator로 현재 위치 가져오기
   - 위치 권한 요청 처리 (거부 시 안내 다이얼로그)

Google Maps API 키는 .env의 GOOGLE_MAPS_API_KEY를 사용해줘.
```

### 검증 방법

```bash
flutter run -d chrome
# Android 에뮬레이터 있으면 병행 테스트 권장
flutter run -d android
```

**통과 기준**
- [ ] 하단 탭 5개 전환 정상 동작
- [ ] 홈 화면에 VlogCard 더미 데이터 표시
- [ ] 지도 화면에 Google Maps 정상 로드
- [ ] 현재 위치 버튼 → 내 위치로 지도 이동
- [ ] 더미 마커 클릭 → 하단 팝업 표시
- [ ] Android 에뮬레이터에서 위치 권한 요청 팝업 표시

---

## 🚀 마일스톤 4 — GPS 연동 촬영

### Claude Code 지시문

```
다음 문서를 읽고 작업해줘:
- docs/02_scenario.md  (시나리오 2 — GPS 연동 촬영)
- docs/03_wireframe.md (화면 5 — 촬영 화면)
- docs/08_gps_algorithm.md (전체)

[마일스톤 4] GPS 연동 촬영 기능을 구현해줘.

작업 목록:
1. models/gps_point.dart
   - docs/08_gps_algorithm.md의 GpsPoint 클래스 그대로 구현

2. services/gps_tracker.dart
   - geolocator로 1초마다 GPS 좌표 수집
   - GpsPoint 리스트에 타임코드(초)와 함께 저장
   - start() / stop() / getTrack() 메서드
   - docs/08_gps_algorithm.md의 filterOutliers() 적용

3. screens/camera/camera_screen.dart
   - 카메라 프리뷰 (camera 패키지)
   - 상단: GPS 좌표 + 위성 수신 상태 표시
   - 현재 위치명 오버레이 (services/location_service.dart 활용)
   - [영상] / [사진] 전환 탭
   - 영상 모드: 촬영 시작/종료 버튼, REC + 타이머 표시
   - 사진 모드: 셔터 버튼

4. 영상 촬영 시 GPS 동시 기록
   - 촬영 시작 → GpsTracker.start()
   - 촬영 종료 → GpsTracker.stop() → GPS JSON 생성
   - GPS JSON을 sqflite 로컬 DB에 임시 저장

5. 사진 촬영 시 EXIF GPS 삽입
   - exif 패키지로 촬영 사진에 GPS 메타데이터 삽입
   - 로컬 갤러리에 저장

6. Flutter Web에서는 camera 패키지 미지원
   - 웹 빌드 시 촬영 탭 대신 "파일 업로드" 버튼으로 대체

위치 권한은 services/location_service.dart 재사용해줘.
```

### 검증 방법

```bash
# 반드시 Android 실기기 또는 에뮬레이터에서 테스트
flutter run -d android
```

**통과 기준**
- [ ] 촬영 화면 진입 시 카메라 프리뷰 정상 표시
- [ ] 상단에 GPS 좌표 실시간 업데이트 표시
- [ ] 영상 촬영 시작 → REC + 타이머 동작
- [ ] 촬영 종료 후 GPS JSON 파일 생성 확인 (로컬 저장)
- [ ] 사진 촬영 후 갤러리에서 GPS EXIF 정보 확인
- [ ] GPS 신호 없는 환경(실내)에서 "GPS 신호 확인 중" 표시

> **팁**: Android Studio의 에뮬레이터에서 GPS 좌표를 수동으로 설정할 수 있습니다.
> (Extended Controls → Location → 임의 좌표 입력)

---

## 🚀 마일스톤 5 — 업로드

### Claude Code 지시문

```
다음 문서를 읽고 작업해줘:
- docs/02_scenario.md  (시나리오 3 — 브이로그 업로드)
- docs/03_wireframe.md (화면 9 — 업로드 화면)
- docs/04_api_spec.md  (2.3 Pre-signed URL, 2.4 메타데이터 저장)
- docs/05_db_schema.md (vlogs 컬렉션, gpsTracks 서브컬렉션)

[마일스톤 5] 브이로그 업로드 기능을 구현해줘.

작업 목록:
1. 백엔드 Node.js 서버 기본 구조 생성 (별도 폴더 server/)
   - server/index.js (Express 앱 진입점)
   - server/routes/vlogs.js (업로드 라우트)
   - server/services/s3.js (Pre-signed URL 발급)
   - .env에서 AWS 키 읽기 (dotenv 패키지)
   - POST /v1/vlogs/upload-url 엔드포인트 구현
   - POST /v1/vlogs 엔드포인트 구현 (Firestore 저장)

2. services/upload_service.dart
   - 백엔드에 Pre-signed URL 요청 (dio 패키지)
   - S3에 직접 PUT 업로드 (진행률 스트림)
   - Firestore에 메타데이터 저장
   - docs/05_db_schema.md vlogs 컬렉션 구조 그대로 사용

3. services/gps_indexer.dart (업로드 전처리용)
   - GPS 트랙을 500개 단위 청크로 분할
   - docs/05_db_schema.md gpsTracks 서브컬렉션 구조로 저장

4. screens/camera/upload_screen.dart
   - 촬영 완료 후 자동 진입
   - 썸네일 미리보기 (영상 첫 프레임 자동 추출)
   - 제목 입력 (필수), 설명 입력 (선택)
   - 공개 범위 선택 (전체공개 / 링크공유 / 비공개)
   - GPS 트랙 요약 표시 (좌표 수, 이동거리)
   - 업로드 진행률 바
   - 업로드 완료 후 홈으로 이동

API Base URL은 .env의 API_BASE_URL 사용해줘.
```

### 검증 방법

```bash
# 백엔드 서버 실행
cd server && node index.js

# 앱 실행 (별도 터미널)
flutter run -d android
```

**통과 기준**
- [ ] 업로드 화면에서 제목 입력 후 [업로드] 버튼 동작
- [ ] 업로드 진행률 바 표시
- [ ] AWS S3 콘솔에서 영상 파일 업로드 확인
- [ ] Firebase Console → Firestore → vlogs 컬렉션 문서 생성 확인
- [ ] gpsTracks 서브컬렉션에 GPS 데이터 저장 확인
- [ ] 업로드 완료 후 홈 화면으로 이동

---

## 🚀 마일스톤 6 — 브이로그 플레이어 (핵심)

### Claude Code 지시문

```
다음 문서를 읽고 작업해줘:
- docs/02_scenario.md  (시나리오 4 — 브이로그 시청)
- docs/03_wireframe.md (화면 6 — 플레이어)
- docs/04_api_spec.md  (2.2 브이로그 상세 조회, 3.1 장소 조회)
- docs/08_gps_algorithm.md (전체 — 가장 중요)

[마일스톤 6] 브이로그 플레이어(영상-지도 동기화)를 구현해줘.
이 기능이 MapVlog의 핵심이니 꼼꼼하게 구현해줘.

작업 목록:
1. services/gps_indexer.dart (재생용)
   - docs/08_gps_algorithm.md의 GpsIndexer 클래스 그대로 구현
   - getPosition(double t) → LatLng 반환 (선형 보간 적용)
   - totalDistance 계산 (Haversine 공식)
   - isStationary(double t) → 10초 이상 공백 구간 처리

2. screens/vlog/vlog_player_screen.dart
   - 상단: video_player 영상 플레이어 (16:9 비율)
   - 진행바 + 재생/일시정지 + 시간 표시
   - 중간: 현재 위치 장소 정보 카드 (Places API 연동)
   - 하단: Google Maps (이동 경로 폴리라인 + 현재 위치 마커)

3. 영상-지도 동기화 로직
   - video_player의 position 변화 감지 (addListener)
   - 0.5초마다 GpsIndexer.getPosition() 호출
   - Google Maps 마커 실시간 이동
   - 지도 카메라 마커 따라가기 (animateCamera)
   - isStationary() true이면 마커 정지

4. 이동 경로 폴리라인
   - 전체 GPS 트랙을 파란색(#1A73E8) 폴리라인으로 표시
   - 두께 4dp
   - 지나간 구간: 진한 파랑 / 아직 안 간 구간: 연한 파랑

5. 장소 정보 팝업
   - 현재 GPS 좌표로 Places API 조회 (30초마다 갱신)
   - 장소명, 카테고리 표시

6. 가로 모드 레이아웃
   - 세로: 영상(상단) + 지도(하단) 분할
   - 가로: 영상(좌) + 지도(우) 분할
   - OrientationBuilder로 자동 전환

7. 지도 마커 클릭 → 해당 타임코드로 영상 이동
   - GPS 트랙 상의 마커를 클릭하면 그 시간대로 seekTo

Firestore gpsTracks 청크 로드는 업로드 시 저장한 구조 그대로 사용해줘.
```

### 검증 방법

```bash
flutter run -d chrome    # 웹에서 기본 동작 확인
flutter run -d android   # 실기기에서 성능 확인
```

**통과 기준**
- [ ] 영상 재생 시 지도 마커가 실시간으로 이동
- [ ] 이동 경로 폴리라인이 전체 경로로 표시
- [ ] 지나간 구간 / 안 간 구간 색상 구분
- [ ] 장소 정보 카드 표시 (Places API 응답)
- [ ] 가로 모드 전환 시 좌우 분할 레이아웃 자동 적용
- [ ] 지도 마커 클릭 → 영상이 해당 시간으로 이동
- [ ] GPS 공백 구간에서 마커가 멈춤 (정지 처리)
- [ ] 영상 30초 이상 재생해도 끊김 없이 동기화 유지

> **성능 기준**: 지도 마커 업데이트가 영상 재생보다 눈에 띄게 느리면 안 됩니다.

---

## 🚀 마일스톤 7 — 포토맵 갤러리 + 프로필 + 공유

### Claude Code 지시문

```
다음 문서를 읽고 작업해줘:
- docs/02_scenario.md  (시나리오 5, 6 — 갤러리, 공유)
- docs/03_wireframe.md (화면 7, 화면 8)
- docs/04_api_spec.md  (4.1 좋아요)

[마일스톤 7] 포토맵 갤러리, 프로필, 공유 기능을 구현해줘.

작업 목록:
1. screens/gallery/gallery_screen.dart
   - 상단 30%: Google Maps (사진 마커 표시)
   - 하단 70%: 사진 그리드 (3열)
   - 사진 마커: 지도 위에 미니 썸네일 표시
   - 사진 마커 클릭 → 사진 상세 팝업 (사진 + 촬영 일시 + 위치명)
   - 그리드 사진 클릭 → 지도 해당 위치로 이동 + 마커 하이라이트

2. screens/profile/profile_screen.dart
   - 프로필 사진 + 닉네임 + 소개글
   - 브이로그 수 / 팔로워 / 팔로잉 카운트
   - 탭: 내 브이로그 그리드 / 내 사진 그리드
   - 로그아웃 버튼 (설정 아이콘)

3. 좋아요 기능
   - VlogCard에 하트 버튼 추가
   - Firestore likes 컬렉션 토글 저장 (docs/05_db_schema.md 기준)
   - likeCount 실시간 업데이트

4. 공유 기능
   - 플레이어 화면 [공유] 버튼
   - share_plus 패키지로 시스템 공유 시트 표시
   - 공유 URL: https://mapvlog.vercel.app/v/{vlogId}

5. 홈 피드 실제 데이터 연결
   - 더미 데이터 → Firestore vlogs 컬렉션 실제 데이터로 교체
   - 최신순 정렬, 무한 스크롤 (페이지네이션)
```

### 검증 방법

```bash
flutter run -d chrome
flutter run -d android
```

**통과 기준**
- [ ] 갤러리 화면에서 사진 마커가 지도에 표시
- [ ] 사진 마커 클릭 → 상세 팝업 표시
- [ ] 그리드 사진 클릭 → 지도 해당 위치로 이동
- [ ] 프로필 화면에 내 브이로그 목록 표시
- [ ] 하트 버튼 클릭 → 좋아요 수 즉시 변경
- [ ] [공유] 버튼 클릭 → 공유 URL 복사/시스템 공유 시트 표시
- [ ] 홈 피드에 실제 업로드한 브이로그 표시
- [ ] 스크롤 하단 도달 시 추가 데이터 로드

---

## 🏁 Phase 1 MVP 최종 검증

모든 마일스톤 완료 후 아래 시나리오를 처음부터 끝까지 테스트합니다.

### 전체 흐름 테스트

```
1. 앱 최초 실행 → 스플래시 → 온보딩 → 로그인
2. Google 계정으로 로그인
3. 홈 화면 진입 확인
4. GPS 연동 동영상 촬영 (30초 이상)
5. 촬영 완료 후 업로드 화면 진입
6. 제목 입력 → [업로드] 버튼
7. 업로드 완료 후 홈 피드에서 내 브이로그 확인
8. 브이로그 클릭 → 플레이어 재생
9. 영상 재생 중 지도 마커 이동 확인 (핵심!)
10. 공유 버튼 → 링크 복사 → 웹 브라우저에서 접속 확인
```

### 최종 체크리스트

**기능**
- [ ] 로그인 / 로그아웃 정상 동작
- [ ] GPS 연동 촬영 → 업로드 전체 흐름
- [ ] 영상-지도 동기화 플레이어 (핵심 기능)
- [ ] 포토맵 갤러리
- [ ] 공유 링크 웹 뷰어

**성능**
- [ ] 지도 마커 동기화 지연 1초 이하
- [ ] 업로드 진행률 바 정상 동작
- [ ] 홈 피드 스크롤 버벅임 없음

**안정성**
- [ ] GPS 없는 환경에서 앱 크래시 없음
- [ ] 네트워크 끊김 시 앱 크래시 없음
- [ ] 업로드 실패 시 재시도 버튼 표시

**배포**
- [ ] `flutter build web --release` 오류 없음
- [ ] Vercel 배포 후 웹 브라우저에서 정상 접근
- [ ] GitHub main 브랜치에 최종 코드 push 완료

---

## 💡 Claude Code 협업 팁

**잘 동작하는 지시 패턴**

- 관련 문서를 먼저 명시하고 → 구체적인 작업 목록 제시
- 파일명과 경로를 명확하게 지정
- "docs/08_gps_algorithm.md의 GpsIndexer 클래스 그대로 구현해줘"처럼 문서와 연결

**잘 안 되는 패턴**

- "앱 전체 다 만들어줘" → 품질 저하
- 문서 없이 "예쁘게 만들어줘" → 방향 없음
- 한 번에 너무 많은 화면 요청 → 중간에 맥락 손실

**오류 발생 시**

1. 오류 메시지를 그대로 Claude Code에 붙여넣기
2. "이 오류 수정해줘"라고 지시
3. `flutter analyze` 출력 결과도 함께 붙여넣기

**실기기 테스트 우선**

GPS, 카메라, 위치 기능은 Chrome 에뮬레이터로 완전히 테스트 불가합니다.
마일스톤 4부터는 반드시 Android 실기기 또는 에뮬레이터로 확인하세요.

---

*최종 수정: 2026-04-15*
