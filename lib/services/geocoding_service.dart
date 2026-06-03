import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:http/http.dart' as http;

/// 좌표 → 도로명 주소 역지오코딩 (웹/모바일 공용)
///
/// Nominatim(OSM) 사용 — API 키 불필요, 도로명(road) + 번지 우선.
/// 웹에서도 동작하도록 `package:http` 사용 (CORS 허용됨).
class GeocodingService {
  /// 위경도 → "시/도 시/군/구 도로명 번지" 형태 (실패 시 null)
  static Future<String?> reverseToRoadAddress(double lat, double lng) async {
    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/reverse', {
        'lat': '$lat',
        'lon': '$lng',
        'format': 'json',
        'accept-language': 'ko',
        'zoom': '18', // street-level
        'addressdetails': '1',
      });
      final res = await http.get(uri, headers: {
        // OSM 정책상 User-Agent 권장 (웹은 브라우저가 자동 세팅)
        if (!kIsWeb) 'User-Agent': 'PinFlick/1.0 (https://pinflick.web.app)',
        'Accept-Language': 'ko',
      }).timeout(const Duration(seconds: 8));

      if (res.statusCode != 200) return null;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      if (data['error'] != null) return null;
      final addr = data['address'] as Map<String, dynamic>?;
      if (addr == null) return null;

      final road = addr['road'] as String?;
      final houseNo = addr['house_number'] as String?;
      final neighbourhood = (addr['neighbourhood'] ??
          addr['suburb'] ??
          addr['quarter']) as String?;
      final city = (addr['city'] ??
          addr['county'] ??
          addr['town'] ??
          addr['borough']) as String?;
      final district =
          (addr['city_district'] ?? addr['district']) as String?;
      final province = (addr['province'] ?? addr['state']) as String?;

      final parts = <String>[];
      if (province != null && province.isNotEmpty) parts.add(province);
      if (city != null && city.isNotEmpty) parts.add(city);
      if (district != null &&
          district.isNotEmpty &&
          district != city) {
        parts.add(district);
      }
      if (road != null && road.isNotEmpty) {
        parts.add(road);
        if (houseNo != null && houseNo.isNotEmpty) parts.add(houseNo);
      } else if (neighbourhood != null && neighbourhood.isNotEmpty) {
        parts.add(neighbourhood);
      }

      if (parts.isEmpty) {
        // 최후의 fallback — display_name 앞부분
        final display = data['display_name'] as String?;
        return display;
      }
      final result = parts.join(' ');
      debugPrint('[Geocoding] → $result');
      return result;
    } catch (e) {
      debugPrint('[Geocoding] 오류: $e');
      return null;
    }
  }

  /// 좌표 → 행정동/법정동 단위만 (예: "청계동", "사직동")
  /// 장소·브랜드 미입력 시 placeName fallback 용
  static Future<String?> reverseToNeighbourhood(
      double lat, double lng) async {
    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/reverse', {
        'lat': '$lat',
        'lon': '$lng',
        'format': 'json',
        'accept-language': 'ko',
        'zoom': '16', // 동 단위
        'addressdetails': '1',
      });
      final res = await http.get(uri, headers: {
        if (!kIsWeb) 'User-Agent': 'PinFlick/1.0 (https://pinflick.web.app)',
        'Accept-Language': 'ko',
      }).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return null;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final addr = data['address'] as Map<String, dynamic>?;
      if (addr == null) return null;
      // 동/읍/면 우선순위
      final dong = (addr['neighbourhood'] ??
          addr['quarter'] ??
          addr['suburb'] ??
          addr['village'] ??
          addr['town'] ??
          addr['city_district'] ??
          addr['borough']) as String?;
      return (dong != null && dong.isNotEmpty) ? dong : null;
    } catch (e) {
      debugPrint('[Geocoding] dong 오류: $e');
      return null;
    }
  }

  /// 주소 텍스트 → 좌표 (forward geocoding) — 단일 최상위 결과
  static Future<({double lat, double lng, String display})?> forwardGeocode(
      String query) async {
    final list = await searchAddresses(query);
    if (list.isEmpty) return null;
    final f = list.first;
    return (lat: f.lat, lng: f.lng, display: f.display);
  }

  /// 주소 검색 — 다중 결과 (자동완성 리스트용)
  static Future<List<({double lat, double lng, String display})>>
      searchAddresses(String query) async {
    if (query.trim().isEmpty) return [];
    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
        'q': query,
        'format': 'json',
        'accept-language': 'ko',
        'limit': '6',
        'addressdetails': '1',
        // countrycodes 제거 — kr 제한이 일부 검색을 막음. 결과는 한국어 우선.
      });
      final res = await http.get(uri, headers: {
        if (!kIsWeb) 'User-Agent': 'PinFlick/1.0 (https://pinflick.web.app)',
        'Accept-Language': 'ko',
      }).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return [];
      final list = jsonDecode(res.body) as List<dynamic>;
      final out = <({double lat, double lng, String display})>[];
      for (final item in list) {
        final m = item as Map<String, dynamic>;
        final lat = double.tryParse(m['lat']?.toString() ?? '');
        final lng = double.tryParse(m['lon']?.toString() ?? '');
        if (lat == null || lng == null) continue;
        final display = m['display_name'] as String? ?? query;
        out.add((lat: lat, lng: lng, display: display));
      }
      return out;
    } catch (e) {
      debugPrint('[Geocoding] search 오류: $e');
      return [];
    }
  }
}
