import 'dart:typed_data';

import 'package:flutter_litert/flutter_litert.dart';

import 'biometric_encoder.dart';
import 'image_ops.dart';

/// Whole image resized to inputSize x inputSize, raw RGB 0..255. Normalisation
/// is inside the exported model.
class CnnInput implements Preprocessor {
  const CnnInput(this.inputSize);

  final int inputSize;

  @override
  Float32List call(RgbImage image) => rgbResize(image, inputSize);
}

/// MobileNetV3-Large embedding network trained with ArcFace, exported by
/// ml/scripts/export_tflite.py.
class TfliteEncoder implements BiometricEncoder {
  TfliteEncoder({
    required this.modelVersion,
    required this.modelBytes,
    required int inputSize,
    required this.embeddingDim,
  }) : preprocessor = CnnInput(inputSize);

  @override
  final String modelVersion;
  final Uint8List modelBytes;
  final int embeddingDim;

  @override
  final CnnInput preprocessor;

  // One interpreter for the life of the app, run on its own isolate so the UI
  // stays responsive. Building one per image would copy and leak the model.
  Future<IsolateInterpreter>? _runner;

  @override
  bool get isResearchModel => true;

  Future<IsolateInterpreter> _start() async {
    final interpreter = Interpreter.fromBuffer(modelBytes);
    return IsolateInterpreter.create(address: interpreter.address);
  }

  @override
  Future<Float64List> embed(TypedData input) async {
    final runner = await (_runner ??= _start());
    final output = Float32List(embeddingDim);
    await runner.run(input, output);
    return Float64List.fromList(output);
  }
}
