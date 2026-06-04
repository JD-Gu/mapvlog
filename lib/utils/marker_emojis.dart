import 'package:flutter/material.dart';

/// 지도 마커 이모지 카탈로그 — 카테고리별 50+ 종 + 색상 자동 매핑
///
/// 사용자가 이모지를 고르면 그에 맞는 색상이 자동 결정되어 지도/카드의
/// 마커 색상까지 일관되게 표현됩니다. (markerColor 자동 파생)
class MarkerEmoji {
  final String emoji;
  final String label;
  final Color color;
  final String category;
  const MarkerEmoji({
    required this.emoji,
    required this.label,
    required this.color,
    required this.category,
  });
}

class MarkerEmojiGroup {
  final String name;
  final String hint; // 섹션 헤더 아이콘 이모지
  final List<MarkerEmoji> emojis;
  const MarkerEmojiGroup({
    required this.name,
    required this.hint,
    required this.emojis,
  });
}

class MarkerEmojis {
  // ── 카테고리별 그룹 ────────────────────────────────────────────────────────
  static const _foodColor = Color(0xFFEA4335);
  static const _cafeColor = Color(0xFF8D6E63);
  static const _drinkColor = Color(0xFFFFA726);
  static const _exerciseColor = Color(0xFF34A853);
  static const _cultureColor = Color(0xFF3F51B5);
  static const _studyColor = Color(0xFF7C4DFF);
  static const _workColor = Color(0xFF546E7A);
  static const _shopColor = Color(0xFFAB47BC);
  static const _placeColor = Color(0xFF1A73E8);
  static const _natureColor = Color(0xFF2E7D32);
  static const _travelColor = Color(0xFF00ACC1);
  static const _eventColor = Color(0xFFD81B60);
  static const _healthColor = Color(0xFFFF6B6B);
  static const _otherColor = Color(0xFF607D8B);

  static const List<MarkerEmojiGroup> groups = [
    MarkerEmojiGroup(
      name: '일반',
      hint: '📍',
      emojis: [
        MarkerEmoji(emoji: '📍', label: '일반', color: _placeColor, category: '일반'),
        MarkerEmoji(emoji: '⭐', label: '즐겨찾기', color: Color(0xFFFFC107), category: '일반'),
        MarkerEmoji(emoji: '❤️', label: '좋아하는 곳', color: Color(0xFFE91E63), category: '일반'),
        MarkerEmoji(emoji: '🔥', label: '핫플', color: Color(0xFFFF5722), category: '일반'),
        MarkerEmoji(emoji: '💎', label: '특별한 곳', color: Color(0xFF00BCD4), category: '일반'),
      ],
    ),
    MarkerEmojiGroup(
      name: '음식',
      hint: '🍽️',
      emojis: [
        MarkerEmoji(emoji: '🍕', label: '피자', color: _foodColor, category: '음식'),
        MarkerEmoji(emoji: '🍔', label: '버거', color: _foodColor, category: '음식'),
        MarkerEmoji(emoji: '🍣', label: '일식', color: Color(0xFFEC407A), category: '음식'),
        MarkerEmoji(emoji: '🍜', label: '면류', color: Color(0xFFFFB300), category: '음식'),
        MarkerEmoji(emoji: '🥘', label: '한식', color: Color(0xFFD84315), category: '음식'),
        MarkerEmoji(emoji: '🍱', label: '도시락', color: Color(0xFFE65100), category: '음식'),
        MarkerEmoji(emoji: '🥩', label: '고기집', color: Color(0xFFBF360C), category: '음식'),
        MarkerEmoji(emoji: '🍗', label: '치킨', color: Color(0xFFFB8C00), category: '음식'),
        MarkerEmoji(emoji: '🍰', label: '디저트', color: Color(0xFFF06292), category: '음식'),
        MarkerEmoji(emoji: '🍩', label: '베이커리', color: Color(0xFFBA68C8), category: '음식'),
        MarkerEmoji(emoji: '🍦', label: '아이스크림', color: Color(0xFFB3E5FC), category: '음식'),
      ],
    ),
    MarkerEmojiGroup(
      name: '카페·음료',
      hint: '☕',
      emojis: [
        MarkerEmoji(emoji: '☕', label: '카페', color: _cafeColor, category: '카페·음료'),
        MarkerEmoji(emoji: '🧋', label: '버블티', color: Color(0xFFA1887F), category: '카페·음료'),
        MarkerEmoji(emoji: '🍺', label: '맥주', color: _drinkColor, category: '카페·음료'),
        MarkerEmoji(emoji: '🍻', label: '술집', color: Color(0xFFF57C00), category: '카페·음료'),
        MarkerEmoji(emoji: '🍷', label: '와인바', color: Color(0xFF8E24AA), category: '카페·음료'),
        MarkerEmoji(emoji: '🥃', label: '위스키바', color: Color(0xFF6D4C41), category: '카페·음료'),
        MarkerEmoji(emoji: '🍹', label: '칵테일', color: Color(0xFFF06292), category: '카페·음료'),
      ],
    ),
    MarkerEmojiGroup(
      name: '운동·활동',
      hint: '🏃',
      emojis: [
        MarkerEmoji(emoji: '🏃', label: '러닝', color: _exerciseColor, category: '운동·활동'),
        MarkerEmoji(emoji: '🏋️', label: '헬스장', color: Color(0xFF558B2F), category: '운동·활동'),
        MarkerEmoji(emoji: '🧘', label: '요가·명상', color: Color(0xFF7CB342), category: '운동·활동'),
        MarkerEmoji(emoji: '⚽', label: '축구', color: Color(0xFF388E3C), category: '운동·활동'),
        MarkerEmoji(emoji: '🏀', label: '농구', color: Color(0xFFE65100), category: '운동·활동'),
        MarkerEmoji(emoji: '🎳', label: '볼링', color: Color(0xFF4527A0), category: '운동·활동'),
        MarkerEmoji(emoji: '⛳', label: '골프', color: Color(0xFF1B5E20), category: '운동·활동'),
        MarkerEmoji(emoji: '🏊', label: '수영', color: Color(0xFF0277BD), category: '운동·활동'),
        MarkerEmoji(emoji: '🚴', label: '자전거', color: Color(0xFF00838F), category: '운동·활동'),
        MarkerEmoji(emoji: '⛷️', label: '스키·보드', color: Color(0xFF01579B), category: '운동·활동'),
      ],
    ),
    MarkerEmojiGroup(
      name: '문화·취미',
      hint: '🎬',
      emojis: [
        MarkerEmoji(emoji: '🎬', label: '영화관', color: _cultureColor, category: '문화·취미'),
        MarkerEmoji(emoji: '🎭', label: '공연', color: Color(0xFF512DA8), category: '문화·취미'),
        MarkerEmoji(emoji: '🎤', label: '노래방', color: Color(0xFFD81B60), category: '문화·취미'),
        MarkerEmoji(emoji: '🎨', label: '미술관', color: Color(0xFFFF7043), category: '문화·취미'),
        MarkerEmoji(emoji: '📚', label: '도서관·서점', color: _studyColor, category: '문화·취미'),
        MarkerEmoji(emoji: '🎮', label: '게임·오락', color: Color(0xFF1976D2), category: '문화·취미'),
        MarkerEmoji(emoji: '🎸', label: '음악·악기', color: Color(0xFF6A1B9A), category: '문화·취미'),
        MarkerEmoji(emoji: '🎵', label: '콘서트', color: Color(0xFFAD1457), category: '문화·취미'),
        MarkerEmoji(emoji: '📷', label: '포토스팟', color: Color(0xFF5D4037), category: '문화·취미'),
      ],
    ),
    MarkerEmojiGroup(
      name: '쇼핑·일상',
      hint: '🛍️',
      emojis: [
        MarkerEmoji(emoji: '🛍️', label: '쇼핑몰', color: _shopColor, category: '쇼핑·일상'),
        MarkerEmoji(emoji: '🛒', label: '마트·시장', color: Color(0xFF8E24AA), category: '쇼핑·일상'),
        MarkerEmoji(emoji: '🏪', label: '편의점', color: Color(0xFF00897B), category: '쇼핑·일상'),
        MarkerEmoji(emoji: '🏠', label: '집·동네', color: Color(0xFF26A69A), category: '쇼핑·일상'),
        MarkerEmoji(emoji: '💼', label: '업무·회사', color: _workColor, category: '쇼핑·일상'),
        MarkerEmoji(emoji: '🏫', label: '학교', color: Color(0xFF1565C0), category: '쇼핑·일상'),
        MarkerEmoji(emoji: '🏨', label: '호텔·숙소', color: Color(0xFF455A64), category: '쇼핑·일상'),
        MarkerEmoji(emoji: '🏥', label: '병원', color: _healthColor, category: '쇼핑·일상'),
        MarkerEmoji(emoji: '💊', label: '약국', color: Color(0xFFD32F2F), category: '쇼핑·일상'),
        MarkerEmoji(emoji: '⛪', label: '교회·종교', color: Color(0xFF5D4037), category: '쇼핑·일상'),
      ],
    ),
    MarkerEmojiGroup(
      name: '여행·자연',
      hint: '🌳',
      emojis: [
        MarkerEmoji(emoji: '🌳', label: '공원', color: _natureColor, category: '여행·자연'),
        MarkerEmoji(emoji: '🌸', label: '꽃·정원', color: Color(0xFFE91E63), category: '여행·자연'),
        MarkerEmoji(emoji: '⛰️', label: '산·등산', color: Color(0xFF4E342E), category: '여행·자연'),
        MarkerEmoji(emoji: '🏖️', label: '해변', color: Color(0xFFFFD54F), category: '여행·자연'),
        MarkerEmoji(emoji: '🌅', label: '일출·일몰', color: Color(0xFFFF7043), category: '여행·자연'),
        MarkerEmoji(emoji: '🚗', label: '드라이브', color: _travelColor, category: '여행·자연'),
        MarkerEmoji(emoji: '✈️', label: '공항·여행', color: Color(0xFF0288D1), category: '여행·자연'),
        MarkerEmoji(emoji: '🚇', label: '지하철·역', color: Color(0xFF1565C0), category: '여행·자연'),
        MarkerEmoji(emoji: '🏝️', label: '섬·휴양', color: Color(0xFF00ACC1), category: '여행·자연'),
      ],
    ),
    MarkerEmojiGroup(
      name: '이벤트·기념',
      hint: '🎉',
      emojis: [
        MarkerEmoji(emoji: '🎉', label: '파티', color: _eventColor, category: '이벤트·기념'),
        MarkerEmoji(emoji: '🎂', label: '생일', color: Color(0xFFEC407A), category: '이벤트·기념'),
        MarkerEmoji(emoji: '💒', label: '결혼식', color: Color(0xFFF8BBD0), category: '이벤트·기념'),
        MarkerEmoji(emoji: '🎁', label: '선물·기념일', color: Color(0xFFC2185B), category: '이벤트·기념'),
        MarkerEmoji(emoji: '🐕', label: '반려동물', color: Color(0xFF8D6E63), category: '이벤트·기념'),
        MarkerEmoji(emoji: '🌟', label: '특별한 추억', color: _otherColor, category: '이벤트·기념'),
      ],
    ),
  ];

  /// 모든 이모지를 단일 리스트로 펼침 (기존 API 호환)
  static List<MarkerEmoji> get options =>
      groups.expand((g) => g.emojis).toList();

  /// emoji 문자열 → 카탈로그 MarkerEmoji (없으면 첫 항목)
  static MarkerEmoji fromEmoji(String? emoji) {
    if (emoji == null || emoji.isEmpty) return options.first;
    for (final g in groups) {
      for (final e in g.emojis) {
        if (e.emoji == emoji) return e;
      }
    }
    return options.first;
  }

  /// emoji → 색상 (markerColor 저장용)
  static Color colorOf(String? emoji) => fromEmoji(emoji).color;

  /// 기본 이모지
  static String get defaultEmoji => groups.first.emojis.first.emoji;

  // ── 자동 카테고리 추천 (제목/장소 키워드 → 이모지) ──────────────────────
  /// 한국어 키워드 매칭 사전 — 가장 먼저 매칭되는 항목 우선
  /// (긴 키워드를 위에 두면 부분 충돌 회피)
  static const Map<String, String> _keywordMap = {
    // ── 음식 ────────────────────────────────────────────────────────────────
    '피자': '🍕', '버거': '🍔', '햄버거': '🍔',
    'pizza': '🍕', 'burger': '🍔',
    '초밥': '🍣', '스시': '🍣', '회': '🍣', '일식': '🍣',
    'sushi': '🍣',
    '라멘': '🍜', '우동': '🍜', '국수': '🍜', '냉면': '🍜', '면': '🍜', '쌀국수': '🍜', '짜장': '🍜', '짬뽕': '🍜',
    'ramen': '🍜', 'pho': '🍜', 'noodle': '🍜',
    '도시락': '🍱', '벤또': '🍱',
    '삼겹': '🥩', '갈비': '🥩', '고기': '🥩', '소고기': '🥩', '돼지': '🥩', '한우': '🥩', '족발': '🥩',
    'bbq': '🥩', 'steak': '🥩',
    '치킨': '🍗', '닭': '🍗', '교촌': '🍗', 'BBQ': '🍗', 'BHC': '🍗', '굽네': '🍗', '네네': '🍗',
    'chicken': '🍗',
    '디저트': '🍰', '케이크': '🍰', '와플': '🍰', '마카롱': '🍰', '크로플': '🍰',
    'cake': '🍰', 'dessert': '🍰',
    '빵': '🍩', '베이커리': '🍩', '도넛': '🍩', '파리바게뜨': '🍩', '뚜레쥬르': '🍩', '크로와상': '🍩',
    'bakery': '🍩', 'bread': '🍩',
    '아이스크림': '🍦', '젤라또': '🍦', '베스킨라빈스': '🍦', '배스킨': '🍦',
    '한식': '🥘', '백반': '🥘', '국밥': '🥘', '찌개': '🥘', '보쌈': '🥘', '비빔밥': '🥘', '김치찌개': '🥘', '된장': '🥘', '맛집': '🥘',
    // ── 카페·음료 ───────────────────────────────────────────────────────────
    '카페': '☕', '커피': '☕', '아메리카노': '☕', '라떼': '☕', '에스프레소': '☕',
    'cafe': '☕', 'coffee': '☕',
    '스타벅스': '☕', 'starbucks': '☕', '스벅': '☕',
    '이디야': '☕', '투썸': '☕', '커피빈': '☕', '메가커피': '☕', '컴포즈': '☕', '폴바셋': '☕',
    '버블티': '🧋', '밀크티': '🧋', '공차': '🧋',
    '맥주': '🍺', '생맥': '🍺', '맥주집': '🍺',
    'beer': '🍺',
    '호프': '🍻', '술집': '🍻', '포차': '🍻', '주점': '🍻', '술': '🍻',
    '와인': '🍷', '와인바': '🍷',
    'wine': '🍷',
    '위스키': '🥃', '바': '🥃', '하이볼': '🥃',
    'whisky': '🥃', 'highball': '🥃',
    '칵테일': '🍹', '모히토': '🍹',
    'cocktail': '🍹',
    // ── 운동 ────────────────────────────────────────────────────────────────
    '러닝': '🏃', '조깅': '🏃', '산책': '🏃', '걷기': '🏃',
    'running': '🏃', 'jogging': '🏃',
    '헬스': '🏋️', '짐': '🏋️', '웨이트': '🏋️', '크로스핏': '🏋️',
    'gym': '🏋️', 'crossfit': '🏋️',
    '요가': '🧘', '필라테스': '🧘', '명상': '🧘',
    'yoga': '🧘', 'pilates': '🧘',
    '축구': '⚽', '풋살': '⚽',
    'soccer': '⚽',
    '농구': '🏀',
    'basketball': '🏀',
    '볼링': '🎳',
    '골프': '⛳',
    'golf': '⛳',
    '수영': '🏊', '풀': '🏊', '워터파크': '🏊',
    '자전거': '🚴', '라이딩': '🚴', '따릉이': '🚴',
    '스키': '⛷️', '보드': '⛷️', '스노보드': '⛷️',
    '클라이밍': '🏋️', '클라이밍짐': '🏋️',
    // ── 문화·취미 ───────────────────────────────────────────────────────────
    '영화': '🎬', '극장': '🎬', 'CGV': '🎬', '메가박스': '🎬', '롯데시네마': '🎬',
    'movie': '🎬', 'cinema': '🎬',
    '공연': '🎭', '뮤지컬': '🎭', '연극': '🎭', '발레': '🎭', '오페라': '🎭',
    '노래방': '🎤', '코노': '🎤', '코인노래방': '🎤',
    '미술관': '🎨', '갤러리': '🎨', '전시': '🎨', '전시회': '🎨',
    '도서관': '📚', '서점': '📚', '북카페': '📚', '교보문고': '📚', '영풍문고': '📚', '독립서점': '📚',
    'library': '📚',
    '게임': '🎮', '오락실': '🎮', 'PC방': '🎮', '플스방': '🎮', '보드게임': '🎮',
    '음악': '🎸', '악기': '🎸', '기타': '🎸', '피아노': '🎸',
    '콘서트': '🎵', '페스티벌': '🎵', '버스킹': '🎵',
    'concert': '🎵',
    '포토': '📷', '사진': '📷', '인생샷': '📷', '뷰': '📷', '뷰포인트': '📷', '야경': '📷',
    'photo': '📷',
    // ── 쇼핑·일상 ──────────────────────────────────────────────────────────
    '쇼핑': '🛍️', '몰': '🛍️', '아울렛': '🛍️', '백화점': '🛍️', '롯데백화점': '🛍️', '신세계': '🛍️', '현대백화점': '🛍️',
    'shopping': '🛍️', 'mall': '🛍️',
    '마트': '🛒', '시장': '🛒', '재래시장': '🛒', '이마트': '🛒', '홈플러스': '🛒', '코스트코': '🛒',
    'market': '🛒',
    '편의점': '🏪', 'CU': '🏪', 'GS25': '🏪', '세븐일레븐': '🏪', '이마트24': '🏪',
    '집': '🏠', '동네': '🏠', '우리집': '🏠', '본가': '🏠',
    'home': '🏠',
    '회사': '💼', '사무실': '💼', '출근': '💼', '미팅': '💼', '오피스': '💼',
    '근무중': '💼', '근무': '💼', '출근중': '💼',
    'office': '💼', 'work': '💼',
    '출장중': '🧳', '출장': '🧳', 'businesstrip': '🧳',
    '휴가중': '🏖️', '휴가': '🏖️', '연차': '🏖️', '월차': '🏖️', 'vacation': '🏖️',
    '학교': '🏫', '학원': '🏫', '대학교': '🏫', '캠퍼스': '🏫', '강의실': '🏫',
    'school': '🏫', 'university': '🏫',
    '호텔': '🏨', '숙소': '🏨', '게스트하우스': '🏨', '에어비앤비': '🏨', '모텔': '🏨', '펜션': '🏨', '리조트': '🏨',
    'hotel': '🏨',
    '병원': '🏥', '치과': '🏥', '내과': '🏥', '한의원': '🏥', '안과': '🏥', '피부과': '🏥',
    'hospital': '🏥',
    '약국': '💊',
    '교회': '⛪', '성당': '⛪', '절': '⛪', '사찰': '⛪', '예배': '⛪',
    // ── 여행·자연 ───────────────────────────────────────────────────────────
    '공원': '🌳', '뚝섬': '🌳', '한강공원': '🌳', '올림픽공원': '🌳', '서울숲': '🌳', '남산': '🌳',
    'park': '🌳',
    '꽃': '🌸', '벚꽃': '🌸', '단풍': '🌸', '튤립': '🌸', '장미': '🌸',
    'flower': '🌸',
    '산': '⛰️', '등산': '⛰️', '북한산': '⛰️', '관악산': '⛰️', '한라산': '⛰️', '설악산': '⛰️', '지리산': '⛰️',
    'mountain': '⛰️', 'hiking': '⛰️',
    '바다': '🏖️', '해변': '🏖️', '비치': '🏖️', '해수욕장': '🏖️', '경포대': '🏖️', '광안리': '🏖️', '해운대': '🏖️',
    'beach': '🏖️', 'sea': '🏖️',
    '일출': '🌅', '일몰': '🌅', '석양': '🌅', '선셋': '🌅',
    'sunset': '🌅', 'sunrise': '🌅',
    '드라이브': '🚗', '여행': '🚗', '로드트립': '🚗',
    'drive': '🚗', 'travel': '🚗',
    '공항': '✈️', '비행기': '✈️', '인천공항': '✈️', '김포공항': '✈️', '제주공항': '✈️',
    'airport': '✈️',
    '지하철': '🚇', '역': '🚇', '강남역': '🚇', '홍대입구역': '🚇', '서울역': '🚇',
    '섬': '🏝️', '휴양': '🏝️', '제주': '🏝️', '울릉도': '🏝️', '발리': '🏝️', '몰디브': '🏝️',
    'island': '🏝️',
    // ── 이벤트·기념 ─────────────────────────────────────────────────────────
    '파티': '🎉', '모임': '🎉', '회식': '🎉', '환영회': '🎉', '송별회': '🎉',
    'party': '🎉',
    '생일': '🎂', 'birthday': '🎂',
    '결혼': '💒', '예식': '💒', '돌잔치': '💒', 'wedding': '💒',
    '선물': '🎁', '기념일': '🎁',
    '반려': '🐕', '강아지': '🐕', '고양이': '🐕', '애견': '🐕', '동물': '🐕',
    'pet': '🐕', 'dog': '🐕', 'cat': '🐕',
  };

  /// 텍스트(제목/장소명)에서 가장 잘 맞는 이모지를 추천.
  /// 매칭되는 키워드가 없으면 null 반환.
  static String? suggestFor(String text) {
    if (text.trim().isEmpty) return null;
    final lower = text.toLowerCase();
    for (final entry in _keywordMap.entries) {
      if (lower.contains(entry.key.toLowerCase())) return entry.value;
    }
    return null;
  }
}
