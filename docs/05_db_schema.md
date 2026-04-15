# 05. DB 스키마

## 개요

MapVlog는 Firebase Cloud Firestore를 주 데이터베이스로 사용합니다.
Firestore는 NoSQL 문서(Document) 기반 DB이며, 컬렉션(Collection) → 문서(Document) → 필드(Field) 구조입니다.

---

## 컬렉션 구조 개요

```
Firestore
├── users/                    # 사용자 정보
├── vlogs/                    # 브이로그
│   └── {vlogId}/
│       ├── gpsTracks/        # GPS 트랙 (서브컬렉션)
│       └── photos/           # 브이로그 내 사진 (서브컬렉션)
├── likes/                    # 좋아요
└── follows/                  # 팔로우 관계
```

---

## 1. users 컬렉션

**경로**: `users/{uid}`

| 필드명 | 타입 | 설명 | 예시 |
|--------|------|------|------|
| uid | string | Firebase Auth UID (문서 ID) | "abc123" |
| email | string | 이메일 | "user@example.com" |
| displayName | string | 닉네임 | "여행러" |
| photoURL | string | 프로필 사진 URL | "https://..." |
| bio | string | 자기소개 | "전국 여행 중" |
| vlogCount | number | 업로드한 브이로그 수 | 12 |
| followerCount | number | 팔로워 수 | 34 |
| followingCount | number | 팔로잉 수 | 21 |
| createdAt | timestamp | 가입일 | Timestamp |
| updatedAt | timestamp | 최종 수정일 | Timestamp |

**예시 문서**
```json
{
  "uid": "abc123",
  "email": "user@example.com",
  "displayName": "여행러",
  "photoURL": "https://cdn.mapvlog.com/profiles/abc123.jpg",
  "bio": "전국 여행 중",
  "vlogCount": 12,
  "followerCount": 34,
  "followingCount": 21,
  "createdAt": "2026-01-01T00:00:00Z",
  "updatedAt": "2026-04-15T00:00:00Z"
}
```

---

## 2. vlogs 컬렉션

**경로**: `vlogs/{vlogId}`

| 필드명 | 타입 | 설명 | 예시 |
|--------|------|------|------|
| id | string | 브이로그 ID (자동 생성) | "vlog_001" |
| authorUid | string | 작성자 UID | "abc123" |
| authorName | string | 작성자 닉네임 (반정규화) | "여행러" |
| title | string | 브이로그 제목 | "홍대 카페 투어" |
| description | string | 설명 | "홍대 주변 카페..." |
| thumbnailUrl | string | 썸네일 CDN URL | "https://cdn..." |
| videoUrl | string | 영상 CDN URL | "https://cdn..." |
| videoKey | string | S3 오브젝트 키 | "videos/abc123/..." |
| videoLength | number | 영상 길이 (초) | 320 |
| startLocation | map | 촬영 시작 위치 | {lat, lng, placeName} |
| endLocation | map | 촬영 종료 위치 | {lat, lng, placeName} |
| totalDistance | number | 이동 거리 (미터) | 3200 |
| gpsPointCount | number | GPS 좌표 개수 | 127 |
| places | array | 주요 장소 목록 | [{t, placeId, name, lat, lng}] |
| visibility | string | 공개 범위 (public/link/private) | "public" |
| viewCount | number | 조회 수 | 152 |
| likeCount | number | 좋아요 수 | 32 |
| createdAt | timestamp | 생성일 | Timestamp |
| updatedAt | timestamp | 수정일 | Timestamp |

**startLocation / endLocation 구조**
```json
{
  "lat": 37.556,
  "lng": 126.923,
  "placeName": "홍대입구역"
}
```

**places 배열 항목 구조**
```json
{
  "t": 0,
  "placeId": "ChIJ...",
  "name": "홍대입구역",
  "lat": 37.556,
  "lng": 126.923
}
```

---

## 3. vlogs/{vlogId}/gpsTracks 서브컬렉션

**경로**: `vlogs/{vlogId}/gpsTracks/{trackId}`

> GPS 좌표는 데이터량이 많으므로 서브컬렉션으로 분리하여 저장합니다.
> 영상 재생 시 한꺼번에 로드하여 클라이언트에서 인덱싱합니다.

| 필드명 | 타입 | 설명 | 예시 |
|--------|------|------|------|
| t | number | 타임코드 (초) | 0, 1, 2, ... |
| lat | number | 위도 | 37.5561 |
| lng | number | 경도 | 126.9231 |
| alt | number | 고도 (미터, 선택) | 15.3 |
| accuracy | number | GPS 정확도 (미터, 선택) | 3.5 |

**저장 방식**
- 한 문서에 최대 500개 좌표를 배열로 묶어 저장 (Firestore 문서 크기 제한 대응)

```json
{
  "chunk": 0,
  "points": [
    { "t": 0, "lat": 37.556, "lng": 126.923 },
    { "t": 1, "lat": 37.5561, "lng": 126.9231 },
    { "t": 2, "lat": 37.5562, "lng": 126.9232 }
  ]
}
```

---

## 4. vlogs/{vlogId}/photos 서브컬렉션

**경로**: `vlogs/{vlogId}/photos/{photoId}`

| 필드명 | 타입 | 설명 | 예시 |
|--------|------|------|------|
| id | string | 사진 ID | "photo_001" |
| t | number | 촬영 타임코드 (초) | 45 |
| url | string | 사진 CDN URL | "https://cdn..." |
| key | string | S3 오브젝트 키 | "photos/abc123/..." |
| lat | number | 위도 | 37.558 |
| lng | number | 경도 | 126.925 |
| placeName | string | 촬영 장소명 | "홍대 카페 A" |
| createdAt | timestamp | 촬영 일시 | Timestamp |

---

## 5. likes 컬렉션

**경로**: `likes/{likeId}`

> likeId = `{uid}_{vlogId}` 형식으로 중복 좋아요 방지

| 필드명 | 타입 | 설명 | 예시 |
|--------|------|------|------|
| uid | string | 좋아요한 사용자 UID | "abc123" |
| vlogId | string | 브이로그 ID | "vlog_001" |
| createdAt | timestamp | 좋아요 일시 | Timestamp |

---

## 6. follows 컬렉션

**경로**: `follows/{followId}`

> followId = `{followerUid}_{followingUid}` 형식

| 필드명 | 타입 | 설명 | 예시 |
|--------|------|------|------|
| followerUid | string | 팔로우하는 사용자 UID | "abc123" |
| followingUid | string | 팔로우 당하는 사용자 UID | "def456" |
| createdAt | timestamp | 팔로우 일시 | Timestamp |

---

## Firestore 보안 규칙 (Security Rules)

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {

    // 사용자 - 본인만 수정 가능, 읽기는 공개
    match /users/{uid} {
      allow read: if true;
      allow write: if request.auth != null && request.auth.uid == uid;
    }

    // 브이로그 - 공개 브이로그는 누구나 읽기, 작성자만 수정/삭제
    match /vlogs/{vlogId} {
      allow read: if resource.data.visibility == 'public'
                  || (request.auth != null && request.auth.uid == resource.data.authorUid);
      allow create: if request.auth != null;
      allow update, delete: if request.auth != null
                             && request.auth.uid == resource.data.authorUid;

      // GPS 트랙 - 브이로그와 동일한 규칙
      match /gpsTracks/{trackId} {
        allow read: if get(/databases/$(database)/documents/vlogs/$(vlogId)).data.visibility == 'public'
                    || request.auth.uid == get(/databases/$(database)/documents/vlogs/$(vlogId)).data.authorUid;
        allow write: if request.auth != null
                     && request.auth.uid == get(/databases/$(database)/documents/vlogs/$(vlogId)).data.authorUid;
      }

      // 사진 - GPS 트랙과 동일
      match /photos/{photoId} {
        allow read: if get(/databases/$(database)/documents/vlogs/$(vlogId)).data.visibility == 'public'
                    || request.auth.uid == get(/databases/$(database)/documents/vlogs/$(vlogId)).data.authorUid;
        allow write: if request.auth != null
                     && request.auth.uid == get(/databases/$(database)/documents/vlogs/$(vlogId)).data.authorUid;
      }
    }

    // 좋아요 - 로그인 사용자만
    match /likes/{likeId} {
      allow read: if true;
      allow write: if request.auth != null;
    }

    // 팔로우 - 로그인 사용자만
    match /follows/{followId} {
      allow read: if true;
      allow write: if request.auth != null;
    }
  }
}
```

---

## 인덱스 설계

| 컬렉션 | 필드 | 용도 |
|--------|------|------|
| vlogs | authorUid (ASC), createdAt (DESC) | 특정 사용자의 브이로그 목록 |
| vlogs | visibility (ASC), createdAt (DESC) | 공개 피드 |
| vlogs | startLocation (GEO) | 위치 기반 검색 |
| likes | uid (ASC), createdAt (DESC) | 사용자 좋아요 목록 |
| follows | followerUid (ASC) | 팔로잉 목록 |
| follows | followingUid (ASC) | 팔로워 목록 |

---

*최종 수정: 2026-04-15*
