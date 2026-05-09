import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../api_service.dart';
import '../models/models.dart';

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

  bool _isPreventionLoading = false;
  Map<String, dynamic>? _preventionData;
  String? _preventionError;

  final Map<String, Color> _severityColors = {
    'low': const Color(0xFF22c55e),
    'moderate': const Color(0xFFf59e0b),
    'high': const Color(0xFFef4444),
    'critical': const Color(0xFF7f1d1d),
  };

  final Map<String, Color> _classColors = {
    'Anthracnose': const Color(0xFFef5350),
    'Bacterial-Spot': const Color(0xFFff7043),
    'Downy-Mildew': const Color(0xFF7e57c2),
    'Healthy-Leaf': const Color(0xFF66bb6a),
    'Pest-Damage': const Color(0xFFffa726),
  };

  Future<void> _pickImage(ImageSource source) async {
    try {
      if (source == ImageSource.camera) {
        final cameraStatus = await Permission.camera.request();
        if (!cameraStatus.isGranted) {
          setState(() { _errorMessage = 'Camera permission denied.'; });
          return;
        }
      }

      if (source == ImageSource.gallery) {
        PermissionStatus galleryStatus;
        if (Platform.isAndroid) {
          galleryStatus = await Permission.photos.request();
          if (!galleryStatus.isGranted) {
            galleryStatus = await Permission.storage.request();
          }
        } else {
          galleryStatus = await Permission.photos.request();
        }
        if (!galleryStatus.isGranted) {
          setState(() { _errorMessage = 'Gallery permission denied.'; });
          return;
        }
      }

      final XFile? pickedFile = await _picker.pickImage(source: source, imageQuality: 85);

      if (pickedFile != null) {
        setState(() {
          _selectedImage = File(pickedFile.path);
          _result = null;
          _errorMessage = null;
          _preventionData = null;
          _preventionError = null;
        });
      }
    } catch (e) {
      setState(() { _errorMessage = 'Failed to pick image.'; });
    }
  }

  Future<void> _uploadImage() async {
    if (_selectedImage == null) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _result = null;
      _preventionData = null;
      _preventionError = null;
    });

    try {
      final apiService = context.read<ApiService>();
      final response = await apiService.uploadImage(_selectedImage!);
      final result = PredictionResult.fromJson(response);

      setState(() {
        _result = result;
      });

      if (result.displayName.isNotEmpty && result.displayName.toLowerCase() != 'unknown' && result.disease.toLowerCase() != 'healthy_leaf') {
        _fetchPrevention(result.displayName);
      }
    } catch (e) {
      String message = 'Unable to analyze image.';
      if (e.toString().contains('not_a_spinach_leaf')) {
        message = 'Please upload a clearer spinach leaf image.';
      } else if (e.toString().contains('unclear_image')) {
        message = 'The image is too blurry. Please upload a clearer photo.';
      }
      setState(() { _errorMessage = message; });
    } finally {
      setState(() { _isLoading = false; });
    }
  }

  Future<void> _fetchPrevention(String diseaseName) async {
    setState(() {
      _isPreventionLoading = true;
      _preventionError = null;
    });

    try {
      final apiService = context.read<ApiService>();
      String normalizedDisease = diseaseName.trim().toLowerCase().replaceAll('_', '-').replaceAll(' ', '-');
      final response = await apiService.getPrevention(normalizedDisease);
      
      setState(() {
        if (response['success'] == true && response['data'] != null) {
          _preventionData = response['data'];
        } else {
          _preventionError = 'No prevention info found for this disease.';
        }
      });
    } catch (e) {
      setState(() {
        _preventionError = 'Unable to load prevention guide.';
      });
    } finally {
      setState(() {
        _isPreventionLoading = false;
      });
    }
  }

  Widget _buildListSection(String title, List<dynamic>? items, IconData icon, Color color) {
    if (items == null || items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color.withOpacity(0.8)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...items.map((item) => Padding(
            padding: const EdgeInsets.only(bottom: 4.0, left: 28),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('• ', style: TextStyle(fontSize: 16, color: Colors.grey)),
                Expanded(child: Text(item.toString(), style: const TextStyle(fontSize: 14))),
              ],
            ),
          )),
        ],
      ),
    );
  }

  Widget _buildDistributionChart(Map<String, dynamic> distribution) {
    List<Widget> bars = [];
    final entries = distribution.entries.toList()..sort((a, b) => (b.value as num).compareTo(a.value as num));

    for (var entry in entries) {
      final double prob = (entry.value as num).toDouble();
      final double normalizedProb = prob > 1 ? prob / 100 : prob;

      final String className = entry.key;
      final Color color = _classColors[className] ?? Colors.blueGrey;
      
      bars.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(className.replaceAll('-', ' '), style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
                  Text('${(prob).toStringAsFixed(1)}%', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                ],
              ),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: normalizedProb,
                  backgroundColor: Colors.grey.shade200,
                  color: color,
                  minHeight: 6,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        const Text('Confidence Distribution', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        ...bars
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAF9),
      // appBar: AppBar(
      //   title: const Text('Disease Detection', style: TextStyle(fontWeight: FontWeight.bold)),
      //   backgroundColor: Colors.white,
      //   foregroundColor: Colors.black87,
      //   elevation: 0,
      // ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Analyze Your Plant',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'Take a photo or upload an image from your gallery to detect diseases',
              style: TextStyle(color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
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
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            if (_selectedImage != null) ...[
              Container(
                height: 250,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 5))],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Image.file(_selectedImage!, fit: BoxFit.cover, width: double.infinity),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                height: 56,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _uploadImage,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade700,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: _isLoading
                      ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                      : const Text('Analyze Plant', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
            ],

            if (_errorMessage != null) ...[
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.red.shade300),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Colors.red),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(_errorMessage!, style: TextStyle(color: Colors.red.shade900, fontWeight: FontWeight.w500)),
                    ),
                  ],
                ),
              ),
            ],

            if (_result != null) ...[
              const SizedBox(height: 32),
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 15, offset: const Offset(0, 5))],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(color: Colors.green.shade50, shape: BoxShape.circle),
                          child: const Icon(Icons.eco, color: Colors.green, size: 28),
                        ),
                        const SizedBox(width: 12),
                        const Text('Analysis Result', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 20),

                    if (_result!.isBlurry)
                      Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(12)),
                        child: Row(
                          children: [
                            const Icon(Icons.warning, color: Colors.orange, size: 20),
                            const SizedBox(width: 8),
                            Expanded(child: Text('Blurry image. Results may be less accurate.', style: TextStyle(color: Colors.orange.shade900, fontSize: 13))),
                          ],
                        ),
                      ),

                    Text(_result!.displayName.replaceAll('-', ' '), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Column(
                      children: [

                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),

                          decoration: BoxDecoration(
                            color: Colors.green.shade50,
                            borderRadius:
                                BorderRadius.circular(16),
                          ),

                          child: Row(
                            children: [

                              Icon(
                                Icons.analytics,
                                color: Colors.green.shade700,
                              ),

                              const SizedBox(width: 12),

                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,

                                  children: [

                                    Text(
                                      'Confidence',
                                      style: TextStyle(
                                        color:
                                            Colors.grey.shade700,
                                        fontSize: 13,
                                      ),
                                    ),

                                    const SizedBox(height: 4),

                                    Text(
                                      '${(_result!.confidence * 100).toStringAsFixed(1)}%',

                                      style: TextStyle(
                                        color:
                                            Colors.green.shade800,
                                        fontWeight:
                                            FontWeight.bold,
                                        fontSize: 18,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 12),

                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),

                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius:
                                BorderRadius.circular(16),
                          ),

                          child: Row(
                            children: [

                              Icon(
                                Icons.local_florist,
                                color: Colors.blue.shade700,
                              ),

                              const SizedBox(width: 12),

                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,

                                  children: [

                                    Text(
                                      'Plant Type',
                                      style: TextStyle(
                                        color:
                                            Colors.grey.shade700,
                                        fontSize: 13,
                                      ),
                                    ),

                                    const SizedBox(height: 4),

                                    Text(
                                      _result!.plantType,

                                      style: TextStyle(
                                        color:
                                            Colors.blue.shade800,
                                        fontWeight:
                                            FontWeight.bold,
                                        fontSize: 18,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    
                    if (_result!.distribution != null) ...[
                      _buildDistributionChart(
                        _result!.distribution!,
                      ),
                    ],

                    if (_preventionData != null) ...[
                      const SizedBox(height: 24),

                      SizedBox(
                        width: double.infinity,
                        height: 56,

                        child: ElevatedButton.icon(
                          icon: const Icon(
                            Icons.health_and_safety,
                          ),

                          label: const Text(
                            'View Prevention Guide',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),

                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                                Colors.green.shade700,
                            foregroundColor: Colors.white,

                            shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(18),
                            ),
                          ),

                          onPressed: () {
                            _showPreventionPopup();
                          },
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              
              if (_isPreventionLoading) ...[
                const SizedBox(height: 24),
                Center(
                  child: Column(
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 12),
                      Text('Loading prevention guide...', style: TextStyle(color: Colors.grey.shade600)),
                    ],
                  ),
                ),
              ],

              if (_preventionError != null) ...[
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(16)),
                  child: Text(_preventionError!, style: TextStyle(color: Colors.orange.shade800)),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
  void _showPreventionPopup() {

    showGeneralDialog(

      context: context,

      barrierDismissible: true,

      barrierLabel: 'Prevention Guide',

      barrierColor:
          Colors.black.withOpacity(0.45),

      transitionDuration:
          const Duration(milliseconds: 300),

      pageBuilder: (_, __, ___) {

        return BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: 8,
            sigmaY: 8,
          ),

        child: SafeArea(

          child: Center(

            child: Material(
              color: Colors.transparent,

              child: Container(

                margin:
                    const EdgeInsets.all(20),

                padding:
                    const EdgeInsets.all(24),

                decoration: BoxDecoration(

                  color: Colors.white.withOpacity(0.80),

                  borderRadius:
                      BorderRadius.circular(28),

                  boxShadow: [
                    BoxShadow(
                      color:
                          Colors.black.withOpacity(0.15),
                      blurRadius: 20,
                    ),
                  ],
                ),

                child: SingleChildScrollView(

                  child: Column(

                    mainAxisSize:
                        MainAxisSize.min,

                    crossAxisAlignment:
                        CrossAxisAlignment.start,

                    children: [

                      Row(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,

                        children: [

                          Container(
                            padding: const EdgeInsets.all(10),

                            decoration: BoxDecoration(
                              color: Colors.green.shade100,
                              shape: BoxShape.circle,
                            ),

                            child: Icon(
                              Icons.health_and_safety,
                              color: Colors.green.shade700,
                            ),
                          ),

                          const SizedBox(width: 12),

                          Expanded(
                            child: Text(
                              'Prevention Guide',

                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),

                          IconButton(
                            onPressed: () {
                              Navigator.pop(context);
                            },

                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),

                      const SizedBox(height: 24),

                      if (_preventionData![
                              'description'] !=
                          null) ...[

                        Text(
                          _preventionData![
                                  'description']
                              .toString(),

                          style: const TextStyle(
                            fontSize: 15,
                            height: 1.6,
                          ),
                        ),

                        const SizedBox(height: 24),
                      ],

                      _buildListSection(
                        'Prevention Measures',
                        _preventionData![
                            'prevention_measures'],
                        Icons.shield,
                        Colors.blue,
                      ),

                      _buildListSection(
                        'Treatment Options',
                        _preventionData![
                            'treatment_options'],
                        Icons.healing,
                        Colors.purple,
                      ),

                      _buildListSection(
                        'Organic Solutions',
                        _preventionData![
                            'organic_solutions'],
                        Icons.eco,
                        Colors.green,
                      ),

                      _buildListSection(
                        'Chemical Solutions',
                        _preventionData![
                            'chemical_solutions'],
                        Icons.science,
                        Colors.orange,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        );
      },

      transitionBuilder:
          (_, animation, __, child) {

        return FadeTransition(
          opacity: animation,

          child: ScaleTransition(
            scale: Tween<double>(
              begin: 0.9,
              end: 1,
            ).animate(animation),

            child: child,
          ),
        );
      },
    );
  }
}