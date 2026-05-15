#!/usr/bin/env bash
# scripts/caddy-enable.sh
#
# Aktiviert ein Caddy-Snippet einer Filehub-App, indem die passende
# `apps/<app>/caddy*.disabled`-Datei nach
# `infra/caddy/snippets/enabled/<app>.caddy` KOPIERT wird (cp, kein symlink,
# damit Docker-Volume-Mounts nicht brechen).
#
# Usage:
#   scripts/caddy-enable.sh <app> [plain|authentik] [--force]
#
# Defaults: variant=plain
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

APPS_DIR="${REPO_ROOT}/apps"
ENABLED_DIR="${REPO_ROOT}/infra/caddy/snippets/enabled"

usage() {
    echo "Usage: scripts/caddy-enable.sh <app> [plain|authentik] [--force]" >&2
}

list_apps() {
    if [[ -d "${APPS_DIR}" ]]; then
        find "${APPS_DIR}" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort
    fi
}

if [[ $# -lt 1 ]]; then
    usage
    exit 1
fi

APP=""
VARIANT="plain"
FORCE=0

for arg in "$@"; do
    case "${arg}" in
        --force|-f)
            FORCE=1
            ;;
        plain|authentik)
            VARIANT="${arg}"
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            if [[ -z "${APP}" ]]; then
                APP="${arg}"
            else
                echo "ERROR: Unbekanntes Argument: ${arg}" >&2
                usage
                exit 1
            fi
            ;;
    esac
done

if [[ -z "${APP}" ]]; then
    echo "ERROR: <app> ist erforderlich." >&2
    usage
    exit 1
fi

APP_DIR="${APPS_DIR}/${APP}"
if [[ ! -d "${APP_DIR}" ]]; then
    echo "ERROR: App '${APP}' existiert nicht (${APP_DIR})." >&2
    echo "Verfuegbare Apps:" >&2
    list_apps | sed 's/^/  - /' >&2
    exit 2
fi

case "${VARIANT}" in
    plain)
        SRC="${APP_DIR}/caddy.disabled"
        ;;
    authentik)
        SRC="${APP_DIR}/caddy.authentik.disabled"
        ;;
esac

if [[ ! -f "${SRC}" ]]; then
    echo "ERROR: Snippet '${SRC}' nicht gefunden (variant=${VARIANT})." >&2
    exit 3
fi

mkdir -p "${ENABLED_DIR}"
DST="${ENABLED_DIR}/${APP}.caddy"

if [[ -e "${DST}" && "${FORCE}" -ne 1 ]]; then
    echo "ERROR: Ziel '${DST}' existiert bereits." >&2
    echo "Hinweis: scripts/caddy-enable.sh ${APP} ${VARIANT} --force zum Ueberschreiben." >&2
    exit 4
fi

cp "${SRC}" "${DST}"
echo "OK: ${SRC} -> ${DST} (variant=${VARIANT})"

# Optional: Caddy-Konfig validieren, ohne reload zu erzwingen.
GATEWAY_CFG="${REPO_ROOT}/config/caddy/filehub-gateway.Caddyfile"
if [[ -f "${GATEWAY_CFG}" ]]; then
    if command -v docker >/dev/null 2>&1 \
       && docker exec filehub-gateway caddy --help >/dev/null 2>&1; then
        echo "OK: filehub-gateway-Container gefunden, validiere Caddyfile ..."
        if docker exec filehub-gateway caddy validate \
                --config /etc/caddy/Caddyfile --adapter caddyfile; then
            echo "OK: caddy validate erfolgreich (kein reload ausgefuehrt)."
        else
            echo "WARN: caddy validate meldet Fehler (siehe oben)." >&2
        fi
    else
        echo "WARN: Container 'filehub-gateway' nicht erreichbar - Validierung uebersprungen."
    fi
else
    echo "WARN: ${GATEWAY_CFG} nicht vorhanden - Validierung uebersprungen."
fi

echo "OK: Snippet fuer '${APP}' aktiviert. Reload bei Bedarf manuell ausloesen."
