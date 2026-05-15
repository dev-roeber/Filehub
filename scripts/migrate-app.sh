#!/usr/bin/env bash
# Filehub Migrate-App (Phase 1: dry-run/plan only).
#
# Zweck:
#   Helfer fuer den Cutover Root-Compose -> apps/<id>/compose.yml.
#   Phase 1: NUR planen / auditieren / Befehle drucken. Es werden KEINE
#   docker compose up/down/stop/restart Aufrufe ausgefuehrt.
#   `--execute` bricht bewusst mit exit 1 ab.
#
# Usage:
#   scripts/migrate-app.sh <app> --dry-run
#   scripts/migrate-app.sh <app> --print-commands
#   scripts/migrate-app.sh <app> --rollback-plan
#   scripts/migrate-app.sh <app> --execute   # exit 1: not implemented in phase 1
#
# Exit-Codes:
#   0  dry-run/print/rollback erfolgreich ohne FAIL
#   1  kein/unbekannter Modus, oder --execute (Phase-1-Hinweis)
#   2  FAIL (App unbekannt, compose.yml fehlt, Authentik-Sonderfall)
#
# Kommentare und Ausgaben bewusst ASCII-only (kein Umlaut).

set -uo pipefail
cd "$(dirname "$0")/.."

REGISTRY="config/apps.yml"

usage() {
  sed -n '1,22p' "$0"
}

# ---------------------------------------------------------------------------
# Argument-Parsing
# ---------------------------------------------------------------------------
if [[ $# -lt 1 ]]; then
  usage
  echo "ERROR: kein Argument" >&2
  exit 1
fi

APP=""
MODE=""
for arg in "$@"; do
  case "$arg" in
    --dry-run|--print-commands|--rollback-plan|--execute)
      if [[ -n "$MODE" ]]; then
        echo "ERROR: nur genau ein Modus erlaubt (haben: $MODE und $arg)" >&2
        exit 1
      fi
      MODE="$arg"
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --*)
      echo "ERROR: unbekannte Option $arg" >&2
      usage
      exit 1
      ;;
    *)
      if [[ -n "$APP" ]]; then
        echo "ERROR: mehrere App-Argumente: $APP und $arg" >&2
        exit 1
      fi
      APP="$arg"
      ;;
  esac
done

if [[ -z "$APP" ]]; then
  usage
  echo "ERROR: <app> fehlt" >&2
  exit 1
fi

if [[ -z "$MODE" ]]; then
  usage
  echo "ERROR: kein Modus angegeben (--dry-run | --print-commands | --rollback-plan | --execute)" >&2
  exit 1
fi

# Authentik-Sonderfall: vor Registry-Check (authentik ist nicht in apps.yml)
if [[ "$APP" == "authentik" ]]; then
  echo "FAIL authentik hat eine separate Migrationsphase und wird NICHT ueber" >&2
  echo "     migrate-app.sh behandelt. Siehe infra/authentik/ und die zugehoerige" >&2
  echo "     Migrationsdokumentation." >&2
  exit 2
fi

# ---------------------------------------------------------------------------
# Registry-Lookup
# ---------------------------------------------------------------------------
if [[ ! -f "$REGISTRY" ]]; then
  echo "FAIL $REGISTRY fehlt" >&2
  exit 2
fi

APP_IDS_RAW="$(python3 - <<'PY'
import re, pathlib
text = pathlib.Path("config/apps.yml").read_text()
section = None
for line in text.splitlines():
    if line.startswith("apps:"):
        section = "apps"; continue
    if line.startswith("infra:"):
        section = "infra"; continue
    if section != "apps":
        continue
    m = re.match(r"\s+-\s+id:\s*(\S+)\s*$", line)
    if m:
        print(m.group(1))
PY
)"

APP_IDS=()
while IFS= read -r id; do
  [[ -z "$id" ]] && continue
  APP_IDS+=("$id")
done <<< "$APP_IDS_RAW"

app_known=0
for id in "${APP_IDS[@]}"; do
  if [[ "$id" == "$APP" ]]; then
    app_known=1
    break
  fi
done

if [[ $app_known -eq 0 ]]; then
  echo "FAIL Unbekannte App '$APP'." >&2
  echo "Verfuegbare Apps (config/apps.yml):" >&2
  for id in "${APP_IDS[@]}"; do
    echo "  - $id" >&2
  done
  exit 2
fi

# --execute: in Phase 1 nicht implementiert
if [[ "$MODE" == "--execute" ]]; then
  cat <<'MSG'
ERROR: --execute ist in Phase 1 nicht implementiert.
Nutze --dry-run / --print-commands / --rollback-plan, fuehre die Schritte
manuell aus und verifiziere jeweils mit just runtime-audit.
MSG
  exit 1
fi

APP_DIR="apps/$APP"
APP_COMPOSE="$APP_DIR/compose.yml"
APP_BACKUP_INC="$APP_DIR/backup.include"
APP_HEALTH="$APP_DIR/healthcheck.sh"

# ---------------------------------------------------------------------------
# Compose-Lookup-Helfer
# ---------------------------------------------------------------------------
# Primary container_name aus apps/<app>/compose.yml
get_primary_container() {
  local file="$1"
  [[ -f "$file" ]] || return 0
  grep -E "^[[:space:]]*container_name:" "$file" \
    | head -n1 \
    | sed -E 's/^[[:space:]]*container_name:[[:space:]]*//; s/[[:space:]]*$//'
}

# Alle container_names aus apps/<app>/compose.yml
list_app_containers() {
  local file="$1"
  [[ -f "$file" ]] || return 0
  grep -E "^[[:space:]]*container_name:" "$file" \
    | sed -E 's/^[[:space:]]*container_name:[[:space:]]*//; s/[[:space:]]*$//'
}

# Welche Root-Compose-Datei enthaelt container_name=<name>?
find_root_match_file() {
  local needle="$1"
  shopt -s nullglob
  local files=(compose.yml compose.*.yml)
  shopt -u nullglob
  for f in "${files[@]}"; do
    [[ -f "$f" ]] || continue
    if grep -E "^[[:space:]]*container_name:[[:space:]]*$needle[[:space:]]*$" "$f" >/dev/null 2>&1; then
      echo "$f"
      return 0
    fi
  done
  return 1
}

# Service-Name in Root-Compose-Datei, der container_name=<needle> setzt
find_root_service_name() {
  local file="$1" needle="$2"
  [[ -f "$file" ]] || return 1
  python3 - "$file" "$needle" <<'PY'
import re, sys
path, needle = sys.argv[1], sys.argv[2]
with open(path) as fh:
    lines = fh.read().splitlines()
in_services = False
services_indent = None
current_service = None
current_indent = None
for line in lines:
    stripped = line.rstrip()
    if not stripped:
        continue
    if re.match(r"^services:\s*$", line):
        in_services = True
        services_indent = None
        continue
    if in_services:
        m = re.match(r"^(\s*)(\S.*?):\s*$", line)
        # top-level key (no indent) ends services
        if line and not line.startswith(" ") and not line.startswith("\t") and line.endswith(":"):
            in_services = False
            continue
        if m:
            indent = len(m.group(1))
            key = m.group(2).strip()
            if services_indent is None and indent > 0:
                services_indent = indent
            if services_indent is not None and indent == services_indent:
                current_service = key
                current_indent = indent
                continue
        cm = re.match(r"^(\s*)container_name:\s*(\S+)\s*$", line)
        if cm and cm.group(2).strip() == needle and current_service:
            print(current_service)
            sys.exit(0)
sys.exit(1)
PY
}

# ---------------------------------------------------------------------------
# Status aus migration-status holen (JSON) - mit Fallback auf docker inspect
# ---------------------------------------------------------------------------
get_status_for_app() {
  local app="$1"
  local json=""
  json="$(scripts/migration-status.sh --json 2>/dev/null || true)"
  if [[ -n "$json" ]]; then
    python3 - "$app" <<'PY' <<<"$json"
import json, sys
app = sys.argv[1]
data_text = sys.stdin.read()
try:
    data = json.loads(data_text)
except Exception:
    sys.exit(0)
for a in data.get("apps", []):
    if a.get("app") == app:
        print("container=" + str(a.get("container","")))
        print("run=" + str(a.get("run","")))
        print("health=" + str(a.get("health","")))
        print("source=" + str(a.get("source","")))
        print("safe=" + str(a.get("safe","")))
        print("root_match=" + str(a.get("root_match","")))
        break
PY
  fi
}

# Fallback: direkter docker inspect ueber primary container
docker_inspect_status() {
  local name="$1"
  if ! docker inspect "$name" >/dev/null 2>&1; then
    echo "run=missing"
    echo "health=-"
    echo "source=none"
    return
  fi
  local state health cfg src
  state="$(docker inspect --format '{{.State.Status}}' "$name" 2>/dev/null)"
  health="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$name" 2>/dev/null)"
  cfg="$(docker inspect --format '{{index .Config.Labels "com.docker.compose.project.config_files"}}' "$name" 2>/dev/null)"
  src="unknown"
  if echo "$cfg" | grep -qE "apps/$APP/compose\.yml"; then
    src="app"
  elif echo "$cfg" | grep -qE "(^|[,/[:space:]])compose(\.[a-z0-9-]+)?\.yml([,[:space:]]|$)"; then
    if echo "$cfg" | grep -qE "/apps/"; then
      src="unknown"
    else
      src="root"
    fi
  fi
  local run="no"
  [[ "$state" == "running" ]] && run="yes"
  echo "run=$run"
  echo "health=${health:-none}"
  echo "source=$src"
}

# ---------------------------------------------------------------------------
# Status-Auswertung
# ---------------------------------------------------------------------------
STATUS_BLOCK="$(get_status_for_app "$APP" || true)"

S_CONTAINER=""
S_RUN=""
S_HEALTH=""
S_SOURCE=""
S_SAFE=""
S_ROOT_MATCH=""
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  case "$line" in
    container=*)  S_CONTAINER="${line#container=}" ;;
    run=*)        S_RUN="${line#run=}" ;;
    health=*)     S_HEALTH="${line#health=}" ;;
    source=*)     S_SOURCE="${line#source=}" ;;
    safe=*)       S_SAFE="${line#safe=}" ;;
    root_match=*) S_ROOT_MATCH="${line#root_match=}" ;;
  esac
done <<< "$STATUS_BLOCK"

# Primary aus app-compose ist die Quelle der Wahrheit fuer Befehle
PRIMARY=""
if [[ -f "$APP_COMPOSE" ]]; then
  PRIMARY="$(get_primary_container "$APP_COMPOSE")"
fi

# Fallback fuer Status, falls migration-status nichts geliefert hat
if [[ -z "$S_RUN" && -n "$PRIMARY" ]]; then
  FALLBACK="$(docker_inspect_status "$PRIMARY" 2>/dev/null || true)"
  while IFS= read -r line; do
    case "$line" in
      run=*)    S_RUN="${line#run=}" ;;
      health=*) S_HEALTH="${line#health=}" ;;
      source=*) S_SOURCE="${line#source=}" ;;
    esac
  done <<< "$FALLBACK"
  S_CONTAINER="$PRIMARY"
fi

# Root-Compose-Match-Datei + Service-Name
ROOT_MATCH_FILE=""
ROOT_SERVICE=""
if [[ -n "$PRIMARY" ]]; then
  ROOT_MATCH_FILE="$(find_root_match_file "$PRIMARY" || true)"
  if [[ -n "$ROOT_MATCH_FILE" ]]; then
    ROOT_SERVICE="$(find_root_service_name "$ROOT_MATCH_FILE" "$PRIMARY" 2>/dev/null || true)"
  fi
fi

FAIL=0

# ---------------------------------------------------------------------------
# Modus: --dry-run
# ---------------------------------------------------------------------------
if [[ "$MODE" == "--dry-run" ]]; then
  echo "=== migrate-app dry-run: $APP ==="
  echo

  echo "-- Registry --"
  echo "OK  $APP ist in $REGISTRY registriert"
  echo

  echo "-- App-Dateien --"
  if [[ -f "$APP_COMPOSE" ]]; then
    echo "OK   $APP_COMPOSE vorhanden"
  else
    echo "FAIL $APP_COMPOSE fehlt"
    FAIL=1
  fi
  if [[ -f "$APP_BACKUP_INC" ]]; then
    echo "OK   $APP_BACKUP_INC vorhanden"
  else
    echo "WARN $APP_BACKUP_INC fehlt - Backup wird leer / unvollstaendig sein"
  fi
  if [[ -f "$APP_HEALTH" ]]; then
    if [[ -x "$APP_HEALTH" ]]; then
      echo "OK   $APP_HEALTH vorhanden und executable"
    else
      echo "WARN $APP_HEALTH vorhanden aber nicht executable (chmod +x noetig)"
    fi
  else
    echo "WARN $APP_HEALTH fehlt"
  fi
  echo

  echo "-- Container-Status (primary) --"
  if [[ -z "$PRIMARY" ]]; then
    echo "WARN kein primary container_name in $APP_COMPOSE feststellbar"
  else
    echo "INFO primary container_name: $PRIMARY"
    echo "INFO run=${S_RUN:-?} health=${S_HEALTH:-?} source=${S_SOURCE:-?}"
    case "${S_SOURCE:-}" in
      root)
        echo "OK   source=root - sicher zu migrieren (Cutover sinnvoll)"
        ;;
      app)
        echo "WARN source=app - bereits aus apps/$APP/compose.yml betrieben (schon migriert)"
        ;;
      unknown|none|"")
        echo "WARN source=${S_SOURCE:-unknown} - manueller Check noetig"
        ;;
    esac
    if [[ "${S_RUN:-}" == "missing" ]]; then
      echo "WARN Container $PRIMARY existiert nicht - Cutover-Stop entfaellt"
    fi
  fi
  echo

  echo "-- Root-Compose-Match --"
  if [[ -n "$ROOT_MATCH_FILE" ]]; then
    echo "OK   $PRIMARY -> $ROOT_MATCH_FILE (service: ${ROOT_SERVICE:-?})"
  else
    if [[ -n "$PRIMARY" ]]; then
      echo "WARN kein Root-Compose-Match fuer $PRIMARY gefunden - Rollback nicht trivial"
    else
      echo "WARN kein Primary, daher kein Root-Compose-Match auswertbar"
    fi
  fi
  echo

  # Weitere Container in app-compose listen (Helper)
  if [[ -f "$APP_COMPOSE" ]]; then
    ALL_NAMES=()
    while IFS= read -r n; do
      [[ -z "$n" ]] && continue
      ALL_NAMES+=("$n")
    done < <(list_app_containers "$APP_COMPOSE")
    if (( ${#ALL_NAMES[@]} > 1 )); then
      echo "-- Weitere Container in $APP_COMPOSE --"
      for n in "${ALL_NAMES[@]}"; do
        [[ "$n" == "$PRIMARY" ]] && continue
        echo "INFO helper-container: $n"
      done
      echo
    fi
  fi

  # Paperless-Sonderfall
  if [[ "$APP" == "paperless" ]]; then
    echo "-- Paperless-Sonderfall --"
    PAPERLESS_HELPERS=(filehub-paperless-db filehub-paperless-redis filehub-paperless-tika filehub-paperless-gotenberg)
    for c in "${PAPERLESS_HELPERS[@]}"; do
      if docker inspect "$c" >/dev/null 2>&1; then
        state="$(docker inspect --format '{{.State.Status}}' "$c" 2>/dev/null)"
        health="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$c" 2>/dev/null)"
        echo "INFO helper $c state=$state health=$health"
      else
        echo "INFO helper $c nicht vorhanden"
      fi
    done
    echo "WARN paperless hat Helper-Container (db/redis/tika/gotenberg) - Wartungsfenster laenger einplanen"
    echo
  fi

  # Empfehlung
  echo "-- Empfehlung --"
  SAFE_LABEL="${S_SAFE:-unknown}"
  if [[ -z "${S_SAFE:-}" ]]; then
    if [[ "${S_SOURCE:-}" == "root" ]]; then
      SAFE_LABEL="yes"
    elif [[ "${S_SOURCE:-}" == "app" ]]; then
      SAFE_LABEL="no"
    else
      SAFE_LABEL="warn"
    fi
  fi
  echo "EMPFEHLUNG: $APP aktuell safe=$SAFE_LABEL. Naechster Schritt: scripts/migrate-app.sh $APP --print-commands"

  if (( FAIL > 0 )); then
    exit 2
  fi
  exit 0
fi

# ---------------------------------------------------------------------------
# Vor print/rollback: compose.yml muss existieren
# ---------------------------------------------------------------------------
if [[ ! -f "$APP_COMPOSE" ]]; then
  echo "FAIL $APP_COMPOSE fehlt - Plan kann nicht erstellt werden" >&2
  exit 2
fi

# ---------------------------------------------------------------------------
# Modus: --print-commands
# ---------------------------------------------------------------------------
if [[ "$MODE" == "--print-commands" ]]; then
  echo "# Geplante Migrations-Befehle fuer $APP (NICHT ausgefuehrt)"
  echo
  echo "# 1) Backup"
  echo "just backup-app $APP"
  echo
  echo "# 2) Root-Service stoppen (kein down, kein -v)"
  if [[ -n "$ROOT_MATCH_FILE" && -n "$ROOT_SERVICE" ]]; then
    echo "docker compose -f compose.yml -f $ROOT_MATCH_FILE stop $ROOT_SERVICE"
    echo "docker compose -f compose.yml -f $ROOT_MATCH_FILE rm -f $ROOT_SERVICE"
  elif [[ -n "$ROOT_MATCH_FILE" ]]; then
    echo "# TODO: Service-Name in $ROOT_MATCH_FILE manuell ermitteln (container_name=$PRIMARY)"
    echo "# docker compose -f compose.yml -f $ROOT_MATCH_FILE stop <service>"
    echo "# docker compose -f compose.yml -f $ROOT_MATCH_FILE rm -f <service>"
  else
    echo "# TODO: kein Root-Compose-Match fuer container_name=${PRIMARY:-?} gefunden"
    echo "# Cutover-Stop manuell verifizieren (evtl. ist Container nicht aus Root-Compose)"
  fi
  echo
  echo "# 3) App-Compose starten"
  echo "just app-up $APP"
  echo
  echo "# 4) Healthcheck"
  echo "just app-health $APP"
  echo
  echo "# 5) Drift-Audit"
  echo "just runtime-audit"

  if [[ "$APP" == "paperless" ]]; then
    echo
    echo "# Hinweis paperless: Helper-Container (db/redis/tika/gotenberg) erfordern"
    echo "# laengeres Wartungsfenster. Reihenfolge der Stops/Starts beachten."
  fi
  exit 0
fi

# ---------------------------------------------------------------------------
# Modus: --rollback-plan
# ---------------------------------------------------------------------------
if [[ "$MODE" == "--rollback-plan" ]]; then
  echo "# Rollback-Plan fuer $APP (NICHT ausgefuehrt)"
  echo
  echo "just app-down $APP"
  if [[ -n "$ROOT_MATCH_FILE" && -n "$ROOT_SERVICE" ]]; then
    echo "docker compose -f compose.yml -f $ROOT_MATCH_FILE up -d $ROOT_SERVICE"
  elif [[ -n "$ROOT_MATCH_FILE" ]]; then
    echo "# TODO: Service-Name in $ROOT_MATCH_FILE manuell ermitteln (container_name=$PRIMARY)"
    echo "# docker compose -f compose.yml -f $ROOT_MATCH_FILE up -d <service>"
  else
    echo "# WARN: kein Root-Compose-Match fuer container_name=${PRIMARY:-?} gefunden"
    echo "# Rollback ist NICHT trivial - vorheriger Compose-Stand muss manuell"
    echo "# rekonstruiert werden (git history, Backup)."
  fi
  echo "just runtime-audit"
  exit 0
fi

# Sollte nie erreicht werden
echo "ERROR: interner Fehler - unerwarteter Modus $MODE" >&2
exit 1
