import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:postmortemid/biometrics/image_ops.dart';
import 'package:postmortemid/biometrics/quality.dart';

void main() {
  const thresholds = QualityThresholds(
    minSide: 256,
    minBrightness: 40,
    maxBrightness: 220,
    minSharpness: 20,
  );

  GrayImage flat(int w, int h, double value) =>
      GrayImage(w, h, Float64List(w * h)..fillRange(0, w * h, value));

  GrayImage checker(int w, int h) => GrayImage(
    w,
    h,
    Float64List.fromList([
      for (var y = 0; y < h; y++)
        for (var x = 0; x < w; x++) ((x ~/ 2 + y ~/ 2).isEven ? 60.0 : 190.0),
    ]),
  );

  test('a sharp, well-exposed image passes', () {
    expect(qualityIssues(measureQuality(checker(512, 400)), thresholds), isEmpty);
  });

  test('a flat image is reported as blurry', () {
    expect(qualityIssues(measureQuality(flat(512, 512, 120)), thresholds), [QualityIssue.blurry]);
  });

  test('dark, bright and small images are reported', () {
    expect(
      qualityIssues(measureQuality(flat(512, 512, 10)), thresholds),
      containsAll([QualityIssue.tooDark]),
    );
    expect(
      qualityIssues(measureQuality(flat(512, 512, 250)), thresholds),
      containsAll([QualityIssue.tooBright]),
    );
    expect(
      qualityIssues(measureQuality(checker(200, 300)), thresholds),
      [QualityIssue.tooSmall],
    );
  });

  test('messages are plain language without numbers', () {
    for (final issue in QualityIssue.values) {
      expect(issue.message, isNot(matches(RegExp(r'\d'))));
      expect(issue.message, contains('.'));
    }
  });

  test('box resize averages blocks and repeats pixels when upsampling', () {
    final g = GrayImage(4, 4, Float64List.fromList(List.generate(16, (i) => i.toDouble())));
    final down = boxResize(g, 2);
    expect(down.pixels, [2.5, 4.5, 10.5, 12.5]);
    final up = boxResize(GrayImage(2, 2, Float64List.fromList([1, 2, 3, 4])), 4);
    expect(up.pixels.sublist(0, 4), [1, 1, 2, 2]);
  });
}
