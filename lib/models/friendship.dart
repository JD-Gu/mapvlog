import 'package:cloud_firestore/cloud_firestore.dart';

/// 친구 관계 상태
enum FriendshipStatus {
  pending,   // 내가 보낸 요청 (상대 응답 대기)
  incoming,  // 상대가 나에게 보낸 요청 (내 응답 대기)
  accepted;  // 양방향 수락 완료

  String get value => name;

  static FriendshipStatus fromString(String? s) => switch (s) {
        'pending' => FriendshipStatus.pending,
        'incoming' => FriendshipStatus.incoming,
        'accepted' => FriendshipStatus.accepted,
        _ => FriendshipStatus.pending,
      };
}

/// 친구 관계 등급 (베프/부끄럼/불편) — 그룹 베이스라인
/// 통일된 3-mode 용어: 베프(인싸) · 부끄럼 · 불편
enum FriendRelType {
  best,    // 베프 💖 — 실시간 정확 위치 공유
  normal,  // 부끄럼 🙈 — 동·반경 단위 대략 위치 (안개)
  bad;     // 잠수 🥷 — 마지막 위치 고정 (얼음/오프라인)

  String get value => name;
  String get label => switch (this) {
        FriendRelType.best => '베프',
        FriendRelType.normal => '부끄럼',
        FriendRelType.bad => '잠수',
      };
  String get emoji => switch (this) {
        FriendRelType.best => '💖',
        FriendRelType.normal => '🙈',
        FriendRelType.bad => '🥷',
      };

  static FriendRelType fromString(String? s) => switch (s) {
        'best' => FriendRelType.best,
        'normal' => FriendRelType.normal,
        'bad' => FriendRelType.bad,
        _ => FriendRelType.normal,
      };
}

/// 개별 친구 오버라이드 — 그룹/마스터 설정보다 우선
enum FriendIndividualMode {
  precise, // 🎯 항상 정확히 공유 (베프 강제)
  ice,     // 🥷 항상 잠수 (얼음·오프라인 강제)
  inherit; // 🔗 그룹 설정 따름 (기본값)

  String get value => name;
  String get label => switch (this) {
        FriendIndividualMode.precise => '항상 정확히 공유',
        FriendIndividualMode.ice => '항상 잠수',
        FriendIndividualMode.inherit => '그룹 설정 따름',
      };
  String get emoji => switch (this) {
        FriendIndividualMode.precise => '🎯',
        FriendIndividualMode.ice => '🥷',
        FriendIndividualMode.inherit => '🔗',
      };

  static FriendIndividualMode fromString(String? s) => switch (s) {
        'precise' => FriendIndividualMode.precise,
        'ice' => FriendIndividualMode.ice,
        _ => FriendIndividualMode.inherit,
      };
}

/// 최종 노출 모드 — 위치 정밀도 결정 결과
enum FriendEffectiveMode {
  precise, // 정확
  fog,     // 흐릿 (안개)
  ice;     // 얼음 (고정)
}

/// 친구 doc — users/{myUid}/friends/{friendUid}
class Friendship {
  final String friendUid;
  final FriendshipStatus status;
  final FriendRelType relType;               // 그룹 (베이스라인)
  final FriendIndividualMode individualMode; // 개별 오버라이드
  final String? nicknameByMe;
  final DateTime createdAt;
  final DateTime? acceptedAt;

  // 화면 표시용 캐시 (상대 프로필)
  final String? displayName;
  final String? photoUrl;
  final String? email;

  // 얼음/불편 모드 진입 시 친구 위치 스냅샷 (마킹 시점)
  final double? frozenLat;
  final double? frozenLng;
  final DateTime? frozenAt;

  const Friendship({
    required this.friendUid,
    required this.status,
    this.relType = FriendRelType.normal,
    this.individualMode = FriendIndividualMode.inherit,
    this.nicknameByMe,
    required this.createdAt,
    this.acceptedAt,
    this.displayName,
    this.photoUrl,
    this.email,
    this.frozenLat,
    this.frozenLng,
    this.frozenAt,
  });

  factory Friendship.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    final frozen = d['frozenLocation'] as Map<String, dynamic>?;
    return Friendship(
      friendUid: doc.id,
      status: FriendshipStatus.fromString(d['status'] as String?),
      relType: FriendRelType.fromString(d['relType'] as String?),
      individualMode:
          FriendIndividualMode.fromString(d['individualMode'] as String?),
      nicknameByMe: d['nicknameByMe'] as String?,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      acceptedAt: (d['acceptedAt'] as Timestamp?)?.toDate(),
      displayName: d['displayName'] as String?,
      photoUrl: d['photoUrl'] as String?,
      email: d['email'] as String?,
      frozenLat: (frozen?['lat'] as num?)?.toDouble(),
      frozenLng: (frozen?['lng'] as num?)?.toDouble(),
      frozenAt: (frozen?['frozenAt'] as Timestamp?)?.toDate(),
    );
  }

  /// 표시 이름 — 별명 우선, 없으면 캐시된 displayName, 그것도 없으면 friendUid 짧게
  String get effectiveName {
    if (nicknameByMe != null && nicknameByMe!.isNotEmpty) return nicknameByMe!;
    if (displayName != null && displayName!.isNotEmpty) return displayName!;
    return friendUid.substring(0, friendUid.length.clamp(0, 8));
  }

  /// 위치 공개 우선순위 엔진 — 이 친구에게 적용되는 최종 노출 모드 계산
  ///
  /// 우선순위:
  ///   1순위: individualMode가 inherit이 아니면 그대로 (precise/ice)
  ///   2순위: 마스터 스위치(myPrivacy)가 제한 모드(fog/ice)면 마스터 적용
  ///   3순위: 그룹 베이스라인 (best→precise, normal→fog, bad→ice)
  FriendEffectiveMode effectiveMode(String? myPrivacyValue) {
    // 1순위: 개별 오버라이드
    if (individualMode == FriendIndividualMode.precise) {
      return FriendEffectiveMode.precise;
    }
    if (individualMode == FriendIndividualMode.ice) {
      return FriendEffectiveMode.ice;
    }
    // 2순위: 마스터 스위치가 제한적이면 우선
    if (myPrivacyValue == 'ice') return FriendEffectiveMode.ice;
    if (myPrivacyValue == 'fog') return FriendEffectiveMode.fog;
    // 3순위: 그룹 베이스라인
    return switch (relType) {
      FriendRelType.best => FriendEffectiveMode.precise,
      FriendRelType.normal => FriendEffectiveMode.fog,
      FriendRelType.bad => FriendEffectiveMode.ice,
    };
  }
}
