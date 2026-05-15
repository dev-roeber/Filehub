#!/usr/bin/env bash
# Wird von systemd OnFailure aufgerufen (siehe filehub-backup-alert@.service).
# Sendet einen knappen Auszug der letzten Service-Logs an ntfy, ohne Secrets.
set -euo pipefail
cd "$(dirname "$0")/.."

unit="${1:-filehub-backup.service}"
test_mode=0
if [[ "$unit" == "--test" || "${2:-}" == "--test" ]]; then
  test_mode=1
  unit="${unit/--test/filehub-backup.service}"
fi

if [[ "$test_mode" -eq 1 ]]; then
  body="Backup-Alert TEST: ${unit} (manueller Smoke-Test, kein echter Fehler)"
else
  log_tail=$(journalctl -u "$unit" -n 20 --no-pager -o cat 2>/dev/null \
    | grep -viE 'password|secret|token|passphrase|RESTIC_PASSWORD' \
    | tail -n 15 || true)
  body="Backup-Service ${unit} hat versagt."$'\n'$'\n'"Letzte Zeilen (ohne Secrets):"$'\n'"${log_tail:-<journal nicht verfuegbar>}"
fi

# In Datei loggen ohne Secrets
log_dir="backups/alerts"
mkdir -p "$log_dir"
chmod 700 "$log_dir" 2>/dev/null || true
ts=$(date +%Y%m%d-%H%M%S)
printf '%s\n' "$body" > "$log_dir/${ts}-${unit//\//_}.log"
chmod 600 "$log_dir/${ts}-${unit//\//_}.log" 2>/dev/null || true

if [[ -f .secrets/ntfy.env ]]; then
  scripts/notify.sh \
    --title "Filehub Backup-Alert: ${unit}" \
    --message "$body" \
    --priority high \
    --tags "rotating_light,filehub,backup" \
    --quiet || true
fi

echo "backup-alert: gemeldet (test=${test_mode}) - Log: $log_dir/${ts}-${unit//\//_}.log"
