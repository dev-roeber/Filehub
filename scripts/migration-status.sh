#!/usr/bin/env bash
# Filehub Migration-Status.
#
# Zweck:
#   Pro App in config/apps.yml anzeigen, ob der Container aktuell aus dem
#   Root-Compose oder aus der modularen apps/<id>/compose.yml betrieben wird.
#   Read-only. Es werden ausschliesslich `docker ps`, `docker inspect` und
#   `grep` genutzt - keinerlei docker compose up/down/restart/stop.
#
# Usage:
#   scripts/migration-status.sh [--quiet] [--json]
#
# Optionen:
#   --quiet  Nur Tabelle und Summary, keine begleitenden WARN/FAIL/INFO-Zeilen
#   --json   JSON-Struktur statt Tabelle
#
# Exit-Codes:
#   0  keine WARNs und keine FAILs
#   1  WARNs (aber keine FAILs)
#   2  FAILs (z.B. Docker nicht erreichbar)
#
# Kommentare und Ausgaben bewusst ASCII-only (kein Umlaut).

set -uo pipefail
cd "$(dirname "$0")/.."

QUIET=0
JSON=0
for arg in "$@"; do
  case "$arg" in
    --quiet) QUIET=1 ;;
    --json)  JSON=1 ;;
    -h|--help)
      sed -n '1,25p' "$0"
      exit 0
      ;;
    *)
      echo "Unbekanntes Argument: $arg" >&2
      exit 2
      ;;
  esac
done

WARN_COUNT=0
FAIL_COUNT=0
APPS_CHECKED=0
RUN_APP=0
RUN_ROOT=0
RUN_UNKNOWN=0
SAFE_YES=0
SAFE_WARN=0
SAFE_NO=0

# Sammelpuffer fuer Tabelle und JSON
PREMSG=()      # vor jeder Tabellenzeile: optional 1 Zeile
ROWS=()        # finale Tabellenzeilen
JSON_APPS=()   # JSON-Eintraege pro App
GROUP_LINES=() # Sondergruppen-Output

# ---------------------------------------------------------------------------
# Docker-Erreichbarkeit
# ---------------------------------------------------------------------------
if ! docker info >/dev/null 2>&1; then
  echo "FAIL docker daemon nicht erreichbar - Migration-Status abgebrochen" >&2
  if [[ $JSON -eq 1 ]]; then
    cat <<JSON
{"summary":{"apps_checked":0,"running_app":0,"running_root":0,"unknown_none":0,"safe_yes":0,"safe_warn":0,"safe_no":0,"warn":0,"fail":1},"apps":[]}
JSON
  else
    echo "---"
    echo "Apps geprueft: 0"
    echo "running app-source: 0"
    echo "running root-source: 0"
    echo "unknown/none: 0"
    echo "safe=yes: 0"
    echo "safe=warn: 0"
    echo "safe=no: 0"
    echo "WARN: 0"
    echo "FAIL: 1"
  fi
  exit 2
fi

REGISTRY="config/apps.yml"
if [[ ! -f "$REGISTRY" ]]; then
  echo "FAIL $REGISTRY fehlt" >&2
  exit 2
fi

# ---------------------------------------------------------------------------
# Registry parsen (App-IDs)
# ---------------------------------------------------------------------------
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

# ---------------------------------------------------------------------------
# Root-Compose-Files einsammeln: container_name -> dateiname
# ---------------------------------------------------------------------------
shopt -s nullglob
ROOT_COMPOSES=(compose.yml compose.*.yml)
shopt -u nullglob

declare -A ROOT_HAS  # container_name -> "file1 file2"
for rc in "${ROOT_COMPOSES[@]}"; do
  [[ -f "$rc" ]] || continue
  while IFS= read -r line; do
    n="$(echo "$line" | sed -E 's/^[[:space:]]*container_name:[[:space:]]*//; s/[[:space:]]*$//')"
    [[ -z "$n" ]] && continue
    ROOT_HAS[$n]="${ROOT_HAS[$n]:-}$rc "
  done < <(grep -E "^[[:space:]]*container_name:" "$rc" 2>/dev/null)
done

# ---------------------------------------------------------------------------
# Helper: truncate string
# ---------------------------------------------------------------------------
truncate_str() {
  local s="$1" maxlen="$2"
  if (( ${#s} > maxlen )); then
    echo "${s:0:$((maxlen-1))}~"
  else
    echo "$s"
  fi
}

# JSON-Escape (Backslash, dann Quote)
json_esc() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  printf '%s' "$s"
}

# Parse PortBindings JSON aus docker inspect zu "host:cont,host:cont"
parse_ports() {
  local bindings="$1"
  # Format: map[8000/tcp:[{127.0.0.1 8000}] 9001/tcp:[{ 9001}]]
  # Wir nutzen --format '{{json .HostConfig.PortBindings}}' fuer JSON.
  if [[ -z "$bindings" || "$bindings" == "null" || "$bindings" == "{}" ]]; then
    echo ""
    return
  fi
  python3 - <<PY "$bindings"
import json, sys
try:
    data = json.loads(sys.argv[1])
except Exception:
    print("")
    sys.exit(0)
parts = []
if not data:
    print("")
    sys.exit(0)
for cport, binds in data.items():
    cnum = cport.split("/")[0]
    if not binds:
        continue
    for b in binds:
        hip = b.get("HostIp","") or ""
        hp  = b.get("HostPort","") or ""
        if hip and hip not in ("0.0.0.0","::"):
            parts.append(f"{hip}:{hp}->{cnum}")
        else:
            parts.append(f"{hp}->{cnum}")
print(",".join(parts))
PY
}

# ---------------------------------------------------------------------------
# Per-App Auswertung
# ---------------------------------------------------------------------------
for id in "${APP_IDS[@]}"; do
  APPS_CHECKED=$((APPS_CHECKED+1))
  app_compose="apps/$id/compose.yml"

  pre=""    # begleitende Zeile (max 1)
  row_app="$id"
  row_container="-"
  row_run="missing"
  row_health="-"
  row_source="none"
  row_ports=""
  row_safe="no"

  if [[ ! -f "$app_compose" ]]; then
    FAIL_COUNT=$((FAIL_COUNT+1))
    pre="FAIL $id $app_compose fehlt"
    row_safe="no"; SAFE_NO=$((SAFE_NO+1))
    RUN_UNKNOWN=$((RUN_UNKNOWN+1))
    ROWS+=("$(printf '%-15s %-31s %-4s %-9s %-7s %-27s %s' "$row_app" "$row_container" "$row_run" "$row_health" "$row_source" "$(truncate_str "$row_ports" 27)" "$row_safe")")
    PREMSG+=("$pre")
    JSON_APPS+=("{\"app\":\"$(json_esc "$id")\",\"container\":\"\",\"run\":\"$row_run\",\"health\":\"$row_health\",\"source\":\"$row_source\",\"ports\":\"\",\"safe\":\"$row_safe\",\"note\":\"$(json_esc "$pre")\"}")
    continue
  fi

  # container_name(s) aus app-compose
  names=()
  while IFS= read -r line; do
    n="$(echo "$line" | sed -E 's/^[[:space:]]*container_name:[[:space:]]*//; s/[[:space:]]*$//')"
    [[ -z "$n" ]] && continue
    names+=("$n")
  done < <(grep -E "^[[:space:]]*container_name:" "$app_compose")

  if (( ${#names[@]} == 0 )); then
    WARN_COUNT=$((WARN_COUNT+1))
    pre="WARN $id $app_compose enthaelt keinen container_name"
    row_container="-"
    row_safe="warn"; SAFE_WARN=$((SAFE_WARN+1))
    RUN_UNKNOWN=$((RUN_UNKNOWN+1))
    ROWS+=("$(printf '%-15s %-31s %-4s %-9s %-7s %-27s %s' "$row_app" "$row_container" "$row_run" "$row_health" "$row_source" "$(truncate_str "$row_ports" 27)" "$row_safe")")
    PREMSG+=("$pre")
    JSON_APPS+=("{\"app\":\"$(json_esc "$id")\",\"container\":\"\",\"run\":\"$row_run\",\"health\":\"$row_health\",\"source\":\"$row_source\",\"ports\":\"\",\"safe\":\"$row_safe\",\"note\":\"$(json_esc "$pre")\"}")
    continue
  fi

  primary="${names[0]}"
  extra_count=$(( ${#names[@]} - 1 ))
  if (( extra_count > 0 )); then
    row_container="$primary (+$extra_count)"
  else
    row_container="$primary"
  fi

  # root_match: primaerer Container in einem Root-Compose?
  root_match="no"
  if [[ -n "${ROOT_HAS[$primary]:-}" ]]; then
    root_match="yes"
  fi

  # docker inspect des primaeren Containers
  if docker inspect "$primary" >/dev/null 2>&1; then
    state="$(docker inspect --format '{{.State.Status}}' "$primary" 2>/dev/null)"
    health="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$primary" 2>/dev/null)"
    cfg_files="$(docker inspect --format '{{index .Config.Labels "com.docker.compose.project.config_files"}}' "$primary" 2>/dev/null)"
    port_json="$(docker inspect --format '{{json .HostConfig.PortBindings}}' "$primary" 2>/dev/null)"
    ports_str="$(parse_ports "$port_json")"

    if [[ "$state" == "running" ]]; then
      row_run="yes"
    else
      row_run="no"
    fi
    row_health="${health:-none}"
    row_ports="$ports_str"

    # Source aus config_files ermitteln
    if [[ -n "$cfg_files" ]]; then
      if echo "$cfg_files" | grep -qE "(^|[,/[:space:]])$app_compose([,[:space:]]|$)"; then
        row_source="app"
      elif echo "$cfg_files" | grep -qE "(^|[,/[:space:]])compose(\.[a-z0-9-]+)?\.yml([,[:space:]]|$)"; then
        # Pfad endet auf compose*.yml direkt (Repo-Root, also kein apps/)
        if echo "$cfg_files" | grep -qE "/apps/"; then
          row_source="unknown"
        else
          row_source="root"
        fi
      else
        row_source="unknown"
      fi
    else
      row_source="unknown"
    fi
  else
    row_run="missing"
    row_health="-"
    row_source="none"
    row_ports=""
  fi

  # Zaehler running-source
  if [[ "$row_run" == "yes" ]]; then
    case "$row_source" in
      app)  RUN_APP=$((RUN_APP+1)) ;;
      root) RUN_ROOT=$((RUN_ROOT+1)) ;;
      *)    RUN_UNKNOWN=$((RUN_UNKNOWN+1)) ;;
    esac
  fi

  # Safe-to-migrate Logik
  safe="yes"
  reason=""
  if [[ "$row_run" == "missing" ]]; then
    safe="no"
    reason="Container $primary existiert nicht - nichts zu migrieren"
  elif [[ "$row_source" == "app" ]]; then
    safe="no"
    reason="bereits aus apps/$id/compose.yml betrieben"
  else
    if [[ "$row_health" == "unhealthy" || "$row_health" == "starting" ]]; then
      safe="warn"
      reason="Health=$row_health"
    fi
    if [[ ! -f "apps/$id/backup.include" ]]; then
      safe="warn"
      reason="apps/$id/backup.include fehlt"
    fi
    if [[ "$root_match" == "no" ]]; then
      safe="warn"
      reason="kein Root-Compose-Match fuer $primary (kein Rollback-Netz)"
    fi
  fi

  row_safe="$safe"
  case "$safe" in
    yes)  SAFE_YES=$((SAFE_YES+1)) ;;
    warn) SAFE_WARN=$((SAFE_WARN+1)); WARN_COUNT=$((WARN_COUNT+1)) ;;
    no)   SAFE_NO=$((SAFE_NO+1));
          # 'no' ist nicht zwingend FAIL - es ist eine Aussage
          ;;
  esac

  # Begleitende Zeile zusammensetzen
  if [[ "$safe" == "warn" ]]; then
    pre="WARN $id $reason"
  elif [[ "$safe" == "no" && -n "$reason" ]]; then
    if [[ "$row_run" == "missing" ]]; then
      pre="WARN $id $reason"
      WARN_COUNT=$((WARN_COUNT+1))
    else
      pre="INFO $id $reason"
    fi
  fi

  ROWS+=("$(printf '%-15s %-31s %-4s %-9s %-7s %-27s %s' \
    "$row_app" "$row_container" "$row_run" "$row_health" "$row_source" \
    "$(truncate_str "$row_ports" 27)" "$row_safe")")
  PREMSG+=("$pre")

  JSON_APPS+=("{\"app\":\"$(json_esc "$id")\",\"container\":\"$(json_esc "$primary")\",\"container_count\":${#names[@]},\"run\":\"$row_run\",\"health\":\"$row_health\",\"source\":\"$row_source\",\"root_match\":\"$root_match\",\"ports\":\"$(json_esc "$row_ports")\",\"safe\":\"$row_safe\",\"note\":\"$(json_esc "$pre")\"}")
done

# ---------------------------------------------------------------------------
# Sondergruppen: Paperless-Begleiter, Authentik
# ---------------------------------------------------------------------------
PAPERLESS_HELPERS=(filehub-paperless-db filehub-paperless-redis filehub-paperless-tika filehub-paperless-gotenberg)
AUTHENTIK_CONTAINERS=(filehub-authentik-server filehub-authentik-worker filehub-authentik-redis filehub-authentik-db)

# Was steht in apps/paperless/compose.yml?
declare -A PAPERLESS_APP_NAMES
if [[ -f apps/paperless/compose.yml ]]; then
  while IFS= read -r line; do
    n="$(echo "$line" | sed -E 's/^[[:space:]]*container_name:[[:space:]]*//; s/[[:space:]]*$//')"
    [[ -z "$n" ]] && continue
    PAPERLESS_APP_NAMES[$n]=1
  done < <(grep -E "^[[:space:]]*container_name:" apps/paperless/compose.yml)
fi

GROUP_HEADER_PAPERLESS=0
for c in "${PAPERLESS_HELPERS[@]}"; do
  if docker inspect "$c" >/dev/null 2>&1; then
    state="$(docker inspect --format '{{.State.Status}}' "$c" 2>/dev/null)"
    health="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$c" 2>/dev/null)"
    cfg_files="$(docker inspect --format '{{index .Config.Labels "com.docker.compose.project.config_files"}}' "$c" 2>/dev/null)"
    src="unknown"
    if echo "$cfg_files" | grep -qE "apps/paperless/compose\.yml"; then
      src="app"
    elif [[ -n "$cfg_files" ]]; then
      src="root"
    fi
    in_app_compose="no"
    [[ -n "${PAPERLESS_APP_NAMES[$c]:-}" ]] && in_app_compose="yes"
    if (( GROUP_HEADER_PAPERLESS == 0 )); then
      GROUP_LINES+=("=== Paperless-Begleitcontainer (Sonderfall) ===")
      GROUP_HEADER_PAPERLESS=1
    fi
    GROUP_LINES+=("$(printf '%-32s state=%-8s health=%-9s source=%-7s in-app-compose=%s' "$c" "$state" "$health" "$src" "$in_app_compose")")
    if [[ "$state" == "running" && "$in_app_compose" == "no" ]]; then
      GROUP_LINES+=("INFO paperless $c laeuft aus Root-Compose, nicht in apps/paperless/compose.yml referenziert - Migration erfordert Sonderbehandlung")
    fi
  fi
done

GROUP_HEADER_AUTH=0
for c in "${AUTHENTIK_CONTAINERS[@]}"; do
  if docker inspect "$c" >/dev/null 2>&1; then
    state="$(docker inspect --format '{{.State.Status}}' "$c" 2>/dev/null)"
    health="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$c" 2>/dev/null)"
    cfg_files="$(docker inspect --format '{{index .Config.Labels "com.docker.compose.project.config_files"}}' "$c" 2>/dev/null)"
    src="unknown"
    if echo "$cfg_files" | grep -qE "infra/authentik"; then
      src="infra"
    elif [[ -n "$cfg_files" ]]; then
      src="root"
    fi
    if (( GROUP_HEADER_AUTH == 0 )); then
      GROUP_LINES+=("=== Authentik (separate Migrationsphase) ===")
      GROUP_HEADER_AUTH=1
    fi
    GROUP_LINES+=("$(printf '%-32s state=%-8s health=%-9s source=%s' "$c" "$state" "$health" "$src")")
  fi
done
if (( GROUP_HEADER_AUTH == 1 )); then
  GROUP_LINES+=("INFO authentik separate Migrationsphase - kein safe-Marker hier")
fi

# ---------------------------------------------------------------------------
# Ausgabe
# ---------------------------------------------------------------------------
if [[ $JSON -eq 1 ]]; then
  joined=""
  for a in "${JSON_APPS[@]}"; do
    [[ -n "$joined" ]] && joined+=","
    joined+="$a"
  done
  cat <<JSON
{
  "summary": {
    "apps_checked": $APPS_CHECKED,
    "running_app": $RUN_APP,
    "running_root": $RUN_ROOT,
    "unknown_none": $RUN_UNKNOWN,
    "safe_yes": $SAFE_YES,
    "safe_warn": $SAFE_WARN,
    "safe_no": $SAFE_NO,
    "warn": $WARN_COUNT,
    "fail": $FAIL_COUNT
  },
  "apps": [$joined]
}
JSON
else
  # Tabellen-Header
  printf '%-15s %-31s %-4s %-9s %-7s %-27s %s\n' "APP" "CONTAINER" "RUN" "HEALTH" "SOURCE" "PORTS" "SAFE"
  printf -- '-%.0s' {1..100}; echo
  for i in "${!ROWS[@]}"; do
    if [[ $QUIET -eq 0 && -n "${PREMSG[$i]:-}" ]]; then
      echo "${PREMSG[$i]}"
    fi
    echo "${ROWS[$i]}"
  done

  if (( ${#GROUP_LINES[@]} > 0 )); then
    echo
    for l in "${GROUP_LINES[@]}"; do
      echo "$l"
    done
  fi

  echo "---"
  echo "Apps geprueft: $APPS_CHECKED"
  echo "running app-source: $RUN_APP"
  echo "running root-source: $RUN_ROOT"
  echo "unknown/none: $RUN_UNKNOWN"
  echo "safe=yes: $SAFE_YES"
  echo "safe=warn: $SAFE_WARN"
  echo "safe=no: $SAFE_NO"
  echo "WARN: $WARN_COUNT"
  echo "FAIL: $FAIL_COUNT"
fi

if (( FAIL_COUNT > 0 )); then
  exit 2
fi
if (( WARN_COUNT > 0 )); then
  exit 1
fi
exit 0
