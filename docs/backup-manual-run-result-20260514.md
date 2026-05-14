# Manueller Backup-Lauf Ergebnis 2026-05-14

## Zusammenfassung

Manueller Lauf des installierten systemd-Backup-Services erfolgreich. Retention-Policy nur als Dry-Run geprueft. Keine Snapshots geloescht. Produktiver Filehub-Stack lief durch.

## Service-Lauf

Aufruf:

```bash
sudo systemctl start filehub-backup.service
```

Status: OK (`status=0/SUCCESS`).

Laufzeit ca. 61 Sekunden.

Lokaler Backup-Pfad:

```text
/home/sebastian/Repos/Filehub/backups/20260514-201557
```

Lokale Dateien:

```text
convertx-data.tar.gz        805 B
filehub-config.tar.gz        18K
observability-data.tar.gz   7.9K
paperless-data.tar.gz        11K
paperless-postgres.sql      246K
```

Restic-Snapshot:

```text
2eafc502
```

Restic-Statistik:

```text
Files: 54 new, 0 changed, 0 unmodified
Dirs:  22 new, 0 changed, 0 unmodified
Added to the repository: 385.749 KiB (76.071 KiB stored)
processed 54 files, 472.382 KiB in 0:15
```

Snapshots im Repository nach Lauf: 4.

## Service-Anpassungen

Bei der Inbetriebnahme zwei Fixes:

1. ExecStart-Wrapper `flock` entfernt, weil `scripts/backup.sh` sich bereits selbst per `flock` re-execed. Doppel-Locking war zuvor die Ursache fuer `status=1`.
2. `PATH` in der Unit um `/home/linuxbrew/.linuxbrew/bin` ergaenzt, weil `restic` und `rclone` aus Linuxbrew kommen und im systemd-Default-PATH fehlten.

Aktueller Stand `deploy/systemd/filehub-backup.service`:

- `ExecStart=/home/sebastian/Repos/Filehub/scripts/backup.sh`
- `Environment=PATH=/home/linuxbrew/.linuxbrew/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin`
- `Environment=HOME=/home/sebastian`

Aus dem ersten fehlgeschlagenen Startversuch verblieb ein leeres lokales Backup-Verzeichnis `backups/20260514-201526`. Es wurde nicht geloescht (Regel: keine lokalen Backups loeschen).

## Timer

Timer weiterhin aktiv (`active (waiting)`, enabled).

Naechster geplanter automatischer Lauf:

```text
Fri 2026-05-15 03:46:37 CEST
```

## Retention-Policy Dry-Run

Aufruf:

```bash
restic forget --keep-daily 7 --keep-weekly 4 --keep-monthly 6 --dry-run
```

Status: OK.

Ergebnis:

- Snapshots geprueft: 4
- Snapshots, die behalten wuerden: 4
- Snapshots, die entfernt wuerden: 0
- Kein `--prune` ausgefuehrt
- Kein `RESTIC_APPLY_RETENTION=true` gesetzt

Befund: restic gruppiert beim `forget` per `(host, paths, tags)`. `scripts/backup.sh` uebergibt `backups/<timestamp>` als Pfad, sodass jeder Lauf eine eigene Pfadgruppe bildet. Folge: Mit der aktuellen Skript-Form bleibt in jeder Gruppe genau ein Snapshot, und die Policy `--keep-daily/--keep-weekly/--keep-monthly` greift nicht ueber Tagesgrenzen hinweg.

Empfehlung fuer spaeteren Retention-Roll-out (separater Schritt):

- Entweder `restic forget --group-by host,tags` einsetzen, um den `backups/<timestamp>`-Pfad fuer die Gruppierung zu ignorieren.
- Oder `restic backup --tag filehub-daily ...` setzen und mit `--group-by tags` arbeiten.
- Vor jeder Aenderung erneut `--dry-run` ausfuehren.

## Pruefungen

`just doctor`: OK mit erwartbaren Warnungen fuer belegte Filehub-Ports.

`just health`: OK fuer Paperless, ConvertX, Homepage, Dozzle, Uptime Kuma, Paperless DB, Paperless Redis.

`git status`: vor Commit modifizierte Unit-Datei und neue Doku.

## Risiken

- Retention greift mit der aktuellen `backups/<timestamp>`-Pfad-Form nicht. Speicherverbrauch waechst weiter, bis Gruppierung/Tags ergaenzt sind.
- Service haengt am Linuxbrew-Pfad. Wenn Linuxbrew umzieht, muss `Environment=PATH=` in der Unit angepasst werden.
- Lock-Datei `/tmp/filehub-backup.lock` bleibt nach Lauf liegen. Das ist normal; `flock -n` arbeitet auf File-Descriptor-Ebene und nicht ueber die Existenz der Datei.
- Es existiert ein leeres lokales Backup-Verzeichnis aus einem fehlgeschlagenen Startversuch. Es bleibt zu Audit-Zwecken erhalten.

## Naechster Schritt

Am 2026-05-15 den ersten automatischen Lauf verifizieren (`just backup-logs`, `restic snapshots`). Anschliessend Tag- oder Gruppierungs-Strategie fuer Retention festlegen, erneut `--dry-run` ausfuehren und erst dann `RESTIC_APPLY_RETENTION=true` setzen.
