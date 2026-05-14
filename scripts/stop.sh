#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
docker compose -f compose.yml -f compose.paperless.yml -f compose.convertx.yml -f compose.observability.yml down
