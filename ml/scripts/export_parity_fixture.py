"""Write a synthetic test image and the values the Python pipeline computes for it.

mobile/test/parity_test.dart checks that the Dart implementation gives the
same quality measures and LBP descriptor. A synthetic PNG is used so the
test has no licensing constraints and no JPEG decoder differences.

    uv run python ml/scripts/export_parity_fixture.py
"""

import json

import numpy as np
from PIL import Image

from postmortemid import lbp, paths, quality

OUT = paths.REPO / "mobile" / "test" / "fixtures"


def synthetic_image(width: int = 300, height: int = 220, seed: int = 3) -> np.ndarray:
    rng = np.random.default_rng(seed)
    y, x = np.mgrid[0:height, 0:width]
    texture = 60 * np.sin(x / 5.0) * np.cos(y / 7.0) + 0.4 * x + 0.2 * y
    channels = [texture + rng.normal(0, 12, texture.shape) + offset for offset in (90, 70, 50)]
    return np.clip(np.stack(channels, axis=-1), 0, 255).astype(np.uint8)


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    rgb = synthetic_image()
    Image.fromarray(rgb).save(OUT / "parity.png")
    cfg = lbp.LbpConfig(size=64, grid=4)
    m = quality.measure(rgb)
    expected = {
        "width": m.width,
        "height": m.height,
        "brightness": m.brightness,
        "sharpness": m.sharpness,
        "lbp": {"size": cfg.size, "grid": cfg.grid, "vector": lbp.describe(rgb, cfg).tolist()},
    }
    (OUT / "parity.json").write_text(json.dumps(expected))
    print(f"wrote {OUT / 'parity.png'} and parity.json")


if __name__ == "__main__":
    main()
