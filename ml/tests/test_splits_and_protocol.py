import numpy as np
import pandas as pd
import pytest

from postmortemid import sift, splits, verification
from postmortemid.decision import Decision, decide


def frame(n_ids: int = 30, per_id: int = 6) -> pd.DataFrame:
    return pd.DataFrame(
        {
            "identity": [f"cow{i:02d}" for i in range(n_ids) for _ in range(per_id)],
            "sha1": [f"h{i}" for i in range(n_ids * per_id)],
        }
    )


def test_split_is_identity_disjoint_and_reproducible():
    df = frame()
    a = splits.identity_disjoint_split(df["identity"], seed=1)
    b = splits.identity_disjoint_split(df["identity"], seed=1)
    assert a == b
    df["split"] = df["identity"].map(a)
    splits.check_disjoint(df)
    counts = df.groupby("split")["identity"].nunique()
    assert counts.to_dict() == {"train": 18, "dev": 6, "test": 6}


def test_check_disjoint_detects_identity_leakage():
    df = frame(3, 2).assign(split=["train", "test", "dev", "dev", "test", "test"])
    with pytest.raises(AssertionError, match="cow00"):
        splits.check_disjoint(df)


def test_check_disjoint_detects_same_file_in_two_splits():
    df = pd.DataFrame(
        {"identity": ["a", "b"], "sha1": ["same", "same"], "split": ["train", "test"]}
    )
    with pytest.raises(AssertionError, match="identical image files"):
        splits.check_disjoint(df)


def test_roles_and_scoring():
    df = frame(4, 5)
    roles = verification.assign_roles(df, k=3).reset_index(drop=True)
    assert (roles.groupby("identity")["role"].apply(lambda r: (r == "enrol").sum()) == 3).all()

    rng = np.random.default_rng(0)
    centres = rng.normal(size=(4, 16))
    ids = roles["identity"].str[-2:].astype(int).to_numpy()
    emb = centres[ids] + 0.01 * rng.normal(size=(len(roles), 16))
    scores = verification.score_all(roles, emb)
    # 2 queries per animal; each against 4 templates.
    assert len(scores) == 8 * 4
    assert scores["genuine"].sum() == 8
    assert verification.rank1_accuracy(scores) == 1.0
    assert verification.open_set_rejection_rate(scores, tau=0.99) == 1.0


def test_identities_with_too_few_images_are_dropped():
    df = pd.DataFrame({"identity": ["a"] * 3 + ["b"] * 5})
    roles = verification.assign_roles(df, k=3)
    assert set(roles["identity"]) == {"b"}


def test_three_band_decision():
    assert decide(0.95, 0.8, 0.9) is Decision.MATCH
    assert decide(0.9, 0.8, 0.9) is Decision.MATCH
    assert decide(0.85, 0.8, 0.9) is Decision.REVIEW
    assert decide(0.8, 0.8, 0.9) is Decision.REVIEW
    assert decide(0.79, 0.8, 0.9) is Decision.NO_MATCH
    with pytest.raises(ValueError):
        decide(0.5, 0.9, 0.8)


def test_enrolment_uses_the_earliest_frames():
    df = pd.DataFrame({"identity": ["a"] * 5, "frame": [40, 10, 30, 20, 50], "file": list("vwxyz")})
    roles = verification.assign_roles(df, k=3)
    enrolled = roles.loc[roles["role"] == "enrol", "frame"].tolist()
    assert sorted(enrolled) == [10, 20, 30]


def test_query_start_keeps_the_same_queries_for_every_k():
    df = pd.DataFrame(
        {
            "identity": ["a"] * 8 + ["b"] * 5,
            "frame": list(range(8)) + list(range(5)),
            "file": [f"f{n}" for n in range(13)],
        }
    )
    queries = [
        verification.assign_roles(df, k, query_start=5).query("role == 'query'")["frame"].tolist()
        for k in (1, 3, 5)
    ]
    assert queries[0] == queries[1] == queries[2] == [5, 6, 7]
    with pytest.raises(ValueError):
        verification.assign_roles(df, 3, query_start=2)


def test_open_set_rejection_counts_queries_with_a_strong_impostor():
    scores = pd.DataFrame(
        {
            "query_pos": [0, 0, 1, 1],
            "query_identity": ["a", "a", "b", "b"],
            "template_identity": ["a", "b", "b", "a"],
            "score": [0.9, 0.7, 0.9, 0.2],
            "genuine": [True, False, True, False],
        }
    )
    assert verification.open_set_rejection_rate(scores, tau=0.5) == 0.5
    assert verification.rank1_accuracy(scores) == 1.0


def test_sift_scores_own_animal_and_sampled_impostors(monkeypatch):
    df = frame(5, 4)
    roles = verification.assign_roles(df, k=3).reset_index(drop=True)
    empty: tuple[np.ndarray, np.ndarray | None] = (np.zeros((0, 2), np.float32), None)
    monkeypatch.setattr(sift, "inlier_matches", lambda a, b: 1)
    scores = sift.score_sampled(roles, [empty] * len(roles), impostors_per_query=2, seed=0)
    for _, rows in scores.groupby("query_pos"):
        assert len(rows) == 3
        assert rows["genuine"].to_numpy().sum() == 1
    own = scores["query_identity"] == scores["template_identity"]
    assert scores["genuine"].equals(own)
