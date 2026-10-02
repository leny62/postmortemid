import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../capture/capture_controller.dart';
import '../data/models.dart';
import 'result_screen.dart';
import 'theme.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key, required this.services});

  final AppServices services;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  late final Future<List<HistoryEntry>> _entries = widget.services.repository.history();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('History')),
      body: FutureBuilder<List<HistoryEntry>>(
        future: _entries,
        builder: (context, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final entries = snap.data!;
          if (entries.isEmpty) {
            return const Center(child: Text('No verification results yet.'));
          }
          return ListView.separated(
            itemCount: entries.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) => HistoryTile(
              entry: entries[i],
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ResultScreen(
                    outcome: VerificationOutcome(
                      record: entries[i].record,
                      studyCode: entries[i].studyCode,
                      timePoint: entries[i].timePoint,
                    ),
                    isResearchModel: widget.services.manifest.encoder.isResearchModel,
                    calibration: widget.services.manifest.calibration,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class HistoryTile extends StatelessWidget {
  const HistoryTile({super.key, required this.entry, this.onTap});

  final HistoryEntry entry;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final r = entry.record;
    return ListTile(
      onTap: onTap,
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.file(
          File(entry.queryPath),
          width: 48,
          height: 48,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => const Icon(Icons.image_not_supported_outlined, size: 48),
        ),
      ),
      title: Text('${entry.studyCode}  ·  ${entry.timePoint.code}'),
      subtitle: Text(
        '${DateFormat('d MMM yyyy, HH:mm').format(r.createdAt)}\n'
        'Score ${r.similarity.toStringAsFixed(3)}  ·  ${r.modelVersion}',
      ),
      isThreeLine: true,
      trailing: Chip(
        avatar: Icon(r.decision.icon, color: r.decision.color, size: 18),
        label: Text(r.decision.label),
        side: BorderSide(color: r.decision.color),
      ),
    );
  }
}
