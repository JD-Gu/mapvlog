import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// 5대 이벤트 카테고리.
/// sports/culture/festival/public = `events` 컬렉션, daily = 기존 vlogs(UGC).
enum EventCategory {
  sports,
  culture,
  festival,
  public,
  daily;

  String get value => name;

  String get label => switch (this) {
        EventCategory.sports => '스포츠/레저',
        EventCategory.culture => '공연/전시',
        EventCategory.festival => '축제/바자회',
        EventCategory.public => '공공/지자체',
        EventCategory.daily => '일상/기업',
      };

  String get emoji => switch (this) {
        EventCategory.sports => '🏆',
        EventCategory.culture => '🎭',
        EventCategory.festival => '🎪',
        EventCategory.public => '🏛️',
        EventCategory.daily => '🍿',
      };

  Color get color => switch (this) {
        EventCategory.sports => const Color(0xFF1E88E5),
        EventCategory.culture => const Color(0xFFEC407A),
        EventCategory.festival => const Color(0xFFFFA726),
        EventCategory.public => const Color(0xFF26A69A),
        EventCategory.daily => const Color(0xFF7C4DFF),
      };

  static EventCategory fromString(String? s) => switch (s) {
        'sports' => EventCategory.sports,
        'culture' => EventCategory.culture,
        'festival' => EventCategory.festival,
        'public' => EventCategory.public,
        _ => EventCategory.daily,
      };

  /// events 컬렉션을 쓰는 카테고리 (daily 는 vlogs UGC 라 관리자 등록 대상 아님)
  static const List<EventCategory> adminCategories = [
    sports,
    culture,
    festival,
    public,
  ];
}

enum EventCostType {
  free,
  paid;

  String get value => name;
  String get label => this == EventCostType.free ? '무료' : '유료';
  static EventCostType fromString(String? s) =>
      s == 'paid' ? EventCostType.paid : EventCostType.free;
}

/// 라이브 이벤트 핀. 모든 핀에 시작~종료 일시가 있고, 끝나면 자동으로 숨겨진다.
class PinEvent {
  final String id;
  final String title;
  final EventCategory category;
  final String description;
  final String? posterUrl;
  final double lat;
  final double lng;
  final String placeName;
  final String? address;
  final DateTime startAt;
  final DateTime endAt;
  final bool allDay;
  final EventCostType costType;
  final String? price; // 유료일 때 표시용 ("성인 15,000원" 등)
  final String? link; // 예매/상세 URL
  final String source; // 'admin' | 'crawler'
  final String status; // 'active' | 'ended' | 'hidden'
  final String createdBy;
  final int viewCount;
  final int likeCount;
  final int saveCount;
  final int commentCount;
  final DateTime createdAt;
  final DateTime? updatedAt;

  PinEvent({
    required this.id,
    required this.title,
    required this.category,
    this.description = '',
    this.posterUrl,
    required this.lat,
    required this.lng,
    required this.placeName,
    this.address,
    required this.startAt,
    required this.endAt,
    this.allDay = false,
    this.costType = EventCostType.free,
    this.price,
    this.link,
    this.source = 'admin',
    this.status = 'active',
    required this.createdBy,
    this.viewCount = 0,
    this.likeCount = 0,
    this.saveCount = 0,
    this.commentCount = 0,
    required this.createdAt,
    this.updatedAt,
  });

  bool isEnded([DateTime? now]) => (now ?? DateTime.now()).isAfter(endAt);

  bool isOngoing([DateTime? now]) {
    final n = now ?? DateTime.now();
    return n.isAfter(startAt) && n.isBefore(endAt);
  }

  /// 상태 배지 텍스트 (진행 중 / D-3 / 오늘 시작 / 오늘 종료 / 종료)
  String statusBadge([DateTime? now]) {
    final n = now ?? DateTime.now();
    if (n.isAfter(endAt)) return '종료';
    if (n.isBefore(startAt)) {
      final today = DateTime(n.year, n.month, n.day);
      final startDay = DateTime(startAt.year, startAt.month, startAt.day);
      final d = startDay.difference(today).inDays;
      if (d <= 0) return '오늘 시작';
      return 'D-$d';
    }
    final today = DateTime(n.year, n.month, n.day);
    final endDay = DateTime(endAt.year, endAt.month, endAt.day);
    if (endDay == today) return '오늘 종료';
    return '진행 중';
  }

  factory PinEvent.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    DateTime ts(dynamic v, [DateTime? fallback]) =>
        (v is Timestamp) ? v.toDate() : (fallback ?? DateTime.now());
    return PinEvent(
      id: doc.id,
      title: (d['title'] as String?) ?? '',
      category: EventCategory.fromString(d['category'] as String?),
      description: (d['description'] as String?) ?? '',
      posterUrl: d['posterUrl'] as String?,
      lat: (d['lat'] as num?)?.toDouble() ?? 0,
      lng: (d['lng'] as num?)?.toDouble() ?? 0,
      placeName: (d['placeName'] as String?) ?? '',
      address: d['address'] as String?,
      startAt: ts(d['startAt']),
      endAt: ts(d['endAt'], DateTime.now().add(const Duration(hours: 1))),
      allDay: (d['allDay'] as bool?) ?? false,
      costType: EventCostType.fromString(d['costType'] as String?),
      price: d['price'] as String?,
      link: d['link'] as String?,
      source: (d['source'] as String?) ?? 'admin',
      status: (d['status'] as String?) ?? 'active',
      createdBy: (d['createdBy'] as String?) ?? '',
      viewCount: (d['viewCount'] as num?)?.toInt() ?? 0,
      likeCount: (d['likeCount'] as num?)?.toInt() ?? 0,
      saveCount: (d['saveCount'] as num?)?.toInt() ?? 0,
      commentCount: (d['commentCount'] as num?)?.toInt() ?? 0,
      createdAt: ts(d['createdAt']),
      updatedAt: d['updatedAt'] is Timestamp
          ? (d['updatedAt'] as Timestamp).toDate()
          : null,
    );
  }

  Map<String, dynamic> toMap() => {
        'title': title,
        'category': category.value,
        'description': description,
        'posterUrl': posterUrl,
        'lat': lat,
        'lng': lng,
        'placeName': placeName,
        'address': address,
        'startAt': Timestamp.fromDate(startAt),
        'endAt': Timestamp.fromDate(endAt),
        'allDay': allDay,
        'costType': costType.value,
        'price': price,
        'link': link,
        'source': source,
        'status': status,
        'createdBy': createdBy,
      };
}
