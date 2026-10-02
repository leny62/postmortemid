"""Download the public muzzle database from Zenodo, check its hash and unpack it.

    uv run python ml/scripts/download_dataset.py

The archive is about 644 MB. Images are licensed CC BY 4.0 (Xiong, Li and
Erickson, 2022) and are kept out of version control.
"""

import hashlib
import urllib.request
import zipfile

from postmortemid import dataset, paths

ARCHIVE = paths.RAW / "BeefCattle_Muzzle_database.zip"


def sha256(path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def main() -> None:
    paths.RAW.mkdir(parents=True, exist_ok=True)
    if (paths.RAW / dataset.IMAGE_DIR).exists():
        print("dataset already unpacked")
        return
    if not ARCHIVE.exists():
        print(f"downloading {dataset.ZENODO_URL}")
        urllib.request.urlretrieve(dataset.ZENODO_URL, ARCHIVE)
    digest = sha256(ARCHIVE)
    if digest != dataset.ARCHIVE_SHA256:
        raise SystemExit(f"hash mismatch: {digest}. Delete {ARCHIVE} and try again.")
    with zipfile.ZipFile(ARCHIVE) as z:
        z.extractall(paths.RAW)
    print(f"unpacked to {paths.RAW / dataset.IMAGE_DIR}")


if __name__ == "__main__":
    main()
