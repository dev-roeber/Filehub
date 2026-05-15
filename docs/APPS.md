# Filehub Apps

Uebersicht aller Anwendungen, die ueber `config/apps.yml` registriert sind.
Jede App laeuft eigenstaendig, mit eigenem Volume, eigenem Backup und eigenem
Healthcheck. Authentik-Schutz ist pro App optional (`authentik_optional: true`)
und standardmaessig deaktiviert.

## Uebersicht

| id           | name           | port | internal_url                              | default_enabled | authentik_optional | backup_include                       |
| ------------ | -------------- | ---- | ----------------------------------------- | --------------- | ------------------ | ------------------------------------ |
| paperless    | Paperless-ngx  | 8000 | http://filehub-paperless-webserver:8000   | true            | true               | apps/paperless/backup.include        |
| convertx     | ConvertX       | 3000 | http://filehub-convertx:3000              | true            | true               | apps/convertx/backup.include         |
| stirling-pdf | Stirling PDF   | 3004 | http://filehub-stirling-pdf:8080          | true            | true               | apps/stirling-pdf/backup.include     |
| filebrowser  | Filebrowser    | 3003 | http://filehub-filebrowser:80             | true            | true               | apps/filebrowser/backup.include      |
| homepage     | Homepage       | 3001 | http://filehub-homepage:3000              | true            | true               | apps/homepage/backup.include         |
| uptime-kuma  | Uptime Kuma    | 3002 | http://filehub-uptime-kuma:3001           | true            | true               | apps/uptime-kuma/backup.include      |
| dozzle       | Dozzle         | 9999 | http://filehub-dozzle:8080                | true            | true               | apps/dozzle/backup.include           |
| grafana      | Grafana        | 3005 | http://filehub-grafana:3000               | true            | true               | apps/grafana/backup.include          |
| whisper-asr  | Whisper ASR    | 9001 | http://filehub-whisper-asr:9000           | false (opt-in)  | true               | apps/whisper-asr/backup.include      |

Alle Ports binden lokal an `127.0.0.1`. Public-Zugriff laeuft ausschliesslich
ueber das optionale Gateway (`infra/gateway`).

## Lifecycle pro App

Einheitliche Kommandos via Justfile:

```
just app-up <id>        # startet die App
just app-down <id>      # stoppt die App
just app-restart <id>   # Neustart
just app-status <id>    # Compose-Status
just app-logs <id>      # tail -f Logs
just app-pull <id>      # Image-Update ziehen
just app-update <id>    # Pull + Restart (Pre-Backup empfohlen)
just app-health <id>    # ruft healthcheck.sh
```

## App-Sektionen

### paperless -- Paperless-ngx

Dokumentenmanagement mit OCR, Volltextsuche und Tagging. Persistente Daten in
PostgreSQL plus Document-Store.

- Start: `just app-up paperless`
- Health: `just app-health paperless`

### convertx -- ConvertX

Web-UI fuer Dateikonvertierung (Bilder, Audio, Video, Office). Stateless bis
auf User- und Job-Datenbank.

- Start: `just app-up convertx`
- Health: `just app-health convertx`

### stirling-pdf -- Stirling PDF

Toolkit fuer PDF-Operationen (Merge, Split, OCR, Komprimieren, Signieren).

- Start: `just app-up stirling-pdf`
- Health: `just app-health stirling-pdf`

### filebrowser -- Filebrowser

Web-Dateibrowser fuer den gemeinsamen Daten-Mount. Eigene User-DB.

- Start: `just app-up filebrowser`
- Health: `just app-health filebrowser`

### homepage -- Homepage

Dashboard mit Status- und Quicklink-Kacheln, generiert aus der App-Registry.
Kein Pflichteinstieg -- jede App ist auch direkt erreichbar.

- Start: `just app-up homepage`
- Health: `just app-health homepage`

### uptime-kuma -- Uptime Kuma

Uptime-Monitoring mit Benachrichtigungen. Eigene SQLite-DB.

- Start: `just app-up uptime-kuma`
- Health: `just app-health uptime-kuma`

### dozzle -- Dozzle

Web-Log-Viewer fuer alle laufenden Docker-Container. Stateless.

- Start: `just app-up dozzle`
- Health: `just app-health dozzle`

### grafana -- Grafana

Metrics-Dashboards (Open-Source-Edition). Eigene SQLite-DB unter
`data/grafana`. Image laeuft als Host-PUID (statt Grafana-Default
UID 472), damit Bind-Mount ohne chown nutzbar ist. Erst-Admin-
Passwort kommt aus `FILEHUB_ADMIN_PASSWORD` und ist nur fuer die
Initialisierung wirksam - spaetere Aenderung ueber Grafana-UI.

- Start: `just app-up grafana`
- Health: `just app-health grafana`
- Provisioning: optional unter `config/grafana/provisioning/`.

### whisper-asr -- Whisper ASR Webservice

Speech-to-Text-API (OpenAI Whisper, CPU-Variante). Hoher RAM-Bedarf,
Modelldownload beim ersten Start (mehrere GB). `default_enabled=false`
- bewusst opt-in. Modellcache (`data/whisper-asr/cache`) ist
**nicht** im Backup enthalten (reproduzierbar). Werks-Default
`ASR_MODEL=base`.

- Start: `just app-up whisper-asr`
- Health: `just app-health whisper-asr`
- Modellauswahl: `WHISPER_ASR_MODEL=tiny|base|small|medium|large` in `.env`.

## Backup und Restore pro App

Jede App liefert eine eigene `backup.include`-Datei (Pfad-Liste). Damit
laesst sich eine einzelne App sichern und wiederherstellen, ohne andere Apps
zu beruehren:

```
just backup-app <id>
just restore-app <id> <snapshot-id>
```

Details siehe `docs/BACKUP.md` und `docs/backup-restore.md`.

## Verweise

- `config/apps.yml` -- Registry mit allen Feldern.
- `docs/ARCHITECTURE.md` -- Plattform-Konzept.
- `docs/AUTHENTIK_OPTIONAL.md` -- SSO pro App aktivieren.
- `docs/OPERATIONS.md` -- Status, Audit, Wartung.
