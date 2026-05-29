import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'auth_service.dart';
import 'config/app_config.dart';
import 'services/cache_service.dart';
import 'services/error_service.dart';
import 'services/network_service.dart';


class ApiService {
  final String baseUrl = AppConfig.apiBaseUrl;
  final AuthService _authService;
  final CacheService _cacheService;
  final NetworkService _networkService;

  ApiService(this._authService, this._cacheService, this._networkService);

  Map<String, String> _getAuthHeaders() {
    final token = _authService.getAccessToken();
    return {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };
  }

  /// Uploads an image file to the plant disease detection API.
  Future<Map<String, dynamic>> uploadImage(File imageFile) async {
    final url = Uri.parse('$baseUrl/api/predict/');
    final request = http.MultipartRequest('POST', url);

    try {
      await _networkService.ensureConnected();
      final token = _authService.getAccessToken();
      if (token != null) {
        request.headers['Authorization'] = 'Bearer $token';
      }

      final multipartFile = await http.MultipartFile.fromPath(
        'image',
        imageFile.path,
      );

      request.files.add(multipartFile);

      final streamedResponse = await request.send();
      final responseString = await streamedResponse.stream.bytesToString();

      if (streamedResponse.statusCode != 200) {
        throw HttpException(
          'Upload failed with status ${streamedResponse.statusCode}: $responseString',
        );
      }

      final decoded = json.decode(responseString);
      if (decoded is! Map<String, dynamic>) {
        throw FormatException('API returned unexpected JSON structure.');
      }

      return decoded;
    } catch (error) {
      throw ErrorService.parse(error);
    }
  }

  /// Fetches user's prediction history.
  Future<List<Map<String, dynamic>>> getHistory() async {
    final cacheKey = 'history';
    final cached = _cacheService.get(cacheKey);
    if (cached is List) {
      return List<Map<String, dynamic>>.from(cached);
    }

    try {
      await _networkService.ensureConnected();
      final url = Uri.parse('$baseUrl/api/history');
      final response = await http.get(url, headers: _getAuthHeaders());

      if (response.statusCode != 200) {
        throw HttpException('Failed to fetch history: ${response.body}');
      }

      final decoded = json.decode(response.body);
      if (decoded is! List) {
        throw FormatException('Unexpected history response format');
      }

      _cacheService.set(cacheKey, decoded, ttl: const Duration(minutes: 45));
      return List<Map<String, dynamic>>.from(decoded);
    } catch (error) {
      final appError = ErrorService.parse(error);
      if (appError.fallbackAllowed && cached is List) {
        return List<Map<String, dynamic>>.from(cached);
      }
      throw appError;
    }
  }

  /// Fetches prevention data for a disease.
  Future<Map<String, dynamic>> getPrevention(String diseaseName) async {
    final cacheKey = 'prevention:$diseaseName';
    final cached = _cacheService.get(cacheKey);
    if (cached is Map<String, dynamic>) {
      return cached;
    }

    try {
      await _networkService.ensureConnected();
      final url = Uri.parse('$baseUrl/api/prevention');
      final response = await http.post(
        url,
        headers: _getAuthHeaders(),
        body: json.encode({'disease_name': diseaseName}),
      );

      if (response.statusCode != 200) {
        throw HttpException('Failed to fetch prevention: ${response.body}');
      }

      final decoded = json.decode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw FormatException('Unexpected prevention response format');
      }

      _cacheService.set(cacheKey, decoded, ttl: const Duration(days: 1));
      return decoded;
    } catch (error) {
      final appError = ErrorService.parse(error);
      if (appError.fallbackAllowed && cached is Map<String, dynamic>) {
        return cached;
      }
      throw appError;
    }
  }

  /// Fetches user profile.
  Future<Map<String, dynamic>> getProfile() async {
    final cacheKey = 'profile';
    final cached = _cacheService.get(cacheKey);
    if (cached is Map<String, dynamic>) {
      return cached;
    }

    try {
      await _networkService.ensureConnected();
      final url = Uri.parse('$baseUrl/api/profile');
      final response = await http.get(url, headers: _getAuthHeaders());

      if (response.statusCode != 200) {
        throw HttpException('Failed to fetch profile: ${response.body}');
      }

      final decoded = json.decode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw FormatException('Unexpected profile response format');
      }

      _cacheService.set(cacheKey, decoded, ttl: const Duration(hours: 6));
      return decoded;
    } catch (error) {
      final appError = ErrorService.parse(error);
      if (appError.fallbackAllowed && cached is Map<String, dynamic>) {
        return cached;
      }
      throw appError;
    }
  }

  /// Updates user profile.
  Future<void> updateProfile(String firstName, String lastName) async {
    await _networkService.ensureConnected();
    final url = Uri.parse('$baseUrl/api/update-profile');
    final response = await http.post(
      url,
      headers: _getAuthHeaders(),
      body: json.encode({
        'first_name': firstName,
        'last_name': lastName,
      }),
    );

    if (response.statusCode != 200) {
      throw HttpException('Failed to update profile: ${response.body}');
    }

    await _cacheService.remove('profile');
  }

  /// Classifies a drug/compound.
  Future<Map<String, dynamic>> classifyDrug(String input, {bool confirmMedicine = false}) async {
    final normalized = input.toLowerCase().trim();
    final cacheKey = 'drug_classification:$normalized';
    final cached = _cacheService.get(cacheKey);
    if (cached is Map<String, dynamic>) {
      return cached;
    }

    try {
      await _networkService.ensureConnected();
      final url = Uri.parse('$baseUrl/api/drug/classify');
      final response = await http.post(
        url,
        headers: _getAuthHeaders(),
        body: json.encode({
          'input': input,
          'confirm_medicine': confirmMedicine,
        }),
      );

      if (response.statusCode != 200) {
        throw HttpException('Failed to classify drug: ${response.body}');
      }

      final decoded = json.decode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw FormatException('Unexpected classification response format');
      }

      _cacheService.set(cacheKey, decoded, ttl: const Duration(hours: 12));
      return decoded;
    } catch (error) {
      final appError = ErrorService.parse(error);
      if (appError.fallbackAllowed && cached is Map<String, dynamic>) {
        return cached;
      }
      throw appError;
    }
  }

  Future<List<dynamic>> getDrugAutocomplete(String query) async {
    final normalized = query.toLowerCase().trim();
    final cacheKey = 'drug_suggestions:$normalized';
    final cached = _cacheService.get(cacheKey);
    if (cached is List) {
      return cached;
    }

    try {
      await _networkService.ensureConnected();
      final url = Uri.parse('$baseUrl/api/drug/autocomplete?q=$query');
      final response = await http.get(
        url,
        headers: _getAuthHeaders(),
      );

      if (response.statusCode != 200) {
        throw HttpException('Failed to fetch autocomplete: ${response.body}');
      }

      final data = json.decode(response.body);
      final suggestions = data['suggestions'] ?? [];
      _cacheService.set(cacheKey, suggestions, ttl: const Duration(minutes: 30));
      return suggestions;
    } catch (error) {
      final appError = ErrorService.parse(error);
      if (appError.fallbackAllowed && cached is List) {
        return cached;
      }
      throw appError;
    }
  }
}
