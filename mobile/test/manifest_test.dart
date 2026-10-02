import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:postmortemid/biometrics/model_manifest.dart';

void main() {
  test('the bundled manifest loads and states what has not been measured', () {
    final json = jsonDecode(File(manifestAsset).readAsStringSync()) as Map<String, dynamic>;
    final file = (json['encoder'] as Map<String, dynamic>)['model_file'] as String?;
    final bytes = file == null ? null : File('$modelAssetDir/$file').readAsBytesSync();
    final m = ModelManifest.fromJson(json, modelBytes: bytes);
    expect(m.encoder.modelVersion, isNotEmpty);
    expect(m.thresholds.tauFar01, greaterThanOrEqualTo(m.thresholds.tauFar1));
    expect(m.status, contains('Post-mortem performance has not been measured'));
    expect(m.enrolmentImages, greaterThan(0));
  });

  test('a tflite encoder without its model file is rejected', () {
    expect(
      () => ModelManifest.fromJson({
        'encoder': {'type': 'tflite', 'model_version': 'x', 'input_size': 224, 'embedding_dim': 8},
        'thresholds': {'version': 'v', 'tau_far1': 0.1, 'tau_far01': 0.2},
      }),
      throwsFormatException,
    );
  });

  test('an unknown encoder type is rejected', () {
    expect(
      () => ModelManifest.fromJson({
        'encoder': {'type': 'unknown', 'model_version': 'x'},
        'thresholds': {'version': 'v', 'tau_far1': 0.1, 'tau_far01': 0.2},
      }),
      throwsFormatException,
    );
  });
}
