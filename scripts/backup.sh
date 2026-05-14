#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

LOCK_FILE="${BACKUP_LOCK_FILE:-/tmp/filehub-backup.lock}"
if [[ "${BACKUP_LOCK_ACQUIRED:-}" != "1" ]]; then
  exec env BACKUP_LOCK_ACQUIRED=1 flock -n "$LOCK_FILE" "$0" "$@" || {
    echo "ERROR: Ein anderer Backup-Lauf haelt bereits $LOCK_FILE. Abbruch." >&2
    exit 1
  }
fi

if [[ ! -f .env ]]; then
  echo "ERROR: .env fehlt." >&2
  exit 1
fi

# shellcheck disable=SC1091
set -a; source .env; set +a

timestamp="$(date +%Y%m%d-%H%M%S)"
backup_dir="backups/${timestamp}"
mkdir -p "$backup_dir"
chmod 700 "$backup_dir"

echo "Erstelle lokales Backup unter $backup_dir"

if docker inspect filehub-paperless-db >/dev/null 2>&1; then
  echo "Erzeuge Postgres-Dump."
  docker exec filehub-paperless-db pg_dump -U "$PAPERLESS_DBUSER" "$PAPERLESS_DBNAME" > "$backup_dir/paperless-postgres.sql"
else
  echo "WARN: DB-Container nicht gefunden. Postgres-Dump wird übersprungen."
fi

tar --warning=no-file-changed -czf "$backup_dir/filehub-config.tar.gz" compose*.yml justfile config docs scripts .env.example README.md
tar --warning=no-file-changed -czf "$backup_dir/paperless-data.tar.gz" data/paperless
tar --warning=no-file-changed -czf "$backup_dir/convertx-data.tar.gz" data/convertx
tar --warning=no-file-changed -czf "$backup_dir/observability-data.tar.gz" data/uptime-kuma data/homepage
if [[ -d data/filebrowser ]]; then
  tar --warning=no-file-changed -czf "$backup_dir/filebrowser-data.tar.gz" data/filebrowser config/filebrowser
fi
if [[ -d data/stirling ]]; then
  tar --warning=no-file-changed -czf "$backup_dir/stirling-data.tar.gz" data/stirling
fi

for archive in "$backup_dir"/*.tar.gz; do
  tar -tzf "$archive" >/dev/null
done

if [[ "${INCLUDE_ENV_IN_BACKUP:-false}" == "true" ]]; then
  echo "WARN: INCLUDE_ENV_IN_BACKUP=true. .env wird sensibel gesichert."
  cp .env "$backup_dir/env.SENSITIVE"
  chmod 600 "$backup_dir/env.SENSITIVE"
else
  echo ".env wurde nicht gesichert. Setze INCLUDE_ENV_IN_BACKUP=true nur bewusst."
fi

if [[ -n "${RESTIC_REPOSITORY:-}" && -n "${RESTIC_PASSWORD:-}" ]]; then
  echo "RESTIC_REPOSITORY und RESTIC_PASSWORD sind gesetzt. Starte restic backup."
  export RESTIC_REPOSITORY RESTIC_PASSWORD
  if [[ "$RESTIC_REPOSITORY" == rclone:* ]]; then
    RCLONE_CONFIG_PATH="${RCLONE_CONFIG_PATH:-/home/sebastian/.config/rclone/rclone.conf}"
    if [[ ! -r "$RCLONE_CONFIG_PATH" ]]; then
      echo "ERROR: RCLONE_CONFIG_PATH ist fuer rclone-Restic-Repositories nicht lesbar." >&2
      exit 1
    fi
    export RCLONE_CONFIG="$RCLONE_CONFIG_PATH"
  fi
  if ! restic cat config >/dev/null 2>&1; then
    echo "ERROR: Restic-Repository ist nicht initialisiert oder nicht erreichbar. Fuehre restic init bewusst separat aus." >&2
    exit 1
  fi
  restic_paths=("$backup_dir" data/paperless data/convertx config docs scripts compose.yml compose.paperless.yml compose.convertx.yml compose.observability.yml .env.example README.md)
  [[ -d data/filebrowser ]] && restic_paths+=(data/filebrowser)
  [[ -d data/stirling ]] && restic_paths+=(data/stirling)
  [[ -f compose.extensions.yml ]] && restic_paths+=(compose.extensions.yml)
  restic backup --tag filehub-full "${restic_paths[@]}"
  if [[ "${RESTIC_APPLY_RETENTION:-false}" == "true" ]]; then
    echo "RESTIC_APPLY_RETENTION=true. Wende restic retention mit prune an (nur Tag filehub-full)."
    restic forget \
      --tag filehub-full \
      --group-by host,tags \
      --keep-daily "${BACKUP_RETENTION_DAILY:-7}" \
      --keep-weekly "${BACKUP_RETENTION_WEEKLY:-4}" \
      --keep-monthly "${BACKUP_RETENTION_MONTHLY:-6}" \
      --prune
  else
    echo "Restic retention/prune wird nicht automatisch angewendet. Setze RESTIC_APPLY_RETENTION=true nur bewusst."
  fi
else
  echo "Restic ist nicht konfiguriert. Lokales Backup-Paket wurde vorbereitet."
fi

echo "----- Backup-Zusammenfassung -----"
echo "Lokaler Backup-Pfad: $backup_dir"
echo "Erzeugte Artefakte:"
for f in "$backup_dir"/*; do
  name="$(basename "$f")"
  case "$name" in
    env.SENSITIVE) echo "  - $name  [sensible Datei, nicht ausgegeben]" ;;
    *) size="$(du -h "$f" 2>/dev/null | awk '{print $1}')"; echo "  - $name  ($size)" ;;
  esac
done
if [[ -n "${RESTIC_REPOSITORY:-}" && -n "${RESTIC_PASSWORD:-}" ]]; then
  latest_id="$(restic snapshots --tag filehub-full --latest 1 --json 2>/dev/null | sed -n 's/.*"short_id":"\([^"]*\)".*/\1/p' | head -1)"
  if [[ -n "$latest_id" ]]; then
    echo "Neuester restic-Snapshot (Tag filehub-full): $latest_id"
  fi
fi
if [[ "${RESTIC_APPLY_RETENTION:-false}" != "true" ]]; then
  echo "Hinweis: Restic-Retention bleibt deaktiviert (RESTIC_APPLY_RETENTION!=true)."
fi
echo "----------------------------------"
echo "Backup abgeschlossen: $backup_dir"
