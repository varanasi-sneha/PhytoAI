import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'auth_service.dart';
import 'config/app_config.dart';

class ApiService {
  final String baseUrl = AppConfig.apiBaseUrl;
  final AuthService _authService;

  ApiService(this._authService);

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
    } on SocketException catch (error) {
      throw HttpException('Network error while uploading image: $error');
    } on FormatException catch (error) {
      throw FormatException('Unable to decode JSON response: $error');
    } catch (error) {
      rethrow;
    }
  }

  /// Fetches user's prediction history.
  Future<List<Map<String, dynamic>>> getHistory() async {
    final url = Uri.parse('$baseUrl/api/history');
    final response = await http.get(url, headers: _getAuthHeaders());

    if (response.statusCode != 200) {
      throw HttpException('Failed to fetch history: ${response.body}');
    }

    final decoded = json.decode(response.body);
    if (decoded is! List) {
      throw FormatException('Unexpected history response format');
    }

    return List<Map<String, dynamic>>.from(decoded);
  }

  /// Fetches prevention data for a disease.
  Future<Map<String, dynamic>> getPrevention(String diseaseName) async {
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

    return decoded;
  }

  /// Fetches user profile.
  Future<Map<String, dynamic>> getProfile() async {
    final url = Uri.parse('$baseUrl/api/profile');
    final response = await http.get(url, headers: _getAuthHeaders());

    if (response.statusCode != 200) {
      throw HttpException('Failed to fetch profile: ${response.body}');
    }

    final decoded = json.decode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw FormatException('Unexpected profile response format');
    }

    return decoded;
  }

  /// Updates user profile.
  Future<void> updateProfile(String firstName, String lastName) async {
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
  }

  /// Classifies a drug/compound.
  Future<Map<String, dynamic>> classifyDrug(String input, {bool confirmMedicine = false}) async {
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

    return decoded;
  }
  Future<List<dynamic>> getDrugAutocomplete(
      String query) async {

    final url = Uri.parse(
      '$baseUrl/api/drug/autocomplete?q=$query',
    );

    final response = await http.get(
      url,
      headers: _getAuthHeaders(),
    );

    if (response.statusCode == 200) {

      final data = json.decode(response.body);

      return data['suggestions'] ?? [];
    }

    return [];
  }
}
