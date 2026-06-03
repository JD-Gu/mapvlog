// PinFlick — FCM 웹 푸시 서비스워커
//
// 웹(PWA)에서 백그라운드/탭 비활성 상태일 때 들어오는 FCM 메시지를
// 시스템 알림으로 표시한다. Cloud Functions 는 웹 토큰에 "data-only"
// 페이로드를 보내고, 표시는 이 SW 의 onBackgroundMessage 가 담당한다.
//
// ⚠️ killswitch SW(flutter_service_worker.js)와는 다른 파일/역할이므로 공존 가능.

/* eslint-disable no-undef */
importScripts(
  'https://www.gstatic.com/firebasejs/10.14.1/firebase-app-compat.js');
importScripts(
  'https://www.gstatic.com/firebasejs/10.14.1/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'AIzaSyAS4uoCzU7LWKrJpz5-ZWIVoCnyQVczKNg',
  authDomain: 'pinflick.web.app',
  projectId: 'mapvlog-1f06d',
  storageBucket: 'mapvlog-1f06d.firebasestorage.app',
  messagingSenderId: '82352854112',
  appId: '1:82352854112:web:82c75c80da1d5343b85f05',
});

const messaging = firebase.messaging();

// 백그라운드 메시지 → 시스템 알림 표시 (data-only 페이로드 기준)
messaging.onBackgroundMessage(function (payload) {
  const d = payload.data || {};
  const title = d.title || '핀플릭 알림';
  const options = {
    body: d.body || '',
    icon: '/icons/Icon-192.png',
    badge: '/icons/Icon-192.png',
    tag: d.tag || 'pinflick',
    data: d, // notificationclick 에서 사용
  };
  return self.registration.showNotification(title, options);
});

// 알림 클릭 → 앱 탭 포커스 / 없으면 새 창
self.addEventListener('notificationclick', function (event) {
  event.notification.close();
  const data = event.notification.data || {};
  let path = '/';
  if (data.type === 'comment' && data.vlogId) {
    path = '/#/vlog/' + data.vlogId;
  }
  event.waitUntil(
    clients
      .matchAll({ type: 'window', includeUncontrolled: true })
      .then(function (clientList) {
        for (const client of clientList) {
          if ('focus' in client) return client.focus();
        }
        if (clients.openWindow) return clients.openWindow(path);
      })
  );
});
