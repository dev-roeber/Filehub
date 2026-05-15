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

## Neue Apps (2026-05-15)

- **grafana**: `data/grafana` + `config/grafana/provisioning` werden
  gesichert. Grafana laeuft als Host-PUID, daher keine Permission-
  Konflikte beim Restore.
  - **Restore-Hinweis**: `PUID`/`PGID` in `.env` muessen zur UID/GID des
    Ziel-Hosts passen. Falls der Restore auf einem Host mit anderem UID
    erfolgt, vor dem Start entweder die `.env`-Werte anpassen ODER nach
    der Extraction `chown -R <neue-UID>:<neue-GID> data/grafana`
    ausfuehren, sonst entstehen Permission-Konflikte auf der SQLite-DB.
- **whisper-asr**: nur `data/whisper-asr/work` und Config-Dateien
  sind im `backup.include`. Der Modellcache
  (`data/whisper-asr/cache`, mehrere GB) ist **bewusst ausgeschlossen**
  - die Modelle sind reproduzierbar nachladbar.
  - **Restore-Hinweis**: Modelle werden beim ersten Start nachgeladen
    (Netzzugriff zum Modell-Repo noetig). Der Erst-Start kann je nach
    Modellgroesse mehrere Minuten dauern; `start_period` im Healthcheck
    gegebenenfalls an die Modellgroesse anpassen.

## Verweise

- `docs/backup-restore.md` -- detaillierte Restore-Prozedur.
- `docs/backup-schedule.md` -- Schedule, systemd-Timer, Retention.
- `docs/retention-policy.md` -- Aufbewahrungsregeln.
- `docs/encrypted-secrets-backup.md` -- Secrets-Backup.
