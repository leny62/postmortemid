"""Build the cleaned image table, duplicate-identity screen and identity-disjoint split for E0.

Run after downloading the dataset (see docs/dataset.md):
    uv run python ml/scripts/prepare_data.py
"""

import json

from postmortemid import paths
from postmortemid.prepare import prepare


def main() -> None:
    cfg = json.loads((paths.CONFIGS / "e0.json").read_text())
    p = prepare(cfg)
    print(f"scanned {len(p.raw)} images of {p.raw['identity'].nunique()} identities")
    print(f"dropped duplicate identities: {p.dropped_identities}")
    print(f"removed {len(p.distinct) - len(p.images)} within-animal near-duplicates")
    print(
        p.images.groupby("split").agg(identities=("identity", "nunique"), images=("file", "size"))
    )


if __name__ == "__main__":
    main()
