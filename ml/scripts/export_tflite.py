# /// script
# requires-python = ">=3.12,<3.13"
# dependencies = [
#     "litert-torch==0.9.4",
#     "torch==2.13.*",
#     "torchvision==0.28.*",
#     "numpy>=2.0",
#     "pandas>=2.2",
#     "pillow>=11.0",
#     "scikit-learn>=1.5",
#     "opencv-python-headless>=4.10",
# ]
# ///
"""Export the E0 ArcFace model to TensorFlow Lite and recalibrate it for the phone.

The converter needs an older PyTorch than the main environment, so this runs
as a standalone script with its own pinned dependencies:

    uv run --script ml/scripts/export_tflite.py [--score-test]

It converts the saved weights, checks the TFLite output against PyTorch,
then scores dev animals with the TFLite model and the exact preprocessing
the app uses. The thresholds written to ml/experiments/e0_tflite.json are
the ones the app applies. Test animals are scored only with --score-test,
once the export is final, so test numbers cannot steer export choices.
"""

import argparse
import json
import sys
from pathlib import Path

import numpy as np
import torch
import torch.nn.functional as F
from torch import nn

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / "ml" / "src"))

from postmortemid import e0, metrics, paths, verification  # noqa: E402
from postmortemid.imageops import load_rgb, rgb_resize  # noqa: E402
from postmortemid.models import MuzzleEmbedder  # noqa: E402
from postmortemid.training import IMAGENET_MEAN, IMAGENET_STD  # noqa: E402

WEIGHTS = paths.ARTIFACTS / "pmid-mnv3-arcface-e0-v0.1.pt"
OUT = paths.MOBILE_MODEL_ASSETS / "pmid-mnv3-arcface-e0-v0.1.tflite"
SIZE = 224


class PhoneEncoder(nn.Module):
    """Takes raw RGB pixels (1, 224, 224, 3) in 0..255 and returns a unit-length embedding.

    Normalisation and the channel transpose live inside the model so the app
    only resizes and copies pixels.
    """

    def __init__(self, embedder: MuzzleEmbedder) -> None:
        super().__init__()
        self.embedder = embedder
        self.register_buffer("mean", torch.tensor(IMAGENET_MEAN).view(1, 3, 1, 1) * 255)
        self.register_buffer("std", torch.tensor(IMAGENET_STD).view(1, 3, 1, 1) * 255)

    def forward(self, rgb: torch.Tensor) -> torch.Tensor:
        x = (rgb.permute(0, 3, 1, 2) - self.mean) / self.std
        return F.normalize(self.embedder(x), dim=1)


def phone_input(path: str) -> np.ndarray:
    return rgb_resize(load_rgb(paths.RAW / path), SIZE).astype(np.float32)[None]


def synthetic_rgb(width: int = 320, height: int = 240) -> np.ndarray:
    """Deterministic test pattern that the Dart integration test rebuilds pixel for pixel."""
    y, x = np.mgrid[0:height, 0:width].astype(np.float64)
    base = 128 + 60 * np.sin(x / 5) * np.cos(y / 7) + 0.3 * (x - y)
    channels = [np.floor(np.clip(base + offset, 0, 255)) for offset in (20.0, 0.0, -20.0)]
    return np.stack(channels, axis=-1).astype(np.uint8)


def write_device_fixture(run) -> None:
    rgb = synthetic_rgb()
    expected = run(rgb_resize(rgb, SIZE).astype(np.float32)[None])
    values = ", ".join(f"{v:.8f}" for v in expected)
    path = REPO / "mobile" / "integration_test" / "expected_embedding.dart"
    path.parent.mkdir(exist_ok=True)
    path.write_text(
        "// Written by ml/scripts/export_tflite.py: TFLite output for the synthetic\n"
        "// pattern in model_parity_test.dart, computed on the laptop.\n"
        f"const expectedEmbedding = <double>[{values}];\n"
    )
    print(f"wrote {path.relative_to(REPO)}")


def main() -> None:
    import litert_torch
    from ai_edge_litert.interpreter import Interpreter

    parser = argparse.ArgumentParser()
    parser.add_argument("--fixture-only", action="store_true")
    parser.add_argument("--score-test", action="store_true")
    args = parser.parse_args()

    saved = torch.load(WEIGHTS, map_location="cpu")
    embedder = MuzzleEmbedder(saved["config"]["embedding_dim"])
    embedder.load_state_dict(saved["state_dict"])
    model = PhoneEncoder(embedder).eval()

    if not args.fixture_only:
        sample = torch.from_numpy(phone_input(e0.load().images["path"].iloc[0]))
        litert_torch.convert(model, (sample,)).export(str(OUT))
        print(f"wrote {OUT.relative_to(REPO)} ({OUT.stat().st_size / 1e6:.1f} MB)")

    interpreter = Interpreter(model_path=str(OUT))
    interpreter.allocate_tensors()
    inp = interpreter.get_input_details()[0]
    out = interpreter.get_output_details()[0]

    def run(x: np.ndarray) -> np.ndarray:
        interpreter.set_tensor(inp["index"], x)
        interpreter.invoke()
        return interpreter.get_tensor(out["index"])[0]

    write_device_fixture(run)
    if args.fixture_only:
        return

    data = e0.load()
    scored = ["dev", "test"] if args.score_test else ["dev"]
    keep = data.images["split"].isin(scored).to_numpy()
    emb = np.zeros((len(data.images), saved["config"]["embedding_dim"]), dtype=np.float32)
    agreement = []
    with torch.no_grad():
        for i in np.flatnonzero(keep):
            x = phone_input(data.images["path"].iloc[i])
            emb[i] = run(x)
            if len(agreement) < 50:
                ref = model(torch.from_numpy(x))[0].numpy()
                agreement.append(float(verification.cosine(ref, emb[i])))
    print(f"TFLite vs PyTorch cosine on 50 images: min {min(agreement):.6f}")

    dev = e0.scores_for(data, emb, "dev")
    th = e0.calibrate(dev)
    g = dev.loc[dev["genuine"], "score"].to_numpy()
    i = dev.loc[~dev["genuine"], "score"].to_numpy()
    result = {
        "model_file": OUT.name,
        "model_bytes": OUT.stat().st_size,
        "input": {
            "shape": [1, SIZE, SIZE, 3],
            "pixels": "RGB 0..255, whole image antialiased bilinear resize",
        },
        "tflite_vs_pytorch_min_cosine": min(agreement),
        **th,
        "dev": {"roc_auc": metrics.roc_auc(g, i), "eer": metrics.eer(g, i)[0]},
    }
    if args.score_test:
        test = e0.scores_for(data, emb, "test")
        result["test"] = metrics.summarise(test, th["tau_far1"], th["tau_far01"])
        result["rank1"] = verification.rank1_accuracy(test)
    (paths.EXPERIMENTS / "e0_tflite.json").write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps({k: v for k, v in result.items() if k != "input"}, indent=2))


if __name__ == "__main__":
    main()
