import 'dart:math' as math;
import 'dart:typed_data';

/// Grayscale image with values in 0..255, stored row-major.
///
/// The operations in this file mirror ml/src/postmortemid/imageops.py so the
/// phone and the research pipeline compute the same numbers.
class GrayImage {
  GrayImage(this.width, this.height, this.pixels) : assert(pixels.length == width * height);

  final int width;
  final int height;
  final Float64List pixels;

  double at(int x, int y) => pixels[y * width + x];
}

/// Decoded 8-bit RGB pixels, row-major, three bytes per pixel.
class RgbImage {
  RgbImage(this.width, this.height, this.pixels) : assert(pixels.length == width * height * 3);

  final int width;
  final int height;
  final Uint8List pixels;

  GrayImage toGray() => grayFromRgb(pixels, width, height);
}

GrayImage grayFromRgb(Uint8List rgb, int width, int height) {
  final out = Float64List(width * height);
  for (var i = 0; i < out.length; i++) {
    final r = rgb[i * 3], g = rgb[i * 3 + 1], b = rgb[i * 3 + 2];
    out[i] = 0.299 * r + 0.587 * g + 0.114 * b;
  }
  return GrayImage(width, height, out);
}

GrayImage centerSquare(GrayImage img) {
  final side = math.min(img.width, img.height);
  final top = (img.height - side) ~/ 2;
  final left = (img.width - side) ~/ 2;
  final out = Float64List(side * side);
  for (var y = 0; y < side; y++) {
    for (var x = 0; x < side; x++) {
      out[y * side + x] = img.at(left + x, top + y);
    }
  }
  return GrayImage(side, side, out);
}

/// Area-average resize to size x size. Upsampling repeats the nearest pixel.
GrayImage boxResize(GrayImage img, int size) {
  final w = img.width, h = img.height;
  final integral = Float64List((w + 1) * (h + 1));
  for (var y = 0; y < h; y++) {
    var rowSum = 0.0;
    for (var x = 0; x < w; x++) {
      rowSum += img.at(x, y);
      integral[(y + 1) * (w + 1) + x + 1] = integral[y * (w + 1) + x + 1] + rowSum;
    }
  }
  double sum(int r0, int r1, int c0, int c1) =>
      integral[r1 * (w + 1) + c1] -
      integral[r0 * (w + 1) + c1] -
      integral[r1 * (w + 1) + c0] +
      integral[r0 * (w + 1) + c0];

  final out = Float64List(size * size);
  for (var i = 0; i < size; i++) {
    final r0 = (i * h) ~/ size;
    final r1 = math.max(((i + 1) * h) ~/ size, r0 + 1);
    for (var j = 0; j < size; j++) {
      final c0 = (j * w) ~/ size;
      final c1 = math.max(((j + 1) * w) ~/ size, c0 + 1);
      out[i * size + j] = sum(r0, r1, c0, c1) / ((r1 - r0) * (c1 - c0));
    }
  }
  return GrayImage(size, size, out);
}

GrayImage graySquare(GrayImage img, int size) => boxResize(centerSquare(img), size);

/// Antialiased bilinear resampling weights, PIL's BILINEAR filter in floats.
/// Mirrors _bilinear_weights in ml/src/postmortemid/imageops.py.
List<(int, Float64List)> _bilinearWeights(int nIn, int nOut) {
  final scale = nIn / nOut;
  final support = math.max(scale, 1.0);
  return [
    for (var i = 0; i < nOut; i++)
      () {
        final center = (i + 0.5) * scale;
        final lo = math.max((center - support + 0.5).toInt(), 0);
        final hi = math.min((center + support + 0.5).toInt(), nIn);
        final w = Float64List(hi - lo);
        var sum = 0.0;
        for (var t = lo; t < hi; t++) {
          w[t - lo] = math.max(0.0, 1.0 - ((t - center + 0.5) / support).abs());
          sum += w[t - lo];
        }
        for (var k = 0; k < w.length; k++) {
          w[k] /= sum;
        }
        return (lo, w);
      }(),
  ];
}

/// Whole-image antialiased bilinear resize to size x size, RGB interleaved, as
/// the CNN expects. Mirrors rgb_resize in ml/src/postmortemid/imageops.py.
Float32List rgbResize(RgbImage img, int size) {
  final rows = _bilinearWeights(img.height, size);
  final cols = _bilinearWeights(img.width, size);
  // Horizontal pass first: height x size x 3.
  final tmp = Float64List(img.height * size * 3);
  for (var y = 0; y < img.height; y++) {
    for (var j = 0; j < size; j++) {
      final (lo, w) = cols[j];
      var r = 0.0, g = 0.0, b = 0.0;
      for (var k = 0; k < w.length; k++) {
        final p = (y * img.width + lo + k) * 3;
        r += w[k] * img.pixels[p];
        g += w[k] * img.pixels[p + 1];
        b += w[k] * img.pixels[p + 2];
      }
      final o = (y * size + j) * 3;
      tmp[o] = r;
      tmp[o + 1] = g;
      tmp[o + 2] = b;
    }
  }
  final out = Float32List(size * size * 3);
  for (var i = 0; i < size; i++) {
    final (lo, w) = rows[i];
    for (var j = 0; j < size; j++) {
      var r = 0.0, g = 0.0, b = 0.0;
      for (var k = 0; k < w.length; k++) {
        final p = ((lo + k) * size + j) * 3;
        r += w[k] * tmp[p];
        g += w[k] * tmp[p + 1];
        b += w[k] * tmp[p + 2];
      }
      final o = (i * size + j) * 3;
      out[o] = r;
      out[o + 1] = g;
      out[o + 2] = b;
    }
  }
  return out;
}
