#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

if [[ ! -f .env.example ]]; then
  echo "ERROR: .env.example fehlt." >&2
  exit 1
fi

if [[ -f .env ]]; then
  echo ".env existiert bereits. Es wird nichts überschrieben."
  exit 0
fi

uid_value="$(id -u)"
gid_value="$(id -g)"
paperless_secret="$(openssl rand -base64 48 | tr -d '\n')"
paperless_admin_password="$(openssl rand -base64 24 | tr -d '\n')"
db_password="$(openssl rand -base64 32 | tr -d '\n')"
convertx_secret="$(openssl rand -base64 48 | tr -d '\n')"

cp .env.example .env
chmod 600 .env

sed -i \
  -e "s/^PUID=.*/PUID=${uid_value}/" \
  -e "s/^PGID=.*/PGID=${gid_value}/" \
  -e "s#^PAPERLESS_SECRET_KEY=.*#PAPERLESS_SECRET_KEY=${paperless_secret}#" \
  -e "s#^PAPERLESS_ADMIN_PASSWORD=.*#PAPERLESS_ADMIN_PASSWORD=${paperless_admin_password}#" \
  -e "s#^PAPERLESS_DBPASS=.*#PAPERLESS_DBPASS=${db_password}#" \
  -e "s#^POSTGRES_PASSWORD=.*#POSTGRES_PASSWORD=${db_password}#" \
  -e "s#^CONVERTX_JWT_SECRET=.*#CONVERTX_JWT_SECRET=${convertx_secret}#" \
  .env

mkdir -p data/paperless/{consume,data,media,export} data/postgres data/redis data/convertx data/uptime-kuma data/homepage backups

echo ".env wurde erzeugt und mit chmod 600 geschützt."
echo "Secrets stehen nur in .env und werden nicht ausgegeben."
