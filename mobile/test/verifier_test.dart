import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:postmortemid/biometrics/verifier.dart';

void main() {
  const verifier = Verifier(Thresholds(version: 't', tauFar1: 0.80, tauFar01: 0.90));

  test('scores map to the three decision bands', () {
    expect(verifier.decide(0.95), Decision.match);
    expect(verifier.decide(0.90), Decision.match);
    expect(verifier.decide(0.85), Decision.review);
    expect(verifier.decide(0.80), Decision.review);
    expect(verifier.decide(0.79), Decision.noMatch);
  });

  test('template is the normalised mean of normalised embeddings', () {
    final t = Verifier.buildTemplate([
      Float64List.fromList([2, 0]),
      Float64List.fromList([0, 5]),
    ]);
    expect(t[0], closeTo(0.70710678, 1e-6));
    expect(t[1], closeTo(0.70710678, 1e-6));
  });

  test('cosine similarity ignores vector length', () {
    final a = Float64List.fromList([1, 2, 3]);
    final b = Float64List.fromList([2, 4, 6]);
    expect(Verifier.cosine(a, b), closeTo(1, 1e-12));
    expect(Verifier.cosine(a, Float64List.fromList([-1, -2, -3])), closeTo(-1, 1e-12));
  });

  test('embeddings of different sizes are rejected', () {
    expect(() => Verifier.cosine(Float64List(3), Float64List(4)), throwsArgumentError);
  });
}
