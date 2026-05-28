import 'dart:typed_data';
import 'rdkit_webview_service.dart';

/// Public API — same signature as before.
/// Now delegates to RDKit.js running in a hidden WebView instead of
/// a native MethodChannel plugin.
class CompoundFingerprintGenerator {
  static Future<Float32List> generate(String smiles) async {
    return RDKitWebViewService.instance.generateFingerprint(smiles);
  }
}