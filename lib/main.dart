// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final List<CameraDescription> cameras = await availableCameras();
  runApp(BananaClassifierApp(availableCameras: cameras));
}

class BananaClassifierApp extends StatelessWidget {
  const BananaClassifierApp({super.key, this.availableCameras = const []});

  final List<CameraDescription> availableCameras;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Banana Ripeness',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
        useMaterial3: true,
      ),
      home: CameraClassifierPage(availableCameras: availableCameras),
    );
  }
}

class CameraClassifierPage extends StatefulWidget {
  const CameraClassifierPage({super.key, required this.availableCameras});

  final List<CameraDescription> availableCameras;

  @override
  State<CameraClassifierPage> createState() => _CameraClassifierPageState();
}

class _CameraClassifierPageState extends State<CameraClassifierPage> {
  static const _labels = ['Unripe', 'Ripe', 'Overripe'];
  static const _modelAsset = 'assets/models/banana_ripeness.tflite';

  CameraController? _cameraController;
  CameraDescription? _activeCamera;
  final ImagePicker _imagePicker = ImagePicker();

  Interpreter? _interpreter;
  List<int>? _inputShape;
  List<int>? _outputShape;
  late int _inputWidth;
  late int _inputHeight;
  // ignore: unused_field
  late int _outputClasses;

  Prediction _latestPrediction = const Prediction(label: '---', confidence: 0);
  String _statusMessage = 'Initializing camera and model...';

  bool _isProcessingFrame = false;
  bool _cameraStreamActive = false;
  Uint8List? _lastUploadPreview;

  @override
  void initState() {
    super.initState();
    _activeCamera = widget.availableCameras.isNotEmpty ? widget.availableCameras.first : null;
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await Future.wait([
      _initializeInterpreter(),
      _initializeCamera(),
    ]);
    if (!mounted) return;
    setState(() {
      _statusMessage = _isReady
          ? 'Point the camera at a banana to see ripeness.'
          : 'Camera or model failed to initialize.';
    });
  }

  Future<void> _initializeInterpreter() async {
    try {
      final options = InterpreterOptions()
        ..threads = 2
        ..useNnApiForAndroid = Platform.isAndroid;

      final interpreter = await Interpreter.fromAsset(_modelAsset, options: options);
      final inputTensor = interpreter.getInputTensor(0);
      final outputTensor = interpreter.getOutputTensor(0);

      _inputShape = inputTensor.shape;
      _outputShape = outputTensor.shape;
      _inputHeight = _inputShape![1];
      _inputWidth = _inputShape![2];
      _outputClasses = _outputShape!.isNotEmpty ? _outputShape!.last : _labels.length;

      setState(() {
        _interpreter = interpreter;
      });
    } catch (e) {
      setState(() {
        _statusMessage = 'Failed to load model: $e';
      });
    }
  }

  Future<void> _initializeCamera() async {
    if (_activeCamera == null) {
      setState(() {
        _statusMessage = 'No cameras were found on this device.';
      });
      return;
    }

    final controller = CameraController(
      _activeCamera!,
      ResolutionPreset.low,
      enableAudio: false,
      imageFormatGroup: Platform.isIOS ? ImageFormatGroup.bgra8888 : ImageFormatGroup.yuv420,
    );

    try {
      await controller.initialize();
      await _startImageStream();
      if (!mounted) return;
      setState(() {
        _cameraController = controller;
      });
    } catch (e) {
      await controller.dispose();
      setState(() {
        _statusMessage = 'Camera error: $e';
      });
    }
  }

  Future<void> _startImageStream() async {
    if (_cameraController == null || _cameraStreamActive) return;
    await _cameraController!.startImageStream(_processCameraImage);
    _cameraStreamActive = true;
  }

  Future<void> _stopImageStream() async {
    if (_cameraController == null || !_cameraStreamActive) return;
    await _cameraController!.stopImageStream();
    _cameraStreamActive = false;
  }

  bool get _isReady =>
      _cameraController?.value.isInitialized == true &&
      _interpreter != null &&
      _inputShape != null &&
      _outputShape != null;

  void _processCameraImage(CameraImage image) {
    if (!_isReady || _isProcessingFrame) return;

    _isProcessingFrame = true;
    _runInference(image).whenComplete(() => _isProcessingFrame = false);
  }

  Future<void> _runInference(CameraImage image) async {
    try {
      final img.Image processed = _prepareCameraImage(image);
      final prediction = await _predictFromImage(processed);

      if (!mounted) return;
      setState(() {
        _latestPrediction = prediction;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _statusMessage = 'Processing error: $e';
      });
    }
  }

  img.Image _prepareCameraImage(CameraImage image) {
    final img.Image rgbImage = _convertCameraImage(image);
    return _applyOrientation(rgbImage);
  }

  img.Image _applyOrientation(img.Image image) {
    final rotation = _cameraController?.description.sensorOrientation ?? 0;
    if (rotation == 0) return image;
    return img.copyRotate(image, rotation.toDouble());
  }

  img.Image _convertCameraImage(CameraImage image) {
    if (image.format.group == ImageFormatGroup.bgra8888) {
      return _convertBGRA8888(image);
    }
    return _convertYUV420(image);
  }

  img.Image _convertBGRA8888(CameraImage image) {
    final plane = image.planes.first;
    final bytes = plane.bytes;
    final img.Image rgbImage = img.Image(image.width, image.height);

    int pixelIndex = 0;
    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final int b = bytes[pixelIndex++];
        final int g = bytes[pixelIndex++];
        final int r = bytes[pixelIndex++];
        final int a = bytes[pixelIndex++];
        rgbImage.setPixelRgba(x, y, r, g, b, a);
      }
    }
    return rgbImage;
  }

  img.Image _convertYUV420(CameraImage image) {
    final int width = image.width;
    final int height = image.height;
    final img.Image rgbImage = img.Image(width, height);

    final Plane yPlane = image.planes[0];
    final Plane uPlane = image.planes[1];
    final Plane vPlane = image.planes[2];

    final int uvRowStride = uPlane.bytesPerRow;
    final int uvPixelStride = uPlane.bytesPerPixel ?? 1;

    for (int y = 0; y < height; y++) {
      final int yRow = y * yPlane.bytesPerRow;
      final int uvRow = (y >> 1) * uvRowStride;

      for (int x = 0; x < width; x++) {
        final int uvIndex = uvRow + (x >> 1) * uvPixelStride;
        final int yIndex = yRow + x;

        final int yp = yPlane.bytes[yIndex];
        final int up = uPlane.bytes[uvIndex];
        final int vp = vPlane.bytes[uvIndex];

        final double r = yp + 1.403 * (vp - 128);
        final double g = yp - 0.344 * (up - 128) - 0.714 * (vp - 128);
        final double b = yp + 1.770 * (up - 128);

        rgbImage.setPixelRgba(
          x,
          y,
          _clampTo8Bit(r),
          _clampTo8Bit(g),
          _clampTo8Bit(b),
          255,
        );
      }
    }

    return rgbImage;
  }

  List<List<List<List<double>>>> _createInputTensor(img.Image image) {
    return [
      List.generate(
        _inputHeight,
        (y) => List.generate(
          _inputWidth,
          (x) {
            final int pixel = image.getPixel(x, y);
            final double r = img.getRed(pixel) / 255.0;
            final double g = img.getGreen(pixel) / 255.0;
            final double b = img.getBlue(pixel) / 255.0;
            return [r, g, b];
          },
        ),
      ),
    ];
  }

  img.Image _resizeToInput(img.Image image) {
    return img.copyResize(
      image,
      width: _inputWidth,
      height: _inputHeight,
      interpolation: img.Interpolation.linear,
    );
  }

  Future<Prediction> _predictFromImage(img.Image image) async {
    final img.Image resized = _resizeToInput(image);
    final inputTensor = _createInputTensor(resized);
    final List<List<double>> output = [List<double>.filled(_outputClasses, 0)];
    _interpreter!.run(inputTensor, output);
    final normalized = _softmax(output.first);
    return _mapPrediction(normalized);
  }

  Prediction _mapPrediction(List<double> probabilities) {
    int maxIndex = 0;
    double maxScore = probabilities.first;
    for (int i = 1; i < probabilities.length; i++) {
      if (probabilities[i] > maxScore) {
        maxScore = probabilities[i];
        maxIndex = i;
      }
    }
    final label = maxIndex < _labels.length ? _labels[maxIndex] : 'Unknown';
    return Prediction(label: label, confidence: maxScore);
  }

  List<double> _softmax(List<double> logits) {
    if (logits.isEmpty) return logits;
    final double maxLogit = logits.reduce(math.max);
    final List<double> exps = logits.map((value) => math.exp(value - maxLogit)).toList();
    final double sum = exps.reduce((a, b) => a + b);
    if (sum == 0 || sum.isNaN) {
      return List<double>.filled(logits.length, 0);
    }
    return exps.map((value) => value / sum).toList();
  }

  int _clampTo8Bit(double value) => value.clamp(0, 255).toInt();

  Future<void> _pickAndClassifyPhoto() async {
    if (_interpreter == null || _isProcessingFrame) return;
    _isProcessingFrame = true;
    final controller = _cameraController;
    try {
      await _stopImageStream();
      final XFile? file = await _imagePicker.pickImage(source: ImageSource.gallery);
      if (file == null) {
        return;
      }
      final bytes = await file.readAsBytes();
      final img.Image? decoded = img.decodeImage(bytes);
      if (decoded == null) {
        if (!mounted) return;
        setState(() {
          _statusMessage = 'Failed to decode selected image.';
        });
        return;
      }
      final prediction = await _predictFromImage(decoded);
      if (!mounted) return;
      setState(() {
        _latestPrediction = prediction;
        _statusMessage = 'Classified uploaded photo.';
        _lastUploadPreview = Uint8List.fromList(img.encodeJpg(decoded));
      });
      if (!mounted) return;
      await _showUploadResult(prediction);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _statusMessage = 'Upload error: $e';
      });
    } finally {
      _isProcessingFrame = false;
      if (controller != null && controller.value.isInitialized) {
        await _startImageStream();
      }
    }
  }

  Future<void> _switchCamera() async {
    if (widget.availableCameras.length < 2 || _activeCamera == null) return;
    final currentIndex = widget.availableCameras.indexOf(_activeCamera!);
    final nextIndex = (currentIndex + 1) % widget.availableCameras.length;
    _activeCamera = widget.availableCameras[nextIndex];

    final previousController = _cameraController;
    setState(() {
      _cameraController = null;
      _statusMessage = 'Switching camera...';
    });

    if (previousController != null) {
      await previousController.stopImageStream();
      await previousController.dispose();
    }

    await _initializeCamera();
  }

  Future<void> _showUploadResult(Prediction prediction) async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 24,
            bottom: MediaQuery.of(context).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.green),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Photo classified',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (_lastUploadPreview != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.memory(
                    _lastUploadPreview!,
                    fit: BoxFit.cover,
                  ),
                ),
              const SizedBox(height: 16),
              Text(
                prediction.label,
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(color: Colors.green.shade700),
              ),
              const SizedBox(height: 8),
              Text(
                'Confidence: ${(prediction.confidence * 100).toStringAsFixed(1)}%',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'Result shown here so it doesn\'t block the camera preview.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    final controller = _cameraController;
    _cameraController = null;
    controller?.dispose();
    _interpreter?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Banana Ripeness'),
        actions: [
          if (widget.availableCameras.length > 1)
            IconButton(
              icon: const Icon(Icons.cameraswitch),
              tooltip: 'Switch camera',
              onPressed: _cameraController == null ? null : _switchCamera,
            ),
        ],
      ),
      body: SafeArea(
        child: _buildBody(),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: (_interpreter == null) ? null : _pickAndClassifyPhoto,
        icon: const Icon(Icons.photo_library_outlined),
        label: const Text('Upload photo'),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  Widget _buildBody() {
    if (_cameraController == null) {
      return _buildCenteredMessage(_statusMessage);
    }

    return Stack(
      children: [
        Positioned.fill(
          child: _cameraController!.value.isInitialized
              ? CameraPreview(_cameraController!)
              : const Center(child: CircularProgressIndicator()),
        ),
        Positioned(
          left: 16,
          right: 16,
          top: 16,
          child: _StatusBanner(
            isReady: _isReady,
            message: _statusMessage,
            showInstructions: _cameraController?.value.isInitialized == true,
          ),
        ),
        Positioned(
          left: 16,
          right: 16,
          bottom: 110,
          child: PredictionCard(prediction: _latestPrediction),
        ),
      ],
    );
  }

  Widget _buildCenteredMessage(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ),
    );
  }
}

class Prediction {
  const Prediction({required this.label, required this.confidence});

  final String label;
  final double confidence;
}

class PredictionCard extends StatelessWidget {
  const PredictionCard({super.key, required this.prediction});

  final Prediction prediction;

  @override
  Widget build(BuildContext context) {
    final double confidencePercent = (prediction.confidence * 100).clamp(0, 100).toDouble();
    final String confidenceLabel;
    if (prediction.confidence >= 0.8) {
      confidenceLabel = 'High confidence';
    } else if (prediction.confidence >= 0.5) {
      confidenceLabel = 'Medium confidence';
    } else {
      confidenceLabel = 'Low confidence';
    }

    return Card(
      color: Colors.black.withOpacity(0.45),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Prediction',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(color: Colors.white70),
            ),
            const SizedBox(height: 8),
            Text(
              prediction.label,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(color: Colors.white),
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: prediction.confidence.clamp(0, 1).toDouble(),
              minHeight: 6,
              color: Colors.greenAccent,
              backgroundColor: Colors.white24,
            ),
            const SizedBox(height: 4),
            Text(
              '$confidenceLabel (${confidencePercent.toStringAsFixed(0)}%)',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({
    required this.isReady,
    required this.message,
    this.showInstructions = false,
  });

  final bool isReady;
  final String message;
  final bool showInstructions;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: isReady ? Colors.green.withOpacity(0.8) : Colors.orange.withOpacity(0.8),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(isReady ? Icons.check_circle : Icons.warning_amber, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    message,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white),
                  ),
                ),
              ],
            ),
            if (showInstructions && isReady) ...[
              const SizedBox(height: 8),
              Text(
                'Tip: Keep the camera steady over a banana to classify instantly, '
                'or tap "Upload photo" to analyze a saved picture without blocking the viewfinder.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white70),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

