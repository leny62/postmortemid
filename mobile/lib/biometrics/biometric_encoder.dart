import 'dart:typed_data';

import 'image_ops.dart';

/// Turns a captured image into an L2-normalised embedding.
///
/// The prototype ships [LbpEncoder], a demonstration encoder. The research
/// model (MobileNetV3-Large with ArcFace, exported to TFLite) will be a second
/// implementation of this interface, so the UI and storage do not change.
abstract interface class BiometricEncoder {
  String get modelVersion;

  /// False for any encoder whose accuracy has not been evaluated as the research model.
  bool get isResearchModel;

  Float64List encode(GrayImage image);
}
