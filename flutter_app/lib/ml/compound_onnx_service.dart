import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:onnxruntime/onnxruntime.dart';

class CompoundOnnxService {
  CompoundOnnxService._private();
  static final CompoundOnnxService instance = CompoundOnnxService._private();

  bool _initialized = false;
  OrtSession? _session;

  static const List<String> classNames = [
    'Animal-derived',
    'Bacteria-derived',
    'Chromista-derived',
    'Fungi-derived',
    'Plant-derived',
  ];

  Future<void> init({
    String modelAssetPath = 'assets/models/np_classifier_v7_2_int8.onnx',
  }) async {
    if (_initialized) {
      return;
    }

    try {
      final byteData = await rootBundle.load(modelAssetPath);

      final modelBytes = byteData.buffer.asUint8List(
        byteData.offsetInBytes,
        byteData.lengthInBytes,
      );

      final sessionOptions = OrtSessionOptions();
      sessionOptions.setSessionGraphOptimizationLevel(
        GraphOptimizationLevel.ortEnableAll,
      );
      sessionOptions.setIntraOpNumThreads(2);

      try {
        OrtEnv.instance.init();
        _session = OrtSession.fromBuffer(modelBytes, sessionOptions);
        _initialized = true;
      } catch (e) {
        _initialized = false;
        debugPrint('[CompoundONNX] ❌ Session creation failed: $e');
        rethrow;
      } finally {
        sessionOptions.release();
      }
    } catch (e) {
      debugPrint('[CompoundONNX] ❌ Model load failed: $e');
      rethrow;
    }
  }

  bool get isInitialized => _initialized;

  Future<List<double>> runInference(Float32List inputTensor) async {
    if (!_initialized || _session == null) {
      throw Exception('model_uninitialized');
    }

    if (inputTensor.length != 1191) {
      throw Exception(
        'invalid_input_shape: expected 1191 got ${inputTensor.length}',
      );
    }

    final inputName = _session!.inputNames.isNotEmpty
        ? _session!.inputNames.first
        : 'input';

    final ortValue = OrtValueTensor.createTensorWithDataList(inputTensor, [
      1,
      1191,
    ]);
    final runOptions = OrtRunOptions();

    try {
      final outputs = _session!.run(runOptions, {inputName: ortValue});

      if (outputs.isEmpty) {
        throw Exception('inference_failed: empty outputs');
      }

      List<double> flattenNumeric(dynamic value) {
        if (value == null) return [];
        if (value is num) return [value.toDouble()];
        if (value is Float32List) {
          return value.map((e) => e.toDouble()).toList();
        }
        if (value is List) {
          if (value.isEmpty) return [];
          if (value.every((element) => element is num)) {
            return value.cast<num>().map((e) => e.toDouble()).toList();
          }
          return value.expand((element) => flattenNumeric(element)).toList();
        }
        if (value is Map) {
          return value.values
              .expand((element) => flattenNumeric(element))
              .toList();
        }
        try {
          final dynamic nested = (value as dynamic).value;
          if (nested != null && nested != value) {
            return flattenNumeric(nested);
          }
        } catch (_) {}
        return [];
      }

      List<List<double>> collectCandidates(dynamic value) {
        if (value == null) return [];
        if (value is num || value is Float32List || value is List) {
          final flattened = flattenNumeric(value);
          if (flattened.isNotEmpty) {
            return [flattened];
          }
          return [];
        }
        if (value is Map) {
          final candidates = <List<double>>[];
          for (final element in value.values) {
            candidates.addAll(collectCandidates(element));
          }
          return candidates;
        }
        try {
          final dynamic nested = (value as dynamic).value;
          if (nested != null && nested != value) {
            return collectCandidates(nested);
          }
        } catch (_) {}
        return [];
      }

      final candidates = <List<double>>[];
      for (final output in outputs) {
        if (output == null) continue;
        dynamic outputValue;
        try {
          outputValue = (output as dynamic).value;
        } catch (_) {
          outputValue = output;
        }
        candidates.addAll(collectCandidates(outputValue));
      }

      final List<double> rawOutput = candidates.firstWhere(
        (candidate) => candidate.length == 5,
        orElse: () => candidates.isNotEmpty ? candidates.first : [],
      );

      if (rawOutput.isEmpty) {
        throw Exception('inference_failed: no numeric output found');
      }

      if (rawOutput.length != 5) {
        throw Exception(
          'unexpected_output_length: expected 5 got ${rawOutput.length}',
        );
      }

      return rawOutput;
    } finally {
      ortValue.release();
      runOptions.release();
    }
  }

  void dispose() {
    _session?.release();
    _session = null;
    _initialized = false;
    OrtEnv.instance.release();
  }
}
