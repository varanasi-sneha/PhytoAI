package com.phytoai.app

import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
  private val channelName = "com.phytoai.app/compound_fingerprint"

  override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)

    MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
      .setMethodCallHandler { call, result ->
        if (call.method == "generateCompoundFeatures") {
          val smiles = call.argument<String>("smiles")
          if (smiles.isNullOrBlank()) {
            result.error("invalid_smiles", "SMILES string is required.", null)
            return@setMethodCallHandler
          }

          // Native SMILES fingerprint generation must be implemented here.
          // For production, integrate RDKit/OpenBabel or a compiled native
          // library to compute ECFP4 + MACCS and return exactly 1191 float values.
          result.error(
            "not_implemented",
            "Platform fingerprint generation is not implemented. Add a native library/plugin to compute ECFP4 and MACCS features.",
            null,
          )
        } else {
          result.notImplemented()
        }
      }
  }
}
