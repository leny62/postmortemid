import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:postmortemid/biometrics/model_manifest.dart';

void main() {
  test('the bundled manifest loads and is labelled as a demonstration encoder', () {
    final json = jsonDecode(File(manifestAsset).readAsStringSync()) as Map<String, dynamic>;
    final m = ModelManifest.fromJson(json);
    expect(m.encoder.isResearchModel, isFalse);
    expect(m.encoder.modelVersion, isNotEmpty);
    expect(m.thresholds.tauFar01, greaterThanOrEqualTo(m.thresholds.tauFar1));
    expect(m.status, contains('not the research model'));
    expect(m.enrolmentImages, greaterThan(0));
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
