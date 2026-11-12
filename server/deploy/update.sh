#!/usr/bin/env bash
# Brings the upload server up to date with origin/main. Installed once as
# /usr/local/bin/pmid-deploy and run by the CI deploy key (forced command).
set -euo pipefail

cd /opt/postmortemid
git fetch --quiet origin main
git merge --ff-only --quiet origin/main
cd server
docker compose up -d --build --quiet-pull

for _ in $(seq 1 30); do
  if curl -fsS http://127.0.0.1:18092/health >/dev/null; then
    echo "deployed $(git rev-parse --short HEAD)"
    exit 0
  fi
  sleep 2
done
echo "health check failed" >&2
docker compose logs --tail 50 >&2
exit 1
