import 'package:flutter/material.dart';

import '../capture/capture_controller.dart';
import '../data/models.dart';
import 'capture_panel.dart';
import 'result_screen.dart';

class VerifyScreen extends StatefulWidget {
  const VerifyScreen({super.key, required this.services});

  final AppServices services;

  @override
  State<VerifyScreen> createState() => _VerifyScreenState();
}

class _VerifyScreenState extends State<VerifyScreen> {
  late final Future<List<Animal>> _animals = widget.services.repository.enrolledAnimals(
    widget.services.modelVersion,
  );
  late final CaptureController _controller = CaptureController(widget.services);
  Animal? _claimed;
  TimePoint? _timePoint;
  bool _started = false;
  bool _running = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    if (_timePoint != TimePoint.t0 && !await _confirmPostMortem()) return;
    await _controller.startVerification(_claimed!, _timePoint!);
    setState(() => _started = true);
  }

  /// Images are stored under the chosen time point, so a live image filed as
  /// P0 or P1 would corrupt the study data.
  Future<bool> _confirmPostMortem() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Record as ${_timePoint!.code}?'),
        content: const Text(
          'Use P0 or P1 only for images of the animal after slaughter. '
          'Images of a live animal belong to T0.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Record as ${_timePoint!.code}'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<void> _verify() async {
    setState(() => _running = true);
    final messenger = ScaffoldMessenger.of(context);
    final VerificationOutcome outcome;
    try {
      outcome = await _controller.verify(_controller.passedItems.last);
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Verification could not be completed. Try again.')),
      );
      if (mounted) setState(() => _running = false);
      return;
    }
    if (!mounted) return;
    final manifest = widget.services.manifest;
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => ResultScreen(
          outcome: outcome,
          isResearchModel: manifest.encoder.isResearchModel,
          calibration: manifest.calibration,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Verify')),
      body: FutureBuilder<List<Animal>>(
        future: _animals,
        builder: (context, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final animals = snap.data!;
          if (animals.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No enrolled animals yet. Enrol an animal first.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              DropdownButtonFormField<Animal>(
                initialValue: _claimed,
                decoration: const InputDecoration(labelText: 'Claimed animal'),
                items: [
                  for (final a in animals) DropdownMenuItem(value: a, child: Text(a.studyCode)),
                ],
                onChanged: _started ? null : (a) => setState(() => _claimed = a),
              ),
              const SizedBox(height: 16),
              Text('Query time point', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 8),
              SegmentedButton<TimePoint>(
                emptySelectionAllowed: true,
                segments: [
                  for (final t in TimePoint.values)
                    ButtonSegment(value: t, label: Text(t.code), tooltip: t.label),
                ],
                selected: {?_timePoint},
                onSelectionChanged: _started
                    ? null
                    : (s) => setState(() => _timePoint = s.isEmpty ? null : s.first),
              ),
              if (_timePoint != null) ...[const SizedBox(height: 4), Text(_timePoint!.label)],
              const SizedBox(height: 16),
              if (!_started)
                FilledButton(
                  onPressed: _claimed != null && _timePoint != null ? _start : null,
                  child: const Text('Continue'),
                )
              else ...[
                CapturePanel(controller: _controller, maxImages: 1),
                const SizedBox(height: 16),
                ListenableBuilder(
                  listenable: _controller,
                  builder: (context, _) => FilledButton.icon(
                    onPressed: _controller.passedItems.isNotEmpty && !_running ? _verify : null,
                    icon: const Icon(Icons.compare),
                    label: const Text('Run verification'),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
