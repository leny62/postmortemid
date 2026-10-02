import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:postmortemid/biometrics/image_analysis.dart';
import 'package:postmortemid/biometrics/quality.dart';
import 'package:postmortemid/biometrics/verifier.dart';
import 'package:postmortemid/capture/capture_controller.dart';
import 'package:postmortemid/data/database.dart';
import 'package:postmortemid/data/models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support.dart';

void main() {
  late Directory tmp;
  late Directory source;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('pmid_store');
    source = await Directory.systemTemp.createTemp('pmid_src');
  });

  tearDown(() async {
    await tmp.delete(recursive: true);
    await source.delete(recursive: true);
  });

  Future<String> file(String name) async {
    final f = File('${source.path}/$name');
    await f.writeAsBytes([0]);
    return f.path;
  }

  // The fake analyser picks an embedding by the first part of the original file name.
  final embeddings = {
    'cowA': [1.0, 0.0, 0.0],
    'cowAq': [0.95, 0.31, 0.0],
    'cowAr': [0.85, 0.53, 0.0],
    'cowB': [0.0, 1.0, 0.0],
  };

  test('enrol, verify and read back the result from history', () async {
    final named = await testServices(tmp, embeddings);

    final enrol = CaptureController(named);
    await enrol.startEnrolment(studyCode: 'PM-0001', linkage: LinkageStatus.confirmed);
    for (final name in ['bad_1.jpg', 'cowA_1.jpg', 'cowA_2.jpg', 'cowA_3.jpg']) {
      await enrol.addImage(await file(name));
    }
    expect(enrol.items.length, 4);
    expect(enrol.passedItems.length, 3);
    expect(enrol.items.first.issues, [QualityIssue.blurry]);
    final template = await enrol.createTemplate();
    expect(template.imageCount, 3);
    expect(File(enrol.items.first.path).parent.path, tmp.path);

    final animals = await named.repository.enrolledAnimals('test-encoder-v0');
    expect(animals.map((a) => a.studyCode), ['PM-0001']);

    Future<VerificationOutcome> verifyWith(String name) async {
      final c = CaptureController(named);
      await c.startVerification(animals.single, TimePoint.p0);
      final item = await c.addImage(await file(name));
      return c.verify(item);
    }

    final match = await verifyWith('cowAq.jpg');
    final review = await verifyWith('cowAr.jpg');
    final noMatch = await verifyWith('cowB.jpg');
    expect(match.record.decision, Decision.match);
    expect(review.record.decision, Decision.review);
    expect(noMatch.record.decision, Decision.noMatch);

    final history = await named.repository.history();
    expect(history.length, 3);
    expect(history.first.record.decision, Decision.noMatch);
    expect(history.every((h) => h.timePoint == TimePoint.p0), isTrue);
    expect(history.every((h) => h.record.modelVersion == 'test-encoder-v0'), isTrue);
    expect(history.every((h) => h.record.thresholdVersion == 'test-thresholds-v0'), isTrue);
    expect(history.first.record.appVersion, '0.1.0+test');
  });

  test('a template cannot be created without enough accepted images', () async {
    final services = await testServices(tmp, embeddings);
    final c = CaptureController(services);
    await c.startEnrolment(studyCode: 'PM-0002', linkage: LinkageStatus.pending);
    expect(c.createTemplate, throwsStateError);
  });

  test('templates from another model version are not used', () async {
    final services = await testServices(tmp, embeddings);
    final repo = services.repository;
    final animal = await repo.addAnimal(
      Animal(studyCode: 'PM-0003', linkageStatus: LinkageStatus.pending, createdAt: DateTime(2026)),
    );
    expect(await repo.latestTemplate(animal.id!, 'test-encoder-v0'), isNull);
    expect(await repo.enrolledAnimals('test-encoder-v0'), isEmpty);
  });

  test('excluded animals are not offered for verification', () async {
    final services = await testServices(tmp, embeddings);
    final repo = services.repository;
    final animal = await repo.addAnimal(
      Animal(
        studyCode: 'PM-0004',
        linkageStatus: LinkageStatus.excluded,
        createdAt: DateTime(2026),
      ),
    );
    await repo.addTemplate(
      BiometricTemplate(
        animalId: animal.id!,
        embedding: Float64List.fromList([1, 0, 0]),
        modelVersion: 'test-encoder-v0',
        imageCount: 3,
        createdAt: DateTime(2026),
      ),
    );
    expect(await repo.enrolledAnimals('test-encoder-v0'), isEmpty);
  });

  Future<AppServices> servicesWith(Analyser analyser) async => AppServices(
    repository: await fileRepository(tmp),
    manifest: testManifest,
    imagesDir: tmp,
    exportsDir: Directory('${tmp.path}/exports'),
    deviceModel: 'Test Phone',
    appVersion: '0.1.0+test',
    analyser: analyser,
  );

  List<String> imageRows(Directory export) =>
      File('${export.path}/images.csv').readAsLinesSync().skip(1).toList();

  test('the image is on record before its analysis finishes (NFR5)', () async {
    final pending = Completer<ImageAnalysis>();
    final services = await servicesWith((_) => pending.future);
    final c = CaptureController(services);
    await c.startEnrolment(studyCode: 'PM-0005', linkage: LinkageStatus.pending);
    final adding = c.addImage(await file('cowA_1.jpg'));
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final before = imageRows(await services.exportData());
    expect(before, hasLength(1));
    expect(before.single.split(',')[3], '0', reason: 'analysed flag');

    pending.complete(fakeAnalysis('x_cowA_1.jpg', embeddings));
    await adding;
    final after = imageRows(await services.exportData());
    expect(after.single.split(',')[3], '1');
  });

  test('an unexpected analysis error fails the image instead of leaving it checking', () async {
    final services = await servicesWith((_) async => throw StateError('interpreter failed'));
    final c = CaptureController(services);
    await c.startEnrolment(studyCode: 'PM-0006', linkage: LinkageStatus.pending);
    final item = await c.addImage(await file('cowA_1.jpg'));
    expect(item.state, ItemState.failed);
    expect(item.message, contains('could not be analysed'));
    expect(c.busy, isFalse);
  });

  test('export writes every table as CSV and leaves ear tags out', () async {
    final services = await testServices(tmp, embeddings);
    final c = CaptureController(services);
    await c.startEnrolment(
      studyCode: 'PM-0007',
      externalId: 'RW-TAG-123',
      linkage: LinkageStatus.confirmed,
    );
    for (final name in ['cowA_1.jpg', 'cowA_2.jpg', 'cowA_3.jpg']) {
      await c.addImage(await file(name));
    }
    await c.createTemplate();

    final dir = await services.exportData();
    final names = dir.listSync().map((f) => f.uri.pathSegments.last).toSet();
    expect(names, {
      'animals.csv',
      'capture_sessions.csv',
      'images.csv',
      'templates.csv',
      'verifications.csv',
    });
    final animals = File('${dir.path}/animals.csv').readAsStringSync();
    expect(animals, startsWith('id,study_code,linkage_status,created_at\n'));
    expect(animals, contains('PM-0007'));
    expect(animals, isNot(contains('RW-TAG-123')));
    expect(imageRows(dir), hasLength(3));
  });

  test('a version 1 database is upgraded without losing images', () async {
    sqfliteFfiInit();
    final path = '${tmp.path}/old.db';
    final v1 = await databaseFactoryFfiNoIsolate.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) => db.execute(
          'CREATE TABLE images (id INTEGER PRIMARY KEY, session_id INTEGER NOT NULL, '
          'path TEXT NOT NULL, quality_passed INTEGER NOT NULL, quality_issues TEXT NOT NULL, '
          'width INTEGER NOT NULL, height INTEGER NOT NULL, brightness REAL NOT NULL, '
          'sharpness REAL NOT NULL, captured_at TEXT NOT NULL)',
        ),
      ),
    );
    await v1.insert('images', {
      'session_id': 1,
      'path': 'a.jpg',
      'quality_passed': 1,
      'quality_issues': '',
      'width': 300,
      'height': 300,
      'brightness': 120,
      'sharpness': 40,
      'captured_at': '2026-10-01T10:00:00',
    });
    await v1.close();

    final db = await openStudyDatabase(path, factory: databaseFactoryFfiNoIsolate);
    final rows = await db.query('images');
    expect(rows.single['analysed'], 1);
    await db.close();
  });
}
