import 'dart:math' as math;
import 'dart:typed_data';

import 'biometric_encoder.dart';
import 'image_ops.dart';

const _neighbours = [(-1, -1), (-1, 0), (-1, 1), (0, 1), (1, 1), (1, 0), (1, -1), (0, -1)];

final List<int> _uniformTable = () {
  final table = List<int>.filled(256, 58);
  var next = 0;
  for (var code = 0; code < 256; code++) {
    var transitions = 0;
    for (var i = 0; i < 8; i++) {
      if (((code >> i) & 1) != ((code >> ((i + 1) % 8)) & 1)) transitions++;
    }
    if (transitions <= 2) table[code] = next++;
  }
  return table;
}();

/// Uniform LBP histogram descriptor. Mirrors ml/src/postmortemid/lbp.py.
class LbpDescriptor implements Preprocessor {
  const LbpDescriptor({this.size = 64, this.grid = 4});

  final int size;
  final int grid;

  int get dim => grid * grid * 59;

  @override
  Float64List call(RgbImage image) => describeGray(graySquare(image.toGray(), size));

  Float64List describeGray(GrayImage g) {
    final n = g.width - 2;
    final bins = List<int>.filled(n * n, 0);
    for (var y = 1; y < g.height - 1; y++) {
      for (var x = 1; x < g.width - 1; x++) {
        final c = g.at(x, y);
        var code = 0;
        for (var bit = 0; bit < 8; bit++) {
          final (dy, dx) = _neighbours[bit];
          if (g.at(x + dx, y + dy) >= c) code |= 1 << bit;
        }
        bins[(y - 1) * n + (x - 1)] = _uniformTable[code];
      }
    }

    final vec = Float64List(dim);
    for (var r = 0; r < grid; r++) {
      final r0 = (r * n) ~/ grid, r1 = ((r + 1) * n) ~/ grid;
      for (var c = 0; c < grid; c++) {
        final c0 = (c * n) ~/ grid, c1 = ((c + 1) * n) ~/ grid;
        final offset = (r * grid + c) * 59;
        final count = (r1 - r0) * (c1 - c0);
        for (var y = r0; y < r1; y++) {
          for (var x = c0; x < c1; x++) {
            vec[offset + bins[y * n + x]] += 1 / count;
          }
        }
      }
    }
    var norm = 0.0;
    for (var i = 0; i < vec.length; i++) {
      vec[i] = math.sqrt(vec[i]);
      norm += vec[i] * vec[i];
    }
    norm = math.sqrt(norm);
    for (var i = 0; i < vec.length; i++) {
      vec[i] /= norm;
    }
    return vec;
  }
}

/// A training-free baseline, kept as a fallback encoder. It is not the
/// research model. The whole descriptor is computed in the analysis isolate.
class LbpEncoder implements BiometricEncoder {
  const LbpEncoder({required this.modelVersion, this.preprocessor = const LbpDescriptor()});

  @override
  final String modelVersion;
  @override
  final LbpDescriptor preprocessor;

  @override
  bool get isResearchModel => false;

  @override
  Future<Float64List> embed(TypedData input) async => input as Float64List;
}
