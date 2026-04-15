# 09. 개발 로드맵

## 개요

MapVlog 1인 개발(구자덕 + Claude AI) 기준 단계별 개발 계획입니다.
Phase 1 MVP 완성 후 시장 반응을 보며 Phase 2로 확장합니다.

---

## 전체 일정 요약

| Phase | 기간 | 목표 |
|-------|------|------|
| Phase 0 | 완료 ✅ | 개발환경 세팅 + 기획·설계 문서 |
| Phase 1 | 1~6개월 | MVP 출시 (핵심 기능 완성) |
| Phase 2 | 7~12개월 | 소셜 기능 + 확장 |
| Phase 3 | 12개월 이후 | 수익화 + 고도화 |

---

## Phase 0 — 준비 (완료 ✅)

| 항목 | 상태 |
|------|------|
| Flutter 개발환경 세팅 | ✅ |
| VSCode + Claude Code 연동 | ✅ |
| GitHub 레포 생성 | ✅ |
| CLAUDE.md 작성 | ✅ |
| docs/ 기획·설계 문서 전체 작성 | ✅ |

---

## Phase 1 — MVP (1~6개월)

### 마일스톤 1 — 프로젝트 기반 설정 (1~2주)

| 작업 | 담당 | 설명 |
|------|------|------|
| pubspec.yaml 패키지 설정 | Claude Code | 전체 의존성 추가 |
| Firebase 연동 | 대표님 + Claude Code | google-services.json 설정, FlutterFire 초기화 |
| Google Maps API 키 발급 | 대표님 | 각 플랫폼 적용 |
| AWS S3 버킷 생성 | 대표님 | CloudFront 연동 |
| 기본 앱 구조 생성 | Claude Code | main.dart, app.dart, 라우팅, ThemeData |
| GitHub push + Vercel 연동 | 대표님 | main 브랜치 자동 배포 |

### 마일스톤 2 — 인증 화면 (2~3주)

| 작업 | 담당 | 설명 |
|------|------|------|
| 스플래시 화면 | Claude Code | 로고 + 애니메이션 |
| 온보딩 슬라이드 | Claude Code | 3페이지 슬라이드 |
| 소셜 로그인 화면 | Claude Code | Google / Apple / 카카오 버튼 |
| Firebase Auth 연동 | Claude Code | 로그인/로그아웃 처리 |
| 사용자 프로필 Firestore 저장 | Claude Code | users 컬렉션 생성 |

### 마일스톤 3 — 지도 + 홈 화면 (3~4주)

| 작업 | 담당 | 설명 |
|------|------|------|
| 하단 탭바 네비게이션 | Claude Code | 5개 탭 구성 |
| 홈 피드 화면 | Claude Code | VlogCard 컴포넌트, 그리드 레이아웃 |
| 지도 화면 | Claude Code | Google Maps 전체화면, 마커 표시 |
| 현재 위치 이동 | Claude Code | geolocator 연동 |
| Places API 연동 | Claude Code | 좌표 → 장소명 변환 |

### 마일스톤 4 — GPS 연동 촬영 (4~5주)

| 작업 | 담당 | 설명 |
|------|------|------|
| 촬영 화면 UI | Claude Code | 카메라 프리뷰, 버튼 |
| GPS 1초 수집 서비스 | Claude Code | GpsTracker 서비스 클래스 |
| 동영상 촬영 + GPS 기록 | Claude Code | camera 패키지 + GPS 타임스탬프 JSON |
| 사진 촬영 + EXIF 삽입 | Claude Code | image_picker + exif 패키지 |
| GPS 이상치 필터링 | Claude Code | 08_gps_algorithm.md 기준 |
| 로컬 저장 (sqflite) | Claude Code | 촬영 완료 데이터 임시 보관 |

### 마일스톤 5 — 업로드 (5주)

| 작업 | 담당 | 설명 |
|------|------|------|
| 백엔드 API 서버 구축 | Claude Code | Node.js + Express 기본 구조 |
| Pre-signed URL 발급 API | Claude Code | AWS S3 업로드 연동 |
| 업로드 화면 UI | Claude Code | 제목, 설명, 공개 범위 |
| S3 영상 업로드 | Claude Code | 진행률 표시, 재시도 처리 |
| Firestore 메타데이터 저장 | Claude Code | vlogs 컬렉션 저장 |

### 마일스톤 6 — 브이로그 플레이어 (5~6주) ← 핵심

| 작업 | 담당 | 설명 |
|------|------|------|
| 영상 플레이어 UI | Claude Code | video_player 연동, 컨트롤바 |
| GPS 인덱서 구현 | Claude Code | 08_gps_algorithm.md GpsIndexer 클래스 |
| 영상-지도 동기화 | Claude Code | 타임코드 → 마커 실시간 연동 |
| 이동 경로 폴리라인 | Claude Code | 전체 GPS 트랙 표시 |
| 장소 정보 팝업 | Claude Code | Places API + PlaceInfoCard 위젯 |
| 가로 모드 분할 레이아웃 | Claude Code | 영상 + 지도 좌우 분할 |

### 마일스톤 7 — 포토맵 갤러리 + 프로필 (6주)

| 작업 | 담당 | 설명 |
|------|------|------|
| 포토맵 갤러리 화면 | Claude Code | 지도 + 사진 그리드 혼합 |
| 사진 마커 (미니 썸네일) | Claude Code | 지도 위 사진 마커 |
| 프로필 화면 | Claude Code | 내 브이로그 목록 |
| 공유 링크 생성 | Claude Code | Flutter Web 뷰어 연동 |

### Phase 1 완료 기준 (MVP 체크리스트)

- [ ] 로그인/로그아웃 정상 동작
- [ ] GPS 연동 동영상 촬영 및 저장
- [ ] S3 영상 업로드 성공
- [ ] 영상 재생 + 지도 마커 동기화
- [ ] 이동 경로 폴리라인 표시
- [ ] 포토맵 갤러리 동작
- [ ] 공유 링크 웹 뷰어 접근 가능
- [ ] Flutter Web (Vercel) 정상 배포
- [ ] Android 에뮬레이터 정상 실행

---

## Phase 2 — 소셜 + 확장 (7~12개월)

### 주요 기능

| 기능 | 설명 |
|------|------|
| 팔로우/팔로워 | 사용자 간 팔로우 관계 |
| 피드 큐레이션 | 팔로잉 기반 맞춤 피드 |
| 좋아요 / 댓글 | 브이로그 반응 기능 |
| 알림 | 팔로우, 좋아요, 댓글 푸시 알림 |
| 검색 | 키워드, 위치, 해시태그 검색 |
| 해시태그 | 브이로그 태그 분류 |
| 다크모드 | UI 다크모드 지원 |
| 영상 편집 | 간단한 트리밍 기능 |
| iOS 앱스토어 출시 | TestFlight 베타 → 정식 출시 |
| Google Play 출시 | 내부 테스트 → 정식 출시 |

---

## Phase 3 — 수익화 + 고도화 (12개월 이후)

### 주요 방향

| 방향 | 설명 |
|------|------|
| 여행 추천 기능 | 브이로그 기반 여행 코스 자동 생성 |
| 지역 기반 광고 | 장소 정보 연계 로컬 광고 |
| 프리미엄 구독 | 고해상도 저장, 광고 제거, 클라우드 용량 확장 |
| 지도 플랫폼 API 제공 | 외부 서비스에 GPS-영상 동기화 API 공개 |
| 다국어 지원 | 영어, 일본어, 중국어 |
| AI 하이라이트 추출 | AI로 브이로그 핵심 장면 자동 편집 |

---

## 개발 원칙

**문서 우선**: 기능 개발 전 항상 관련 문서(`docs/`)를 최신 상태로 유지합니다.

**기능 단위 브랜치**: 각 마일스톤 작업은 `feature/` 브랜치에서 개발 후 `develop`에 머지합니다.

**Claude Code 협업**: 각 마일스톤 시작 전 관련 `docs/` 문서를 Claude Code에게 참조시키고 구현을 지시합니다.

**실기기 검증 우선**: Claude Code가 코드를 완성하면 대표님이 에뮬레이터 또는 실기기로 직접 확인합니다.

---

*최종 수정: 2026-04-15*
