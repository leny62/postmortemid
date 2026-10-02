"""Copy a few test-split images into ml/data/demo for the app demonstration.

Test animals were never used for training or threshold setting. The script
also writes one blurred copy and one small image so the quality check can be
shown rejecting them. These copies are demonstration props, not study data.

    uv run python ml/scripts/export_demo_images.py
    adb push ml/data/demo /sdcard/Pictures/PostMortemID-demo
"""

import shutil

import pandas as pd
from PIL import Image, ImageFilter

from postmortemid import paths

OUT = paths.DATA / "demo"
ANIMALS = 3
PER_ANIMAL = 5


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
    OUT.mkdir(parents=True)
    for n, identity in enumerate(chosen, start=1):
        for i, row in enumerate(
            usable[usable["identity"] == identity].head(PER_ANIMAL).itertuples()
        ):
            role = "enrol" if i < 3 else "query"
            shutil.copy(paths.RAW / row.path, OUT / f"animal{n}_{role}{i + 1}_{identity}.jpg")

    sample = usable[usable["identity"] == chosen[0]].iloc[3]
    with Image.open(paths.RAW / sample.path) as im:
        im.filter(ImageFilter.GaussianBlur(6)).save(OUT / "quality_blurred_copy.jpg", quality=92)
    small = test[test["short_side"] < 160].iloc[0]
    shutil.copy(paths.RAW / small.path, OUT / "quality_too_small.jpg")
    print(f"wrote {len(list(OUT.iterdir()))} files to {OUT.relative_to(paths.REPO)}")
    for p in sorted(OUT.iterdir()):
        print(" ", p.name)


if __name__ == "__main__":
    main()
