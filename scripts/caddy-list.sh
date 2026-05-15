#!/usr/bin/env bash
# scripts/caddy-list.sh
#
# Listet alle aktivierten Caddy-Snippets unter
# `infra/caddy/snippets/enabled/` (ohne .gitkeep).
# Ausgabeformat pro Zeile: <appname> (basename ohne .caddy-Suffix).
#
# Wenn das Verzeichnis fehlt, wird es angelegt.
# Wenn keine Snippets aktiv sind: stdout "(keine aktivierten Snippets)".
#
# Usage:
#   scripts/caddy-list.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENABLED_DIR="${REPO_ROOT}/infra/caddy/snippets/enabled"

# Verzeichnis sicherstellen (idempotent).
mkdir -p "${ENABLED_DIR}"

# Eintraege einsammeln (alles ausser .gitkeep).
ENTRIES=()
while IFS= read -r -d '' f; do
    base="$(basename "${f}")"
    if [[ "${base}" == ".gitkeep" ]]; then
        continue
    fi
    # .caddy-Suffix entfernen, falls vorhanden.
    name="${base%.caddy}"
    ENTRIES+=("${name}")
done < <(find "${ENABLED_DIR}" -mindepth 1 -maxdepth 1 -type f -print0 2>/dev/null)

if [[ ${#ENTRIES[@]} -eq 0 ]]; then
    echo "(keine aktivierten Snippets)"
    exit 0
fi

printf '%s\n' "${ENTRIES[@]}" | sort
exit 0
