import 'dart:io';
import 'dart:typed_data';

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

/// Quality result and, if the image passed, the encoder input.
class CheckedImage {
  const CheckedImage({required this.measures, required this.issues, this.input});

  final QualityMeasures measures;
  final List<QualityIssue> issues;
  final TypedData? input;
}

RgbImage decodeRgb(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) throw const FormatException('unsupported image file');
  final upright = img.bakeOrientation(decoded).convert(numChannels: 3, format: img.Format.uint8);
  return RgbImage(upright.width, upright.height, upright.getBytes(order: img.ChannelOrder.rgb));
}

CheckedImage checkImage(RgbImage image, QualityThresholds thresholds, Preprocessor prepare) {
  final measures = measureQuality(image.toGray());
  final issues = qualityIssues(measures, thresholds);
  return CheckedImage(
    measures: measures,
    issues: issues,
    input: issues.isEmpty ? prepare(image) : null,
  );
}

/// Decoding, the quality check and preprocessing take long enough to freeze
/// the UI, so they run in a background isolate. Only the small encoder input
/// comes back; the encoder then runs where its model lives.
Future<ImageAnalysis> analyseFile(
  String path,
  QualityThresholds thresholds,
  BiometricEncoder encoder,
) async {
  final bytes = await File(path).readAsBytes();
  final prepare = encoder.preprocessor;
  final checked = await compute(
    (Uint8List b) => checkImage(decodeRgb(b), thresholds, prepare),
    bytes,
  );
  final input = checked.input;
  return ImageAnalysis(
    measures: checked.measures,
    issues: checked.issues,
    embedding: input == null ? null : await encoder.embed(input),
  );
}
