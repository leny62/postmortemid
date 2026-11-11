import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:postmortemid/biometrics/image_analysis.dart';
import 'package:postmortemid/biometrics/quality.dart';
import 'package:postmortemid/capture/capture_controller.dart';
import 'package:postmortemid/capture/field_protocol.dart';
import 'package:postmortemid/data/field_export.dart';
import 'package:postmortemid/data/models.dart';
import 'package:postmortemid/ui/animal_field_screen.dart';
import 'package:postmortemid/ui/field_study_screen.dart';
import 'package:postmortemid/ui/theme.dart';

import 'support.dart';

void main() {
  late Directory tmp;
  late Directory source;
  late AppServices services;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('pmid_field');
    source = await Directory.systemTemp.createTemp('pmid_field_src');
    services = await testServices(tmp, {
      'cow': [1.0, 0.0],
    });
  });

  tearDown(() async {
    await tmp.delete(recursive: true);
    await source.delete(recursive: true);
  });

  Future<String> photo(String name) async {
    final f = File('${source.path}/$name');
    await f.writeAsBytes([0]);
    return f.path;
  }

  Future<Animal> animal(String code, {String? earTag}) => services.repository.addAnimal(
    Animal(
      studyCode: code,
      externalId: earTag,
      linkageStatus: LinkageStatus.confirmed,
      createdAt: DateTime(2026, 11, 13, 8),
    ),
  );

  /// Takes one burst; names starting with `bad` fail the quality check.
  Future<CaptureController> burst(Animal a, TimePoint t, Modality m, List<String> names) async {
    final c = CaptureController(services);
    await c.startCollection(a, t, m);
    for (final n in names) {
      await c.addImage(await photo(n), move: true);
    }
    return c;
  }

  test('next field code continues the site sequence', () {
    expect(nextFieldCode('A', []), 'PM-A01');
    expect(nextFieldCode('A', ['PM-A01', 'PM-A09', 'PM-B03', 'PM-0001']), 'PM-A10');
    expect(nextFieldCode('B', ['PM-A01', 'PM-B03']), 'PM-B04');
  });

  test('failed photos are discarded unless kept, and counts add up across bursts', () async {
    final a = await animal('PM-A01');
    final first = await burst(a, TimePoint.t0, Modality.muzzle, ['cow_1.jpg', 'bad_2.jpg']);
    expect(first.keptCount, 1);
    expect(File('${source.path}/cow_1.jpg').existsSync(), isFalse, reason: 'moved, not copied');

    await first.setKept(first.items.last, true);
    expect(first.keptCount, 2);
    await burst(a, TimePoint.t0, Modality.muzzle, ['cow_3.jpg']);
    await burst(a, TimePoint.p0, Modality.face, ['cow_4.jpg', 'bad_5.jpg']);

    final counts = (await services.repository.collectedCounts())[a.id]!;
    expect(counts[(TimePoint.t0, Modality.muzzle)], 3);
    expect(counts[(TimePoint.p0, Modality.face)], 1);
    expect(counts[(TimePoint.p0, Modality.muzzle)], isNull);
  });

  test('the field log and identity link are saved with the animal', () async {
    final a = await animal('PM-A02');
    final slaughter = DateTime(2026, 11, 13, 9, 40);
    await services.repository.updateFieldLog(
      a.id!,
      FieldLog(
        slaughterTime: slaughter,
        headWashed: false,
        noseCondition: NoseCondition.dirty,
        notes: 'blood on the left nostril',
      ),
    );
    await services.repository.updateLinkage(a.id!, LinkageStatus.pending);

    final back = await services.repository.animalById(a.id!);
    expect(back.fieldLog.slaughterTime, slaughter);
    expect(back.fieldLog.headWashed, isFalse);
    expect(back.fieldLog.noseCondition, NoseCondition.dirty);
    expect(back.fieldLog.notes, 'blood on the left nostril');
    expect(back.linkageStatus, LinkageStatus.pending);
  });

  test('export zip uses the pilot layout and leaves out ear tags and excluded animals', () async {
    final a = await animal('PM-A01', earTag: 'RW-TAG-777');
    final b = await animal('PM-A02');
    await animal('PM-A03');
    await burst(a, TimePoint.t0, Modality.muzzle, ['cow_1.jpg', 'cow_2.jpg', 'bad_3.jpg']);
    await burst(a, TimePoint.p0, Modality.face, ['cow_4.jpg']);
    await burst(b, TimePoint.t0, Modality.muzzle, ['cow_5.jpg']);
    await services.repository.updateFieldLog(
      a.id!,
      FieldLog(slaughterTime: DateTime(2026, 11, 13, 9, 40), headWashed: true),
    );
    await services.repository.updateLinkage(b.id!, LinkageStatus.excluded);

    final zip = await exportFieldZip(services.repository, services.exportsDir, 'Test Phone');
    final archive = ZipDecoder().decodeBytes(zip.readAsBytesSync());
    final names = archive.files.map((f) => f.name).toList();
    final photos = names.where((n) => n.endsWith('.jpg')).toList();

    expect(photos, hasLength(3));
    expect(photos.where((n) => n.startsWith('PM-A01/L/muzzle/')), hasLength(2));
    expect(photos.where((n) => n.startsWith('PM-A01/P0/face/')), hasLength(1));
    expect(names.any((n) => n.startsWith('PM-A02/')), isFalse);
    expect(names, containsAll(['slaughter_times.csv', 'field_animals.csv', 'field_images.csv']));

    String text(String name) =>
        String.fromCharCodes(archive.files.firstWhere((f) => f.name == name).content);
    expect(
      text('slaughter_times.csv'),
      'identity,slaughter_time\nPM-A01,2026-11-13T09:40:00.000\n',
    );
    expect(text('field_animals.csv'), contains('PM-A01,confirmed,2026-11-13T09:40:00.000,yes'));
    expect(
      text('field_animals.csv').trim().split('\n'),
      hasLength(2),
      reason: 'unphotographed left out',
    );
    expect(text('field_images.csv').trim().split('\n'), hasLength(4));
    for (final f in archive.files.where((f) => f.name.endsWith('.csv'))) {
      expect(String.fromCharCodes(f.content), isNot(contains('RW-TAG-777')));
    }
  });

  testWidgets('photo check judges size on the original and finds dark, flat photos', (
    tester,
  ) async {
    final textured = img.Image(width: 2400, height: 1800);
    for (final px in textured) {
      final v = (px.x ~/ 3 + px.y ~/ 3).isEven ? 40 : 200;
      px.setRgb(v, v, v);
    }
    final dark = img.Image(width: 2400, height: 1800)..clear(img.ColorRgb8(10, 10, 10));
    final (sharp, flat) = (await tester.runAsync(() async {
      final paths = <String>[];
      for (final (name, image) in [('textured.jpg', textured), ('dark.jpg', dark)]) {
        final f = File('${source.path}/$name')..writeAsBytesSync(img.encodeJpg(image));
        paths.add(f.path);
      }
      return (
        await checkPhotoQuality(paths[0], testManifest.quality),
        await checkPhotoQuality(paths[1], testManifest.quality),
      );
    }))!;
    expect((sharp.measures.width, sharp.measures.height), (2400, 1800));
    expect(sharp.issues, isEmpty);
    expect(sharp.embedding, isNull);
    expect(flat.issues, containsAll([QualityIssue.tooDark, QualityIssue.blurry]));
  });

  Widget wrap(Widget child) => MaterialApp(theme: buildTheme(), home: child);

  testWidgets('field list shows each animal with its photo progress', (tester) async {
    await tester.runAsync(() async {
      final a = await animal('PM-A01');
      await burst(a, TimePoint.t0, Modality.muzzle, ['cow_1.jpg', 'cow_2.jpg']);
      await animal('PM-A02');
    });
    await tester.pumpWidget(wrap(FieldStudyScreen(services: services)));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pump();

    expect(find.text('PM-A01'), findsOneWidget);
    expect(find.text('Alive 2/10  ·  After slaughter 0/8'), findsOneWidget);
    expect(find.text('PM-A02'), findsOneWidget);
    expect(find.text('Add animal'), findsOneWidget);
  });

  testWidgets('animal screen lists the four photo sets and the log', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    late Animal a;
    await tester.runAsync(() async {
      a = await animal('PM-A03', earTag: 'RW-TAG-1');
      await burst(a, TimePoint.p0, Modality.muzzle, ['cow_1.jpg']);
    });
    await tester.pumpWidget(wrap(AnimalFieldScreen(services: services, animalId: a.id!)));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pump();

    for (final set in fieldProtocol) {
      expect(find.text(set.label), findsOneWidget);
    }
    expect(find.text('1 / 5'), findsOneWidget);
    expect(find.text('Slaughter time'), findsOneWidget);
    expect(find.text('Not set'), findsOneWidget);
    expect(find.textContaining('RW-TAG-1'), findsOneWidget);
  });
}
