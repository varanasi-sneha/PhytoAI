import 'dart:math';

import 'cache_service.dart';

class LocalHistoryService {
  final CacheService _cache;
  static const String _key = 'history';

  LocalHistoryService({required CacheService cache}) : _cache = cache;

  Future<List<Map<String, dynamic>>> getHistory() async {
    final cached = _cache.get(_key);
    if (cached is List) return List<Map<String, dynamic>>.from(cached);
    return <Map<String, dynamic>>[];
  }

  Future<void> addHistoryItem(Map<String, dynamic> item) async {
    final list = await getHistory();
    // Prepend newest
    list.insert(0, item);
    // Keep reasonable limit
    if (list.length > 500) list.removeRange(500, list.length);
    await _cache.set(_key, list, ttl: const Duration(days: 365 * 10));
  }

  Future<void> deleteHistoryItem(String id) async {
    final list = await getHistory();
    list.removeWhere((e) => (e['id']?.toString() ?? '') == id);
    await _cache.set(_key, list, ttl: const Duration(days: 365 * 10));
  }

  Future<void> clearHistory() async {
    await _cache.remove(_key);
  }

  String makeId() {
    final rand = Random();
    return DateTime.now().millisecondsSinceEpoch.toString() + '-' + rand.nextInt(999999).toString();
  }
}
