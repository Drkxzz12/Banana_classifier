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

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> savedList = prefs.getStringList('banana_history') ?? [];
    
    setState(() {
      _history = savedList
          .map((item) => jsonDecode(item) as Map<String, dynamic>)
          .toList()
          .reversed // Show newest first
          .toList();
    });
  }

  Future<void> _clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('banana_history');
    setState(() {
      _history = [];
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Scan History"),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: _clearHistory,
            tooltip: "Clear History",
          )
        ],
      ),
      body: _history.isEmpty
          ? const Center(child: Text("No scans yet."))
          : ListView.builder(
              itemCount: _history.length,
              itemBuilder: (context, index) {
                final item = _history[index];
                final date = DateTime.parse(item['timestamp']);
                final formattedDate = DateFormat('MMM d, h:mm a').format(date);
                final confidence = (item['confidence'] * 100).toStringAsFixed(1);
                
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: _getColorForLabel(item['label']),
                      child: const Icon(Icons.history, color: Colors.white),
                    ),
                    title: Text(
                      item['label'],
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text("Confidence: $confidence%"),
                    trailing: Text(
                      formattedDate,
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ),
                );
              },
            ),
    );
  }

  Color _getColorForLabel(String label) {
    if (label.toLowerCase().contains('unripe')) return Colors.green;
    if (label.toLowerCase().contains('over')) return Colors.brown;
    return Colors.yellow.shade700; // Ripe
  }
}