import 'dart:typed_data';

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
      debugPrint('[CompoundONNX] Already initialized, skipping');
      return;
    }

    debugPrint('[CompoundONNX] Loading model from: $modelAssetPath');
    try {
      final byteData = await rootBundle.load(modelAssetPath);
      debugPrint('[CompoundONNX] Asset size: ${byteData.lengthInBytes} bytes');

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
        debugPrint('[CompoundONNX] OrtEnv initialized');
        _session = OrtSession.fromBuffer(modelBytes, sessionOptions);
        _initialized = true;
        debugPrint('[CompoundONNX] ✅ Session created');
        debugPrint('[CompoundONNX] Input names: ${_session!.inputNames}');
        debugPrint('[CompoundONNX] Output names: ${_session!.outputNames}');
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
    debugPrint('[CompoundONNX] runInference called, initialized=$_initialized');

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
    debugPrint('[CompoundONNX] Using input name: $inputName');

    final ortValue = OrtValueTensor.createTensorWithDataList(
      inputTensor,
      [1, 1191],
    );
    final runOptions = OrtRunOptions();

    try {
      debugPrint('[CompoundONNX] Running inference...');
      final outputs = _session!.run(runOptions, {inputName: ortValue});
      debugPrint('[CompoundONNX] Outputs count: ${outputs.length}');

      if (outputs.isEmpty || outputs.first == null) {
        throw Exception('inference_failed: empty outputs');
      }

      final dynamic outputData = outputs[1]!.value;
      debugPrint('[CompoundONNX] Output type: ${outputData.runtimeType}');
      debugPrint('[CompoundONNX] Raw output: $outputData');

      final List<double> rawOutput = [];

      if (outputData is List) {
        if (outputData.isNotEmpty && outputData.first is List) {
          rawOutput.addAll(
            (outputData.first as List).map((e) => (e as num).toDouble()),
          );
        } else {
          rawOutput.addAll(outputData.map((e) => (e as num).toDouble()));
        }
      } else {
        throw Exception('inference_failed: unexpected output type');
      }

      debugPrint('[CompoundONNX] Raw output length: ${rawOutput.length}');
      debugPrint('[CompoundONNX] Raw output values: $rawOutput');

      if (rawOutput.length != 5) {
        throw Exception(
          'unexpected_output_length: expected 5 got ${rawOutput.length}',
        );
      }

      debugPrint('[CompoundONNX] ✅ Inference complete: $rawOutput');
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
    debugPrint('[CompoundONNX] Disposed');
  }
}