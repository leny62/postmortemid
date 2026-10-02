"""Copy a few test-split images into ml/data/demo for the app demonstration.

Test animals were never used for training or threshold setting. The script
also writes one blurred copy and one small image so the quality check can be
shown rejecting them. These copies are demonstration props, not study data.

The Android photo picker shows thumbnails without file names, so each role
gets its own folder (shown as an album), and contact_sheet.png maps every
thumbnail to its name for the presenter.

    uv run python ml/scripts/export_demo_images.py
    adb push ml/data/demo/albums/. /sdcard/Pictures/
"""

import shutil

import pandas as pd
from PIL import Image, ImageDraw, ImageFilter, ImageOps

from postmortemid import paths

OUT = paths.DATA / "demo"
ALBUMS = OUT / "albums"
ANIMALS = 3
PER_ANIMAL = 5
THUMB = 220


def contact_sheet(albums: list[tuple[str, list[str]]]) -> Image.Image:
    cols = max(len(files) for _, files in albums)
    sheet = Image.new("RGB", (cols * (THUMB + 10) + 10, len(albums) * (THUMB + 60) + 10), "white")
    draw = ImageDraw.Draw(sheet)
    for r, (album, files) in enumerate(albums):
        top = 10 + r * (THUMB + 60)
        draw.text((10, top), album, fill="black")
        for c, name in enumerate(files):
            with Image.open(ALBUMS / album / name) as im:
                thumb = ImageOps.fit(im.convert("RGB"), (THUMB, THUMB))
            left = 10 + c * (THUMB + 10)
            sheet.paste(thumb, (left, top + 16))
            draw.text((left, top + 20 + THUMB), name, fill="black")
    return sheet


def main() -> None:
    images = pd.read_csv(paths.SPLITS / "e0_images.csv")
    test = pd.DataFrame(images[images["split"] == "test"])
    test["short_side"] = test[["width", "height"]].min(axis=1)
    usable = pd.DataFrame(test[test["short_side"] >= 256]).sort_values(
        ["identity", "frame", "file"]
    )
    counts = usable["identity"].value_counts(sort=False).sort_index()
    chosen = [str(i) for i in counts.index if counts[i] >= PER_ANIMAL][:ANIMALS]

    if OUT.exists():
        shutil.rmtree(OUT)
    albums: dict[str, list[str]] = {}

    def put(album: str, source, name: str) -> None:
        (ALBUMS / album).mkdir(parents=True, exist_ok=True)
        if isinstance(source, Image.Image):
            source.save(ALBUMS / album / name, quality=92)
        else:
            shutil.copy(source, ALBUMS / album / name)
        albums.setdefault(album, []).append(name)

    for n, identity in enumerate(chosen, start=1):
        rows = usable[usable["identity"] == identity].head(PER_ANIMAL)
        for i, path in enumerate(rows["path"]):
            role = "enrol" if i < 3 else "query"
            put(f"PMID-A{n}-{role}", paths.RAW / path, f"animal{n}_{role}{i + 1}_{identity}.jpg")

    sample = usable[usable["identity"] == chosen[0]].iloc[3]
    with Image.open(paths.RAW / sample["path"]) as im:
        put("PMID-quality", im.filter(ImageFilter.GaussianBlur(6)), "quality_blurred_copy.jpg")
    small = test[test["short_side"] < 160].iloc[0]
    put("PMID-quality", paths.RAW / small["path"], "quality_too_small.jpg")

    contact_sheet(sorted(albums.items())).save(OUT / "contact_sheet.png")
    total = sum(len(files) for files in albums.values())
    print(f"wrote {total} images to {ALBUMS.relative_to(paths.REPO)}")
    for album, files in sorted(albums.items()):
        print(f"  {album}: {', '.join(files)}")
    print(f"contact sheet: {(OUT / 'contact_sheet.png').relative_to(paths.REPO)}")


if __name__ == "__main__":
    main()
