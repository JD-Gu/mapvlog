// PinFlick — 레거시 Service Worker 자폭(killswitch) 스크립트
//
// 이전 버전(PWA SW 사용 시절)에서 등록된 Flutter SW 가 신규 빌드를 캐시로
// 가로채는 문제를 영구 해결한다.
//
// 동작:
//   1) 기존 SW 의 스크립트 URL(/flutter_service_worker.js)에 이 파일이 배포됨.
//   2) 브라우저는 SW 업데이트 체크 시 byte-different 를 감지 → 이 SW 설치.
//   3) activate 시점에 모든 Cache Storage 삭제 + 자기 자신 unregister + 클라이언트 reload.
//   4) 이후 이 앱은 --pwa-strategy=none 빌드라 더 이상 SW 를 등록하지 않음.

self.addEventListener('install', function (event) {
  // 대기 없이 즉시 활성화
  self.skipWaiting();
});

self.addEventListener('activate', function (event) {
  event.waitUntil(
    (async function () {
      try {
        // 1) 모든 캐시 삭제
        const keys = await caches.keys();
        await Promise.all(keys.map(function (k) { return caches.delete(k); }));
      } catch (e) {}

      try {
        // 2) 자기 자신 등록 해제
        await self.registration.unregister();
      } catch (e) {}

      try {
        // 3) 제어 중인 모든 탭을 새로고침 → SW 없는 새 버전 로드
        const clientList = await self.clients.matchAll({ type: 'window' });
        clientList.forEach(function (client) {
          try {
            client.navigate(client.url);
          } catch (e) {}
        });
      } catch (e) {}
    })()
  );
});

// 네트워크 우선 — 혹시 fetch 이벤트가 와도 캐시를 쓰지 않고 항상 네트워크로
self.addEventListener('fetch', function (event) {
  // passthrough: 기본 네트워크 동작 (캐시 미사용)
});
