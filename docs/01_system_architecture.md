# 01. 시스템 아키텍처

## 개요

PinFlick은 **Flutter 단일 코드베이스(Android·Web) + Firebase 백엔드**로만 구성된 서버리스 아키텍처입니다.
별도의 애플리케이션 서버(Node 등)나 외부 스토리지(S3 등)는 사용하지 않습니다.

> 이전 설계의 Node.js/Express + AWS S3 구성은 폐기되었습니다. 모든 백엔드는 Firebase로 통합되었습니다.

---

## 전체 구성도

```
┌──────────────────────────────────────────────┐
│                Client (Flutter)               │
│   Android App        │        Web (PWA)        │
│   - 친구 실시간 지도 / 브이로그 / 체크인 / 피드    │
│   - Provider 상태관리 · google_maps_flutter     │
└───────────────┬───────────────────────────────┘
                │  Firebase SDK (직접 연결)
   ┌────────────┼─────────────┬───────────────┬─────────────┐
   ▼            ▼             ▼               ▼             ▼
┌────────┐ ┌──────────┐ ┌───────────┐ ┌────────────┐ ┌──────────┐
│Firebase│ │Cloud     │ │ Firebase  │ │  Cloud      │ │ Firebase │
│Auth    │ │Firestore │ │ Storage   │ │  Functions  │ │ Hosting  │
│(Google)│ │(DB+실시간)│ │(사진·영상)│ │(FCM/정리)   │ │(웹 배포) │
└────────┘ └──────────┘ └───────────┘ └─────┬───────┘ └──────────┘
                                            │ FCM 발송
                                            ▼
                                      ┌──────────┐
                                      │   FCM    │ → 기기 푸시
                                      └──────────┘
```

---

## 레이어별 역할

### 1. Client (Flutter)
* Android / Web(PWA) 동일 코드베이스.
* Firebase SDK로 Firestore·Auth·Storage·FCM에 **직접** 연결 (중간 API 서버 없음).
* 지도: `google_maps_flutter`, 위치: `geolocator`, 역지오코딩: Nominatim(OSM) HTTP.
* 상태관리: Provider.

### 2. Firebase Auth
* **Google 로그인 전용** (웹 `signInWithPopup`, 모바일 `google_sign_in`).

### 3. Cloud Firestore
* 사용자/친구/그룹/위치, 브이로그/체크인, 댓글/좋아요/저장/리액션, FCM 토큰 저장.
* 실시간 스트림으로 피드·친구 위치·댓글 등 구독.
* 접근 제어는 `firestore.rules`, 복합 인덱스는 `firestore.indexes.json`.

### 4. Firebase Storage
* 사진·영상 원본 저장 (웹 `putData`, 모바일 `putFile`). 영상은 `video_compress`로 압축 후 업로드.

### 5. Cloud Functions (2nd gen · Node 22 · asia-northeast3)
* Firestore 트리거로 **FCM 푸시 발송**(호출·친구요청·댓글) + **만료 체크인 정리**(스케줄).
* Blaze 요금제 필요.

### 6. Firebase Hosting
* Flutter Web 정적 배포 (`pinflick.web.app`). 베타 APK도 `downloads/` 로 함께 제공.

---

## 데이터 흐름

### 친구 위치 공유
```
내 기기 위치 변경 → (프라이버시 모드에 따라 정확/안개/고정 가공)
  → Firestore users/{uid}.location 업데이트
  → 친구 클라이언트가 실시간 스트림으로 수신 → 지도 마커 갱신
```

### 브이로그/체크인 등록
```
사진·영상(또는 위치+메시지) → Storage 업로드(미디어) → Firestore vlogs/{id} 저장
  → 친구 피드·지도에 실시간 노출
```

### 알림(FCM)
```
ping/friend/comment 문서 생성 → Cloud Functions 트리거
  → 수신자 fcmTokens 조회 → FCM 멀티캐스트 → 기기 푸시(웹은 SW가 표시)
```

---

## 웹 캐시 / OTA 갱신 전략

* `--pwa-strategy=none` 으로 빌드하여 Flutter SW를 생성하지 않음.
* 레거시 SW는 `tools/killswitch_sw.js`(자폭 SW)를 `flutter_service_worker.js` 자리에 배포해 캐시를 정리.
* 실행 중 앱은 `version.json` 을 주기적으로 폴링 → `build` 가 올라가면 갱신 배너 표시.
* FCM 웹 푸시는 `web/firebase-messaging-sw.js` 가 담당 (killswitch SW와 별개 파일).

---

## 배포 구성

| 구분 | 플랫폼 | 방식 |
|------|--------|------|
| Web | Firebase Hosting | `firebase deploy --only hosting` |
| Android | APK 베타 (`web/downloads/pinflick.apk`) | `flutter build apk` 후 복사·배포 |
| Functions | Cloud Functions | `firebase deploy --only functions` |
| Rules/Index | Firestore | `firebase deploy --only firestore` |

---

## 보안 고려사항

* Firestore Security Rules로 접근 제어 (예: `saves` 는 `uid` 필드 기반 인가).
* API 키는 `.env`/Firebase 콘솔 관리, 하드코딩 금지.
* FCM 발송은 신뢰된 서버(Cloud Functions)에서만.
* 위치 데이터는 프라이버시 모드(베프/부끄럼/잠수)로 사용자가 공개 수준 직접 제어.

---

*최종 수정: 2026-06 (PinFlick 기준)*
