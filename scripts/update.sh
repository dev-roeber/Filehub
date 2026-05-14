#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

echo "Starte sicheres Update: pull, up -d, danach Status."
docker compose -f compose.yml -f compose.paperless.yml -f compose.convertx.yml -f compose.observability.yml pull
docker compose -f compose.yml -f compose.paperless.yml -f compose.convertx.yml -f compose.observability.yml up -d
docker compose -f compose.yml -f compose.paperless.yml -f compose.convertx.yml -f compose.observability.yml ps

if [[ "${PRUNE_OLD_IMAGES:-false}" == "true" ]]; then
  echo "PRUNE_OLD_IMAGES=true gesetzt. Entferne ungenutzte Images."
  docker image prune -f
else
  echo "Ungenutzte Images wurden nicht entfernt. Setze PRUNE_OLD_IMAGES=true für automatisches Prune."
fi
