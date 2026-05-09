import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../api_service.dart';
import '../models/models.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({Key? key}) : super(key: key);

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<HistoryItem> _history = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final apiService = context.read<ApiService>();
      final response = await apiService.getHistory();
      final history = response.map((item) => HistoryItem.fromJson(item)).toList();

      setState(() {
        _history = history;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
  children: [

    Padding(
      padding: const EdgeInsets.fromLTRB(
          20, 16, 20, 8),

      child: Row(
        mainAxisAlignment:
            MainAxisAlignment.spaceBetween,

        children: [

          const Text(
            'Prediction History',

            style: TextStyle(
              fontSize: 24,
              fontWeight:
                  FontWeight.bold,
            ),
          ),

          TextButton.icon(

            icon: Icon(
              Icons.delete_sweep,
              color:
                  Colors.red.shade700,
            ),

            label: Text(
              'Clear All',

              style: TextStyle(
                color:
                    Colors.red.shade700,
                fontWeight:
                    FontWeight.bold,
              ),
            ),

            onPressed: () {
              _showClearAllPopup();
            },
          ),
        ],
      ),
    ),

    Expanded(
      child: RefreshIndicator(
      onRefresh: _loadHistory,
      child: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _errorMessage!,
                        style: const TextStyle(color: Colors.red),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadHistory,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : _history.isEmpty
                  ? const Center(
                      child: Text('No prediction history found'),
                    )
                  : ListView.builder(
                      itemCount: _history.length,
                      itemBuilder: (context, index) {
                        final item = _history[index];
                        return GestureDetector(

                        onLongPress: () {
                          _showDeletePopup(item);
                        },

                        child: Container(
                          margin: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),

                          padding: const EdgeInsets.all(18),

                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(22),

                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.06),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),

                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,

                            children: [

                              Row(
                                children: [

                                  Container(
                                    padding: const EdgeInsets.all(10),

                                    decoration: BoxDecoration(
                                      color: item.confidence > 0.8
                                          ? Colors.green.shade100
                                          : Colors.orange.shade100,

                                      borderRadius:
                                          BorderRadius.circular(14),
                                    ),

                                    child: Icon(
                                      Icons.local_florist,
                                      color: item.confidence > 0.8
                                          ? Colors.green
                                          : Colors.orange,
                                    ),
                                  ),

                                  const SizedBox(width: 14),

                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,

                                      children: [

                                        Text(
                                          item.displayName
                                              .replaceAll('-', ' ')
                                              .replaceAll('_', ' '),

                                          style: const TextStyle(
                                            fontSize: 20,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),

                                        const SizedBox(height: 4),

                                        Text(
                                          item.plantType,
                                          style: TextStyle(
                                            color: Colors.grey.shade700,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),

                              const SizedBox(height: 20),

                              Container(
                                padding: const EdgeInsets.all(14),

                                decoration: BoxDecoration(
                                  color: Colors.grey.shade100,
                                  borderRadius:
                                      BorderRadius.circular(16),
                                ),

                                child: Column(
                                  children: [

                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,

                                      children: [
                                        const Text(
                                          'Confidence',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),

                                        Text(
                                          '${(item.confidence * 100).toStringAsFixed(1)}%',
                                        ),
                                      ],
                                    ),

                                    const SizedBox(height: 10),

                                    LinearProgressIndicator(
                                      value: item.confidence,
                                      minHeight: 10,
                                      borderRadius:
                                          BorderRadius.circular(20),
                                    ),
                                  ],
                                ),
                              ),

                              const SizedBox(height: 18),

                              Row(
                                children: [

                                  const Icon(
                                    Icons.access_time,
                                    size: 18,
                                    color: Colors.grey,
                                  ),

                                  const SizedBox(width: 6),

                                  Text(
                                    DateFormat(
                                      'MMM dd, yyyy • hh:mm a',
                                    ).format(item.createdAt),

                                    style: TextStyle(
                                      color: Colors.grey.shade700,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        );
                      },
                    ),
            ),
          ),
        ],
      );
  }
  void _showDeletePopup(
      HistoryItem item) {

    showGeneralDialog(

      context: context,

      barrierDismissible: true,

      barrierLabel: 'Delete',

      barrierColor:
          Colors.black.withOpacity(0.3),

      transitionDuration:
          const Duration(milliseconds: 250),

      pageBuilder:
          (_, __, ___) {

        return BackdropFilter(

          filter: ImageFilter.blur(
            sigmaX: 8,
            sigmaY: 8,
          ),

          child: Center(

            child: Container(

              margin:
                  const EdgeInsets.all(24),

              padding:
                  const EdgeInsets.all(24),

              decoration: BoxDecoration(

                color:
                    Colors.white.withOpacity(0.92),

                borderRadius:
                    BorderRadius.circular(28),

                boxShadow: [
                  BoxShadow(
                    color: Colors.black
                        .withOpacity(0.08),
                    blurRadius: 20,
                  ),
                ],
              ),

              child: Column(

                mainAxisSize:
                    MainAxisSize.min,

                children: [

                  Container(
                    padding:
                        const EdgeInsets.all(18),

                    decoration: BoxDecoration(
                      color:
                          Colors.red.shade50,
                      shape: BoxShape.circle,
                    ),

                    child: Icon(
                      Icons.delete_rounded,
                      color:
                          Colors.red.shade700,
                      size: 36,
                    ),
                  ),

                  const SizedBox(height: 20),

                  const Text(
                    'Delete History?',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight:
                          FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 12),

                  Text(
                    item.displayName
                        .replaceAll('-', ' ')
                        .replaceAll('_', ' '),

                    textAlign: TextAlign.center,

                    style: TextStyle(
                      fontSize: 16,
                      color:
                          Colors.grey.shade700,
                    ),
                  ),

                  const SizedBox(height: 28),

                  Row(
                    children: [

                      Expanded(
                        child: OutlinedButton(

                          style:
                              OutlinedButton.styleFrom(
                            padding:
                                const EdgeInsets.symmetric(
                              vertical: 16,
                            ),

                            shape:
                                RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(
                                      16),
                            ),
                          ),

                          onPressed: () {
                            Navigator.pop(context);
                          },

                          child:
                              const Text('Cancel'),
                        ),
                      ),

                      const SizedBox(width: 14),

                      Expanded(
                        child: ElevatedButton.icon(

                          icon: const Icon(
                            Icons.delete,
                          ),

                          label: const Text(
                            'Delete',
                          ),

                          style:
                              ElevatedButton.styleFrom(
                            backgroundColor:
                                Colors.red.shade600,

                            foregroundColor:
                                Colors.white,

                            padding:
                                const EdgeInsets.symmetric(
                              vertical: 16,
                            ),

                            shape:
                                RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(
                                      16),
                            ),
                          ),

                          onPressed: () async {

                            Navigator.pop(context);

                            await _deleteHistoryItem(
                                item);
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
  Future<void> _deleteHistoryItem(
      HistoryItem item) async {

    setState(() {

      _history.remove(item);
    });
    // connect backend delete API
  }
  void _showClearAllPopup() {

    showDialog(

      context: context,

      builder: (_) {

        return AlertDialog(

          shape:
              RoundedRectangleBorder(
            borderRadius:
                BorderRadius.circular(24),
          ),

          title: Row(
            children: [

              Icon(
                Icons.warning_rounded,
                color:
                    Colors.red.shade700,
              ),

              const SizedBox(width: 10),

              const Text(
                'Clear History',
              ),
            ],
          ),

          content: const Text(
            'Delete all prediction history permanently?',
          ),

          actions: [

            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },

              child:
                  const Text('Cancel'),
            ),

            ElevatedButton(

              style:
                  ElevatedButton.styleFrom(
                backgroundColor:
                    Colors.red.shade600,

                foregroundColor:
                    Colors.white,
              ),

              onPressed: () {

                setState(() {

                  _history.clear();
                });

                Navigator.pop(context);
              },

              child:
                  const Text('Delete All'),
            ),
          ],
        );
      },
    );
  }
}