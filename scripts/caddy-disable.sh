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

# Falls das enabled/-Verzeichnis fehlt: anlegen und mit WARN beenden.
if [[ ! -d "${ENABLED_DIR}" ]]; then
    mkdir -p "${ENABLED_DIR}"
    echo "WARN: ${ENABLED_DIR} existierte nicht - angelegt, nichts zu deaktivieren."
    exit 0
fi

DST="${ENABLED_DIR}/${APP}.caddy"

if [[ ! -e "${DST}" && ! -L "${DST}" ]]; then
    echo "WARN: ${DST} existierte nicht - nichts zu tun (idempotent)."
    exit 0
fi

# Sicherheits-Check: niemals einem Symlink folgen, der ausserhalb von
# enabled/ zeigt - sonst koennte man versehentlich die Original-Snippets
# unter apps/<app>/caddy*.disabled loeschen.
if [[ -L "${DST}" ]]; then
    TARGET_REAL="$(realpath -m "${DST}")"
    ENABLED_REAL="$(realpath -m "${ENABLED_DIR}")"
    # TARGET_REAL muss mit ENABLED_REAL/ beginnen (oder genau gleich sein).
    case "${TARGET_REAL}" in
        "${ENABLED_REAL}"/*)
            : # ok, liegt unter enabled/
            ;;
        *)
            echo "ERROR: ${DST} ist ein Symlink, der ausserhalb von ${ENABLED_REAL} zeigt (-> ${TARGET_REAL})." >&2
            echo "ERROR: Aus Sicherheitsgruenden wird dieser Link NICHT entfernt." >&2
            exit 5
            ;;
    esac
fi

rm -f "${DST}"
echo "OK: ${DST} entfernt."

exit 0
