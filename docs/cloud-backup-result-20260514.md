# Cloud-Backup Ergebnis 2026-05-14

## Zusammenfassung

Erster kontrollierter vollstaendiger restic-Cloud-Backup-Lauf fuer Filehub erfolgreich. Produktiver Filehub-Stack lief waehrenddessen weiter. Keine Retention, kein Prune.

## Repository

```text
rclone:gdrive:backups/filehub
```

Status: erreichbar und initialisiert.

## Verwendetes Lokales Backup

```text
/home/sebastian/Repos/Filehub/backups/20260514-200051
```

Lokale Backup-Dateien:

```text
convertx-data.tar.gz         805 B
filehub-config.tar.gz         17K
observability-data.tar.gz    7.9K
paperless-data.tar.gz         11K
paperless-postgres.sql       245K
```

PostgreSQL-Dump vorhanden und nicht leer. `.env` wurde nicht in das Backup aufgenommen.

## Cloud-Backup

Status: OK.

Snapshot:

```text
c58c8361
```

Restic-Auszug:

```text
Files: 53 new, 0 changed, 0 unmodified
Dirs: 22 new, 0 changed, 0 unmodified
Added to the repository: 361.809 KiB (66.870 KiB stored)
processed 53 files, 459.508 KiB in 0:17
```

Gesamtlaufzeit `scripts/backup.sh` (lokal + restic): ca. 66 Sekunden.

Retention/Prune:

```text
not executed
```

## rclone Speicher

`rclone about gdrive:`:

```text
Total:   5 TiB
Used:    9.080 GiB
Free:    4.985 TiB
```

## Snapshots Nach Backup

```text
96ccefac  2026-05-14 18:49:05  filehub-smoke-test            47 B
4cde3873  2026-05-14 18:59:31                         434.413 KiB
c58c8361  2026-05-14 20:01:37                         459.508 KiB
```

3 Snapshots im Repository.

## Restic Check

Status: OK.

```text
[0:03] 100.00%  3 / 3 snapshots
no errors were found
```

Laufzeit: ca. 17 Sekunden.

## Cloud-Restore-Smoke

Status: OK.

Restore-Ziel:

```text
/home/sebastian/Repos/Filehub-restic-restore-smoke
```

Vollstaendiger Restore von Snapshot `c58c8361` (459.508 KiB, 75 Dateien/Verzeichnisse, 0:02).

Erwartete Backup-Artefakte unter `.../backups/20260514-200051/`:

```text
paperless-postgres.sql    245K
paperless-data.tar.gz      11K
convertx-data.tar.gz      805 B
filehub-config.tar.gz      17K
observability-data.tar.gz 7.9K
```

Alle vier geforderten Artefakte wiederherstellbar und nicht leer.

Hinweis: Restore wurde bewusst nicht in produktive Pfade geschrieben.

## Bekannte Rate-Limits

Beim heutigen vollstaendigen Lauf keine finalen Rate-Limit-Fehler. Beim frueheren 47-Byte-Smoke-Test kurzzeitig Google-Drive/rclone Rate-Limits, durch Retries abgefangen.

## Produktiver Stack

`just health` vor und nach dem Backup OK. Stack nicht gestoppt.

## Risiken

- restic-Passphrase liegt in `.env` und muss extern im Passwortmanager gesichert bleiben.
- Google Drive kann bei groesseren Backups Rate-Limits ausloesen; kontrolliertes Zeitfenster waehlen.
- Retention/Prune bewusst deaktiviert; vor Aktivierung `restic forget --dry-run`.
- Restore-Smoke prueft Wiederherstellbarkeit der Backup-Artefakte, keinen vollstaendigen Anwendungs-Restore.
- Restore-Smoke-Verzeichnis enthaelt wiederhergestellte Daten und bleibt sensibel.
- Snapshot enthaelt nur Backup-Archive plus Konfig/Compose/Scripts, keine live `data/postgres`- oder `data/redis`-Volumes (per Design, da live nicht konsistent lesbar).

## Naechster Schritt

Regelmaessigen Backup-Zeitplan definieren (z. B. cron/systemd-timer). Periodischen Cloud-Restore-Test planen. Retention erst nach `restic forget --dry-run` und bewusstem Opt-in via `RESTIC_APPLY_RETENTION=true`.
