#!/usr/bin/env bash
# Healthcheck fuer convertx. Exit 0 = healthy, 1 = unhealthy.
set -euo pipefail
container="filehub-convertx"
url="http://127.0.0.1:3000/"

if ! docker inspect "$container" >/dev/null 2>&1; then
  echo "FAIL: container $container nicht vorhanden"; exit 1
fi
state="$(docker inspect -f '{{.State.Health.Status}}' "$container" 2>/dev/null || echo none)"
http="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 5 "$url" || echo 000)"
echo "container=$container state=$state http=$http url=$url"
case "$state" in
  healthy) ;;
  none|"<no value>") [[ "$http" =~ ^(2|3) ]] || { echo "FAIL"; exit 1; } ;;
  *) echo "FAIL"; exit 1 ;;
esac
