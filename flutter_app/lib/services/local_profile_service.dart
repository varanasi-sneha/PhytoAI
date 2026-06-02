import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../auth_service.dart';
import 'cache_service.dart';

class LocalProfileService {
  final CacheService _cache;
  final AuthService _auth;
  static const String _keyPrefix = 'local_profile';

  LocalProfileService({required CacheService cache, required AuthService auth})
      : _cache = cache,
        _auth = auth;

  String _cacheKey(String userId) => '$_keyPrefix:$userId';

  Future<Map<String, dynamic>> getProfile() async {
    final user = _auth.currentUser;
    final key = _cacheKey(user?.id ?? 'anon');
    final cached = _cache.get(key);
    if (cached is Map<String, dynamic>) {
      return Map<String, dynamic>.from(cached);
    }

    final profile = {
      'email': user?.email ?? '',
      'first_name': null,
      'last_name': null,
      'profile_image_path': null,
    };

    await _cache.set(key, profile, ttl: const Duration(days: 3650));
    return profile;
  }

  Future<void> _cacheProfile(Map<String, dynamic> profile) async {
    final user = _auth.currentUser;
    final key = _cacheKey(user?.id ?? 'anon');
    await _cache.set(key, profile, ttl: const Duration(days: 3650));
  }

  Future<void> updateProfile(String firstName, String lastName) async {
    final profile = await getProfile();
    final user = _auth.currentUser;
    profile['email'] = user?.email ?? profile['email'] ?? '';
    profile['first_name'] = firstName;
    profile['last_name'] = lastName;
    await _cacheProfile(profile);
  }

  Future<String?> updateProfileImage(File imageFile) async {
    final directory = await getApplicationDocumentsDirectory();
    final imageFolder = Directory('${directory.path}/profile_images');
    if (!await imageFolder.exists()) {
      await imageFolder.create(recursive: true);
    }

    final savedFile = File('${imageFolder.path}/profile_photo.png');
    await imageFile.copy(savedFile.path);

    final profile = await getProfile();
    profile['profile_image_path'] = savedFile.path;
    await _cacheProfile(profile);
    return savedFile.path;
  }

  Future<File?> getProfileImageFile() async {
    final profile = await getProfile();
    final path = profile['profile_image_path'] as String?;
    if (path == null) return null;
    final file = File(path);
    return await file.exists() ? file : null;
  }

  Future<void> clear() async {
    final user = _auth.currentUser;
    final key = _cacheKey(user?.id ?? 'anon');
    await _cache.remove(key);
  }

  Future<void> clearProfile() async {
    final file = await getProfileImageFile();
    if (file != null && await file.exists()) {
      try {
        await file.delete();
      } catch (_) {
        // Ignore deletion failures for local cleanup.
      }
    }
    await clear();
  }
}
