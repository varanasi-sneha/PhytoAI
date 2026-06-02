import 'dart:io';
import 'dart:typed_data';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;
import 'package:onnxruntime/onnxruntime.dart';

import '../services/error_service.dart';

class OnnxRuntimeService {
  OnnxRuntimeService._private();
  static final OnnxRuntimeService instance = OnnxRuntimeService._private();

  bool _initialized = false;
  OrtSession? _session;

  // Class labels must match training order (indices 0-4, index 5 is OOD)
  static const List<String> classNames = [
    'Anthracnose',
    'Bacterial-Spot',
    'Downy-Mildew',
    'Healthy-Leaf',
    'Pest-Damage',
  ];

  // ── Thresholds (must match predict.py) ──────────────────────────────────────
  static const double _blurThreshold      = 40.0;
  static const double _confidenceThresh   = 0.35;
  static const double _oodEntropyThresh   = 2.5;
  static const double _oodProbThresh      = 0.45;
  static const double _greenPixelRatio    = 0.03;

  // ── Init ─────────────────────────────────────────────────────────────────────

  Future<void> init(String assetPath) async {
    if (_initialized) {
      return;
    }

    try {
      final byteData = await rootBundle.load(assetPath);
      final modelBytes = byteData.buffer.asUint8List(
        byteData.offsetInBytes,
        byteData.lengthInBytes,
      );

      OrtEnv.instance.init();
      final sessionOptions = OrtSessionOptions();
      sessionOptions.setSessionGraphOptimizationLevel(GraphOptimizationLevel.ortEnableAll);
      sessionOptions.setIntraOpNumThreads(2);

      try {
        _session = OrtSession.fromBuffer(modelBytes, sessionOptions);
        _initialized = true;
      } catch (e) {
        _initialized = false;
        debugPrint('[ONNX] Error creating session from buffer: $e');
        rethrow;
      } finally {
        sessionOptions.release();
      }
    } catch (e) {
      _initialized = false;
      debugPrint('[ONNX] Model initialization failed: $e');
      rethrow;
    }
  }

  // ── Image preprocessing ───────────────────────────────────────────────────────
  // Matches backend torchvision: Resize(256), CenterCrop(224), ToTensor(), Normalize(MEAN, STD)

  Future<Float32List> _preprocess(File imageFile) async {
    final bytes = await imageFile.readAsBytes();
    final image = img.decodeImage(bytes);
    if (image == null) throw Exception('invalid_image');

    final processed = _resizeAndCenterCrop(image);

    const mean = [0.485, 0.456, 0.406];
    const std  = [0.229, 0.224, 0.225];

    final Float32List input = Float32List(1 * 3 * 224 * 224);
    var offset = 0;
    double minValue = double.infinity;
    double maxValue = double.negativeInfinity;
    final List<double> firstValues = [];

    for (int c = 0; c < 3; c++) {
      for (int y = 0; y < 224; y++) {
        for (int x = 0; x < 224; x++) {
          final pixel = processed.getPixelSafe(x, y);
          final double channelVal = c == 0
              ? pixel.r / 255.0
              : c == 1
                  ? pixel.g / 255.0
                  : pixel.b / 255.0;
          final normalized = (channelVal - mean[c]) / std[c];
          input[offset++] = normalized;
          if (firstValues.length < 10) firstValues.add(normalized);
          minValue = math.min(minValue, normalized);
          maxValue = math.max(maxValue, normalized);
        }
      }
    }

    return input;
  }

  img.Image _resizeAndCenterCrop(img.Image image) {
    final width  = image.width;
    final height = image.height;

    // Resize so shortest side = 256, preserving aspect ratio
    final scale     = 256 / (width < height ? width : height);
    final newWidth  = (width  * scale).round();
    final newHeight = (height * scale).round();

    final resized = img.copyResize(image, width: newWidth, height: newHeight);

    // Center crop to 224×224
    final x = (resized.width  - 224) ~/ 2;
    final y = (resized.height - 224) ~/ 2;

    return img.copyCrop(resized, x: x, y: y, width: 224, height: 224);
  }

  // ── Blur estimation (Laplacian variance — matches cv2.Laplacian in predict.py) ──

  Future<double> _estimateBlur(File imageFile) async {
    final bytes = await imageFile.readAsBytes();
    final image = img.decodeImage(bytes);
    if (image == null) return 0.0;

    final gray = img.grayscale(image);
    final w    = gray.width;
    final h    = gray.height;

    // Laplacian kernel: center*4 - left - right - top - bottom
    final List<double> laplValues = [];
    for (var y = 1; y < h - 1; y++) {
      for (var x = 1; x < w - 1; x++) {
        final center = gray.getPixelSafe(x,     y    ).r.toDouble();
        final left   = gray.getPixelSafe(x - 1, y    ).r.toDouble();
        final right  = gray.getPixelSafe(x + 1, y    ).r.toDouble();
        final top    = gray.getPixelSafe(x,     y - 1).r.toDouble();
        final bottom = gray.getPixelSafe(x,     y + 1).r.toDouble();
        laplValues.add(center * 4 - left - right - top - bottom);
      }
    }

    if (laplValues.isEmpty) return 0.0;
    final mean     = laplValues.reduce((a, b) => a + b) / laplValues.length;
    final variance = laplValues
        .map((v) => (v - mean) * (v - mean))
        .reduce((a, b) => a + b) / laplValues.length;
    return variance;
  }

  // ── Leaf colour gate (matches _has_leaf_colour in predict.py) ──────────────
  // Python OpenCV HSV: H in [35,85] on 0-180 scale → [70°,170°] on 0-360 scale
  // S >= 30/255, V >= 30/255 (both on 0-1 scale here)
  // Green pixel ratio threshold: > 3% of sampled pixels

  bool _hasLeafColour(img.Image image) {
    var greenPixelCount = 0;

    for (var y = 0; y < image.height; y += 2) {
      for (var x = 0; x < image.width; x += 2) {
        final pixel = image.getPixelSafe(x, y);
        final r = pixel.r / 255.0;
        final g = pixel.g / 255.0;
        final b = pixel.b / 255.0;

        final maxC  = math.max(r, math.max(g, b));
        final minC  = math.min(r, math.min(g, b));
        final delta = maxC - minC;

        double hue;
        if (delta == 0) {
          hue = 0;
        } else if (maxC == r) {
          hue = 60 * (((g - b) / delta) % 6);
        } else if (maxC == g) {
          hue = 60 * (((b - r) / delta) + 2);
        } else {
          hue = 60 * (((r - g) / delta) + 4);
        }
        if (hue < 0) hue += 360;

        final saturation = maxC == 0 ? 0.0 : delta / maxC;
        final value      = maxC;

        // [70°,170°] matches OpenCV's [35,85] on 0-180 scale
        if (hue >= 70 &&
            hue <= 170 &&
            saturation >= (30 / 255) &&
            value      >= (30 / 255)) {
          greenPixelCount++;
        }
      }
    }

    final sampled =
        ((image.width / 2).ceil()) * ((image.height / 2).ceil());
    return greenPixelCount / sampled > _greenPixelRatio;
  }

  // ── Main predict ──────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> predict(File imageFile) async {
    if (!_initialized || _session == null) {
      throw Exception('model_uninitialized');
    }

    // 1. Blur estimation
    final blurScore = await _estimateBlur(imageFile);
    final isBlurry  = blurScore < _blurThreshold;

    // 2. Leaf colour gate (fast OOD check before model inference)
    final rawBytes     = await imageFile.readAsBytes();
    final originalImage = img.decodeImage(rawBytes);
    final hasLeafColour = originalImage != null && _hasLeafColour(originalImage);

    if (!hasLeafColour) {
      throw AppError(
        code: 'not_a_spinach_leaf',
        message: 'No leaf-like colour detected. Please upload a clear photo of a '
                 'Malabar spinach leaf against a plain background.',
        retryable: true,
        fallbackAllowed: false,
      );
    }

    // 3. Preprocess
    Float32List inputTensor;
    try {
      inputTensor = await _preprocess(imageFile);
    } catch (e) {
      throw Exception('invalid_image');
    }

    // 4. Tensor creation and inference
    final inputOrt  = OrtValueTensor.createTensorWithDataList(inputTensor, [1, 3, 224, 224]);
    final inputName = _session!.inputNames.isNotEmpty ? _session!.inputNames.first : 'input';

    final inputs     = {inputName: inputOrt};
    final runOptions = OrtRunOptions();

    try {
      final outputs = _session!.run(runOptions, inputs);

      if (outputs.isEmpty || outputs.first == null) {
        throw Exception('inference_failed');
      }

      final dynamic outputData = outputs.first!.value;

      // Parse logits
      List<double> logits = [];
      if (outputData is List) {
        if (outputData.isNotEmpty && outputData.first is List) {
          logits = (outputData.first as List).map((e) => (e as num).toDouble()).toList();
        } else {
          logits = outputData.map((e) => (e as num).toDouble()).toList();
        }
      } else {
        throw Exception('inference_failed');
      }

      // 5. Softmax over all 6 outputs
      final maxLogit = logits.reduce((a, b) => a > b ? a : b);
      final exps     = logits.map((l) => math.exp(l - maxLogit)).toList();
      final sumExps  = exps.reduce((a, b) => a + b);
      final probs6   = exps.map((e) => e / sumExps).toList();

      // 6. Split OOD class (index 5) from disease classes (indices 0-4)
      final double oodProb;
      final List<double> probs5;
      if (probs6.length == 6) {
        oodProb = probs6[5];
        probs5  = probs6.sublist(0, 5);
      } else {
        // Fallback: treat all outputs as disease classes, no OOD
        oodProb = 0.0;
        probs5  = probs6;
      }

      // 7. Shannon entropy over full 6-class distribution
      var entropy = 0.0;
      for (final p in probs6) {
        if (p > 0) entropy -= p * math.log(p);
      }

      // 8. OOD gate — matches predict.py logic exactly
      if (oodProb > _oodProbThresh || entropy > _oodEntropyThresh) {
        throw AppError(
          code: 'not_a_spinach_leaf',
          message: 'This image does not appear to be a Malabar spinach leaf. '
                   'Please upload a clear, close-up photo of a Malabar spinach leaf.',
          retryable: true,
          fallbackAllowed: false,
        );
      }

      // 9. Re-normalise 5 disease probs (so they sum to 1 independent of OOD logit)
      final sumProbs  = probs5.reduce((a, b) => a + b);
      final probsNorm = probs5.map((p) => sumProbs > 0 ? p / sumProbs : 0.0).toList();

      // 10. Top prediction
      var topIdx  = 0;
      var topProb = probsNorm[0];
      for (var i = 1; i < probsNorm.length; i++) {
        if (probsNorm[i] > topProb) {
          topIdx  = i;
          topProb = probsNorm[i];
        }
      }
      final label = classNames.length > topIdx ? classNames[topIdx] : 'unknown';

      // 11. Blurry + low-confidence combined → reject (matches predict.py step 7)
      // if (isBlurry && topProb < _confidenceThresh) {
      //   throw AppError(
      //     code: 'unclear_image',
      //     message: 'The image is too blurry (sharpness: ${blurScore.toStringAsFixed(0)}) '
      //              'and the model is only ${(topProb * 100).toStringAsFixed(1)}% confident. '
      //              'Please retake the photo in good lighting with the leaf filling the frame.',
      //     retryable: true,
      //     fallbackAllowed: true,
      //   );
      // }

      // Only warn, don't reject

      // 12. Build distribution map
      final distribution = Map.fromIterables(
        classNames.take(probsNorm.length),
        probsNorm.map((p) => p * 100),
      );

      // 13. Build message (matches predict.py step 8)
      final isLowConfidence = topProb < _confidenceThresh;
      final String message;
      if (isBlurry) {
        message = '⚠️ Image is slightly blurry (sharpness: ${blurScore.toStringAsFixed(0)}). '
                  'Most likely: ${label.replaceAll('-', ' ')} '
                  '(${(topProb * 100).toStringAsFixed(1)}% confidence). '
                  'Better lighting may improve accuracy.';
      } else if (isLowConfidence) {
        message = '⚠️ Low confidence (${(topProb * 100).toStringAsFixed(1)}%). '
                  'Possible ${label.replaceAll('-', ' ')}, but consider a clearer '
                  'close-up or consult an agronomist.';
      } else {
        message = '${label.replaceAll('-', ' ')} detected with '
                  '${(topProb * 100).toStringAsFixed(1)}% confidence.';
      }

      return {
        'disease':               label,                          // e.g. "Downy-Mildew"
        'display_name':          label.replaceAll('-', ' '),     // e.g. "Downy Mildew"
        'confidence':            topProb,                        // 0-1 float
        'confidence_percentage': '${(topProb * 100).toStringAsFixed(1)}%',
        'plant_type':            'malabar_spinach',              // matches predict.py
        'distribution':          distribution,
        'is_blurry':             isBlurry,
        'blur_score':            blurScore,
        'is_low_confidence':     isLowConfidence,
        'message':               message,
      };
    } catch (e) {
      debugPrint('[ONNX] Prediction failed: $e');
      rethrow;
    } finally {
      inputOrt.release();
      runOptions.release();
    }
  }

  // ── Dispose ───────────────────────────────────────────────────────────────────

  void dispose() {
    _session?.release();
    _session = null;
    _initialized = false;
    OrtEnv.instance.release();
  }
}