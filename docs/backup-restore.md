# Backup und Restore

## Gesicherte Pfade

`scripts/backup.sh` sichert lokal unter `backups/YYYYmmdd-HHMMSS`:

- PostgreSQL-Dump aus `filehub-paperless-db`
- `config/`, `docs/`, `scripts/`, Compose-Dateien, `justfile`, `.env.example`, `README.md`
- `data/paperless`
- `data/convertx`
- `data/uptime-kuma`
- `data/homepage`

`.env` wird standardmäßig nicht gesichert. Mit `INCLUDE_ENV_IN_BACKUP=true` wird sie als `env.SENSITIVE` aufgenommen.

## Restic und rclone

Wenn `RESTIC_REPOSITORY` und `RESTIC_PASSWORD` gesetzt sind, startet das Backup-Script zusätzlich ein restic-Backup. Für rclone-Backends wird `RCLONE_CONFIG_PATH` verwendet, standardmäßig:

```text
/home/sebastian/.config/rclone/rclone.conf
```

Google Drive kann über rclone als restic-Backend genutzt werden, z. B. nach vorheriger rclone-Konfiguration. Zugangsdaten bleiben außerhalb des Repositories.

Aktuelles Ziel fuer Google Drive:

```env
RESTIC_REPOSITORY=rclone:gdrive:backups/filehub
RCLONE_CONFIG_PATH=/home/sebastian/.config/rclone/rclone.conf
```

`RESTIC_PASSWORD` liegt nur in `.env` und muss zusaetzlich extern in einem Passwortmanager gesichert werden. Ohne diese Passphrase ist ein Restore aus dem restic-Repository nicht moeglich.

Das restic-Repository muss bewusst initialisiert werden:

```bash
set -a
source .env
set +a
export RESTIC_REPOSITORY RESTIC_PASSWORD
export RCLONE_CONFIG="$RCLONE_CONFIG_PATH"
restic cat config || restic init
restic snapshots
```

## Cloud-Smoke-Test

Vor einem grossen Cloud-Backup wurde ein kleiner Smoke-Test empfohlen:

1. kleine Testdatei unter `backups/restic-smoke-test/` erzeugen
2. nur diese Datei mit `restic backup --tag filehub-smoke-test` sichern
3. `restic snapshots --tag filehub-smoke-test` pruefen
4. Snapshot lokal in ein temporaeres Verzeichnis restoren
5. Dateiinhalt oder Checksumme vergleichen

Der Smoke-Test hinterlaesst absichtlich einen kleinen Snapshot. Snapshots werden nicht automatisch geloescht.

## Retention

Retention und `prune` werden nicht automatisch bei jedem Backup ausgefuehrt. Das normale Backup-Script fuehrt `restic forget --prune` nur aus, wenn diese Variable bewusst gesetzt ist:

```env
RESTIC_APPLY_RETENTION=true
```

Vor jeder produktiven Retention sollte zuerst ein Dry-Run erfolgen:

```bash
restic forget --keep-daily 7 --keep-weekly 4 --keep-monthly 6 --dry-run
```

## Kosten und Risiken

- Google-Drive-Speicherverbrauch steigt mit Snapshots und geaenderten Daten.
- Der erste vollstaendige Upload kann je nach Datenmenge lange dauern.
- Upload-Traffic und Google-API-Limits koennen Backups verzoegern.
- Restic-Snapshots sind verschluesselt; verlorene Passphrase bedeutet verlorenen Zugriff.
- Ein erfolgreiches Backup ersetzt keinen regelmaessigen Restore-Test.

## Lokales Backup

```bash
just backup
```

## Restore

`scripts/restore.sh` ist absichtlich nur eine vorsichtige Vorlage. Es überschreibt keine Daten.

Manueller Ablauf:

1. Aktuellen Zustand mit `scripts/backup.sh` sichern.
2. Backup-Inhalt prüfen.
3. Stack stoppen: `just down`.
4. Bestehende Zielverzeichnisse verschieben, nicht löschen.
5. Tar-Dateien gezielt entpacken.
6. Dateirechte für UID/GID aus `.env` prüfen.
7. PostgreSQL-Dump manuell in den DB-Container importieren.
8. Stack starten: `just up`.
9. `just health` und Logs prüfen.

Paperless-Medien und Datenbank müssen zeitlich zusammenpassen.
