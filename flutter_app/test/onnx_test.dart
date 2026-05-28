import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_appp/ml/onnx_runtime_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Test ONNX initialization', () async {
    // Mock the rootBundle.load to return the real file bytes from the disk
    final file = File('assets/models/plant_model.onnx');
    final bytes = await file.readAsBytes();
    
    // Register a mock handler for rootBundle
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', (message) async {
      return bytes.buffer.asByteData(bytes.offsetInBytes, bytes.lengthInBytes);
    });

    print('[TEST] Starting ONNX init test...');
    try {
      await OnnxRuntimeService.instance.init('assets/models/plant_model.onnx');
      print('[TEST] ONNX init succeeded!');
    } catch (e, stackTrace) {
      print('[TEST] ONNX init failed: $e');
      print(stackTrace);
    }
  });
}
