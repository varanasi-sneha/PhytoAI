import 'dart:io';

import '../ml/onnx_runtime_service.dart';
import 'cache_service.dart';
import 'error_service.dart';

class LocalInferenceResult {
  final bool success;
  final Map<String, dynamic>? response;
  final AppError? error;
  final bool fallbackToRemote;

  LocalInferenceResult({
    required this.success,
    this.response,
    this.error,
    this.fallbackToRemote = false,
  });
}

class LocalInferenceService {
  final CacheService _cacheService;
  bool _plantModelLoaded = false;
  String? _modelPath;

  LocalInferenceService({required CacheService cacheService}) : _cacheService = cacheService;

  bool get hasPlantModel => _plantModelLoaded;
  String? get modelStatus {
    if (!_plantModelLoaded) return 'ONNX model not available';
    return 'Offline ONNX model ready';
  }

  /// Initialize local inference with ONNX model path
  /// modelPath should be the asset path to plant_model.onnx
  Future<void> initialize({String? modelPath}) async {
    _modelPath = modelPath ?? 'assets/models/plant_model.onnx';
    print("[LocalInferenceService] Starting local ONNX model load from path: $_modelPath");
    try {
      await OnnxRuntimeService.instance.init(_modelPath!);
      _plantModelLoaded = true;
      print("[LocalInferenceService] Local ONNX model loaded successfully!");
    } catch (e, stackTrace) {
      _plantModelLoaded = false;

      print("❌ MODEL INIT FAILED");
      print("❌ ERROR: $e");
      print("❌ STACK: $stackTrace");

      rethrow; // 🔥 THIS IS CRITICAL
    }
  }

  /// Get model metadata for debugging/info
  Map<String, dynamic>? getModelMetadata() {
    if (!_plantModelLoaded) return null;
    return {'model': 'onnx', 'path': _modelPath};
  }

  /// Predict plant disease from image file using on-device ONNX inference
  Future<LocalInferenceResult> predictPlant(File imageFile) async {
    final cacheKey = await _generateCacheKey(imageFile);
    final cachedData = _cacheService.get(cacheKey);
    if (cachedData is Map<String, dynamic>) {
      return LocalInferenceResult(success: true, response: cachedData, fallbackToRemote: false);
    }

    if (!_plantModelLoaded) {
      return LocalInferenceResult(
        success: false,
        error: AppError.modelUnavailable,
        fallbackToRemote: false,
      );
    }

    try {
      final result = await OnnxRuntimeService.instance.predict(imageFile);
      // Cache the result for offline reuse
      await cachePredictionResult(imageFile, result);
      return LocalInferenceResult(success: true, response: result, fallbackToRemote: false);
    } catch (error) {
      final mapped = ErrorService.parse(error);
      return LocalInferenceResult(success: false, error: mapped, fallbackToRemote: false);
    }
  }

  /// Cache prediction result for offline reuse
  Future<void> cachePredictionResult(File imageFile, Map<String, dynamic> result) async {
    try {
      final cacheKey = await _generateCacheKey(imageFile);
      await _cacheService.set(cacheKey, result, ttl: const Duration(days: 7));
    } catch (_) {
      // Caching error is non-fatal
    }
  }

  /// Generate cache key based on image file properties
  Future<String> _generateCacheKey(File imageFile) async {
    final modified = await imageFile.lastModified();
    final size = await imageFile.length();
    return 'plant:$size:${modified.millisecondsSinceEpoch}';
  }

  void dispose() {
    OnnxRuntimeService.instance.dispose();
    _plantModelLoaded = false;
  }
}
