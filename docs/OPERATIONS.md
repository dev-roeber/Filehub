# Operations

Taegliche Betriebskommandos fuer Filehub. Alle Kommandos sind ueber das
Justfile gebuendelt und arbeiten gegen die App-Registry `config/apps.yml`.

## Status und Audit

```
just apps-status        # Compose-Status aller registrierten Apps
just infra-status       # Status der Infrastruktur (Gateway, Backup, Authentik)
just audit-report       # Gesamt-Auditreport (inkl. registry-audit am Ende)
just registry-audit     # Reine Konsistenzpruefung Registry <-> Filesystem
just registry-audit-quiet # nur WARN/FAIL + Summary
```

`registry-audit` prueft pro App: id-Regex, Verzeichnis, Pflicht-Artefakte
(compose.yml, healthcheck.sh, backup.include, README.md) als FAIL, optionale
Artefakte (.env.example, caddy.*.disabled) als WARN, Registry-Pfade
(compose/health/backup_include), Port-Uniqueness und id-Sicherheit.
Infra-Modul `authentik` wird separat geprueft.

Exit-Code: 0 bei `FAIL=0` (auch mit WARNs), sonst 1. `audit-report` ruft
`registry-audit --quiet` zusaetzlich auf und zeigt die letzten Zeilen.

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
just gateway-up          # startet filehub-gateway (compose.auth.yml)
just gateway-down        # stoppt + entfernt Container
just gateway-restart     # neustart ohne Recreate
just gateway-logs        # tail -f des Gateway-Logs
just gateway-reload      # docker restart (Caddy admin off, kein API-Reload)
just gateway-status      # Container-Status + http-Probe
just gateway-bootstrap-check  # read-only PRE/POST-BOOTSTRAP-Check
```

Caddy-Snippets pro App aktivieren/deaktivieren:

```
just caddy-list                # aktive Snippets
just caddy-enable <app>        # apps/<app>/caddy.disabled -> enabled/
just caddy-enable-auth <app>   # caddy.authentik.disabled (forward_auth)
just caddy-disable <app>       # entfernt enabled/<app>.caddy
```

Ohne Gateway sind die Apps weiterhin direkt unter `127.0.0.1:<port>`
erreichbar.

## Authentik (separat)

Authentik wird unabhaengig vom Gateway verwaltet (Default: deaktiviert):

```
just auth-up        # nur wenn AUTHENTIK_ENABLED=true
just auth-down
just auth-restart
just auth-logs
just auth-status
```

DB-Parameter fuer Backup koennen via ENV ueberschrieben werden
(`AUTHENTIK_DB_HOST/PORT/USER/NAME`, `AUTHENTIK_REDIS_CONTAINER`).
Details siehe `docs/AUTHENTIK_OPTIONAL.md`.

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
Das Script ueberschreibt **nicht** die aktive `services.yaml`.

`just homepage-apply` uebernimmt `services.generated.yaml` -> `services.yaml`
mit folgenden Garantien:

- Existenz-Check auf `services.generated.yaml` (sonst exit 2).
- YAML-Validierung (pyyaml falls verfuegbar, sonst grep-Plausibilitaet).
- Backup der aktuellen `services.yaml` nach
  `config/homepage/services.yaml.bak.<YYYYMMDD-HHMMSS>` (cp).
- Diff-Zusammenfassung (erste 40 Zeilen) wird stdout ausgegeben.
- Atomares Schreiben via tmp + mv. Keine interaktive Nachfrage.
- Exit-Codes: 0 OK, 2 generated fehlt, 3 Restart-Fehler, 4 Validate-Fehler.

`just homepage-apply-restart` ist identisch, fuehrt anschliessend
`docker restart filehub-homepage` aus. Bei Restart-Fehler: WARN, exit 3,
**ohne** Rollback der Datei (Backup bleibt vorhanden).

Quelle der Wahrheit fuer Ports, Container und Beschreibungen ist die Registry
`config/apps.yml` (Felder `port`, `internal_url`, `description`, `category`,
`default_enabled`).
