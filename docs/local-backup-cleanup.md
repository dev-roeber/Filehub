# Lokale Backups: Aufbewahrung und Cleanup

Stand: 2026-05-15. Lokale Backups unter `backups/<timestamp>/` koennen
ueber `scripts/local-backup-retention.sh` aufgeraeumt werden. Das
Skript ist konservativ und loescht nur nach explizitem Doppel-Opt-in.

## Policy

- Behalte die letzten 7 Backup-Verzeichnisse.
- Behalte zusaetzlich alles, was juenger als 14 Tage ist, auch wenn es
  damit mehr als 7 sind.
- Loesche nie das juengste Backup, unabhaengig von der Policy.
- Loesche grundsaetzlich nur dann etwas, wenn beide Opt-in-Schalter
  gesetzt sind (siehe unten).

Die Policy ist absichtlich grosszuegig: solange der Cloud-Restore-Smoke
nicht regelmaessig laeuft (siehe `docs/restore-test.md`), dient die
lokale Kopie als zweite Linie.

## Dry-Run

```bash
just local-backup-retention-dry-run
```

Das ruft `scripts/local-backup-retention.sh` ohne `--apply` auf und
listet, welche Verzeichnisse nach Policy entfernt wuerden. Es wird
nichts geaendert.

## Anwenden (Doppel-Opt-in)

Loeschung erfolgt nur, wenn beide Bedingungen gleichzeitig erfuellt
sind:

1. Aufruf mit `--apply` (bzw. `just local-backup-retention-apply`).
2. Umgebungsvariable `LOCAL_BACKUP_RETENTION_APPLY=true` gesetzt.

Beispiel:

```bash
LOCAL_BACKUP_RETENTION_APPLY=true just local-backup-retention-apply
```

Fehlt einer der Schalter, bricht das Skript ab und gibt einen Hinweis
aus. Damit kann ein vergessenes `--apply` keine Daten loeschen, und
eine versehentlich exportierte Umgebungsvariable allein reicht
ebenfalls nicht.

## Schutzmechanismen

- Juengster Backup-Pfad wird auch bei Doppel-Opt-in nie geloescht.
- Verzeichnisse, deren Namen nicht dem Timestamp-Schema entsprechen,
  werden ignoriert.
- Symlinks werden nicht verfolgt; das Skript arbeitet ausschliesslich
  innerhalb von `backups/`.
- Cloud-Restore-Smoke und restic-Snapshots werden nicht angefasst.

## Manuelle Inspektion

```bash
du -sh /home/sebastian/Repos/Filehub/backups/*
ls -1dt /home/sebastian/Repos/Filehub/backups/*/ | head -n 10
```

Vor einem `--apply`-Lauf empfiehlt sich der Dry-Run plus ein Blick auf
die aktuellen Snapshots:

```bash
set -a && . /home/sebastian/Repos/Filehub/.env && set +a
restic snapshots --tag filehub-full --compact
```

## Risiken

- Lokale Backups enthalten `paperless-postgres.sql` und tar-Archive mit
  Anwendungsdaten. Sie sind sensibel und gehoeren nicht in unkontrollierte
  Kopien.
- Eine falsch konfigurierte Schwelle kann mehr loeschen als beabsichtigt.
  Dry-Run ist Pflicht.
- Solange `LOCAL_BACKUP_RETENTION_APPLY=true` nicht gesetzt ist, ist der
  Pfad sicher.
