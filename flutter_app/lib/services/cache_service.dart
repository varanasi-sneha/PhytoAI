import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class CacheService {
  late final SharedPreferences _prefs;
  static const String _prefix = 'phyto_cache:';
  static const String _expirySuffix = ':expiry';

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  String _dataKey(String key) => '$_prefix$key';
  String _expiryKey(String key) => '${_dataKey(key)}$_expirySuffix';

  Future<void> set(String key, Object value, {Duration ttl = const Duration(hours: 1)}) async {
    final jsonString = json.encode(value);
    await _prefs.setString(_dataKey(key), jsonString);
    await _prefs.setInt(_expiryKey(key), DateTime.now().add(ttl).millisecondsSinceEpoch);
  }

  dynamic get(String key) {
    final expiry = _prefs.getInt(_expiryKey(key));
    if (expiry == null || expiry < DateTime.now().millisecondsSinceEpoch) {
      remove(key);
      return null;
    }

    final raw = _prefs.getString(_dataKey(key));
    if (raw == null) return null;
    try {
      return json.decode(raw);
    } catch (_) {
      remove(key);
      return null;
    }
  }

  Future<void> remove(String key) async {
    await _prefs.remove(_dataKey(key));
    await _prefs.remove(_expiryKey(key));
  }

  Future<void> clearAll() async {
    final keys = _prefs.getKeys().where((k) => k.startsWith(_prefix)).toList();
    for (final key in keys) {
      await _prefs.remove(key);
    }
  }
}
