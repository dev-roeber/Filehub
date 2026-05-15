#!/usr/bin/env bash
# Filehub Runtime-Audit.
#
# Zweck:
#   Drift-Pruefung zwischen config/apps.yml (Registry), den modularen
#   apps/<id>/compose.yml-Dateien, den Root-Compose-Dateien und den
#   tatsaechlich laufenden Docker-Containern. Read-only - keine
#   docker stop/restart/up-Operationen.
#
# Usage:
#   scripts/runtime-audit.sh [--quiet] [--strict] [--json]
#
# Optionen:
#   --quiet    OK- und INFO-Zeilen unterdruecken
#   --strict   WARN -> non-zero exit
#   --json     einfache JSON-Struktur (summary + findings) statt Plain-Output
#
# Exit-Codes:
#   0  keine FAILs (und im Nicht-strict-Modus auch WARN erlaubt)
#   1  --strict: WARN>0 oder FAIL>0
#   2  FAIL>0 (auch ohne --strict) oder Docker nicht erreichbar
#
# Kommentare und Ausgaben bewusst ASCII-only (kein Umlaut).

set -uo pipefail
cd "$(dirname "$0")/.."

QUIET=0
STRICT=0
JSON=0
for arg in "$@"; do
  case "$arg" in
    --quiet)  QUIET=1 ;;
    --strict) STRICT=1 ;;
    --json)   JSON=1 ;;
    -h|--help)
      sed -n '1,30p' "$0"
      exit 0
      ;;
    *)
      echo "Unbekanntes Argument: $arg" >&2
      exit 2
      ;;
  esac
done

# ---------------------------------------------------------------------------
# Sammelstrukturen
# ---------------------------------------------------------------------------
OK_COUNT=0
INFO_COUNT=0
WARN_COUNT=0
FAIL_COUNT=0
APPS_CHECKED=0
COMPOSES_CHECKED=0
CONTAINERS_CHECKED=0

FINDINGS=()

emit() {
  # $1 = level, $2 = namespace, $3 = detail
  local level="$1" ns="$2" detail="$3"
  case "$level" in
    OK)   OK_COUNT=$((OK_COUNT+1));   [[ $QUIET -eq 1 || $JSON -eq 1 ]] || echo "OK   $ns $detail" ;;
    INFO) INFO_COUNT=$((INFO_COUNT+1)); [[ $QUIET -eq 1 || $JSON -eq 1 ]] || echo "INFO $ns $detail" ;;
    WARN) WARN_COUNT=$((WARN_COUNT+1)); [[ $JSON -eq 1 ]] || echo "WARN $ns $detail" ;;
    FAIL) FAIL_COUNT=$((FAIL_COUNT+1)); [[ $JSON -eq 1 ]] || echo "FAIL $ns $detail" ;;
  esac
  if [[ $JSON -eq 1 ]]; then
    # JSON-sicheres Escape (Backslash, dann Quotes)
    local d="${detail//\\/\\\\}"
    d="${d//\"/\\\"}"
    FINDINGS+=("{\"level\":\"$level\",\"ns\":\"$ns\",\"detail\":\"$d\"}")
  fi
}

# ---------------------------------------------------------------------------
# 1) Docker-Erreichbarkeit
# ---------------------------------------------------------------------------
if ! docker info >/dev/null 2>&1; then
  echo "FAIL docker daemon nicht erreichbar - Audit abgebrochen"
  echo "---"
  echo "Apps geprueft: 0"
  echo "Compose-Dateien geprueft: 0"
  echo "Container geprueft: 0"
  echo "OK:   0"
  echo "INFO: 0"
  echo "WARN: 0"
  echo "FAIL: 1"
  exit 2
fi

REGISTRY="config/apps.yml"
if [[ ! -f "$REGISTRY" ]]; then
  emit FAIL registry "$REGISTRY fehlt"
  echo "---"
  echo "FAIL: $FAIL_COUNT"
  exit 2
fi

# ---------------------------------------------------------------------------
# 2) Registry parsen (Stil analog scripts/registry-audit.sh)
# Ausgabe: id|port|default_enabled
# ---------------------------------------------------------------------------
PARSED="$(python3 - <<'PY'
import re, pathlib
text = pathlib.Path("config/apps.yml").read_text()
section = None
current = None
records = []

def flush():
    global current
    if current and current.get("id"):
        records.append(current)
    current = None

for line in text.splitlines():
    if line.startswith("apps:"):
        flush(); section = "apps"; continue
    if line.startswith("infra:"):
        flush(); section = "infra"; continue
    if section is None:
        continue
    m = re.match(r"\s+-\s+id:\s*(\S+)\s*$", line)
    if m:
        flush()
        current = {"section": section, "id": m.group(1)}
        continue
    if current is None:
        continue
    for key in ("port", "default_enabled"):
        m = re.match(rf"\s+{key}:\s*(.+?)\s*$", line)
        if m:
            current[key] = m.group(1).strip()
            break

flush()

for r in records:
    if r.get("section") != "apps":
        continue
    print("|".join([
        r.get("id",""),
        r.get("port",""),
        r.get("default_enabled",""),
    ]))
PY
)"

declare -A REG_PORT
declare -A REG_ENABLED
APP_IDS=()
while IFS='|' read -r id port enabled; do
  [[ -z "$id" ]] && continue
  APP_IDS+=("$id")
  REG_PORT[$id]="$port"
  REG_ENABLED[$id]="$enabled"
done <<< "$PARSED"

APPS_CHECKED=${#APP_IDS[@]}

# ---------------------------------------------------------------------------
# 3) Compose validieren + 4) Container-Namen + 6) Port-Bindings extrahieren
# ---------------------------------------------------------------------------
declare -A APP_CONTAINERS    # id -> "c1 c2 c3"
declare -A APP_HOSTPORT      # id -> erster gefundener Hostport
declare -A CONTAINER_OWNER   # container_name -> "appid"

ENV_FILE_ARG=()
if [[ -f ".env" ]]; then
  ENV_FILE_ARG=(--env-file .env)
else
  emit WARN env ".env fehlt - compose config ohne env-file"
fi

for id in "${APP_IDS[@]}"; do
  cfile="apps/$id/compose.yml"
  if [[ ! -f "$cfile" ]]; then
    emit FAIL compose "$cfile fehlt"
    continue
  fi
  COMPOSES_CHECKED=$((COMPOSES_CHECKED+1))

  if docker compose "${ENV_FILE_ARG[@]}" -f "$cfile" config -q >/dev/null 2>&1; then
    emit OK compose "$cfile validiert"
  else
    err="$(docker compose "${ENV_FILE_ARG[@]}" -f "$cfile" config -q 2>&1 | head -1)"
    emit FAIL compose "$cfile invalide: $err"
  fi

  # container_name extrahieren
  names=""
  while IFS= read -r line; do
    n="$(echo "$line" | sed -E 's/^[[:space:]]*container_name:[[:space:]]*//; s/[[:space:]]*$//')"
    [[ -z "$n" ]] && continue
    names+="$n "
    # Konfliktcheck App <-> App
    if [[ -n "${CONTAINER_OWNER[$n]:-}" ]]; then
      emit FAIL container "container_name '$n' doppelt: $id und ${CONTAINER_OWNER[$n]}"
    else
      CONTAINER_OWNER[$n]="$id"
    fi
  done < <(grep -E "^[[:space:]]*container_name:" "$cfile")
  APP_CONTAINERS[$id]="${names% }"

  # Hostport-Bindings pruefen
  # Wir nehmen den ersten Eintrag unter 'ports:' bis zur naechsten unindentierten Sektion.
  ports_block="$(awk '
    /^[[:space:]]+ports:[[:space:]]*$/ { inb=1; next }
    inb && /^[[:space:]]*-[[:space:]]/ { print; next }
    inb && /^[[:space:]]*[a-zA-Z]/ { inb=0 }
  ' "$cfile")"

  hostport=""
  while IFS= read -r pline; do
    [[ -z "$pline" ]] && continue
    # Quotes weg, Whitespace weg
    raw="$(echo "$pline" | sed -E 's/^[[:space:]]*-[[:space:]]*//; s/^"//; s/"$//')"
    if [[ "$raw" == 0.0.0.0:* ]]; then
      emit FAIL ports "$cfile bind 0.0.0.0 explizit: $raw"
    fi
    # Default-Substitution aufloesen: ${VAR:-NNNN} -> NNNN
    resolved="$(echo "$raw" | sed -E 's/\$\{[A-Za-z_][A-Za-z0-9_]*:-([0-9]+)\}/\1/g')"
    if [[ "$resolved" == 127.0.0.1:* ]]; then
      # 127.0.0.1:HOST:CONT
      hp="$(echo "$resolved" | cut -d: -f2)"
      [[ -z "$hostport" ]] && hostport="$hp"
    elif [[ "$resolved" =~ ^[0-9]+:[0-9]+ ]]; then
      # Form HOST:CONT ohne IP-Praefix -> WARN
      emit WARN ports "$cfile bind ohne 127.0.0.1-Praefix: $raw"
      hp="$(echo "$resolved" | cut -d: -f1)"
      [[ -z "$hostport" ]] && hostport="$hp"
    fi
  done <<< "$ports_block"

  APP_HOSTPORT[$id]="$hostport"

  # 7) Registry-Port vs Compose-Port
  rp="${REG_PORT[$id]:-}"
  if [[ -z "$hostport" ]]; then
    if [[ -n "$rp" ]]; then
      emit WARN ports "apps/$id Registry-Port=$rp aber kein Hostport-Bind in $cfile"
    fi
  else
    if [[ -z "$rp" ]]; then
      emit WARN ports "apps/$id Registry-Port fehlt, compose bindet $hostport"
    elif [[ "$rp" != "$hostport" ]]; then
      emit FAIL ports "apps/$id Registry-Port=$rp != Compose-Hostport=$hostport"
    else
      emit OK ports "apps/$id Port $hostport konsistent"
    fi
  fi
done

# ---------------------------------------------------------------------------
# 5b) Konfliktcheck App-Compose <-> Root-Compose (erwartet -> INFO)
# ---------------------------------------------------------------------------
shopt -s nullglob
ROOT_COMPOSES=(compose.yml compose.*.yml)
shopt -u nullglob

declare -A ROOT_CONTAINERS  # name -> "file1 file2"
for rc in "${ROOT_COMPOSES[@]}"; do
  [[ -f "$rc" ]] || continue
  while IFS= read -r line; do
    n="$(echo "$line" | sed -E 's/^[[:space:]]*container_name:[[:space:]]*//; s/[[:space:]]*$//')"
    [[ -z "$n" ]] && continue
    ROOT_CONTAINERS[$n]="${ROOT_CONTAINERS[$n]:-}$rc "
  done < <(grep -E "^[[:space:]]*container_name:" "$rc" 2>/dev/null)
done

for cname in "${!CONTAINER_OWNER[@]}"; do
  if [[ -n "${ROOT_CONTAINERS[$cname]:-}" ]]; then
    emit INFO container "$cname auch in Root-Compose (${ROOT_CONTAINERS[$cname]% }) - erwartete Kompatibilitaet"
  fi
done

# ---------------------------------------------------------------------------
# 9) Authentik-Sondercheck (AUTHENTIK_ENABLED)
# ---------------------------------------------------------------------------
AUTH_ENABLED=""
if [[ -f .env ]] && grep -qE "^AUTHENTIK_ENABLED=" .env; then
  AUTH_ENABLED="$(grep -E "^AUTHENTIK_ENABLED=" .env | tail -1 | cut -d= -f2- | tr -d '"' | tr -d "'" | tr '[:upper:]' '[:lower:]')"
elif [[ -f .env.example ]] && grep -qE "^AUTHENTIK_ENABLED=" .env.example; then
  AUTH_ENABLED="$(grep -E "^AUTHENTIK_ENABLED=" .env.example | tail -1 | cut -d= -f2- | tr -d '"' | tr -d "'" | tr '[:upper:]' '[:lower:]')"
fi
[[ -z "$AUTH_ENABLED" ]] && AUTH_ENABLED="false"

# ---------------------------------------------------------------------------
# 8) Laufende Container einlesen
# ---------------------------------------------------------------------------
PS_RAW="$(docker ps --format '{{.Names}}'$'\t''{{.State}}'$'\t''{{.Status}}' 2>/dev/null)"
PS_PORTS="$(docker ps --format '{{.Names}}'$'\t''{{.Ports}}' 2>/dev/null)"

declare -A RUN_STATE
declare -A RUN_STATUS
declare -A RUN_PORTS
RUNNING_FILEHUB=()

while IFS=$'\t' read -r name state status; do
  [[ -z "$name" ]] && continue
  RUN_STATE[$name]="$state"
  RUN_STATUS[$name]="$status"
  if [[ "$name" == filehub-* ]]; then
    RUNNING_FILEHUB+=("$name")
  fi
done <<< "$PS_RAW"

while IFS=$'\t' read -r name ports; do
  [[ -z "$name" ]] && continue
  RUN_PORTS[$name]="$ports"
done <<< "$PS_PORTS"

CONTAINERS_CHECKED=${#RUNNING_FILEHUB[@]}

# Authentik-Container-Set
is_authentik() {
  case "$1" in
    filehub-authentik-server|filehub-authentik-worker|filehub-authentik-redis|filehub-authentik-db|filehub-authentik-postgres)
      return 0 ;;
    *) return 1 ;;
  esac
}

# Erwartete Container pro App pruefen
for id in "${APP_IDS[@]}"; do
  enabled="${REG_ENABLED[$id]:-true}"
  for cname in ${APP_CONTAINERS[$id]:-}; do
    state="${RUN_STATE[$cname]:-}"
    status="${RUN_STATUS[$cname]:-}"
    if [[ -z "$state" ]]; then
      if [[ "$enabled" == "true" ]]; then
        emit WARN container "$cname (apps/$id) ist default_enabled, laeuft aber nicht"
      else
        emit INFO container "$cname (apps/$id) nicht aktiv (default_enabled=$enabled)"
      fi
      continue
    fi
    # Status-Bewertung
    if [[ "$status" == *"(unhealthy)"* ]]; then
      emit FAIL container "$cname unhealthy ($status)"
    elif [[ "$status" == *"(health: starting)"* ]]; then
      emit WARN container "$cname health: starting ($status)"
    elif [[ "$status" == *"(healthy)"* ]]; then
      emit OK container "$cname healthy"
    else
      emit INFO container "$cname laeuft ohne Healthcheck-Status ($status)"
    fi
  done
done

# Container, die laufen aber zu keiner App-Compose gehoeren
for name in "${RUNNING_FILEHUB[@]}"; do
  if [[ -z "${CONTAINER_OWNER[$name]:-}" ]]; then
    if is_authentik "$name" || [[ "$name" == filehub-gateway ]]; then
      # Authentik/Gateway gehoeren zu Infra, eigene Behandlung
      continue
    fi
    emit WARN container "$name laeuft, ist aber in keiner apps/<id>/compose.yml registriert"
  fi
done

# Authentik-Sonderlogik
auth_any_running=0
for n in filehub-authentik-server filehub-authentik-worker filehub-authentik-redis filehub-authentik-db filehub-authentik-postgres; do
  if [[ -n "${RUN_STATE[$n]:-}" ]]; then
    auth_any_running=1
    break
  fi
done

if [[ "$AUTH_ENABLED" == "false" ]]; then
  if (( auth_any_running == 1 )); then
    emit WARN authentik "AUTHENTIK_ENABLED=false, aber Authentik-Container laufen (Phase-1-Bootstrap-Kompatibilitaet)"
  else
    emit OK authentik "AUTHENTIK_ENABLED=false, keine Authentik-Container aktiv"
  fi
else
  if (( auth_any_running == 0 )); then
    emit WARN authentik "AUTHENTIK_ENABLED=true, aber keine Authentik-Container aktiv"
  else
    emit OK authentik "AUTHENTIK_ENABLED=true und Authentik laeuft"
  fi
fi

# ---------------------------------------------------------------------------
# 10) 0.0.0.0-Bindings auf laufenden App-Containern
# ---------------------------------------------------------------------------
for name in "${RUNNING_FILEHUB[@]}"; do
  is_authentik "$name" && continue
  pstr="${RUN_PORTS[$name]:-}"
  if [[ "$pstr" == *"0.0.0.0:"* ]]; then
    emit FAIL ports "$name bindet auf 0.0.0.0 ($pstr)"
  fi
done

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
if [[ $JSON -eq 1 ]]; then
  # findings als JSON-Array zusammensetzen
  joined=""
  for f in "${FINDINGS[@]}"; do
    [[ -n "$joined" ]] && joined+=","
    joined+="$f"
  done
  cat <<JSON
{
  "summary": {
    "apps_checked": $APPS_CHECKED,
    "composes_checked": $COMPOSES_CHECKED,
    "containers_checked": $CONTAINERS_CHECKED,
    "ok": $OK_COUNT,
    "info": $INFO_COUNT,
    "warn": $WARN_COUNT,
    "fail": $FAIL_COUNT
  },
  "findings": [$joined]
}
JSON
else
  echo "---"
  echo "Apps geprueft: $APPS_CHECKED"
  echo "Compose-Dateien geprueft: $COMPOSES_CHECKED"
  echo "Container geprueft: $CONTAINERS_CHECKED"
  echo "OK:   $OK_COUNT"
  echo "INFO: $INFO_COUNT"
  echo "WARN: $WARN_COUNT"
  echo "FAIL: $FAIL_COUNT"
fi

# Exit-Code
if (( FAIL_COUNT > 0 )); then
  exit 2
fi
if (( STRICT == 1 )) && (( WARN_COUNT > 0 )); then
  exit 1
fi
exit 0
