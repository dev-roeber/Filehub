#!/usr/bin/env bash
# Filehub Migrate-App (Phase 2: homepage-only execute).
#
# Zweck:
#   Helfer fuer den Cutover Root-Compose -> apps/<id>/compose.yml.
#   - dry-run / print-commands / rollback-plan: read-only.
#   - --execute (Phase 2): aktuell NUR fuer 'homepage' freigegeben.
#     Erfordert zusaetzlich --yes-i-am-sure.
#
# Usage:
#   scripts/migrate-app.sh <app> --dry-run
#   scripts/migrate-app.sh <app> --print-commands
#   scripts/migrate-app.sh <app> --rollback-plan
#   scripts/migrate-app.sh homepage --execute --yes-i-am-sure
#
# Exit-Codes:
#   0  Aktion erfolgreich
#   1  kein/unbekannter Modus, Confirmation fehlt
#   2  Preflight/FAIL (App unbekannt, compose.yml fehlt, Authentik/Paperless gesperrt,
#      execute fuer nicht-freigegebene App, registry-/runtime-audit FAIL)
#   3  Rollback fehlgeschlagen
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
CONFIRM=0
OVERRIDE_ORDER=0
ALLOW_PAPERLESS=0
for arg in "$@"; do
  case "$arg" in
    --dry-run|--print-commands|--rollback-plan|--execute)
      if [[ -n "$MODE" ]]; then
        echo "ERROR: nur genau ein Modus erlaubt (haben: $MODE und $arg)" >&2
        exit 1
      fi
      MODE="$arg"
      ;;
    --yes-i-am-sure)
      CONFIRM=1
      ;;
    --override-order)
      OVERRIDE_ORDER=1
      ;;
    --allow-paperless)
      ALLOW_PAPERLESS=1
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

# ---------------------------------------------------------------------------
# Verbindliche Migrationsreihenfolge (User-Defined)
# ---------------------------------------------------------------------------
# Reihenfolge fuer Live-Cutover. authentik bleibt separate Phase und ist
# NICHT teil dieser Liste.
MIGRATION_ORDER=(homepage filebrowser stirling-pdf paperless convertx uptime-kuma dozzle)

order_index_of() {
  local needle="$1" i=0
  for a in "${MIGRATION_ORDER[@]}"; do
    if [[ "$a" == "$needle" ]]; then
      echo "$i"
      return 0
    fi
    i=$((i + 1))
  done
  return 1
}

# Liefert source=app|root|... fuer eine App via migration-status JSON
get_source_for_app() {
  local app="$1"
  scripts/migration-status.sh --json 2>/dev/null | python3 -c "
import json, sys
target = '$app'
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(1)
for a in data.get('apps', []):
    if a.get('app') == target:
        print(a.get('source',''))
        break
" 2>/dev/null
}

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
  echo "# 2) Root-Service(s) stoppen (kein down, kein -v)"
  if [[ "$APP" == "paperless" ]]; then
    PAPERLESS_STOP_ORDER=(paperless-webserver paperless-tika paperless-gotenberg paperless-redis paperless-db)
    for svc in "${PAPERLESS_STOP_ORDER[@]}"; do
      echo "docker compose -f compose.yml -f compose.paperless.yml stop $svc"
    done
    for svc in "${PAPERLESS_STOP_ORDER[@]}"; do
      echo "docker compose -f compose.yml -f compose.paperless.yml rm -f $svc"
    done
  elif [[ -n "$ROOT_MATCH_FILE" && -n "$ROOT_SERVICE" ]]; then
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
  echo "# 3) App-Compose starten (depends_on regelt Reihenfolge)"
  echo "just app-up $APP"
  echo
  echo "# 4) Healthcheck"
  if [[ "$APP" == "paperless" ]]; then
    echo "# Multi-Container-Check: 5 Container running + webserver http 200/302"
    echo "# MIGRATE_HEALTH_TIMEOUT_SECONDS=300 MIGRATE_HEALTH_INTERVAL_SECONDS=10"
  else
    echo "just app-health $APP"
  fi
  echo
  echo "# 5) Drift-Audit"
  echo "just runtime-audit"

  if [[ "$APP" == "paperless" ]]; then
    echo
    echo "# Paperless-Sonderhinweise:"
    echo "# - 5 Container: db, redis, tika, gotenberg, webserver"
    echo "# - Stop-Reihenfolge: webserver -> tika -> gotenberg -> redis -> db"
    echo "# - Start-Reihenfolge (Rollback): db -> redis -> tika -> gotenberg -> webserver"
    echo "# - Wartungsfenster fuer Postgres-Restart + Index-Rebuild einplanen"
    echo "# - Execute nur mit: --execute --yes-i-am-sure --allow-paperless"
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
  if [[ "$APP" == "paperless" ]]; then
    PAPERLESS_START_ORDER=(paperless-db paperless-redis paperless-tika paperless-gotenberg paperless-webserver)
    for svc in "${PAPERLESS_START_ORDER[@]}"; do
      echo "docker compose -f compose.yml -f compose.paperless.yml up -d $svc"
    done
  elif [[ -n "$ROOT_MATCH_FILE" && -n "$ROOT_SERVICE" ]]; then
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

# ---------------------------------------------------------------------------
# Modus: --execute (Phase 2, homepage-only)
# ---------------------------------------------------------------------------
if [[ "$MODE" == "--execute" ]]; then

  # Allow-Liste: homepage (A), filebrowser (B), stirling-pdf (C-1), convertx (D).
  # paperless (C-2) ist NUR ueber --allow-paperless erreichbar.
  EXECUTE_ALLOWED_APPS=("homepage" "filebrowser" "stirling-pdf" "convertx")
  # Apps, die zusaetzlich --allow-paperless erfordern (Multi-Container-Sonderfall)
  if [[ "$APP" == "paperless" && $ALLOW_PAPERLESS -eq 1 ]]; then
    EXECUTE_ALLOWED_APPS+=("paperless")
  fi
  allowed=0
  for a in "${EXECUTE_ALLOWED_APPS[@]}"; do
    [[ "$a" == "$APP" ]] && allowed=1
  done

  # Paperless: gesperrt, ausser explizit --allow-paperless gesetzt
  # (Sonderpfad mit Wartungsfenster, derzeit nicht freigegeben).
  if [[ "$APP" == "paperless" ]]; then
    if [[ $ALLOW_PAPERLESS -ne 1 ]]; then
      echo "FAIL paperless ist gesperrt fuer --execute (DB-Helper, separate Phase)" >&2
      echo "     Sonderfreigabe nur ueber --allow-paperless + --yes-i-am-sure," >&2
      echo "     und nur nach Vorbereitung des Wartungsfensters." >&2
      exit 2
    fi
    # Wenn --allow-paperless gesetzt, faellt die Allow-Liste durch (aktuell
    # nicht freigegeben), siehe naechste Pruefung.
  fi
  # authentik wurde oben schon mit exit 2 abgefangen.

  if [[ $allowed -eq 0 ]]; then
    allowed_list="$(IFS=,; echo "${EXECUTE_ALLOWED_APPS[*]}")"
    echo "FAIL execute currently allowed only for: $allowed_list (angefragt: $APP)" >&2
    exit 2
  fi

  if [[ $CONFIRM -ne 1 ]]; then
    echo "ERROR: --execute braucht zusaetzlich --yes-i-am-sure" >&2
    echo "       Beispiel: scripts/migrate-app.sh $APP --execute --yes-i-am-sure" >&2
    exit 1
  fi

  # ---------------- Reihenfolge-Pruefung ----------------
  # Alle Vorgaenger in MIGRATION_ORDER muessen bereits source=app sein.
  echo "-- Reihenfolge --"
  target_idx="$(order_index_of "$APP")"
  if [[ -z "$target_idx" ]]; then
    echo "FAIL $APP ist nicht in MIGRATION_ORDER definiert" >&2
    exit 2
  fi
  ORDER_FAIL=0
  for ((i=0; i<target_idx; i++)); do
    pred="${MIGRATION_ORDER[$i]}"
    src="$(get_source_for_app "$pred" || true)"
    if [[ "$src" == "app" ]]; then
      echo "OK   Vorgaenger $pred source=app"
    else
      echo "FAIL Vorgaenger $pred source=${src:-unknown} (erwartet: app)"
      ORDER_FAIL=1
    fi
  done
  if (( ORDER_FAIL > 0 )); then
    if [[ $OVERRIDE_ORDER -eq 1 && "$APP" != "paperless" ]]; then
      echo "WARN --override-order gesetzt: Reihenfolge-FAIL wird ignoriert"
    elif [[ $OVERRIDE_ORDER -eq 1 && "$APP" == "paperless" ]]; then
      echo "FAIL --override-order ist fuer paperless NICHT erlaubt" >&2
      exit 2
    else
      echo "ABORT Reihenfolge nicht erfuellt - keine Aktion ausgefuehrt" >&2
      echo "       Erwartete Reihenfolge: ${MIGRATION_ORDER[*]}" >&2
      exit 2
    fi
  fi
  echo

  echo "=== migrate-app EXECUTE: $APP ==="
  echo "WARN destruktive Aktion: stop+rm Root-Container, up App-Compose"
  echo

  # ---------------- Preflight ----------------
  echo "-- Preflight --"
  PRE_FAIL=0

  # 1. App-Compose vorhanden
  if [[ -f "$APP_COMPOSE" ]]; then
    echo "OK   $APP_COMPOSE vorhanden"
  else
    echo "FAIL $APP_COMPOSE fehlt"
    PRE_FAIL=1
  fi

  # 2. backup.include vorhanden
  if [[ -f "$APP_BACKUP_INC" ]]; then
    echo "OK   $APP_BACKUP_INC vorhanden"
  else
    echo "FAIL $APP_BACKUP_INC fehlt"
    PRE_FAIL=1
  fi

  # 3. healthcheck.sh vorhanden + executable
  if [[ -x "$APP_HEALTH" ]]; then
    echo "OK   $APP_HEALTH executable"
  else
    echo "FAIL $APP_HEALTH fehlt oder nicht executable"
    PRE_FAIL=1
  fi

  # 4. docker compose config -q fuer App-Compose
  if docker compose -f "$APP_COMPOSE" config -q >/dev/null 2>&1; then
    echo "OK   docker compose config -q $APP_COMPOSE"
  else
    echo "FAIL docker compose config -q $APP_COMPOSE schlug fehl"
    PRE_FAIL=1
  fi

  # 5. Root-Compose-Match + Service
  if [[ -n "$ROOT_MATCH_FILE" && -n "$ROOT_SERVICE" ]]; then
    echo "OK   Root-Match: $ROOT_MATCH_FILE / service=$ROOT_SERVICE"
  else
    echo "FAIL kein Root-Compose-Match (file=$ROOT_MATCH_FILE service=$ROOT_SERVICE)"
    PRE_FAIL=1
  fi

  # 6. Primary vorhanden
  if [[ -z "$PRIMARY" ]]; then
    echo "FAIL kein primary container_name in $APP_COMPOSE"
    PRE_FAIL=1
  else
    echo "OK   primary container_name=$PRIMARY"
  fi

  # 7. Aktueller Source = root oder missing (nicht app)
  echo "INFO aktueller Status: run=$S_RUN health=$S_HEALTH source=$S_SOURCE"
  case "$S_SOURCE" in
    root)
      echo "OK   aktuell source=root - Cutover sinnvoll"
      ;;
    app)
      echo "FAIL source=app - bereits aus apps/$APP/compose.yml betrieben"
      PRE_FAIL=1
      ;;
    *)
      echo "FAIL source=$S_SOURCE - nicht eindeutig migrierbar"
      PRE_FAIL=1
      ;;
  esac

  # 8. registry-audit ohne FAIL
  if scripts/registry-audit.sh --quiet >/dev/null 2>&1; then
    echo "OK   registry-audit ohne FAIL"
  else
    echo "FAIL registry-audit meldet FAIL"
    PRE_FAIL=1
  fi

  # 9. runtime-audit ohne FAIL (exit 2 = FAIL, exit 0/1 ok)
  scripts/runtime-audit.sh --quiet >/dev/null 2>&1
  rc=$?
  if [[ $rc -eq 2 ]]; then
    echo "FAIL runtime-audit meldet FAIL (exit 2)"
    PRE_FAIL=1
  else
    echo "OK   runtime-audit ohne FAIL (exit $rc)"
  fi

  # 10. Kein App-Compose-Container schon parallel aktiv
  #     (sollte nicht, weil Doppelstart von Docker geblockt wuerde -
  #      aber wir loggen es als Sicherheitscheck)
  CONFLICT=0
  while IFS= read -r n; do
    [[ -z "$n" ]] && continue
    if docker inspect "$n" >/dev/null 2>&1; then
      cfg="$(docker inspect --format '{{index .Config.Labels "com.docker.compose.project.config_files"}}' "$n" 2>/dev/null || true)"
      if echo "$cfg" | grep -q "apps/$APP/compose.yml"; then
        state="$(docker inspect --format '{{.State.Status}}' "$n" 2>/dev/null)"
        if [[ "$state" == "running" ]]; then
          echo "FAIL Container $n laeuft bereits aus apps/$APP/compose.yml"
          CONFLICT=1
        fi
      fi
    fi
  done < <(list_app_containers "$APP_COMPOSE")
  if [[ $CONFLICT -eq 0 ]]; then
    echo "OK   keine Duplikat-Konflikte"
  else
    PRE_FAIL=1
  fi

  echo

  if (( PRE_FAIL > 0 )); then
    echo "ABORT Preflight FAIL - keine Aktion ausgefuehrt" >&2
    exit 2
  fi

  echo "OK   Preflight komplett bestanden"
  echo

  # ---------------- Backup ----------------
  echo "-- Backup --"
  echo ">> just backup-app $APP"
  if just backup-app "$APP"; then
    echo "OK   Backup erfolgreich"
  else
    echo "FAIL Backup fehlgeschlagen - Abbruch ohne Container-Eingriff" >&2
    exit 2
  fi

  # Verifizieren: Artefakt jetzt vorhanden und frisch
  if scripts/backup-age.sh --quiet "$APP"; then
    echo "OK   backup-age bestaetigt frisches Artefakt"
  else
    echo "FAIL backup-age findet kein frisches Artefakt - Abbruch" >&2
    exit 2
  fi
  echo

  # ---------------- Stop Root-Service(s) ----------------
  echo "-- Stop Root-Service --"
  ROOT_CMD=(docker compose -f compose.yml -f "$ROOT_MATCH_FILE")

  # Paperless-Sonderfall: 5 Services in Reihenfolge
  if [[ "$APP" == "paperless" ]]; then
    # Stop in dieser Reihenfolge (Webserver zuerst, DB zuletzt):
    PAPERLESS_STOP_ORDER=(paperless-webserver paperless-tika paperless-gotenberg paperless-redis paperless-db)
    for svc in "${PAPERLESS_STOP_ORDER[@]}"; do
      echo ">> ${ROOT_CMD[*]} stop $svc"
      if ! "${ROOT_CMD[@]}" stop "$svc"; then
        echo "FAIL stop $svc fehlgeschlagen" >&2
        exit 2
      fi
    done
    for svc in "${PAPERLESS_STOP_ORDER[@]}"; do
      echo ">> ${ROOT_CMD[*]} rm -f $svc  (keine Volumes!)"
      "${ROOT_CMD[@]}" rm -f "$svc" || echo "WARN rm -f $svc fehlgeschlagen"
    done
  else
    echo ">> ${ROOT_CMD[*]} stop $ROOT_SERVICE"
    if ! "${ROOT_CMD[@]}" stop "$ROOT_SERVICE"; then
      echo "FAIL stop fehlgeschlagen" >&2
      exit 2
    fi
    echo ">> ${ROOT_CMD[*]} rm -f $ROOT_SERVICE  (keine Volumes!)"
    if ! "${ROOT_CMD[@]}" rm -f "$ROOT_SERVICE"; then
      echo "WARN rm -f fehlgeschlagen - versuche trotzdem App-Start"
    fi
  fi
  echo

  # ---------------- App-Compose hochfahren ----------------
  echo "-- App-Compose hochfahren --"
  echo ">> just app-up $APP"
  APP_UP_FAIL=0
  if ! just app-up "$APP"; then
    echo "FAIL just app-up $APP schlug fehl"
    APP_UP_FAIL=1
  else
    echo "OK   App-Compose gestartet"
  fi

  # ---------------- Healthcheck-Loop ----------------
  HEALTH_OK=0
  if [[ $APP_UP_FAIL -eq 0 ]]; then
    # Paperless: laengere Defaults + Multi-Container-Check
    if [[ "$APP" == "paperless" ]]; then
      HC_TIMEOUT="${MIGRATE_HEALTH_TIMEOUT_SECONDS:-300}"
      HC_INTERVAL="${MIGRATE_HEALTH_INTERVAL_SECONDS:-10}"
    else
      HC_TIMEOUT="${MIGRATE_HEALTH_TIMEOUT_SECONDS:-60}"
      HC_INTERVAL="${MIGRATE_HEALTH_INTERVAL_SECONDS:-5}"
    fi
    HC_MAX_TRIES=$(( HC_TIMEOUT / HC_INTERVAL ))
    (( HC_MAX_TRIES < 1 )) && HC_MAX_TRIES=1
    echo
    echo "-- Healthcheck-Loop (bis ${HC_TIMEOUT}s, alle ${HC_INTERVAL}s, ${HC_MAX_TRIES} Versuche) --"

    paperless_multi_check() {
      # Alle 5 Container muessen running sein, webserver zusaetzlich http 200/302.
      local containers=(filehub-paperless-db filehub-paperless-redis filehub-paperless-tika filehub-paperless-gotenberg filehub-paperless-webserver)
      local all_ok=1
      for c in "${containers[@]}"; do
        if ! docker inspect "$c" >/dev/null 2>&1; then
          all_ok=0
          echo "    $c missing"
          continue
        fi
        local state health
        state="$(docker inspect --format '{{.State.Status}}' "$c" 2>/dev/null)"
        health="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$c" 2>/dev/null)"
        if [[ "$state" != "running" ]]; then
          all_ok=0
          echo "    $c state=$state (erwartet running)"
          continue
        fi
        if [[ "$health" != "healthy" && "$health" != "none" ]]; then
          all_ok=0
          echo "    $c health=$health (erwartet healthy)"
          continue
        fi
      done
      # HTTP-Probe webserver
      local port="${PAPERLESS_PORT:-8000}"
      local http_code
      http_code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "http://127.0.0.1:${port}/" 2>/dev/null || echo 000)"
      case "$http_code" in
        200|302)
          ;;
        *)
          all_ok=0
          echo "    webserver http=$http_code (erwartet 200/302)"
          ;;
      esac
      return $((1 - all_ok))
    }

    for ((i=1; i<=HC_MAX_TRIES; i++)); do
      if [[ "$APP" == "paperless" ]]; then
        if paperless_multi_check; then
          HEALTH_OK=1
          echo "OK   paperless multi-check bestanden (Versuch $i)"
          break
        fi
      else
        if just app-health "$APP" >/dev/null 2>&1; then
          HEALTH_OK=1
          echo "OK   app-health bestanden (Versuch $i)"
          break
        fi
      fi
      echo "INFO Versuch $i/$HC_MAX_TRIES: noch nicht healthy, warte ${HC_INTERVAL}s"
      sleep "$HC_INTERVAL"
    done
    if [[ $HEALTH_OK -ne 1 ]]; then
      echo "FAIL Healthcheck nicht bestanden innerhalb ${HC_TIMEOUT}s"
    fi
  fi

  # ---------------- Rollback wenn noetig ----------------
  if [[ $APP_UP_FAIL -ne 0 || $HEALTH_OK -ne 1 ]]; then
    echo
    echo "!! Migration fehlgeschlagen - ROLLBACK wird ausgefuehrt"
    echo "-- Rollback --"
    ROLLBACK_FAIL=0
    echo ">> just app-down $APP"
    if ! just app-down "$APP"; then
      echo "WARN just app-down $APP schlug fehl - fortsetzen"
    fi
    if [[ "$APP" == "paperless" ]]; then
      # Reverse-Order: db zuerst, webserver zuletzt
      PAPERLESS_START_ORDER=(paperless-db paperless-redis paperless-tika paperless-gotenberg paperless-webserver)
      for svc in "${PAPERLESS_START_ORDER[@]}"; do
        echo ">> ${ROOT_CMD[*]} up -d $svc"
        if ! "${ROOT_CMD[@]}" up -d "$svc"; then
          echo "FAIL Rollback up -d $svc fehlgeschlagen"
          ROLLBACK_FAIL=1
        fi
      done
      echo ">> Rollback-Healthcheck (paperless multi-check, max 60s)"
      for ((j=1; j<=12; j++)); do
        if paperless_multi_check >/dev/null 2>&1; then
          echo "OK   paperless wieder healthy aus Root-Compose (Versuch $j)"
          break
        fi
        sleep 5
      done
    else
      echo ">> ${ROOT_CMD[*]} up -d $ROOT_SERVICE"
      if ! "${ROOT_CMD[@]}" up -d "$ROOT_SERVICE"; then
        echo "FAIL Rollback up -d fehlgeschlagen"
        ROLLBACK_FAIL=1
      fi
      echo ">> Rollback-Healthcheck"
      sleep 5
      if just app-health "$APP" >/dev/null 2>&1; then
        echo "OK   App wieder healthy aus Root-Compose"
      else
        echo "WARN App nach Rollback nicht sofort healthy - manuell verifizieren"
      fi
    fi
    echo ">> just runtime-audit"
    scripts/runtime-audit.sh --quiet || true

    if [[ $ROLLBACK_FAIL -ne 0 ]]; then
      echo "FAIL Rollback fehlgeschlagen - MANUELLE NACHARBEIT NOETIG" >&2
      exit 3
    fi
    echo "INFO Rollback durchgefuehrt - urspruenglicher Stand wiederhergestellt"
    exit 2
  fi

  # ---------------- Post-Audit ----------------
  echo
  echo "-- Post-Audit --"
  echo ">> just runtime-audit"
  scripts/runtime-audit.sh --quiet || true
  echo ">> just migration-status (Auszug $APP)"
  scripts/migration-status.sh --quiet 2>/dev/null | grep -E "^($APP\b|APP\b)" || scripts/migration-status.sh 2>/dev/null | grep -E "^($APP\b|APP\b)" || true

  echo
  echo "=== migrate-app EXECUTE: $APP ABGESCHLOSSEN ==="
  echo "OK   $APP laeuft jetzt aus apps/$APP/compose.yml"
  echo "INFO Root-Compose-Datei $ROOT_MATCH_FILE bleibt als Rollback-Reserve im Repo"
  exit 0
fi

# Sollte nie erreicht werden
echo "ERROR: interner Fehler - unerwarteter Modus $MODE" >&2
exit 1
