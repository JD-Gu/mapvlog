# 10. Claude Code 협업 가이드

> PinFlick은 Phase 1 MVP + 소셜·위치공유·FCM·체크인이 **이미 출시·운영 중**입니다.
> 이전의 "마일스톤 1~7 단계별 빌드 계획"은 완료되어 폐기했습니다.
> 이 문서는 **현재 운영 중인 앱을 Claude Code로 이어서 개발·배포하는 방식**을 정리합니다.
> 프로젝트 전반은 루트 `CLAUDE.md` 가 단일 기준입니다.

---

## 1. 작업 사이클 (현재 운영 방식)

기능/수정 요청은 보통 아래 한 사이클로 처리됩니다.

```
요청 → 관련 코드 탐색·수정 → flutter analyze
   → 버전 3곳 올리기 → 웹 빌드(+killswitch SW) → APK 빌드
   → build/web/downloads 로 APK 복사 → firebase deploy → git commit
```

- **버전 3곳 동기화 필수**: `pubspec.yaml`(`version: X.Y.Z+B`) · `lib/utils/constants.dart`(`kAppVersion`/`kAppBuildNumber`) · `web/version.json`(`version`/`build`/`notes`).
- `web/version.json`의 `notes` 에 사용자용 업데이트 내역을 적으면, 실행 중 앱에 OTA 갱신 배너로 노출됩니다.

### 표준 배포 명령
```bash
flutter analyze
flutter build web --release --pwa-strategy=none
cp tools/killswitch_sw.js build/web/flutter_service_worker.js
flutter build apk --release
cp build/app/outputs/flutter-apk/app-release.apk build/web/downloads/pinflick.apk
firebase deploy --only hosting          # + firestore:rules / functions (변경 시)
```

---

## 2. 잘 동작하는 요청 패턴

- **구체적 단일 과제**: "체크인 수정 UI를 등록과 같게", "다크모드에서 좋아요 색이 안 보여" 등 스크린샷·증상과 함께.
- **오류는 그대로 전달**: 메시지/로그를 붙여넣고 "이거 고쳐줘".
- **파일/기능 기준 명시**: "live_map의 친구 마커 앵커를 꼭지점으로".

피해야 할 것: "앱 전체 다 만들어줘"식 광범위 요청(품질 저하), 한 번에 너무 많은 화면 동시 변경.

---

## 3. 자주 건드리는 위치 (빠른 참조)

| 작업 | 주요 파일 |
|------|-----------|
| 하단 탭/FAB/코치마크 | `lib/app.dart` |
| 친구 실시간 지도·마커·프라이버시 | `lib/screens/live_map/live_map_screen.dart` |
| 체크인 등록·수정 | `lib/widgets/check_in_sheet.dart` |
| 브이로그 등록 마법사 / 수정 | `lib/screens/camera/vlog_upload_wizard.dart` / `lib/screens/vlog/vlog_edit_screen.dart` |
| 위치 선택·보정(공용) | `lib/widgets/map_picker_sheet.dart` |
| 피드 카드·소셜 | `lib/widgets/vlog_card.dart`, `comments_sheet.dart` |
| Firestore 모델/쿼리 | `lib/services/firestore_service.dart`, `lib/models/*` |
| 위치/프라이버시/Ping | `lib/services/user_status_service.dart`, `models/user_status.dart` |
| FCM 토큰/핸들러 | `lib/services/push_service.dart` |
| 푸시 발송·만료정리(서버) | `functions/index.js` |
| 색상·버전·VAPID | `lib/utils/constants.dart` |
| 보안 규칙/인덱스 | `firestore.rules`, `firestore.indexes.json` |

---

## 4. 주의 (반복적으로 중요한 것)

- **색상은 `colorScheme` 우선** — 고정 `AppColors.textPrimary` 류를 텍스트/아이콘에 쓰면 다크모드에서 안 보임.
- **공용 컴포넌트 재사용** — 등록/수정 등 유사 UI는 위젯 추출(`CheckInSheet`, `MapPickerSheet` 등).
- **역지오코딩은 `GeocodingService`(웹 동작) 우선**, 모바일만 기기 Geocoder fallback.
- **시트/스와이퍼 내 GoogleMap** 은 `EagerGestureRecognizer` 로 제스처 우선 점유.
- **Cloud Functions 변경** 후엔 `firebase deploy --only functions` (Blaze 필요).
- **규칙 변경**은 배포 즉시 모든 클라이언트에 적용되므로 신중히.

---

## 5. 콘솔에서 사람이 해야 하는 것 (Claude가 못 함)

- Firebase **Blaze 플랜** 결제수단 (Cloud Functions/FCM 발송).
- 웹 FCM **VAPID 키 생성**(콘솔 → Cloud Messaging) → `kWebVapidKey` 에 입력.
- Google Maps API 키 (`.env`), OAuth 동의화면 등.

---

*최종 수정: 2026-06 (PinFlick 기준)*
