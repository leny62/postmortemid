import io
import zipfile
from datetime import datetime

import pandas as pd
import pytest
from PIL import Image

from postmortemid import field_import, pilot


def jpeg(shade: int = 120, when: str | None = None) -> bytes:
    out = io.BytesIO()
    exif = Image.Exif()
    if when:
        exif.get_ifd(pilot.EXIF_IFD)[pilot.EXIF_DATETIME_ORIGINAL] = when
    Image.new("RGB", (32, 24), (shade, 90, 80)).save(out, "JPEG", exif=exif)
    return out.getvalue()


def app_zip(path, photos: dict[str, bytes], slaughter: str, device: str = "Phone A"):
    with zipfile.ZipFile(path, "w") as z:
        for name, data in photos.items():
            z.writestr(name, data)
        identities = sorted({n.split("/")[0] for n in photos})
        z.writestr("slaughter_times.csv", f"identity,slaughter_time\n{identities[0]},{slaughter}\n")
        z.writestr(
            "field_animals.csv",
            "identity,linkage_status,device_model\n"
            + "".join(f"{i},confirmed,{device}\n" for i in identities),
        )
        z.writestr("field_images.csv", "file,identity\n" + "".join(f"{n},x\n" for n in photos))
    return path


def test_capture_time_falls_back_to_the_app_file_name(tmp_path):
    p = tmp_path / "20261113_094012_345_17.jpg"
    p.write_bytes(jpeg())
    assert pilot.capture_time(p) == datetime(2026, 11, 13, 9, 40, 12, 345000)
    q = tmp_path / "IMG_0001.jpg"
    q.write_bytes(jpeg())
    assert pilot.capture_time(q) is None


def test_zips_from_two_phones_merge_into_the_pilot_layout(tmp_path):
    root = tmp_path / "field"
    a = app_zip(
        tmp_path / "a.zip",
        {
            "PM-A01/L/muzzle/20261113_090000_000_1.jpg": jpeg(100),
            "PM-A01/P0/muzzle/20261113_100000_000_2.jpg": jpeg(110),
        },
        "2026-11-13T09:40:00.000",
    )
    b = app_zip(
        tmp_path / "b.zip",
        {"PM-B01/L/face/20261113_110000_000_1.jpg": jpeg(130)},
        "2026-11-13T11:30:00.000",
        device="Phone B",
    )
    assert field_import.import_zip(a, root) == 2
    assert field_import.import_zip(b, root) == 1
    assert field_import.import_zip(a, root) == 0, "re-importing the same zip adds nothing"

    slaughter = pd.read_csv(root / "slaughter_times.csv")
    assert slaughter["identity"].tolist() == ["PM-A01", "PM-B01"]
    assert len(pd.read_csv(root / "field_animals.csv")) == 2
    df = pilot.scan(root)
    assert set(df["identity"]) == {"PM-A01", "PM-B01"}
    assert df.loc[df["stage"] == "P0", "captured_at"].item() == datetime(2026, 11, 13, 10)


def test_conflicting_slaughter_times_are_refused(tmp_path):
    root = tmp_path / "field"
    photo = {"PM-A01/L/muzzle/20261113_090000_000_1.jpg": jpeg()}
    field_import.import_zip(app_zip(tmp_path / "a.zip", photo, "2026-11-13T09:40"), root)
    with pytest.raises(ValueError, match="slaughter_time: 2026-11-13T09:40 vs 2026-11-13T09:55"):
        field_import.import_zip(app_zip(tmp_path / "b.zip", photo, "2026-11-13T09:55"), root)


def test_blank_values_merge_with_filled_ones(tmp_path):
    root = tmp_path / "field"
    field_import.merge_log(
        root, "field_animals.csv", pd.DataFrame([{"identity": "PM-A01", "device_model": "T"}])
    )
    field_import.merge_log(
        root,
        "field_animals.csv",
        pd.DataFrame([{"identity": "PM-A01", "device_model": "T", "collector": "leny"}]),
    )
    merged = pd.read_csv(root / "field_animals.csv", dtype=str)
    assert merged.to_dict("records") == [
        {"identity": "PM-A01", "device_model": "T", "collector": "leny"}
    ]


def test_camera_photos_are_sorted_with_labels_carried_down(tmp_path):
    photos, root = tmp_path / "roll", tmp_path / "field"
    photos.mkdir()
    times = ["09:00:00", "09:00:10", "09:00:20", "09:01:00", "10:00:00", "10:00:05"]
    for n, t in enumerate(times):
        (photos / f"IMG_{n:04d}.jpg").write_bytes(jpeg(100 + n, f"2026:11:13 {t}"))

    runs = field_import.write_runs_template(photos, photos / "runs.csv")
    assert runs["file"].tolist() == [f"IMG_{n:04d}.jpg" for n in range(6)]
    labels = [
        ("PM-A01", "L", "skip"),  # code card
        ("", "", "muzzle"),
        ("", "", ""),
        ("", "", "face"),
        ("", "P0", "skip"),
        ("", "", "muzzle"),
    ]
    runs[field_import.RUN_COLUMNS] = labels
    runs.to_csv(photos / "runs.csv", index=False)

    assert field_import.import_camera(photos, photos / "runs.csv", root) == 4
    df = pilot.scan(root)
    counts = df.groupby(["stage", "modality"]).size().to_dict()
    assert counts == {("L", "muzzle"): 2, ("L", "face"): 1, ("P0", "muzzle"): 1}

    field_import.contact_sheet(photos, tmp_path / "sheet.png")
    assert (tmp_path / "sheet.png").stat().st_size > 0


def test_camera_import_refuses_unlabelled_or_unknown_runs(tmp_path):
    photos = tmp_path / "roll"
    photos.mkdir()
    for n in range(2):
        (photos / f"IMG_{n}.jpg").write_bytes(jpeg())
    runs = field_import.write_runs_template(photos, photos / "runs.csv")
    runs[field_import.RUN_COLUMNS] = [("", "", ""), ("PM-A01", "L", "muzzle")]
    runs.to_csv(photos / "runs.csv", index=False)
    with pytest.raises(ValueError, match="first full label"):
        field_import.import_camera(photos, photos / "runs.csv", tmp_path / "f")

    runs[field_import.RUN_COLUMNS] = [("PM-A01", "alive", "muzzle"), ("", "", "")]
    runs.to_csv(photos / "runs.csv", index=False)
    with pytest.raises(ValueError, match="unknown stage"):
        field_import.import_camera(photos, photos / "runs.csv", tmp_path / "f")

    (photos / "IMG_9.HEIC").write_bytes(b"")
    with pytest.raises(ValueError, match="HEIC"):
        field_import.camera_photos(photos)
