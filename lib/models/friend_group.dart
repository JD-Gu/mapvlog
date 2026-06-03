import 'package:cloud_firestore/cloud_firestore.dart';

/// 그룹별 위치 권한 모드 — 친구그루핑정책.md
/// 통일된 3-mode 용어: 베프 · 부끄럼 · 불편
enum GroupMode {
  /// 💖 베프 — 실시간 정확 위치 공유 (구 "인싸")
  insider('insider', '베프', '💖', '실시간 정확 위치 공유'),

  /// 🙈 부끄럼 — 행정동/반경 마스킹
  shy('shy', '부끄럼', '🙈', '동·반경 단위 대략 위치'),

  /// 🥷 잠수 — 숨김/고정 (오프라인 상태 및 마지막 위치 고정)
  uneasy('uneasy', '잠수', '🥷', '숨김/고정 · 오프라인 및 마지막 위치 고정');

  final String value;
  final String label;
  final String emoji;
  final String description;
  const GroupMode(this.value, this.label, this.emoji, this.description);

  static GroupMode fromValue(String? v) {
    switch (v) {
      case 'insider':
        return GroupMode.insider;
      case 'shy':
        return GroupMode.shy;
      case 'uneasy':
        return GroupMode.uneasy;
      default:
        return GroupMode.insider;
    }
  }
}

/// 사용자가 자유롭게 정의하는 친구 그룹
///
/// Firestore 경로: users/{ownerUid}/friendGroups/{groupId}
/// — 각 사용자가 본인 그룹만 정의·소유 (개인 분류)
class FriendGroup {
  final String id;
  final String name;        // '가족', '동아리', '꽃꽂이 모임' 등
  final String emoji;       // 그룹 대표 이모지
  final GroupMode mode;     // 인싸/부끄럼/불편
  final List<String> memberUids; // 이 그룹에 속한 친구 UID 목록 (M:N 다중)
  final DateTime createdAt;

  const FriendGroup({
    required this.id,
    required this.name,
    required this.emoji,
    required this.mode,
    required this.memberUids,
    required this.createdAt,
  });

  factory FriendGroup.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return FriendGroup(
      id: doc.id,
      name: d['name'] as String? ?? '이름 없음',
      emoji: d['emoji'] as String? ?? '👥',
      mode: GroupMode.fromValue(d['mode'] as String?),
      memberUids: (d['memberUids'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      createdAt:
          (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() => {
        'name': name,
        'emoji': emoji,
        'mode': mode.value,
        'memberUids': memberUids,
        'createdAt': FieldValue.serverTimestamp(),
      };

  FriendGroup copyWith({
    String? name,
    String? emoji,
    GroupMode? mode,
    List<String>? memberUids,
  }) =>
      FriendGroup(
        id: id,
        name: name ?? this.name,
        emoji: emoji ?? this.emoji,
        mode: mode ?? this.mode,
        memberUids: memberUids ?? this.memberUids,
        createdAt: createdAt,
      );
}
