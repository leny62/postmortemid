import 'package:flutter/material.dart';

import '../capture/capture_controller.dart';
import 'enrol_screen.dart';
import 'history_screen.dart';
import 'verify_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.services});

  final AppServices services;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    void open(Widget screen) =>
        Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));

    return Scaffold(
      appBar: AppBar(title: const Text('PostMortemID')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Muzzle verification research prototype', style: text.titleMedium),
          const SizedBox(height: 12),
          _StatusCard(services: services),
          const SizedBox(height: 24),
          _ActionTile(
            icon: Icons.add_a_photo_outlined,
            title: 'Enrol',
            subtitle: 'Register a study animal and create a muzzle template from live images',
            onTap: () => open(EnrolScreen(services: services)),
          ),
          _ActionTile(
            icon: Icons.fact_check_outlined,
            title: 'Verify',
            subtitle: 'Compare a new muzzle image with an enrolled animal',
            onTap: () => open(VerifyScreen(services: services)),
          ),
          _ActionTile(
            icon: Icons.history,
            title: 'History',
            subtitle: 'Past verification results stored on this phone',
            onTap: () => open(HistoryScreen(services: services)),
          ),
          _ActionTile(
            icon: Icons.file_download_outlined,
            title: 'Export data',
            subtitle: 'Save all study records as CSV files on this phone',
            onTap: () => _export(context),
          ),
          const SizedBox(height: 16),
          Text(
            'Works offline. Images and results are stored only on this phone.',
            style: text.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Future<void> _export(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final dir = await services.exportData();
      messenger.showSnackBar(SnackBar(content: Text('Exported to ${dir.path}')));
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('The export failed. Try again.')));
    }
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.services});

  final AppServices services;

  @override
  Widget build(BuildContext context) {
    final m = services.manifest;
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.science_outlined, color: scheme.onSecondaryContainer),
                const SizedBox(width: 8),
                Text('Prototype status', style: Theme.of(context).textTheme.titleSmall),
              ],
            ),
            const SizedBox(height: 8),
            Text(m.status),
            const SizedBox(height: 12),
            _InfoRow('Model', m.encoder.modelVersion),
            _InfoRow('Thresholds', m.thresholds.version),
            _InfoRow('App', services.appVersion),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 2),
    child: Row(
      children: [
        SizedBox(width: 96, child: Text(label, style: Theme.of(context).textTheme.labelMedium)),
        Expanded(
          child: Text(value, style: const TextStyle(fontFamily: 'monospace')),
        ),
      ],
    ),
  );
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card.outlined(
    margin: const EdgeInsets.only(bottom: 12),
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: Icon(icon, size: 32),
      title: Text(title, style: Theme.of(context).textTheme.titleMedium),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    ),
  );
}
