"""Bring field photos into the pilot layout read by pilot.scan.

Two sources: zips exported by the app's field collection mode (one per phone),
and camera-roll photos sorted with a runs file that the researcher fills in.
"""

import zipfile
from pathlib import Path, PurePosixPath

import pandas as pd
from PIL import Image, ImageDraw, ImageOps

from postmortemid.pilot import IMAGE_SUFFIXES, MODALITIES, STAGES, capture_time

# Logs merged across phones, with the columns that identify a row.
FIELD_LOGS = {
    "slaughter_times.csv": ["identity"],
    "field_animals.csv": ["identity", "device_model"],
    "field_images.csv": ["file"],
}
RUN_COLUMNS = ["identity", "stage", "modality"]
SKIP = "skip"


def _place(data: bytes, target: Path) -> bool:
    """Writes data to target; False if an identical file is already there."""
    if target.exists():
        if target.read_bytes() == data:
            return False
        raise FileExistsError(f"{target} already exists with different content")
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(data)
    return True


def merge_log(root: Path, name: str, new: pd.DataFrame) -> None:
    """Adds rows to a log under root, combining rows with the same key.

    Blank values never conflict, so a phone's zip and its server upload merge
    cleanly. Two different non-blank values for one key are refused.
    """
    key = FIELD_LOGS[name]
    path = root / name
    frames = [new.astype(str)]
    if path.exists():
        frames.insert(0, pd.read_csv(path, dtype=str, keep_default_na=False))
    merged = pd.concat(frames).fillna("")
    rows, clashes = [], []
    for ident, group in merged.groupby(key, sort=True):
        row = {}
        for column in merged.columns:
            values = sorted({v for v in group[column] if v != ""})
            if len(values) > 1:
                clashes.append(f"{'/'.join(map(str, ident))} {column}: {' vs '.join(values)}")
            row[column] = values[0] if values else ""
        rows.append(row)
    if clashes:
        raise ValueError(
            f"{name} disagrees with what is already imported ({'; '.join(clashes)}). "
            f"Correct the log on the phone, or edit {path}, then import again."
        )
    root.mkdir(parents=True, exist_ok=True)
    pd.DataFrame(rows, columns=merged.columns).to_csv(path, index=False)


def import_zip(zip_path: Path, root: Path) -> int:
    """Extracts one app export into root and merges its logs. Returns new photos."""
    added = 0
    with zipfile.ZipFile(zip_path) as z:
        for info in z.infolist():
            name = PurePosixPath(info.filename)
            if info.is_dir() or ".." in name.parts or name.is_absolute():
                continue
            if name.name in FIELD_LOGS and len(name.parts) == 1:
                with z.open(info) as f:
                    merge_log(root, name.name, pd.read_csv(f, dtype=str, keep_default_na=False))
            elif name.suffix.lower() in IMAGE_SUFFIXES and len(name.parts) == 4:
                added += _place(z.read(info), root.joinpath(*name.parts))
    return added


def camera_photos(photo_dir: Path) -> pd.DataFrame:
    """Camera-roll photos ordered by capture time, then name."""
    heic = [p.name for p in photo_dir.iterdir() if p.suffix.lower() in {".heic", ".heif"}]
    if heic:
        raise ValueError(f"{len(heic)} HEIC photos (e.g. {heic[0]}): export them as JPEG first")
    files = [p for p in photo_dir.iterdir() if p.suffix.lower() in IMAGE_SUFFIXES]
    if not files:
        raise ValueError(f"no photos in {photo_dir}")
    df = pd.DataFrame({"file": [p.name for p in files], "captured_at": map(capture_time, files)})
    return df.sort_values(["captured_at", "file"], kind="stable").reset_index(drop=True)


def write_runs_template(photo_dir: Path, out: Path) -> pd.DataFrame:
    """One row per photo; the researcher fills identity, stage and modality where a run starts."""
    df = camera_photos(photo_dir)
    for c in RUN_COLUMNS:
        df[c] = ""
    df.to_csv(out, index=False)
    return df


def contact_sheet(photo_dir: Path, out: Path, per_row: int = 6, thumb: int = 220) -> None:
    """Thumbnails in capture order, labelled with their spreadsheet row in the runs file."""
    df = camera_photos(photo_dir)
    rows = -(-len(df) // per_row)
    label = 34
    sheet = Image.new("RGB", (per_row * thumb, rows * (thumb + label)), "white")
    draw = ImageDraw.Draw(sheet)
    for i, (name, taken) in enumerate(zip(df["file"], df["captured_at"], strict=True)):
        x, y = (i % per_row) * thumb, (i // per_row) * (thumb + label)
        with Image.open(photo_dir / name) as im:
            small = ImageOps.exif_transpose(im).convert("RGB")
            small.thumbnail((thumb - 8, thumb - 8))
        sheet.paste(small, (x + 4, y + 4))
        when = "?" if bool(pd.isna(taken)) else taken.strftime("%H:%M:%S")
        draw.text((x + 4, y + thumb), f"row {i + 2}  {name[:16]}  {when}", fill="black")
    sheet.save(out)


def import_camera(photo_dir: Path, runs_csv: Path, root: Path) -> int:
    """Copies camera photos into root using a filled runs file. Returns new photos.

    Each column carries down until the next filled value, so only the first
    photo of a run needs a label. Modality "skip" drops photos such as code cards.
    """
    runs = pd.read_csv(runs_csv, dtype=str, keep_default_na=False)
    runs[RUN_COLUMNS] = runs[RUN_COLUMNS].replace("", pd.NA).ffill()
    unlabelled = runs[runs[RUN_COLUMNS].isna().any(axis=1)]
    if not unlabelled.empty:
        raise ValueError(f"photos before the first full label: {unlabelled['file'].tolist()[:5]}")
    keep = runs[runs["modality"] != SKIP]
    bad = keep[~keep["stage"].isin(STAGES) | ~keep["modality"].isin(MODALITIES)]
    if not bad.empty:
        raise ValueError(f"unknown stage or modality on {bad['file'].tolist()[:5]}")
    added = 0
    for identity, stage, modality, name in keep[[*RUN_COLUMNS, "file"]].itertuples(index=False):
        target = root / str(identity) / str(stage) / str(modality) / str(name)
        added += _place((photo_dir / str(name)).read_bytes(), target)
    return added
