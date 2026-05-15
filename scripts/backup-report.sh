#!/usr/bin/env bash
# Kompakter Backup-Statusbericht. Liest .env, sendet bei --notify per ntfy.
set -euo pipefail
cd "$(dirname "$0")/.."

notify=0
[[ "${1:-}" == "--notify" ]] && notify=1

[[ -f .env ]] && { set -a; . ./.env; set +a; }

# letzter lokaler Backup-Ordner
last_local="(keiner)"
if compgen -G "backups/2*" >/dev/null; then
  last_local=$(ls -1dt backups/2* 2>/dev/null | head -1)
fi
local_size=$(du -sh backups 2>/dev/null | awk '{print $1}')

# restic
repo_ok="nein"
latest_snap=""
snap_count="0"
if [[ -n "${RESTIC_REPOSITORY:-}" && -n "${RESTIC_PASSWORD:-}" ]]; then
  if [[ "$RESTIC_REPOSITORY" == rclone:* && -n "${RCLONE_CONFIG_PATH:-}" ]]; then
    export RCLONE_CONFIG="$RCLONE_CONFIG_PATH"
  fi
  if restic cat config >/dev/null 2>&1; then
    repo_ok="ja"
    snap_count=$(restic snapshots --tag filehub-full --json 2>/dev/null | grep -o '"short_id"' | wc -l || echo 0)
    latest_snap=$(restic snapshots --tag filehub-full --latest 1 --json 2>/dev/null \
      | sed -n 's/.*"short_id":"\([^"]*\)".*/\1/p' | head -1)
  fi
fi

# timer
next_run="(unbekannt)"
if command -v systemctl >/dev/null; then
  next_run=$(systemctl list-timers filehub-backup.timer --no-pager 2>/dev/null \
    | awk 'NR==2 {print $1, $2, $3}')
fi

report=$(cat <<EOF
Filehub Backup-Report ($(date -Iseconds))
- Letzter lokaler Backup-Ordner: ${last_local}
- Lokaler backups/-Verbrauch:    ${local_size:-?}
- Restic erreichbar:             ${repo_ok}
- Snapshots (filehub-full):      ${snap_count}
- Neuester Snapshot:             ${latest_snap:-<keiner>}
- Naechster Timer-Lauf:          ${next_run}
EOF
)

printf '%s\n' "$report"

if [[ "$notify" -eq 1 && -f .secrets/ntfy.env ]]; then
  scripts/notify.sh \
    --title "Filehub Backup-Report" \
    --message "$report" \
    --tags "package,filehub" \
    --quiet || true
fi
