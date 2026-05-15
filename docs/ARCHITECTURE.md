# Filehub Architektur

Filehub ist eine modulare App-Plattform, kein Monolith. Jede Anwendung lebt
eigenstaendig: eigene Compose-Datei, eigene Volumes, eigenes Backup, eigener
Healthcheck. Die Plattform liefert lediglich Konventionen, eine Registry und
einige zentrale Helfer.

## Verzeichnisstruktur

```
apps/        Eine App pro Verzeichnis (paperless, convertx, ...)
infra/       Plattform-Bausteine (gateway, authentik, backup, monitoring)
config/      Registry und geteilte Konfiguration (apps.yml, caddy)
scripts/     Helfer (Healthchecks, Backup-Aggregation, Audit)
docs/        Dokumentation
deploy/      Deploy-bezogene Artefakte
data/        Laufzeitdaten (nicht im Repo)
backups/     Lokale Backup-Ablage (nicht im Repo)
```

## Lose Kopplung

- Apps wissen nichts voneinander. Jede App ist auch ohne die anderen lauffaehig.
- Plattformfunktionen (Reverse-Proxy, SSO, Backup-Orchestrierung) sind opt-in.
- Kein gemeinsamer DB-Cluster, keine geteilten Volumes zwischen Apps.

## Konventionen pro App

Jedes Verzeichnis `apps/<id>/` enthaelt:

- `compose.yml` -- Zielzustand der Compose-Definition.
- `.env.example` -- Vorlage fuer App-spezifische Variablen.
- `README.md` -- Kurzbeschreibung, Defaults, Stolperfallen.
- `backup.include` -- Pfad-Liste fuer das modulare Backup.
- `healthcheck.sh` -- Liefert 0 wenn die App gesund ist.
- `caddy.disabled` -- Caddy-Snippet fuer den Reverse-Proxy ohne SSO,
  inaktiv bis bewusst zu `caddy` umbenannt.
- `caddy.authentik.disabled` -- Caddy-Snippet mit Authentik-Forward-Auth,
  ebenfalls inaktiv bis bewusst aktiviert.

## Infrastruktur

`infra/` enthaelt Plattform-Komponenten, die nicht Teil einer einzelnen App
sind:

- `infra/gateway/` -- Reverse-Proxy (Caddy), optional.
- `infra/authentik/` -- Identity Provider, default deaktiviert.
- `infra/backup/` -- Restic-Dispatcher und systemd-Integration.
- `infra/monitoring/` -- ergaenzende Plattform-Metriken.

Authentik ist explizit Infrastruktur, keine App. Standardwert
`AUTHENTIK_ENABLED=false`. Erst durch `just auth-up` wird das Modul gestartet.
Solange Authentik deaktiviert ist, laufen alle Apps standalone.

## Registry: config/apps.yml

`config/apps.yml` ist die Single Source of Truth ueber alle Apps. Die Felder
`id`, `name`, `port`, `internal_url`, `default_enabled`, `authentik_optional`,
`backup_include`, `compose` und `health` werden ausgewertet von:

- Justfile-Helfern (`just app-up <id>`, `just apps-status`, ...)
- Homepage-Generator
- Backup-Aggregator (`scripts/backup.sh`)
- Audit-Report (`just audit-report` -> registry-audit + runtime-audit)

Neue Apps werden hier registriert. Wer den Eintrag vergisst, wird vom Audit
auffallen.

### Zwei Audit-Ebenen

- **registry-audit** prueft die Dateistruktur gegen `config/apps.yml`
  (Pflicht-Artefakte, Pfade, Port-Uniqueness). Read-only auf Filesystem.
- **runtime-audit** prueft Drift gegen die laufenden Container
  (`container_name`-Konflikte, Hostport-Bindings, Health, Authentik-Status).
  Read-only via `docker info`, `docker ps`, `docker compose config -q`.

Beide tolerieren WARN-Befunde im Default. `--strict` macht WARN zu exit 1
fuer CI/Schedules. FAIL liefert immer exit 2.

Wichtige Invariante: `apps/<id>/compose.yml` und Root-`compose.*.yml`
teilen sich denselben `container_name`. Doppelstart ist Docker-seitig
gesperrt. `runtime-audit` markiert die Doppelnennung als INFO.

## Migration vom Compose-Sammelsurium

Im Repo-Root existieren historisch gewachsene Compose-Dateien
(`compose.paperless.yml`, `compose.convertx.yml`, `compose.extensions.yml`,
`compose.observability.yml`, `compose.auth.yml`, `compose.backup.yml`,
`compose.proxy.yml`, `compose.yml`). Diese bleiben uebergangsweise kompatibel
und werden von der Registry referenziert.

Der Zielzustand ist `apps/<id>/compose.yml` pro Anwendung. Die Migration
geschieht schrittweise pro App. Wechsel-Kriterium: die App laesst sich
ausschliesslich ueber `apps/<id>/` betreiben (Compose, Env, Backup,
Healthcheck, Caddy-Snippets), die Root-Datei wird nur noch als Symlink
oder Fallback gehalten.

## Verweise

- `docs/APPS.md` -- Liste der Apps und Quickstart.
- `docs/AUTHENTIK_OPTIONAL.md` -- Authentik aktivieren/deaktivieren.
- `docs/BACKUP.md` -- Modulares Backup-Konzept.
- `docs/OPERATIONS.md` -- Taegliche Ops.
- `docs/SECURITY.md` -- Single-User-Setup und Secrets.
