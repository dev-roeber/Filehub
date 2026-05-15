# Operations

Taegliche Betriebskommandos fuer Filehub. Alle Kommandos sind ueber das
Justfile gebuendelt und arbeiten gegen die App-Registry `config/apps.yml`.

## Status und Audit

```
just apps-status            # Compose-Status aller registrierten Apps
just infra-status           # Status der Infrastruktur (Gateway, Backup, Authentik)
just audit-report           # Gesamt-Report (inkl. registry- + runtime-audit)
just registry-audit         # Datei-Konsistenz Registry <-> Filesystem
just registry-audit-quiet   # nur WARN/FAIL + Summary
just runtime-audit          # Drift Registry <-> Compose <-> laufende Container
just runtime-audit-quiet    # nur WARN/FAIL + Summary
just runtime-audit-strict   # WARN -> exit 1 (fuer CI/Schedules)
```

### registry-audit vs runtime-audit

| Ebene | Prueft | Quelle |
|---|---|---|
| registry-audit | Dateistruktur: id-Regex, Pflicht-Artefakte, Registry-Pfade, Port-Uniqueness | nur Dateisystem |
| runtime-audit | Drift: `docker compose config`, container_name-Konflikte, Hostport-Bindings, laufende Container, Health, Authentik-Status | Docker + Dateisystem |

Empfohlene Reihenfolge: erst `registry-audit` (Struktur), dann `runtime-audit`
(Live-Zustand). `audit-report` ruft beide nacheinander.

### Klassifikation der Findings

- **OK**: erwartet und korrekt.
- **INFO**: bewusste Kompatibilitaet (z.B. identischer `container_name` in
  `apps/<id>/compose.yml` und Root-`compose.*.yml` — siehe unten).
- **WARN**: Drift, der manuelles Nachsehen rechtfertigt (fehlender optionaler
  Artefakt, Authentik laeuft obwohl `AUTHENTIK_ENABLED=false`, starting Health,
  Container ohne Healthcheck). Bricht Default-Lauf nicht ab; `--strict` schon.
- **FAIL**: harte Drift (container_name-Konflikt zwischen zwei modularen
  Compose-Dateien, `0.0.0.0`-Bind auf App-Container, Registry-Port stimmt
  nicht mit Compose-Port ueberein, unhealthy Container). Exit 2.

Exit-Codes:
- 0 bei `FAIL=0` (WARN toleriert).
- 1 bei `--strict` und WARN>0.
- 2 bei FAIL>0.

### Root-Compose vs apps/&lt;id&gt;/compose.yml

`container_name` ist in beiden Welten identisch, damit ein gradueller
Wechsel ohne Bruch moeglich ist. **Niemals beide gleichzeitig starten** —
Docker lehnt einen zweiten Start mit dem gleichen Namen ab und der laufende
Stack waere unbrauchbar. `runtime-audit` markiert diese Doppelnennung als
INFO. Aktiver Betrieb laeuft weiterhin aus Root-Compose; die modularen
`apps/<id>/compose.yml` stehen fuer den geplanten spaeteren Cutover bereit.

### 127.0.0.1-Bindings

`runtime-audit` parsed `ports:`-Bloecke aus jeder `apps/<id>/compose.yml`
und meldet abweichende Bindings:
- `0.0.0.0:<port>:` auf einem App-Container: **FAIL**.
- Bind ohne Host-Praefix: **WARN** (Docker bindet defaultmaessig 0.0.0.0).
- `127.0.0.1:<port>:`: OK.

Authentik-Container sind von dieser Regel ausgenommen, weil sie ohne
Hostport laufen und der Gateway sie ueber `authentik_net` erreicht.

### Authentik bleibt optional

`runtime-audit` liest `AUTHENTIK_ENABLED` zuerst aus `.env`, fallback
`.env.example`. Inkonsistenzen werden als WARN ausgegeben (nicht FAIL),
damit der Phase-1-Bootstrap-Stack weiterlaufen kann, ohne den Audit rot
zu faerben.

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

## Migration zwischen Root-Compose und apps/<id>/

Werkzeuge (read-only, Phase 1):

```
just migration-status               # Tabelle pro App: source/safe
just migrate-dry-run <app>          # Pre-Check + Empfehlung
just migrate-plan <app>             # geplante Cutover-Befehle
just migrate-rollback-plan <app>    # geplanter Rollback
just backup-age <app>               # Existenz + Alter des App-Backups
```

Execute (sukzessive Freigabe je App):

```
just migrate-execute-homepage             # Phase A, erledigt
just migrate-execute-filebrowser          # Phase B, erledigt
just migrate-execute-stirling-pdf         # Phase C-1, erledigt
just migrate-execute-paperless-careful    # Phase C-2, erledigt (Multi-Container)
just migrate-execute-convertx             # Phase D, erledigt
just migrate-execute-uptime-kuma          # Phase E, erledigt (120s Healthcheck-Default)
just migrate-execute-dozzle              # Phase F, erledigt
# Alle 7 Apps migriert. authentik separate Sonderphase.
```

Die Reihenfolge (homepage -> filebrowser -> stirling-pdf -> paperless ->
convertx -> uptime-kuma -> dozzle) ist in `scripts/migrate-app.sh`
hartcodiert (`MIGRATION_ORDER`). Vorgaenger-Check vor jedem Execute.

Sperren in der Execute-Logik:
- Nur `homepage` auf der Allow-Liste.
- `paperless` und `authentik` sind hart blockiert (separate Phase).
- Pflicht-Flag `--yes-i-am-sure`, sonst Abbruch (exit 1).
- Preflight: 10 Checks (Compose-Dateien, registry-audit, runtime-audit,
  source=root, Root-Match eindeutig, keine Duplikate).
- Backup ist Pflicht (`just backup-app <app>`), Verifikation via
  `scripts/backup-age.sh --quiet`.
- Healthcheck-Loop 12x5s nach `just app-up`.
- Bei Fehler: automatischer Rollback (`just app-down` + Root `up -d`),
  keine Volume-Loeschung.

Volle Details siehe `docs/MODULAR_RUNTIME_MIGRATION.md`.

## Neue Apps (2026-05-15)

- **grafana** (Port 3005, `default_enabled=true`): Metrics-Dashboards.
  Image `grafana/grafana:11.4.0`, laeuft als Host-PUID. Erst-Admin
  via `FILEHUB_ADMIN_PASSWORD`. Provisioning optional unter
  `config/grafana/provisioning/`.
- **whisper-asr** (Port 9001, `default_enabled=false` - opt-in):
  Speech-to-Text. Image
  `onerahmet/openai-whisper-asr-webservice:v1.7.0` (CPU). Hoher
  RAM-Bedarf; Modellcache bewusst NICHT im Backup.

## Verweise

- `docs/APPS.md` -- App-Liste und Quickstart.
- `docs/BACKUP.md` -- Modulares Backup.
- `docs/update-runbook.md` -- detaillierter Update-Runbook.
- `docs/operations.md` -- bestehende Ops-Notizen (kleines o).
- `docs/MODULAR_RUNTIME_MIGRATION.md` -- Cutover-Plan + Execute-Details.

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
