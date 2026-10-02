"""Build the cleaned E0 image table and identity-disjoint split from the raw download."""

from dataclasses import dataclass

import pandas as pd

from postmortemid import dataset, paths, splits

COLUMNS = ["identity", "file", "path", "width", "height", "frame", "sha1", "dhash", "split"]


@dataclass
class Prepared:
    raw: pd.DataFrame
    shared_frame_screen: pd.DataFrame
    dropped_identities: list[str]
    distinct: pd.DataFrame
    images: pd.DataFrame


def prepare(cfg: dict) -> Prepared:
    if not (paths.RAW / dataset.IMAGE_DIR).exists():
        raise FileNotFoundError(f"Dataset not found under {paths.RAW}. See docs/dataset.md.")
    raw = dataset.scan(paths.RAW)
    screen = dataset.find_duplicate_identities(raw, paths.RAW)
    drop = dataset.identities_to_drop(screen, raw.groupby("identity").size())
    distinct = raw[~raw["identity"].isin(drop)]
    kept = dataset.remove_near_duplicates(distinct, cfg["near_duplicate_max_bits"]).copy()
    assignment = splits.identity_disjoint_split(
        kept["identity"], tuple(cfg["split"]["fractions"]), cfg["split"]["seed"]
    )
    kept["split"] = kept["identity"].map(assignment)
    splits.check_disjoint(kept)
    kept = kept.reset_index(drop=True)[COLUMNS]

    paths.SPLITS.mkdir(parents=True, exist_ok=True)
    screen.to_csv(paths.SPLITS / "shared_frame_screen.csv", index=False)
    (paths.SPLITS / "dropped_duplicate_identities.txt").write_text("\n".join(drop) + "\n")
    kept.to_csv(paths.SPLITS / "e0_images.csv", index=False)
    return Prepared(raw, screen, drop, distinct, kept)
