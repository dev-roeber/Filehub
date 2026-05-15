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

# --- Modularer App-Backup-Modus -----------------------------------------------
# Wenn FILEHUB_BACKUP_ONLY_APP=<id> gesetzt ist, sichert dieser Lauf NUR die
# eine App: liest apps/<id>/backup.include + erzeugt benoetigte DB-Dumps.
# Restic ueberspringt dann den globalen Backup-Lauf (eingeschraenkte paths).

backup_app_module() {
  local app="$1"
  local include="apps/$app/backup.include"
  if [[ ! -f "$include" ]]; then
    echo "ERROR: $include fehlt." >&2
    return 1
  fi
  echo "App-Modus: sichere nur '$app' (aus $include)."

  # App-spezifische DB-Dumps.
  case "$app" in
    paperless)
      if docker inspect filehub-paperless-db >/dev/null 2>&1; then
        docker exec filehub-paperless-db pg_dump -U "$PAPERLESS_DBUSER" "$PAPERLESS_DBNAME" \
          > "$backup_dir/paperless-postgres.sql" || \
          { echo "WARN: paperless pg_dump fehlgeschlagen."; rm -f "$backup_dir/paperless-postgres.sql"; }
      fi
      ;;
    authentik)
      if docker inspect filehub-authentik-db >/dev/null 2>&1; then
        docker exec filehub-authentik-db pg_dump -U authentik authentik \
          > "$backup_dir/authentik-postgres.sql" || \
          { echo "WARN: authentik pg_dump fehlgeschlagen."; rm -f "$backup_dir/authentik-postgres.sql"; }
      fi
      if docker inspect filehub-authentik-redis >/dev/null 2>&1; then
        docker exec filehub-authentik-redis redis-cli BGSAVE >/dev/null 2>&1 || true
        sleep 2
        docker exec filehub-authentik-redis cat /data/dump.rdb \
          > "$backup_dir/authentik-redis-dump.rdb" 2>/dev/null || \
          { echo "WARN: authentik redis dump fehlgeschlagen."; rm -f "$backup_dir/authentik-redis-dump.rdb"; }
      fi
      ;;
  esac

  # Pfadliste aus backup.include lesen (Kommentare/Leerzeilen filtern).
  mapfile -t paths < <(grep -vE '^[[:space:]]*(#|$)' "$include")
  local existing=()
  for p in "${paths[@]}"; do
    [[ -e "$p" ]] && existing+=("$p") || echo "  skip (nicht vorhanden): $p"
  done
  if [[ ${#existing[@]} -gt 0 ]]; then
    tar --warning=no-file-changed -czf "$backup_dir/${app}-app.tar.gz" "${existing[@]}"
  fi
}

if [[ -n "${FILEHUB_BACKUP_ONLY_APP:-}" ]]; then
  backup_app_module "$FILEHUB_BACKUP_ONLY_APP"
  echo "App-Modus abgeschlossen. Globaler Backup-Lauf wird uebersprungen."
  echo "Lokaler Backup-Pfad: $backup_dir"
  exit 0
fi
# --- Ende modularer Modus -----------------------------------------------------

if docker inspect filehub-paperless-db >/dev/null 2>&1; then
  echo "Erzeuge Paperless Postgres-Dump."
  docker exec filehub-paperless-db pg_dump -U "$PAPERLESS_DBUSER" "$PAPERLESS_DBNAME" > "$backup_dir/paperless-postgres.sql"
else
  echo "WARN: Paperless DB-Container nicht gefunden. Postgres-Dump wird übersprungen."
fi

if docker inspect filehub-authentik-db >/dev/null 2>&1; then
  echo "Erzeuge Authentik Postgres-Dump."
  if ! docker exec filehub-authentik-db pg_dump -U authentik authentik > "$backup_dir/authentik-postgres.sql"; then
    echo "WARN: Authentik pg_dump fehlgeschlagen. Backup-Lauf fuehrt weiter, Authentik-DB fehlt im Paket."
    rm -f "$backup_dir/authentik-postgres.sql"
  fi
else
  echo "WARN: Authentik DB-Container nicht gefunden. Postgres-Dump wird übersprungen."
fi

if docker inspect filehub-authentik-redis >/dev/null 2>&1; then
  echo "Loese Authentik Redis BGSAVE aus und kopiere dump.rdb (konsistenter Snapshot)."
  old_lastsave="$(docker exec filehub-authentik-redis redis-cli LASTSAVE 2>/dev/null || echo 0)"
  if docker exec filehub-authentik-redis redis-cli BGSAVE >/dev/null 2>&1; then
    # Auf BGSAVE-Abschluss warten (LASTSAVE muss sich erhoehen; max 30s).
    for _ in $(seq 1 30); do
      new_lastsave="$(docker exec filehub-authentik-redis redis-cli LASTSAVE 2>/dev/null || echo 0)"
      if [[ "$new_lastsave" -gt "$old_lastsave" ]]; then
        break
      fi
      sleep 1
    done
    # dump.rdb gehoert dem Container-User (0600) - via docker exec lesen.
    if docker exec filehub-authentik-redis cat /data/dump.rdb > "$backup_dir/authentik-redis-dump.rdb" 2>/dev/null; then
      chmod 600 "$backup_dir/authentik-redis-dump.rdb"
    else
      echo "WARN: Konnte authentik-redis dump.rdb nicht aus dem Container kopieren."
      rm -f "$backup_dir/authentik-redis-dump.rdb"
    fi
  else
    echo "WARN: Authentik Redis BGSAVE konnte nicht ausgeloest werden."
  fi
fi

if [[ -d data/authentik ]]; then
  # Postgres-Datendir (700/UID 70) und redis-Dir (dump.rdb ist 0600) bewusst auslassen -
  # Postgres wird via pg_dump, Redis als RDB-Datei via docker exec gesichert.
  tar --warning=no-file-changed -czf "$backup_dir/authentik-data.tar.gz" \
    data/authentik/media \
    data/authentik/custom-templates \
    data/authentik/certs
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
  # Authentik: media/custom-templates/certs (Postgres+Redis liegen als Dumps im backup_dir).
  [[ -d data/authentik/media ]] && restic_paths+=(data/authentik/media)
  [[ -d data/authentik/custom-templates ]] && restic_paths+=(data/authentik/custom-templates)
  [[ -d data/authentik/certs ]] && restic_paths+=(data/authentik/certs)
  [[ -f compose.auth.yml ]] && restic_paths+=(compose.auth.yml)
  [[ -f compose.extensions.yml ]] && restic_paths+=(compose.extensions.yml)
  restic backup --tag filehub-full "${restic_paths[@]}"
  if [[ "${RESTIC_APPLY_RETENTION:-false}" == "true" ]]; then
    prune_args=()
    if [[ "${RESTIC_APPLY_PRUNE:-false}" == "true" ]]; then
      echo "RESTIC_APPLY_PRUNE=true. Wende forget + prune an (langsam, sperrt repo)."
      prune_args=(--prune)
    else
      echo "RESTIC_APPLY_RETENTION=true (forget ohne prune). RESTIC_APPLY_PRUNE=true zusaetzlich noetig, um Daten zu reclaimen."
    fi
    restic forget \
      --tag filehub-full \
      --group-by host,tags \
      --keep-daily "${BACKUP_RETENTION_DAILY:-7}" \
      --keep-weekly "${BACKUP_RETENTION_WEEKLY:-4}" \
      --keep-monthly "${BACKUP_RETENTION_MONTHLY:-6}" \
      "${prune_args[@]}"
  else
    echo "Restic retention/prune wird nicht automatisch angewendet. Setze RESTIC_APPLY_RETENTION=true nur bewusst (+ RESTIC_APPLY_PRUNE=true fuer prune)."
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
