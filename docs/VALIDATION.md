# Validation: modulare App-Struktur

Letztes Update: 2026-05-15 nach zweiter Stabilisierungs-Serie
(958e612..HEAD: registry-audit, homepage-apply, caddy-Helper-Haertung).

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

## just-Kommandos

Funktional verifiziert:
- `just app-list` -- liest config/apps.yml, gibt 7 Apps tabellarisch aus.
- `just apps-status` -- alle 7 Apps healthy.
- `just infra-status` -- 4 Authentik-Container + Gateway healthy, beide Netzwerke vorhanden.
- `just auth-status` -- Authentik-UI 302.
- `just app-health <id>` -- liefert container/state/http (nutzt jetzt Registry-Pfad mit Fallback).
- `just homepage-generate` -- erzeugt config/homepage/services.generated.yaml (7 Services).
- `just caddy-list` -- listet aktivierte Snippets (leer im Default).
- `just secrets-audit` -- alle Pruefungen bestanden.
- `just gateway-bootstrap-check` -- STATE=POST-BOOTSTRAP.

Neue Gateway-/Auth-Targets verfuegbar: `gateway-restart`, `gateway-logs`,
`gateway-reload`, `auth-restart`, `auth-logs`.

Neue Targets (zweite Serie):
- `just registry-audit` -- 7 Apps, 3 Infra-Module, 103 OK, 0 WARN, 0 FAIL.
- `just registry-audit-quiet` -- nur Summary.
- `just homepage-apply` -- atomares Promote services.generated.yaml -> services.yaml.
- `just homepage-apply-restart` -- wie oben + docker restart filehub-homepage.
- `just caddy-list` -- ruft scripts/caddy-list.sh (legt enabled/ bei Bedarf an).

Alte Aliase (`up-auth`, `down-auth`, `restart-auth`, `logs-auth`, `up-core`,
`up-extensions`, ...) bleiben kompatibel.

## Healthcheck-Pfade in Registry

`config/apps.yml` verweist jetzt auf `apps/<id>/healthcheck.sh` statt
auf das nie existierende `scripts/health/<id>.sh`. `scripts/app.sh`
liest die Registry, faellt bei fehlendem Eintrag auf
`apps/<id>/healthcheck.sh` zurueck.

## Authentik-Aktivierungsstatus

- `.env.example` definiert `AUTHENTIK_ENABLED=false` als Default.
- `just auth-up` bricht ab, wenn AUTHENTIK_ENABLED != true.
- Bestehender Authentik-Stack laeuft aus dem Phase-1-Bootstrap weiter
  (compose.auth.yml unangetastet).

## Authentik-DB-Parametrisierung

`scripts/backup.sh` nutzt nun durchgaengig:
- `AUTHENTIK_DB_HOST`, `AUTHENTIK_DB_PORT`, `AUTHENTIK_DB_USER`,
  `AUTHENTIK_DB_NAME`, `AUTHENTIK_REDIS_CONTAINER`.

Defaults sind kompatibel zu `compose.auth.yml` und `infra/authentik/compose.yml`.

## Backup-Modul-Test

| Aufruf | Ergebnis |
|---|---|
| `FILEHUB_BACKUP_ONLY_APP=homepage scripts/backup.sh` | homepage-app.tar.gz erzeugt |
| `FILEHUB_BACKUP_ONLY_APP=convertx scripts/backup.sh` | convertx-app.tar.gz erzeugt |
| `FILEHUB_BACKUP_ONLY_APP=authentik scripts/backup.sh` | authentik-postgres.sql (2.5 MB), authentik-redis-dump.rdb (143 KB), authentik-app.tar.gz |

Restic wird im App-Modus uebersprungen. Globaler Lauf bleibt unveraendert.

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

Keine echten Passwoerter im Diff. `.env.example` nutzt `<set-local-secret>`
als Platzhalter, neue `AUTHENTIK_DB_*`-Defaults enthalten nur Container-/
Datenbank-Namen, keine Credentials.

## Caddy-Helper-Test

| Aufruf | Ergebnis |
|---|---|
| `scripts/caddy-enable.sh homepage plain` | Snippet kopiert, `caddy validate` im Container "Valid configuration" |
| zweiter Aufruf ohne `--force` | exit 4, keine Ueberschreibung |
| `scripts/caddy-disable.sh homepage` | idempotent, Datei entfernt |
| `scripts/caddy-enable.sh nicht-existent plain` | exit 2, App-Liste in stderr |

Keine erzwungenen Reloads, kein Container-Restart durch den Helper.

## Registry-Audit-Test

| Aufruf | Ergebnis |
|---|---|
| `scripts/registry-audit.sh` | 7 Apps, 3 Infra-Module, 103 OK, 0 WARN, 0 FAIL, exit 0 |
| `scripts/registry-audit.sh --quiet` | nur Summary, exit 0 |

Prueft Pflicht-Artefakte (compose.yml, healthcheck.sh, backup.include,
README.md) als FAIL, optionale (.env.example, caddy.*.disabled) als WARN.
Zusaetzlich: id-Regex `^[a-z0-9-]+$`, Port-Uniqueness, Registry-Pfade.

## Homepage-Apply-Test

| Aufruf | Ergebnis |
|---|---|
| `scripts/homepage-apply.sh --help` | Usage + Exit-Codes (0/2/3/4) |
| `scripts/homepage-apply.sh` ohne generated | exit 2 |
| Apply nach Generate | Backup `services.yaml.bak.<ts>`, atomares mv, exit 0 |
| `--restart` (nicht im CI-Lauf) | docker restart filehub-homepage |

Keine interaktive Abfrage. Diff-Vorschau (head -40) wird angezeigt.

## Caddy-Helper-Haertung (Roundtrip)

| Aufruf | Ergebnis |
|---|---|
| `scripts/caddy-list.sh` (leer) | "(keine aktivierten Snippets)", exit 0 |
| `scripts/caddy-enable.sh homepage plain` | enabled-Datei kopiert, caddy validate OK |
| zweiter Aufruf ohne `--force` | exit 4 |
| zweiter Aufruf mit `--force` (cmp -s) | exit 0 "schon aktuell" |
| Quelle leer (size 0) | exit 3 |
| `scripts/caddy-disable.sh homepage` | Datei entfernt, idempotent |
| Symlink-Target ausserhalb enabled/ | exit 5 (Schutz) |

## Keine destruktiven Aenderungen

- Keine Container neu gestartet, kein `docker compose down`.
- Keine Volumes geloescht oder umbenannt.
- Keine Restic-Snapshots geloescht.
- Keine Public-Bindings veraendert (alle weiterhin 127.0.0.1).
- `services.yaml` der Homepage unveraendert (`services.generated.yaml` ist Output).
