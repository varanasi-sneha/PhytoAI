import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../auth_service.dart';
import 'cache_service.dart';

class LocalProfileService {
  final CacheService _cache;
  final AuthService _auth;
  static const String _key = 'profile';

  LocalProfileService({required CacheService cache, required AuthService auth})
      : _cache = cache,
        _auth = auth;

  Future<Map<String, dynamic>> getProfile() async {
    final cached = _cache.get(_key);
    if (cached is Map<String, dynamic>) {
      return Map<String, dynamic>.from(cached);
    }

    final user = _auth.currentUser;
    final profile = {
      'email': user?.email ?? '',
      'first_name': null,
      'last_name': null,
      'profile_image_path': null,
    };

    await _cacheProfile(profile);
    return profile;
  }

  Future<void> _cacheProfile(Map<String, dynamic> profile) async {
    await _cache.set(_key, profile, ttl: const Duration(days: 3650));
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
    await _cache.remove(_key);
  }
}
