#!/usr/bin/env bash
# Filehub Gateway Migration-Status.
#
# Zeigt Status fuer filehub-gateway an: running, source (root/infra/unknown),
# health, ports, config_files-Label, safe-to-migrate.
# Read-only, kein Container-Eingriff.
#
# Usage:
#   scripts/gateway-migration-status.sh
#   scripts/gateway-migration-status.sh --quiet
#   scripts/gateway-migration-status.sh --json
#
# Exit-Codes:
#   0  Gateway laeuft, Quelle eindeutig (root oder infra)
#   1  WARN: Gateway laeuft, aber Quelle unklar
#   2  FAIL: Gateway nicht gefunden / Docker nicht erreichbar
#
# Konvention "safe-to-migrate":
#   yes   source=root, Container running, health=healthy
#   no    source=infra (schon migriert) ODER missing
#   warn  source=unknown, oder health!=healthy

set -uo pipefail
cd "$(dirname "$0")/.."

QUIET=0
JSON=0
for arg in "$@"; do
  case "$arg" in
    --quiet) QUIET=1 ;;
    --json)  JSON=1 ;;
    -h|--help)
      sed -n '1,22p' "$0"; exit 0 ;;
    *)
      echo "ERROR: unbekannte Option $arg" >&2
      exit 2 ;;
  esac
done

log() { (( QUIET == 0 )) && echo "$@"; }

# Docker erreichbar?
if ! docker info >/dev/null 2>&1; then
  echo "FAIL Docker nicht erreichbar" >&2
  exit 2
fi

CONTAINER="filehub-gateway"

# Existiert der Container?
if ! docker inspect "$CONTAINER" >/dev/null 2>&1; then
  if (( JSON == 1 )); then
    echo '{"container":"filehub-gateway","run":"missing","source":"none","safe":"no"}'
  else
    log "Gateway-Container '$CONTAINER' existiert nicht."
    log "Empfehlung: just gateway-up (compose.auth.yml) oder Cutover via infra/gateway/."
  fi
  exit 2
fi

STATE="$(docker inspect --format '{{.State.Status}}' "$CONTAINER" 2>/dev/null)"
HEALTH="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$CONTAINER" 2>/dev/null)"
CFG="$(docker inspect --format '{{index .Config.Labels "com.docker.compose.project.config_files"}}' "$CONTAINER" 2>/dev/null)"
PORTS_RAW="$(docker inspect --format '{{range $p, $bs := .NetworkSettings.Ports}}{{range $bs}}{{.HostIp}}:{{.HostPort}}->{{$p}} {{end}}{{end}}' "$CONTAINER" 2>/dev/null)"

RUN="no"
[[ "$STATE" == "running" ]] && RUN="yes"

SOURCE="unknown"
if echo "$CFG" | grep -q "infra/gateway/compose.yml"; then
  SOURCE="infra"
elif echo "$CFG" | grep -qE "compose\.auth\.yml"; then
  SOURCE="root"
fi

# safe-to-migrate Logik
SAFE="warn"
case "$SOURCE" in
  root)
    if [[ "$RUN" == "yes" && "$HEALTH" == "healthy" ]]; then
      SAFE="yes"
    fi
    ;;
  infra)
    SAFE="no" # schon migriert
    ;;
esac

EXIT=0
[[ "$SOURCE" == "unknown" ]] && EXIT=1

if (( JSON == 1 )); then
  printf '{"container":"%s","run":"%s","state":"%s","health":"%s","source":"%s","ports":"%s","config_files":"%s","safe":"%s"}\n' \
    "$CONTAINER" "$RUN" "$STATE" "$HEALTH" "$SOURCE" "${PORTS_RAW% }" "$CFG" "$SAFE"
  exit $EXIT
fi

if (( QUIET == 0 )); then
  printf 'CONTAINER     %s\n' "$CONTAINER"
  printf 'RUN           %s (state=%s)\n' "$RUN" "$STATE"
  printf 'HEALTH        %s\n' "$HEALTH"
  printf 'SOURCE        %s\n' "$SOURCE"
  printf 'PORTS         %s\n' "${PORTS_RAW% }"
  printf 'CONFIG_FILES  %s\n' "$CFG"
  printf 'SAFE          %s\n' "$SAFE"
  echo
  case "$SOURCE" in
    root)
      echo "Bootstrap-Quelle. Cutover auf infra/gateway/ ist vorbereitet."
      echo "Naechster Schritt: docs/GATEWAY_MIGRATION_RUNBOOK.md"
      ;;
    infra)
      echo "Cutover bereits erfolgt. compose.auth.yml bleibt als Rollback."
      ;;
    *)
      echo "WARN Quelle nicht eindeutig - manueller Check noetig."
      ;;
  esac
else
  printf 'gateway run=%s source=%s health=%s safe=%s\n' "$RUN" "$SOURCE" "$HEALTH" "$SAFE"
fi

exit $EXIT
