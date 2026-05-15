#!/usr/bin/env bash
# Filehub Registry-Audit.
# Konsistenzpruefung zwischen config/apps.yml und Dateisystem.
# Nutzung:
#   scripts/registry-audit.sh [--quiet]
#
# Exit-Code 0 wenn keine FAILs (auch bei WARNs), sonst 1.
# Kommentare bewusst ohne Umlaute (ASCII) analog zum Bestand.

set -euo pipefail
cd "$(dirname "$0")/.."

QUIET=0
for arg in "$@"; do
  case "$arg" in
    --quiet) QUIET=1 ;;
    -h|--help)
      echo "Usage: $0 [--quiet]"
      exit 0
      ;;
    *)
      echo "Unbekanntes Argument: $arg" >&2
      exit 2
      ;;
  esac
done

REGISTRY="config/apps.yml"

# Existenz pruefen
if [[ ! -f "$REGISTRY" ]]; then
  echo "FAIL $REGISTRY existiert nicht"
  echo "---"
  echo "Apps geprueft: 0"
  echo "Infra-Module geprueft: 0"
  echo "OK: 0"
  echo "WARN: 0"
  echo "FAIL: 1"
  exit 1
fi

# Grundstruktur greppen
if ! grep -q '^apps:' "$REGISTRY"; then
  echo "FAIL $REGISTRY enthaelt keinen 'apps:'-Block"
  exit 1
fi
if ! grep -q '^infra:' "$REGISTRY"; then
  echo "FAIL $REGISTRY enthaelt keinen 'infra:'-Block"
  exit 1
fi

# Python-Parser: liest apps.yml zeilenbasiert (analog scripts/app.sh)
# und gibt Records auf stdout aus, ein Feld pro Zeile, Trenner '|'.
# Format: SECTION|id|name|compose|port|health|backup_include
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
    for key in ("name", "compose", "port", "health", "backup_include"):
        m = re.match(rf"\s+{key}:\s*(.+?)\s*$", line)
        if m:
            current[key] = m.group(1).strip()
            break

flush()

for r in records:
    print("|".join([
        r.get("section",""),
        r.get("id",""),
        r.get("name",""),
        r.get("compose",""),
        r.get("port",""),
        r.get("health",""),
        r.get("backup_include",""),
    ]))
PY
)"

OK_COUNT=0
WARN_COUNT=0
FAIL_COUNT=0
APP_COUNT=0
INFRA_COUNT=0

declare -A PORT_OWNER

emit_ok()   { OK_COUNT=$((OK_COUNT+1));   [[ $QUIET -eq 1 ]] || echo "OK   $1"; }
emit_warn() { WARN_COUNT=$((WARN_COUNT+1)); echo "WARN $1"; }
emit_fail() { FAIL_COUNT=$((FAIL_COUNT+1)); echo "FAIL $1"; }

check_required_file() {
  local path="$1"
  if [[ -f "$path" ]]; then
    emit_ok "$path"
  else
    emit_fail "$path fehlt"
  fi
}

check_optional_file() {
  local path="$1"
  if [[ -f "$path" ]]; then
    emit_ok "$path"
  else
    emit_warn "$path fehlt"
  fi
}

check_executable() {
  local path="$1"
  if [[ ! -f "$path" ]]; then
    emit_fail "$path fehlt"
  elif [[ ! -x "$path" ]]; then
    emit_fail "$path nicht executable"
  else
    emit_ok "$path"
  fi
}

ID_REGEX='^[a-z0-9-]+$'

while IFS='|' read -r section id name compose port health backup_include; do
  [[ -z "$section" ]] && continue

  if [[ "$section" == "apps" ]]; then
    APP_COUNT=$((APP_COUNT+1))

    # id-Regex
    if [[ "$id" =~ $ID_REGEX ]]; then
      emit_ok "apps/$id id-Format"
    else
      emit_fail "apps id '$id' matcht nicht $ID_REGEX"
    fi

    APP_DIR="apps/$id"
    if [[ -d "$APP_DIR" ]]; then
      emit_ok "$APP_DIR/ (Verzeichnis)"
    else
      emit_fail "$APP_DIR/ Verzeichnis fehlt"
      continue
    fi

    # Pflicht-Artefakte
    check_required_file "$APP_DIR/compose.yml"
    check_executable    "$APP_DIR/healthcheck.sh"
    check_required_file "$APP_DIR/backup.include"
    check_required_file "$APP_DIR/README.md"

    # Optional-Artefakte
    check_optional_file "$APP_DIR/.env.example"
    check_optional_file "$APP_DIR/caddy.disabled"
    check_optional_file "$APP_DIR/caddy.authentik.disabled"

    # Registry-Felder als Datei pruefen
    if [[ -n "$compose" ]]; then
      if [[ -f "$compose" ]]; then
        emit_ok "registry compose: $compose"
      else
        emit_fail "registry compose: $compose existiert nicht"
      fi
      # Apps duerfen nicht auf infra/authentik verweisen
      if [[ "$compose" == infra/authentik* ]]; then
        emit_fail "apps/$id verweist auf infra/authentik: $compose"
      fi
    fi
    if [[ -n "$health" ]]; then
      if [[ -f "$health" ]]; then
        emit_ok "registry health: $health"
      else
        emit_fail "registry health: $health existiert nicht"
      fi
      if [[ "$health" == infra/authentik* ]]; then
        emit_fail "apps/$id health verweist auf infra/authentik: $health"
      fi
    fi
    if [[ -n "$backup_include" ]]; then
      if [[ -f "$backup_include" ]]; then
        emit_ok "registry backup_include: $backup_include"
      else
        emit_fail "registry backup_include: $backup_include existiert nicht"
      fi
      if [[ "$backup_include" == infra/authentik* ]]; then
        emit_fail "apps/$id backup_include verweist auf infra/authentik: $backup_include"
      fi
    fi

    # Port validieren
    if [[ -n "$port" ]]; then
      if [[ "$port" =~ ^[0-9]+$ ]] && (( port >= 1 && port <= 65535 )); then
        emit_ok "apps/$id port=$port"
        if [[ -n "${PORT_OWNER[$port]:-}" ]]; then
          emit_fail "port $port doppelt vergeben: $id und ${PORT_OWNER[$port]}"
        else
          PORT_OWNER[$port]="$id"
        fi
      else
        emit_fail "apps/$id port '$port' ist nicht numerisch oder ausserhalb 1..65535"
      fi
    fi

  elif [[ "$section" == "infra" ]]; then
    INFRA_COUNT=$((INFRA_COUNT+1))

    if [[ "$id" =~ $ID_REGEX ]]; then
      emit_ok "infra/$id id-Format"
    else
      emit_fail "infra id '$id' matcht nicht $ID_REGEX"
    fi

    if [[ "$id" == "authentik" ]]; then
      INFRA_DIR="infra/authentik"
      if [[ -d "$INFRA_DIR" ]]; then
        emit_ok "$INFRA_DIR/ (Verzeichnis)"
        check_required_file "$INFRA_DIR/compose.yml"
        check_required_file "$INFRA_DIR/README.md"
        check_optional_file "$INFRA_DIR/.env.example"
        check_optional_file "$INFRA_DIR/backup.include"
        check_optional_file "$INFRA_DIR/caddy.disabled"
      else
        emit_fail "$INFRA_DIR/ Verzeichnis fehlt"
      fi
    fi

    # compose-Referenz pruefen, falls vorhanden
    if [[ -n "$compose" ]]; then
      if [[ -f "$compose" ]]; then
        emit_ok "registry infra compose: $compose"
      else
        emit_fail "registry infra compose: $compose existiert nicht"
      fi
    fi
  fi
done <<< "$PARSED"

echo "---"
echo "Apps geprueft: $APP_COUNT"
echo "Infra-Module geprueft: $INFRA_COUNT"
echo "OK: $OK_COUNT"
echo "WARN: $WARN_COUNT"
echo "FAIL: $FAIL_COUNT"

if (( FAIL_COUNT > 0 )); then
  exit 1
fi
exit 0
