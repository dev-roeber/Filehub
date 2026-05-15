# Modulares Backup

Filehub sichert Apps modular. Jede App entscheidet selbst, welche Pfade in das
Backup gehoeren, und kann unabhaengig von den anderen Apps gesichert oder
wiederhergestellt werden.

## Prinzip

- Pro App existiert `apps/<id>/backup.include` mit einer Liste der zu
  sichernden Pfade (Volumes, Konfigurations-Verzeichnisse).
- `scripts/backup.sh` liest die Registry `config/apps.yml` und aggregiert die
  Includes aller aktivierten Apps zu einem einzelnen Restic-Snapshot.
- Restic-Repo, Retention und Schedule bleiben gegenueber dem bisherigen Setup
  unveraendert.

## Datenbank-Dumps

Vor dem Restic-Run werden konsistente Dumps erzeugt:

- Paperless: `pg_dump` der Paperless-PostgreSQL-Instanz, Output in das
  Include-Verzeichnis der App.
- Authentik (nur wenn aktiv): `pg_dump` der Authentik-PostgreSQL-Instanz plus
  `BGSAVE` der Authentik-Redis-Instanz, Output in das Include-Verzeichnis von
  `infra/authentik`.

Damit ist der Snapshot konsistent, ohne Container stoppen zu muessen.

## Authentik im Backup

Authentik wird nur dann mitgesichert, wenn

- `AUTHENTIK_ENABLED=true` ist, oder
- der App-spezifische Lauf `just backup-app authentik` explizit angefragt
  wird.

Solange Authentik deaktiviert ist, taucht es nicht in den Snapshots auf und
verursacht keine Dumps.

## Kommandos

```
just backup           # vollstaendiger Lauf ueber alle aktiven Apps
just backup-app <id>  # nur eine einzelne App sichern
just restore-app <id> <snapshot-id>
just backup-status
```

Restic verwaltet die Snapshots, Tags werden pro App vergeben
(`app=<id>`), damit Restore und Retention zielgenau funktionieren.

## Empfehlung vor Updates

Vor `just app-update <id>` oder `just up` mit neuen Images einen Pre-Update-
Snapshot anlegen:

```
just backup-app <id>
just app-update <id>
```

Im Fehlerfall reicht ein Restore der einzelnen App, ohne den Rest der
Plattform anzufassen.

## Verweise

- `docs/backup-restore.md` -- detaillierte Restore-Prozedur.
- `docs/backup-schedule.md` -- Schedule, systemd-Timer, Retention.
- `docs/retention-policy.md` -- Aufbewahrungsregeln.
- `docs/encrypted-secrets-backup.md` -- Secrets-Backup.
