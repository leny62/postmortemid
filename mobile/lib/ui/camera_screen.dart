import 'dart:io';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import 'camera_support.dart';

/// Keeps only the centre square of a photo, the area inside the on-screen guide.
/// Until a detector finds the muzzle, this is what makes a phone photo look
/// like the muzzle crops the model was trained on.
String cropToGuide(String path) {
  final photo = img.bakeOrientation(img.decodeImage(File(path).readAsBytesSync())!);
  final side = math.min(photo.width, photo.height);
  final square = img.copyCrop(
    photo,
    x: (photo.width - side) ~/ 2,
    y: (photo.height - side) ~/ 2,
    width: side,
    height: side,
  );
  final out = path.replaceFirst(RegExp(r'\.\w+$'), '_guide.jpg');
  File(out).writeAsBytesSync(img.encodeJpg(square, quality: 95));
  return out;
}

/// Guided capture (FR1): a square guide shows where the muzzle should be,
/// and the saved image is cropped to that square.
class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  CameraController? _controller;
  String? _error;
  bool _taking = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final controller = await openBackCamera(ResolutionPreset.high);
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _controller = controller);
    } on CameraException catch (e) {
      setState(() => _error = cameraErrorText(e));
    }
  }

  Future<void> _take() async {
    final controller = _controller;
    if (controller == null || _taking) return;
    setState(() => _taking = true);
    try {
      final file = await controller.takePicture();
      final square = await compute(cropToGuide, file.path);
      if (mounted) Navigator.of(context).pop(square);
    } catch (_) {
      if (!mounted) return;
      setState(() => _taking = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('The photo could not be taken. Try again.')));
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: const Text('Capture muzzle')),
      body: _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(_error!, style: const TextStyle(color: Colors.white)),
              ),
            )
          : controller == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: Center(
                    child: AspectRatio(
                      aspectRatio: 1 / controller.value.aspectRatio,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [CameraPreview(controller), const CaptureGuide()],
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: FilledButton.icon(
                    onPressed: _taking ? null : _take,
                    icon: const Icon(Icons.camera),
                    label: const Text('Capture'),
                  ),
                ),
              ],
            ),
    );
  }
}
