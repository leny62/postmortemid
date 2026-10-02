import 'dart:typed_data';

import 'package:sqflite/sqflite.dart';

import '../biometrics/verifier.dart';
import 'models.dart';

class LocalRepository {
  LocalRepository(this._db);

  final Database _db;

  Future<Animal> addAnimal(Animal animal) async {
    final id = await _db.insert('animals', {
      'study_code': animal.studyCode,
      'external_id': animal.externalId,
      'linkage_status': animal.linkageStatus.name,
      'created_at': animal.createdAt.toIso8601String(),
    });
    return Animal(
      id: id,
      studyCode: animal.studyCode,
      externalId: animal.externalId,
      linkageStatus: animal.linkageStatus,
      createdAt: animal.createdAt,
    );
  }

  Future<Animal?> findAnimal(String studyCode) async {
    final rows = await _db.query('animals', where: 'study_code = ?', whereArgs: [studyCode]);
    return rows.isEmpty ? null : Animal.fromRow(rows.first);
  }

  Future<int> addSession(CaptureSession s) => _db.insert('capture_sessions', {
    'animal_id': s.animalId,
    'time_point': s.timePoint.code,
    'modality': s.modality,
    'purpose': s.purpose.name,
    'device_model': s.deviceModel,
    'started_at': s.startedAt.toIso8601String(),
  });

  Future<int> addImage(CapturedImage i) => _db.insert('images', {
    'session_id': i.sessionId,
    'path': i.path,
    'quality_passed': i.qualityPassed ? 1 : 0,
    'quality_issues': i.qualityIssues.join(','),
    'width': i.width,
    'height': i.height,
    'brightness': i.brightness,
    'sharpness': i.sharpness,
    'captured_at': i.capturedAt.toIso8601String(),
  });

  Future<int> addTemplate(BiometricTemplate t) => _db.insert('templates', {
    'animal_id': t.animalId,
    'embedding': Uint8List.view(Float64List.fromList(t.embedding).buffer),
    'model_version': t.modelVersion,
    'image_count': t.imageCount,
    'created_at': t.createdAt.toIso8601String(),
  });

  /// Latest template for an animal made with this model. Templates from another
  /// model version live in a different embedding space and cannot be compared.
  Future<BiometricTemplate?> latestTemplate(int animalId, String modelVersion) async {
    final rows = await _db.query(
      'templates',
      where: 'animal_id = ? AND model_version = ?',
      whereArgs: [animalId, modelVersion],
      orderBy: 'id DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : BiometricTemplate.fromRow(rows.first);
  }

  Future<List<Animal>> enrolledAnimals(String modelVersion) async {
    final rows = await _db.rawQuery(
      '''
      SELECT DISTINCT a.* FROM animals a
      JOIN templates t ON t.animal_id = a.id
      WHERE t.model_version = ? AND a.linkage_status != ?
      ORDER BY a.study_code''',
      [modelVersion, LinkageStatus.excluded.name],
    );
    return rows.map(Animal.fromRow).toList();
  }

  Future<int> addVerification(VerificationRecord v) => _db.insert('verifications', {
    'template_id': v.templateId,
    'query_image_id': v.queryImageId,
    'similarity': v.similarity,
    'tau_far1': v.tauFar1,
    'tau_far01': v.tauFar01,
    'decision': v.decision.name,
    'model_version': v.modelVersion,
    'threshold_version': v.thresholdVersion,
    'app_version': v.appVersion,
    'created_at': v.createdAt.toIso8601String(),
  });

  Future<List<HistoryEntry>> history() async {
    final rows = await _db.rawQuery('''
      SELECT v.*, a.study_code, s.time_point, i.path AS query_path
      FROM verifications v
      JOIN templates t ON t.id = v.template_id
      JOIN animals a ON a.id = t.animal_id
      JOIN images i ON i.id = v.query_image_id
      JOIN capture_sessions s ON s.id = i.session_id
      ORDER BY v.created_at DESC, v.id DESC''');
    return [
      for (final r in rows)
        HistoryEntry(
          studyCode: r['study_code'] as String,
          timePoint: TimePoint.fromCode(r['time_point'] as String),
          queryPath: r['query_path'] as String,
          record: VerificationRecord(
            id: r['id'] as int,
            templateId: r['template_id'] as int,
            queryImageId: r['query_image_id'] as int,
            similarity: r['similarity'] as double,
            tauFar1: r['tau_far1'] as double,
            tauFar01: r['tau_far01'] as double,
            decision: Decision.fromName(r['decision'] as String),
            modelVersion: r['model_version'] as String,
            thresholdVersion: r['threshold_version'] as String,
            appVersion: r['app_version'] as String,
            createdAt: DateTime.parse(r['created_at'] as String),
          ),
        ),
    ];
  }
}
