import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/cache_service.dart';
import '../services/compound_classification_service.dart';
import '../services/error_service.dart';
import '../api_service.dart';

class DrugClassificationScreen extends StatefulWidget {
  const DrugClassificationScreen({Key? key}) : super(key: key);

  @override
  State<DrugClassificationScreen> createState() => _DrugClassificationScreenState();
}

class _DrugClassificationScreenState extends State<DrugClassificationScreen> {
  List<String> _suggestions = [];
  bool _showSuggestions = false;
  Timer? _debounce;
  final _inputController = TextEditingController();
  Map<String, dynamic>? _result;
  bool _isLoading = false;
  String? _errorMessage;
  bool _confirmMedicine = false;
  String? _currentMedicineSmiles;

  final Map<String, String> _classIcons = {
    'Animal-derived': '🦁',
    'Bacteria-derived': '🦠',
    'Chromista-derived': '🌊',
    'Fungi-derived': '🍄',
    'Plant-derived': '🌿',
  };

  @override
  void dispose() {
    _debounce?.cancel();
    _inputController.dispose();
    super.dispose();
  }

  Future<void> _classify({String? forceInput}) async {
    final input = forceInput ?? _inputController.text.trim();
    if (input.isEmpty) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _result = null;
    });

    try {
      final classifier = context.read<CompoundClassificationService>();
      final response = await classifier.classifyCompound(input, confirmMedicine: _confirmMedicine);

      setState(() {
        _result = response;
        if (response['status'] == 'medicine_detected') {
          _currentMedicineSmiles = response['smiles'] as String?;
        }
        _confirmMedicine = false; // Reset for next use
      });
    } catch (error) {
      final appError = ErrorService.parse(error);
      setState(() {
        _errorMessage = appError.message;
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
    _classify(forceInput: _currentMedicineSmiles);
  }

  Widget _buildProbabilityBars(Map<String, dynamic> probabilities) {
    List<Widget> bars = [];
    final List<String> classes = [
      'Animal-derived',
      'Bacteria-derived',
      'Chromista-derived',
      'Fungi-derived',
      'Plant-derived'
    ];

    for (var className in classes) {
      final double prob = (probabilities[className] ?? 0.0).toDouble();
      final String icon = _classIcons[className] ?? '🔬';
      
      bars.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '$icon $className',
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                  Text(
                    '${(prob * 100).toStringAsFixed(1)}%',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: prob,
                  backgroundColor: Colors.grey.shade200,
                  color: Colors.green.shade600,
                  minHeight: 8,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(children: bars);
  }

  Widget _buildResultTile(String title, String value, IconData icon, {Color color = Colors.green}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: color.withOpacity(0.8),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
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
      backgroundColor: const Color(0xFFF8FAF9),
      // appBar: AppBar(
      //   title: const Text('Compound Classifier', style: TextStyle(fontWeight: FontWeight.bold)),
      //   backgroundColor: Colors.white,
      //   foregroundColor: Colors.black87,
      //   elevation: 0,
      // ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header Section
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.green.shade700, Colors.teal.shade600],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(color: Colors.green.withOpacity(0.3), blurRadius: 15, offset: const Offset(0, 5)),
                ],
              ),
              child: Column(
                children: const [
                  Icon(Icons.science, color: Colors.white, size: 48),
                  SizedBox(height: 12),
                  Text(
                    'AI Origin Classification',
                    style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Enter a compound name, SMILES, CAS number, or medicine to discover its natural origin.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Input Section
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 2)),
                ],
              ),
              child: TextField(
                controller: _inputController,
                style: const TextStyle(fontSize: 16),
                decoration: InputDecoration(
                  hintText: 'e.g., Caffeine, Aspirin, or SMILES',
                  prefixIcon: Icon(Icons.search, color: Colors.green.shade600),
                  suffixIcon: _inputController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, color: Colors.grey),
                          onPressed: () {
                            _inputController.clear();
                            setState(() {});
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(vertical: 20),
                ),
                onChanged: (value) {

                  setState(() {});

                    if (_debounce?.isActive ?? false) {
                      _debounce!.cancel();
                    }

                    _debounce = Timer(
                      const Duration(milliseconds: 350),
                      () {
                        _fetchSuggestions(value);
                      },
                    );
                  },
                onSubmitted: (_) => _isLoading ? null : _classify(),
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,

              children: [

                _buildExampleChip('🌿 Quercetin'),
                _buildExampleChip('🐾 Cholesterol'),
                _buildExampleChip(
                  '💊 Aspirin SMILES',
                  value:
                      'CC(=O)Oc1ccccc1C(=O)O',
                ),
                _buildExampleChip(
                  '🦠 Tetracycline (CAS)',
                  value: '60-54-8',
                ),
                _buildExampleChip(
                  '🌱 Taxol',
                ),
              ],
            ),
            if (_showSuggestions) ...[

              const SizedBox(height: 12),

              Container(

                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius:
                      BorderRadius.circular(18),

                  boxShadow: [
                    BoxShadow(
                      color:
                          Colors.black.withOpacity(0.05),
                      blurRadius: 10,
                    ),
                  ],
                ),

                child: Column(

                  children:
                      _suggestions.map((s) {

                    return ListTile(

                      leading:
                          const Icon(Icons.search),

                      title: Text(s),

                      onTap: () {

                        _inputController.text = s;

                        setState(() {

                          _showSuggestions =
                              false;
                        });
                      },
                    );
                  }).toList(),
                ),
              ),
            ],


            // Analyze Button
            SizedBox(
              height: 56,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green.shade700,
                  foregroundColor: Colors.white,
                  elevation: 2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                onPressed: _isLoading ? null : _classify,
                child: _isLoading
                    ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                    : const Text('Analyze Compound', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
              ),
            ),

            if (_errorMessage != null) ...[
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, color: Colors.red.shade700),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: TextStyle(color: Colors.red.shade900, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
              )
            ],

            if (_result != null && !_isLoading) ...[
              const SizedBox(height: 24),

              // MEDICINE DETECTED
              if (_result!['status'] == 'medicine_detected') ...[
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))],
                    border: Border.all(color: Colors.blue.shade100),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.medication, color: Colors.blue.shade600, size: 28),
                          const SizedBox(width: 10),
                          const Text(
                            'Medicine Detected',
                            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '"${_result!['medicine_name'] ?? _inputController.text}" is a pharmaceutical product. Its active compound is shown below. Would you like to classify it?',
                        style: TextStyle(fontSize: 15, color: Colors.grey.shade700, height: 1.5),
                      ),
                      const SizedBox(height: 20),
                      _buildResultTile(
                        'Active Compound',
                        _result!['active_compound'] ?? _result!['canonical_name'] ?? 'Unknown',
                        Icons.science,
                        color: Colors.blue,
                      ),
                      if (_result!['drug_indication'] != null)
                        _buildResultTile(
                          'Indication',
                          _result!['drug_indication'],
                          Icons.healing,
                          color: Colors.teal,
                        ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton.icon(
                          onPressed: _handleMedicineDetected,
                          icon: const Icon(Icons.auto_awesome),
                          label: const Text('Classify Active Compound'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue.shade600,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // CLASSIFIED
              if (_result!['status'] == 'classified') ...[
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 15, offset: const Offset(0, 6))],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.green.shade50,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.check_circle, color: Colors.green, size: 28),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${_classIcons[_result!['class_name']] ?? ''} ${_result!['class_name']}',
                                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.blue.shade50,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        '${_result!['confidence_percentage']}% Confidence',
                                        style: TextStyle(color: Colors.blue.shade700, fontWeight: FontWeight.w600, fontSize: 12),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),

                      if (_result!['resolved_name'] != null || _result!['iupac_name'] != null)
                        _buildResultTile(
                          'Resolved Name',
                          _result!['resolved_name'] ?? _result!['iupac_name']!,
                          Icons.subtitles,
                          color: Colors.indigo,
                        ),

                      if (_result!['salt_warning'] != null)
                        Container(
                          margin: const EdgeInsets.only(bottom: 16),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.orange.shade200),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.warning_amber_rounded, color: Colors.orange.shade800),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  _result!['salt_warning'],
                                  style: TextStyle(color: Colors.orange.shade900, fontSize: 13),
                                ),
                              ),
                            ],
                          ),
                        ),

                      const Divider(height: 32),
                      const Text(
                        'Class Probabilities',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      if (_result!['probabilities'] != null)
                        _buildProbabilityBars(Map<String, dynamic>.from(_result!['probabilities'])),
                    ],
                  ),
                ),
              ],

              // NOT FOUND
              if (_result!['status'] == 'not_found') ...[
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.orange.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.search_off, color: Colors.orange.shade800, size: 28),
                          const SizedBox(width: 12),
                          Text(
                            'Compound Not Found',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.orange.shade900),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _result!['message'] ?? 'Please try another name or structure.',
                        style: TextStyle(color: Colors.orange.shade900, height: 1.4),
                      ),
                      if (_result!['suggestions'] != null && (_result!['suggestions'] as List).isNotEmpty) ...[
                        const SizedBox(height: 20),
                        const Text(
                          'Did you mean?',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: (_result!['suggestions'] as List).map((s) {
                            return ActionChip(
                              label: Text(s.toString()),
                              backgroundColor: Colors.white,
                              side: BorderSide(color: Colors.orange.shade300),
                              onPressed: () {
                                _inputController.text = s.toString();
                                _classify();
                              },
                            );
                          }).toList(),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ],
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
  Widget _buildExampleChip(
    String label, {
    String? value,
  }) {

    return ActionChip(

      label: Text(label),

      backgroundColor:
          Colors.white,

      side: BorderSide(
        color: Colors.green.shade200,
      ),

      onPressed: () {

        _inputController.text =
            value ??
            label
                .replaceAll(
                    RegExp(r'^[^\w]+'),
                    '')
                .split('(')
                .first
                .trim();

        setState(() {});
      },
    );
  }
  Future<void> _fetchSuggestions(
      String query) async {

    if (query.length < 2) {
      setState(() {
        _suggestions = [];
        _showSuggestions = false;
      });
      return;
    }

    final cacheService = context.read<CacheService>();
    final normalized = query.toLowerCase().trim();
    final cacheKey = 'drug_suggestions:$normalized';
    final cached = cacheService.get(cacheKey);
    if (cached is List) {
      setState(() {
        _suggestions = List<String>.from(cached);
        _showSuggestions = _suggestions.isNotEmpty;
      });
      return;
    }

    try {
      final apiService = context.read<ApiService>();
      final results = await apiService.getDrugAutocomplete(query);
      cacheService.set(cacheKey, results, ttl: const Duration(minutes: 30));

      setState(() {
        _suggestions = List<String>.from(results);
        _showSuggestions = _suggestions.isNotEmpty;
      });
    } catch (_) {
      setState(() {
        _suggestions = [];
        _showSuggestions = false;
      });
    }
  }
}