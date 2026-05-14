# Restic Retention Policy

## Tag-Konzept

Volle Filehub-Backups laufen mit `restic backup --tag filehub-full`. Dieser Tag ist die einzige Gruppe, fuer die Retention vorgesehen ist.

Smoke-Test-Backups verwenden `--tag filehub-smoke-test` und bleiben damit getrennt. Sie werden weder vom geplanten Backup noch von der Retention beruehrt.

`scripts/backup.sh` setzt den Tag fuer alle vom systemd-Service oder von `just backup` ausgeloesten Cloud-Backups automatisch.

## Gruppierung

Restic gruppiert beim `forget` standardmaessig per `(host, paths, tags)`. Da `scripts/backup.sh` jedoch ein wechselndes `backups/<timestamp>`-Verzeichnis als Backup-Pfad uebergibt, ist diese Default-Gruppierung fuer die Retention ungeeignet: jeder Lauf bildet eine eigene Gruppe, und die `--keep-*`-Regeln greifen nicht ueber Tagesgrenzen hinweg.

Loesung: explizit `--group-by host,tags` setzen, sodass der wechselnde Pfad ignoriert wird und alle `filehub-full`-Snapshots eines Hosts in einer Gruppe landen.

## Aktuelle Policy

- `keep-daily`: 7
- `keep-weekly`: 4
- `keep-monthly`: 6

Voreinstellungen sind ueber `.env` ueberschreibbar:

```env
BACKUP_RETENTION_DAILY=7
BACKUP_RETENTION_WEEKLY=4
BACKUP_RETENTION_MONTHLY=6
```

## Dry-Run

Pflicht vor jeder Aktivierung:

```bash
set -a && . .env && set +a
restic forget \
  --tag filehub-full \
  --group-by host,tags \
  --keep-daily "${BACKUP_RETENTION_DAILY:-7}" \
  --keep-weekly "${BACKUP_RETENTION_WEEKLY:-4}" \
  --keep-monthly "${BACKUP_RETENTION_MONTHLY:-6}" \
  --dry-run
```

Der Dry-Run zeigt, welche Snapshots behalten und welche entfernt wuerden. Solange unklar ist, ob Loeschungen gewuenscht sind, wird kein `--prune` ausgefuehrt.

## Aktivierung

Retention wird nur ausgefuehrt, wenn in `.env` bewusst gesetzt ist:

```env
RESTIC_APPLY_RETENTION=true
```

Dann fuehrt `scripts/backup.sh` nach jedem Cloud-Backup automatisch aus:

```bash
restic forget \
  --tag filehub-full \
  --group-by host,tags \
  --keep-daily "${BACKUP_RETENTION_DAILY:-7}" \
  --keep-weekly "${BACKUP_RETENTION_WEEKLY:-4}" \
  --keep-monthly "${BACKUP_RETENTION_MONTHLY:-6}" \
  --prune
```

Aktivierung ist ein bewusster Opt-in pro Umgebung. Sie ersetzt keinen vorherigen Dry-Run.

## Smoke-Snapshots

Smoke-Snapshots werden bewusst nicht in die Retention aufgenommen. Wenn ein alter Smoke-Snapshot bereinigt werden soll, geschieht das gezielt und manuell, z. B. via:

```bash
restic forget <snapshot-id>
```

Ohne `--prune` werden nur die Snapshot-Referenzen geloescht, der Speicher wird durch das naechste manuelle `restic prune` freigegeben.

## Risiken

- Solange Retention deaktiviert ist, waechst der Google-Drive-Speicherbedarf monoton.
- `--prune` kann lange laufen, weil Google Drive viele kleine Pack-Files erneut anfasst.
- Falsche Policy kann gewuenschte Snapshots loeschen. Dry-Run und Verifikation sind Pflicht.
- Tag-Aenderungen erzeugen neue Snapshot-IDs. Alte IDs sind danach nicht mehr gueltig.
