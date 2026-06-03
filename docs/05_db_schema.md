# 05. DB 스키마 (Cloud Firestore)

PinFlick은 Cloud Firestore(NoSQL)를 주 DB로 사용합니다. 아래는 현재 구현 기준 스키마입니다.

> 이전 설계의 `follows`(팔로우), S3 `key`, `gpsTracks` 청크 서브컬렉션 등은 폐기되었습니다.
> 친구 관계는 `users/{uid}/friends`, GPS 트랙은 `vlogs/{id}.gpsTrack`(배열)에 보관합니다.

---

## 컬렉션 개요

```
users/{uid}
  ├── friends/{friendUid}
  ├── friendGroups/{groupId}
  ├── pings/{pingId}
  └── fcmTokens/{token}
vlogs/{vlogId}
  ├── comments/{commentId}
  │     └── likes/{uid}
  ├── likes/{uid}
  ├── saves/{uid}
  └── reactions/{uid_emoji}
config/{configId}
```

---

## 1. users/{uid}

| 필드 | 타입 | 설명 |
|------|------|------|
| uid | string | Firebase Auth UID (문서 ID) |
| displayName / email / photoUrl | string | 프로필 |
| privacyMode | string | `precise`(베프) / `fog`(부끄럼) / `ice`(잠수) — 마스터 위치 공개 모드 |
| status | map | `{emoji, message, ...}` 현재 상태(선택) |
| location | map | `{lat, lng, updatedAt, isMoving, batteryLevel}` (프라이버시 모드에 따라 가공) |
| frozenLocation | map | 잠수(ice) 진입 시 고정된 위치 |
| createdAt / lastSeen | timestamp | |

### users/{uid}/friends/{friendUid}  — 친구 관계 (양방향 doc 쌍)
| 필드 | 타입 | 설명 |
|------|------|------|
| status | string | `pending`(내가 보냄) / `incoming`(받음) / `accepted` |
| relType | string | 그룹 베이스라인: `best`(베프) / `normal`(부끄럼) / `bad`(잠수) |
| individualMode | string | 개별 오버라이드: `precise`(항상 정확) / `ice`(항상 잠수) / `inherit`(그룹 따름) |
| displayName / photoUrl / email | string | 상대 프로필 캐시 |
| frozenLat / frozenLng / frozenAt | — | 잠수/얼음 시 상대 위치 스냅샷 |
| createdAt / acceptedAt | timestamp | |

### users/{uid}/friendGroups/{groupId}  — 커스텀 친구 그룹
`{ name, emoji, mode(GroupMode), memberUids[], createdAt }`

### users/{uid}/pings/{pingId}  — 받은 호출
`{ fromUid, fromName, emoji, message, createdAt }` (최근 1시간 표시)

### users/{uid}/fcmTokens/{token}  — FCM 토큰
`{ platform: 'web'|'android'|..., updatedAt }`

---

## 2. vlogs/{vlogId}  (브이로그 + 체크인)

| 필드 | 타입 | 설명 |
|------|------|------|
| id | string | 문서 ID |
| authorId / authorName / authorPhotoUrl | | 작성자 |
| title / placeName / address | string | 제목 · 장소명 · 도로명주소 |
| lat / lng | number | 대표 위치 |
| videoUrl / thumbnailUrl | string | 영상/썸네일 URL |
| photoUrls | array<string> | 멀티 사진 (없으면 빈 배열) |
| gpsTrack | array | `[{t, lat, lng}, ...]` GPS 타임스탬프 트랙 (영상 동기화용) |
| durationSeconds | number? | 영상 길이 |
| markerEmoji / markerColor | string / int | 카테고리 이모지 + 마커 색 |
| **isCheckIn** | bool | 체크인 여부 (미디어 없이 위치+이모지+메시지) |
| **expiresAt** | timestamp? | 체크인 만료 시각 (지나면 지도 숨김 + 서버 자동 삭제) |
| **visibility** | string | `public` / `groups` / `private` |
| visibleGroupIds / visibleUids | array | groups 모드일 때 공개 대상 |
| likeCount / commentCount / viewCount | number | 카운터 |
| createdAt / updatedAt | timestamp | |

### vlogs/{vlogId}/comments/{commentId}
`{ id, authorId, authorName, authorPhotoUrl?, content, parentId?(답글), likeCount, createdAt }`
* 답글은 같은 서브컬렉션에 `parentId`(최상위 댓글 ID)로 평탄화 저장(depth=1).
* `comments/{id}/likes/{uid}` — 댓글 좋아요.

### vlogs/{vlogId}/likes/{uid} · saves/{uid} · reactions/{uid_emoji}
* `likes/{uid}` — 좋아요 (docId = uid).
* `saves/{uid}` — 저장(북마크). `{ uid, createdAt }`. **컬렉션그룹 쿼리로 내 저장 목록 조회.**
* `reactions/{uid_emoji}` — Slack식 이모지 리액션. `{ userId, emoji, createdAt }`.

---

## 3. config/{configId}
앱 설정(예: 신규 버전 정보). 읽기 공개, 쓰기 마스터.

---

## 보안 규칙 핵심 (firestore.rules)

* `vlogs`: 로그인 사용자 읽기, 작성자/마스터만 수정·삭제. visibility 필터는 클라이언트에서 enforce.
* `saves`: **`uid` 필드 기반 인가** — collectionGroup(`saves`).where(`uid`==me) 쿼리를 허용하기 위함.
  ```
  match /saves/{saveId} {
    allow read:   if request.auth.uid == resource.data.uid;
    allow create: if request.auth.uid == request.resource.data.uid;
    allow delete: if request.auth.uid == resource.data.uid;
  }
  ```
* `fcmTokens`: 본인만 read/write (Cloud Functions는 Admin으로 우회).
* `friends`: 본인 또는 상대가 read/write (요청 페어 생성·수락).

## 인덱스 (firestore.indexes.json)

| 컬렉션그룹 | 필드 | 용도 |
|-----------|------|------|
| saves (COLLECTION_GROUP) | uid ASC, createdAt DESC | 내가 저장한 vlog 목록 |
| vlogs (COLLECTION) | isCheckIn ASC, expiresAt ASC | 만료 체크인 정리(스케줄 함수) |

---

*최종 수정: 2026-06 (PinFlick 기준)*
