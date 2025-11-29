import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  List<Map<String, dynamic>> _history = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() => _isLoading = true);
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final List<String> savedList = prefs.getStringList('banana_history') ?? [];
      
      setState(() {
        _history = savedList
            .map((item) {
              try {
                return jsonDecode(item) as Map<String, dynamic>;
              } catch (e) {
                debugPrint('Error decoding history item: $e');
                return null;
              }
            })
            .whereType<Map<String, dynamic>>()
            .toList()
            .reversed // Show newest first
            .toList();
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading history: $e');
      setState(() {
        _history = [];
        _isLoading = false;
      });
    }
  }

  Future<void> _clearHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear History'),
        content: const Text('Are you sure you want to delete all scan history?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Clear'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('banana_history');
      setState(() {
        _history = [];
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('History cleared')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Scan History"),
        actions: [
          if (_history.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: _clearHistory,
              tooltip: "Clear History",
            )
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _history.isEmpty
              ? RefreshIndicator(
                  onRefresh: _loadHistory,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    child: SizedBox(
                      height: MediaQuery.of(context).size.height * 0.7,
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.history,
                              size: 64,
                              color: Colors.grey.shade400,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              "No scans yet",
                              style: TextStyle(
                                fontSize: 18,
                                color: Colors.grey.shade600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              "Your scan history will appear here",
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey.shade500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadHistory,
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: _history.length,
                    itemBuilder: (context, index) {
                    final item = _history[index];
                    final date = DateTime.parse(item['timestamp']);
                    final formattedDate = DateFormat('MMM d, h:mm a').format(date);
                    final confidence = (item['confidence'] * 100).toStringAsFixed(1);
                    final label = item['label'] ?? 'Unknown';
                    
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      elevation: 2,
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        leading: CircleAvatar(
                          backgroundColor: _getColorForLabel(label),
                          child: const Icon(Icons.eco, color: Colors.white),
                        ),
                        title: Text(
                          label,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(
                                  Icons.check_circle,
                                  size: 14,
                                  color: Colors.grey.shade600,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  "Confidence: $confidence%",
                                  style: TextStyle(
                                    color: Colors.grey.shade700,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                Icon(
                                  Icons.access_time,
                                  size: 14,
                                  color: Colors.grey.shade600,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  formattedDate,
                                  style: TextStyle(
                                    color: Colors.grey.shade600,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        trailing: _getConfidenceIndicator(item['confidence']),
                      ),
                    );
                  },
                  ),
                ),
    );
  }

  Color _getColorForLabel(String label) {
    final lowerLabel = label.toLowerCase();
    
    // Handle various label formats
    if (lowerLabel.contains('unripe') || lowerLabel.contains('not ripe')) {
      return Colors.green;
    }
    if (lowerLabel.contains('over')) {
      return Colors.brown;
    }
    if (lowerLabel.contains('ripe')) {
      return Colors.orange; // Changed from yellow for better visibility
    }
    if (lowerLabel.contains('not banana')) {
      return Colors.grey;
    }
    
    return Colors.blue; // Default/Unknown
  }

  Widget _getConfidenceIndicator(double confidence) {
    final IconData icon;
    final Color color;
    
    if (confidence >= 0.8) {
      icon = Icons.sentiment_very_satisfied;
      color = Colors.green;
    } else if (confidence >= 0.5) {
      icon = Icons.sentiment_satisfied;
      color = Colors.orange;
    } else {
      icon = Icons.sentiment_dissatisfied;
      color = Colors.red;
    }
    
    return Icon(icon, color: color, size: 28);
  }
}