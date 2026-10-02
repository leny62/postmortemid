import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../capture/capture_controller.dart';
import 'camera_screen.dart';

/// Capture and import buttons plus a list of images with their quality result.
class CapturePanel extends StatelessWidget {
  const CapturePanel({super.key, required this.controller, this.maxImages});

  final CaptureController controller;
  final int? maxImages;

  Future<void> _capture(BuildContext context) async {
    final path = await Navigator.of(
      context,
    ).push<String>(MaterialPageRoute(builder: (_) => const CameraScreen()));
    if (path != null) await controller.addImage(path);
  }

  Future<void> _choose() async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 2048);
    if (file != null) await controller.addImage(file.path);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final full = maxImages != null && controller.passedItems.length >= maxImages!;
        final canAdd = !controller.busy && !full;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: canAdd ? () => _capture(context) : null,
                    icon: const Icon(Icons.photo_camera),
                    label: const Text('Capture'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: canAdd ? _choose : null,
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('Choose image'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            for (final item in controller.items.reversed)
              CaptureItemTile(item: item, onRemove: () => controller.removeItem(item)),
          ],
        );
      },
    );
  }
}

class CaptureItemTile extends StatelessWidget {
  const CaptureItemTile({super.key, required this.item, this.onRemove});

  final CaptureItem item;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final (icon, color, title) = switch (item.state) {
      ItemState.analysing => (Icons.hourglass_top, Colors.grey, 'Checking image...'),
      ItemState.passed => (Icons.check_circle, const Color(0xFF1B7F3B), 'Image accepted'),
      ItemState.failed => (Icons.error, const Color(0xFFB3261E), 'Please capture again'),
    };
    final reasons = item.issues.map((i) => i.message).join('\n');
    final failedText = reasons.isEmpty ? 'This file could not be read as an image.' : reasons;
    return Card.outlined(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.file(
                File(item.path),
                width: 56,
                height: 56,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const SizedBox(width: 56, height: 56),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(icon, color: color, size: 18),
                      const SizedBox(width: 6),
                      Text(title, style: Theme.of(context).textTheme.titleSmall),
                    ],
                  ),
                  if (item.state == ItemState.failed) ...[
                    const SizedBox(height: 4),
                    Text(failedText),
                  ],
                ],
              ),
            ),
            if (item.state != ItemState.analysing && onRemove != null)
              IconButton(tooltip: 'Remove', icon: const Icon(Icons.close), onPressed: onRemove),
          ],
        ),
      ),
    );
  }
}
