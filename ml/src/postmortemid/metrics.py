"""Verification metrics. Accept means score >= threshold throughout."""

from collections.abc import Callable
from dataclasses import dataclass

import numpy as np
import pandas as pd
from sklearn.metrics import roc_auc_score, roc_curve


def _split(scores: pd.DataFrame) -> tuple[np.ndarray, np.ndarray]:
    genuine = scores.loc[scores["genuine"], "score"].to_numpy()
    impostor = scores.loc[~scores["genuine"], "score"].to_numpy()
    return genuine, impostor


def roc_auc(genuine: np.ndarray, impostor: np.ndarray) -> float:
    y = np.r_[np.ones(len(genuine)), np.zeros(len(impostor))]
    return float(roc_auc_score(y, np.r_[genuine, impostor]))


def eer(genuine: np.ndarray, impostor: np.ndarray) -> tuple[float, float]:
    y = np.r_[np.ones(len(genuine)), np.zeros(len(impostor))]
    far, tar, thresholds = roc_curve(y, np.r_[genuine, impostor])
    frr = 1 - tar
    i = int(np.argmin(np.abs(far - frr)))
    return float((far[i] + frr[i]) / 2), float(thresholds[i])


def threshold_at_far(impostor: np.ndarray, far: float) -> float:
    """Lowest threshold whose false-accept rate on these impostors is <= far."""
    ranked = np.sort(impostor)[::-1]
    k = int(np.floor(far * len(ranked)))
    if k >= len(ranked):
        return float(ranked[-1])
    # Accepting only scores strictly above the (k+1)-th highest impostor keeps
    # at most k false accepts, even when scores are tied.
    return float(np.nextafter(ranked[k], np.inf))


@dataclass(frozen=True)
class Rates:
    tar: float
    far: float
    frr: float


def rates_at(genuine: np.ndarray, impostor: np.ndarray, threshold: float) -> Rates:
    tar = float(np.mean(genuine >= threshold))
    return Rates(tar=tar, far=float(np.mean(impostor >= threshold)), frr=1 - tar)


def tar_at_far(genuine: np.ndarray, impostor: np.ndarray, far: float) -> float:
    return rates_at(genuine, impostor, threshold_at_far(impostor, far)).tar


def summarise(scores: pd.DataFrame, tau_far1: float, tau_far01: float) -> dict[str, float]:
    """Metrics on an evaluation set, using thresholds fixed beforehand on development data."""
    g, i = _split(scores)
    eer_value, _ = eer(g, i)
    at1 = rates_at(g, i, tau_far1)
    at01 = rates_at(g, i, tau_far01)
    return {
        "n_genuine": len(g),
        "n_impostor": len(i),
        "roc_auc": roc_auc(g, i),
        "eer": eer_value,
        "oracle_tar_at_far1": tar_at_far(g, i, 0.01),
        "oracle_tar_at_far01": tar_at_far(g, i, 0.001),
        "calibrated_tar_at_far1": at1.tar,
        "realised_far_at_far1": at1.far,
        "calibrated_tar_at_far01": at01.tar,
        "realised_far_at_far01": at01.far,
    }


def bootstrap_ci(
    scores: pd.DataFrame,
    statistic: Callable[[np.ndarray, np.ndarray], float],
    n_resamples: int = 1000,
    seed: int = 0,
    level: float = 0.95,
) -> tuple[float, float]:
    """Percentile CI from resampling query animals with replacement.

    Comparisons from one animal are correlated, so the animal, not the image
    pair, is the resampling unit (proposal Section 3.2.4).
    """
    rng = np.random.default_rng(seed)
    groups = {k: _split(v) for k, v in scores.groupby("query_identity")}
    keys = list(groups)
    values = []
    for _ in range(n_resamples):
        picked = rng.choice(len(keys), size=len(keys), replace=True)
        g = np.concatenate([groups[keys[j]][0] for j in picked])
        i = np.concatenate([groups[keys[j]][1] for j in picked])
        values.append(statistic(g, i))
    alpha = (1 - level) / 2
    lo, hi = np.quantile(values, [alpha, 1 - alpha])
    return float(lo), float(hi)
