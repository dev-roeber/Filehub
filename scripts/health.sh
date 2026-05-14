#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

if [[ -f .env ]]; then
  # shellcheck disable=SC1091
  set -a; source .env; set +a
fi

docker compose -f compose.yml -f compose.paperless.yml -f compose.convertx.yml -f compose.observability.yml ps

check_http() {
  local name="$1"
  local url="$2"
  if curl -fsS --max-time 10 "$url" >/dev/null; then
    echo "OK: $name $url"
  else
    echo "WARN: $name nicht erreichbar: $url"
  fi
}

check_http "Paperless" "http://127.0.0.1:${PAPERLESS_PORT:-8000}/"
check_http "ConvertX" "http://127.0.0.1:${CONVERTX_PORT:-3000}/"
check_http "Homepage" "http://127.0.0.1:${HOMEPAGE_PORT:-3001}/"
check_http "Dozzle" "http://127.0.0.1:${DOZZLE_PORT:-9999}/"
check_http "Uptime Kuma" "http://127.0.0.1:${UPTIME_KUMA_PORT:-3002}/"

for svc in filehub-paperless-db filehub-paperless-redis; do
  if docker inspect -f '{{.State.Running}}' "$svc" 2>/dev/null | grep -q true; then
    echo "OK: $svc läuft."
  else
    echo "WARN: $svc läuft nicht."
  fi
done
