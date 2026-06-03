import 'package:cloud_firestore/cloud_firestore.dart';

/// 사용자 상태 (이모지 + 라벨)
class UserStatus {
  final String emoji;
  final String label;
  final DateTime updatedAt;

  const UserStatus({
    required this.emoji,
    required this.label,
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() => {
        'emoji': emoji,
        'label': label,
        'updatedAt': Timestamp.fromDate(updatedAt),
      };

  factory UserStatus.fromJson(Map<String, dynamic> json) => UserStatus(
        emoji: json['emoji'] as String? ?? '',
        label: json['label'] as String? ?? '',
        updatedAt: (json['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      );
}

/// 사용자 라이브 위치
class UserLocation {
  final double lat;
  final double lng;
  final DateTime updatedAt;
  final bool? isMoving;       // 이동 중 플래그
  final int? batteryLevel;    // 배터리 잔량 0~100

  const UserLocation({
    required this.lat,
    required this.lng,
    required this.updatedAt,
    this.isMoving,
    this.batteryLevel,
  });

  factory UserLocation.fromJson(Map<String, dynamic> json) => UserLocation(
        lat: (json['lat'] as num?)?.toDouble() ?? 0,
        lng: (json['lng'] as num?)?.toDouble() ?? 0,
        updatedAt: (json['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
        isMoving: json['isMoving'] as bool?,
        batteryLevel: (json['batteryLevel'] as num?)?.toInt(),
      );
}

/// 프라이버시 모드 — 통일된 3-mode (베프·부끄럼·잠수)
enum PrivacyMode {
  precise, // 베프 모드 — 실시간 정밀 좌표 100% 오픈
  fog,     // 부끄럼 모드 — 동네 단위 (≈1km)
  ice;     // 잠수 모드 — 마지막 위치에 머물러 있음

  String get label => switch (this) {
        PrivacyMode.precise => '베프 모드',
        PrivacyMode.fog => '부끄럼 모드',
        PrivacyMode.ice => '잠수 모드',
      };

  String get emoji => switch (this) {
        PrivacyMode.precise => '💖',
        PrivacyMode.fog => '🙈',
        PrivacyMode.ice => '🥷',
      };

  String get description => switch (this) {
        PrivacyMode.precise =>
          '친구들에게 실시간 정확 위치를 공유해요',
        PrivacyMode.fog =>
          '동·반경 단위 대략 위치만 살짝 공유해요',
        PrivacyMode.ice =>
          '마지막 위치 고정 — 오프라인처럼 표시돼요',
      };

  static PrivacyMode fromString(String? s) => switch (s) {
        'precise' => PrivacyMode.precise,
        'fog' => PrivacyMode.fog,
        'ice' => PrivacyMode.ice,
        _ => PrivacyMode.fog, // 기본값: 부끄럼 (안전한 기본)
      };

  String get value => name;
}

/// 라이브 맵에 표시되는 사용자 프로필 (상태 + 위치 + 프라이버시)
class LiveUser {
  final String uid;
  final String displayName;
  final String? photoUrl;
  final UserStatus? status;
  final UserLocation? location;
  final PrivacyMode privacyMode;
  final DateTime? lastSeen;

  const LiveUser({
    required this.uid,
    required this.displayName,
    this.photoUrl,
    this.status,
    this.location,
    this.privacyMode = PrivacyMode.fog,
    this.lastSeen,
  });

  factory LiveUser.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return LiveUser(
      uid: doc.id,
      displayName: d['displayName'] as String? ?? '사용자',
      photoUrl: d['photoUrl'] as String?,
      status: d['status'] is Map
          ? UserStatus.fromJson(d['status'] as Map<String, dynamic>)
          : null,
      location: d['liveLocation'] is Map
          ? UserLocation.fromJson(d['liveLocation'] as Map<String, dynamic>)
          : null,
      privacyMode: PrivacyMode.fromString(d['privacyMode'] as String?),
      lastSeen: (d['lastSeen'] as Timestamp?)?.toDate(),
    );
  }

  /// 위치가 신선한지 (10분 이내 업데이트)
  bool get isFresh {
    if (location == null) return false;
    return DateTime.now().difference(location!.updatedAt).inMinutes < 10;
  }
}

/// 친구 호출 (Ping)
class Ping {
  final String id;
  final String fromUid;
  final String fromName;
  final String emoji;
  final String message;
  final DateTime createdAt;

  const Ping({
    required this.id,
    required this.fromUid,
    required this.fromName,
    required this.emoji,
    required this.message,
    required this.createdAt,
  });

  factory Ping.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return Ping(
      id: doc.id,
      fromUid: d['fromUid'] as String? ?? '',
      fromName: d['fromName'] as String? ?? '익명',
      emoji: d['emoji'] as String? ?? '👋',
      message: d['message'] as String? ?? '어디야?',
      createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
}

/// 미리 정의된 호출 옵션
class PingPresets {
  static const List<({String emoji, String message})> presets = [
    (emoji: '👋', message: '어디야?'),
    (emoji: '🏃', message: '빨리 와!'),
    (emoji: '🤝', message: '만나자!'),
    (emoji: '📞', message: '전화해줘'),
    (emoji: '💬', message: '톡 봐줘'),
    (emoji: '❤️', message: '보고싶어'),
    (emoji: '🍻', message: '한잔 콜?'),
    (emoji: '🍚', message: '밥 먹자'),
    (emoji: '☕', message: '커피 한잔?'),
    (emoji: '🎮', message: '게임 ㄱ?'),
    (emoji: '🚗', message: '데리러 와'),
    (emoji: '🛍️', message: '같이 쇼핑'),
    (emoji: '🎉', message: '축하해!'),
    (emoji: '🆘', message: '도와줘!'),
    (emoji: '😴', message: '자?'),
    (emoji: '🤔', message: '뭐해?'),
  ];
}

/// 미리 정의된 상태 옵션
class StatusPresets {
  static const List<({String emoji, String label})> presets = [
    (emoji: '☕', label: '카페'),
    (emoji: '🍽️', label: '식사'),
    (emoji: '💻', label: '일/공부'),
    (emoji: '🛌', label: '집콕'),
    (emoji: '🚗', label: '이동 중'),
    (emoji: '🛍️', label: '쇼핑'),
    (emoji: '🏃', label: '운동'),
    (emoji: '🌳', label: '산책'),
    (emoji: '✈️', label: '여행'),
    (emoji: '🎉', label: '모임'),
    (emoji: '🎵', label: '공연/콘서트'),
    (emoji: '🎬', label: '영화'),
  ];
}
