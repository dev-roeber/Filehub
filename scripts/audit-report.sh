#!/usr/bin/env bash
# Sammelt einen kompletten Filehub-Betriebsstatus. Keine Secrets.
set -uo pipefail
cd "$(dirname "$0")/.."

notify=0
[[ "${1:-}" == "--notify" ]] && notify=1

section() { printf '\n=== %s ===\n' "$1"; }

section "git"
git -C . status --short --branch 2>&1 | head -20
git -C . log --oneline -3 2>&1

section "docker compose ps"
docker compose -f compose.yml -f compose.paperless.yml -f compose.convertx.yml \
  -f compose.observability.yml -f compose.extensions.yml ps 2>&1 | tail -20

section "health"
./scripts/health.sh 2>&1 | tail -20

section "doctor (Public Bindings / Ports / Swap)"
./scripts/doctor.sh 2>&1 | tail -25

section "secrets-audit"
./scripts/secrets-audit.sh 2>&1 | tail -15

section "backup-timer"
systemctl status filehub-backup.timer --no-pager 2>&1 | head -8 || true
systemctl list-timers filehub-backup.timer --no-pager 2>&1 | head -3 || true

section "letzte restic snapshots"
( set -a; . ./.env 2>/dev/null; set +a
  restic snapshots --tag filehub-full --compact 2>&1 | tail -10 ) || true

section "storage"
./scripts/storage-check.sh 2>&1 | tail -15
storage_exit=$?

section "uptime kuma"
if curl -fsS --max-time 5 http://127.0.0.1:3002/ >/dev/null 2>&1; then
  echo "uptime-kuma erreichbar"
else
  echo "uptime-kuma NICHT erreichbar"
fi

section "backup-report"
./scripts/backup-report.sh 2>&1 | tail -10

section "registry-audit (Modularitaet)"
./scripts/registry-audit.sh --quiet 2>&1 | tail -15 || true

if [[ "$notify" -eq 1 && -f .secrets/ntfy.env ]]; then
  summary=$(./scripts/backup-report.sh 2>/dev/null)
  ./scripts/notify.sh --title "Filehub Audit-Report" \
    --message "$summary" --tags "clipboard,filehub" --quiet || true
fi

exit 0
