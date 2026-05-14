# Filehub

Filehub ist ein selfhosted Docker-Stack für private Datei-Konvertierung, Dokumentenmanagement, OCR, PDF-/Office-Verarbeitung, Monitoring und Backup-Vorbereitung.

Der initiale Betrieb ist bewusst `localhost-only`: Alle Webdienste binden an `127.0.0.1`. Remote-Zugriff erfolgt per SSH-Tunnel, nicht über öffentliche App-Ports.

## Architektur

User -> SSH-Tunnel -> localhost Ports -> Docker Services -> interne Dienste -> Backup

Kernkomponenten:

| Service | Zweck | Lokale URL |
|---|---|---|
| Paperless-ngx | Dokumentenmanagement, OCR, Office/E-Mail via Tika/Gotenberg | `http://127.0.0.1:8000` |
| ConvertX | Dateikonvertierung | `http://127.0.0.1:3000` |
| Homepage | Dashboard | `http://127.0.0.1:3001` |
| Dozzle | Docker-Logs | `http://127.0.0.1:9999` |
| Uptime Kuma | Monitoring | `http://127.0.0.1:3002` |
| PostgreSQL | Paperless-Datenbank | intern |
| Redis | Paperless-Queue/Cache | intern |
| Tika/Gotenberg | Dokumentenextraktion und Office-Konvertierung | intern |

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
ssh -L 3000:127.0.0.1:3000 -L 8000:127.0.0.1:8000 -L 9999:127.0.0.1:9999 -L 3001:127.0.0.1:3001 -L 3002:127.0.0.1:3002 sebastian@SERVER_IP
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

## Deployment-Pfad

Das Repository liegt initial unter `/home/sebastian/Repos/Filehub`. `/opt/stacks` existierte bei der Einrichtung nicht. Ein späterer Deploy nach `/opt/stacks/filehub` kann per Kopie oder Git-Checkout erfolgen, nachdem `/opt/stacks` bewusst mit passenden Rechten angelegt wurde.
