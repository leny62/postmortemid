import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;

import 'csv.dart';
import 'local_repository.dart';
import 'models.dart';

final _fileStamp = DateFormat('yyyyMMdd_HHmmss_SSS');

/// Stage folder names the pilot analysis reads: L for live, then P0 or P1.
String stageFolder(TimePoint t) => t == TimePoint.t0 ? 'L' : t.code;

/// Writes the field photos as one zip in the folder layout the pilot analysis
/// reads (PM-A01/L/muzzle/...), with slaughter times and per-photo logs.
/// Ear tags stay on the phone. Only photographed, non-excluded animals are listed.
Future<File> exportFieldZip(LocalRepository repo, Directory exportsDir, String deviceModel) async {
  final images = await repo.fieldImages();
  final photographed = {for (final r in images) r['study_code']};
  final animals = [
    for (final a in await repo.allAnimals())
      if (photographed.contains(a.studyCode)) a,
  ];

  final files = <(String, String)>[];
  final imageRows = <List<Object?>>[];
  for (final r in images) {
    final capturedAt = DateTime.parse(r['captured_at'] as String);
    final stage = stageFolder(TimePoint.fromCode(r['time_point'] as String));
    final name = p.posix.join(
      r['study_code'] as String,
      stage,
      r['modality'] as String,
      '${_fileStamp.format(capturedAt)}_${r['image_id']}.jpg',
    );
    files.add((r['path'] as String, name));
    imageRows.add([
      name,
      r['study_code'],
      stage,
      r['modality'],
      r['session_id'],
      r['captured_at'],
      r['quality_passed'],
      r['quality_issues'],
      r['width'],
      r['height'],
      r['brightness'],
      r['sharpness'],
      r['device_model'],
    ]);
  }

  final texts = {
    'slaughter_times.csv': csvTable(
      ['identity', 'slaughter_time'],
      [
        for (final a in animals)
          if (a.fieldLog.slaughterTime != null)
            [a.studyCode, a.fieldLog.slaughterTime!.toIso8601String()],
      ],
    ),
    'field_animals.csv': csvTable(
      [
        'identity',
        'linkage_status',
        'slaughter_time',
        'head_washed',
        'nose_condition',
        'notes',
        'device_model',
      ],
      [
        for (final a in animals)
          [
            a.studyCode,
            a.linkageStatus.name,
            a.fieldLog.slaughterTime?.toIso8601String(),
            switch (a.fieldLog.headWashed) {
              true => 'yes',
              false => 'no',
              null => '',
            },
            a.fieldLog.noseCondition?.name,
            a.fieldLog.notes,
            deviceModel,
          ],
      ],
    ),
    'field_images.csv': csvTable([
      'file',
      'identity',
      'stage',
      'modality',
      'burst',
      'captured_at',
      'quality_passed',
      'quality_issues',
      'width',
      'height',
      'brightness',
      'sharpness',
      'device_model',
    ], imageRows),
  };

  await exportsDir.create(recursive: true);
  final device = deviceModel.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-');
  final out = p.join(
    exportsDir.path,
    'pmid_field_${device}_${_fileStamp.format(DateTime.now())}.zip',
  );
  // Photos are already JPEG, so they are stored uncompressed; zipping in an
  // isolate keeps the UI responsive for exports of a few hundred megabytes.
  await Isolate.run(() => _writeZip(out, files, texts));
  return File(out);
}

void _writeZip(String out, List<(String, String)> files, Map<String, String> texts) {
  final zip = ZipFileEncoder()..create(out, level: ZipFileEncoder.store);
  for (final (source, name) in files) {
    zip.addFileSync(File(source), name, ZipFileEncoder.store);
  }
  for (final MapEntry(:key, :value) in texts.entries) {
    zip.addArchiveFile(ArchiveFile.string(key, value));
  }
  zip.closeSync();
}
