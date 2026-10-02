import 'dart:typed_data';

import '../biometrics/verifier.dart';

enum LinkageStatus {
  pending('Pending'),
  confirmed('Confirmed'),
  excluded('Excluded');

  const LinkageStatus(this.label);
  final String label;
}

/// Capture time points from the study protocol.
enum TimePoint {
  t0('T0', 'Ante-mortem (live)'),
  p0('P0', 'Immediate post-mortem'),
  p1('P1', 'Later post-mortem');

  const TimePoint(this.code, this.label);
  final String code;
  final String label;

  static TimePoint fromCode(String code) => values.firstWhere((t) => t.code == code);
}

enum SessionPurpose { enrolment, verification }

class Animal {
  const Animal({
    this.id,
    required this.studyCode,
    this.externalId,
    required this.linkageStatus,
    required this.createdAt,
  });

  factory Animal.fromRow(Map<String, Object?> r) => Animal(
    id: r['id'] as int,
    studyCode: r['study_code'] as String,
    externalId: r['external_id'] as String?,
    linkageStatus: LinkageStatus.values.byName(r['linkage_status'] as String),
    createdAt: DateTime.parse(r['created_at'] as String),
  );

  final int? id;
  final String studyCode;

  /// Ear tag or facility record number. Optional, and never shown in exports.
  final String? externalId;
  final LinkageStatus linkageStatus;
  final DateTime createdAt;
}

class CaptureSession {
  const CaptureSession({
    this.id,
    required this.animalId,
    required this.timePoint,
    required this.modality,
    required this.purpose,
    required this.deviceModel,
    required this.startedAt,
  });

  final int? id;
  final int animalId;
  final TimePoint timePoint;
  final String modality;
  final SessionPurpose purpose;
  final String deviceModel;
  final DateTime startedAt;
}

class BiometricTemplate {
  const BiometricTemplate({
    this.id,
    required this.animalId,
    required this.embedding,
    required this.modelVersion,
    required this.imageCount,
    required this.createdAt,
  });

  factory BiometricTemplate.fromRow(Map<String, Object?> r) => BiometricTemplate(
    id: r['id'] as int,
    animalId: r['animal_id'] as int,
    embedding: Uint8List.fromList(r['embedding'] as List<int>).buffer.asFloat64List(),
    modelVersion: r['model_version'] as String,
    imageCount: r['image_count'] as int,
    createdAt: DateTime.parse(r['created_at'] as String),
  );

  final int? id;
  final int animalId;
  final Float64List embedding;
  final String modelVersion;
  final int imageCount;
  final DateTime createdAt;
}

class VerificationRecord {
  const VerificationRecord({
    this.id,
    required this.templateId,
    required this.queryImageId,
    required this.similarity,
    required this.tauFar1,
    required this.tauFar01,
    required this.decision,
    required this.modelVersion,
    required this.thresholdVersion,
    required this.appVersion,
    required this.createdAt,
  });

  final int? id;
  final int templateId;
  final int queryImageId;
  final double similarity;
  final double tauFar1;
  final double tauFar01;
  final Decision decision;
  final String modelVersion;
  final String thresholdVersion;
  final String appVersion;
  final DateTime createdAt;
}

/// A verification joined with the animal and query details, for the history screen.
class HistoryEntry {
  const HistoryEntry({
    required this.record,
    required this.studyCode,
    required this.timePoint,
    required this.queryPath,
  });

  final VerificationRecord record;
  final String studyCode;
  final TimePoint timePoint;
  final String queryPath;
}
