"""Field photo upload service.

Phones send each photo once (idempotent PUT keyed by path and SHA-256) and the
animal log when it changes. The researcher downloads everything as one zip in
the layout ml/scripts/import_field.py reads, the same as an app export.
"""

import csv
import hashlib
import io
import json
import os
import re
import secrets
import tempfile
import zipfile
from pathlib import Path
from typing import Annotated

from fastapi import BackgroundTasks, Depends, FastAPI, Header, HTTPException, Request
from fastapi.responses import FileResponse
from pydantic import BaseModel

IDENTITY = re.compile(r"^PM-[A-Z0-9]{2,8}$")
STAGES = {"L", "P0", "P1"}
MODALITIES = {"muzzle", "face"}
PHOTO_NAME = re.compile(r"^[A-Za-z0-9_-]{1,80}\.jpe?g$")
MAX_PHOTO_BYTES = 30 * 1024 * 1024
IMAGE_COLUMNS = [
    "file",
    "identity",
    "stage",
    "modality",
    "burst",
    "captured_at",
    "quality_passed",
    "quality_issues",
    "width",
    "height",
    "brightness",
    "sharpness",
    "device_model",
    "collector",
]
ANIMAL_COLUMNS = [
    "identity",
    "linkage_status",
    "slaughter_time",
    "head_washed",
    "nose_condition",
    "notes",
    "device_model",
    "collector",
]


class AnimalLog(BaseModel):
    linkage_status: str
    slaughter_time: str | None = None
    head_washed: str | None = None
    nose_condition: str | None = None
    notes: str | None = None
    device_model: str


def parse_tokens(raw: str) -> dict[str, str]:
    """ "alice:tok1,bob:tok2" to {token: collector}."""
    pairs = [p.split(":", 1) for p in raw.split(",") if p.strip()]
    return {token.strip(): name.strip() for name, token in pairs}


def create_app(data_dir: Path, tokens: dict[str, str], admin_token: str) -> FastAPI:
    app = FastAPI(title="PostMortemID upload", docs_url=None, redoc_url=None)
    photos_dir, logs_dir = data_dir / "field", data_dir / "logs"

    def bearer(authorization: Annotated[str | None, Header()] = None) -> str:
        scheme, _, token = (authorization or "").partition(" ")
        if scheme.lower() != "bearer" or not token:
            raise HTTPException(401, "missing token")
        return token

    def collector(token: Annotated[str, Depends(bearer)]) -> str:
        for known, name in tokens.items():
            if secrets.compare_digest(token, known):
                return name
        raise HTTPException(401, "unknown token")

    def admin(token: Annotated[str, Depends(bearer)]) -> None:
        if not admin_token or not secrets.compare_digest(token, admin_token):
            raise HTTPException(401, "admin token required")

    def check_identity(identity: str) -> None:
        if not IDENTITY.match(identity):
            raise HTTPException(422, "identity must look like PM-A01")

    @app.get("/health")
    def health() -> dict[str, bool]:
        return {"ok": True}

    @app.put("/v1/photos/{identity}/{stage}/{modality}/{name}")
    async def put_photo(
        identity: str,
        stage: str,
        modality: str,
        name: str,
        request: Request,
        who: Annotated[str, Depends(collector)],
        x_sha256: Annotated[str, Header()],
        x_meta: Annotated[str, Header()] = "{}",
    ) -> dict[str, str]:
        check_identity(identity)
        if stage not in STAGES or modality not in MODALITIES or not PHOTO_NAME.match(name):
            raise HTTPException(422, "unknown stage, modality or file name")
        body = await request.body()
        if not body or len(body) > MAX_PHOTO_BYTES:
            raise HTTPException(413, "photo is empty or too large")
        digest = hashlib.sha256(body).hexdigest()
        if digest != x_sha256.lower():
            raise HTTPException(400, "checksum mismatch, upload again")

        target = photos_dir / identity / stage / modality / name
        if target.exists():
            if hashlib.sha256(target.read_bytes()).hexdigest() == digest:
                return {"status": "exists"}
            raise HTTPException(409, "a different photo already has this name")
        try:
            meta = json.loads(x_meta)
        except json.JSONDecodeError as e:
            raise HTTPException(422, "X-Meta must be JSON") from e

        target.parent.mkdir(parents=True, exist_ok=True)
        partial = target.with_suffix(".part")
        partial.write_bytes(body)
        partial.replace(target)
        row = {c: meta.get(c, "") for c in IMAGE_COLUMNS}
        row |= {
            "file": f"{identity}/{stage}/{modality}/{name}",
            "identity": identity,
            "stage": stage,
            "modality": modality,
            "collector": who,
        }
        logs_dir.mkdir(parents=True, exist_ok=True)
        with (logs_dir / "images.jsonl").open("a") as f:
            f.write(json.dumps(row) + "\n")
        return {"status": "stored"}

    @app.put("/v1/animals/{identity}")
    def put_animal(
        identity: str, log: AnimalLog, who: Annotated[str, Depends(collector)]
    ) -> dict[str, str]:
        check_identity(identity)
        animals = logs_dir / "animals"
        animals.mkdir(parents=True, exist_ok=True)
        row = log.model_dump() | {"identity": identity, "collector": who}
        (animals / f"{identity}__{who}.json").write_text(json.dumps(row))
        return {"status": "stored"}

    def image_rows() -> list[dict[str, str]]:
        path = logs_dir / "images.jsonl"
        if not path.exists():
            return []
        rows = [json.loads(line) for line in path.read_text().splitlines() if line]
        return list({r["file"]: r for r in rows}.values())

    def animal_rows() -> list[dict[str, str]]:
        animals = logs_dir / "animals"
        files = sorted(animals.glob("*.json")) if animals.exists() else []
        return [json.loads(p.read_text()) for p in files]

    @app.get("/v1/summary", dependencies=[Depends(admin)])
    def summary() -> dict[str, dict[str, int]]:
        out: dict[str, dict[str, int]] = {}
        for r in image_rows():
            key = f"{r['stage']}/{r['modality']}"
            out.setdefault(r["identity"], {})[key] = out.get(r["identity"], {}).get(key, 0) + 1
        return dict(sorted(out.items()))

    @app.get("/v1/export.zip", dependencies=[Depends(admin)])
    def export(background: BackgroundTasks) -> FileResponse:
        animals = animal_rows()
        slaughter = [
            {"identity": a["identity"], "slaughter_time": a["slaughter_time"]}
            for a in animals
            if a.get("slaughter_time")
        ]
        texts = {
            "slaughter_times.csv": _csv(["identity", "slaughter_time"], slaughter),
            "field_animals.csv": _csv(ANIMAL_COLUMNS, animals),
            "field_images.csv": _csv(IMAGE_COLUMNS, image_rows()),
        }
        handle, path = tempfile.mkstemp(suffix=".zip")
        os.close(handle)
        with zipfile.ZipFile(path, "w", zipfile.ZIP_STORED) as z:
            for photo in sorted(photos_dir.glob("*/*/*/*.jp*g")):
                z.write(photo, photo.relative_to(photos_dir).as_posix())
            for name, text in texts.items():
                z.writestr(name, text)
        background.add_task(os.remove, path)
        return FileResponse(path, media_type="application/zip", filename="pmid_field_server.zip")

    return app


def _csv(columns: list[str], rows: list[dict[str, str]]) -> str:
    out = io.StringIO()
    writer = csv.DictWriter(out, columns, extrasaction="ignore", lineterminator="\n")
    writer.writeheader()
    writer.writerows(rows)
    return out.getvalue()


def app_from_env() -> FastAPI:
    return create_app(
        Path(os.environ.get("PMID_DATA_DIR", "/data")),
        parse_tokens(os.environ.get("PMID_TOKENS", "")),
        os.environ.get("PMID_ADMIN_TOKEN", ""),
    )
