"""Uniform LBP texture descriptor used as the on-device demonstration encoder.

This is not the research model. It runs on the phone today, in plain Dart,
so the offline workflow can be demonstrated end to end before the
MobileNetV3 model is exported. Mirrored in mobile/lib/biometrics/lbp_encoder.dart.
"""

from dataclasses import asdict, dataclass

import numpy as np

from postmortemid.imageops import gray_square

# Neighbour offsets (dy, dx), clockwise from top-left. Bit i is neighbour i.
NEIGHBOURS = ((-1, -1), (-1, 0), (-1, 1), (0, 1), (1, 1), (1, 0), (1, -1), (0, -1))


@dataclass(frozen=True)
class LbpConfig:
    size: int = 128
    grid: int = 4

    @property
    def dim(self) -> int:
        return self.grid * self.grid * 59

    def to_dict(self) -> dict:
        return asdict(self)


def _uniform_table() -> np.ndarray:
    table = np.full(256, 58, dtype=np.int64)
    next_bin = 0
    for code in range(256):
        bits = [(code >> i) & 1 for i in range(8)]
        transitions = sum(bits[i] != bits[(i + 1) % 8] for i in range(8))
        if transitions <= 2:
            table[code] = next_bin
            next_bin += 1
    assert next_bin == 58
    return table


UNIFORM_TABLE = _uniform_table()


def lbp_codes(gray: np.ndarray) -> np.ndarray:
    h, w = gray.shape
    center = gray[1 : h - 1, 1 : w - 1]
    codes = np.zeros(center.shape, dtype=np.int64)
    for bit, (dy, dx) in enumerate(NEIGHBOURS):
        neighbour = gray[1 + dy : h - 1 + dy, 1 + dx : w - 1 + dx]
        codes |= (neighbour >= center).astype(np.int64) << bit
    return codes


def describe_gray(gray: np.ndarray, cfg: LbpConfig) -> np.ndarray:
    bins = UNIFORM_TABLE[lbp_codes(gray)]
    n = bins.shape[0]
    edges = (np.arange(cfg.grid + 1) * n) // cfg.grid
    parts = []
    for r in range(cfg.grid):
        for c in range(cfg.grid):
            cell = bins[edges[r] : edges[r + 1], edges[c] : edges[c + 1]]
            hist = np.bincount(cell.ravel(), minlength=59).astype(np.float64)
            parts.append(hist / cell.size)
    # Square root before L2 normalisation turns cosine similarity into the
    # Hellinger kernel, which compares histograms better than raw counts.
    vec = np.sqrt(np.concatenate(parts))
    return vec / np.linalg.norm(vec)


def describe(rgb: np.ndarray, cfg: LbpConfig) -> np.ndarray:
    return describe_gray(gray_square(rgb, cfg.size), cfg)
