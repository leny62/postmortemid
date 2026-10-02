import numpy as np
import pandas as pd
import pytest

from postmortemid import metrics


def test_threshold_at_far_never_exceeds_target_with_ties():
    impostor = np.array([0.1] * 50 + [0.5] * 50)
    tau = metrics.threshold_at_far(impostor, 0.01)
    assert np.mean(impostor >= tau) <= 0.01


def test_threshold_at_far_allows_exactly_k_false_accepts():
    impostor = np.arange(1000) / 1000
    tau = metrics.threshold_at_far(impostor, 0.01)
    assert np.sum(impostor >= tau) == 10


def test_perfect_separation():
    g = np.array([0.9, 0.95, 0.99])
    i = np.array([0.1, 0.2, 0.3])
    assert metrics.roc_auc(g, i) == 1.0
    assert metrics.eer(g, i)[0] == 0.0
    assert metrics.tar_at_far(g, i, 0.01) == 1.0


def test_eer_for_overlapping_scores():
    g = np.array([0.4, 0.6, 0.8, 0.9])
    i = np.array([0.1, 0.3, 0.5, 0.7])
    value, _ = metrics.eer(g, i)
    assert value == pytest.approx(0.25)


def test_rates_at_threshold():
    r = metrics.rates_at(np.array([0.2, 0.6, 0.9]), np.array([0.1, 0.7]), 0.5)
    assert r.tar == pytest.approx(2 / 3)
    assert r.frr == pytest.approx(1 / 3)
    assert r.far == pytest.approx(0.5)


def test_bootstrap_resamples_animals_not_pairs():
    rows = []
    for animal in range(20):
        rows.append((f"a{animal}", 0.9 if animal < 10 else 0.4, True))
        rows += [(f"a{animal}", 0.2, False)] * 30
    scores = pd.DataFrame(rows, columns=["query_identity", "score", "genuine"])
    lo, hi = metrics.bootstrap_ci(scores, lambda g, i: float(np.mean(g >= 0.5)), 500, 0)
    # Half the animals are accepted, so the interval must be wide around 0.5.
    assert lo < 0.4 < 0.6 < hi
