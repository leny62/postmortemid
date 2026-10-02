import 'dart:math' as math;

import 'image_ops.dart';

const qualityAnalysisSize = 256;

enum QualityIssue {
  tooSmall('The image is too small. Move closer so the muzzle fills the frame.'),
  tooDark('The image is too dark. Move to better light and capture again.'),
  tooBright('The image is too bright. Avoid direct sunlight or flash glare and capture again.'),
  blurry('The image is too blurry. Hold the phone still and capture again.');

  const QualityIssue(this.message);
  final String message;
}

class QualityThresholds {
  const QualityThresholds({
    required this.minSide,
    required this.minBrightness,
    required this.maxBrightness,
    required this.minSharpness,
  });

  factory QualityThresholds.fromJson(Map<String, dynamic> json) => QualityThresholds(
    minSide: json['min_side'] as int,
    minBrightness: (json['min_brightness'] as num).toDouble(),
    maxBrightness: (json['max_brightness'] as num).toDouble(),
    minSharpness: (json['min_sharpness'] as num).toDouble(),
  );

  final int minSide;
  final double minBrightness;
  final double maxBrightness;
  final double minSharpness;
}

class QualityMeasures {
  const QualityMeasures({
    required this.width,
    required this.height,
    required this.brightness,
    required this.sharpness,
  });

  final int width;
  final int height;
  final double brightness;
  final double sharpness;
}

double laplacianVariance(GrayImage g) {
  final n = (g.width - 2) * (g.height - 2);
  var sum = 0.0, sumSq = 0.0;
  for (var y = 1; y < g.height - 1; y++) {
    for (var x = 1; x < g.width - 1; x++) {
      final v = g.at(x - 1, y) + g.at(x + 1, y) + g.at(x, y - 1) + g.at(x, y + 1) - 4 * g.at(x, y);
      sum += v;
      sumSq += v * v;
    }
  }
  final mean = sum / n;
  return math.max(0, sumSq / n - mean * mean);
}

QualityMeasures measureQuality(GrayImage full) {
  final g = graySquare(full, qualityAnalysisSize);
  var total = 0.0;
  for (final v in g.pixels) {
    total += v;
  }
  return QualityMeasures(
    width: full.width,
    height: full.height,
    brightness: total / g.pixels.length,
    sharpness: laplacianVariance(g),
  );
}

List<QualityIssue> qualityIssues(QualityMeasures m, QualityThresholds t) => [
  if (math.min(m.width, m.height) < t.minSide) QualityIssue.tooSmall,
  if (m.brightness < t.minBrightness) QualityIssue.tooDark,
  if (m.brightness > t.maxBrightness) QualityIssue.tooBright,
  if (m.sharpness < t.minSharpness) QualityIssue.blurry,
];
