"""Train the E0 ArcFace model and save its weights for on-device export.

Training is deterministic for a given config, so this reproduces the model
evaluated in the notebook. The script checks that by comparing test metrics
with ml/experiments/e0_results.json before saving.

    uv run python ml/scripts/train_arcface.py
"""

import json

import torch

from postmortemid import e0, metrics, paths, training

MODEL_FILE = paths.ARTIFACTS / "pmid-mnv3-arcface-e0-v0.1.pt"


def main() -> None:
    data = e0.load()
    device = training.pick_device()
    # Monitoring stays on: its evaluation passes advance the random stream, and the
    # notebook trains with them, so turning it off would train a different model.
    model, _ = e0.train(data, "arcface", device)
    emb = e0.cnn_embeddings(data, model, device)
    dev, test = e0.scores_for(data, emb, "dev"), e0.scores_for(data, emb, "test")
    th = e0.calibrate(dev)
    got = metrics.summarise(test, th["tau_far1"], th["tau_far01"])

    results = json.loads((paths.EXPERIMENTS / "e0_results.json").read_text())
    want = next(
        r for r in results["results_test"] if r["model"] == "MobileNetV3 ArcFace (proposed)"
    )
    for key in ("eer", "calibrated_tar_at_far1", "tau_far1"):
        value = got.get(key, th.get(key))
        if abs(value - want[key]) > 1e-6:
            raise SystemExit(f"{key}: {value} differs from the notebook ({want[key]})")

    paths.ARTIFACTS.mkdir(parents=True, exist_ok=True)
    torch.save({"state_dict": model.cpu().state_dict(), "config": data.cfg["train"]}, MODEL_FILE)
    print(f"matches notebook (EER {got['eer']:.4f}); saved {MODEL_FILE.relative_to(paths.REPO)}")


if __name__ == "__main__":
    main()
