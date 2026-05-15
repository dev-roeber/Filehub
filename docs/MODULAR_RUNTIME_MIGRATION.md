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

Aufsteigender Risiko-Score: zuerst zustandslose Apps, dann komplexe.

1. **homepage** -- rein lesendes Dashboard, schnell rollbackbar.
2. **dozzle** -- nur Docker-Socket-Reader, kein eigener State.
3. **stirling-pdf** -- temporaere Daten, kein DB.
4. **convertx** -- SQLite-State, App-eigene Volumes.
5. **filebrowser** -- bind-mount auf Datenverzeichnis, State in App-DB.
6. **uptime-kuma** -- eigener State, Monitor-Konfiguration.
7. **paperless** -- Sonderfall (Postgres, Redis, Tika, Gotenberg).
8. **authentik** -- separate Phase, nicht im selben Wartungsfenster.

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

`scripts/migrate-app.sh --execute` ist in Phase 1 bewusst nicht
implementiert. Cutover laeuft manuell, mit dem ausgegebenen Plan als
Spickzettel.

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
