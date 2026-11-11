#!/usr/bin/env bash
# Run on the VPS as root from the server/ folder of the repo.
set -euo pipefail

if ss -tlnp | grep -q ':18092 '; then
  echo "port 18092 is already in use; pick another in compose.yaml and the nginx config" >&2
  exit 1
fi
[ -f .env ] || { echo "copy .env.example to .env and set the tokens first" >&2; exit 1; }

mkdir -p /srv/pmid/data
chown 1000:1000 /srv/pmid/data
chmod 700 /srv/pmid/data
docker compose up -d --build

cp deploy/pmid.lenycodes.tech.conf /etc/nginx/sites-available/pmid.lenycodes.tech
ln -sf /etc/nginx/sites-available/pmid.lenycodes.tech /etc/nginx/sites-enabled/pmid.lenycodes.tech
nginx -t
systemctl reload nginx
certbot --nginx -d pmid.lenycodes.tech
curl -fsS https://pmid.lenycodes.tech/health && echo
