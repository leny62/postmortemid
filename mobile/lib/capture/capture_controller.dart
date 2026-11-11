import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../biometrics/image_analysis.dart';
import '../biometrics/model_manifest.dart';
import '../biometrics/quality.dart';
import '../biometrics/verifier.dart';
import '../data/local_repository.dart';
import '../data/models.dart';

typedef Analyser = Future<ImageAnalysis> Function(String path);

class AppServices {
  AppServices({
    required this.repository,
    required this.manifest,
    required this.imagesDir,
    required this.exportsDir,
    required this.deviceModel,
    required this.appVersion,
    Analyser? analyser,
    Analyser? photoCheck,
  }) : analyser = analyser ?? ((path) => analyseFile(path, manifest.quality, manifest.encoder)),
       photoCheck = photoCheck ?? ((path) => checkPhotoQuality(path, manifest.quality));

  final LocalRepository repository;
  final ModelManifest manifest;
  final Directory imagesDir;
  final Directory exportsDir;
  final String deviceModel;
  final String appVersion;
  final Analyser analyser;

  /// Quality check without encoding, for full-size field photos.
  final Analyser photoCheck;

  Verifier get verifier => Verifier(manifest.thresholds);
  String get modelVersion => manifest.encoder.modelVersion;

  /// Writes the study records as CSV into a new timestamped folder and returns it.
  Future<Directory> exportData() async {
    final stamp = DateTime.now().toIso8601String().replaceAll(RegExp(r'[:.]'), '-');
    final dir = Directory(p.join(exportsDir.path, 'export_$stamp'));
    await repository.exportCsv(dir);
    return dir;
  }
}

enum ItemState { analysing, passed, failed }

class CaptureItem {
  CaptureItem(this.path);

  final String path;
  ItemState state = ItemState.analysing;
  List<QualityIssue> issues = const [];

  /// Set when the image failed for a reason other than a quality issue.
  String? message;

  /// A field photo that failed the quality check but was kept on request.
  bool kept = false;
  ImageAnalysis? analysis;
  int? imageId;
}

class VerificationOutcome {
  const VerificationOutcome({
    required this.record,
    required this.studyCode,
    required this.timePoint,
  });

  final VerificationRecord record;
  final String studyCode;
  final TimePoint timePoint;
}

/// Runs one capture session: save, quality check, encode, then enrol or verify.
class CaptureController extends ChangeNotifier {
  CaptureController(this._services);

  final AppServices _services;
  final List<CaptureItem> items = [];
  Animal? animal;
  int? _sessionId;
  TimePoint? _timePoint;
  SessionPurpose? _purpose;

  List<CaptureItem> get passedItems => items.where((i) => i.state == ItemState.passed).toList();
  bool get busy => items.any((i) => i.state == ItemState.analysing);
  int get required => _services.manifest.enrolmentImages;

  Future<void> startEnrolment({
    required String studyCode,
    String? externalId,
    required LinkageStatus linkage,
  }) async {
    final repo = _services.repository;
    final existing = await repo.findAnimal(studyCode);
    animal =
        existing ??
        await repo.addAnimal(
          Animal(
            studyCode: studyCode,
            externalId: externalId,
            linkageStatus: linkage,
            createdAt: DateTime.now(),
          ),
        );
    await _startSession(TimePoint.t0, SessionPurpose.enrolment);
  }

  Future<void> startVerification(Animal claimed, TimePoint timePoint) async {
    animal = claimed;
    await _startSession(timePoint, SessionPurpose.verification);
  }

  /// One burst of field photos for the abattoir protocol. Photos are kept at
  /// full size and only quality-checked; failed ones are discarded unless kept.
  Future<void> startCollection(Animal subject, TimePoint timePoint, Modality modality) async {
    animal = subject;
    await _startSession(timePoint, SessionPurpose.collection, modality: modality);
  }

  Future<void> _startSession(
    TimePoint timePoint,
    SessionPurpose purpose, {
    Modality modality = Modality.muzzle,
  }) async {
    _timePoint = timePoint;
    _purpose = purpose;
    _sessionId = await _services.repository.addSession(
      CaptureSession(
        animalId: animal!.id!,
        timePoint: timePoint,
        modality: modality,
        purpose: purpose,
        deviceModel: _services.deviceModel,
        startedAt: DateTime.now(),
      ),
    );
    items.clear();
    notifyListeners();
  }

  /// Copies the image into app storage and records it before any processing,
  /// so a crash during analysis does not lose the capture (NFR5).
  /// With [move], a camera temp file is moved rather than copied, so full-size
  /// field photos are not stored twice.
  Future<CaptureItem> addImage(String sourcePath, {bool move = false}) async {
    final name = '${DateTime.now().microsecondsSinceEpoch}_${p.basename(sourcePath)}';
    final target = p.join(_services.imagesDir.path, name);
    final saved = move
        ? await _move(File(sourcePath), target)
        : await File(sourcePath).copy(target);
    final item = CaptureItem(saved.path);
    items.add(item);
    notifyListeners();

    final collecting = _purpose == SessionPurpose.collection;
    try {
      item.imageId = await _services.repository.addPendingImage(_sessionId!, saved.path);
      final analysis = await (collecting ? _services.photoCheck : _services.analyser)(saved.path);
      await _services.repository.completeImage(
        item.imageId!,
        qualityPassed: analysis.passed,
        qualityIssues: analysis.issues.map((i) => i.name).toList(),
        width: analysis.measures.width,
        height: analysis.measures.height,
        brightness: analysis.measures.brightness,
        sharpness: analysis.measures.sharpness,
      );
      item
        ..analysis = analysis
        ..issues = analysis.issues
        ..state = analysis.passed ? ItemState.passed : ItemState.failed;
      if (collecting && !analysis.passed) {
        await _services.repository.setDiscarded(item.imageId!, true);
      }
    } on FormatException {
      item
        ..state = ItemState.failed
        ..issues = const []
        ..message = 'This file could not be read as an image.';
    } catch (_) {
      // The file and its pending row stay on record for later inspection.
      item
        ..state = ItemState.failed
        ..issues = const []
        ..message = 'The image could not be analysed. Please try again.';
    }
    notifyListeners();
    return item;
  }

  static Future<File> _move(File source, String target) async {
    try {
      return await source.rename(target);
    } on FileSystemException {
      final copy = await source.copy(target);
      await source.delete();
      return copy;
    }
  }

  void removeItem(CaptureItem item) {
    items.remove(item);
    notifyListeners();
  }

  /// Counts a field photo that failed the quality check, or stops counting one.
  Future<void> setKept(CaptureItem item, bool keep) async {
    await _services.repository.setDiscarded(item.imageId!, !keep);
    item.kept = keep;
    notifyListeners();
  }

  /// Field photos from this burst that count towards the protocol.
  int get keptCount => items
      .where((i) => i.state == ItemState.passed || (i.state == ItemState.failed && i.kept))
      .length;

  Future<BiometricTemplate> createTemplate() async {
    final usable = passedItems.take(required).toList();
    if (usable.length < required) {
      throw StateError('$required images that pass the quality check are needed');
    }
    final template = BiometricTemplate(
      animalId: animal!.id!,
      embedding: Verifier.buildTemplate([for (final i in usable) i.analysis!.embedding!]),
      modelVersion: _services.modelVersion,
      imageCount: usable.length,
      createdAt: DateTime.now(),
    );
    final id = await _services.repository.addTemplate(template);
    return BiometricTemplate(
      id: id,
      animalId: template.animalId,
      embedding: template.embedding,
      modelVersion: template.modelVersion,
      imageCount: template.imageCount,
      createdAt: template.createdAt,
    );
  }

  Future<VerificationOutcome> verify(CaptureItem query) async {
    if (query.state != ItemState.passed) throw StateError('query image failed the quality check');
    final template = await _services.repository.latestTemplate(animal!.id!, _services.modelVersion);
    if (template == null) throw StateError('no template for ${animal!.studyCode}');

    final verifier = _services.verifier;
    final score = Verifier.cosine(template.embedding, query.analysis!.embedding!);
    final record = VerificationRecord(
      templateId: template.id!,
      queryImageId: query.imageId!,
      similarity: score,
      tauFar1: verifier.thresholds.tauFar1,
      tauFar01: verifier.thresholds.tauFar01,
      decision: verifier.decide(score),
      modelVersion: _services.modelVersion,
      thresholdVersion: verifier.thresholds.version,
      appVersion: _services.appVersion,
      createdAt: DateTime.now(),
    );
    // Saved before it is shown, as in the proposal's sequence diagram (Figure 9).
    await _services.repository.addVerification(record);
    return VerificationOutcome(
      record: record,
      studyCode: animal!.studyCode,
      timePoint: _timePoint!,
    );
  }
}
