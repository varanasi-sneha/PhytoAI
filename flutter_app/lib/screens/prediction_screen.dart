import 'dart:io';

// import 'package:flutter/foundation.dart';
import 'prevention_screen.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../api_service.dart';
import '../models/models.dart';

bool isWebPlatform() {
  return identical(0, 0.0);
}

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

  Future<void> _requestPermissions() async {
    final cameraStatus = await Permission.camera.request();
    final storageStatus = await Permission.storage.request();

    if (!cameraStatus.isGranted || !storageStatus.isGranted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Camera and storage permissions are required')),
      );
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    try {

      /// CAMERA PERMISSION
      if (source == ImageSource.camera) {
        final cameraStatus = await Permission.camera.request();

        if (!cameraStatus.isGranted) {
          setState(() {
            _errorMessage = 'Camera permission denied.';
          });
          return;
        }
      }

      /// GALLERY PERMISSION
      if (source == ImageSource.gallery) {

        PermissionStatus galleryStatus;

        if (Platform.isAndroid) {
          galleryStatus = await Permission.photos.request();

          /// fallback for older android
          if (!galleryStatus.isGranted) {
            galleryStatus = await Permission.storage.request();
          }
        } else {
          galleryStatus = await Permission.photos.request();
        }

        if (!galleryStatus.isGranted) {
          setState(() {
            _errorMessage = 'Gallery permission denied.';
          });
          return;
        }
      }

      final XFile? pickedFile = await _picker.pickImage(
        source: source,
        imageQuality: 85,
      );

      if (pickedFile != null) {
        setState(() {
          _selectedImage = File(pickedFile.path);
          _result = null;
          _errorMessage = null;
        });
      }

    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to pick image.';
      });
    }
  }

  Future<void> _uploadImage() async {
    if (_selectedImage == null) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final apiService = context.read<ApiService>();
      final response = await apiService.uploadImage(_selectedImage!);
      final result = PredictionResult.fromJson(response);

      setState(() {
        _result = result;
      });
    } catch (e) {

      String message =
          'Unable to analyze image.';

      if (e.toString().contains('not_a_spinach_leaf')) {
        message =
            'Please upload a clearer spinach leaf image.';
      }

      setState(() {
        _errorMessage = message;
      });

    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Widget _buildResultTile(
    String title,
    String value,
    IconData icon,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(14),
      ),

      child: Row(
        children: [
          Icon(icon, color: Colors.green),

          const SizedBox(width: 12),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),

                const SizedBox(height: 4),

                Text(
                  value,
                  style: const TextStyle(fontSize: 16),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  

  @override
  Widget build(BuildContext context) {
    return Scaffold(
    appBar: AppBar(
      title: const Text('Disease Detection'),
    ),

    body: SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Take a photo of your plant to detect diseases',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ElevatedButton.icon(
                onPressed: () => _pickImage(ImageSource.camera),
                icon: const Icon(Icons.camera),
                label: const Text('Camera'),
              ),
              ElevatedButton.icon(
                onPressed: () => _pickImage(ImageSource.gallery),
                icon: const Icon(Icons.photo_library),
                label: const Text('Gallery'),
              ),
            ],
          ),
          const SizedBox(height: 24),
          if (_selectedImage != null) ...[
            Container(
              height: 200,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey),
                borderRadius: BorderRadius.circular(8),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(
                  _selectedImage!,
                  fit: BoxFit.cover,
                  width: double.infinity,
                ),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _isLoading ? null : _uploadImage,
              child: _isLoading
                  ? const CircularProgressIndicator()
                  : const Text('Analyze Plant'),
            ),
          ],

          if (_result != null) ...[
            const SizedBox(height: 24),

            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),

              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [

                  /// HEADER
                  Row(
                    children: const [
                      Icon(
                        Icons.eco,
                        color: Colors.green,
                        size: 30,
                      ),
                      SizedBox(width: 10),
                      Text(
                        'Analysis Result',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  /// DISEASE
                  _buildResultTile(
                    'Disease',
                    _result!.displayName,
                    Icons.bug_report,
                  ),

                  const SizedBox(height: 20),

                  SizedBox(
                    width: double.infinity,

                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.shield),

                      label: const Text(
                        'View Prevention Guide',
                      ),

                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          vertical: 16,
                        ),
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),

                      onPressed: () {

                        Navigator.push(
                          context,

                          MaterialPageRoute(
                            builder: (_) => PreventionScreen(
                              diseaseName:
                                _result!.displayName
                                    .toLowerCase()
                                    .replaceAll('_', '-')
                                    .replaceAll(' ', '-'),
                            ),
                          ),
                        );
                      },
                    ),
                  ),

                  // PLANT TYPE
                  _buildResultTile(
                    'Plant Type',
                    _result!.plantType,
                    Icons.local_florist,
                  ),

                  // CONFIDENCE
                  _buildResultTile(
                    'Confidence',
                    '${(_result!.confidence * 100).toStringAsFixed(1)}%',
                    Icons.analytics,
                  ),
                ],
              ),
            ),
          ],
          if (_errorMessage != null) ...[
            const SizedBox(height: 20),

            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Colors.red.shade300,
                ),
              ),

              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.error_outline,
                    color: Colors.red,
                    size: 28,
                  ),

                  const SizedBox(width: 12),

                  Expanded(
                    child: Text(
                      _errorMessage!,
                      style: TextStyle(
                        color: Colors.red.shade900,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    )
    );
  }
}