import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/media_item.dart';

/// MediaItem 로컬 저장/조회 서비스 (SharedPreferences 기반)
/// 마일스톤 7에서 Firestore로 교체 예정
class MediaStorageService {
  static const _key = 'media_items';

  /// 아이템 저장 (신규 추가)
  static Future<void> save(MediaItem item) async {
    final prefs = await SharedPreferences.getInstance();
    final list = await loadAll();
    // 같은 id가 있으면 덮어쓰기
    final updated = [
      item,
      ...list.where((e) => e.id != item.id),
    ];
    await prefs.setStringList(
      _key,
      updated.map((e) => e.toJsonString()).toList(),
    );
  }

  /// 특정 아이템 업데이트 (remoteUrl 등)
  static Future<void> update(MediaItem item) => save(item);

  /// 전체 목록 최신순 반환
  static Future<List<MediaItem>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? [];
    return raw
        .map((s) =>
            MediaItem.fromJson(jsonDecode(s) as Map<String, dynamic>))
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  /// GPS 태그된 아이템만 반환
  static Future<List<MediaItem>> loadGeotagged() async {
    final all = await loadAll();
    return all.where((e) => e.hasGps).toList();
  }

  /// 아이템 삭제
  static Future<void> delete(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final list = await loadAll();
    await prefs.setStringList(
      _key,
      list.where((e) => e.id != id).map((e) => e.toJsonString()).toList(),
    );
  }

  /// 전체 삭제
  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
