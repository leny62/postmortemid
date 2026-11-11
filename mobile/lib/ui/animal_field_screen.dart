import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../capture/capture_controller.dart';
import '../capture/field_protocol.dart';
import '../data/models.dart';
import 'burst_camera_screen.dart';

/// One animal at the abattoir: the photo checklist and the log that replaces paper.
class AnimalFieldScreen extends StatefulWidget {
  const AnimalFieldScreen({super.key, required this.services, required this.animalId});

  final AppServices services;
  final int animalId;

  @override
  State<AnimalFieldScreen> createState() => _AnimalFieldScreenState();
}

class _AnimalFieldScreenState extends State<AnimalFieldScreen> {
  final _notes = TextEditingController();
  Animal? _animal;
  Map<(TimePoint, Modality), int> _counts = const {};

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _saveNotes();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final repo = widget.services.repository;
    final animal = await repo.animalById(widget.animalId);
    final counts = (await repo.collectedCounts())[widget.animalId] ?? const {};
    if (!mounted) return;
    if (_animal == null) _notes.text = animal.fieldLog.notes ?? '';
    setState(() {
      _animal = animal;
      _counts = counts;
    });
  }

  Future<void> _saveLog(FieldLog log) async {
    await widget.services.repository.updateFieldLog(widget.animalId, log);
    await _reload();
  }

  FieldLog _withLog({
    DateTime? slaughterTime,
    bool? headWashed,
    NoseCondition? nose,
    bool clearNose = false,
  }) {
    final log = _animal!.fieldLog;
    return FieldLog(
      slaughterTime: slaughterTime ?? log.slaughterTime,
      headWashed: headWashed ?? log.headWashed,
      noseCondition: clearNose ? null : nose ?? log.noseCondition,
      notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
    );
  }

  void _saveNotes() {
    final animal = _animal;
    if (animal == null || (animal.fieldLog.notes ?? '') == _notes.text.trim()) return;
    widget.services.repository.updateFieldLog(widget.animalId, _withLog());
  }

  Future<void> _pickSlaughterTime() async {
    final current = _animal!.fieldLog.slaughterTime ?? DateTime.now();
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
    );
    if (time == null) return;
    await _saveLog(
      _withLog(
        slaughterTime: DateTime(current.year, current.month, current.day, time.hour, time.minute),
      ),
    );
  }

  Future<void> _capture(ShotSet set) async {
    final controller = CaptureController(widget.services);
    await controller.startCollection(_animal!, set.timePoint, set.modality);
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BurstCameraScreen(
          controller: controller,
          shotSet: set,
          studyCode: _animal!.studyCode,
          alreadyKept: _counts[(set.timePoint, set.modality)] ?? 0,
        ),
      ),
    );
    // Photos still being checked finish in the background; wait so the counts are right.
    while (controller.busy) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    controller.dispose();
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final animal = _animal;
    if (animal == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final log = animal.fieldLog;
    final text = Theme.of(context).textTheme;
    final timeFormat = DateFormat('HH:mm');

    return Scaffold(
      appBar: AppBar(title: Text(animal.studyCode)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (animal.externalId != null)
            Text('Ear tag: ${animal.externalId} (stays on this phone)', style: text.bodyMedium),
          const SizedBox(height: 8),
          Text('Photos', style: text.titleMedium),
          const SizedBox(height: 4),
          Text(
            'After slaughter: at head inspection, before the head is skinned or the nose is cut.',
            style: text.bodySmall,
          ),
          const SizedBox(height: 8),
          for (final set in fieldProtocol)
            _ShotTile(
              set: set,
              count: _counts[(set.timePoint, set.modality)] ?? 0,
              onTap: () => _capture(set),
            ),
          const SizedBox(height: 16),
          Text('Log', style: text.titleMedium),
          const SizedBox(height: 8),
          Card.outlined(
            child: ListTile(
              title: const Text('Slaughter time'),
              subtitle: Text(
                log.slaughterTime == null ? 'Not set' : timeFormat.format(log.slaughterTime!),
              ),
              trailing: Wrap(
                spacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: () => _saveLog(_withLog(slaughterTime: DateTime.now())),
                    style: OutlinedButton.styleFrom(minimumSize: const Size(64, 44)),
                    child: const Text('Now'),
                  ),
                  IconButton(
                    tooltip: 'Set time',
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: _pickSlaughterTime,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Text('Head washed before the after-slaughter photos?'),
          const SizedBox(height: 4),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: true, label: Text('Yes')),
              ButtonSegment(value: false, label: Text('No')),
            ],
            selected: {?log.headWashed},
            emptySelectionAllowed: true,
            onSelectionChanged: (v) => v.isEmpty ? null : _saveLog(_withLog(headWashed: v.single)),
          ),
          const SizedBox(height: 12),
          const Text('Nose condition after slaughter'),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            children: [
              for (final n in NoseCondition.values)
                ChoiceChip(
                  label: Text(n.label),
                  selected: log.noseCondition == n,
                  onSelected: (on) => _saveLog(on ? _withLog(nose: n) : _withLog(clearNose: true)),
                ),
            ],
          ),
          const SizedBox(height: 12),
          const Text('Is the head surely from this animal?'),
          const SizedBox(height: 4),
          SegmentedButton<LinkageStatus>(
            segments: const [
              ButtonSegment(value: LinkageStatus.confirmed, label: Text('Sure')),
              ButtonSegment(value: LinkageStatus.pending, label: Text('Unsure')),
              ButtonSegment(value: LinkageStatus.excluded, label: Text('Exclude')),
            ],
            selected: {animal.linkageStatus},
            onSelectionChanged: (v) async {
              await widget.services.repository.updateLinkage(widget.animalId, v.single);
              await _reload();
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _notes,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Notes',
              hintText: 'Blood or dirt on the nose, damage, poor light...',
            ),
            onEditingComplete: _saveNotes,
            onTapOutside: (_) => _saveNotes(),
          ),
        ],
      ),
    );
  }
}

class _ShotTile extends StatelessWidget {
  const _ShotTile({required this.set, required this.count, required this.onTap});

  final ShotSet set;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final done = count >= set.target;
    return Card.outlined(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Icon(
          done ? Icons.check_circle : Icons.photo_camera_outlined,
          color: done ? const Color(0xFF1B7F3B) : null,
          size: 32,
        ),
        title: Text(set.label),
        subtitle: LinearProgressIndicator(value: (count / set.target).clamp(0, 1)),
        trailing: Text('$count / ${set.target}', style: Theme.of(context).textTheme.titleMedium),
        onTap: onTap,
      ),
    );
  }
}
