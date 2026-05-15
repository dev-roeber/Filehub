# Validation: modulare App-Struktur

Letztes Update: 2026-05-15 nach Migration-Phase-2
(c57031e..HEAD: backup-age, homepage --execute, just migrate-execute-homepage).
Vorherige Etappen: runtime-audit (e3ccbe7), registry-audit (958e612),
homepage-apply (4647b5e), caddy-Haertung (4958a03).

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

## Runtime-Audit-Test

| Aufruf | Ergebnis |
|---|---|
| `just runtime-audit` | 7 Apps, 7 Compose, 16 Container, 25 OK, 11 INFO, 1 WARN, 0 FAIL, exit 0 |
| `just runtime-audit-quiet` | nur WARN-Zeilen + Summary, exit 0 |
| `just runtime-audit-strict` | exit 1 wegen 1 WARN |
| `just runtime-audit --json` | strukturierte Ausgabe `summary` + `findings` |

Findings im aktuellen Stack:
- **OK**: alle `apps/<id>/compose.yml` validieren, Registry-Ports passen.
- **INFO** (11x): 7 App-Container + 4 Authentik-Container haben `container_name`
  auch in Root-Compose -- erwartete Kompatibilitaet (kein Parallelstart).
- **WARN** (1x): `AUTHENTIK_ENABLED=false` in `.env.example`, aber Authentik-Container
  laufen aus Phase-1-Bootstrap. Bewusst toleriert.
- **FAIL** (0): keine `container_name`-Konflikte zwischen modularen Compose,
  keine 0.0.0.0-Bindings, keine unhealthy Container, keine Port-Mismatches.

## Audit-Report-Integration

`just audit-report` ruft jetzt am Ende `registry-audit --quiet` und
`runtime-audit --quiet` auf. Wenn Docker nicht erreichbar ist, wird der
runtime-Teil mit einer WARN-Zeile uebersprungen statt das Skript abzubrechen.

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

## Migration-Werkzeuge (Phase 1, Dry-Run only)

| Aufruf | Ergebnis |
|---|---|
| `just migration-status` | 7 Apps, alle `safe=yes`, alle `source=root`, exit 0 |
| `just migrate-dry-run homepage` | Registry/Dateien/Container/Root-Match OK, Empfehlung print-commands |
| `just migrate-plan homepage` | 5-Schritt-Plan mit `compose.observability.yml` als Root-Match |
| `just migrate-rollback-plan homepage` | `just app-down` + `up -d homepage` aus Root-Compose |
| `scripts/migrate-app.sh authentik --dry-run` | exit 2 (separate Migrationsphase) |
| `scripts/migrate-app.sh unknown --dry-run` | exit 2 (Registry-FAIL) |
| `scripts/migrate-app.sh homepage --execute` | exit 1, Phase-1-Hinweis |

Read-only verifiziert: keine `docker stop/start/restart`, kein
`docker compose up/down` durch Migration-Skripte (im read-only-Modus).

## Migration-Phase-2 (homepage --execute)

| Aufruf | Ergebnis |
|---|---|
| `scripts/backup-age.sh homepage` (ohne Backup) | WARN + RECOMMEND, exit 2 |
| `scripts/migrate-app.sh paperless --execute` | FAIL paperless gesperrt, exit 2 |
| `scripts/migrate-app.sh authentik --execute` | FAIL separate Phase, exit 2 |
| `scripts/migrate-app.sh convertx --execute --yes-i-am-sure` | FAIL allow-list, exit 2 |
| `scripts/migrate-app.sh homepage --execute` (ohne Confirm) | ERROR braucht --yes-i-am-sure, exit 1 |
| `just migrate-execute-homepage` | Preflight + Backup + Cutover + Healthcheck-Loop |

Execute fuehrt aus:
1. Preflight (10 Checks)
2. `just backup-app homepage` + `backup-age` Verifikation
3. `docker compose stop homepage && rm -f homepage` aus Root-Compose-Match
4. `just app-up homepage`
5. Healthcheck-Loop bis 60s (12x5s)
6. Bei Fehler: automatischer Rollback (app-down + Root up -d)
7. Post-Audit: runtime-audit + migration-status

Exit-Codes: 0 OK, 2 Preflight/Migration-Fail, 3 Rollback-Fail.

### Live-Cutover homepage (2026-05-15)

Ausgefuehrt: `just migrate-execute-homepage`, exit 0, **kein Rollback** noetig.

Ablauf-Eckdaten:
- Preflight: 10 von 10 OK.
- Backup-Artefakt: `backups/20260515-121407/homepage-app.tar.gz`.
- Stop+rm filehub-homepage aus `compose.observability.yml` -- Volume blieb erhalten.
- App-Compose-Start: 1 Container erstellt + gestartet.
- Healthcheck-Loop: bestanden bei Versuch 2 (~10s).
- Post-Audit: 25 OK, 11 INFO, 1 WARN (Authentik), 0 FAIL.

Validierung nach Cutover:
| Check | Ergebnis |
|---|---|
| `just app-health homepage` | state=healthy, http=200 |
| HTTP-Probe 127.0.0.1:3001/ | 200 |
| `just migration-status` (homepage) | source=app, run=yes, health=healthy |
| `just apps-status` | alle 7 Apps healthy |
| `just runtime-audit` | 0 FAIL |
| `just backup-age homepage` | OK 0h 0min |
| Andere Apps source | bleiben source=root (paperless, convertx, stirling-pdf, filebrowser, uptime-kuma, dozzle) |

Stand: homepage migriert (source=app), 6 Apps bleiben source=root.
Root-Compose-Datei `compose.observability.yml` bleibt als Rollback-Reserve im Repo.

### Live-Cutover filebrowser (2026-05-15)

Ausgefuehrt: `just migrate-execute-filebrowser`, exit 0, **kein Rollback** noetig.

Ablauf-Eckdaten:
- Reihenfolge-Pruefung: homepage source=app OK.
- Preflight: 10 von 10 OK.
- Backup-Artefakt: `backups/20260515-122438/filebrowser-app.tar.gz`.
- Stop+rm filehub-filebrowser aus `compose.extensions.yml` -- Volume blieb erhalten.
- App-Compose-Start: 1 Container erstellt + gestartet.
- Healthcheck-Loop: bestanden bei Versuch 2 (~10s).
- Post-Audit: 25 OK, 11 INFO, 1 WARN (Authentik), 0 FAIL.

Validierung nach Cutover:
| Check | Ergebnis |
|---|---|
| `just app-health filebrowser` | state=healthy, http=200 |
| HTTP-Probe 127.0.0.1:3003/ | 200 |
| `just migration-status` (filebrowser) | source=app, run=yes, health=healthy |
| `just apps-status` | alle 7 Apps healthy |
| `just runtime-audit` | 0 FAIL |
| `just backup-age filebrowser` | OK 0h 0min |
| Andere Apps source | bleiben source=root (paperless, convertx, stirling-pdf, uptime-kuma, dozzle) |

Stand: homepage + filebrowser migriert (source=app), 5 Apps source=root.
Root-Compose-Datei `compose.extensions.yml` bleibt als Rollback-Reserve im Repo.

### Live-Cutover stirling-pdf (2026-05-15)

Ausgefuehrt: `just migrate-execute-stirling-pdf`, exit 0, **kein Rollback** noetig.

Ablauf-Eckdaten:
- Reihenfolge-Pruefung: homepage + filebrowser source=app OK.
- Preflight: 10 von 10 OK.
- Backup-Artefakt: `backups/20260515-123520/stirling-pdf-app.tar.gz`.
- Stop+rm filehub-stirling-pdf aus `compose.extensions.yml` -- Volume blieb erhalten.
- App-Compose-Start: 1 Container erstellt + gestartet.
- Healthcheck-Loop: bestanden bei Versuch 6 (~25s, Stirling startet etwas langsamer).
- Post-Audit: 25 OK, 11 INFO, 1 WARN (Authentik), 0 FAIL.

Validierung nach Cutover:
| Check | Ergebnis |
|---|---|
| `just app-health stirling-pdf` | state=healthy, http=401 (Basic-Auth, Stirling-Default) |
| `just migration-status` (stirling-pdf) | source=app, run=yes, health=healthy |
| `just apps-status` | alle 7 Apps healthy |
| `just runtime-audit` | 0 FAIL |
| `just backup-age stirling-pdf` | OK 0h 0min |
| Andere Apps source | bleiben source=root (paperless, convertx, uptime-kuma, dozzle) |

Stand: homepage + filebrowser + stirling-pdf migriert (source=app), 4 Apps source=root.

### Live-Cutover paperless (2026-05-15)

Ausgefuehrt: `just migrate-execute-paperless-careful`, exit 0, **kein Rollback** noetig.

Ablauf-Eckdaten:
- Reihenfolge-Pruefung: homepage + filebrowser + stirling-pdf source=app OK.
- Preflight: 10 von 10 OK.
- Backup-Artefakt: `backups/20260515-123914/paperless-app.tar.gz`.
- Stop-Reihenfolge: webserver -> tika -> gotenberg -> redis -> db (alle 5).
- rm -f Reihenfolge: webserver -> tika -> gotenberg -> redis -> db (Volumes erhalten).
- App-Compose-Start: depends_on regelte korrekt Reihenfolge (db,redis,gotenberg,tika -> healthy -> webserver).
- Healthcheck-Loop: paperless-Default 300s/10s, multi-check (5 Container + http-Probe webserver), bestanden bei Versuch 3 (~30s).
- Post-Audit: 25 OK, 11 INFO, 1 WARN (Authentik), 0 FAIL.

Validierung nach Cutover:
| Check | Ergebnis |
|---|---|
| `just app-health paperless` | state=healthy, http=302 (Redirect zu Login) |
| HTTP-Probe 127.0.0.1:8000/ | 302 |
| `just migration-status` (paperless) | source=app, run=yes, health=healthy, +4 Helper |
| `just apps-status` | alle 7 Apps healthy |
| `just runtime-audit` | 0 FAIL |
| `just backup-age paperless` | OK 0h 1min |
| Bind-Mounts | identische Pfade in App- und Root-Compose -> Daten erhalten |
| Andere Apps source | bleiben source=root (convertx, uptime-kuma, dozzle) |

Stand: homepage + filebrowser + stirling-pdf + paperless migriert (source=app), 3 Apps source=root.

### Live-Cutover convertx (2026-05-15)

Ausgefuehrt: `just migrate-execute-convertx`, exit 0, **kein Rollback** noetig.

Eckdaten:
- Reihenfolge-Pruefung: 4 Vorgaenger source=app OK.
- Preflight 10/10 OK.
- Backup: `backups/20260515-132715/convertx-app.tar.gz`.
- Stop+rm `filehub-convertx` aus `compose.convertx.yml` (Volume erhalten).
- Healthcheck-Loop: bestanden bei Versuch 2 (~10s).
- Post-Audit: 0 FAIL.

Validierung nach Cutover:
| Check | Ergebnis |
|---|---|
| `just app-health convertx` | state=healthy, http=302 |
| HTTP-Probe 127.0.0.1:3000/ | 302 |
| `just migration-status` (convertx) | source=app, healthy |
| `just runtime-audit` | 0 FAIL |
| `just backup-age convertx` | OK 0h 0min |

Stand: homepage + filebrowser + stirling-pdf + paperless + convertx migriert (source=app), 2 Apps source=root.

### Live-Cutover uptime-kuma (2026-05-15)

Ausgefuehrt: `just migrate-execute-uptime-kuma`, exit 0, **kein Rollback** noetig.

Eckdaten:
- Reihenfolge-Pruefung: 5 Vorgaenger source=app OK.
- Preflight 10/10 OK.
- Backup: `backups/20260515-132856/uptime-kuma-app.tar.gz`.
- Stop+rm `filehub-uptime-kuma` aus `compose.observability.yml` (Volume erhalten).
- Healthcheck-Loop: uptime-kuma-Default 120s/5s, bestanden bei Versuch 2 (~10s).
- Post-Audit: 0 FAIL.

Validierung nach Cutover:
| Check | Ergebnis |
|---|---|
| `just app-health uptime-kuma` | state=healthy, http=302 |
| HTTP-Probe 127.0.0.1:3002/ | 302 (Login-Redirect) |
| `just migration-status` (uptime-kuma) | source=app, healthy |
| `just runtime-audit` | 0 FAIL |
| `just backup-age uptime-kuma` | OK 0h 0min |

Stand: 6 Apps migriert (source=app), nur dozzle source=root. Authentik separate Sonderphase.

### Live-Cutover dozzle (2026-05-15)

Ausgefuehrt: `just migrate-execute-dozzle`, exit 0, **kein Rollback** noetig.

Eckdaten:
- Reihenfolge-Pruefung: 6 Vorgaenger source=app OK.
- Preflight 10/10 OK.
- Backup: `backups/20260515-134505/dozzle-app.tar.gz`.
- Stop+rm `filehub-dozzle` aus `compose.observability.yml`.
- Healthcheck-Loop: bestanden bei Versuch 7 (~35s, Dozzle braucht Indexierung).
- Post-Audit: 0 FAIL.

Validierung nach Cutover:
| Check | Ergebnis |
|---|---|
| `just app-health dozzle` | state=healthy, http=200 |
| HTTP-Probe 127.0.0.1:9999/ | 200 |
| `just migration-status` (dozzle) | source=app, healthy |
| `just runtime-audit` | 0 FAIL |
| `just backup-age dozzle` | OK 0h 0min |

**Stand: alle 7 Apps source=app, healthy. Modulare Runtime-Migration der App-Schicht abgeschlossen.** Nur Authentik bleibt in separater Sonderphase aus Root-Compose.

### Neue Apps: grafana + whisper-asr (2026-05-15)

Zwei neue App-Module installiert und registriert. Beide live healthy,
keine bestehende App veraendert.

| App | Port | default_enabled | Image | Healthcheck |
|---|---|---|---|---|
| grafana | 3005 | true | grafana/grafana:11.4.0 | /api/health -> 200 |
| whisper-asr | 9001 | false (opt-in) | onerahmet/openai-whisper-asr-webservice:v1.7.0 (CPU) | /docs -> 200 |

Grafana-Spezifikum: `user: ${PUID:-1000}:${PGID:-1000}` im compose.yml,
weil Grafana-Default-UID 472 nicht ins Host-owned `data/grafana`
schreiben kann. Erst-Init lief mit FILEHUB_ADMIN_USER/PASSWORD aus
.env; spaetere Passwortaenderung via Grafana-UI.

Whisper-ASR-Spezifikum: CPU-Variante (kein -gpu), `start_period 120s`
fuer Modelldownload, `data/whisper-asr/cache` bewusst NICHT im
backup.include (gross + reproduzierbar).

Validierung:
| Check | Ergebnis |
|---|---|
| `docker compose config -q apps/grafana/compose.yml` | OK |
| `docker compose config -q apps/whisper-asr/compose.yml` | OK |
| `just registry-audit` | 9 Apps, 3 Infra, 129 OK, 0 WARN, 0 FAIL |
| `just runtime-audit` | 31 OK, 12 INFO, 1 WARN (Authentik), 0 FAIL, 18 Container |
| `just app-health grafana` | state=healthy, http=200 |
| `just app-health whisper-asr` | state=healthy, http=200 |
| `just backup-app grafana` | OK, `backups/20260515-141230/grafana-app.tar.gz` |
| `just backup-app whisper-asr` | OK, `backups/20260515-141230/whisper-asr-app.tar.gz` |
| `just homepage-generate` | 8 Services (whisper-asr ausgeschlossen wegen default_enabled=false) |
| `just secrets-audit` | alle Pruefungen bestanden |
| `just apps-status` | 9 Apps healthy |

Caddy-Snippets fuer beide Apps angelegt (`caddy.disabled` +
`caddy.authentik.disabled`), **default deaktiviert** - `just caddy-list`
zeigt keine neuen aktiven Snippets.

### Gateway-Cutover live (2026-05-15)

Ausgefuehrt manuell (Schritt-fuer-Schritt aus `docs/GATEWAY_MIGRATION_RUNBOOK.md`),
exit 0, **kein Rollback** noetig.

Eckdaten:
- Caddyfile-Backup: `config/caddy/filehub-gateway.Caddyfile.bak.20260515-142551`
  (lokal, nicht im Git).
- Stop+rm filehub-gateway aus `compose.auth.yml`.
- Start aus `infra/gateway/compose.yml`.
- Caddy validate: OK (`automatic HTTPS is completely disabled`, kein Fehler).
- HTTP-Probe /_health: 200, root: 302 (Forward-Auth-Redirect).
- gateway-bootstrap-check: STATE=POST-BOOTSTRAP.
- gateway-migration-status: SOURCE=infra, HEALTH=healthy.
- runtime-audit: `OK gateway filehub-gateway laeuft aus infra/gateway/`.

Stand: Gateway modular, Authentik-Cutover bleibt naechster Schritt.

### Gateway-Modularisierung vorbereitet (2026-05-15)

`infra/gateway/compose.yml` ist angelegt, aber **noch nicht aktiv**.
filehub-gateway laeuft weiterhin aus `compose.auth.yml`.

Compose-Parity-Check (alle OK):
| Datei | docker compose config -q |
|---|---|
| `infra/gateway/compose.yml` | OK |
| `infra/authentik/compose.yml` | OK |
| `compose.auth.yml` | OK |

Status-Tools:
| Tool | Ergebnis |
|---|---|
| `just gateway-migration-status` | RUN=yes, HEALTH=healthy, SOURCE=root, SAFE=yes |
| `just gateway-status` | health=200, root=302 |
| `just gateway-bootstrap-check` | STATE=POST-BOOTSTRAP |
| `just runtime-audit` | 25 OK, 12 INFO (inkl. gateway=root), 1 WARN (Authentik), 0 FAIL |
| `just registry-audit` | 103 OK, 0 WARN, 0 FAIL |
| `just secrets-audit` | alle Pruefungen bestanden |

**Geloeste Diskrepanzen** (gegenueber dem Authentik-Runbook):
1. Gateway-Service fehlt im Infra-Modul -> `infra/gateway/compose.yml` angelegt.
2. `filehub_net` external -> im Gateway-Infra-Modul explizit als `external: true`.
3. `caddy-gateway`-Volumes -> als Bind-Mounts mit `../../data/...`-Praefix.
4. `FILEHUB_GATEWAY_PORT`-Default -> in `infra/gateway/.env.example` dokumentiert.

**Verbleibende Diskrepanzen** (dokumentiert, nicht gefixt):
5. Bind-Mount-Diff-Check noch nicht automatisiert.
6. Image-Tag `caddy:2.8-alpine` weiterhin hardcoded.
7. `name: filehub`-Direktive unterschiedlich (faktisch konsistent).

### Phase C abgeschlossen

| App | Status | Healthcheck-Loop |
|---|---|---|
| stirling-pdf | source=app | ~25s (Versuch 6) |
| paperless | source=app | ~30s (Versuch 3, 300s/10s Defaults) |

### Migrationsreihenfolge im Code

`scripts/migrate-app.sh` haelt `MIGRATION_ORDER`:
```
homepage filebrowser stirling-pdf paperless convertx uptime-kuma dozzle
```
Vor `--execute` werden alle Vorgaenger gegen `migration-status --json`
gepuneft (`source=app` erforderlich). `--override-order` Notfall-Flag
(nicht fuer paperless). Allow-Liste aktuell: `homepage, filebrowser`.

## Keine destruktiven Aenderungen

- Keine Container neu gestartet, kein `docker compose down`.
- Keine Volumes geloescht oder umbenannt.
- Keine Restic-Snapshots geloescht.
- Keine Public-Bindings veraendert (alle weiterhin 127.0.0.1).
- `services.yaml` der Homepage unveraendert (`services.generated.yaml` ist Output).
