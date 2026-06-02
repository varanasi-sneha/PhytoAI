import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'cache_service.dart';

class LocalHistoryService extends ChangeNotifier {
  final CacheService _cache;
  static const String _key = 'history';
  static final Uuid _uuid = Uuid();

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
    notifyListeners();
  }

  Future<void> deleteHistoryItem(String id) async {
    final list = await getHistory();
    list.removeWhere((e) => (e['id']?.toString() ?? '') == id);
    await _cache.set(_key, list, ttl: const Duration(days: 365 * 10));
    notifyListeners();
  }

  Future<void> clearHistory() async {
    await _cache.remove(_key);
    notifyListeners();
  }

  String makeId() {
    return _uuid.v4();
  }
}
