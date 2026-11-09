from datetime import datetime

import numpy as np
import pandas as pd
import pytest
from PIL import Image

from postmortemid import metrics, pilot


def write_image(path, when: str | None = None) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    im = Image.new("RGB", (64, 48), (120, 90, 80))
    exif = Image.Exif()
    if when:
        exif.get_ifd(pilot.EXIF_IFD)[pilot.EXIF_DATETIME_ORIGINAL] = when
    im.save(path, exif=exif)


def field(tmp_path, live: int = 4, pm: int = 2):
    for a in ("PM-0001", "PM-0002"):
        for n in range(live):
            write_image(tmp_path / a / "L" / "muzzle" / f"{n}.jpg", f"2026:11:10 09:0{n}:00")
        for n in range(pm):
            write_image(tmp_path / a / "P0" / "muzzle" / f"{n}.jpg", f"2026:11:10 10:0{n}:00")
    return tmp_path


def test_scan_reads_layout_and_capture_time(tmp_path):
    df = pilot.scan(field(tmp_path))
    assert len(df) == 12
    assert set(df["stage"]) == {"L", "P0"}
    assert df.loc[0, "captured_at"] == datetime(2026, 11, 10, 9, 0)


def test_scan_rejects_heic(tmp_path):
    p = tmp_path / "PM-0001" / "L" / "muzzle" / "a.HEIC"
    p.parent.mkdir(parents=True)
    p.write_bytes(b"")
    with pytest.raises(ValueError, match="HEIC"):
        pilot.scan(tmp_path)


def test_roles_enrol_earliest_live_and_exclude_incomplete(tmp_path):
    root = field(tmp_path)
    write_image(root / "PM-0003" / "L" / "muzzle" / "0.jpg", "2026:11:10 09:00:00")
    roles = pilot.assign_roles(pilot.scan(root), k=3)
    assert "PM-0003" in roles.excluded
    a1 = roles.table[roles.table["identity"] == "PM-0001"]
    assert a1["role"].tolist() == ["enrol"] * 3 + ["query_live"] + ["query_pm"] * 2
    assert a1.loc[a1["role"] == "enrol", "path"].str.endswith(("0.jpg", "1.jpg", "2.jpg")).all()


def test_live_and_postmortem_conditions_share_templates(tmp_path):
    roles = pilot.assign_roles(pilot.scan(field(tmp_path)), k=3).table
    emb = np.random.default_rng(0).normal(size=(len(roles), 8))
    live = pilot.score_condition(roles, emb, "query_live")
    pm = pilot.score_condition(roles, emb, "query_pm")
    assert len(live) == 2 * 1 * 2 and len(pm) == 2 * 2 * 2
    assert live["genuine"].sum() == 2 and pm["genuine"].sum() == 4


def test_minutes_since_slaughter(tmp_path):
    roles = pilot.assign_roles(pilot.scan(field(tmp_path)), k=3).table
    times = pd.DataFrame({"identity": ["PM-0001"], "slaughter_time": ["2026-11-10 09:50"]})
    minutes = pilot.minutes_since_slaughter(roles, times)
    assert sorted(minutes.tolist()) == [10.0, 11.0]


def test_paired_bootstrap_of_identical_tables_is_zero():
    ids = [f"a{n}" for n in range(6)]
    rng = np.random.default_rng(0)
    scores = pd.DataFrame(
        [(q, t, q == t) for q in ids for t in ids],
        columns=["query_identity", "template_identity", "genuine"],
    )
    scores["score"] = np.where(scores["genuine"], 0.8, 0.2) + rng.normal(0, 0.2, len(scores))

    def eer(g, i, gw, iw):
        return metrics.eer(g, i, gw, iw)[0]

    lo, hi = metrics.paired_bootstrap_ci([scores, scores], lambda s: s[1] - s[0], eer, 200)
    assert lo == hi == 0.0
