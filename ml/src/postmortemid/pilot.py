"""Abattoir pilot: live-to-live and live-to-post-mortem verification on the same animals.

Expected layout under the field root, one folder per study animal:

    PM-0001/L/muzzle/*.jpg    live, before slaughter
    PM-0001/P0/muzzle/*.jpg   post-mortem, at head inspection
    PM-0001/L/face/*.jpg ...

The first k live images (by capture time) form the template. Remaining live
images are the live-to-live queries (E1) and all P0 images are the
live-to-post-mortem queries (E2), so both conditions share one template.
"""

import re
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path

import numpy as np
import pandas as pd
from PIL import Image

from postmortemid import verification

STAGES = ("L", "P0")
MODALITIES = ("muzzle", "face")
IMAGE_SUFFIXES = {".jpg", ".jpeg", ".png"}
EXIF_IFD = 0x8769
EXIF_DATETIME_ORIGINAL = 36867
EXIF_DATETIME = 306
# The app names field photos by capture time, e.g. 20261113_094012_345_17.jpg.
APP_NAME_TIME = re.compile(r"^(\d{8}_\d{6}_\d{3})_")


def capture_time(path: Path) -> datetime | None:
    """EXIF capture time, else the time in an app file name."""
    with Image.open(path) as im:
        exif = im.getexif()
        raw = exif.get_ifd(EXIF_IFD).get(EXIF_DATETIME_ORIGINAL) or exif.get(EXIF_DATETIME)
    if raw:
        return datetime.strptime(str(raw).strip("\x00 "), "%Y:%m:%d %H:%M:%S")
    named = APP_NAME_TIME.match(path.name)
    return datetime.strptime(named.group(1), "%Y%m%d_%H%M%S_%f") if named else None


def scan(root: Path) -> pd.DataFrame:
    """One row per image, ordered by animal, stage, modality and capture time."""
    rows = []
    for path in sorted(root.glob("*/*/*/*")):
        animal, stage, modality = path.relative_to(root).parts[:3]
        if stage not in STAGES or modality not in MODALITIES:
            continue
        if path.suffix.lower() not in IMAGE_SUFFIXES:
            if path.suffix.lower() in {".heic", ".heif"}:
                raise ValueError(f"{path}: HEIC is not supported, export as JPEG")
            continue
        rows.append(
            {
                "identity": animal,
                "stage": stage,
                "modality": modality,
                "path": str(path.relative_to(root)),
                "captured_at": capture_time(path),
            }
        )
    df = pd.DataFrame(rows)
    if df.empty:
        raise ValueError(f"no images found under {root}")
    return df.sort_values(
        ["identity", "stage", "modality", "captured_at", "path"], kind="stable"
    ).reset_index(drop=True)


@dataclass(frozen=True)
class Roles:
    table: pd.DataFrame
    excluded: dict[str, str]


def assign_roles(df: pd.DataFrame, k: int) -> Roles:
    """Roles for one modality: enrol, query_live or query_pm.

    Animals without enough live images or without post-mortem images are excluded.
    """
    parts, excluded = [], {}
    for animal, group in df.groupby("identity", sort=True):
        live = group[group["stage"] == "L"]
        pm = group[group["stage"] == "P0"]
        if len(live) <= k:
            excluded[animal] = f"{len(live)} live images, need more than {k}"
            continue
        if pm.empty:
            excluded[animal] = "no post-mortem images"
            continue
        role = np.where(np.arange(len(live)) < k, "enrol", "query_live")
        parts += [live.assign(role=role), pm.assign(role="query_pm")]
    if not parts:
        raise ValueError("no animal has both enough live images and post-mortem images")
    return Roles(pd.concat(parts), excluded)


def score_condition(roles: pd.DataFrame, emb: np.ndarray, query_role: str) -> pd.DataFrame:
    """Every query of one role against every template. emb rows align with roles rows."""
    keep = roles["role"].isin(["enrol", query_role]).to_numpy()
    part = roles[keep].assign(role=lambda d: d["role"].replace(query_role, "query"))
    scores = verification.score_all(part.reset_index(drop=True), emb[keep])
    scores["path"] = part["path"].to_numpy()[scores["query_pos"]]
    return scores


def minutes_since_slaughter(roles: pd.DataFrame, slaughter: pd.DataFrame) -> pd.Series:
    """Minutes from recorded slaughter time to each post-mortem capture, indexed by path."""
    pm = roles[roles["role"] == "query_pm"].merge(slaughter, on="identity", how="inner")
    pm = pm.dropna(subset=["captured_at"])
    delta = (pd.to_datetime(pm["captured_at"]) - pd.to_datetime(pm["slaughter_time"])).dt
    return pd.Series(delta.total_seconds().to_numpy() / 60, index=pm["path"].to_numpy())
