"""Identity-disjoint splitting. The animal, never the image, is the unit of assignment."""

from collections.abc import Iterable

import numpy as np
import pandas as pd

SPLITS = ("train", "dev", "test")


def identity_disjoint_split(
    identities: Iterable[str],
    fractions: tuple[float, float, float] = (0.6, 0.2, 0.2),
    seed: int = 42,
) -> dict[str, str]:
    if not np.isclose(sum(fractions), 1.0):
        raise ValueError("fractions must sum to 1")
    unique = sorted(set(identities))
    rng = np.random.default_rng(seed)
    order = rng.permutation(len(unique))
    n_train = round(fractions[0] * len(unique))
    n_dev = round(fractions[1] * len(unique))
    assignment = {}
    for rank, idx in enumerate(order):
        if rank < n_train:
            split = "train"
        elif rank < n_train + n_dev:
            split = "dev"
        else:
            split = "test"
        assignment[unique[idx]] = split
    return assignment


def check_disjoint(df: pd.DataFrame) -> None:
    """Raise if any identity or any image file appears in more than one split."""
    per_identity = df.groupby("identity")["split"].nunique()
    leaked = per_identity[per_identity > 1]
    if not leaked.empty:
        raise AssertionError(f"identities in more than one split: {list(leaked.index)}")
    if "sha1" in df:
        per_file = df.groupby("sha1")["split"].nunique()
        if (per_file > 1).any():
            raise AssertionError("identical image files appear in more than one split")
