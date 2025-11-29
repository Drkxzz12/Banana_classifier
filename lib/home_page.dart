// ignore_for_file: use_build_context_synchronously, deprecated_member_use

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'camera_page.dart';
import 'history_page.dart'; // 👈 Import the new page
import 'main.dart'; 

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  void _showSelectionDialog(BuildContext context, String mode) {
    // ... (Keep your existing _showSelectionDialog logic exactly as is) ...
    // Copy-paste your existing _showSelectionDialog code here
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text("Select Source for $mode", style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _OptionButton(icon: Icons.camera_alt, label: "Camera", color: Colors.blue, onTap: () {
                    Navigator.pop(ctx);
                    _navigateToCamera(context, mode, null);
                  }),
                  _OptionButton(icon: Icons.photo_library, label: "Gallery", color: Colors.purple, onTap: () async {
                    Navigator.pop(ctx);
                    await _pickFromGallery(context, mode);
                  }),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _pickFromGallery(BuildContext context, String mode) async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1920, // Limit size for performance
      maxHeight: 1920,
      imageQuality: 85,
    );
    if (image != null) {
      _navigateToCamera(context, mode, image);
    }
  }

  void _navigateToCamera(BuildContext context, String mode, XFile? preSelectedImage) {
    if (cameras.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("No camera found!")));
      return;
    }

    String modelName = (mode == 'bunch') ? 'banana_ripeness_bunch.tflite' : 'banana_ripeness_individual.tflite';

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CameraPage(
          camera: cameras.first,
          modelPath: 'assets/models/$modelName',
          title: mode == 'bunch' ? 'Bunch Mode' : 'Individual Mode',
          preSelectedImage: preSelectedImage,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Select Mode"), 
        centerTitle: true,
        // 👇 ADD THIS ACTION
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: "View History",
            onPressed: () {
              Navigator.push(
                context, 
                MaterialPageRoute(builder: (context) => const HistoryPage())
              );
            },
          )
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildMainButton(context, "🍌 Individual Banana", Colors.lightGreen, () => _showSelectionDialog(context, 'individual')),
            const SizedBox(height: 20),
            _buildMainButton(context, "🌳 Banana Bunch", Colors.teal, () => _showSelectionDialog(context, 'bunch')),
          ],
        ),
      ),
    );
  }

  Widget _buildMainButton(BuildContext context, String text, Color color, VoidCallback onTap) {
    return SizedBox(
      width: 250,
      height: 60,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        ),
        onPressed: onTap,
        child: Text(text, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      ),
    );
  }
}

// Keep your _OptionButton class exactly the same
class _OptionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _OptionButton({required this.icon, required this.label, required this.color, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 100,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: color.withOpacity(0.3))),
        child: Column(children: [Icon(icon, size: 40, color: color), const SizedBox(height: 8), Text(label, style: TextStyle(color: color, fontWeight: FontWeight.bold))]),
      ),
    );
  }
}