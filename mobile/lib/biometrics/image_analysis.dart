import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

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

const _photoDecodeWidth = 1024;

/// Quality check for full-size field photos, without encoding. The platform
/// decoder shrinks the photo while decoding, which is much faster and lighter
/// than a full-size decode in Dart. Size is judged on the original photo.
Future<ImageAnalysis> checkPhotoQuality(String path, QualityThresholds thresholds) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(await File(path).readAsBytes());
  final ui.ImageDescriptor descriptor;
  try {
    descriptor = await ui.ImageDescriptor.encoded(buffer);
  } catch (_) {
    buffer.dispose();
    throw const FormatException('unsupported image file');
  }
  final (width, height) = (descriptor.width, descriptor.height);
  final codec = await descriptor.instantiateCodec(
    targetWidth: width > _photoDecodeWidth ? _photoDecodeWidth : null,
  );
  final frame = await codec.getNextFrame();
  final rgba = (await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  final (w, h) = (frame.image.width, frame.image.height);
  frame.image.dispose();
  codec.dispose();
  descriptor.dispose();
  buffer.dispose();

  final scaled = await compute(
    (ByteData data) => measureQuality(grayFromRgba(data.buffer.asUint8List(), w, h)),
    rgba,
  );
  final measures = QualityMeasures(
    width: width,
    height: height,
    brightness: scaled.brightness,
    sharpness: scaled.sharpness,
  );
  return ImageAnalysis(measures: measures, issues: qualityIssues(measures, thresholds));
}
