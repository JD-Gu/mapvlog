# 01. 시스템 아키텍처

## 개요

MapVlog는 GPS 타임스탬프 기반 브이로그 플랫폼으로, Flutter 크로스플랫폼 앱 + Node.js 백엔드 + Firebase + AWS S3 구조로 설계됩니다.

---

## 전체 시스템 구성도

```
┌─────────────────────────────────────────────────────────────┐
│                        Client Layer                         │
│                                                             │
│   ┌──────────────┐   ┌──────────────┐   ┌──────────────┐  │
│   │  Android App │   │   iOS App    │   │  Flutter Web │  │
│   │ (Flutter)    │   │  (Flutter)   │   │  (Vercel)    │  │
│   └──────┬───────┘   └──────┬───────┘   └──────┬───────┘  │
└──────────┼────────────────── ┼─────────────────┼───────────┘
           │                   │                 │
           └───────────────────┼─────────────────┘
                               │ HTTPS / REST API
┌──────────────────────────────▼──────────────────────────────┐
│                       Backend Layer                         │
│                                                             │
│   ┌─────────────────────────────────────────────────────┐  │
│   │           Node.js + Express API Server              │  │
│   │                 (AWS EC2 / NCP)                     │  │
│   │                                                     │  │
│   │  - REST API 엔드포인트 처리                            │  │
│   │  - GPS 데이터 인덱싱 및 보간 처리                       │  │
│   │  - 영상·사진 업로드 Pre-signed URL 발급                 │  │
│   │  - 장소 정보 API 중계 (Google Places / 카카오)          │  │
│   └──────────────┬──────────────┬──────────────────────┘  │
└──────────────────┼──────────────┼───────────────────────────┘
                   │              │
       ┌───────────▼──┐    ┌──────▼───────────┐
       │   Firebase   │    │     AWS S3 +     │
       │  Firestore   │    │   CloudFront     │
       │  Firebase    │    │   CDN            │
       │  Auth        │    │  (영상·사진 저장)  │
       └──────────────┘    └──────────────────┘
```

---

## 레이어별 역할

### 1. Client Layer (Flutter)

| 구분 | 설명 |
|------|------|
| Android / iOS | GPS 연동 촬영, 영상-지도 동기화 플레이어 |
| Flutter Web | 브이로그 공유 뷰어, 반응형 웹 UI |
| 상태관리 | Provider 또는 Riverpod |
| 지도 렌더링 | google_maps_flutter |
| 영상 재생 | video_player |

### 2. Backend Layer (Node.js + Express)

| 역할 | 설명 |
|------|------|
| REST API | 브이로그 CRUD, 사용자 관리 |
| GPS 인덱싱 | 타임코드 ↔ GPS 좌표 변환 알고리즘 |
| 업로드 처리 | AWS S3 Pre-signed URL 발급 |
| 장소 API 중계 | Google Places / 카카오 로컬 API 프록시 |

### 3. Firebase

| 서비스 | 용도 |
|--------|------|
| Firebase Auth | 소셜 로그인 (Google, Apple, Kakao) |
| Cloud Firestore | 브이로그 메타데이터, 사용자 정보, GPS 트랙 |

### 4. AWS S3 + CloudFront

| 역할 | 설명 |
|------|------|
| S3 | 영상 파일, 사진 파일 원본 저장 |
| CloudFront | CDN을 통한 빠른 미디어 스트리밍 |

---

## 데이터 흐름

### 촬영 → 업로드 흐름

```
사용자 촬영
    │
    ▼
Flutter 앱에서 GPS 타임스탬프 JSON 생성
    │
    ▼
백엔드에 Pre-signed URL 요청
    │
    ▼
AWS S3에 직접 영상/사진 업로드
    │
    ▼
Firestore에 메타데이터(GPS 트랙, 장소, 제목 등) 저장
    │
    ▼
업로드 완료 → 브이로그 목록에 노출
```

### 재생 → 지도 동기화 흐름

```
브이로그 선택
    │
    ▼
Firestore에서 GPS 트랙 데이터 로드
    │
    ▼
video_player로 영상 재생 시작
    │
    ▼
현재 타임코드 → GPS 좌표 인덱스 변환 (보간법 적용)
    │
    ▼
google_maps_flutter 마커 실시간 업데이트
    │
    ▼
Places API로 현재 위치 장소 정보 팝업 표시
```

---

## 배포 구성

| 구분 | 플랫폼 | 방식 |
|------|--------|------|
| Flutter Web | Vercel | GitHub 푸시 → 자동 배포 (CI/CD) |
| Android | Google Play Store | flutter build appbundle |
| iOS | App Store | flutter build ipa |
| 백엔드 API | AWS EC2 / NCP | PM2 + Nginx |

---

## 보안 고려사항

- API 키는 `.env`로 관리, `.gitignore` 필수 적용
- Firebase Security Rules로 Firestore 접근 제어
- AWS S3 버킷 퍼블릭 차단, CloudFront 서명 URL 사용
- HTTPS 통신 강제 (HTTP 리다이렉트)
- GPS 데이터는 항상 null 체크 후 처리

---

*최종 수정: 2026-04-15*
