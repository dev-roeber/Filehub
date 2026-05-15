#!/usr/bin/env bash
# Filehub Backup-Age (Phase 2 Preflight).
#
# Zweck:
#   Prueft, ob fuer eine App ein "ausreichend aktuelles" Backup-Artefakt
#   im lokalen backups/-Tree liegt. Wird vor Migrate-Execute aufgerufen.
#   Read-only: prueft Datei-Existenz und mtime, loescht nichts.
#
# Konvention:
#   FILEHUB_BACKUP_ONLY_APP=<app> scripts/backup.sh erzeugt
#     backups/<YYYYMMDD-HHMMSS>/<app>-app.tar.gz
#   Authentik und Paperless sind hier explizit ausgeschlossen
#   (separate Backup-Pfade mit DB-Dumps).
#
# Usage:
#   scripts/backup-age.sh <app> [--quiet] [--max-age-hours N]
#
# Exit-Codes:
#   0  aktuelles Backup plausibel vorhanden (< MAX_AGE)
#   1  WARN: Backup vorhanden aber aelter als MAX_AGE, oder Pruefung unklar
#   2  FAIL: kein Backup-Artefakt gefunden, App unbekannt, Argument-Fehler
#
# Defaults:
#   MAX_AGE_HOURS=24
#
# Ausgaben ASCII-only.

set -uo pipefail
cd "$(dirname "$0")/.."

QUIET=0
APP=""
MAX_AGE_HOURS=24

while [[ $# -gt 0 ]]; do
  case "$1" in
    --quiet) QUIET=1; shift ;;
    --max-age-hours)
      shift
      if [[ $# -lt 1 ]]; then
        echo "ERROR: --max-age-hours braucht Wert" >&2
        exit 2
      fi
      MAX_AGE_HOURS="$1"
      shift
      ;;
    -h|--help)
      sed -n '1,28p' "$0"
      exit 0
      ;;
    --*)
      echo "ERROR: unbekannte Option $1" >&2
      exit 2
      ;;
    *)
      if [[ -n "$APP" ]]; then
        echo "ERROR: mehrere App-Argumente: $APP und $1" >&2
        exit 2
      fi
      APP="$1"
      shift
      ;;
  esac
done

if [[ -z "$APP" ]]; then
  echo "ERROR: <app> fehlt" >&2
  exit 2
fi

log() {
  if [[ $QUIET -eq 0 ]]; then
    echo "$@"
  fi
}

# --- Registry-Pruefung (App muss existieren) ---
REGISTRY="config/apps.yml"
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

app_known=0
while IFS= read -r id; do
  [[ -z "$id" ]] && continue
  if [[ "$id" == "$APP" ]]; then
    app_known=1
    break
  fi
done <<< "$APP_IDS_RAW"

if [[ $app_known -eq 0 ]]; then
  echo "FAIL Unbekannte App '$APP' (nicht in $REGISTRY)" >&2
  exit 2
fi

# --- Sonderfall: Authentik (nicht in apps.yml) ---
if [[ "$APP" == "authentik" ]]; then
  echo "FAIL authentik ist eine separate Backup-Klasse (pg_dump + redis dump)" >&2
  echo "     und wird hier NICHT geprueft. Siehe scripts/backup.sh." >&2
  exit 2
fi

# --- Backup-Verzeichnis prueft ---
BACKUP_ROOT="backups"
if [[ ! -d "$BACKUP_ROOT" ]]; then
  log "WARN $BACKUP_ROOT/ existiert nicht - kein Backup-Lauf seit Setup"
  echo "RECOMMEND: just backup-app $APP"
  exit 1
fi

ARTIFACT_NAME="${APP}-app.tar.gz"

# Neueste Datei suchen (find + sort by mtime)
NEWEST_PATH=""
NEWEST_MTIME=0
while IFS= read -r -d '' path; do
  mt="$(stat -c %Y "$path" 2>/dev/null || echo 0)"
  if (( mt > NEWEST_MTIME )); then
    NEWEST_MTIME=$mt
    NEWEST_PATH="$path"
  fi
done < <(find "$BACKUP_ROOT" -maxdepth 2 -type f -name "$ARTIFACT_NAME" -print0 2>/dev/null)

if [[ -z "$NEWEST_PATH" ]]; then
  log "WARN Kein Backup-Artefakt $ARTIFACT_NAME unter $BACKUP_ROOT/<TS>/ gefunden"
  echo "RECOMMEND: just backup-app $APP"
  # Kein Artefakt = FAIL: vor Execute MUSS ein Backup laufen.
  exit 2
fi

NOW="$(date +%s)"
AGE_SECONDS=$(( NOW - NEWEST_MTIME ))
AGE_HOURS=$(( AGE_SECONDS / 3600 ))
AGE_MIN=$(( (AGE_SECONDS % 3600) / 60 ))

log "INFO neuestes Backup: $NEWEST_PATH"
log "INFO Alter: ${AGE_HOURS}h ${AGE_MIN}min  (max erlaubt: ${MAX_AGE_HOURS}h)"

MAX_AGE_SECONDS=$(( MAX_AGE_HOURS * 3600 ))

if (( AGE_SECONDS <= MAX_AGE_SECONDS )); then
  log "OK   Backup ist innerhalb der MAX_AGE-Schwelle"
  exit 0
fi

log "WARN Backup ist aelter als ${MAX_AGE_HOURS}h"
echo "RECOMMEND: just backup-app $APP"
exit 1
