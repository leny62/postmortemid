"""Loading and cleaning the public muzzle database (Xiong et al., 2022)."""

import hashlib
import re
from itertools import combinations
from pathlib import Path

import cv2
import numpy as np
import pandas as pd
from PIL import Image

from postmortemid import sift

ZENODO_DOI = "10.5281/zenodo.6324361"
ZENODO_URL = "https://zenodo.org/api/records/6324361/files/BeefCattle_Muzzle_database.zip/content"
ARCHIVE_SHA256 = "0a4b519f300e0d96727c60f4515fd8cb6e2c74eaaa1f6fdc43d23b8e44693c1c"
IMAGE_DIR = "BeefCattle_Muzzle_Individualized"

FRAME_PATTERN = re.compile(r"DSCF(\d+)")
# Same-frame crops of one animal share pixels and give dozens to hundreds of
# RANSAC inliers; crops of two different animals in one frame give under 6.
SAME_ANIMAL_MIN_INLIERS = 10
# Two crops of one animal within 2 bits of a 64-bit difference hash are
# effectively the same picture. No sampled cross-animal pair came that close.
NEAR_DUPLICATE_MAX_BITS = 2


def scan(root: Path) -> pd.DataFrame:
    """One row per image: identity (folder), file, size, camera frame number and content hash."""
    rows = []
    for path in sorted((root / IMAGE_DIR).glob("*/*.jpg")):
        with Image.open(path) as im:
            width, height = im.size
            hash_bits = dhash(im)
        match = FRAME_PATTERN.search(path.name)
        rows.append(
            {
                "identity": path.parent.name,
                "file": path.name,
                "path": str(path.relative_to(root)),
                "width": width,
                "height": height,
                "frame": int(match.group(1)) if match else pd.NA,
                "sha1": hashlib.sha1(path.read_bytes()).hexdigest(),
                "dhash": f"{hash_bits:016x}",
            }
        )
    df = pd.DataFrame(rows)
    df["frame"] = df["frame"].astype("Int64")
    return df


def dhash(im: Image.Image) -> int:
    """64-bit difference hash: sign of horizontal gradients on a 9x8 thumbnail."""
    g = np.asarray(im.convert("L").resize((9, 8), Image.Resampling.BILINEAR), dtype=np.int16)
    bits = (g[:, 1:] > g[:, :-1]).ravel()
    return int("".join("1" if b else "0" for b in bits), 2)


def hamming(a: str, b: str) -> int:
    return (int(a, 16) ^ int(b, 16)).bit_count()


def remove_near_duplicates(
    df: pd.DataFrame, max_bits: int = NEAR_DUPLICATE_MAX_BITS
) -> pd.DataFrame:
    """Within each animal, keep an image only if it differs from every image kept before it.

    Consecutive frames of a still animal are almost identical. Leaving them in
    lets a query match its own near-copy in the template and inflates genuine scores.
    """
    keep = []
    for _, group in df.sort_values(["identity", "frame", "file"]).groupby("identity"):
        kept: list[str] = []
        for idx, h in zip(group.index, group["dhash"], strict=True):
            if all(hamming(h, k) > max_bits for k in kept):
                kept.append(h)
                keep.append(idx)
    return df.loc[sorted(keep)]


def find_duplicate_identities(df: pd.DataFrame, root: Path) -> pd.DataFrame:
    """Find folders that hold the same physical animal as another folder.

    Two folders containing crops of the same camera frame are either the same
    animal filed twice, or two animals standing in one photo. SIFT on the
    same-frame crops tells these apart. This only finds duplicates that share
    frames; the same animal photographed in separate sessions is not detected.
    """
    framed = df.dropna(subset=["frame"])
    frames = framed.groupby("identity")["frame"].apply(set)
    lookup = framed.set_index(["identity", "frame"])["path"]
    rows = []
    for a, b in combinations(frames.index, 2):
        shared = sorted(frames[a] & frames[b])
        if not shared:
            continue
        inliers = []
        for frame in shared[:6]:
            fa = sift.describe(_read_gray(root / _first(lookup[(a, frame)])))
            fb = sift.describe(_read_gray(root / _first(lookup[(b, frame)])))
            inliers.append(sift.inlier_matches(fa, fb))
        median = float(np.median(inliers))
        rows.append(
            {
                "identity_a": a,
                "identity_b": b,
                "shared_frames": len(shared),
                "median_inliers": median,
                "same_animal": median >= SAME_ANIMAL_MIN_INLIERS,
            }
        )
    return pd.DataFrame(rows)


def _first(value: object) -> str:
    return value if isinstance(value, str) else str(pd.Series(value).iloc[0])


def _read_gray(path: Path) -> np.ndarray:
    gray = cv2.imread(str(path), cv2.IMREAD_GRAYSCALE)
    if gray is None:
        raise FileNotFoundError(path)
    return np.asarray(gray)


def identities_to_drop(pairs: pd.DataFrame, counts: pd.Series) -> list[str]:
    """For each group of folders showing one animal, keep the folder with most images."""
    same = pairs[pairs["same_animal"]]
    parent: dict[str, str] = {}

    def find(x: str) -> str:
        while parent.get(x, x) != x:
            x = parent[x]
        return x

    for a, b in zip(same["identity_a"], same["identity_b"], strict=True):
        parent[find(a)] = find(b)
    groups: dict[str, list[str]] = {}
    for name in set(same["identity_a"]) | set(same["identity_b"]):
        groups.setdefault(find(name), []).append(name)
    drop = []
    for members in groups.values():
        keep = max(sorted(members), key=lambda m: counts[m])
        drop += [m for m in members if m != keep]
    return sorted(drop)


def load_cache(df: pd.DataFrame, root: Path, cache: Path, size: int) -> np.ndarray:
    """All images resized to size x size RGB uint8, cached as one .npy file in row order."""
    if cache.exists():
        images = np.load(cache, mmap_mode="r")
        if images.shape[0] == len(df) and images.shape[1] == size:
            return images
    out = np.empty((len(df), size, size, 3), dtype=np.uint8)
    for i, rel in enumerate(df["path"]):
        with Image.open(root / rel) as im:
            out[i] = np.asarray(im.convert("RGB").resize((size, size), Image.Resampling.BILINEAR))
    cache.parent.mkdir(parents=True, exist_ok=True)
    np.save(cache, out)
    return out
