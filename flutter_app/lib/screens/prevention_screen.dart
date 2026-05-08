import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api_service.dart';

class PreventionScreen extends StatefulWidget {

  final String? diseaseName;

  const PreventionScreen({
    Key? key,
    this.diseaseName,
  }) : super(key: key);

  @override
  State<PreventionScreen> createState() => _PreventionScreenState();
}

class _PreventionScreenState extends State<PreventionScreen> {
  final _diseaseController = TextEditingController();
  Map<String, dynamic>? _preventionData;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _diseaseController.dispose();
    super.dispose();
  }

  Future<void> _getPrevention() async {
    final diseaseName =
      _diseaseController.text
          .trim()
          .replaceAll('_', ' ')
          .toLowerCase();
    if (diseaseName.isEmpty) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _preventionData = null;
    });

    try {
      final apiService = context.read<ApiService>();
      String normalizedDisease =
        diseaseName
            .trim()
            .toLowerCase()
            .replaceAll('_', '-')
            .replaceAll(' ', '-');

      final response =
          await apiService.getPrevention(
              normalizedDisease);

      setState(() {
        _preventionData = response;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'No prevention information found for this disease.';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(

    appBar: AppBar(
      title: const Text(
        'Prevention Guide',
      ),
    ),

    body: SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Get Prevention Tips',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          const Text(
            'Enter the disease name to get prevention and treatment information',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _diseaseController,

            decoration: InputDecoration(
              labelText: 'Disease Name',

              hintText:
                  'e.g. bacterial spot',

              prefixIcon: const Icon(
                Icons.search,
              ),

              filled: true,
              fillColor: Colors.white,

              border: OutlineInputBorder(
                borderRadius:
                    BorderRadius.circular(18),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 56,

            child: ElevatedButton.icon(
              icon: const Icon(Icons.shield),

              label: const Text(
                'Get Prevention Guide',
                style: TextStyle(fontSize: 16),
              ),

              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,

                shape: RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(18),
                ),
              ),

              onPressed:
                  _isLoading ? null : _getPrevention,
            ),
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: 16),
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
                children: [

                  const Icon(
                    Icons.error_outline,
                    color: Colors.red,
                  ),

                  const SizedBox(width: 12),

                  Expanded(
                    child: Text(
                      _errorMessage!,
                      style: TextStyle(
                        color: Colors.red.shade900,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ],
              ),
            )
          ],
          if (_preventionData != null) ...[

            const SizedBox(height: 24),

            Container(
              padding: const EdgeInsets.all(20),

              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),

              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,

                children: [

                  /// HEADER
                  Row(
                    children: const [

                      Icon(
                        Icons.health_and_safety,
                        color: Colors.green,
                        size: 32,
                      ),

                      SizedBox(width: 12),

                      Text(
                        'Prevention Guide',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  /// DISEASE NAME
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),

                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius:
                          BorderRadius.circular(14),
                    ),

                    child: Row(
                      children: [

                        const Icon(
                          Icons.bug_report,
                          color: Colors.green,
                        ),

                        const SizedBox(width: 10),

                        Expanded(
                          child: Text(
                            _diseaseController.text
                                .replaceAll('-', ' ')
                                .replaceAll('_', ' '),

                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  /// PREVENTION CONTENT
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(18),

                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius:
                          BorderRadius.circular(18),
                    ),

                    child: Text(
                      (_preventionData!['data'] ??
                              'No prevention data available.')
                          .toString()
                          .replaceAll('\\n', '\n')
                          .replaceAll('_', ' '),

                      style: const TextStyle(
                        fontSize: 16,
                        height: 1.8,
                        color: Colors.black87,
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
  @override
  void initState() {
    super.initState();

    if (widget.diseaseName != null) {

      _diseaseController.text =
          widget.diseaseName!;

      Future.microtask(() {
        _getPrevention();
      });
    }
  }
}