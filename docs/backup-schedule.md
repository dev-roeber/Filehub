# Filehub Backup-Zeitplan

Dieser Plan automatisiert `scripts/backup.sh` ueber einen systemd-Timer. Der Timer laeuft konservativ einmal taeglich, mit randomisiertem Versatz und einem flock-Lock, der parallele Laeufe verhindert.

## Komponenten

- `deploy/systemd/filehub-backup.service` — oneshot service als User `sebastian`, ruft `scripts/backup.sh` ueber `flock -n /tmp/filehub-backup.lock` auf.
- `deploy/systemd/filehub-backup.timer` — taeglich 03:30, `RandomizedDelaySec=30min`, `Persistent=true`.
- `scripts/backup.sh` — re-execed sich beim Start unter einem `flock`. Bei laufender Instanz bricht es mit klarer Meldung ab.

Keine Passphrasen, Tokens oder privaten Keys liegen in den Unit-Dateien. Secrets werden ausschliesslich aus `.env` im Repo gelesen.

## Installation

```bash
just backup-install-timer
```

Das kopiert die Unit-Dateien nach `/etc/systemd/system/` und ruft `systemctl daemon-reload` auf.

## Aktivierung

```bash
just backup-enable-timer
```

Das aktiviert und startet den Timer. Der Service selbst laeuft erst zum naechsten Timer-Zeitpunkt, nicht sofort.

Status pruefen:

```bash
just backup-timer-status
```

## Manueller Lauf

```bash
just backup-run-now
```

Das startet `filehub-backup.service` sofort. Wenn bereits ein Lauf aktiv ist, blockiert `flock` und der zweite Lauf wird abgebrochen.

Pruefablauf nach manuellem Lauf:

```bash
systemctl status filehub-backup.service --no-pager
just backup-logs
set -a && . .env && set +a
restic snapshots
```

Ein konkretes Lauf-Ergebnis ist in `docs/backup-manual-run-result-20260514.md` dokumentiert.

## Logs

```bash
just backup-logs
```

Zeigt die letzten 200 journal-Zeilen von `filehub-backup.service`. Die Logs enthalten keine Secrets, sondern nur Status, Dateinamen und restic-Zusammenfassungen.

## Timer Deaktivieren

```bash
just backup-disable-timer
```

Das stoppt und deaktiviert den Timer. Lokale Backups unter `backups/` bleiben erhalten.

## Schutzmechanismen

- `flock -n /tmp/filehub-backup.lock` schuetzt vor parallelen Laeufen, sowohl bei direktem Skript-Aufruf als auch via systemd.
- `Type=oneshot` und kein `OnCalendar`-Refresh waehrend laufender Unit verhindern doppelten Start durch den Timer.
- `RandomizedDelaySec=30min` glaettet Spitzen.
- `Persistent=true` holt verpasste Laeufe nach Reboot nach.

## Retention

Retention/Prune bleibt deaktiviert. Bevor `RESTIC_APPLY_RETENTION=true` in `.env` gesetzt wird:

1. Policy in `.env` festlegen (`BACKUP_RETENTION_DAILY/WEEKLY/MONTHLY`).
2. Manuell pruefen:

```bash
set -a && . .env && set +a
restic forget --dry-run \
  --keep-daily "${BACKUP_RETENTION_DAILY:-7}" \
  --keep-weekly "${BACKUP_RETENTION_WEEKLY:-4}" \
  --keep-monthly "${BACKUP_RETENTION_MONTHLY:-6}"
```

Erst nach bewusster Pruefung Opt-in setzen.

Wichtig: `scripts/backup.sh` uebergibt `backups/<timestamp>` an restic. Dadurch hat jeder Lauf einen eigenen Pfad und restic gruppiert per `(host, paths, tags)` jeden Snapshot in eine eigene Gruppe. Folge: Ein nackter `restic forget --keep-*` greift effektiv nicht. Bevor Retention aktiviert wird, entweder:

- `--group-by host,tags` setzen, damit der wechselnde Pfad fuer die Gruppierung ignoriert wird, oder
- restic-backup-Aufrufe um stabile Tags ergaenzen (z. B. `--tag filehub-daily`) und mit `--group-by tags` arbeiten.

Retention erst nach separater Freigabe aktivieren. Vor jeder Aenderung erneut `--dry-run`.

## Restore-Test-Intervall

Mindestens einmal pro Monat einen Cloud-Restore-Smoke gegen einen separaten Pfad pruefen, siehe `docs/restore-test.md` und `docs/cloud-backup-result-20260514.md`.

## Bekannte Risiken

- Google Drive kann Rate-Limits ausloesen. `scripts/backup.sh` bricht in dem Fall durch restic/rclone-Retries normalerweise nicht ab.
- Der Service laeuft als User `sebastian`. Aenderungen an `.env` werden zur naechsten Laufzeit automatisch wirksam.
- Snapshot enthaelt die generierten Backup-Archive und ausgewaehlte Repo-Pfade, aber keine live `data/postgres` oder `data/redis`-Volumes. Diese werden ueber Postgres-Dump und tar-Archive abgedeckt.
