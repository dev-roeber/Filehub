# Modular Runtime Migration

Plan und Werkzeuge fuer den schrittweisen Cutover vom Root-Compose-Betrieb
auf den modularen Betrieb mit `apps/<id>/compose.yml`.

Diese Phase ist Vorbereitung: **keine App wird hier live migriert**. Sie
beschreibt die Vorgehensweise, Reihenfolge und Werkzeuge.

## Ziel

- Endzustand: jede App laeuft ausschliesslich aus `apps/<id>/compose.yml`.
- Root-Compose-Dateien bleiben fuer Rollback erhalten, werden aber nicht
  mehr aktiv gestartet.
- Single-User-Konventionen (`FILEHUB_ADMIN_USER/PASSWORD`) bleiben gueltig.
- Authentik bleibt eine eigene, optionale Migrationsphase.

## Warum kein Parallelbetrieb

`apps/<id>/compose.yml` und Root-`compose.*.yml` benutzen denselben
`container_name`. Docker akzeptiert keinen zweiten Container mit gleichem
Namen. Wer beide gleichzeitig hochfaehrt, blockiert den eigenen Start und
laeuft Gefahr, halbe Stacks zu hinterlassen. **Pro App immer nur eine
Welt aktiv.** Der `runtime-audit` markiert diese gewollte Doppelnennung
als INFO.

## Vorbedingungen vor jedem Cutover

1. Aktuelles Backup: `just backup-app <app>`.
2. `just registry-audit` grun (0 FAIL).
3. `just runtime-audit` ohne FAIL (WARNs durch Authentik-Bootstrap sind okay).
4. `just migration-status` zeigt `safe=yes` fuer die Ziel-App.
5. Falls Authentik lokal laeuft: `AUTHENTIK_ENABLED=true` in `.env` setzen,
   damit `runtime-audit-strict` nicht durch den Drift-WARN failt
   (`.env.example` bleibt auf `false`).
6. Kein anderer paralleler Stack-Start im selben Terminal.

## Reihenfolge

Diese Reihenfolge ist **verbindlich** und im Code in `scripts/migrate-app.sh`
als `MIGRATION_ORDER` hinterlegt. Vor jedem `--execute` prueft das Skript,
ob alle Vorgaenger `source=app` haben.

| Phase | App | Status |
|---|---|---|
| A | homepage | erledigt (2026-05-15) |
| B | filebrowser | erledigt (2026-05-15) |
| C-1 | stirling-pdf | erledigt (2026-05-15) |
| C-2 | paperless | erledigt (2026-05-15, Multi-Container-Cutover) |
| D | convertx | erledigt (2026-05-15) |
| E | uptime-kuma | erledigt (2026-05-15, 120s/5s Healthcheck-Default) |
| F | dozzle | vorbereitet, Dry-Run gruen, naechster Live-Cutover |
| -- | authentik | separate Sonderphase, blockiert in migrate-app.sh |

### Warum diese Reihenfolge

- **homepage** zuerst, weil zustandslos und niedrigster Blast-Radius.
- **filebrowser** vor allem anderen, weil Bind-Mount auf Datenverzeichnis
  schon dezentralisiert ist und Rollback einfach.
- **stirling-pdf + paperless** als fachlicher Block (Dokument-Workflow),
  technisch getrennt migriert. Stirling zuerst (zustandslos), dann
  Paperless (DB + 3 Helper, Wartungsfenster).
- **convertx** nach dem Dokument-Block, weil App-eigene SQLite-Volumes.
- **uptime-kuma** nach convertx, weil Monitor-State.
- **dozzle** als letzter Schritt -- nicht vorziehen, obwohl risikoarm.
  Begruendung: Dozzle ist Diagnose-Werkzeug. Solange noch andere Apps
  migrieren, soll Dozzle aus Root-Compose erreichbar bleiben, um
  Logs zu zeigen, falls eine Migration in den Rollback geht.
- **authentik** in einer komplett eigenen Phase, mit pg_dump + Redis
  + Provider-Export.

### Reihenfolge erzwingen / umgehen

- `--override-order` umgeht die Pruefung, **aber nicht fuer paperless**.
- Paperless braucht zusaetzlich `--allow-paperless --yes-i-am-sure`.
- `--override-order` ist ein Notfall-Flag (z.B. Wiederholung nach
  Teil-Migration). Standard ist immer die harte Reihenfolge.

### Warum `safe=no` fuer bereits migrierte Apps

`migration-status` markiert eine App als `safe=no`, sobald
`source=app`. Das ist kein Fehler: es zeigt "nicht (mehr) migrierbar",
weil schon migriert. Falls eine bereits migrierte App im Status als
`safe=no` auftaucht, ist das gewuenscht und braucht keine Aktion.

## Standardablauf pro App

```
# 0) Status erfassen
just migration-status
just migrate-dry-run <app>

# 1) Befehlsplan ansehen
just migrate-plan <app>

# 2) Backup ziehen
just backup-app <app>

# 3) Root-Service stoppen (kein down -v, kein Volume-Loeschen)
docker compose -f compose.yml -f <root-match.yml> stop <service>
docker compose -f compose.yml -f <root-match.yml> rm -f <service>

# 4) App-Compose starten
just app-up <app>

# 5) Healthcheck
just app-health <app>

# 6) Drift-Audit
just runtime-audit
```

Die konkreten Werte fuer `<root-match.yml>` und `<service>` liefert
`just migrate-plan <app>`. Nichts auswendig lernen.

## Rollback-Prinzip

Rollback ist immer "App-Compose runter, Root-Compose hoch". Keine
Volumes oder Daten anfassen. Volumes ueberleben den Wechsel, weil
Docker-Volumes nicht an die Compose-Datei gebunden sind, sondern
projekt-/labelgebunden. Beide Welten haben dasselbe Projekt (`filehub`)
und gleiche Volume-Namen.

```
# Rollback fuer <app>
just app-down <app>
docker compose -f compose.yml -f <root-match.yml> up -d <service>
just runtime-audit
```

`just migrate-rollback-plan <app>` gibt den exakten Befehl fuer eine
konkrete App aus.

## Sonderfall Paperless

Paperless besteht aus mehreren Containern:
- `filehub-paperless-webserver`
- `filehub-paperless-db` (Postgres)
- `filehub-paperless-redis`
- `filehub-paperless-tika`
- `filehub-paperless-gotenberg`

Konsequenzen:
- Cutover ist nicht 1:1 mit den anderen Apps; die DB muss konsistent
  uebernommen werden.
- Vor dem Stop: **erzwungenes** Backup (`just backup-app paperless`)
  und visuelle Bestaetigung im Backup-Log.
- Laengeres Wartungsfenster einplanen, weil Postgres-Restart und
  Index-Wiederaufbau dauern koennen.
- Der Reihenfolge nach: erst die Helper-Container hochfahren
  (`db`, `redis`, `tika`, `gotenberg`), dann den Webserver.
- Wenn Healthchecks failen: Rollback sofort durchziehen, nicht
  rumbasteln.

### Implementierte Paperless-Sonderlogik (Phase C-2, erledigt)

`migrate-app.sh` behandelt paperless seit Phase C-2 als Multi-Container-
Sonderfall:

1. **Stop-Reihenfolge**: webserver -> tika -> gotenberg -> redis -> db.
2. **rm -f Reihenfolge**: identisch.
3. **Start**: `just app-up paperless` (depends_on regelt Reihenfolge:
   db,redis,gotenberg,tika -> healthy -> webserver).
4. **Healthcheck-Loop**: Defaults 300s/10s, multi-check ueber alle 5
   Container (state=running + Health) plus HTTP-Probe Webserver
   (Code 200 oder 302).
5. **Rollback**: `just app-down paperless`, dann Root-Compose in
   Reverse-Order (db -> redis -> tika -> gotenberg -> webserver),
   anschliessend multi-check 60s.
6. **Pflichtflag**: `--allow-paperless` zusaetzlich zu `--execute
   --yes-i-am-sure`. Ohne `--allow-paperless` Abbruch exit 2.

### Restore (paperless)

Die App nutzt Bind-Mounts auf `data/postgres`, `data/redis`,
`data/paperless`. Im Cutover bleiben Volumes erhalten. Bei DB-
Korruption nach Cutover:

1. App-Compose stoppen: `just app-down paperless`.
2. Restic-Snapshot zurueckspielen oder Backup-Tarball entpacken.
3. `backups/<TS>/paperless-postgres.sql` einspielen.
4. App-Compose wieder starten: `just app-up paperless`.

### convertX, uptime-kuma, dozzle (Phasen D, E, F)

| App | Phase | Sperre |
|---|---|---|
| convertx | D | nicht in EXECUTE_ALLOWED_APPS |
| uptime-kuma | E | nicht in EXECUTE_ALLOWED_APPS |
| dozzle | F | nicht in EXECUTE_ALLOWED_APPS (bewusst zuletzt) |

Dozzle bleibt explizit als letzter Schritt, damit waehrend frueherer
Migrations-Schritte das Container-Log-UI noch aus Root-Compose
erreichbar ist.

## Sonderfall Authentik

Authentik wird **nicht** im selben Wartungsfenster wie eine App migriert.
Grunde:
- Authentik-Stack ist Identity-Provider, Ausfall macht Folge-Logins
  unmoeglich.
- `infra/authentik/compose.yml` ist als separate Phase konzipiert
  (siehe `docs/AUTHENTIK_OPTIONAL.md`).
- `scripts/migrate-app.sh authentik --dry-run` bricht bewusst mit
  exit 2 ab und verweist auf die separate Phase.

Plan fuer die Authentik-Phase (nicht Teil dieses Cutovers):
1. Datenbank-Backup (pg_dump + Redis-Dump) zwingend vorher.
2. Provider-Definitionen in Authentik exportieren (UI).
3. Erst nach erfolgreichem Cutover aller Apps anfassen.

## Werkzeuge

| Befehl | Zweck |
|---|---|
| `just migration-status` | Tabelle pro App mit safe-Marker |
| `just migrate-dry-run <app>` | Pre-Check, Bewertung, Empfehlung |
| `just migrate-plan <app>` | Geplante Cutover-Befehle (kein Eingriff) |
| `just migrate-rollback-plan <app>` | Geplante Rollback-Befehle |
| `just runtime-audit` | Live-Drift gegen Registry + Compose |
| `just registry-audit` | Datei-Konsistenz |

`scripts/migrate-app.sh --execute` ist in Phase 2 implementiert, aber
**nur fuer homepage freigegeben**. Aufruf:

```
just migrate-execute-homepage
# = scripts/migrate-app.sh homepage --execute --yes-i-am-sure
```

Fuer alle anderen Apps bricht `--execute` mit exit 2 ab. Cutover dieser
Apps laeuft weiterhin manuell, mit dem `--print-commands`-Output als
Spickzettel.

### Warum nur homepage in Phase 2

- Homepage hat keinen eigenen DB-State und nutzt nur Bind-Mounts auf
  `config/homepage`. Rollback durch reines Container-Recreate ist sicher.
- Helper-Container fehlen, Healthcheck ist HTTP-basiert und schnell.
- Niedrigster Blast-Radius im Stack -- ideal als erster Cutover.

paperless wird hart blockiert (DB-Helper-Container), authentik bleibt
in einer separaten Phase (Identity-Provider, eigenes Backup-Format).

### Preflight im Execute-Modus

Vor jedem Stop laeuft eine Pflicht-Pruefung:

1. `apps/<app>/compose.yml`, `backup.include`, `healthcheck.sh` vorhanden.
2. `docker compose -f apps/<app>/compose.yml config -q` OK.
3. Root-Compose-Match + Service-Name eindeutig auffindbar.
4. `migration-status` liefert `source=root` (keine Doppel-Migration).
5. `registry-audit` ohne FAIL.
6. `runtime-audit` ohne FAIL.
7. Kein laufender App-Compose-Duplikat-Container.

Bei jedem FAIL: Abbruch ohne Container-Eingriff (exit 2).

### Backup-Pflicht

`--execute` ruft intern `just backup-app <app>` auf. Anschliessend
verifiziert `scripts/backup-age.sh --quiet <app>`, dass ein frisches
`<app>-app.tar.gz`-Artefakt unter `backups/<TS>/` existiert. Fehlt das
Artefakt nach dem Backup-Lauf, wird vor dem Container-Eingriff
abgebrochen (exit 2).

### Healthcheck-Loop

Nach `just app-up <app>` wird `just app-health <app>` gepollt. Standard
ist 60 Sekunden mit 5-Sekunden-Intervall (12 Versuche). Per
Environment-Variable einstellbar:

- `MIGRATE_HEALTH_TIMEOUT_SECONDS` (default 60)
- `MIGRATE_HEALTH_INTERVAL_SECONDS` (default 5)

Beispiel fuer paperless-Phase:

```
MIGRATE_HEALTH_TIMEOUT_SECONDS=300 \
MIGRATE_HEALTH_INTERVAL_SECONDS=10 \
  scripts/migrate-app.sh paperless --execute --allow-paperless --yes-i-am-sure
```

Schlaegt der Check innerhalb des Timeouts nicht durch, greift das
automatische Rollback:

```
just app-down <app>
docker compose -f compose.yml -f <root-match.yml> up -d <service>
```

Rollback loescht keine Volumes. Exit-Code 3 zeigt an, dass auch der
Rollback fehlgeschlagen ist und manuelle Nacharbeit noetig ist.

## Was nicht passieren darf

- Volumes loeschen (`docker compose down -v`, `docker volume rm`).
- Snapshots loeschen (`restic forget --prune` ohne Plan).
- Parallel beide Welten starten (Doppelstart -> Container-Konflikt).
- Authentik im selben Wartungsfenster wie eine App migrieren.
- Echte Secrets committen. `.env` bleibt im `.gitignore`.

## Abschluss-Kriterien

Cutover einer App gilt als erledigt, wenn:
- `just app-health <app>` -> exit 0.
- `just runtime-audit` zeigt `source=app` fuer die App-Container.
- Backup laeuft (`FILEHUB_BACKUP_ONLY_APP=<app> scripts/backup.sh`).
- Externer Zugriff (Gateway, Direkt-Bind) unveraendert funktionsfaehig.

Wenn alle 7 Apps `source=app` zeigen, ist die Root-Compose-Welt fuer den
regulaeren Betrieb stilzulegen. Die Dateien bleiben als Rollback-Reserve
im Repo.
