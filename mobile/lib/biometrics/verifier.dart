import 'dart:math' as math;
import 'dart:typed_data';

enum Decision {
  match('Match'),
  review('Review'),
  noMatch('No match');

  const Decision(this.label);
  final String label;

  static Decision fromName(String name) => values.byName(name);
}

/// Thresholds fixed on development animals. tauFar01 is the stricter one.
class Thresholds {
  const Thresholds({required this.version, required this.tauFar1, required this.tauFar01})
    : assert(tauFar01 >= tauFar1);

  final String version;
  final double tauFar1;
  final double tauFar01;
}

class Verifier {
  const Verifier(this.thresholds);

  final Thresholds thresholds;

  /// Mean of the normalised enrolment embeddings, normalised again.
  static Float64List buildTemplate(List<Float64List> embeddings) {
    if (embeddings.isEmpty) throw ArgumentError('at least one embedding is needed');
    final dim = embeddings.first.length;
    final out = Float64List(dim);
    for (final e in embeddings) {
      final unit = normalise(e);
      for (var i = 0; i < dim; i++) {
        out[i] += unit[i] / embeddings.length;
      }
    }
    return normalise(out);
  }

  static Float64List normalise(Float64List v) {
    var norm = 0.0;
    for (final x in v) {
      norm += x * x;
    }
    norm = math.sqrt(norm);
    return Float64List.fromList([for (final x in v) x / norm]);
  }

  static double cosine(Float64List a, Float64List b) {
    if (a.length != b.length) throw ArgumentError('embedding sizes differ');
    var dot = 0.0, na = 0.0, nb = 0.0;
    for (var i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      na += a[i] * a[i];
      nb += b[i] * b[i];
    }
    return dot / (math.sqrt(na) * math.sqrt(nb));
  }

  Decision decide(double score) {
    if (score >= thresholds.tauFar01) return Decision.match;
    if (score < thresholds.tauFar1) return Decision.noMatch;
    return Decision.review;
  }
}
