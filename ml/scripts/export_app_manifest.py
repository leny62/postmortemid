"""Write mobile/assets/model/manifest.json from the E0 results.

The manifest tells the app which encoder to run, with which settings, and the
dev-set thresholds to apply. By default it uses the TFLite ArcFace model
written by export_tflite.py; --encoder lbp selects the LBP fallback.

    uv run python ml/scripts/export_app_manifest.py [--encoder tflite|lbp]
"""

import argparse
import json

from postmortemid import paths

LBP_MODEL = "LBP (on-device demo)"
QUALITY_NOTE = "Post-mortem performance has not been measured."


def lbp_manifest(results: dict) -> dict:
    row = next(r for r in results["results_test"] if r["model"] == LBP_MODEL)
    return {
        "status": (
            "Initial public-data demonstration using the LBP fallback encoder, a texture "
            f"descriptor that is not the research model. {QUALITY_NOTE}"
        ),
        "encoder": {
            "type": "lbp",
            "model_version": "pmid-lbp-demo-v0.1",
            "size": results["lbp_selected"]["size"],
            "grid": results["lbp_selected"]["grid"],
        },
        "thresholds": {
            "version": "e0-lbp-dev-v0.1",
            "tau_far1": row["tau_far1"],
            "tau_far01": row["tau_far01"],
            "source": "E0 dev animals, FAR targets 1% and 0.1%",
        },
    }


def tflite_manifest(results: dict) -> dict:
    tflite = json.loads((paths.EXPERIMENTS / "e0_tflite.json").read_text())
    return {
        "status": (
            "Initial public-data demonstration. The encoder is MobileNetV3-Large trained with "
            "ArcFace on public images of live cattle (experiment E0). It has not been trained "
            f"or tested on Rwandan cattle or smartphone photos. {QUALITY_NOTE}"
        ),
        "encoder": {
            "type": "tflite",
            "model_version": "pmid-mnv3-arcface-e0-v0.1",
            "model_file": tflite["model_file"],
            "input_size": tflite["input"]["shape"][1],
            "embedding_dim": results["config"]["train"]["embedding_dim"],
        },
        "thresholds": {
            "version": "e0-arcface-tflite-dev-v0.1",
            "tau_far1": tflite["tau_far1"],
            "tau_far01": tflite["tau_far01"],
            "source": "E0 dev animals scored by the exported TFLite model, FAR 1% and 0.1%",
        },
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--encoder", choices=["tflite", "lbp"], default="tflite")
    args = parser.parse_args()

    results = json.loads((paths.EXPERIMENTS / "e0_results.json").read_text())
    cfg = results["config"]
    dev_animals = results["data"]["split"]["dev"]["animals"]
    manifest = tflite_manifest(results) if args.encoder == "tflite" else lbp_manifest(results)
    manifest |= {
        "calibration": (
            f"Thresholds were set on {dev_animals} development animals from a public database of "
            "live cattle (experiment E0, live-to-live)."
        ),
        "quality": cfg["app"]["quality"],
        "enrolment_images": cfg["protocol"]["k_enrol"],
    }
    out = paths.MOBILE_MODEL_ASSETS / "manifest.json"
    out.write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"wrote {out.relative_to(paths.REPO)} ({args.encoder})")
    print(json.dumps(manifest["thresholds"], indent=2))


if __name__ == "__main__":
    main()
