"""Score the abattoir pilot with the E0 models, without retraining.

    uv run python ml/scripts/run_pilot.py [--root ml/data/field] [--k 3]

Optional ml/data/field/slaughter_times.csv (identity,slaughter_time as
YYYY-MM-DD HH:MM) enables the time-since-slaughter check. Thresholds come from
E0 dev animals, so calibrated rates here measure a cross-domain transfer.
Writes ml/experiments/pilot_results.json, pilot_scores.csv and figures in docs/figures.
"""

import argparse
import json
from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
import torch
from PIL import Image
from scipy.stats import spearmanr

from postmortemid import metrics, paths, pilot, training, verification
from postmortemid.imageops import center_square, load_rgb
from postmortemid.models import FrozenImageNetEncoder, MuzzleEmbedder
from postmortemid.quality import QualityThresholds, issues, measure

ARCFACE = "MobileNetV3 ArcFace (proposed)"
IMAGENET = "MobileNetV3 ImageNet (frozen)"
CACHE_SIZE = 256
CONDITIONS = {"live_to_live": "query_live", "live_to_postmortem": "query_pm"}
FIGURES = paths.REPO / "docs" / "figures"


def load_pixels(root: Path, rel_paths: pd.Series) -> np.ndarray:
    out = np.empty((len(rel_paths), CACHE_SIZE, CACHE_SIZE, 3), dtype=np.uint8)
    for i, rel in enumerate(rel_paths):
        square = Image.fromarray(center_square(load_rgb(root / rel)))
        out[i] = np.asarray(square.resize((CACHE_SIZE, CACHE_SIZE), Image.Resampling.BILINEAR))
    return out


def arcface_model() -> torch.nn.Module:
    saved = torch.load(paths.ARTIFACTS / "pmid-mnv3-arcface-e0-v0.1.pt", map_location="cpu")
    model = MuzzleEmbedder(saved["config"]["embedding_dim"])
    model.load_state_dict(saved["state_dict"])
    return model


def e0_thresholds() -> dict[str, dict[str, float]]:
    e0 = json.loads((paths.EXPERIMENTS / "e0_results.json").read_text())
    return {r["model"]: {k: r[k] for k in ("tau_far1", "tau_far01")} for r in e0["results_test"]}


def auc_stat(g, i, gw, iw) -> float:
    return metrics.roc_auc(g, i, gw, iw)


def eer_stat(g, i, gw, iw) -> float:
    return metrics.eer(g, i, gw, iw)[0]


def condition_summary(scores: pd.DataFrame, tau: dict[str, float], boot: dict) -> dict:
    row = metrics.summarise(scores, tau["tau_far1"], tau["tau_far01"])
    row["n_animals"] = scores["query_identity"].nunique()
    row["open_set_rejection_at_far1"] = verification.open_set_rejection_rate(
        scores, tau["tau_far1"]
    )
    for name, stat in [("roc_auc", auc_stat), ("eer", eer_stat)]:
        row[f"{name}_ci"] = metrics.bootstrap_ci(scores, stat, **boot)
    return row


def drop_ci(live: pd.DataFrame, pm: pd.DataFrame, boot: dict) -> dict:
    return {
        "roc_auc_change": metrics.roc_auc(*_g_i(pm)) - metrics.roc_auc(*_g_i(live)),
        "roc_auc_change_ci": metrics.paired_bootstrap_ci(
            [live, pm], lambda s: s[1] - s[0], auc_stat, **boot
        ),
    }


def _g_i(scores: pd.DataFrame) -> tuple[np.ndarray, np.ndarray]:
    return (
        scores.loc[scores["genuine"], "score"].to_numpy(),
        scores.loc[~scores["genuine"], "score"].to_numpy(),
    )


def plot_distributions(runs: dict[str, dict[str, pd.DataFrame]], out: Path) -> None:
    fig, axes = plt.subplots(1, len(runs), figsize=(4.2 * len(runs), 3.4), squeeze=False)
    for ax, (label, conds) in zip(axes[0], runs.items(), strict=True):
        live, pm = conds["live_to_live"], conds["live_to_postmortem"]
        bins = np.linspace(-0.2, 1.0, 49)
        ax.hist(
            live.loc[~live["genuine"], "score"],
            bins,
            density=True,
            alpha=0.45,
            color="#888888",
            label="Impostor",
        )
        ax.hist(
            live.loc[live["genuine"], "score"],
            bins,
            density=True,
            histtype="step",
            linewidth=1.8,
            color="#1f6fb4",
            label="Genuine, live to live",
        )
        ax.hist(
            pm.loc[pm["genuine"], "score"],
            bins,
            density=True,
            histtype="step",
            linewidth=1.8,
            color="#c0392b",
            label="Genuine, live to post-mortem",
        )
        ax.set_title(label, fontsize=10)
        ax.set_xlabel("Cosine similarity")
    axes[0][0].set_ylabel("Density")
    axes[0][-1].legend(fontsize=8, frameon=False)
    fig.tight_layout()
    fig.savefig(out, dpi=200)
    plt.close(fig)


def plot_time(points: pd.DataFrame, out: Path) -> None:
    fig, ax = plt.subplots(figsize=(4.6, 3.4))
    ax.scatter(points["minutes"], points["score"], s=14, color="#c0392b")
    ax.set_xlabel("Minutes since slaughter")
    ax.set_ylabel("Genuine score (ArcFace, muzzle)")
    fig.tight_layout()
    fig.savefig(out, dpi=200)
    plt.close(fig)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=paths.FIELD)
    parser.add_argument("--k", type=int, default=3)
    parser.add_argument("--resamples", type=int, default=2000)
    args = parser.parse_args()

    cfg = json.loads((paths.CONFIGS / "e0.json").read_text())
    boot = {"n_resamples": args.resamples, "seed": cfg["bootstrap"]["seed"]}
    thresholds = QualityThresholds(**cfg["app"]["quality"])
    tau = e0_thresholds()
    device = training.pick_device()
    images = pilot.scan(args.root)
    images["quality_issues"] = [
        ",".join(issues(measure(load_rgb(args.root / p)), thresholds)) for p in images["path"]
    ]

    models = {ARCFACE: arcface_model(), IMAGENET: FrozenImageNetEncoder()}
    plan = [(ARCFACE, "muzzle"), (IMAGENET, "muzzle"), (IMAGENET, "face")]
    results: dict = {
        "experiment": "Pilot (E1, E2, E3, E5, E6)",
        "k_enrol": args.k,
        "thresholds_from": "E0 dev animals (public live data)",
        "n_images": int(len(images)),
        "quality_flagged": int((images["quality_issues"] != "").sum()),
        "runs": {},
    }
    runs: dict[str, dict[str, pd.DataFrame]] = {}
    all_scores = []
    for model_name, modality in plan:
        part = images[images["modality"] == modality]
        if part.empty:
            continue
        roles = pilot.assign_roles(part, args.k)
        emb = training.embed(
            models[model_name],
            load_pixels(args.root, roles.table["path"]),
            cfg["train"]["image_size"],
            device,
        )
        label = f"{model_name}, {modality}"
        conds = {c: pilot.score_condition(roles.table, emb, r) for c, r in CONDITIONS.items()}
        runs[label] = conds
        results["runs"][label] = {
            "excluded_animals": roles.excluded,
            **{c: condition_summary(s, tau[model_name], boot) for c, s in conds.items()},
            **drop_ci(conds["live_to_live"], conds["live_to_postmortem"], boot),
        }
        for c, s in conds.items():
            all_scores.append(s.assign(model=model_name, modality=modality, condition=c))
        if (model_name, modality) == (ARCFACE, "muzzle"):
            arc_roles = roles.table

    muzzle, face = f"{IMAGENET}, muzzle", f"{IMAGENET}, face"
    if muzzle in runs and face in runs:
        tables = [
            runs[muzzle]["live_to_live"],
            runs[muzzle]["live_to_postmortem"],
            runs[face]["live_to_live"],
            runs[face]["live_to_postmortem"],
        ]
        results["muzzle_vs_face_auc_drop_difference_ci"] = metrics.paired_bootstrap_ci(
            tables, lambda s: (s[1] - s[0]) - (s[3] - s[2]), auc_stat, **boot
        )

    slaughter_file = args.root / "slaughter_times.csv"
    arc_label = f"{ARCFACE}, muzzle"
    if slaughter_file.exists() and arc_label in runs:
        minutes = pilot.minutes_since_slaughter(arc_roles, pd.read_csv(slaughter_file))
        pm = runs[arc_label]["live_to_postmortem"]
        genuine = pm[pm["genuine"]].assign(minutes=lambda d: d["path"].map(minutes)).dropna()
        if genuine["minutes"].nunique() > 2:
            rho, p = spearmanr(genuine["minutes"], genuine["score"])
            results["time_since_slaughter"] = {
                "n_queries": len(genuine),
                "minutes_range": [float(genuine["minutes"].min()), float(genuine["minutes"].max())],
                "spearman_rho": float(rho),
                "p_value": float(p),
            }
            plot_time(genuine, FIGURES / "pilot_time_since_slaughter.png")

    FIGURES.mkdir(parents=True, exist_ok=True)
    plot_distributions(runs, FIGURES / "pilot_score_distributions.png")
    pd.concat(all_scores).drop(columns="query_pos").to_csv(
        paths.EXPERIMENTS / "pilot_scores.csv", index=False
    )
    out = paths.EXPERIMENTS / "pilot_results.json"
    out.write_text(json.dumps(results, indent=2, default=float) + "\n")
    print(json.dumps(results, indent=2, default=float))


if __name__ == "__main__":
    main()
