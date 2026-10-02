import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import 'biometric_encoder.dart';
import 'image_ops.dart';
import 'quality.dart';

class ImageAnalysis {
  const ImageAnalysis({required this.measures, required this.issues, this.embedding});

  final QualityMeasures measures;
  final List<QualityIssue> issues;

  /// Only computed when the image passes the quality check.
  final Float64List? embedding;

  bool get passed => issues.isEmpty;
}

RgbImage decodeRgb(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) throw const FormatException('unsupported image file');
  final upright = img.bakeOrientation(decoded).convert(numChannels: 3, format: img.Format.uint8);
  return RgbImage(upright.width, upright.height, upright.getBytes(order: img.ChannelOrder.rgb));
}

ImageAnalysis analyse(RgbImage image, QualityThresholds thresholds, BiometricEncoder encoder) {
  final measures = measureQuality(image.toGray());
  final issues = qualityIssues(measures, thresholds);
  return ImageAnalysis(
    measures: measures,
    issues: issues,
    embedding: issues.isEmpty ? encoder.encode(image) : null,
  );
}

/// Decoding a phone photo takes long enough to freeze the UI, so it runs in a background isolate.
Future<ImageAnalysis> analyseFile(
  String path,
  QualityThresholds thresholds,
  BiometricEncoder encoder,
) async {
  final bytes = await File(path).readAsBytes();
  return compute((Uint8List b) => analyse(decodeRgb(b), thresholds, encoder), bytes);
}
