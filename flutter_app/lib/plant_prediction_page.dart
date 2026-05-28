import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import 'api_service.dart';

class PlantPredictionPage extends StatefulWidget {
  const PlantPredictionPage({Key? key}) : super(key: key);

  @override
  State<PlantPredictionPage> createState() => _PlantPredictionPageState();
}

class _PlantPredictionPageState extends State<PlantPredictionPage> {
  late ApiService _apiService;
  final ImagePicker _picker = ImagePicker();

  bool _isLoading = false;
  String? _resultText;
  String? _errorText;

  Future<void> _pickAndUploadImage() async {
    final XFile? pickedFile = await _picker.pickImage(source: ImageSource.gallery);
    if (pickedFile == null) {
      return;
    }

    setState(() {
      _isLoading = true;
      _resultText = null;
      _errorText = null;
    });

    try {
      final response = await _apiService.uploadImage(File(pickedFile.path));
      setState(() {
        _resultText = 'Label: ${response['label']}\n'
            'Confidence: ${response['confidence']}\n'
            'Status: ${response['status']}';
      });
    } catch (error) {
      setState(() {
        _errorText = error.toString();
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _apiService = context.read<ApiService>();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Plant Disease Detection'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ElevatedButton(
              onPressed: _isLoading ? null : _pickAndUploadImage,
              child: const Text('Select Image and Upload'),
            ),
            const SizedBox(height: 24),
            if (_isLoading) const Center(child: CircularProgressIndicator()),
            if (_resultText != null) ...[
              const SizedBox(height: 24),
              Text(
                _resultText!,
                style: const TextStyle(fontSize: 16),
              ),
            ],
            if (_errorText != null) ...[
              const SizedBox(height: 24),
              Text(
                _errorText!,
                style: const TextStyle(color: Colors.red, fontSize: 16),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
