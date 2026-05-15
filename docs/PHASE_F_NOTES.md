# Phase F Notes: dozzle + authentik (Restphase)

Erstellt: 2026-05-15. Phase F ist die Restphase nach Abschluss von
Phasen A-E. Dozzle bleibt der letzte regulaere App-Cutover; Authentik
ist eine komplett separate Sonderphase mit eigenem Backup-/Restore-Plan.

Stand:
- A: homepage source=app.
- B: filebrowser source=app.
- C-1: stirling-pdf source=app.
- C-2: paperless source=app (Multi-Container).
- D: convertx source=app.
- E: uptime-kuma source=app.
- **F: dozzle source=root, vorbereitet, noch nicht ausgefuehrt.**
- Authentik: separate Sonderphase, weiterhin Drift-WARN aus
  Phase-1-Bootstrap erwartet.

## dozzle

Dozzle ist Diagnose-Werkzeug, das nur den Docker-Socket liest.
Kein eigener State, keine Daten. Risiko-Profil identisch zu
homepage (zustandsloses Dashboard).

Dry-Run: `just migrate-dry-run dozzle`

```
OK   apps/dozzle/compose.yml vorhanden
OK   apps/dozzle/backup.include vorhanden
OK   apps/dozzle/healthcheck.sh vorhanden und executable
INFO primary container_name: filehub-dozzle
INFO run=yes health=healthy source=root
OK   source=root - sicher zu migrieren (Cutover sinnvoll)
OK   filehub-dozzle -> compose.observability.yml (service: dozzle)
EMPFEHLUNG: dozzle aktuell safe=yes.
```

Plan: `just migrate-plan dozzle`

```
just backup-app dozzle
docker compose -f compose.yml -f compose.observability.yml stop dozzle
docker compose -f compose.yml -f compose.observability.yml rm -f dozzle
just app-up dozzle
just app-health dozzle
just runtime-audit
```

Rollback: `just migrate-rollback-plan dozzle`

```
just app-down dozzle
docker compose -f compose.yml -f compose.observability.yml up -d dozzle
just runtime-audit
```

### Warum dozzle als Letzter

Dozzle ist das Log-Inspektions-Werkzeug. Solange andere Migrationen
laufen, bleibt es vorteilhaft, dass Dozzle stabil aus Root-Compose
verfuegbar ist: ein fehlgeschlagener Cutover anderer Apps kann via
Dozzle-UI nachvollzogen werden, ohne dass Dozzle selbst betroffen
ist. Erst nach allen anderen Cutovers ist Dozzle dran.

### Naechste Schritte fuer Dozzle-Cutover (nicht in dieser Phase)

1. `EXECUTE_ALLOWED_APPS` in `scripts/migrate-app.sh` um `dozzle`
   erweitern.
2. `just migrate-execute-dozzle` Target im justfile anlegen.
3. Live-Cutover analog zu homepage.

## authentik (separate Sonderphase)

Authentik ist explizit **keine App** im Sinne der Phasen A-F,
sondern Identity-Provider-Infrastruktur. `migrate-app.sh authentik`
bricht weiterhin mit exit 2 ab.

### Erwartbare Drift-WARN

`just runtime-audit` meldet 1x WARN:
```
WARN authentik AUTHENTIK_ENABLED=false, aber Authentik-Container laufen
     (Phase-1-Bootstrap-Kompatibilitaet)
```
Das ist nach wie vor gewollt: `.env.example` setzt den Default auf
`false`, aber im Phase-1-Bootstrap wurden Authentik-Container
manuell gestartet. Solange das so ist, bleibt die WARN sichtbar.

### Authentik-Migrationsplan (Skizze, nicht ausgefuehrt)

1. **Backup**:
   - `pg_dump` ueber `filehub-authentik-db`
   - Redis-Dump ueber `filehub-authentik-redis`
   - Provider-Definitionen aus Authentik-UI exportieren
   - `backups/<TS>/authentik-postgres.sql`, `authentik-redis-dump.rdb`,
     `authentik-data.tar.gz` werden bereits durch
     `FILEHUB_BACKUP_ONLY_APP=authentik scripts/backup.sh` erzeugt.
2. **Cutover**:
   - `compose.auth.yml` -> `infra/authentik/compose.yml`
   - Vorsicht: gleiche Volume-Konvention pruefen
   - Stop-Reihenfolge: server, worker, redis, db
   - Start ueber `just auth-up` (mit `AUTHENTIK_ENABLED=true` in `.env`)
3. **Verification**:
   - `just auth-status` -> 302
   - `just gateway-bootstrap-check` -> POST-BOOTSTRAP
   - Provider-Konfiguration manuell prufen
4. **Rollback**:
   - `auth-down` + `compose.auth.yml up -d`
   - Bei DB-Problem: pg_restore aus `backups/<TS>/authentik-postgres.sql`

Authentik braucht ein eigenes Wartungsfenster mit angekuendigter
Login-Unverfuegbarkeit. Forward-Auth-protected Apps werden in dieser
Zeit nicht erreichbar sein.

### Sperre im Code

`scripts/migrate-app.sh authentik` bricht **bei jedem Modus** mit
exit 2 ab. Es gibt kein `--allow-authentik` und kein Justfile-Target.
Das ist bewusst so: Authentik braucht ein eigenes Script.

## Was nicht passieren darf

- Bereits migrierte Apps (Phasen A-E) **nicht** wieder aus
  Root-Compose starten. Docker blockt durch `container_name`-Konflikt,
  aber der Fehlversuch verwirrt das State-Tracking.
- Root-Compose-Dateien (`compose.*.yml`) **nicht** loeschen. Sie
  bleiben als Rollback-Reserve im Repo.
- Authentik **nicht** ohne pg_dump anfassen.
- Dozzle-Cutover **nicht** vorzeitig durchziehen, solange kein
  Wartungsfenster oder kein Bedarf besteht.

## Aktueller migration-status (nach Phase E)

```
homepage      source=app    healthy   (Phase A)
filebrowser   source=app    healthy   (Phase B)
stirling-pdf  source=app    healthy   (Phase C-1)
paperless     source=app    healthy   (Phase C-2, +4 Helper)
convertx      source=app    healthy   (Phase D)
uptime-kuma   source=app    healthy   (Phase E)
dozzle        source=root   healthy   (Phase F, vorbereitet)
authentik     separate Sonderphase, weiterhin Drift-WARN
```

6 von 7 Apps aus `apps/<id>/compose.yml`. Nur Dozzle steht noch aus.
