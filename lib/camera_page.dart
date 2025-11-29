// ignore_for_file: deprecated_member_use

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart'; 
import 'package:tflite_flutter/tflite_flutter.dart';

class CameraPage extends StatefulWidget {
  final CameraDescription camera;
  final String modelPath;
  final String title;
  final XFile? preSelectedImage;

  const CameraPage({
    super.key,
    required this.camera,
    required this.modelPath,
    required this.title,
    this.preSelectedImage,
  });

  @override
  State<CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends State<CameraPage> {
  CameraController? _controller;
  Interpreter? _interpreter;
  List<String> _labels = ['Unripe', 'Ripe', 'Overripe'];
  bool _isBusy = false;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    // 1. Load Model
    try {
      _interpreter = await Interpreter.fromAsset(widget.modelPath);
      _interpreter!.allocateTensors();
    } catch (e) {
      _showError("Failed to load AI model. Please restart the app.");
      if (mounted) {
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) Navigator.pop(context);
        });
      }
      return;
    }

    // 2. Load Labels
    try {
      final labelData = await rootBundle.loadString('assets/models/labels.txt');
      final loaded = labelData.split('\n').where((s) => s.isNotEmpty).toList();
      if (loaded.isNotEmpty) setState(() => _labels = loaded);
    } catch (e) {
      debugPrint("Using fallback labels.");
    }

    // 3. Handle Gallery Image
    if (widget.preSelectedImage != null) {
      // Small delay to ensure UI is ready
      Future.delayed(Duration.zero, () {
        _analyzeFile(File(widget.preSelectedImage!.path));
      });
      return;
    }

    // 4. Setup Camera
    try {
      _controller = CameraController(
        widget.camera,
        ResolutionPreset.max, // Maximum quality for better crop
        enableAudio: false,
      );
      await _controller!.initialize();
      // Lock focus to auto to ensure sharpness
      await _controller!.setFocusMode(FocusMode.auto);
      if (mounted) setState(() {});
    } catch (e) {
      _showError("Failed to initialize camera: $e");
      if (mounted) {
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) Navigator.pop(context);
        });
      }
    }
  }

  Future<void> _takePictureAndClassify() async {
    if (_controller == null || !_controller!.value.isInitialized || _isBusy) return;
    setState(() => _isBusy = true);

    try {
      // Optional: Lock focus before snap
      await _controller!.setFocusMode(FocusMode.locked);
      final XFile file = await _controller!.takePicture();
      await _controller!.setFocusMode(FocusMode.auto); // Unlock
      
      await _analyzeFile(File(file.path));
    } catch (e) {
      _showError("Capture Error: $e");
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _analyzeFile(File imageFile) async {
    img.Image? image;
    try {
      final Uint8List bytes = await imageFile.readAsBytes();
      image = img.decodeImage(bytes);
      
      if (image == null) throw Exception("Could not decode image");

      // FIX: Rotate image if needed (exif data)
      if (Platform.isAndroid || Platform.isIOS) {
         image = img.bakeOrientation(image);
      }

      final prediction = await _runInference(image);
      
      if (mounted) {
        _showResultDialog(imageFile, prediction);
      }
    } catch (e) {
      _showError("Analysis Error: $e");
    } finally {
      // Image will be garbage collected automatically
      // No explicit cleanup needed for img.Image in package v3
    }
  }

  Future<Map<String, dynamic>> _runInference(img.Image image) async {
    if (_interpreter == null) return {'label': 'Error', 'confidence': 0.0};

    // ============================================================
    // 🧠 SMART CROP LOGIC
    // This improves accuracy by removing background noise.
    // We crop the Center Square of the image (matching the UI overlay).
    // ============================================================
    
    int size = math.min(image.width, image.height);
    
    // Calculate center coordinates
    int x = (image.width - size) ~/ 2;
    int y = (image.height - size) ~/ 2;

    // Crop to square (Version 3 compatible)
    img.Image cropped = img.copyCrop(image, x, y, size, size);

    // Resize the *cropped* banana to model size (224x224)
    img.Image resized = img.copyResize(cropped, width: 224, height: 224);

    // ============================================================

    // Create Input Tensor
    var input = List.generate(1, (i) => 
      List.generate(224, (y) => 
        List.generate(224, (x) {
          var pixel = resized.getPixel(x, y);
          // Using image package v3 (pixel is int)
          double r = img.getRed(pixel).toDouble();
          double g = img.getGreen(pixel).toDouble();
          double b = img.getBlue(pixel).toDouble();
          return [r, g, b];
        })
      )
    );

    var outputTensor = _interpreter!.getOutputTensor(0);
    var shape = outputTensor.shape;
    var outputClasses = shape.last;

    var output = List.filled(1 * outputClasses, 0.0).reshape([1, outputClasses]);

    _interpreter!.run(input, output);

    List<double> result = List<double>.from(output[0]);
    
    int maxIndex = 0;
    double maxScore = result[0];
    for (int i = 1; i < result.length; i++) {
      if (result[i] > maxScore) {
        maxScore = result[i];
        maxIndex = i;
      }
    }

    String label = "Unknown";
    if (maxIndex < _labels.length) {
      label = _labels[maxIndex];
    }

    return {'label': label, 'confidence': maxScore};
  }

  void _showResultDialog(File imageFile, Map<String, dynamic> result) {
    _saveToHistory(result);
    final confidence = result['confidence'] as double;
    final isLowConfidence = confidence < 0.6;
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text("Analysis Result"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(imageFile, height: 200, width: 200, fit: BoxFit.cover),
                ),
                // Show the crop area visually in result
                Container(
                  width: 200, height: 200,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.greenAccent, width: 2)
                  ),
                )
              ],
            ),
            const SizedBox(height: 15),
            Text(
              "${result['label']}",
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.green),
            ),
            Text(
              "Confidence: ${(confidence * 100).toStringAsFixed(1)}%",
              style: const TextStyle(fontSize: 16, color: Colors.grey),
            ),
            if (isLowConfidence) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.orange.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.warning_amber, color: Colors.orange, size: 20),
                    SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        "Low confidence. Try better lighting.",
                        style: TextStyle(fontSize: 12, color: Colors.orange),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              if (_controller == null) Navigator.pop(context);
            },
            child: Text(_controller == null ? "Close" : "Scan Again"),
          ),
        ],
      ),
    );
  }

    // 👇 2. HELPER FUNCTION TO SAVE
  Future<void> _saveToHistory(Map<String, dynamic> result) async {
    final prefs = await SharedPreferences.getInstance();
    List<String> history = prefs.getStringList('banana_history') ?? [];
    
    // Create a record
    final Map<String, dynamic> record = {
      'label': result['label'],
      'confidence': result['confidence'],
      'timestamp': DateTime.now().toIso8601String(),
    };

    // Add to list
    history.add(jsonEncode(record));
    
    // Keep only last 100 scans
    if (history.length > 100) {
      history = history.sublist(history.length - 100);
    }
    
    await prefs.setStringList('banana_history', history);
  }

  void _showError(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    _interpreter?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Gallery loading state
    if (_controller == null) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.title)),
        body: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 12),
              Text("Analyzing Image..."),
            ],
          ),
        ),
      );
    }

    if (!_controller!.value.isInitialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // Camera Mode
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: Colors.black87,
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          // 1. Full Screen Camera
          Center(child: CameraPreview(_controller!)),

          // 2. The Focus Overlay (Darkens outside, clear center)
          Positioned.fill(
            child: CustomPaint(
              painter: OverlayPainter(),
            ),
          ),

          // 3. Instructions
          const Positioned(
            top: 30,
            left: 0,
            right: 0,
            child: Text(
              "Center banana in the square",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white, 
                fontSize: 16, 
                shadows: [Shadow(blurRadius: 4, color: Colors.black)]
              ),
            ),
          ),

          // 4. Shutter Button
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 40),
              child: FloatingActionButton.large(
                backgroundColor: Colors.white,
                onPressed: _takePictureAndClassify,
                child: _isBusy 
                  ? const CircularProgressIndicator() 
                  : const Icon(Icons.camera, color: Colors.black, size: 50),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// 🖌️ Custom Painter to draw the specific Focus Box
class OverlayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black.withOpacity(0.5); // Darken background
    
    // Define the center square box
    final double boxSize = size.width * 0.8; // 80% of screen width
    final double left = (size.width - boxSize) / 2;
    final double top = (size.height - boxSize) / 2;
    final rect = Rect.fromLTWH(left, top, boxSize, boxSize);

    // Draw the "Cutout" logic
    // We draw a huge rectangle (screen) and subtract the center rectangle
    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRect(rect);
    
    // fillType evenOdd makes the inner rect transparent (the hole)
    path.fillType = PathFillType.evenOdd; 
    
    canvas.drawPath(path, paint);

    // Draw a Green Border around the cutout
    final borderPaint = Paint()
      ..color = Colors.greenAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    
    // Draw corner brackets (optional, just drawing simple box here for stability)
    canvas.drawRect(rect, borderPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}