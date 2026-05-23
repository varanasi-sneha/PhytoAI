import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth_service.dart';
import 'cache_service.dart';
import 'local_profile_service.dart';
import 'network_service.dart';

class SupabaseProfileService {
  final SupabaseClient _client = Supabase.instance.client;
  final AuthService _auth;
  final CacheService _cache;
  final LocalProfileService _local;
  final NetworkService _network;

  static const _table = 'profiles';
  static const _bucket = 'profile-photos';
  static const _cacheKey = 'supabase_profile';

  SupabaseProfileService({required CacheService cache})
      : _cache = cache,
        _auth = AuthService(),
        _network = NetworkService(),
        // LocalProfileService needs the same CacheService + AuthService
        // instances so they share the same underlying SharedPreferences state.
        _local = LocalProfileService(cache: cache, auth: AuthService());

  String get _userId => _auth.currentUser!.id;

  // ---------------------------------------------------------------------------
  // Fetch profile
  // Returns Map with keys: email, first_name, last_name, avatar_url.
  // Online  → Supabase `profiles` table (10-min cache).
  // Offline → LocalProfileService map, re-keyed to match the same shape
  //           (local uses 'profile_image_path', we expose it as 'avatar_url').
  // ---------------------------------------------------------------------------
  Future<Map<String, dynamic>> getProfile() async {
    try {
      await _network.ensureConnected();

      final cached = _cache.get(_cacheKey);
      if (cached is Map) {
        return Map<String, dynamic>.from(cached);
      }

      final rows = await _client
          .from(_table)
          .select('email, first_name, last_name, avatar_url')
          .eq('user_id', _userId)
          .limit(1);

      if (rows == null || (rows as List).isEmpty) {
        // No remote row yet — fall back to local so the screen isn't empty.
        return _localProfileAsMap();
      }

      final profile = Map<String, dynamic>.from(rows.first as Map);
      await _cache.set(_cacheKey, profile, ttl: const Duration(minutes: 10));
      return profile;
    } catch (_) {
      // Offline — use local data.
      return _localProfileAsMap();
    }
  }

  /// Reads the LocalProfileService map and normalises it to the same shape
  /// the rest of the app expects from getProfile():
  ///   email, first_name, last_name, avatar_url
  Future<Map<String, dynamic>> _localProfileAsMap() async {
    final local = await _local.getProfile();
    return {
      'email': local['email'],
      'first_name': local['first_name'],
      'last_name': local['last_name'],
      // Local stores the path under 'profile_image_path'; callers use 'avatar_url'.
      'avatar_url': local['profile_image_path'],
    };
  }

  // ---------------------------------------------------------------------------
  // Update name — local first, then remote upsert.
  // ---------------------------------------------------------------------------
  Future<void> updateProfile(String firstName, String lastName) async {
    await _local.updateProfile(firstName, lastName);

    try {
      await _network.ensureConnected();
      await _client.from(_table).upsert(
        {
          'user_id': _userId,
          'email': _auth.currentUser?.email,
          'first_name': firstName,
          'last_name': lastName,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        onConflict: 'user_id',
      );
      await _cache.remove(_cacheKey);
    } catch (_) {
      // Offline — local write already done.
    }
  }

  // ---------------------------------------------------------------------------
  // Upload profile photo.
  // Always saves locally first. Returns public URL on success, null if offline.
  // ---------------------------------------------------------------------------
  Future<String?> updateProfileImage(File imageFile) async {
    // Always keep a local copy regardless of connectivity.
    await _local.updateProfileImage(imageFile);

    try {
      await _network.ensureConnected();

      final path = '$_userId/profile.png';
      final bytes = await imageFile.readAsBytes();

      await _client.storage.from(_bucket).uploadBinary(
            path,
            bytes,
            fileOptions:
                const FileOptions(upsert: true, contentType: 'image/png'),
          );

      final publicUrl = _client.storage.from(_bucket).getPublicUrl(path);

      await _client.from(_table).upsert(
        {
          'user_id': _userId,
          'email': _auth.currentUser?.email,
          'avatar_url': publicUrl,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        onConflict: 'user_id',
      );

      await _cache.remove(_cacheKey);
      return publicUrl;
    } catch (_) {
      return null; // Offline — caller uses the local file.
    }
  }

  Future<String?> getProfileImageUrl() async {
    final profile = await getProfile();
    return profile['avatar_url'] as String?;
  }
}