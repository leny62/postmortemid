import 'dart:io';
import 'dart:typed_data';

import 'package:postmortemid/biometrics/image_analysis.dart';
import 'package:postmortemid/biometrics/lbp_encoder.dart';
import 'package:postmortemid/biometrics/model_manifest.dart';
import 'package:postmortemid/biometrics/quality.dart';
import 'package:postmortemid/biometrics/verifier.dart';
import 'package:postmortemid/capture/capture_controller.dart';
import 'package:postmortemid/data/database.dart';
import 'package:postmortemid/data/local_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const testManifest = ModelManifest(
  encoder: LbpEncoder(modelVersion: 'test-encoder-v0'),
  thresholds: Thresholds(version: 'test-thresholds-v0', tauFar1: 0.80, tauFar01: 0.90),
  quality: QualityThresholds(minSide: 256, minBrightness: 40, maxBrightness: 220, minSharpness: 20),
  enrolmentImages: 3,
  status: 'Test build.',
  calibration: 'Test thresholds.',
);

Future<LocalRepository> fileRepository(Directory dir) async {
  sqfliteFfiInit();
  final db = await openStudyDatabase('${dir.path}/study.db', factory: databaseFactoryFfiNoIsolate);
  return LocalRepository(db);
}

/// Analyser that reads a fixed embedding from the file name instead of decoding pixels.
/// Files named `bad_*` fail the blur check.
ImageAnalysis fakeAnalysis(String path, Map<String, List<double>> embeddings) {
  // Stored files are named <timestamp>_<original name>.
  final original = path.split(Platform.pathSeparator).last.split('_').skip(1).join('_');
  final key = original.split('.').first.split('_').first;
  final measures = const QualityMeasures(width: 800, height: 600, brightness: 120, sharpness: 90);
  if (key == 'bad') {
    return ImageAnalysis(measures: measures, issues: const [QualityIssue.blurry]);
  }
  return ImageAnalysis(
    measures: measures,
    issues: const [],
    embedding: Float64List.fromList(embeddings[key]!),
  );
}

Future<AppServices> testServices(Directory dir, Map<String, List<double>> embeddings) async {
  return AppServices(
    repository: await fileRepository(dir),
    manifest: testManifest,
    imagesDir: dir,
    deviceModel: 'Test Phone',
    appVersion: '0.1.0+test',
    analyser: (path) async => fakeAnalysis(path, embeddings),
  );
}
