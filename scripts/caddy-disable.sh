#!/usr/bin/env bash
# scripts/caddy-disable.sh
#
# Deaktiviert ein zuvor mit scripts/caddy-enable.sh kopiertes Snippet,
# indem die Datei `infra/caddy/snippets/enabled/<app>.caddy` entfernt wird.
# Idempotent: exit 0 auch wenn die Datei nicht existiert.
#
# Usage:
#   scripts/caddy-disable.sh <app>
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENABLED_DIR="${REPO_ROOT}/infra/caddy/snippets/enabled"

if [[ $# -lt 1 ]]; then
    echo "Usage: scripts/caddy-disable.sh <app>" >&2
    exit 1
fi

APP="$1"
DST="${ENABLED_DIR}/${APP}.caddy"

if [[ -f "${DST}" ]]; then
    rm -f "${DST}"
    echo "OK: ${DST} entfernt."
else
    echo "WARN: ${DST} existierte nicht - nichts zu tun (idempotent)."
fi

exit 0
