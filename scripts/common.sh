#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_CORE=(-f compose.yml -f compose.paperless.yml -f compose.convertx.yml)
COMPOSE_OBS=(-f compose.yml -f compose.paperless.yml -f compose.convertx.yml -f compose.observability.yml)
COMPOSE_ALL=(-f compose.yml -f compose.paperless.yml -f compose.convertx.yml -f compose.observability.yml)

cd_root() {
  cd "$PROJECT_ROOT"
}

require_root_dir() {
  if [[ ! -f compose.yml || ! -d scripts ]]; then
    echo "ERROR: Dieses Script muss aus dem Filehub-Projektroot laufen." >&2
    exit 1
  fi
}

load_env() {
  if [[ -f .env ]]; then
    set -a
    # shellcheck disable=SC1091
    source .env
    set +a
  fi
}

compose_core() {
  docker compose "${COMPOSE_CORE[@]}" "$@"
}

compose_all() {
  docker compose "${COMPOSE_ALL[@]}" "$@"
}

port_free() {
  local port="$1"
  ! ss -ltn "( sport = :$port )" | awk 'NR > 1 {found=1} END {exit found ? 0 : 1}'
}

random_secret() {
  openssl rand -base64 48 | tr -d '\n'
}
