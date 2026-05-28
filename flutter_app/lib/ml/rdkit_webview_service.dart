import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../services/error_service.dart';

class RDKitWebViewService {
  RDKitWebViewService._private();
  static final RDKitWebViewService instance = RDKitWebViewService._private();

  WebViewController? _controller;
  bool _ready = false;
  bool _widgetBuilt = false;
  Completer<void>? _readyCompleter;

  int _callId = 0;
  final Map<int, Completer<Float32List>> _pending = {};

  Widget buildHiddenWebView() {
    // ── Only build once — reuse existing controller on rebuild ──
    if (_widgetBuilt && _controller != null) {
      debugPrint('[RDKit] WebView already built, reusing controller');
      return SizedBox(
        width: 1,
        height: 1,
        child: WebViewWidget(controller: _controller!),
      );
    }

    _widgetBuilt = true;
    _readyCompleter ??= Completer<void>();

    debugPrint('[RDKit] Building hidden WebView...');

    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        'RDKitReady',
        onMessageReceived: (msg) {
          debugPrint('[RDKit] ✅ WASM ready signal received');
          _ready = true;
          if (!(_readyCompleter?.isCompleted ?? true)) {
            _readyCompleter!.complete();
          }
        },
      )
      ..addJavaScriptChannel(
        'FingerprintResult',
        onMessageReceived: (msg) => _handleResult(msg.message),
      )
      ..addJavaScriptChannel(
        'RDKitLog',
        onMessageReceived: (msg) {
          debugPrint('[RDKit JS] ${msg.message}');
        },
      )
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (url) {
          debugPrint('[RDKit] Page finished loading: $url');
        },
        onWebResourceError: (error) {
          debugPrint('[RDKit] WebResource error: ${error.description}');
        },
      ))
      ..loadFlutterAsset('assets/rdkit/rdkit_bridge.html');

    _controller = controller;

    debugPrint('[RDKit] WebView controller created, loading HTML asset...');

    return SizedBox(
      width: 1,
      height: 1,
      child: WebViewWidget(controller: controller),
    );
  }

  bool get isReady => _ready;

  Future<void> waitUntilReady({
    Duration timeout = const Duration(seconds: 60),
  }) async {
    if (_ready) return;

    if (_controller == null) {
      throw AppError(
        code: 'rdkit_not_mounted',
        message: 'RDKit WebView has not been mounted. '
            'Make sure buildHiddenWebView() is in the widget tree.',
        retryable: false,
        fallbackAllowed: false,
      );
    }

    debugPrint('[RDKit] Waiting for WASM to load (timeout: ${timeout.inSeconds}s)...');
    _readyCompleter ??= Completer<void>();

    await _readyCompleter!.future.timeout(
      timeout,
      onTimeout: () => throw AppError(
        code: 'rdkit_timeout',
        message: 'RDKit.js WASM did not load within ${timeout.inSeconds}s. '
            'Check internet connection.',
        retryable: true,
        fallbackAllowed: false,
      ),
    );
  }

  Future<Float32List> generateFingerprint(String smiles) async {
    if (_controller == null) {
      throw AppError(
        code: 'rdkit_not_mounted',
        message: 'RDKit WebView not mounted yet.',
        retryable: false,
        fallbackAllowed: false,
      );
    }

    debugPrint('[RDKit] generateFingerprint called, ready=$_ready');
    await waitUntilReady();

    final id = _callId++;
    final completer = Completer<Float32List>();
    _pending[id] = completer;

    final js = '''
      (function() {
        try {
          var result = generateFingerprint(${jsonEncode(smiles)});
          FingerprintResult.postMessage(JSON.stringify({ id: $id, data: result }));
        } catch(e) {
          FingerprintResult.postMessage(JSON.stringify({ 
            id: $id, 
            data: JSON.stringify({ error: e.toString() }) 
          }));
        }
      })();
    ''';

    await _controller!.runJavaScript(js);

    return completer.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () {
        _pending.remove(id);
        throw AppError(
          code: 'rdkit_fp_timeout',
          message: 'Fingerprint generation timed out.',
          retryable: true,
          fallbackAllowed: false,
        );
      },
    );
  }

  void _handleResult(String message) {
    try {
      debugPrint('[RDKit] FingerprintResult received, length=${message.length}');
      final outer = jsonDecode(message) as Map<String, dynamic>;
      final id = outer['id'] as int;
      final completer = _pending.remove(id);
      if (completer == null) {
        debugPrint('[RDKit] No pending completer for id=$id');
        return;
      }

      final String dataStr = outer['data'] as String;
      final inner = jsonDecode(dataStr) as Map<String, dynamic>;

      if (inner.containsKey('error')) {
        debugPrint('[RDKit] JS error: ${inner['error']}');
        completer.completeError(AppError(
          code: 'rdkit_js_error',
          message: inner['error'] as String,
          retryable: false,
          fallbackAllowed: false,
        ));
        return;
      }

      final List<dynamic> fpList = inner['fingerprint'] as List<dynamic>;
      debugPrint('[RDKit] Fingerprint received, length=${fpList.length}');

      if (fpList.length != 1191) {
        completer.completeError(AppError(
          code: 'rdkit_fp_dim',
          message: 'Expected 1191 features, got ${fpList.length}.',
          retryable: false,
          fallbackAllowed: false,
        ));
        return;
      }

      final fp = Float32List.fromList(
        fpList.map((e) => (e as num).toDouble()).toList(),
      );
      debugPrint('[RDKit] ✅ Fingerprint complete, passing to ONNX');
      completer.complete(fp);
    } catch (e) {
      debugPrint('[RDKit] _handleResult error: $e');
    }
  }

  /// Call this to reset state on hot restart during development
  void reset() {
    _ready = false;
    _widgetBuilt = false;
    _controller = null;
    _readyCompleter = null;
    _pending.clear();
    debugPrint('[RDKit] Service reset');
  }
}