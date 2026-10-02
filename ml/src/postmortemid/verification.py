"""1:1 verification protocol: enrol k images per animal, query with the rest."""

import numpy as np
import pandas as pd


def l2_normalise(x: np.ndarray) -> np.ndarray:
    return x / np.linalg.norm(x, axis=-1, keepdims=True)


def cosine(a: np.ndarray, b: np.ndarray) -> float:
    return float(np.dot(a, b) / (np.linalg.norm(a) * np.linalg.norm(b)))


def assign_roles(df: pd.DataFrame, k: int) -> pd.DataFrame:
    """Mark the first k captured images of each animal as enrolment and later ones as queries.

    Capture order follows the camera frame number, so queries are always taken
    after enrolment, as in the study protocol. Animals without a query image
    after enrolment are dropped.
    """
    order = ["identity", "frame", "file"] if "frame" in df else ["identity"]
    parts = []
    for _, group in df.sort_values(order, kind="stable").groupby("identity", sort=True):
        if len(group) <= k:
            continue
        roles = np.where(np.arange(len(group)) < k, "enrol", "query")
        parts.append(group.assign(role=roles))
    return pd.concat(parts).sort_index()


def build_templates(df: pd.DataFrame, emb: np.ndarray) -> tuple[list[str], np.ndarray]:
    """Average the normalised enrolment embeddings of each identity (proposal Section 3.2.3).

    emb rows are aligned with df rows by position.
    """
    emb = l2_normalise(emb)
    enrol = (df["role"] == "enrol").to_numpy()
    ids = df["identity"].to_numpy()
    names = sorted(set(ids[enrol]))
    templates = np.stack([emb[enrol & (ids == name)].mean(0) for name in names])
    return names, l2_normalise(templates)


def score_all(df: pd.DataFrame, emb: np.ndarray) -> pd.DataFrame:
    """Score every query against every template.

    Each query gives one genuine comparison (its own template) and one
    impostor comparison per other enrolled animal.
    """
    names, templates = build_templates(df, emb)
    query = (df["role"] == "query").to_numpy()
    q_emb = l2_normalise(emb[query])
    q_ids = df["identity"].to_numpy()[query]
    q_pos = np.flatnonzero(query)
    sims = q_emb @ templates.T
    rows, cols = np.meshgrid(np.arange(len(q_ids)), np.arange(len(names)), indexing="ij")
    template_ids = np.asarray(names)[cols.ravel()]
    query_ids = q_ids[rows.ravel()]
    return pd.DataFrame(
        {
            "query_pos": q_pos[rows.ravel()],
            "query_identity": query_ids,
            "template_identity": template_ids,
            "score": sims.ravel(),
            "genuine": query_ids == template_ids,
        }
    )


def rank1_accuracy(scores: pd.DataFrame) -> float:
    best = scores.loc[scores.groupby("query_pos")["score"].idxmax()]
    return float(best["genuine"].mean())


def open_set_rejection_rate(scores: pd.DataFrame, tau: float) -> float:
    """Share of queries correctly rejected when their own template is removed from the gallery.

    Mirrors experiment E6: a query is rejected if its best impostor score is below tau.
    """
    best_impostor = scores.loc[~scores["genuine"]].groupby("query_pos")["score"].max()
    return float((best_impostor < tau).mean())
