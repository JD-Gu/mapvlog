/// 장소명 + 주소를 직관적으로 결합 (피드 카드·플레이어 공용)
///
/// 예) placeName="양천구청", address="서울특별시 양천구 목동동로 105"
///     → "양천구청 · 양천구 목동동로 105" (시/도 prefix 정리, 중복 시 생략)
String combinedLocationLabel(String placeName, String? address) {
  final place = placeName.trim();
  var addr = (address ?? '').trim();
  if (addr.isEmpty) return place;

  const provinces = [
    '서울특별시', '부산광역시', '대구광역시', '인천광역시', '광주광역시',
    '대전광역시', '울산광역시', '세종특별자치시', '경기도', '강원특별자치도',
    '강원도', '충청북도', '충청남도', '전북특별자치도', '전라북도',
    '전라남도', '경상북도', '경상남도', '제주특별자치도', '제주도',
  ];
  for (final p in provinces) {
    if (addr.startsWith('$p ')) {
      addr = addr.substring(p.length + 1);
      break;
    }
  }

  if (place.isEmpty) return addr;
  if (addr.contains(place)) return addr;
  if (place.contains(addr)) return place;
  return '$place · $addr';
}
