# 04. API 명세

## 개요

MapVlog 백엔드(Node.js + Express) REST API 명세입니다.
Base URL: `https://api.mapvlog.com/v1`

---

## 인증

모든 인증이 필요한 API는 Firebase ID Token을 헤더에 포함합니다.

```
Authorization: Bearer {firebase_id_token}
Content-Type: application/json
```

---

## 1. 인증 (Auth)

### 1.1 사용자 등록 / 프로필 생성

```
POST /auth/register
```

**Request Body**
```json
{
  "uid": "firebase_uid",
  "email": "user@example.com",
  "displayName": "닉네임",
  "photoURL": "https://..."
}
```

**Response 200**
```json
{
  "success": true,
  "user": {
    "uid": "firebase_uid",
    "displayName": "닉네임",
    "createdAt": "2026-04-15T00:00:00Z"
  }
}
```

---

### 1.2 사용자 프로필 조회

```
GET /users/:uid
```

**Response 200**
```json
{
  "uid": "firebase_uid",
  "displayName": "닉네임",
  "photoURL": "https://...",
  "vlogCount": 12,
  "followerCount": 34,
  "followingCount": 21,
  "createdAt": "2026-01-01T00:00:00Z"
}
```

---

### 1.3 사용자 프로필 수정

```
PATCH /users/:uid
Authorization: Bearer {token}
```

**Request Body**
```json
{
  "displayName": "새닉네임",
  "bio": "소개글"
}
```

---

## 2. 브이로그 (Vlog)

### 2.1 브이로그 목록 조회

```
GET /vlogs
```

**Query Parameters**

| 파라미터 | 타입 | 필수 | 설명 |
|---------|------|------|------|
| lat | float | 선택 | 중심 위도 |
| lng | float | 선택 | 중심 경도 |
| radius | int | 선택 | 검색 반경 (미터, 기본값: 10000) |
| limit | int | 선택 | 최대 개수 (기본값: 20) |
| cursor | string | 선택 | 페이지네이션 커서 |

**Response 200**
```json
{
  "vlogs": [
    {
      "id": "vlog_id_001",
      "title": "홍대 카페 투어",
      "thumbnailUrl": "https://cdn.mapvlog.com/thumbs/...",
      "videoUrl": "https://cdn.mapvlog.com/videos/...",
      "authorUid": "user_uid",
      "authorName": "닉네임",
      "startLocation": {
        "lat": 37.556,
        "lng": 126.923,
        "placeName": "홍대입구역"
      },
      "distance": 3200,
      "duration": 320,
      "viewCount": 152,
      "likeCount": 32,
      "createdAt": "2026-04-10T12:00:00Z"
    }
  ],
  "nextCursor": "cursor_string",
  "total": 158
}
```

---

### 2.2 브이로그 상세 조회

```
GET /vlogs/:vlogId
```

**Response 200**
```json
{
  "id": "vlog_id_001",
  "title": "홍대 카페 투어",
  "description": "홍대 주변 카페 탐방",
  "thumbnailUrl": "https://...",
  "videoUrl": "https://...",
  "videoLength": 320,
  "authorUid": "user_uid",
  "authorName": "닉네임",
  "gpsTrack": [
    { "t": 0, "lat": 37.556, "lng": 126.923 },
    { "t": 1, "lat": 37.5561, "lng": 126.9231 },
    { "t": 2, "lat": 37.5562, "lng": 126.9232 }
  ],
  "places": [
    {
      "t": 0,
      "placeId": "ChIJ...",
      "name": "홍대입구역",
      "lat": 37.556,
      "lng": 126.923
    }
  ],
  "photos": [
    {
      "t": 45,
      "url": "https://cdn.mapvlog.com/photos/...",
      "lat": 37.558,
      "lng": 126.925
    }
  ],
  "visibility": "public",
  "viewCount": 152,
  "likeCount": 32,
  "createdAt": "2026-04-10T12:00:00Z"
}
```

---

### 2.3 브이로그 업로드 (Pre-signed URL 발급)

```
POST /vlogs/upload-url
Authorization: Bearer {token}
```

**Request Body**
```json
{
  "filename": "vlog_20260415.mp4",
  "contentType": "video/mp4",
  "fileSize": 52428800
}
```

**Response 200**
```json
{
  "uploadUrl": "https://s3.amazonaws.com/mapvlog/...?X-Amz-...",
  "key": "videos/user_uid/vlog_20260415.mp4",
  "expiresIn": 3600
}
```

---

### 2.4 브이로그 메타데이터 저장

```
POST /vlogs
Authorization: Bearer {token}
```

**Request Body**
```json
{
  "title": "홍대 카페 투어",
  "description": "홍대 주변 카페 탐방",
  "videoKey": "videos/user_uid/vlog_20260415.mp4",
  "thumbnailKey": "thumbs/user_uid/thumb_20260415.jpg",
  "gpsTrack": [
    { "t": 0, "lat": 37.556, "lng": 126.923 },
    { "t": 1, "lat": 37.5561, "lng": 126.9231 }
  ],
  "videoLength": 320,
  "visibility": "public"
}
```

**Response 201**
```json
{
  "success": true,
  "vlogId": "vlog_id_001",
  "shareUrl": "https://mapvlog.vercel.app/v/vlog_id_001"
}
```

---

### 2.5 브이로그 수정

```
PATCH /vlogs/:vlogId
Authorization: Bearer {token}
```

**Request Body** (변경할 필드만 포함)
```json
{
  "title": "수정된 제목",
  "description": "수정된 설명",
  "visibility": "private"
}
```

---

### 2.6 브이로그 삭제

```
DELETE /vlogs/:vlogId
Authorization: Bearer {token}
```

**Response 200**
```json
{
  "success": true,
  "message": "브이로그가 삭제되었습니다."
}
```

---

## 3. 장소 정보 (Places)

### 3.1 좌표 기반 장소 조회

```
GET /places/nearby
```

**Query Parameters**

| 파라미터 | 타입 | 필수 | 설명 |
|---------|------|------|------|
| lat | float | 필수 | 위도 |
| lng | float | 필수 | 경도 |
| radius | int | 선택 | 반경 (미터, 기본값: 100) |

**Response 200**
```json
{
  "places": [
    {
      "placeId": "ChIJ...",
      "name": "홍대입구역",
      "address": "서울 마포구 양화로 188",
      "types": ["subway_station", "transit_station"],
      "lat": 37.556,
      "lng": 126.923,
      "rating": 4.2
    }
  ]
}
```

---

## 4. 좋아요 (Like)

### 4.1 좋아요 추가/취소 (토글)

```
POST /vlogs/:vlogId/like
Authorization: Bearer {token}
```

**Response 200**
```json
{
  "liked": true,
  "likeCount": 33
}
```

---

## 5. 팔로우 (Follow)

### 5.1 팔로우/언팔로우 (토글)

```
POST /users/:uid/follow
Authorization: Bearer {token}
```

**Response 200**
```json
{
  "following": true,
  "followerCount": 35
}
```

---

## HTTP 상태 코드

| 코드 | 설명 |
|------|------|
| 200 | 성공 |
| 201 | 생성 성공 |
| 400 | 잘못된 요청 (파라미터 오류) |
| 401 | 인증 실패 (토큰 없음 / 만료) |
| 403 | 권한 없음 |
| 404 | 리소스 없음 |
| 500 | 서버 내부 오류 |

---

## 에러 응답 형식

```json
{
  "success": false,
  "error": {
    "code": "UNAUTHORIZED",
    "message": "인증이 필요합니다."
  }
}
```

---

*최종 수정: 2026-04-15*
