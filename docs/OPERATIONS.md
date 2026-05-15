# Operations

Taegliche Betriebskommandos fuer Filehub. Alle Kommandos sind ueber das
Justfile gebuendelt und arbeiten gegen die App-Registry `config/apps.yml`.

## Status und Audit

```
just apps-status      # Compose-Status aller registrierten Apps
just infra-status     # Status der Infrastruktur (Gateway, Backup, Authentik)
just audit-report     # Konsistenzpruefung Registry <-> Filesystem <-> Compose
```

Der Audit-Report deckt typische Drift-Faelle ab: App im Verzeichnis aber nicht
in der Registry, Registry-Eintrag ohne `backup.include`, Caddy-Snippet aktiv
ohne Gateway, fehlender Healthcheck.

## Single-App-Lifecycle

Pro App stehen einheitliche Lifecycle-Kommandos zur Verfuegung:

```
just app-up <id>
just app-down <id>
just app-restart <id>
just app-logs <id>
just app-status <id>
just app-pull <id>
just app-update <id>
just app-health <id>
```

`app-update` zieht das neue Image und startet die App neu. Vor jedem Update
wird empfohlen, einen App-spezifischen Snapshot anzulegen
(`just backup-app <id>`), siehe `docs/BACKUP.md`.

## Gateway (Reverse-Proxy)

Das Gateway ist optional und steuert den externen Zugriff:

```
just gateway-up
just gateway-down
just gateway-status
```

Ohne Gateway sind die Apps weiterhin direkt unter `127.0.0.1:<port>`
erreichbar. Welche Apps das Gateway proxied, ergibt sich aus den aktiven
Caddy-Snippets (`caddy` statt `caddy.disabled`).

## Authentik (separat)

Authentik wird unabhaengig vom Gateway verwaltet:

```
just auth-up
just auth-down
just auth-status
```

Default ist deaktiviert. Details siehe `docs/AUTHENTIK_OPTIONAL.md`.

## Logs und Diagnose

```
just app-logs <id>    # tail -f fuer eine App
just logs             # zentrale Sicht (Dozzle), falls aktiv
```

Healthchecks pro App liegen in `scripts/health/<id>.sh`. `just app-health <id>`
gibt Exit-Code 0 zurueck, wenn die App gesund ist.

## Update-Routine

1. `just apps-status` -- Ausgangslage pruefen.
2. `just backup-app <id>` -- Pre-Update-Snapshot.
3. `just app-update <id>` -- Pull + Restart.
4. `just app-health <id>` -- Gesundheit verifizieren.
5. Bei Fehler: `just restore-app <id> <snapshot>`.

## Verweise

- `docs/APPS.md` -- App-Liste und Quickstart.
- `docs/BACKUP.md` -- Modulares Backup.
- `docs/update-runbook.md` -- detaillierter Update-Runbook.
- `docs/operations.md` -- bestehende Ops-Notizen (kleines o).

## Homepage-Generator

`just homepage-generate` liest `config/apps.yml` und erzeugt eine
gethomepage-kompatible Datei `config/homepage/services.generated.yaml`.

- Das Script ueberschreibt **nicht** die aktive `services.yaml`.
- Aktivierung manuell: `diff config/homepage/services.yaml config/homepage/services.generated.yaml`,
  dann bewusst per `mv` / `cp` ueberschreiben und Homepage neu laden.
- Quelle der Wahrheit fuer Ports, Container und Beschreibungen ist die Registry
  `config/apps.yml` (Felder `port`, `internal_url`, `description`, `category`,
  `default_enabled`).
