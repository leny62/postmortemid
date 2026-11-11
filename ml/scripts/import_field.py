"""Bring abattoir photos into ml/data/field for run_pilot.py.

From the app (one zip per phone; logs are merged):
    uv run python ml/scripts/import_field.py zip pmid_field_*.zip

From a camera roll (photos exported as JPEG originals, not sent by WhatsApp):
    uv run python ml/scripts/import_field.py sheet <photo_dir>
        writes runs.csv and contact_sheet.png next to the photos; in runs.csv fill
        identity, stage (L or P0) and modality (muzzle, face or skip) on the first
        photo of each run, then:
    uv run python ml/scripts/import_field.py camera <photo_dir> [--runs runs.csv]
    Write slaughter_times.csv (identity,slaughter_time) in ml/data/field by hand from the log.
"""

import argparse
from pathlib import Path

from postmortemid import field_import, paths


def main() -> None:
    parser = argparse.ArgumentParser(description="Bring abattoir photos into ml/data/field.")
    parser.add_argument("--root", type=Path, default=paths.FIELD)
    sub = parser.add_subparsers(dest="command", required=True)
    z = sub.add_parser("zip", help="import app exports")
    z.add_argument("zips", type=Path, nargs="+")
    s = sub.add_parser("sheet", help="write runs.csv and a contact sheet for camera photos")
    s.add_argument("photos", type=Path)
    c = sub.add_parser("camera", help="import camera photos with a filled runs.csv")
    c.add_argument("photos", type=Path)
    c.add_argument("--runs", type=Path)
    args = parser.parse_args()

    if args.command == "zip":
        for path in args.zips:
            n = field_import.import_zip(path, args.root)
            print(f"{path.name}: {n} new photos")
    elif args.command == "sheet":
        runs, sheet = args.photos / "runs.csv", args.photos / "contact_sheet.png"
        if runs.exists():
            raise SystemExit(f"{runs} exists; delete it to start again")
        n = len(field_import.write_runs_template(args.photos, runs))
        field_import.contact_sheet(args.photos, sheet)
        print(f"{n} photos: fill {runs}, using {sheet}")
    else:
        runs = args.runs or args.photos / "runs.csv"
        n = field_import.import_camera(args.photos, runs, args.root)
        print(f"{n} new photos in {args.root}")


if __name__ == "__main__":
    main()
