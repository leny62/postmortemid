"""Image operations shared with the mobile app.

The Dart code in mobile/lib/biometrics/image_ops.dart implements the same
functions. Any change here must be made there too, and the parity fixture in
mobile/test/fixtures must be regenerated with ml/scripts/export_parity_fixture.py.
"""

from pathlib import Path

import numpy as np
from PIL import Image, ImageOps


def load_rgb(path: str | Path) -> np.ndarray:
    with Image.open(path) as im:
        return np.asarray(ImageOps.exif_transpose(im).convert("RGB"))


def to_gray(rgb: np.ndarray) -> np.ndarray:
    rgb = rgb.astype(np.float64)
    return 0.299 * rgb[..., 0] + 0.587 * rgb[..., 1] + 0.114 * rgb[..., 2]


def center_square(img: np.ndarray) -> np.ndarray:
    h, w = img.shape[:2]
    side = min(h, w)
    top = (h - side) // 2
    left = (w - side) // 2
    return img[top : top + side, left : left + side]


def _bounds(n: int, size: int) -> tuple[np.ndarray, np.ndarray]:
    start = (np.arange(size) * n) // size
    end = np.maximum((np.arange(1, size + 1) * n) // size, start + 1)
    return start, end


def box_resize(gray: np.ndarray, size: int) -> np.ndarray:
    """Area-average resize of a 2D array to size x size.

    Downsampling averages each source block; upsampling repeats the nearest
    source pixel. Chosen over library resizers because it is trivial to
    reproduce exactly in Dart, so phone and laptop compute the same descriptor.
    """
    h, w = gray.shape
    row_start, row_end = _bounds(h, size)
    col_start, col_end = _bounds(w, size)
    integral = np.zeros((h + 1, w + 1), dtype=np.float64)
    integral[1:, 1:] = gray.cumsum(0).cumsum(1)
    r0, r1 = row_start[:, None], row_end[:, None]
    c0, c1 = col_start[None, :], col_end[None, :]
    total = integral[r1, c1] - integral[r0, c1] - integral[r1, c0] + integral[r0, c0]
    area = (r1 - r0) * (c1 - c0)
    return total / area


def gray_square(rgb: np.ndarray, size: int) -> np.ndarray:
    return box_resize(center_square(to_gray(rgb)), size)


def _bilinear_weights(n_in: int, n_out: int) -> np.ndarray:
    """Antialiased bilinear resampling matrix (n_out x n_in), PIL's BILINEAR filter in floats.

    When shrinking, the triangle filter is widened by the scale factor so every
    source pixel contributes, as PIL does; when enlarging it interpolates.
    """
    scale = n_in / n_out
    support = max(scale, 1.0)
    weights = np.zeros((n_out, n_in))
    for i in range(n_out):
        center = (i + 0.5) * scale
        lo = max(int(center - support + 0.5), 0)
        hi = min(int(center + support + 0.5), n_in)
        taps = np.arange(lo, hi)
        w = np.maximum(0.0, 1.0 - np.abs((taps - center + 0.5) / support))
        weights[i, lo:hi] = w / w.sum()
    return weights


def rgb_resize(rgb: np.ndarray, size: int) -> np.ndarray:
    """Whole-image antialiased bilinear resize to size x size, as the phone does for the CNN input.

    The image is squashed, not cropped, matching how the training images were resized.
    Mirrored by rgbResize in mobile/lib/biometrics/image_ops.dart.
    """
    h, w = rgb.shape[:2]
    rows, cols = _bilinear_weights(h, size), _bilinear_weights(w, size)
    return np.stack([rows @ rgb[..., c].astype(np.float64) @ cols.T for c in range(3)], axis=-1)
