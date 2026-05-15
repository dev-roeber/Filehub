#!/usr/bin/env bash
# Filehub App-Helper.
# Bedient die modularen App-Verzeichnisse unter apps/<id>/.
# Nutzung:
#   scripts/app.sh list
#   scripts/app.sh up <app>      | down/restart/logs/status/pull/update/health <app>
#   scripts/app.sh apps-status
#   scripts/app.sh infra-status
#   scripts/app.sh backup-app <app>
#   scripts/app.sh backup-all

set -euo pipefail
cd "$(dirname "$0")/.."

ENV_FILE="${ENV_FILE:-$PWD/.env}"
APPS_DIR="apps"
REGISTRY="config/apps.yml"

list_apps() {
  for d in "$APPS_DIR"/*/; do
    [[ -f "$d/compose.yml" ]] || continue
    basename "$d"
  done | sort
}

require_app() {
  local app="$1"
  [[ -d "$APPS_DIR/$app" && -f "$APPS_DIR/$app/compose.yml" ]] || {
    echo "ERROR: Unbekannte App '$app'. Verfuegbar:" >&2
    list_apps | sed 's/^/  - /' >&2
    exit 1
  }
}

compose_for() {
  local app="$1"
  echo "docker compose --env-file $ENV_FILE -f $APPS_DIR/$app/compose.yml"
}

cmd_list() {
  if [[ -f "$REGISTRY" ]] && command -v python3 >/dev/null 2>&1; then
    python3 - <<'PY'
import re, sys, pathlib
text = pathlib.Path("config/apps.yml").read_text()
in_apps = False
print(f"{'id':<14} {'name':<22} {'port':<6} {'default':<8} {'authentik':<10} {'description'}")
print("-" * 96)
for line in text.splitlines():
    if line.startswith("apps:"):
        in_apps = True; continue
    if line.startswith("infra:"):
        in_apps = False; continue
    if not in_apps: continue
    m = re.match(r"\s+-\s+id:\s*(\S+)", line)
    if m:
        current = {"id": m.group(1)}
        rows = current
        continue
    for key in ("name", "port", "default_enabled", "authentik_optional", "description"):
        m = re.match(rf"\s+{key}:\s*(.+)", line)
        if m and "current" in dir():
            current[key] = m.group(1).strip()
    if "current" in dir() and len(current) >= 6:
        print(f"{current.get('id',''):<14} {current.get('name',''):<22} {current.get('port',''):<6} {current.get('default_enabled',''):<8} {current.get('authentik_optional',''):<10} {current.get('description','')}")
        current = {}
PY
  else
    list_apps
  fi
}

cmd_up()      { require_app "$1"; eval "$(compose_for "$1") up -d"; }
cmd_down()    { require_app "$1"; eval "$(compose_for "$1") stop"; eval "$(compose_for "$1") rm -f"; }
cmd_restart() { require_app "$1"; eval "$(compose_for "$1") restart"; }
cmd_logs()    { require_app "$1"; eval "$(compose_for "$1") logs -f --tail=200"; }
cmd_pull()    { require_app "$1"; eval "$(compose_for "$1") pull"; }
cmd_update()  { require_app "$1"; eval "$(compose_for "$1") pull"; eval "$(compose_for "$1") up -d"; }

cmd_status()  {
  require_app "$1"
  eval "$(compose_for "$1") ps"
}

cmd_health()  {
  require_app "$1"
  if [[ -x "$APPS_DIR/$1/healthcheck.sh" ]]; then
    "$APPS_DIR/$1/healthcheck.sh"
  else
    echo "WARN: $APPS_DIR/$1/healthcheck.sh nicht ausfuehrbar." >&2
    return 1
  fi
}

cmd_apps_status() {
  printf "%-14s %-22s %-10s %s\n" "app" "container" "state" "http"
  printf -- "-%.0s" {1..70}; echo
  for app in $(list_apps); do
    if [[ -x "$APPS_DIR/$app/healthcheck.sh" ]]; then
      out="$("$APPS_DIR/$app/healthcheck.sh" 2>&1 || true)"
      container="$(grep -oE 'container=\S+' <<<"$out" | head -1 | cut -d= -f2)"
      state="$(grep -oE 'state=\S+' <<<"$out" | head -1 | cut -d= -f2)"
      http="$(grep -oE 'http=\S+' <<<"$out" | head -1 | cut -d= -f2)"
      printf "%-14s %-22s %-10s %s\n" "$app" "${container:-?}" "${state:-?}" "${http:-?}"
    else
      printf "%-14s %-22s %-10s %s\n" "$app" "-" "no-healthcheck" "-"
    fi
  done
}

cmd_infra_status() {
  echo "=== Authentik ==="
  for c in filehub-authentik-db filehub-authentik-redis filehub-authentik-server filehub-authentik-worker; do
    if docker inspect "$c" >/dev/null 2>&1; then
      state="$(docker inspect -f '{{.State.Health.Status}}' "$c" 2>/dev/null || echo none)"
      running="$(docker inspect -f '{{.State.Status}}' "$c")"
      printf "  %-32s %-10s %s\n" "$c" "$running" "$state"
    else
      printf "  %-32s %s\n" "$c" "not present"
    fi
  done
  echo "=== Gateway ==="
  if docker inspect filehub-gateway >/dev/null 2>&1; then
    state="$(docker inspect -f '{{.State.Health.Status}}' filehub-gateway 2>/dev/null || echo none)"
    running="$(docker inspect -f '{{.State.Status}}' filehub-gateway)"
    printf "  %-32s %-10s %s\n" "filehub-gateway" "$running" "$state"
  else
    printf "  %-32s %s\n" "filehub-gateway" "not present"
  fi
  echo "=== Networks ==="
  docker network ls --filter name=filehub_net --filter name=authentik_net --format "  {{.Name}}\t{{.Driver}}\t{{.Scope}}"
}

cmd_backup_app() {
  local app="$1"
  require_app "$app"
  local include="$APPS_DIR/$app/backup.include"
  if [[ ! -f "$include" ]]; then
    echo "WARN: $include fehlt - nichts zu sichern." >&2
    return 0
  fi
  FILEHUB_BACKUP_ONLY_APP="$app" ./scripts/backup.sh
}

cmd_backup_all() { ./scripts/backup.sh; }

case "${1:-}" in
  list)         cmd_list ;;
  up)           shift; cmd_up "$@" ;;
  down)         shift; cmd_down "$@" ;;
  restart)      shift; cmd_restart "$@" ;;
  logs)         shift; cmd_logs "$@" ;;
  status)       shift; cmd_status "$@" ;;
  pull)         shift; cmd_pull "$@" ;;
  update)       shift; cmd_update "$@" ;;
  health)       shift; cmd_health "$@" ;;
  apps-status)  cmd_apps_status ;;
  infra-status) cmd_infra_status ;;
  backup-app)   shift; cmd_backup_app "$@" ;;
  backup-all)   cmd_backup_all ;;
  ""|-h|--help|help)
    cat <<EOF
Filehub App-Helper
Usage:
  $0 list
  $0 up|down|restart|logs|status|pull|update|health <app>
  $0 apps-status | infra-status
  $0 backup-app <app> | backup-all
EOF
    ;;
  *) echo "Unknown command: $1" >&2; exit 2 ;;
esac
