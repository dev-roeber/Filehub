#!/usr/bin/env bash
# Idempotente Anlage von Paperless-Baseline-Daten via API.
# Liest Credentials aus .secrets/paperless.env (Mode 600).
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ -f .secrets/paperless.env ]]; then
  set -a; . .secrets/paperless.env; set +a
fi

: "${PAPERLESS_URL:=http://127.0.0.1:8000}"

if [[ -z "${PAPERLESS_TOKEN:-}" ]]; then
  if [[ -z "${PAPERLESS_USERNAME:-}" ]]; then
    read -r -p "Paperless Username: " PAPERLESS_USERNAME
  fi
  if [[ -z "${PAPERLESS_PASSWORD:-}" ]]; then
    read -r -s -p "Paperless Passwort: " PAPERLESS_PASSWORD; echo
  fi
fi

VENV=".venv-paperless"
if [[ ! -d "$VENV" ]]; then
  python3 -m venv "$VENV"
  "$VENV/bin/pip" install --quiet --upgrade pip
  "$VENV/bin/pip" install --quiet requests
fi

export PAPERLESS_URL PAPERLESS_USERNAME PAPERLESS_PASSWORD PAPERLESS_TOKEN
"$VENV/bin/python" scripts/setup_paperless_baseline.py
