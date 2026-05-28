import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth_service.dart';
import 'cache_service.dart';
import 'local_history_service.dart';
import 'network_service.dart';

class SupabaseHistoryService {
  final SupabaseClient _client = Supabase.instance.client;
  final AuthService _auth;
  final CacheService _cache;
  final LocalHistoryService _local;
  final NetworkService _network;

  static const _remoteKey = 'supabase_history';
  static const _table = 'scan_history';

  SupabaseHistoryService({
    required CacheService cache,
    required LocalHistoryService localHistoryService,
  })  : _cache = cache,
        _local = localHistoryService,
        _auth = AuthService(),
        _network = NetworkService();

  String get _userId => _auth.currentUser!.id;

  // Save — local first, then remote.
  Future<void> saveHistoryItem(Map<String, dynamic> item) async {
    final id = item['id']?.toString().isNotEmpty == true
        ? item['id'].toString()
        : _local.makeId();
    final enriched = Map<String, dynamic>.from(item)..['id'] = id;

    await _local.addHistoryItem(enriched);

    try {
      await _network.ensureConnected();
      await _client.from(_table).insert({
        'id': id,
        'prediction': enriched['prediction'],
        'display_name': enriched['display_name'],
        'plant_type': enriched['plant_type'],
        'confidence': enriched['confidence'],
        'image_url': enriched['image_url'],
        'created_at':
            enriched['created_at'] ?? DateTime.now().toUtc().toIso8601String(),
        'user_id': _userId,
      });
      await _cache.remove(_remoteKey);
    } catch (_) {
      // Offline — local write already succeeded.
    }
  }

  // Fetch — remote with 5-min cache, fallback to local.
  // Returns List<Map> with keys: id, prediction, display_name,
  // confidence, plant_type, created_at  (same shape as LocalHistoryService).
  Future<List<Map<String, dynamic>>> getHistory() async {
    try {
      await _network.ensureConnected();

      final cached = _cache.get(_remoteKey);
      if (cached is List) {
        return List<Map<String, dynamic>>.from(
          cached.map((e) => Map<String, dynamic>.from(e as Map)),
        );
      }

      final rows = await _client
          .from(_table)
          .select(
              'id, prediction, display_name, confidence, plant_type, created_at')
          .eq('user_id', _userId)
          .order('created_at', ascending: false);

      final result = List<Map<String, dynamic>>.from(
        (rows as List).map((e) => Map<String, dynamic>.from(e as Map)),
      );

      await _cache.set(_remoteKey, result, ttl: const Duration(minutes: 5));
      return result;
    } catch (_) {
      return _local.getHistory();
    }
  }

  Future<void> deleteHistoryItem(String id) async {
    await _local.deleteHistoryItem(id);
    try {
      await _network.ensureConnected();
      await _client.from(_table).delete().eq('id', id).eq('user_id', _userId);
      await _cache.remove(_remoteKey);
    } catch (_) {}
  }

  Future<void> clearHistory() async {
    await _local.clearHistory();
    try {
      await _network.ensureConnected();
      await _client.from(_table).delete().eq('user_id', _userId);
      await _cache.remove(_remoteKey);
    } catch (_) {}
  }
}