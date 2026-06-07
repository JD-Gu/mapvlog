/**
 * PinFlick — FCM 푸시 발송 Cloud Functions (2nd gen, Firestore 트리거)
 *
 * 트리거:
 *   1) users/{uid}/pings/{pingId}          → 호출(ping) 푸시
 *   2) users/{uid}/friends/{friendUid}     → 친구 요청(incoming) 푸시
 *   3) vlogs/{vlogId}/comments/{commentId} → 댓글/답글 푸시
 *
 * 토큰 위치: users/{uid}/fcmTokens/{token} { platform, updatedAt }
 *   - platform === 'web'  → data-only (firebase-messaging-sw.js 가 표시)
 *   - 그 외(android 등)    → notification + data (시스템 트레이 자동 표시)
 */

const {onDocumentCreated} = require("firebase-functions/v2/firestore");
const {onSchedule} = require("firebase-functions/v2/scheduler");
const {setGlobalOptions} = require("firebase-functions/v2");
const logger = require("firebase-functions/logger");
const admin = require("firebase-admin");

admin.initializeApp();
setGlobalOptions({region: "asia-northeast3", maxInstances: 10});

const db = admin.firestore();
const messaging = admin.messaging();

/** users/{uid}/fcmTokens 조회 → [{token, platform}] */
async function getTokenDocs(uid) {
  const snap = await db
      .collection("users").doc(uid)
      .collection("fcmTokens").get();
  return snap.docs.map((d) => ({
    token: d.id,
    platform: (d.data().platform || ""),
  }));
}

/**
 * 한 사용자에게 푸시 발송 + 무효 토큰 정리
 * @param {string} uid 수신자 UID
 * @param {{type:string,title:string,body:string,emoji?:string,vlogId?:string}} p
 */
async function sendToUser(uid, p) {
  if (!uid) return;
  const tokenDocs = await getTokenDocs(uid);
  if (tokenDocs.length === 0) return;

  const data = {
    type: p.type || "",
    title: p.title || "",
    body: p.body || "",
    emoji: p.emoji || "",
    vlogId: p.vlogId || "",
  };

  const messages = tokenDocs.map(({token, platform}) => {
    if (platform === "web") {
      // 웹: data-only → SW onBackgroundMessage 가 표시 (중복 방지)
      return {token, data};
    }
    // Android 등: notification + data → 트레이 자동 표시
    return {
      token,
      notification: {title: data.title, body: data.body},
      data,
      android: {priority: "high"},
    };
  });

  let resp;
  try {
    resp = await messaging.sendEach(messages);
  } catch (e) {
    logger.error("sendEach 실패", e);
    return;
  }

  // 무효 토큰 정리
  const deletions = [];
  resp.responses.forEach((r, i) => {
    if (r.success) return;
    const code = r.error && r.error.code;
    if (
      code === "messaging/registration-token-not-registered" ||
      code === "messaging/invalid-registration-token" ||
      code === "messaging/invalid-argument"
    ) {
      deletions.push(
          db.collection("users").doc(uid)
              .collection("fcmTokens").doc(tokenDocs[i].token)
              .delete().catch(() => {}),
      );
    }
  });
  await Promise.all(deletions);
  logger.info(
      `push→${uid} type=${data.type} sent=${resp.successCount}/${messages.length}`);
}

// ── 1) 호출(Ping) ────────────────────────────────────────────────────────────
exports.onPingCreated = onDocumentCreated(
    "users/{uid}/pings/{pingId}",
    async (event) => {
      const uid = event.params.uid;
      const ping = event.data && event.data.data();
      if (!ping) return;
      const fromName = ping.fromName || "친구";
      const emoji = ping.emoji || "📣";
      await sendToUser(uid, {
        type: "ping",
        title: `${emoji} ${fromName}님의 호출`,
        body: ping.message || "지금 어디야?",
        emoji,
      });
    },
);

// ── 2) 친구 요청 ──────────────────────────────────────────────────────────────
exports.onFriendDocCreated = onDocumentCreated(
    "users/{uid}/friends/{friendUid}",
    async (event) => {
      const uid = event.params.uid;
      const f = event.data && event.data.data();
      // incoming(= 내가 받은 요청)일 때만 알림
      if (!f || f.status !== "incoming") return;
      const name = f.displayName || "누군가";
      await sendToUser(uid, {
        type: "friend_request",
        title: "👋 새 친구 요청",
        body: `${name}님이 친구 요청을 보냈어요`,
        emoji: "👋",
      });
    },
);

// ── 3) 댓글/답글 ──────────────────────────────────────────────────────────────
exports.onCommentCreated = onDocumentCreated(
    "vlogs/{vlogId}/comments/{commentId}",
    async (event) => {
      const vlogId = event.params.vlogId;
      const c = event.data && event.data.data();
      if (!c) return;

      const commenter = c.authorId;
      const commenterName = c.authorName || "누군가";
      const content = c.content || "";
      const isReply = !!c.parentId;

      const vlogSnap = await db.collection("vlogs").doc(vlogId).get();
      if (!vlogSnap.exists) return;
      const vlog = vlogSnap.data();

      const recipients = new Set();

      // 답글이면 같은 스레드(부모 댓글) 참여자 전원에게 알림
      if (c.parentId) {
        // 1) 부모(최상위) 댓글 작성자
        const parentSnap = await db
            .collection("vlogs").doc(vlogId)
            .collection("comments").doc(c.parentId).get();
        if (parentSnap.exists) {
          const pa = parentSnap.data().authorId;
          if (pa) recipients.add(pa);
        }
        // 2) 같은 부모를 가진 다른 답글 작성자들 (스레드 대화 참여자)
        const siblings = await db
            .collection("vlogs").doc(vlogId)
            .collection("comments")
            .where("parentId", "==", c.parentId)
            .get();
        siblings.forEach((d) => {
          const a = d.data().authorId;
          if (a) recipients.add(a);
        });
      }
      // vlog 작성자 (항상)
      if (vlog.authorId) recipients.add(vlog.authorId);
      // 본인 제외
      recipients.delete(commenter);

      await Promise.all([...recipients].map((uid) => sendToUser(uid, {
        type: "comment",
        title: isReply ?
          `💬 ${commenterName}님의 답글` :
          `💬 ${commenterName}님의 댓글`,
        body: content,
        emoji: "💬",
        vlogId,
      })));
    },
);

// ── 4) 만료된 체크인 자동 삭제 (매시간) ──────────────────────────────────────
// expiresAt 이 지난 체크인 vlog 를 하위 댓글·좋아요·저장과 함께 삭제.
exports.cleanupExpiredCheckins = onSchedule(
    "every 60 minutes",
    async () => {
      const now = admin.firestore.Timestamp.now();
      const snap = await db
          .collection("vlogs")
          .where("isCheckIn", "==", true)
          .where("expiresAt", "<", now)
          .limit(400)
          .get();
      if (snap.empty) {
        logger.info("cleanupExpiredCheckins: 만료 체크인 없음");
        return;
      }
      let n = 0;
      for (const doc of snap.docs) {
        try {
          // recursiveDelete: 하위 comments/likes/saves 까지 정리
          await db.recursiveDelete(doc.ref);
          n++;
        } catch (e) {
          logger.error("recursiveDelete 실패 " + doc.id, e);
        }
      }
      logger.info("cleanupExpiredCheckins 삭제=" + n);
    },
);

// ── 5) 백그라운드 위치 핑 (앱 종료 상태에서도 위치 갱신 유도) ──────────────────
// bgLocationEnabled=true 사용자 중 liveLocation 이 오래된(>3분) 사람에게
// data-only 고우선순위 FCM 발송 → 앱 백그라운드 핸들러가 깨어나 위치를 기록.
// (포그라운드/앱-생존 중인 사용자는 이미 최근 갱신이라 스킵 → 발송량 절약)
exports.bgLocationPing = onSchedule(
    "every 2 minutes",
    async () => {
      const snap = await db
          .collection("users")
          .where("bgLocationEnabled", "==", true)
          .get();
      if (snap.empty) return;
      const now = Date.now();
      const staleMs = 3 * 60 * 1000; // 3분 이상 안 올라온 사람만
      let sent = 0;
      for (const doc of snap.docs) {
        const d = doc.data();
        const last = d.liveLocation && d.liveLocation.updatedAt;
        const lastMs = last && last.toMillis ? last.toMillis() : 0;
        if (now - lastMs < staleMs) continue; // 최근 갱신됨 → 스킵
        const uid = doc.id;
        const tokenDocs = await getTokenDocs(uid);
        const tokens = tokenDocs
            .filter((t) => t.platform !== "web") // 웹은 백그라운드 위치 불가
            .map((t) => t.token);
        if (tokens.length === 0) continue;
        try {
          await messaging.sendEachForMulticast({
            tokens,
            data: {type: "loc_ping", uid},
            android: {priority: "high"},
          });
          sent++;
        } catch (e) {
          logger.error("loc_ping 발송 실패 " + uid, e);
        }
      }
      logger.info("bgLocationPing sent=" + sent);
    },
);

// ── 6) 종료된 이벤트 자동 숨김 (매시간) ──────────────────────────────────────
// status=='active' 이벤트 중 endAt 이 지난 것을 status='ended' 로 변경(보존).
// (active 만 조회 → 단일 필드 인덱스, 복합 불필요)
exports.cleanupEndedEvents = onSchedule(
    "every 60 minutes",
    async () => {
      const now = admin.firestore.Timestamp.now();
      const snap = await db
          .collection("events")
          .where("status", "==", "active")
          .get();
      if (snap.empty) return;
      let n = 0;
      const batch = db.batch();
      snap.docs.forEach((doc) => {
        const endAt = doc.data().endAt;
        if (endAt && endAt.toMillis && endAt.toMillis() < now.toMillis()) {
          batch.update(doc.ref, {status: "ended", updatedAt: now});
          n++;
        }
      });
      if (n > 0) await batch.commit();
      logger.info("cleanupEndedEvents ended=" + n);
    },
);
