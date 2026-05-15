# Phase C Notes: stirling-pdf + paperless

Erstellt: 2026-05-15. Phase C ist der fachliche Block "Dokumentenverarbeitung".
Technisch werden beide Apps einzeln migriert. Diese Notiz fasst die
Dry-Run-Ergebnisse und die noch offenen Voraussetzungen zusammen.

Stand (nach Phase C abgeschlossen, 2026-05-15):
- `homepage` source=app (Phase A).
- `filebrowser` source=app (Phase B).
- `stirling-pdf` source=app (Phase C-1, ~25s Healthcheck).
- `paperless` source=app (Phase C-2, ~30s Multi-Container-Healthcheck).

## stirling-pdf

Dry-Run: `just migrate-dry-run stirling-pdf`

```
-- App-Dateien --
OK   apps/stirling-pdf/compose.yml vorhanden
OK   apps/stirling-pdf/backup.include vorhanden
OK   apps/stirling-pdf/healthcheck.sh vorhanden und executable
-- Container-Status (primary) --
INFO primary container_name: filehub-stirling-pdf
INFO run=yes health=healthy source=root
OK   source=root - sicher zu migrieren (Cutover sinnvoll)
-- Root-Compose-Match --
OK   filehub-stirling-pdf -> compose.extensions.yml (service: stirling-pdf)
-- Empfehlung --
EMPFEHLUNG: stirling-pdf aktuell safe=yes.
```

Plan: `just migrate-plan stirling-pdf`

```
just backup-app stirling-pdf
docker compose -f compose.yml -f compose.extensions.yml stop stirling-pdf
docker compose -f compose.yml -f compose.extensions.yml rm -f stirling-pdf
just app-up stirling-pdf
just app-health stirling-pdf
just runtime-audit
```

Rollback: `just migrate-rollback-plan stirling-pdf`

```
just app-down stirling-pdf
docker compose -f compose.yml -f compose.extensions.yml up -d stirling-pdf
just runtime-audit
```

### Phase-C-Schritt 1: stirling-pdf zuerst

Stirling ist zustandslos (nur temporaere Daten), Cutover ist
strukturell identisch zu homepage/filebrowser. Healthcheck-Loop in
Default-Werten ausreichend (60s/5s).

Status: **bereit, Execute noch nicht freigegeben**. Allow-Liste
muss in `scripts/migrate-app.sh` um `stirling-pdf` erweitert werden,
dann `just migrate-execute-stirling-pdf` (Target noch nicht angelegt)
oder direkt `scripts/migrate-app.sh stirling-pdf --execute --yes-i-am-sure`.

## paperless (Sonderfall)

Dry-Run: `just migrate-dry-run paperless`

```
-- App-Dateien --
OK   apps/paperless/compose.yml vorhanden
OK   apps/paperless/backup.include vorhanden
OK   apps/paperless/healthcheck.sh vorhanden und executable
-- Container-Status (primary) --
INFO primary container_name: filehub-paperless-db
INFO run=yes health=healthy source=root
OK   source=root - sicher zu migrieren (Cutover sinnvoll)
-- Root-Compose-Match --
OK   filehub-paperless-db -> compose.paperless.yml (service: paperless-db)
-- Weitere Container in apps/paperless/compose.yml --
INFO helper-container: filehub-paperless-redis
INFO helper-container: filehub-paperless-tika
INFO helper-container: filehub-paperless-gotenberg
INFO helper-container: filehub-paperless-webserver
WARN paperless hat Helper-Container (db/redis/tika/gotenberg)
```

Plan (zu generisch, **NICHT ausreichend**):

```
just backup-app paperless
docker compose -f compose.yml -f compose.paperless.yml stop paperless-db
docker compose -f compose.yml -f compose.paperless.yml rm -f paperless-db
just app-up paperless
just app-health paperless
just runtime-audit
```

Problem: stoppt nur `paperless-db`, nicht die anderen 4 Container
(webserver, redis, tika, gotenberg). Diese liefen weiter aus
`compose.paperless.yml` und wuerden den App-Compose-Start blockieren
(container_name-Konflikt).

### TODOs vor Paperless-Execute (nicht in dieser Phase)

1. **Paperless-spezifische Stop-Sequenz** in `migrate-app.sh`:
   - Reihenfolge: webserver -> tika -> gotenberg -> redis -> db
   - `--allow-paperless` muss alle 5 Service-Namen anwenden.
2. **Paperless-spezifische Start-Sequenz** (durch App-Compose i.d.R.
   automatisch, aber `depends_on` validieren).
3. **Healthcheck-Loop verlaengern**:
   - `MIGRATE_HEALTH_TIMEOUT_SECONDS=300`
   - Healthcheck muss alle 5 Container pruefen, nicht nur den Primary.
4. **Pflicht-Backup**: `just backup-app paperless` -- ist schon Teil
   der Execute-Logik, nur Dokumentation explizit erwaehnen.
5. **Restore-Hinweis dokumentieren**:
   - DB-Wiederherstellung: `backups/<TS>/paperless-postgres.sql`
   - Daten-Wiederherstellung: Restic-Snapshot `data/paperless`
   - Reihenfolge im Restore-Runbook ergaenzen.
6. **Wartungsfenster ansagen**: Postgres-Restart + Index-Rebuild kann
   mehrere Minuten dauern. Live-Suche im Paperless-UI ist waehrenddessen
   unverfuegbar.

### Sperre

`scripts/migrate-app.sh paperless --execute` bricht mit exit 2 ab,
auch mit `--yes-i-am-sure`. Sonderfreigabe nur ueber
`--allow-paperless` + `--yes-i-am-sure` *und* Aufnahme von `paperless`
in die Allow-Liste. Beides bewusst nicht in dieser Phase.

## Naechster Schritt (Phase D)

Phase C ist abgeschlossen. Naechster geplanter Live-Cutover: **convertx**.
ConvertX hat eigene SQLite-Volumes, ist aber Single-Container und
strukturell vergleichbar zu homepage/filebrowser/stirling-pdf.

Vor Phase D:
1. Allow-Liste in `migrate-app.sh` um `convertx` erweitern.
2. `just migrate-execute-convertx` Target anlegen.
3. Live-Cutover convertx.
4. Danach Phase E: uptime-kuma. Phase F: dozzle. Danach Authentik in
   separater Sonderphase (eigene Doku).
