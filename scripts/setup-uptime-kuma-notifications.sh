#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

VENV="${VENV:-.venv-uptime-kuma}"
KUMA_SECRETS="${UPTIME_KUMA_SECRETS:-.secrets/uptime-kuma.env}"
NTFY_SECRETS="${NTFY_SECRETS:-.secrets/ntfy.env}"

if [[ ! -x "$VENV/bin/python" ]]; then
  echo "Erzeuge venv unter $VENV ..."
  python3 -m venv "$VENV"
  "$VENV/bin/pip" install --quiet uptime-kuma-api
fi

if [[ -f "$KUMA_SECRETS" ]]; then
  # shellcheck disable=SC1090
  set -a; source "$KUMA_SECRETS"; set +a
fi

if [[ -f "$NTFY_SECRETS" ]]; then
  # shellcheck disable=SC1090
  set -a; source "$NTFY_SECRETS"; set +a
fi

UPTIME_KUMA_URL="${UPTIME_KUMA_URL:-http://127.0.0.1:3002}"

if [[ -z "${UPTIME_KUMA_USER:-}" ]]; then
  read -rp "Uptime Kuma Username: " UPTIME_KUMA_USER
fi
if [[ -z "${UPTIME_KUMA_PASSWORD:-}" ]]; then
  read -rsp "Uptime Kuma Passwort: " UPTIME_KUMA_PASSWORD
  echo
fi

if [[ -z "${NTFY_SERVER_URL:-}" || -z "${NTFY_TOPIC:-}" ]]; then
  echo "ERROR: NTFY_SERVER_URL und NTFY_TOPIC muessen in $NTFY_SECRETS gesetzt sein." >&2
  exit 2
fi

# Default-Priority Mapping: ntfy nutzt Strings, Uptime Kuma int 1..5.
case "${NTFY_PRIORITY_DEFAULT:-default}" in
  min)     export NTFY_PRIORITY=1 ;;
  low)     export NTFY_PRIORITY=2 ;;
  default) export NTFY_PRIORITY=3 ;;
  high)    export NTFY_PRIORITY=4 ;;
  max|urgent) export NTFY_PRIORITY=5 ;;
  *)       export NTFY_PRIORITY=3 ;;
esac

export UPTIME_KUMA_URL UPTIME_KUMA_USER UPTIME_KUMA_PASSWORD
export NTFY_SERVER_URL NTFY_TOPIC

RUN_TEST="${RUN_TEST:-0}" exec "$VENV/bin/python" scripts/setup_uptime_kuma_notifications.py
