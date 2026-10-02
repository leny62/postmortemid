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


def eer(
    genuine: np.ndarray,
    impostor: np.ndarray,
    genuine_weight: np.ndarray | None = None,
    impostor_weight: np.ndarray | None = None,
) -> tuple[float, float]:
    y = np.r_[np.ones(len(genuine)), np.zeros(len(impostor))]
    weight = None
    if genuine_weight is not None and impostor_weight is not None:
        weight = np.r_[genuine_weight, impostor_weight]
    far, tar, thresholds = roc_curve(y, np.r_[genuine, impostor], sample_weight=weight)
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


def rates_at(
    genuine: np.ndarray,
    impostor: np.ndarray,
    threshold: float,
    genuine_weight: np.ndarray | None = None,
    impostor_weight: np.ndarray | None = None,
) -> Rates:
    tar = float(np.average(genuine >= threshold, weights=genuine_weight))
    far = float(np.average(impostor >= threshold, weights=impostor_weight))
    return Rates(tar=tar, far=far, frr=1 - tar)


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
    statistic: Callable[[np.ndarray, np.ndarray, np.ndarray, np.ndarray], float],
    n_resamples: int = 2000,
    seed: int = 0,
    level: float = 0.95,
) -> tuple[float, float]:
    """Percentile CI from resampling animals with replacement (subsets bootstrap).

    Comparisons that share an animal are correlated, and an impostor comparison
    involves two animals, the query and the template. Each resample draws
    animals; a genuine comparison is weighted by how often its animal was
    drawn, an impostor comparison by the product for its two animals (Bolle,
    Ratha and Pankanti, 2004). statistic receives genuine scores, impostor
    scores and their weights.
    """
    animals = sorted(set(scores["query_identity"]) | set(scores["template_identity"]))
    query = pd.Categorical(scores["query_identity"], categories=animals).codes
    template = pd.Categorical(scores["template_identity"], categories=animals).codes
    genuine = scores["genuine"].to_numpy(dtype=bool)
    score = scores["score"].to_numpy()
    rng = np.random.default_rng(seed)
    values = []
    for _ in range(n_resamples):
        drawn = np.bincount(rng.integers(len(animals), size=len(animals)), minlength=len(animals))
        weight = np.where(genuine, drawn[query], drawn[query] * drawn[template]).astype(float)
        g, i = genuine & (weight > 0), ~genuine & (weight > 0)
        values.append(statistic(score[g], score[i], weight[g], weight[i]))
    alpha = (1 - level) / 2
    lo, hi = np.quantile(values, [alpha, 1 - alpha])
    return float(lo), float(hi)
