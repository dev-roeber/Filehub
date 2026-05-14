#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

warn=0
fail=0

say() { printf '%s\n' "$*"; }
ok() { printf 'OK: %s\n' "$*"; }
warning() { printf 'WARN: %s\n' "$*"; warn=1; }
error() { printf 'ERROR: %s\n' "$*" >&2; fail=1; }

[[ -f compose.yml ]] || error "compose.yml fehlt oder falsches Verzeichnis."

if docker info >/dev/null 2>&1; then ok "Docker ist erreichbar."; else error "Docker ist nicht erreichbar."; fi
if docker compose version >/dev/null 2>&1; then ok "Docker Compose ist erreichbar."; else error "Docker Compose fehlt."; fi

if [[ -f .env ]]; then
  ok ".env vorhanden."
  # shellcheck disable=SC1091
  set -a; source .env; set +a
else
  error ".env fehlt. Führe scripts/init.sh aus."
fi

for var in PUID PGID PAPERLESS_SECRET_KEY PAPERLESS_ADMIN_PASSWORD PAPERLESS_DBPASS CONVERTX_JWT_SECRET; do
  if [[ -z "${!var:-}" ]]; then
    error "$var ist leer oder nicht gesetzt."
  elif [[ "${!var}" == change-me* ]]; then
    error "$var enthält noch einen Platzhalter."
  else
    ok "$var ist gesetzt."
  fi
done

for dir in data/paperless/consume data/paperless/data data/paperless/media data/paperless/export data/postgres data/redis data/convertx data/uptime-kuma config/homepage backups; do
  [[ -d "$dir" ]] && ok "Verzeichnis $dir vorhanden." || error "Verzeichnis $dir fehlt."
done

for p in "${PAPERLESS_PORT:-8000}" "${CONVERTX_PORT:-3000}" "${HOMEPAGE_PORT:-3001}" "${UPTIME_KUMA_PORT:-3002}" "${DOZZLE_PORT:-9999}"; do
  if ss -ltn "( sport = :$p )" | awk 'NR > 1 {found=1} END {exit found ? 0 : 1}'; then
    warning "Port $p ist bereits belegt. Prüfe Konflikte vor dem Start."
  else
    ok "Port $p ist frei."
  fi
done

if swapon --show | awk 'NR > 1 {found=1} END {exit found ? 0 : 1}'; then
  ok "Swap ist aktiv."
else
  warning "Kein Swap aktiv. scripts/create-swap.sh kann optional 4G anlegen."
fi

avail_kb="$(df -Pk . | awk 'NR==2 {print $4}')"
if (( avail_kb < 20 * 1024 * 1024 )); then
  warning "Weniger als 20 GB frei im Projekt-Dateisystem."
else
  ok "Mindestens 20 GB freier Speicher im Projekt-Dateisystem."
fi

say "UFW-Status:"
if command -v ufw >/dev/null 2>&1; then
  sudo ufw status verbose || true
else
  warning "ufw nicht installiert."
fi

if docker compose -f compose.yml -f compose.paperless.yml -f compose.convertx.yml -f compose.observability.yml config 2>/tmp/filehub-compose-config.err | grep -E 'host_ip: 0\.0\.0\.0|published: "?((80)|(443))"?$' >/dev/null; then
  warning "Compose-Konfiguration auf öffentliche Bindings prüfen."
else
  ok "Keine offensichtlichen Public Bindings in aktiven Compose-Dateien gefunden."
fi

if (( fail )); then
  say "Doctor abgeschlossen: Fehler gefunden."
  exit 1
fi

if (( warn )); then
  say "Doctor abgeschlossen: Warnungen gefunden."
else
  say "Doctor abgeschlossen: keine kritischen Probleme."
fi
