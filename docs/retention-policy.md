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

Pflicht vor jeder Aktivierung. Bequem ueber:

```bash
just backup-dry-run-retention
```

Manuell entspricht das:

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

Der Dry-Run zeigt, welche Snapshots behalten und welche entfernt wuerden. Solange unklar ist, ob Loeschungen gewuenscht sind, wird weder `forget` noch `prune` ausgefuehrt.

Aktuelles Dry-Run-Ergebnis (Stand 2026-05-15): bei vier vorhandenen
`filehub-full`-Snapshots wuerden zwei behalten und zwei entfernt. Es
erfolgt keine Loeschung, da Retention deaktiviert ist.

## Aktivierung (zwei-stufiges Opt-in)

Retention ist standardmaessig deaktiviert. Die Aktivierung erfolgt in
zwei bewussten Schritten in `.env`:

### Stufe 1: forget

```env
RESTIC_APPLY_RETENTION=true
```

Nur wenn diese Variable gesetzt ist, ruft `scripts/backup.sh` nach
einem erfolgreichen Cloud-Backup `restic forget` auf. Das markiert
ueberzaehlige Snapshots als geloescht. Der Speicher wird damit noch
nicht freigegeben.

### Stufe 2: prune

```env
RESTIC_APPLY_PRUNE=true
```

Zusaetzlich zu `RESTIC_APPLY_RETENTION=true`. Erst dann ruft
`scripts/backup.sh` nach `forget` auch `restic prune` auf und gibt
Speicher tatsaechlich frei.

Begruendung fuer die Trennung:

- `prune` laeuft auf Google Drive lange (viele kleine Pack-Files,
  Rate-Limits).
- `prune` haelt einen exklusiven Lock auf das Repo. In dieser Zeit
  blockieren parallele Backups oder Restores.
- Ein Fehler waehrend `prune` ist schwerer zu reparieren als ein
  reines `forget`.

Wer Speicher braucht, schaltet erst Stufe 1 ein, beobachtet einige
Laeufe, und aktiviert dann Stufe 2 bewusst. Beide Stufen ersetzen
keinen vorherigen Dry-Run.

### Aktueller Status

Beide Variablen sind aktuell ungesetzt bzw. ungleich `true`. Es laeuft
weder `forget` noch `prune` automatisch. Snapshots wachsen weiterhin
monoton.

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
