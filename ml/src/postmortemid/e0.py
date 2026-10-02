"""Experiment E0: public-data live-to-live baseline on held-out animals.

Thresholds are always fixed on dev animals and then applied once to test
animals, so the reported test FAR is a realised rate, not an oracle.
"""

import hashlib
import json
from dataclasses import dataclass

import cv2
import numpy as np
import pandas as pd
import torch

from postmortemid import dataset, lbp, metrics, paths, sift, training, verification
from postmortemid.imageops import load_rgb, to_gray
from postmortemid.models import FrozenImageNetEncoder


@dataclass
class E0Data:
    cfg: dict
    images: pd.DataFrame
    pixels: np.ndarray


def load(cfg_name: str = "e0.json") -> E0Data:
    cfg = json.loads((paths.CONFIGS / cfg_name).read_text())
    return from_images(cfg, pd.read_csv(paths.SPLITS / "e0_images.csv"))


def from_images(cfg: dict, images: pd.DataFrame, cache: bool = True) -> E0Data:
    """Pixels for any image table; cached on disk unless cache is False."""
    size = cfg["image_cache_size"]
    digest = hashlib.sha1("\n".join(images["path"]).encode()).hexdigest()[:10]
    path = paths.CACHE / f"e0_{size}_{digest}.npy" if cache else None
    pixels = dataset.load_cache(images, paths.RAW, path, size)
    return E0Data(cfg=cfg, images=images, pixels=pixels)


def split_with_roles(
    data: E0Data, split: str, k: int | None = None, query_start: int | None = None
) -> tuple[pd.DataFrame, np.ndarray]:
    """Rows of one split with enrol/query roles; also returns their positions in data.images."""
    part = data.images[data.images["split"] == split]
    roles = verification.assign_roles(part, k or data.cfg["protocol"]["k_enrol"], query_start)
    return roles, roles.index.to_numpy()


def lbp_embeddings(data: E0Data, cfg: lbp.LbpConfig) -> np.ndarray:
    return np.stack([lbp.describe(load_rgb(paths.RAW / p), cfg) for p in data.images["path"]])


def cnn_embeddings(data: E0Data, model: torch.nn.Module, device: torch.device) -> np.ndarray:
    return training.embed(model, np.asarray(data.pixels), data.cfg["train"]["image_size"], device)


def imagenet_embeddings(data: E0Data, device: torch.device) -> np.ndarray:
    return cnn_embeddings(data, FrozenImageNetEncoder(), device)


def sift_features(data: E0Data, positions: np.ndarray) -> list:
    out = []
    for p in data.images["path"].to_numpy()[positions]:
        gray = to_gray(load_rgb(paths.RAW / p))
        h, w = gray.shape
        scale = sift.SIFT_SIZE / max(h, w)
        if scale < 1:
            gray = cv2.resize(
                gray, (round(w * scale), round(h * scale)), interpolation=cv2.INTER_AREA
            )
        out.append(sift.describe(gray.clip(0, 255).astype(np.uint8)))
    return out


def scores_for(
    data: E0Data,
    emb: np.ndarray,
    split: str,
    k: int | None = None,
    query_start: int | None = None,
) -> pd.DataFrame:
    roles, pos = split_with_roles(data, split, k, query_start)
    return verification.score_all(roles.reset_index(drop=True), emb[pos])


def sift_scores_for(data: E0Data, split: str) -> pd.DataFrame:
    roles, pos = split_with_roles(data, split)
    s = data.cfg["sift"]
    return sift.score_sampled(
        roles.reset_index(drop=True), sift_features(data, pos), s["impostors_per_query"], s["seed"]
    )


def train(
    data: E0Data, loss: str, device: torch.device, monitor: bool = True
) -> tuple[torch.nn.Module, pd.DataFrame]:
    """Fine-tune MobileNetV3-Large on train animals only.

    The dev curve is for monitoring; the final epoch is always used, so dev
    data do not pick the checkpoint and stay clean for threshold setting.
    """
    cfg = training.TrainConfig(**(data.cfg["train"] | {"loss": loss}))
    part = data.images[data.images["split"] == "train"]
    labels = pd.factorize(part["identity"], sort=True)[0]
    images = np.asarray(data.pixels)[part.index.to_numpy()]

    def dev_metrics(epoch: int, model: torch.nn.Module) -> dict:
        s = scores_for(data, cnn_embeddings(data, model, device), "dev")
        g, i = s.loc[s["genuine"], "score"].to_numpy(), s.loc[~s["genuine"], "score"].to_numpy()
        return {"dev_roc_auc": metrics.roc_auc(g, i), "dev_eer": metrics.eer(g, i)[0]}

    model, history = training.train_embedder(
        images, labels, cfg, device, dev_metrics if monitor else None
    )
    return model, pd.DataFrame(history)


def calibrate(dev_scores: pd.DataFrame) -> dict[str, float]:
    impostor = dev_scores.loc[~dev_scores["genuine"], "score"].to_numpy()
    return {
        "tau_far1": metrics.threshold_at_far(impostor, 0.01),
        "tau_far01": metrics.threshold_at_far(impostor, 0.001),
    }


def report(
    name: str,
    dev_scores: pd.DataFrame,
    test_scores: pd.DataFrame,
    cfg: dict,
    exhaustive: bool = True,
) -> dict:
    """Test metrics at dev-calibrated thresholds.

    Rank-1 and open-set rejection need every template scored, so they are
    left out for sampled-impostor runs such as SIFT.
    """
    thresholds = calibrate(dev_scores)
    row = {"model": name, **thresholds}
    row |= metrics.summarise(test_scores, thresholds["tau_far1"], thresholds["tau_far01"])
    b = cfg["bootstrap"]

    def eer_stat(g: np.ndarray, i: np.ndarray, gw: np.ndarray, iw: np.ndarray) -> float:
        return metrics.eer(g, i, gw, iw)[0]

    def tar1_stat(g: np.ndarray, i: np.ndarray, gw: np.ndarray, iw: np.ndarray) -> float:
        return metrics.rates_at(g, i, thresholds["tau_far1"], gw, iw).tar

    def far1_stat(g: np.ndarray, i: np.ndarray, gw: np.ndarray, iw: np.ndarray) -> float:
        return metrics.rates_at(g, i, thresholds["tau_far1"], gw, iw).far

    for key, stat in [
        ("eer", eer_stat),
        ("calibrated_tar_at_far1", tar1_stat),
        ("realised_far_at_far1", far1_stat),
    ]:
        row[f"{key}_ci"] = metrics.bootstrap_ci(test_scores, stat, b["n_resamples"], b["seed"])
    if exhaustive:
        row["rank1"] = verification.rank1_accuracy(test_scores)
        row["open_set_rejection_at_far1"] = verification.open_set_rejection_rate(
            test_scores, thresholds["tau_far1"]
        )
    return row
