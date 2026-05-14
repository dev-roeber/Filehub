#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

GREEN='\033[0;32m'; RED='\033[0;31m'; NC='\033[0m'
ok()   { echo -e "${GREEN}OK${NC}: $*"; }
fail() { echo -e "${RED}FAIL${NC}: $*"; FAILED=1; }
FAILED=0

# HTTP
code=$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:3000/)
if [[ "$code" =~ ^(200|301|302)$ ]]; then ok "HTTP $code"; else fail "HTTP $code"; fi

# Healthy
status=$(docker inspect -f '{{.State.Health.Status}}' filehub-convertx 2>/dev/null || echo unknown)
if [[ "$status" == "healthy" ]]; then ok "Container healthy"; else fail "Container Status: $status"; fi

# Logs
errs=$(docker logs --tail 100 filehub-convertx 2>&1 | grep -ciE 'error|fatal|panic' || true)
if [[ "$errs" -le 1 ]]; then ok "Keine auffaelligen Errors in Logs (count=$errs)"
else fail "Errors in Logs: $errs"; fi

# Registrierung deaktiviert
reg=$(grep -E '^ACCOUNT_REGISTRATION=' .env | cut -d= -f2)
if [[ "$reg" == "false" ]]; then ok "ACCOUNT_REGISTRATION=false"
else fail "ACCOUNT_REGISTRATION=$reg (sollte false sein nach Initial-Setup)"; fi

# JWT Secret nicht Default
sec=$(grep -E '^CONVERTX_JWT_SECRET=' .env | cut -d= -f2)
if [[ "$sec" == "change-me-generate-random" || -z "$sec" ]]; then
  fail "CONVERTX_JWT_SECRET ist Default/leer"
else ok "CONVERTX_JWT_SECRET gesetzt (Wert nicht ausgegeben)"; fi

echo
if [[ "$FAILED" == "1" ]]; then echo -e "${RED}ConvertX Smoke-Test: Fehler.${NC}"; exit 1
else echo -e "${GREEN}ConvertX Smoke-Test: OK.${NC}"; fi
