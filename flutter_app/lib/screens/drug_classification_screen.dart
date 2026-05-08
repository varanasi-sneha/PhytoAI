import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api_service.dart';

class DrugClassificationScreen extends StatefulWidget {
  const DrugClassificationScreen({Key? key}) : super(key: key);

  @override
  State<DrugClassificationScreen> createState() => _DrugClassificationScreenState();
}

class _DrugClassificationScreenState extends State<DrugClassificationScreen> {
  final _inputController = TextEditingController();
  Map<String, dynamic>? _result;
  bool _isLoading = false;
  String? _errorMessage;
  bool _confirmMedicine = false;

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  Future<void> _classify() async {
    final input = _inputController.text.trim();
    if (input.isEmpty) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _result = null;
    });

    try {
      final apiService = context.read<ApiService>();
      final response = await apiService.classifyDrug(input, confirmMedicine: _confirmMedicine);

      setState(() {
        _result = response;
        _confirmMedicine = false; // Reset for next use
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Unable to classify compound. Please try another input.';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _handleMedicineDetected() {
    setState(() {
      _confirmMedicine = true;
    });
    _classify();
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
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Drug Classification',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          const Text(
            'Enter a compound name, SMILES, CAS number, or medicine name to classify',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _inputController,

            decoration: InputDecoration(

              hintText:
                  'Enter medicine or compound',

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

              icon: const Icon(Icons.science),

              label: const Text(
                'Analyze Compound',
                style: TextStyle(fontSize: 16),
              ),

              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green.shade700,
                foregroundColor: Colors.white,

                shape: RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(18),
                ),
              ),

              onPressed:
                  _isLoading ? null : _classify,
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
                  color: Colors.red.shade200,
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
                        color: Colors.red.shade800,
                      ),
                    ),
                  ),
                ],
              ),
            )
          ],
          if (_result != null) ...[
            const SizedBox(height: 24),

            Container(
              color: const Color(0xFFF4F7F5),
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

                  /// TITLE
                  Row(
                    children: const [
                      Icon(
                        Icons.science,
                        color: Colors.green,
                        size: 28,
                      ),
                      SizedBox(width: 10),
                      Text(
                        'Classification Result',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  /// MEDICINE DETECTED
                  if (_result!['status'] == 'medicine_detected') ...[
                    Text(
                      _result!['input'] ?? 'Medicine detected',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 12),

                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Text(
                        'This appears to be a medicine/drug. '
                        'Would you like to classify its active compound?',
                        style: TextStyle(fontSize: 15),
                      ),
                    ),

                    const SizedBox(height: 20),

                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _handleMedicineDetected,
                        icon: const Icon(Icons.auto_awesome),
                        label: const Text(
                          'Classify Active Compound',
                        ),
                      ),
                    ),
                  ],

                  /// SUCCESSFUL CLASSIFICATION
                  if (_result!['status'] == 'classified') ...[
                    if (_result!['prediction'] != null)
                      _buildResultTile(
                        'Prediction',
                        _result!['prediction'].toString(),
                        Icons.analytics,
                      ),

                    if (_result!['confidence'] != null)
                      _buildResultTile(
                        'Confidence',
                        '${(_result!['confidence'] * 100).toStringAsFixed(1)}%',
                        Icons.bar_chart,
                      ),

                    if (_result!['input_type'] != null)
                      _buildResultTile(
                        'Input Type',
                        _result!['input_type'].toString(),
                        Icons.category,
                      ),
                  ],

                  /// NOT FOUND
                  if (_result!['status'] == 'not_found') ...[
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Text(
                        'Compound not found. '
                        'Please try another name or structure.',
                      ),
                    ),

                    if (_result!['suggestions'] != null) ...[
                      const SizedBox(height: 16),

                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: (_result!['suggestions'] as List)
                            .map(
                              (s) => Chip(
                                label: Text(s.toString()),
                              ),
                            )
                            .toList(),
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}