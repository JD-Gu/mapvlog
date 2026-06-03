# 📍 PinFlick

> 친구의 위치로 핀(Pin), 친구의 일상을 플릭(Flick)

친구의 **실시간 위치를 지도에서 공유**하고, 위치 기반 **브이로그·체크인**을 남기는 소셜 위치 플랫폼입니다.
Flutter 한 코드베이스로 **Android · Web(PWA)** 를 지원하며, 백엔드는 **Firebase 전용**입니다.

🔗 **웹앱**: https://pinflick.web.app

---

## ✨ 주요 기능

- **친구 실시간 지도** — 친구 위치를 지도에 표시. 프라이버시 3모드: 💖 베프(정확) · 🙈 부끄럼(대략) · 🥷 잠수(숨김). 친구별 개별 설정·그룹·절전 모드.
- **체크인** — 위치 + 이모지 + 한 줄 메시지. 표시 시간(1~24시간) 후 자동 만료·삭제.
- **브이로그** — 멀티 사진/영상 등록 마법사, 영상-지도 GPS 동기화 플레이어.
- **소셜** — 피드, 댓글·답글·멘션, 좋아요, 저장, 리액션, 친구(검색·QR).
- **푸시 알림(FCM)** — 호출·친구요청·댓글.
- **호출(Ping)** — 친구를 콕 찔러 위치 확인 요청.

---

## 🛠 기술 스택

| 영역 | 사용 기술 |
|------|-----------|
| 앱 | Flutter 3.41.x (Dart) · Android / Web(PWA) |
| 지도 | Google Maps |
| 인증 | Firebase Auth (Google 전용) |
| DB / 스토리지 | Cloud Firestore · Firebase Storage |
| 서버리스 | Cloud Functions (FCM 발송, 만료 정리) |
| 배포 | Firebase Hosting · Android APK 베타 |
| 상태관리 | Provider |

---

## 🚀 실행

```bash
flutter pub get
flutter run -d chrome      # 웹 개발
flutter run -d android     # Android
```

`.env` 에 `GOOGLE_MAPS_API_KEY` 가 필요하고, Firebase 설정 파일(`google-services.json`,
`lib/firebase_options.dart`)이 있어야 합니다.

## 📦 빌드 & 배포

```bash
flutter build web --release --pwa-strategy=none
cp tools/killswitch_sw.js build/web/flutter_service_worker.js
flutter build apk --release
cp build/app/outputs/flutter-apk/app-release.apk build/web/downloads/pinflick.apk
firebase deploy --only hosting
```

> 배포 전 `pubspec.yaml` · `lib/utils/constants.dart` · `web/version.json` 의 버전 3곳을 함께 올립니다.
> 자세한 개발 지침은 [`CLAUDE.md`](./CLAUDE.md), 설계 문서는 [`docs/`](./docs) 참고.

---

## 📁 구조 요약

```
lib/
├── screens/    # home, live_map, camera(마법사), vlog, gallery, friends, profile, auth ...
├── widgets/    # vlog_card, check_in_sheet, comments_sheet, map_picker_sheet ...
├── models/     # vlog, friendship, friend_group, user_status, comment ...
├── services/   # firestore, friend, user_status, push(FCM), geocoding ...
└── utils/      # constants(버전·색상), marker_emojis ...
functions/      # Cloud Functions (FCM + 만료 체크인 정리)
```

---

## 👤 개발

1인 개발 (구자덕) · Claude Code 협업. 현재 **BETA** 운영 중.
