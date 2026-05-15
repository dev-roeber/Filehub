#!/usr/bin/env bash
# Prueft Disk/Storage. Exit 0 ok, 1 warn, 2 critical.
set -uo pipefail
cd "$(dirname "$0")/.."

WARN=${STORAGE_WARN_PCT:-80}
CRIT=${STORAGE_CRIT_PCT:-90}

worst=0
report=()

check_fs() {
  local label="$1" path="$2"
  local pct
  pct=$(df -P "$path" 2>/dev/null | awk 'NR==2 {gsub("%","",$5); print $5}')
  [[ -z "$pct" ]] && return
  report+=("$(printf '%-26s %3s%%  (%s)' "$label" "$pct" "$path")")
  if (( pct >= CRIT )); then worst=2
  elif (( pct >= WARN )) && (( worst < 2 )); then worst=1
  fi
}

check_fs "root filesystem" "/"
check_fs "repo filesystem" "."
check_fs "home filesystem" "$HOME"

docker_disk="(docker nicht erreichbar)"
if docker info >/dev/null 2>&1; then
  docker_disk=$(docker system df --format '{{.Type}}: {{.Size}} ({{.Reclaimable}} reclaimable)' 2>/dev/null | paste -sd '; ')
fi
report+=("Docker disk: ${docker_disk}")

data_size=$(du -sh data 2>/dev/null | awk '{print $1}')
backup_size=$(du -sh backups 2>/dev/null | awk '{print $1}')
report+=("Filehub data:  ${data_size:-?}")
report+=("Backups dir:   ${backup_size:-?}")

printf 'Filehub Storage-Check (warn=%s%% crit=%s%%)\n' "$WARN" "$CRIT"
printf '%s\n' "${report[@]}"

case "$worst" in
  0) echo "Status: OK"; exit 0 ;;
  1)
    echo "Status: WARNING"
    if [[ -f .secrets/ntfy.env ]]; then
      scripts/notify.sh --title "Filehub Storage warning" \
        --message "$(printf '%s\n' "${report[@]}")" \
        --priority high --tags "warning,filehub,disk" --quiet || true
    fi
    exit 1
    ;;
  2)
    echo "Status: CRITICAL"
    if [[ -f .secrets/ntfy.env ]]; then
      scripts/notify.sh --title "Filehub Storage CRITICAL" \
        --message "$(printf '%s\n' "${report[@]}")" \
        --priority high --tags "rotating_light,filehub,disk" --quiet || true
    fi
    exit 2
    ;;
esac
