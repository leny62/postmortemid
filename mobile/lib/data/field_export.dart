import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;

import 'csv.dart';
import 'field_records.dart';
import 'local_repository.dart';

/// Writes the field photos as one zip in the folder layout the pilot analysis
/// reads (PM-A01/L/muzzle/...), with slaughter times and per-photo logs.
/// Ear tags stay on the phone. Only photographed, non-excluded animals are listed.
Future<File> exportFieldZip(LocalRepository repo, Directory exportsDir, String deviceModel) async {
  final photos = (await repo.fieldImages()).map(FieldPhoto.fromRow).toList();
  final photographed = {for (final ph in photos) ph.identity};
  final animals = [
    for (final a in await repo.allAnimals())
      if (photographed.contains(a.studyCode)) fieldAnimalLog(a, deviceModel),
  ];

  List<Object?> pick(Map<String, Object?> row, List<String> columns) => [
    for (final c in columns) row[c],
  ];
  final texts = {
    'slaughter_times.csv': csvTable(
      ['identity', 'slaughter_time'],
      [
        for (final a in animals)
          if (a['slaughter_time'] != null) pick(a, ['identity', 'slaughter_time']),
      ],
    ),
    'field_animals.csv': csvTable(fieldAnimalColumns, [
      for (final a in animals) pick(a, fieldAnimalColumns),
    ]),
    'field_images.csv': csvTable(fieldImageColumns, [
      for (final ph in photos) pick(ph.log, fieldImageColumns),
    ]),
  };
  final files = [for (final ph in photos) (ph.sourcePath, ph.file)];

  await exportsDir.create(recursive: true);
  final device = deviceModel.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-');
  final stamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
  final out = p.join(exportsDir.path, 'pmid_field_${device}_$stamp.zip');
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
