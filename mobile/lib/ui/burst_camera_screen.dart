import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../capture/capture_controller.dart';
import '../capture/field_protocol.dart';
import '../data/models.dart';
import 'camera_support.dart';

/// Field capture (FR1, FR3): the camera stays open and every tap saves a
/// full-size photo, labelled with animal, time point and modality.
class BurstCameraScreen extends StatefulWidget {
  const BurstCameraScreen({
    super.key,
    required this.controller,
    required this.shotSet,
    required this.studyCode,
    required this.alreadyKept,
  });

  /// Already started with [CaptureController.startCollection].
  final CaptureController controller;
  final ShotSet shotSet;
  final String studyCode;
  final int alreadyKept;

  @override
  State<BurstCameraScreen> createState() => _BurstCameraScreenState();
}

class _BurstCameraScreenState extends State<BurstCameraScreen> {
  CameraController? _camera;
  String? _error;
  bool _taking = false;
  double _zoom = 1;
  double _maxZoom = 1;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final camera = await openBackCamera(ResolutionPreset.ultraHigh);
      if (!mounted) {
        await camera.dispose();
        return;
      }
      await camera.setFlashMode(FlashMode.off);
      _maxZoom = await camera.getMaxZoomLevel();
      // The protocol asks for 2x on the muzzle so the phone is not pushed close to the nose.
      if (widget.shotSet.modality == Modality.muzzle) await _setZoom(camera, 2);
      setState(() => _camera = camera);
    } on CameraException catch (e) {
      setState(() => _error = cameraErrorText(e));
    }
  }

  Future<void> _setZoom(CameraController camera, double zoom) async {
    final z = math.min(zoom, _maxZoom);
    await camera.setZoomLevel(z);
    if (mounted) setState(() => _zoom = z);
  }

  Future<void> _focus(TapUpDetails d, BoxConstraints box) async {
    final camera = _camera;
    if (camera == null) return;
    final point = Offset(
      (d.localPosition.dx / box.maxWidth).clamp(0, 1),
      (d.localPosition.dy / box.maxHeight).clamp(0, 1),
    );
    try {
      await camera.setFocusPoint(point);
      await camera.setExposurePoint(point);
    } on CameraException {
      // Some phones have a fixed focus point; capture still works.
    }
  }

  Future<void> _take() async {
    final camera = _camera;
    if (camera == null || _taking) return;
    setState(() => _taking = true);
    try {
      final file = await camera.takePicture();
      HapticFeedback.lightImpact();
      unawaited(widget.controller.addImage(file.path, move: true));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('The photo could not be taken. Try again.')));
      }
    }
    if (mounted) setState(() => _taking = false);
  }

  @override
  void dispose() {
    _camera?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final camera = _camera;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text('${widget.studyCode}: ${widget.shotSet.label}'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Done')),
        ],
      ),
      body: _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(_error!, style: const TextStyle(color: Colors.white)),
              ),
            )
          : camera == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: Center(
                    child: AspectRatio(
                      aspectRatio: 1 / camera.value.aspectRatio,
                      child: LayoutBuilder(
                        builder: (context, box) => GestureDetector(
                          onTapUp: (d) => _focus(d, box),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              CameraPreview(camera),
                              CaptureGuide(modality: widget.shotSet.modality),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                _BurstStatus(
                  controller: widget.controller,
                  target: widget.shotSet.target,
                  alreadyKept: widget.alreadyKept,
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  child: Row(
                    children: [
                      SegmentedButton<double>(
                        segments: [
                          const ButtonSegment(value: 1, label: Text('1x')),
                          if (_maxZoom >= 2) const ButtonSegment(value: 2, label: Text('2x')),
                        ],
                        selected: {_zoom},
                        onSelectionChanged: (z) => _setZoom(camera, z.single),
                        style: SegmentedButton.styleFrom(
                          foregroundColor: Colors.white,
                          selectedForegroundColor: Colors.black,
                          selectedBackgroundColor: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _taking ? null : _take,
                          icon: const Icon(Icons.camera),
                          label: const Text('Take photo'),
                          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(64)),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

/// Progress for this photo set and the result of the latest photo.
class _BurstStatus extends StatelessWidget {
  const _BurstStatus({required this.controller, required this.target, required this.alreadyKept});

  final CaptureController controller;
  final int target;
  final int alreadyKept;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final count = alreadyKept + controller.keptCount;
      final done = count >= target;
      final last = controller.items.lastOrNull;
      return Container(
        color: done ? const Color(0xFF1B7F3B) : Colors.black87,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            if (last != null)
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.file(
                    File(last.path),
                    width: 48,
                    height: 48,
                    fit: BoxFit.cover,
                    cacheWidth: 96,
                    errorBuilder: (_, _, _) => const SizedBox(width: 48, height: 48),
                  ),
                ),
              ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    done ? '$count of $target. Done, or take extra.' : '$count of $target photos',
                    style: const TextStyle(color: Colors.white, fontSize: 18),
                  ),
                  if (last != null) _LastShot(item: last),
                ],
              ),
            ),
            if (last != null && last.state == ItemState.failed && last.issues.isNotEmpty)
              TextButton(
                onPressed: () => controller.setKept(last, !last.kept),
                style: TextButton.styleFrom(foregroundColor: Colors.white),
                child: Text(last.kept ? 'Undo keep' : 'Keep anyway'),
              ),
          ],
        ),
      );
    },
  );
}

class _LastShot extends StatelessWidget {
  const _LastShot({required this.item});

  final CaptureItem item;

  @override
  Widget build(BuildContext context) {
    final text = switch (item.state) {
      ItemState.analysing => 'Checking...',
      ItemState.passed => 'Last photo accepted',
      ItemState.failed when item.kept => 'Kept despite quality warning',
      ItemState.failed when item.issues.isNotEmpty => 'Retake: ${item.issues.first.message}',
      ItemState.failed => item.message ?? 'The photo could not be read.',
    };
    return Text(text, style: const TextStyle(color: Colors.white70));
  }
}
