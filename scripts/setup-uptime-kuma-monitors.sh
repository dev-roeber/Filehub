#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

VENV="${VENV:-.venv-uptime-kuma}"
SECRETS_FILE="${UPTIME_KUMA_SECRETS:-.secrets/uptime-kuma.env}"

if [[ ! -x "$VENV/bin/python" ]]; then
  echo "Erzeuge venv unter $VENV ..."
  python3 -m venv "$VENV"
  "$VENV/bin/pip" install --quiet uptime-kuma-api
fi

if [[ -f "$SECRETS_FILE" ]]; then
  # shellcheck disable=SC1090
  set -a; source "$SECRETS_FILE"; set +a
fi

UPTIME_KUMA_URL="${UPTIME_KUMA_URL:-http://127.0.0.1:3002}"

if [[ -z "${UPTIME_KUMA_USER:-}" ]]; then
  read -rp "Uptime Kuma Username: " UPTIME_KUMA_USER
fi
if [[ -z "${UPTIME_KUMA_PASSWORD:-}" ]]; then
  read -rsp "Uptime Kuma Passwort: " UPTIME_KUMA_PASSWORD
  echo
fi

export UPTIME_KUMA_URL UPTIME_KUMA_USER UPTIME_KUMA_PASSWORD

exec "$VENV/bin/python" scripts/setup_uptime_kuma_monitors.py
