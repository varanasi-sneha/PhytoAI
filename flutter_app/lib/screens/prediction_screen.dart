import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/error_service.dart';
import '../services/local_inference_service.dart';
import '../services/supabase_history_service.dart';
import '../data/local_prevention_data.dart';

class PredictionScreen extends StatefulWidget {
  const PredictionScreen({Key? key}) : super(key: key);

  @override
  State<PredictionScreen> createState() => _PredictionScreenState();
}

class _PredictionScreenState extends State<PredictionScreen> {
  final ImagePicker _picker = ImagePicker();
  File? _selectedImage;
  PredictionResult? _result;
  bool _isLoading = false;
  String? _errorMessage;

  Map<String, dynamic>? _preventionData;
  String? _preventionError;

  final Map<String, Color> _classColors = {
    'Anthracnose': const Color(0xFFef5350),
    'Bacterial-Spot': const Color(0xFFff7043),
    'Downy-Mildew': const Color(0xFF7e57c2),
    'Healthy-Leaf': const Color(0xFF66bb6a),
    'Pest-Damage': const Color(0xFFffa726),
  };

  // ─── Image Picker ────────────────────────────────────────────────────────────

  Future<void> _pickImage(ImageSource source) async {
    try {
      if (source == ImageSource.camera) {
        final status = await Permission.camera.request();
        if (!status.isGranted) {
          setState(() => _errorMessage = 'Camera permission denied.');
          return;
        }
      }

      if (source == ImageSource.gallery) {
        PermissionStatus status;
        if (Platform.isAndroid) {
          status = await Permission.photos.request();
          if (!status.isGranted) status = await Permission.storage.request();
        } else {
          status = await Permission.photos.request();
        }
        if (!status.isGranted) {
          setState(() => _errorMessage = 'Gallery permission denied.');
          return;
        }
      }

      final XFile? picked = await _picker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 1024,
        maxHeight: 1024,
      );

      if (picked != null) {
        setState(() {
          _selectedImage = File(picked.path);
          _result = null;
          _errorMessage = null;
          _preventionData = null;
          _preventionError = null;
        });
      }
    } catch (_) {
      setState(() => _errorMessage = 'Failed to pick image.');
    }
  }

  // ─── Prediction ──────────────────────────────────────────────────────────────

  Future<void> _analyzeImage() async {
    if (_selectedImage == null) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _result = null;
      _preventionData = null;
      _preventionError = null;
    });

    try {
      final localInference = context.read<LocalInferenceService>();
      final localResult = await localInference.predictPlant(_selectedImage!);

      if (localResult.success && localResult.response != null) {
        final result = PredictionResult.fromJson(localResult.response!);

        setState(() => _result = result);

        // ── Persist to history (local + Supabase) ───────────────────────
        try {
          final historyService = context.read<SupabaseHistoryService>();
          await historyService.saveHistoryItem({
            'prediction': result.disease,
            'display_name': result.displayName,
            'confidence': result.confidence,
            'plant_type': result.plantType,
            'created_at': DateTime.now().toIso8601String(),
          });
        } catch (e, st) {
          debugPrint('SAVE ERROR: $e\n$st');
        }

        // ── Load prevention locally (instant, no network) ──────────────
        final isRejected = result.disease == 'not_a_spinach_leaf' ||
            result.disease == 'unclear_image';
        final isHealthy = result.disease.toLowerCase() == 'healthy_leaf';

        if (!isRejected && !isHealthy && result.displayName.isNotEmpty) {
          _loadLocalPrevention(result.displayName);
        }
      } else {
        throw localResult.error ?? AppError.unknown;
      }
    } catch (error) {
      setState(() => _errorMessage = ErrorService.parse(error).message);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // ─── Prevention (fully local, synchronous) ──────────────────────────────────

  void _loadLocalPrevention(String diseaseName) {
    final data = LocalPreventionData.getFor(diseaseName);
    setState(() {
      if (data != null) {
        _preventionData = data;
        _preventionError = null;
      } else {
        _preventionError = 'No prevention info available for this disease.';
      }
    });
  }

  // ─── UI Helpers ──────────────────────────────────────────────────────────────

  Widget _buildListSection(
      String title, List<dynamic>? items, IconData icon, Color color) {
    if (items == null || items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 8),
            Text(title,
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: color.withOpacity(0.8))),
          ]),
          const SizedBox(height: 8),
          ...items.map((item) => Padding(
                padding: const EdgeInsets.only(bottom: 4.0, left: 28),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('• ',
                        style: TextStyle(fontSize: 16, color: Colors.grey)),
                    Expanded(
                        child: Text(item.toString(),
                            style: const TextStyle(fontSize: 14))),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  Widget _buildDistributionChart(Map<String, dynamic> distribution) {
    final entries = distribution.entries.toList()
      ..sort((a, b) => (b.value as num).compareTo(a.value as num));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        const Text('Confidence Distribution',
            style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        ...entries.map((entry) {
          final double prob = (entry.value as num).toDouble();
          final double normalized = prob > 1 ? prob / 100 : prob;
          final color = _classColors[entry.key] ?? Colors.blueGrey;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(entry.key.replaceAll('-', ' '),
                        style: const TextStyle(
                            fontWeight: FontWeight.w500, fontSize: 13)),
                    Text('${prob.toStringAsFixed(1)}%',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 13)),
                  ],
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: normalized,
                    backgroundColor: Colors.grey.shade200,
                    color: color,
                    minHeight: 6,
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  // ─── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAF9),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Analyze Your Plant',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center),
            const SizedBox(height: 8),
            const Text(
              'Take a photo or upload an image to detect diseases',
              style: TextStyle(color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),

            // ── Camera / Gallery buttons ──────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _pickImage(ImageSource.camera),
                    icon: const Icon(Icons.camera_alt),
                    label: const Text('Camera'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.green.shade700,
                      elevation: 1,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _pickImage(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library),
                    label: const Text('Gallery'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.green.shade700,
                      elevation: 1,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                    ),
                  ),
                ),
              ],
            ),

            // ── Selected image preview ────────────────────────────────────
            if (_selectedImage != null) ...[
              const SizedBox(height: 24),
              Container(
                height: 250,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 10,
                        offset: const Offset(0, 5))
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Image.file(_selectedImage!,
                      fit: BoxFit.cover, width: double.infinity),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                height: 56,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _analyzeImage,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade700,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          height: 24,
                          width: 24,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2.5))
                      : const Text('Analyze Plant',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
            ],

            // ── Error message ─────────────────────────────────────────────
            if (_errorMessage != null) ...[
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.red.shade300),
                ),
                child: Row(children: [
                  const Icon(Icons.error_outline, color: Colors.red),
                  const SizedBox(width: 12),
                  Expanded(
                      child: Text(_errorMessage!,
                          style: TextStyle(
                              color: Colors.red.shade900,
                              fontWeight: FontWeight.w500))),
                ]),
              ),
            ],

            // ── Result card ───────────────────────────────────────────────
            if (_result != null) ...[
              const SizedBox(height: 32),
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 15,
                        offset: const Offset(0, 5))
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                            color: Colors.green.shade50,
                            shape: BoxShape.circle),
                        child: const Icon(Icons.eco,
                            color: Colors.green, size: 28),
                      ),
                      const SizedBox(width: 12),
                      const Text('Analysis Result',
                          style: TextStyle(
                              fontSize: 20, fontWeight: FontWeight.bold)),
                    ]),
                    const SizedBox(height: 20),

                    // Blurry warning
                    if (_result!.isBlurry)
                      Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                            color: Colors.orange.shade50,
                            borderRadius: BorderRadius.circular(12)),
                        child: Row(children: [
                          const Icon(Icons.warning,
                              color: Colors.orange, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                              child: Text(
                                  'Blurry image — results may be less accurate.',
                                  style: TextStyle(
                                      color: Colors.orange.shade900,
                                      fontSize: 13))),
                        ]),
                      ),

                    Text(
                      _result!.displayName.replaceAll('-', ' '),
                      style: const TextStyle(
                          fontSize: 24, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),

                    // Confidence tile
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(16)),
                      child: Row(children: [
                        Icon(Icons.analytics, color: Colors.green.shade700),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Confidence',
                                style: TextStyle(
                                    color: Colors.grey.shade700,
                                    fontSize: 13)),
                            const SizedBox(height: 4),
                            Text(
                              '${(_result!.confidence * 100).toStringAsFixed(1)}%',
                              style: TextStyle(
                                  color: Colors.green.shade800,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18),
                            ),
                          ],
                        ),
                      ]),
                    ),
                    const SizedBox(height: 12),

                    // Plant type tile
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(16)),
                      child: Row(children: [
                        Icon(Icons.local_florist,
                            color: Colors.blue.shade700),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Plant Type',
                                style: TextStyle(
                                    color: Colors.grey.shade700,
                                    fontSize: 13)),
                            const SizedBox(height: 4),
                            Text(
                              _result!.plantType,
                              style: TextStyle(
                                  color: Colors.blue.shade800,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18),
                            ),
                          ],
                        ),
                      ]),
                    ),

                    // Distribution chart
                    if (_result!.distribution != null)
                      _buildDistributionChart(_result!.distribution!),

                    // Prevention guide button
                    if (_preventionData != null) ...[
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.health_and_safety),
                          label: const Text('View Prevention Guide',
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green.shade700,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18)),
                          ),
                          onPressed: _showPreventionPopup,
                        ),
                      ),
                    ],

                    // Prevention error
                    if (_preventionError != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                            color: Colors.orange.shade50,
                            borderRadius: BorderRadius.circular(12)),
                        child: Text(_preventionError!,
                            style: TextStyle(
                                color: Colors.orange.shade800)),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ─── Prevention Popup ────────────────────────────────────────────────────────

  void _showPreventionPopup() {
    if (_preventionData == null) return;

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Prevention Guide',
      barrierColor: Colors.black.withOpacity(0.45),
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (_, __, ___) {
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: SafeArea(
            child: Center(
              child: Material(
                color: Colors.transparent,
                child: Container(
                  margin: const EdgeInsets.all(20),
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.92),
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withOpacity(0.15),
                          blurRadius: 20)
                    ],
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                  color: Colors.green.shade100,
                                  shape: BoxShape.circle),
                              child: Icon(Icons.health_and_safety,
                                  color: Colors.green.shade700),
                            ),
                            const SizedBox(width: 12),
                            const Expanded(
                                child: Text('Prevention Guide',
                                    style: TextStyle(
                                        fontSize: 22,
                                        fontWeight: FontWeight.bold))),
                            IconButton(
                              onPressed: () => Navigator.pop(context),
                              icon: const Icon(Icons.close),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        if (_preventionData!['description'] != null) ...[
                          Text(
                            _preventionData!['description'].toString(),
                            style:
                                const TextStyle(fontSize: 15, height: 1.6),
                          ),
                          const SizedBox(height: 24),
                        ],
                        _buildListSection(
                            'Prevention Measures',
                            _preventionData!['prevention_measures'],
                            Icons.shield,
                            Colors.blue),
                        _buildListSection(
                            'Treatment Options',
                            _preventionData!['treatment_options'],
                            Icons.healing,
                            Colors.purple),
                        _buildListSection(
                            'Organic Solutions',
                            _preventionData!['organic_solutions'],
                            Icons.eco,
                            Colors.green),
                        _buildListSection(
                            'Chemical Solutions',
                            _preventionData!['chemical_solutions'],
                            Icons.science,
                            Colors.orange),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (_, animation, __, child) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.9, end: 1.0).animate(animation),
          child: child,
        ),
      ),
    );
  }
}