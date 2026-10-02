import 'package:flutter/material.dart';

import '../capture/capture_controller.dart';
import '../data/models.dart';
import 'capture_panel.dart';

final studyCodePattern = RegExp(r'^PM-\d{4}$');

class EnrolScreen extends StatefulWidget {
  const EnrolScreen({super.key, required this.services});

  final AppServices services;

  @override
  State<EnrolScreen> createState() => _EnrolScreenState();
}

class _EnrolScreenState extends State<EnrolScreen> {
  final _form = GlobalKey<FormState>();
  final _studyCode = TextEditingController();
  final _externalId = TextEditingController();
  late final CaptureController _controller = CaptureController(widget.services);
  LinkageStatus _linkage = LinkageStatus.pending;
  bool _started = false;
  bool _saving = false;

  @override
  void dispose() {
    _studyCode.dispose();
    _externalId.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    if (!_form.currentState!.validate()) return;
    final code = _studyCode.text.trim().toUpperCase();
    final existing = await widget.services.repository.findAnimal(code);
    if (existing != null && mounted) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('$code is already registered'),
          content: const Text('A new template will be created for this animal.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Continue'),
            ),
          ],
        ),
      );
      if (proceed != true) return;
    }
    await _controller.startEnrolment(
      studyCode: code,
      externalId: _externalId.text.trim().isEmpty ? null : _externalId.text.trim(),
      linkage: _linkage,
    );
    setState(() => _started = true);
  }

  Future<void> _createTemplate() async {
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _controller.createTemplate();
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('The template could not be saved. Try again.')),
      );
      if (mounted) setState(() => _saving = false);
      return;
    }
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(content: Text('Template saved for ${_controller.animal!.studyCode}')),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Enrol animal')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Form(
            key: _form,
            child: Column(
              children: [
                TextFormField(
                  controller: _studyCode,
                  enabled: !_started,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'Study animal ID',
                    hintText: 'PM-0001',
                  ),
                  validator: (v) => studyCodePattern.hasMatch((v ?? '').trim().toUpperCase())
                      ? null
                      : 'Use the format PM-0000',
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _externalId,
                  enabled: !_started,
                  decoration: const InputDecoration(
                    labelText: 'Ear tag or facility record (optional)',
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<LinkageStatus>(
                  initialValue: _linkage,
                  decoration: const InputDecoration(labelText: 'Identity link'),
                  items: [
                    for (final s in LinkageStatus.values)
                      DropdownMenuItem(value: s, child: Text(s.label)),
                  ],
                  onChanged: _started ? null : (v) => setState(() => _linkage = v!),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const Text('Time point: T0, ante-mortem (live). Modality: muzzle.'),
          const SizedBox(height: 16),
          if (!_started)
            FilledButton(onPressed: _start, child: const Text('Start enrolment'))
          else ...[
            ListenableBuilder(
              listenable: _controller,
              builder: (context, _) {
                final have = _controller.passedItems.length;
                final need = _controller.required;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '$have of $need accepted images',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    LinearProgressIndicator(value: (have / need).clamp(0, 1)),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: have >= need && !_saving && !_controller.busy
                          ? _createTemplate
                          : null,
                      child: const Text('Create template'),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            CapturePanel(controller: _controller, maxImages: _controller.required),
          ],
        ],
      ),
    );
  }
}
