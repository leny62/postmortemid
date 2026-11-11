import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../data/models.dart';

/// Opens the back camera at [preset], falling back to high on phones that
/// reject the larger preset.
Future<CameraController> openBackCamera(ResolutionPreset preset) async {
  final cameras = await availableCameras();
  if (cameras.isEmpty) throw CameraException('NoCamera', 'No camera found on this device.');
  final back = cameras.firstWhere(
    (c) => c.lensDirection == CameraLensDirection.back,
    orElse: () => cameras.first,
  );
  for (final p in {preset, ResolutionPreset.high}) {
    final controller = CameraController(back, p, enableAudio: false);
    try {
      await controller.initialize();
      return controller;
    } on CameraException catch (e) {
      await controller.dispose();
      if (p == ResolutionPreset.high || e.code == 'CameraAccessDenied') rethrow;
    }
  }
  throw StateError('unreachable');
}

String cameraErrorText(CameraException e) => switch (e.code) {
  'CameraAccessDenied' => 'Camera permission was denied. Allow camera access in system settings.',
  'NoCamera' => 'No camera found on this device.',
  _ => 'The camera could not be opened.',
};

/// On-screen framing guide: a square for the muzzle, a tall frame for the face.
class CaptureGuide extends StatelessWidget {
  const CaptureGuide({super.key, this.modality = Modality.muzzle});

  final Modality modality;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final side = box.biggest.shortestSide * 0.9;
      final (width, height, hint) = switch (modality) {
        Modality.muzzle => (side, side, 'Fill the square with the muzzle. Hold still.'),
        Modality.face => (side * 0.75, side, 'Whole face from the front, both eyes visible.'),
      };
      return IgnorePointer(
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: width,
              height: height,
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
                child: Text(hint, style: const TextStyle(color: Colors.white)),
              ),
            ),
          ],
        ),
      );
    },
  );
}
