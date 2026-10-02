import 'dart:typed_data';

import 'image_ops.dart';

/// Pure-Dart step from a decoded image to the encoder's input. It runs in the
/// analysis isolate, so implementations hold only plain values.
abstract interface class Preprocessor {
  TypedData call(RgbImage image);
}

/// Turns a captured image into an L2-normalised embedding, in two steps:
/// [preprocessor] runs in the background isolate that decodes the photo, and
/// [embed] runs where the model lives.
///
/// [TfliteEncoder] runs the MobileNetV3-Large ArcFace model exported from the
/// research pipeline. [LbpEncoder] is a plain-Dart texture descriptor kept as
/// a fallback. The manifest picks one, so the UI and storage do not change.
abstract interface class BiometricEncoder {
  String get modelVersion;

  /// True only for the model architecture the proposal specifies.
  bool get isResearchModel;

  Preprocessor get preprocessor;

  Future<Float64List> embed(TypedData input);
}
