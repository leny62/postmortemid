import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../capture/capture_controller.dart';
import '../capture/field_protocol.dart';
import '../data/field_export.dart';
import '../data/field_upload.dart';
import '../data/models.dart';
import '../data/upload_client.dart';
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
  int _notUploaded = 0;
  (int, int)? _uploading;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final repo = widget.services.repository;
    final animals = await repo.allAnimals();
    final counts = await repo.collectedCounts();
    final notUploaded = (await repo.fieldImages(notUploaded: true)).length;
    if (mounted) {
      setState(() {
        _animals = animals;
        _counts = counts;
        _notUploaded = notUploaded;
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

  Future<bool> _editServer() async {
    final repo = widget.services.repository;
    final url = await repo.setting(uploadUrlKey) ?? '';
    final token = await repo.setting(uploadTokenKey) ?? '';
    if (!mounted) return false;
    final saved = await showDialog<(String, String)>(
      context: context,
      builder: (_) => _ServerDialog(url: url, token: token),
    );
    if (saved == null) return false;
    await repo.saveSetting(uploadUrlKey, saved.$1);
    await repo.saveSetting(uploadTokenKey, saved.$2);
    return true;
  }

  Future<void> _upload() async {
    final s = widget.services;
    var url = await s.repository.setting(uploadUrlKey);
    var token = await s.repository.setting(uploadTokenKey);
    if (url == null || token == null) {
      if (!mounted || !await _editServer()) return;
      url = await s.repository.setting(uploadUrlKey);
      token = await s.repository.setting(uploadTokenKey);
    }
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _uploading = (0, _notUploaded));
    final client = UploadClient(url!, token!);
    try {
      final result = await uploadPending(
        s.repository,
        client,
        s.deviceModel,
        onProgress: (done, total) {
          if (mounted) setState(() => _uploading = (done, total));
        },
      );
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            result.error == null
                ? 'Uploaded ${result.uploaded} photos. Everything is on the server.'
                : '${result.error} ${result.remaining} photos are still waiting.',
          ),
        ),
      );
    } on UploadException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      client.close();
      if (mounted) setState(() => _uploading = null);
      await _reload();
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
          if (_uploading case (final done, final total))
            Center(child: Text('$done / $total'))
          else
            IconButton(
              tooltip: 'Upload to study server',
              onPressed: _notUploaded == 0 ? null : _upload,
              icon: Badge(
                isLabelVisible: _notUploaded > 0,
                label: Text('$_notUploaded'),
                child: const Icon(Icons.cloud_upload_outlined),
              ),
            ),
          PopupMenuButton<void>(
            itemBuilder: (_) => [
              PopupMenuItem(onTap: _editServer, child: const Text('Study server settings')),
            ],
          ),
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

class _ServerDialog extends StatefulWidget {
  const _ServerDialog({required this.url, required this.token});

  final String url;
  final String token;

  @override
  State<_ServerDialog> createState() => _ServerDialogState();
}

class _ServerDialogState extends State<_ServerDialog> {
  late final _url = TextEditingController(text: widget.url);
  late final _token = TextEditingController(text: widget.token);

  bool get _valid =>
      Uri.tryParse(_url.text.trim())?.isScheme('https') == true && _token.text.trim().isNotEmpty;

  @override
  void dispose() {
    _url.dispose();
    _token.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Study server'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _url,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            labelText: 'Server address',
            hintText: 'https://pmid.lenycodes.tech',
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _token,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Upload key',
            helperText: 'From the researcher',
          ),
          onChanged: (_) => setState(() {}),
        ),
      ],
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(
        onPressed: _valid
            ? () => Navigator.pop(context, (_url.text.trim(), _token.text.trim()))
            : null,
        child: const Text('Save'),
      ),
    ],
  );
}
