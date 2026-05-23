// lib/screens/history_screen.dart

import 'package:flutter/material.dart';

import '../services/cache_service.dart';
import '../services/local_history_service.dart';
import '../services/supabase_history_service.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  SupabaseHistoryService? _historyService;

  // Raw maps — no separate HistoryItem model needed.
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initAndLoad();
  }

  Future<void> _initAndLoad() async {
    final cache = CacheService();
    await cache.init();
    _historyService = SupabaseHistoryService(
      cache: cache,
      localHistoryService: LocalHistoryService(cache: cache),
    );
    await _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await _historyService!.getHistory();
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (_) {
      setState(() {
        _error = 'Failed to load history.';
        _loading = false;
      });
    }
  }

  Future<void> _deleteItem(String id) async {
    await _historyService!.deleteHistoryItem(id);
    setState(() => _items.removeWhere((i) => i['id']?.toString() == id));
  }

  Future<void> _clearAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Clear History'),
        content: const Text('Delete all scan history? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _historyService!.clearHistory();
      setState(() => _items.clear());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: _loadHistory, child: const Text('Retry')),
          ],
        ),
      );
    }

    if (_items.isEmpty) {
      return const Center(
        child: Text('No scans yet. Start by scanning a leaf!'),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadHistory,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        // +1 for the header row
        itemCount: _items.length + 1,
        separatorBuilder: (_, i) => i == 0
            ? const SizedBox(height: 12)
            : const SizedBox(height: 8),
        itemBuilder: (context, index) {
          // First slot: scan count + clear-all button
          if (index == 0) {
            return Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${_items.length} scan${_items.length == 1 ? "" : "s"}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.grey,
                        fontWeight: FontWeight.w500,
                      ),
                ),
                TextButton.icon(
                  onPressed: _clearAll,
                  icon: const Icon(Icons.delete_sweep, size: 18),
                  label: const Text('Clear all'),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.red.shade400,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            );
          }
          final item = _items[index - 1];
          return _HistoryCard(
            item: item,
            onDelete: () => _deleteItem(item['id'].toString()),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Card widget — reads directly from the raw Map.
// Keys: id, prediction, display_name, confidence, plant_type, created_at
// ---------------------------------------------------------------------------
class _HistoryCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final VoidCallback onDelete;

  const _HistoryCard({required this.item, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final displayName = item['display_name']?.toString() ?? 'Unknown';
    final prediction = item['prediction']?.toString() ?? '-';
    final confidence = (item['confidence'] as num?)?.toDouble() ?? 0.0;
    final createdAt = _parseDate(item['created_at']);

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          child: const Icon(Icons.eco),
        ),
        title: Text(
          displayName,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(prediction),
            Text(
              'Confidence: ${(confidence * 100).toStringAsFixed(1)}%',
              style: const TextStyle(fontSize: 12),
            ),
            if (createdAt != null)
              Text(
                _formatDate(createdAt),
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
          ],
        ),
        isThreeLine: true,
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline, color: Colors.red),
          onPressed: onDelete,
        ),
      ),
    );
  }

  DateTime? _parseDate(dynamic raw) {
    if (raw == null) return null;
    try {
      return DateTime.parse(raw.toString()).toLocal();
    } catch (_) {
      return null;
    }
  }

  String _formatDate(DateTime dt) =>
      '${dt.day}/${dt.month}/${dt.year}  '
      '${dt.hour.toString().padLeft(2, '0')}:'
      '${dt.minute.toString().padLeft(2, '0')}';
}