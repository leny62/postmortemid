import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

/// Guided capture (FR1): a square guide shows where the muzzle should be.
/// The analysis uses the centre square of the photo, which is this guide area.
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
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() => _error = 'No camera found on this device.');
        return;
      }
      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(back, ResolutionPreset.high, enableAudio: false);
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _controller = controller);
    } on CameraException catch (e) {
      setState(
        () => _error = e.code == 'CameraAccessDenied'
            ? 'Camera permission was denied. Allow camera access in system settings.'
            : 'The camera could not be opened.',
      );
    }
  }

  Future<void> _take() async {
    final controller = _controller;
    if (controller == null || _taking) return;
    setState(() => _taking = true);
    try {
      final file = await controller.takePicture();
      if (mounted) Navigator.of(context).pop(file.path);
    } on CameraException {
      if (mounted) setState(() => _taking = false);
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
                        children: [CameraPreview(controller), const _Guide()],
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

class _Guide extends StatelessWidget {
  const _Guide();

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final side = box.biggest.shortestSide * 0.9;
      return Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: side,
            height: side,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white, width: 3),
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          Positioned(
            bottom: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              color: Colors.black54,
              child: const Text(
                'Fill the square with the muzzle. Hold still.',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ),
        ],
      );
    },
  );
}
