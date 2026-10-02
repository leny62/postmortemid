import 'dart:math' as math;
import 'dart:typed_data';

/// Grayscale image with values in 0..255, stored row-major.
///
/// The operations in this file mirror ml/src/postmortemid/imageops.py so the
/// phone and the research pipeline compute the same numbers.
class GrayImage {
  GrayImage(this.width, this.height, this.pixels)
    : assert(pixels.length == width * height);

  final int width;
  final int height;
  final Float64List pixels;

  double at(int x, int y) => pixels[y * width + x];
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
