"""Measurable capture-quality checks (FR2), mirrored in mobile/lib/biometrics/quality.dart."""

from dataclasses import asdict, dataclass

import numpy as np

from postmortemid.imageops import gray_square

ANALYSIS_SIZE = 256


@dataclass(frozen=True)
class QualityThresholds:
    min_side: int
    min_brightness: float
    max_brightness: float
    min_sharpness: float

    def to_dict(self) -> dict:
        return asdict(self)


@dataclass(frozen=True)
class QualityMeasures:
    width: int
    height: int
    brightness: float
    sharpness: float


def laplacian_variance(gray: np.ndarray) -> float:
    lap = gray[:-2, 1:-1] + gray[2:, 1:-1] + gray[1:-1, :-2] + gray[1:-1, 2:] - 4 * gray[1:-1, 1:-1]
    return float(lap.var())


def measure(rgb: np.ndarray) -> QualityMeasures:
    h, w = rgb.shape[:2]
    # Sharpness depends on scale, so it is always measured at one fixed size.
    gray = gray_square(rgb, ANALYSIS_SIZE)
    return QualityMeasures(
        width=w,
        height=h,
        brightness=float(gray.mean()),
        sharpness=laplacian_variance(gray),
    )


def issues(m: QualityMeasures, t: QualityThresholds) -> list[str]:
    found = []
    if min(m.width, m.height) < t.min_side:
        found.append("too_small")
    if m.brightness < t.min_brightness:
        found.append("too_dark")
    if m.brightness > t.max_brightness:
        found.append("too_bright")
    if m.sharpness < t.min_sharpness:
        found.append("blurry")
    return found
