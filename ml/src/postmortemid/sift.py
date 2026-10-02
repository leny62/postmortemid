"""Training-free SIFT keypoint baseline (proposal Section 3.2.2)."""

import cv2
import numpy as np
import pandas as pd

SIFT_SIZE = 320
RATIO = 0.75


def describe(gray_uint8: np.ndarray) -> tuple[np.ndarray, np.ndarray | None]:
    sift = cv2.SIFT_create(nfeatures=500)
    keypoints, desc = sift.detectAndCompute(gray_uint8, None)
    points = np.array([k.pt for k in keypoints], dtype=np.float32)
    return points, desc


def inlier_matches(
    a: tuple[np.ndarray, np.ndarray | None], b: tuple[np.ndarray, np.ndarray | None]
) -> int:
    """Ratio-test matches that are also consistent with one homography."""
    (pts_a, desc_a), (pts_b, desc_b) = a, b
    if desc_a is None or desc_b is None or len(desc_a) < 2 or len(desc_b) < 2:
        return 0
    pairs = cv2.BFMatcher(cv2.NORM_L2).knnMatch(desc_a, desc_b, k=2)
    good = [p[0] for p in pairs if len(p) == 2 and p[0].distance < RATIO * p[1].distance]
    if len(good) < 4:
        return len(good)
    src = pts_a[[m.queryIdx for m in good]]
    dst = pts_b[[m.trainIdx for m in good]]
    _, mask = cv2.findHomography(src, dst, cv2.RANSAC, 5.0)
    return 0 if mask is None else int(mask.sum())


def score_sampled(
    df: pd.DataFrame,
    features: list[tuple[np.ndarray, np.ndarray | None]],
    impostors_per_query: int,
    seed: int,
) -> pd.DataFrame:
    """Score each query against its own enrolment images and a random sample of other animals.

    The score for a (query, animal) pair is the best inlier count over that
    animal's enrolment images. Impostors are sampled because exhaustive
    RANSAC matching over every pair is too slow for a laptop run.
    """
    rng = np.random.default_rng(seed)
    roles = df["role"].to_numpy()
    ids = df["identity"].to_numpy()
    enrol_by_id: dict[str, list[int]] = {}
    for pos in np.flatnonzero(roles == "enrol"):
        enrol_by_id.setdefault(ids[pos], []).append(int(pos))
    names = sorted(enrol_by_id)
    rows = []
    for q in np.flatnonzero(roles == "query"):
        own = ids[q]
        others = [n for n in names if n != own]
        sampled = rng.choice(others, size=min(impostors_per_query, len(others)), replace=False)
        for name in [own, *sampled]:
            score = max(inlier_matches(features[q], features[e]) for e in enrol_by_id[name])
            rows.append((int(q), own, name, float(score), name == own))
    return pd.DataFrame(
        rows, columns=["query_pos", "query_identity", "template_identity", "score", "genuine"]
    )
