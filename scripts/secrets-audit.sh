#!/usr/bin/env bash
# Inventarisiert und prueft Secret-Dateien.
# Gibt KEINE Secret-Werte aus. Nur Existenz, Modus, Variablennamen.
set -euo pipefail
cd "$(dirname "$0")/.."

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'
ok()   { echo -e "${GREEN}OK${NC}: $*"; }
fail() { echo -e "${RED}FAIL${NC}: $*"; FAILED=1; }
warn() { echo -e "${YELLOW}WARN${NC}: $*"; }

FAILED=0

# .env
if [[ -f .env ]]; then
  mode=$(stat -c '%a' .env)
  if [[ "$mode" == "600" || "$mode" == "640" ]]; then ok ".env vorhanden (Mode $mode)"
  else fail ".env vorhanden, aber Mode $mode (erwartet 600/640)"; fi
else fail ".env fehlt"; fi

# .secrets
if [[ -d .secrets ]]; then
  mode=$(stat -c '%a' .secrets)
  if [[ "$mode" == "700" ]]; then ok ".secrets/ vorhanden (Mode 700)"
  else fail ".secrets/ vorhanden, aber Mode $mode (erwartet 700)"; fi
  shopt -s nullglob
  for f in .secrets/*.env .secrets/*.bak* .secrets/*.key; do
    [[ -f "$f" ]] || continue
    fmode=$(stat -c '%a' "$f")
    if [[ "$fmode" == "600" ]]; then ok "  $(basename "$f") Mode 600"
    else fail "  $(basename "$f") Mode $fmode (erwartet 600)"; fi
  done
  shopt -u nullglob
else fail ".secrets/ fehlt"; fi

# Uptime Kuma
if [[ -f .secrets/uptime-kuma.env ]]; then
  if grep -qE '^UPTIME_KUMA_USER=' .secrets/uptime-kuma.env && \
     grep -qE '^UPTIME_KUMA_PASSWORD=' .secrets/uptime-kuma.env; then
    ok "Uptime Kuma Credentials in .secrets/uptime-kuma.env vorhanden"
  else fail ".secrets/uptime-kuma.env unvollstaendig"; fi
else warn ".secrets/uptime-kuma.env fehlt (Monitor-Setup nicht moeglich)"; fi

# Paperless
if [[ -f .secrets/paperless.env ]]; then ok ".secrets/paperless.env vorhanden"
else warn ".secrets/paperless.env optional, fehlt"; fi

# ConvertX
if [[ -f .secrets/convertx.env ]]; then ok ".secrets/convertx.env vorhanden"
else warn ".secrets/convertx.env optional, fehlt"; fi

# Filebrowser
if [[ -f .secrets/filebrowser.env ]]; then ok ".secrets/filebrowser.env vorhanden"
else warn ".secrets/filebrowser.env fehlt (bei Filebrowser-Betrieb erwartet)"; fi

# Stirling
if [[ -f .secrets/stirling-pdf.env ]]; then ok ".secrets/stirling-pdf.env vorhanden"
else warn ".secrets/stirling-pdf.env fehlt (bei Stirling PDF Login erwartet)"; fi

# .env Inhalte (ohne Werte)
if [[ -f .env ]]; then
  set -a; source .env; set +a
  for key in RESTIC_REPOSITORY RESTIC_PASSWORD RCLONE_CONFIG_PATH \
             PAPERLESS_SECRET_KEY PAPERLESS_ADMIN_PASSWORD PAPERLESS_DBPASS \
             CONVERTX_JWT_SECRET POSTGRES_PASSWORD; do
    val="${!key:-}"
    if [[ -n "$val" ]]; then ok "$key gesetzt"
    else fail "$key fehlt oder leer"; fi
  done
  if [[ -n "${RCLONE_CONFIG_PATH:-}" ]]; then
    if [[ -r "$RCLONE_CONFIG_PATH" ]]; then ok "RCLONE_CONFIG_PATH lesbar"
    else fail "RCLONE_CONFIG_PATH gesetzt aber nicht lesbar"; fi
  fi
fi

# .gitignore-Schutz
for pat in '.env' '.secrets/' '.venv-'; do
  if grep -qE "^${pat//./\\.}" .gitignore 2>/dev/null; then ok ".gitignore deckt $pat ab"
  else fail ".gitignore deckt $pat NICHT ab"; fi
done

# git-tracked Secrets?
if git ls-files 2>/dev/null | grep -qE '^\.env$|^\.secrets/'; then
  fail "GEFAHR: .env oder .secrets/ ist in git getrackt"
else ok "Keine Secret-Dateien in git getrackt"; fi

echo
if [[ "$FAILED" == "1" ]]; then echo -e "${RED}Secrets-Audit: Fehler gefunden.${NC}"; exit 1
else echo -e "${GREEN}Secrets-Audit: alle Pruefungen bestanden.${NC}"; fi
