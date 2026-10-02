import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:postmortemid/biometrics/image_analysis.dart';
import 'package:postmortemid/biometrics/lbp_encoder.dart';
import 'package:postmortemid/biometrics/quality.dart';
import 'package:postmortemid/biometrics/verifier.dart';

// Expected values come from ml/scripts/export_parity_fixture.py.
void main() {
  final expected =
      jsonDecode(File('test/fixtures/parity.json').readAsStringSync()) as Map<String, dynamic>;
  final gray = decodeGray(File('test/fixtures/parity.png').readAsBytesSync());

  test('quality measures match the Python pipeline', () {
    final m = measureQuality(gray);
    expect(m.width, expected['width']);
    expect(m.height, expected['height']);
    expect(m.brightness, closeTo(expected['brightness'] as double, 1e-6));
    expect(m.sharpness, closeTo(expected['sharpness'] as double, 1e-6));
  });

  test('LBP descriptor matches the Python pipeline', () {
    final lbp = expected['lbp'] as Map<String, dynamic>;
    final encoder = LbpEncoder(
      modelVersion: 'test',
      size: lbp['size'] as int,
      grid: lbp['grid'] as int,
    );
    final python = (lbp['vector'] as List).cast<num>().map((v) => v.toDouble()).toList();
    final dart = encoder.encode(gray);
    expect(dart.length, python.length);
    for (var i = 0; i < dart.length; i++) {
      expect(dart[i], closeTo(python[i], 1e-9), reason: 'component $i');
    }
    expect(Verifier.cosine(dart, Verifier.normalise(dart)), closeTo(1, 1e-12));
  });
}
