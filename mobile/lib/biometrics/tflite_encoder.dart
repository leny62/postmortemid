import 'dart:typed_data';

import 'package:flutter_litert/flutter_litert.dart';

import 'biometric_encoder.dart';
import 'image_ops.dart';

/// MobileNetV3-Large embedding network trained with ArcFace, exported by
/// ml/scripts/export_tflite.py. Normalisation is inside the model, so the
/// input is the whole image resized to inputSize, as raw RGB 0..255.
class TfliteEncoder implements BiometricEncoder {
  TfliteEncoder({
    required this.modelVersion,
    required this.modelBytes,
    required this.inputSize,
    required this.embeddingDim,
  });

  @override
  final String modelVersion;
  final Uint8List modelBytes;
  final int inputSize;
  final int embeddingDim;

  // Created on first use in whichever isolate runs the encoder; an
  // interpreter cannot be sent between isolates, but the model bytes can.
  Interpreter? _interpreter;

  @override
  bool get isResearchModel => true;

  @override
  Float64List encode(RgbImage image) {
    final interpreter = _interpreter ??= Interpreter.fromBuffer(modelBytes);
    final input = rgbResize(image, inputSize).reshape([1, inputSize, inputSize, 3]);
    final output = [List<double>.filled(embeddingDim, 0)];
    interpreter.run(input, output);
    return Float64List.fromList(output.first);
  }
}
