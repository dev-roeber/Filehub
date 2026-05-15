# Filehub

Filehub ist eine **modulare App-Plattform** für selfhosted Datei-Konvertierung, Dokumentenmanagement, OCR, PDF-/Office-Verarbeitung, Monitoring und Backup.

Jede App ist eigenständig: eigene `compose.yml`, eigene `.env.example`, eigenes Backup, eigener Healthcheck. Es gibt **keinen Monolith** – Apps können einzeln gestartet, gestoppt, gesichert und aktualisiert werden.

Der initiale Betrieb ist bewusst `localhost-only`: Alle Webdienste binden an `127.0.0.1`. Remote-Zugriff erfolgt per SSH-Tunnel, nicht über öffentliche App-Ports.

## Modulares Layout

```
apps/<id>/        compose.yml, .env.example, backup.include, healthcheck.sh,
                  caddy.disabled, caddy.authentik.disabled
infra/<id>/       Optionale Infrastruktur (authentik, caddy, backup, ...)
config/apps.yml   Maschinenlesbare App-Registry
```

Single-User-Setup: zentrale Admin-Defaults via `FILEHUB_ADMIN_USER` / `FILEHUB_ADMIN_PASSWORD` (in `.env`, NIE im Repo). Authentik ist optional und **default deaktiviert** (`AUTHENTIK_ENABLED=false`).

Doku-Einstieg:
- Architektur: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
- App-Uebersicht: [docs/APPS.md](docs/APPS.md)
- Operations: [docs/OPERATIONS.md](docs/OPERATIONS.md)
- Backup: [docs/BACKUP.md](docs/BACKUP.md)
- Security: [docs/SECURITY.md](docs/SECURITY.md)
- Authentik optional: [docs/AUTHENTIK_OPTIONAL.md](docs/AUTHENTIK_OPTIONAL.md)

## Haeufige Kommandos

```
just app-list                  # alle Apps inkl. Status-Metadaten
just app-up <app>              # einzelne App starten
just app-down <app>            # einzelne App stoppen
just apps-status               # Healthcheck-Uebersicht
just infra-status              # Authentik/Gateway/Networks
just backup-app <app>          # nur diese App sichern
just backup-all                # vollstaendiger Backup-Lauf (bestehend)
just auth-up                   # nur wenn AUTHENTIK_ENABLED=true
```

Bestehende Kommandos (`just up`, `just up-core`, `just up-auth`, ...) bleiben kompatibel.

## Architektur

User -> SSH-Tunnel -> localhost Ports -> Docker Services -> interne Dienste -> Backup

Kernkomponenten:

| Service | Zweck | Lokale URL |
|---|---|---|
| Paperless-ngx | Dokumentenmanagement, OCR, Office/E-Mail via Tika/Gotenberg | `http://127.0.0.1:8000` |
| ConvertX | Dateikonvertierung (Bild, Doc, Audio, Video) | `http://127.0.0.1:3000` |
| Homepage | Dashboard | `http://127.0.0.1:3001` |
| Uptime Kuma | Monitoring (11 Monitore) | `http://127.0.0.1:3002` |
| Filebrowser | Lokaler Datei-Manager | `http://127.0.0.1:3003` |
| Stirling PDF | PDF-Werkzeuge (merge, split, rotate, compress) | `http://127.0.0.1:3004` |
| Dozzle | Docker-Logs | `http://127.0.0.1:9999` |
| PostgreSQL | Paperless-Datenbank | intern |
| Redis | Paperless-Queue/Cache | intern |
| Tika/Gotenberg | Dokumentenextraktion und Office-Konvertierung | intern |

Backup/Betrieb:

- `restic` + `rclone` (Google Drive) fuer verschluesselte Offsite-Backups
- systemd User-Timer `filehub-backup.timer` (taeglich 03:45)
- `just`-Rezepte fuer Start/Stop/Health/Backup/Security/Secrets-Audit
- Scripts unter `scripts/` fuer Init, Doctor, Backup, Restore, Setup-Helfer

## Initialer Start

```bash
cd /home/sebastian/Repos/Filehub
./scripts/init.sh
./scripts/doctor.sh
docker compose -f compose.yml -f compose.paperless.yml -f compose.convertx.yml -f compose.observability.yml config
docker compose -f compose.yml -f compose.paperless.yml -f compose.convertx.yml -f compose.observability.yml pull
docker compose -f compose.yml -f compose.paperless.yml -f compose.convertx.yml -f compose.observability.yml up -d
./scripts/health.sh
```

Mit `just`:

```bash
just init
just doctor
just pull
just up
just health
```

## SSH-Tunnel

```bash
ssh -L 8000:127.0.0.1:8000 \
    -L 3000:127.0.0.1:3000 \
    -L 3001:127.0.0.1:3001 \
    -L 3002:127.0.0.1:3002 \
    -L 3003:127.0.0.1:3003 \
    -L 3004:127.0.0.1:3004 \
    -L 9999:127.0.0.1:9999 \
    sebastian@SERVER_IP
```

Keine echte Server-IP ist im Repository hinterlegt.

## Login und Setup

Paperless-Admin-User und initiales Passwort stehen in `.env`. Secrets werden nicht committed und nicht in Logs ausgegeben.

ConvertX erstellt beim ersten Zugriff den initialen Benutzer. `ACCOUNT_REGISTRATION=false` bleibt gesetzt, damit keine offene Registrierung aktiv ist.

Uptime Kuma benötigt beim ersten Aufruf ein eigenes Admin-Konto.

Details zur manuellen Einrichtung lokaler Monitore stehen in [docs/uptime-kuma.md](docs/uptime-kuma.md).

## Backups

`scripts/backup.sh` erstellt lokale, zeitgestempelte Backups unter `backups/` und erzeugt einen PostgreSQL-Dump, sofern der DB-Container läuft. Wenn `RESTIC_REPOSITORY` und `RESTIC_PASSWORD` gesetzt sind, wird zusätzlich ein verschlüsseltes restic-Backup ausgeführt.

`.env` wird standardmäßig nicht gesichert. Setze `INCLUDE_ENV_IN_BACKUP=true` nur bewusst, weil die Datei sensible Secrets enthält.

Ein isolierter Restore-Test ohne Eingriff in den produktiven Stack ist in [docs/restore-test.md](docs/restore-test.md) beschrieben.

Ein automatischer Zeitplan via systemd-Timer ist in [docs/backup-schedule.md](docs/backup-schedule.md) beschrieben.

Das vorbereitete Cloud-Ziel ist `RESTIC_REPOSITORY=rclone:gdrive:backups/filehub`. Die restic-Passphrase liegt nur in `.env` und muss extern in einem Passwortmanager gesichert werden. Retention/Prune wird nicht automatisch ausgefuehrt; `RESTIC_APPLY_RETENTION=true` ist ein bewusster Opt-in.

## Sicherheit

- Keine Webdienste öffentlich exponieren.
- Keine Bindings wie `0.0.0.0:8000` oder `8000:8000` verwenden.
- `.env` niemals committen.
- Dozzle zeigt Logs und bleibt deshalb strikt lokal.
- Caddy ist vorbereitet, aber nicht Teil des Standardstarts.
- Domain, HTTPS und zusätzliche Authentifizierung sind Phase 2.
- Backups regelmäßig erstellen und Restore testen.

## Updates

```bash
just backup
just update
just health
```

Alte Docker-Images werden nur entfernt, wenn `PRUNE_OLD_IMAGES=true` gesetzt ist.

## Troubleshooting

```bash
just ps
just logs
just doctor
just health
df -h
docker compose -f compose.yml -f compose.paperless.yml -f compose.convertx.yml -f compose.observability.yml ps
```

Prüfe bei Problemen zuerst Port-Konflikte, freien Speicher, Container-Healthchecks und Paperless-/Postgres-Logs.

## Authentik SSO Gateway (Phase 1)

Authentik laeuft lokal als Identity-Provider mit einem zweiten Caddy als Forward-Auth-Gateway vor der Filehub-Homepage. HTTP only, localhost-only.

Starten:

```bash
just up-auth
```

Pruefen:

```bash
just auth-status
just gateway-status
```

URLs:

- Authentik UI: `http://127.0.0.1:9000`
- Filehub-Gateway: `http://127.0.0.1:3080`

Details, Phase-2-Plan und Sicherheits-Hinweise: [docs/sso-gateway.md](docs/sso-gateway.md).

## Deployment-Pfad

Das Repository liegt initial unter `/home/sebastian/Repos/Filehub`. `/opt/stacks` existierte bei der Einrichtung nicht. Ein späterer Deploy nach `/opt/stacks/filehub` kann per Kopie oder Git-Checkout erfolgen, nachdem `/opt/stacks` bewusst mit passenden Rechten angelegt wurde.
