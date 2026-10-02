import numpy as np
import pandas as pd

from postmortemid import dataset, imageops, lbp, quality


def test_box_resize_matches_block_mean():
    g = np.arange(16, dtype=float).reshape(4, 4)
    np.testing.assert_allclose(imageops.box_resize(g, 2), [[2.5, 4.5], [10.5, 12.5]])


def test_box_resize_upsamples_by_repetition():
    g = np.array([[1.0, 2.0], [3.0, 4.0]])
    np.testing.assert_allclose(imageops.box_resize(g, 4)[0], [1, 1, 2, 2])


def test_center_square_crops_the_long_side():
    img = np.zeros((100, 160))
    assert imageops.center_square(img).shape == (100, 100)


def test_lbp_vector_is_unit_length_and_lighting_invariant():
    rng = np.random.default_rng(0)
    rgb = rng.integers(0, 200, size=(120, 150, 3)).astype(np.uint8)
    cfg = lbp.LbpConfig(size=64, grid=4)
    v = lbp.describe(rgb, cfg)
    assert v.shape == (cfg.dim,)
    assert abs(np.linalg.norm(v) - 1) < 1e-12
    brighter = (rgb.astype(int) + 40).clip(0, 255).astype(np.uint8)
    assert float(v @ lbp.describe(brighter, cfg)) > 0.99


def test_uniform_table_has_58_uniform_patterns():
    assert len(set(lbp.UNIFORM_TABLE[lbp.UNIFORM_TABLE < 58])) == 58
    assert lbp.UNIFORM_TABLE[0] != 58 and lbp.UNIFORM_TABLE[255] != 58
    assert lbp.UNIFORM_TABLE[0b01010101] == 58


def test_quality_flags_blur_darkness_and_size():
    t = quality.QualityThresholds(
        min_side=256, min_brightness=40, max_brightness=220, min_sharpness=20
    )
    flat = np.full((300, 300, 3), 120, dtype=np.uint8)
    assert quality.issues(quality.measure(flat), t) == ["blurry"]
    dark = np.full((300, 300, 3), 10, dtype=np.uint8)
    assert "too_dark" in quality.issues(quality.measure(dark), t)
    small = np.random.default_rng(1).integers(0, 255, (100, 400, 3)).astype(np.uint8)
    assert quality.issues(quality.measure(small), t) == ["too_small"]


def test_duplicate_groups_keep_the_largest_folder():
    pairs = pd.DataFrame(
        {
            "identity_a": ["a", "a", "c"],
            "identity_b": ["b", "x", "d"],
            "same_animal": [True, True, False],
        }
    )
    counts = pd.Series({"a": 10, "b": 4, "x": 12, "c": 5, "d": 5})
    assert dataset.identities_to_drop(pairs, counts) == ["a", "b"]


def test_near_duplicates_are_removed_within_but_not_across_animals():
    df = pd.DataFrame(
        {
            "identity": ["a", "a", "a", "b"],
            "frame": [1, 2, 3, 1],
            "file": ["1", "2", "3", "4"],
            "dhash": [
                "ffff000000000000",
                "ffff000000000001",
                "0000ffff00000000",
                "ffff000000000000",
            ],
        }
    )
    kept = dataset.remove_near_duplicates(df, max_bits=2)
    assert kept["file"].tolist() == ["1", "3", "4"]
