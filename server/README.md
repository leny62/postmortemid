# Field photo upload service

A small FastAPI service so phones can send field photos straight to the researcher. Each photo is sent once with its SHA-256 (a repeat upload is a no-op); the animal log is sent when it changes. The researcher downloads everything as one zip in the same layout as an app export:

```bash
curl -H "Authorization: Bearer $PMID_ADMIN_TOKEN" -o field.zip https://pmid.lenycodes.tech/v1/export.zip
uv run python ml/scripts/import_field.py zip field.zip
```

`GET /v1/summary` (admin token) lists photo counts per animal.

## Endpoints

| Method and path | Token | Purpose |
|---|---|---|
| `PUT /v1/photos/{identity}/{stage}/{modality}/{name}` | collector | One JPEG; headers `X-Sha256` and `X-Meta` (JSON photo log) |
| `PUT /v1/animals/{identity}` | collector | Animal log: link status, slaughter time, head washed, nose condition, notes |
| `GET /v1/summary` | admin | Photos per animal, stage and modality |
| `GET /v1/export.zip` | admin | Everything, for `import_field.py zip` |
| `GET /health` | none | Liveness |

Ear tags are never sent. Photos are stored under `/srv/pmid/data` on the server, readable by root and the service only.

## Deploy (Contabo VPS)

1. Add a DNS A record `pmid.lenycodes.tech` pointing to `194.163.133.79` (lenycodes.tech DNS is on Vercel).
2. On the VPS: clone the repo, `cd server`, `cp .env.example .env`, set the tokens, then `./deploy/deploy.sh`. It checks the port, starts the container on `127.0.0.1:18092`, adds the nginx site and gets a certificate.

## Development

```bash
cd server
uv sync
uv run pytest
uv run ruff check .
```
