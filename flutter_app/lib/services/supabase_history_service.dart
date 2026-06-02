import 'package:flutter/foundation.dart';
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

  static const _remoteKeyPrefix = 'supabase_history';
  static const _table = 'scan_history';

  SupabaseHistoryService({
    required CacheService cache,
    required LocalHistoryService localHistoryService,
  })  : _cache = cache,
        _local = localHistoryService,
        _auth = AuthService(),
        _network = NetworkService();

  String? get _userId => _auth.currentUser?.id;

  // Save — local first, then remote.
  Future<void> saveHistoryItem(Map<String, dynamic> item) async {
    final id = item['id']?.toString().isNotEmpty == true
        ? item['id'].toString()
        : _local.makeId();
    final enriched = Map<String, dynamic>.from(item)..['id'] = id;

    await _local.addHistoryItem(enriched);

    try {
      final uid = _userId;
      if (uid == null) return;

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
        'user_id': uid,
      });
      
      await _cache.remove('$_remoteKeyPrefix:$uid');
    } catch (e, st) {
      debugPrint('saveHistoryItem error: $e\n$st');
      // Offline or unauthenticated — local write already succeeded.
    }
  }

  // Fetch — remote with 5-min cache, fallback to local.
  // Returns List<Map> with keys: id, prediction, display_name,
  // confidence, plant_type, created_at  (same shape as LocalHistoryService).
  Future<List<Map<String, dynamic>>> getHistory() async {
    try {
      final uid = _userId;
      
      if (uid == null) return _local.getHistory();

      await _network.ensureConnected();

      final cacheKey = '$_remoteKeyPrefix:$uid';
      final cached = _cache.get(cacheKey);
      if (cached is List && cached.isNotEmpty) {
        return List<Map<String, dynamic>>.from(
          cached.map((e) => Map<String, dynamic>.from(e as Map)),
        );
      }
      if (cached is List) {
        return List<Map<String, dynamic>>.from(
          cached.map((e) => Map<String, dynamic>.from(e as Map)),
        );
      }

      final rows = await _client
          .from(_table)
          .select(
              'id, prediction, display_name, confidence, plant_type, created_at')
          .eq('user_id', uid)
          .order('created_at', ascending: false);

      final result = List<Map<String, dynamic>>.from(
        (rows as List).map((e) => Map<String, dynamic>.from(e as Map)),
      );

      

      if (result.isNotEmpty) {
        await _cache.set(cacheKey, result, ttl: const Duration(minutes: 5));
        return result;
      }

      final localRows = await _local.getHistory();
      return localRows;
    } catch (e, st) {
      debugPrint('getHistory error: $e\n$st');
      return _local.getHistory();
    }
  }

  Future<void> deleteHistoryItem(String id) async {
    await _local.deleteHistoryItem(id);
    final normalizedId = id.trim();
    if (normalizedId.isEmpty || normalizedId == 'null') return;

    try {
      final uid = _userId;
      if (uid == null) return;

      await _network.ensureConnected();
      await _client.from(_table).delete().eq('id', normalizedId).eq('user_id', uid);
      await _cache.remove('$_remoteKeyPrefix:$uid');
    } catch (e, st) {
      debugPrint('deleteHistoryItem error: $e\n$st');
    }
  }

  Future<void> clearHistory() async {
    await _local.clearHistory();
    try {
      final uid = _userId;
      if (uid == null) return;

      await _network.ensureConnected();
      await _client.from(_table).delete().eq('user_id', uid);
      await _cache.remove('$_remoteKeyPrefix:$uid');
    } catch (e, st) {
      debugPrint('clearHistory error: $e\n$st');
    }
  }
}