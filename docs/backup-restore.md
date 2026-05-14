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
