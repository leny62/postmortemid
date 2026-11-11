import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../capture/capture_controller.dart';
import '../capture/field_protocol.dart';
import '../data/field_export.dart';
import '../data/models.dart';
import 'animal_field_screen.dart';

/// Abattoir data collection: every study animal with its photo progress.
class FieldStudyScreen extends StatefulWidget {
  const FieldStudyScreen({super.key, required this.services});

  final AppServices services;

  @override
  State<FieldStudyScreen> createState() => _FieldStudyScreenState();
}

class _FieldStudyScreenState extends State<FieldStudyScreen> {
  List<Animal>? _animals;
  Map<int, Map<(TimePoint, Modality), int>> _counts = const {};
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final repo = widget.services.repository;
    final animals = await repo.allAnimals();
    final counts = await repo.collectedCounts();
    if (mounted) {
      setState(() {
        _animals = animals;
        _counts = counts;
      });
    }
  }

  Future<void> _open(int animalId) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AnimalFieldScreen(services: widget.services, animalId: animalId),
      ),
    );
    await _reload();
  }

  Future<void> _add() async {
    final codes = _animals!.map((a) => a.studyCode).toList();
    final lastSite = codes.reversed
        .map((c) => fieldCodePattern.firstMatch(c)?.group(1))
        .firstWhere((s) => s != null, orElse: () => 'A');
    final result = await showDialog<(String, String?)>(
      context: context,
      builder: (_) => _AddAnimalDialog(site: lastSite!, existing: codes),
    );
    if (result == null) return;
    final (code, earTag) = result;
    final animal = await widget.services.repository.addAnimal(
      Animal(
        studyCode: code,
        externalId: earTag,
        linkageStatus: LinkageStatus.pending,
        createdAt: DateTime.now(),
      ),
    );
    await _reload();
    await _open(animal.id!);
  }

  Future<void> _export() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _exporting = true);
    try {
      final s = widget.services;
      final zip = await exportFieldZip(s.repository, s.exportsDir, s.deviceModel);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(zip.path, mimeType: 'application/zip')],
          text: 'PostMortemID field photos from ${s.deviceModel}',
        ),
      );
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('The export failed. Try again.')));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  String _summary(Animal a) {
    final counts = _counts[a.id] ?? const {};
    String part(TimePoint t) {
      final sets = fieldProtocol.where((s) => s.timePoint == t);
      final have = sets.fold(0, (n, s) => n + ((counts[(t, s.modality)] ?? 0).clamp(0, s.target)));
      final need = sets.fold(0, (n, s) => n + s.target);
      return '$have/$need';
    }

    return 'Alive ${part(TimePoint.t0)}  ·  After slaughter ${part(TimePoint.p0)}';
  }

  @override
  Widget build(BuildContext context) {
    final animals = _animals;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Field collection'),
        actions: [
          IconButton(
            tooltip: 'Export and share',
            onPressed: _exporting || (animals?.isEmpty ?? true) ? null : _export,
            icon: _exporting
                ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator())
                : const Icon(Icons.ios_share),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: animals == null ? null : _add,
        icon: const Icon(Icons.add),
        label: const Text('Add animal'),
      ),
      body: animals == null
          ? const Center(child: CircularProgressIndicator())
          : animals.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Add an animal before photographing it alive. Photos and notes stay '
                  'on this phone until you export and share them.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              children: [
                for (final a in animals)
                  Card.outlined(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      title: Text(a.studyCode),
                      subtitle: Text(_summary(a)),
                      trailing: switch (a.linkageStatus) {
                        LinkageStatus.confirmed => null,
                        LinkageStatus.pending => const Chip(label: Text('Unsure')),
                        LinkageStatus.excluded => const Chip(label: Text('Excluded')),
                      },
                      onTap: () => _open(a.id!),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _AddAnimalDialog extends StatefulWidget {
  const _AddAnimalDialog({required this.site, required this.existing});

  final String site;
  final List<String> existing;

  @override
  State<_AddAnimalDialog> createState() => _AddAnimalDialogState();
}

class _AddAnimalDialogState extends State<_AddAnimalDialog> {
  late final _site = TextEditingController(text: widget.site);
  final _earTag = TextEditingController();

  String get _code => nextFieldCode(_site.text.toUpperCase(), widget.existing);
  bool get _validSite => RegExp(r'^[A-Za-z]$').hasMatch(_site.text);

  @override
  void dispose() {
    _site.dispose();
    _earTag.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(_validSite ? 'Add $_code' : 'Add animal'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _site,
          maxLength: 1,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(
            labelText: 'Abattoir letter',
            helperText: 'One letter per abattoir',
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _earTag,
          decoration: const InputDecoration(
            labelText: 'Ear tag number',
            helperText: 'Stays on this phone only',
          ),
        ),
      ],
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(
        onPressed: _validSite
            ? () => Navigator.pop(context, (
                _code,
                _earTag.text.trim().isEmpty ? null : _earTag.text.trim(),
              ))
            : null,
        child: const Text('Add'),
      ),
    ],
  );
}
