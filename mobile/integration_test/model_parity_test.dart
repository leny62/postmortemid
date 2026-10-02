import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:postmortemid/biometrics/image_analysis.dart';
import 'package:postmortemid/biometrics/image_ops.dart';
import 'package:postmortemid/biometrics/model_manifest.dart';
import 'package:postmortemid/biometrics/tflite_encoder.dart';
import 'package:postmortemid/biometrics/verifier.dart';

import 'expected_embedding.dart';

// Same pattern as synthetic_rgb in ml/scripts/export_tflite.py.
RgbImage syntheticRgb({int width = 320, int height = 240}) {
  final px = Uint8List(width * height * 3);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final base = 128 + 60 * math.sin(x / 5) * math.cos(y / 7) + 0.3 * (x - y);
      for (final (c, offset) in [(0, 20.0), (1, 0.0), (2, -20.0)]) {
        px[(y * width + x) * 3 + c] = (base + offset).clamp(0, 255).floor();
      }
    }
  }
  return RgbImage(width, height, px);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('on-device model matches the laptop and reports its speed', (tester) async {
    final manifest = await ModelManifest.load();
    final encoder = manifest.encoder;
    expect(encoder, isA<TfliteEncoder>());

    final input = encoder.preprocessor(syntheticRgb());
    final watch = Stopwatch()..start();
    final first = await encoder.embed(input);
    final firstMs = watch.elapsedMilliseconds;

    const runs = 10;
    watch.reset();
    for (var i = 0; i < runs; i++) {
      await encoder.embed(input);
    }
    final modelMs = watch.elapsedMilliseconds / runs;

    // The full path the app takes for one photo: read, decode, quality check,
    // resize in a background isolate, then the model. A 720 x 720 JPEG is the
    // size of a camera photo cropped to the guide square.
    final photo = img.copyResize(
      img.Image.fromBytes(
        width: 320,
        height: 240,
        bytes: syntheticRgb().pixels.buffer,
        numChannels: 3,
      ),
      width: 720,
      height: 720,
    );
    final file = File('${Directory.systemTemp.path}/pmid_timing.jpg')
      ..writeAsBytesSync(img.encodeJpg(photo, quality: 95));
    watch.reset();
    for (var i = 0; i < 5; i++) {
      final analysis = await analyseFile(file.path, manifest.quality, encoder);
      expect(analysis.embedding, isNotNull);
    }
    final appMs = watch.elapsedMilliseconds / 5;

    final agreement = Verifier.cosine(first, Float64List.fromList(expectedEmbedding));
    final modelMb = (encoder as TfliteEncoder).modelBytes.lengthInBytes / 1e6;
    // ignore: avoid_print
    print(
      'ON_DEVICE model=${encoder.modelVersion} size_mb=${modelMb.toStringAsFixed(1)} '
      'first_ms=$firstMs model_ms=${modelMs.toStringAsFixed(1)} '
      'photo_to_embedding_ms=${appMs.toStringAsFixed(0)} '
      'cosine_vs_laptop=${agreement.toStringAsFixed(6)}',
    );
    expect(agreement, greaterThan(0.999));
  });
}
