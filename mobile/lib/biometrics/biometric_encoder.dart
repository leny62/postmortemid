import 'dart:typed_data';

import 'image_ops.dart';

/// Turns a captured image into an L2-normalised embedding.
///
/// [TfliteEncoder] runs the MobileNetV3-Large ArcFace model exported from the
/// research pipeline. [LbpEncoder] is a plain-Dart texture descriptor kept as
/// a fallback. The manifest picks one, so the UI and storage do not change.
abstract interface class BiometricEncoder {
  String get modelVersion;

  /// True only for the model architecture the proposal specifies.
  bool get isResearchModel;

  Float64List encode(RgbImage image);
}
