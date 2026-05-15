# Validation: modulare App-Struktur

Stand: 2026-05-15 nach Commit-Serie d6b73c3..59ae444.

## docker compose config

| Compose-Datei | Status |
|---|---|
| apps/paperless/compose.yml | OK |
| apps/convertx/compose.yml | OK |
| apps/stirling-pdf/compose.yml | OK |
| apps/filebrowser/compose.yml | OK |
| apps/homepage/compose.yml | OK |
| apps/uptime-kuma/compose.yml | OK |
| apps/dozzle/compose.yml | OK |
| infra/authentik/compose.yml | OK |

Alle bestehenden compose.*.yml im Repo-Root sind unveraendert.

## Neue just-Kommandos

`just --list` listet 33 Targets in den modularen Namespaces
(`app-*`, `apps-*`, `infra-*`, `auth-*`, `gateway-*`, `backup-*`).

Funktional verifiziert:
- `just app-list` -- liest config/apps.yml, gibt 7 Apps tabellarisch aus.
- `just apps-status` -- alle 7 Apps healthy (HTTP 200/302/401 erwartete Codes).
- `just infra-status` -- 4 Authentik-Container + Gateway healthy.
- `just app-health <id>` -- liefert container/state/http pro App.
- `just secrets-audit` -- alle Pruefungen bestanden, keine Secret-Dateien getrackt.
- `just gateway-bootstrap-check` -- STATE=POST-BOOTSTRAP (Login-Redirect auf Authentik).

## Authentik-Aktivierungsstatus

- `.env.example` definiert `AUTHENTIK_ENABLED=false` als Default.
- `just auth-up` bricht ab, wenn AUTHENTIK_ENABLED != true.
- Bestehender Authentik-Stack laeuft aus dem Phase-1-Bootstrap weiter
  (compose.auth.yml ist unangetastet); das neue Modul infra/authentik
  ist parallel verfuegbar, aber nicht automatisch aktiv.

## Secrets-Audit

```
OK: PAPERLESS_DBPASS gesetzt
OK: CONVERTX_JWT_SECRET gesetzt
OK: POSTGRES_PASSWORD gesetzt
OK: RCLONE_CONFIG_PATH lesbar
OK: .gitignore deckt .env ab
OK: .gitignore deckt .secrets/ ab
OK: Keine Secret-Dateien in git getrackt
```

Keine echten Passwoerter im Diff. .env.example nutzt durchgaengig
`<set-local-secret>` als Platzhalter.

## Backup-Modul-Test

`FILEHUB_BACKUP_ONLY_APP=homepage scripts/backup.sh` erzeugt:
- `backups/<ts>/homepage-app.tar.gz` mit `config/homepage/` + `apps/homepage/`

Restic wird im App-Modus uebersprungen. Globaler Lauf
(`scripts/backup.sh` ohne FILEHUB_BACKUP_ONLY_APP) bleibt unveraendert
und sichert alle Apps + Authentik wie bisher.

## Keine destruktiven Aenderungen

- Keine Container neu gestartet, kein `docker compose down`.
- Keine Volumes geloescht oder umbenannt.
- Keine Restic-Snapshots geloescht.
- Keine Public-Bindings veraendert (alle weiterhin 127.0.0.1).
