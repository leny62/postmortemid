"""Write mobile/assets/model/manifest.json from the E0 results.

The manifest tells the app which encoder to run, with which settings, and the
dev-set thresholds to apply. Run after the notebook has written
ml/experiments/e0_results.json:

    uv run python ml/scripts/export_app_manifest.py
"""

import json

from postmortemid import paths

LBP_MODEL = "LBP (on-device demo)"


def main() -> None:
    results = json.loads((paths.EXPERIMENTS / "e0_results.json").read_text())
    cfg = results["config"]
    app = cfg["app"]
    lbp_row = next(r for r in results["results_test"] if r["model"] == LBP_MODEL)
    dev_animals = results["data"]["split"]["dev"]["animals"]
    manifest = {
        "status": (
            "Initial public-data demonstration. The encoder is an LBP texture descriptor that "
            "shows the offline workflow. It is not the research model, and post-mortem "
            "performance has not been measured."
        ),
        "calibration": (
            f"Thresholds were set on {dev_animals} development animals from a public database of "
            "live cattle (experiment E0, live-to-live)."
        ),
        "encoder": {
            "type": "lbp",
            "model_version": app["model_version"],
            "size": results["lbp_selected"]["size"],
            "grid": results["lbp_selected"]["grid"],
        },
        "thresholds": {
            "version": app["threshold_version"],
            "tau_far1": lbp_row["tau_far1"],
            "tau_far01": lbp_row["tau_far01"],
            "source": "E0 dev animals, FAR targets 1% and 0.1%",
        },
        "quality": app["quality"],
        "enrolment_images": cfg["protocol"]["k_enrol"],
    }
    out = paths.MOBILE_MODEL_ASSETS / "manifest.json"
    out.write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"wrote {out.relative_to(paths.REPO)}")
    print(json.dumps(manifest["thresholds"], indent=2))


if __name__ == "__main__":
    main()
