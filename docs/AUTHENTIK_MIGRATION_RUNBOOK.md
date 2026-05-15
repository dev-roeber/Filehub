# Authentik Migration Runbook

Runbook fuer die separate Authentik-Sonderphase: Cutover des
Authentik-Stacks von `compose.auth.yml` (Phase-1-Bootstrap im Repo-Root)
auf das modulare Infrastruktur-Modul `infra/authentik/compose.yml`.

Erstellt: 2026-05-15. Status: **Plan, nicht ausgefuehrt**.

Dieses Runbook ist eine Schritt-fuer-Schritt-Anleitung. Keine Live-
Eingriffe werden hier durchgefuehrt. Es ergaenzt:
- `docs/MODULAR_RUNTIME_MIGRATION.md` (Phasen A-F, App-Cutover)
- `docs/PHASE_F_NOTES.md` (Authentik-Skizze)
- `docs/AUTHENTIK_OPTIONAL.md` (Funktionsbeschreibung Authentik)

## 1. Ziel und Abgrenzung

**Ziel**: Authentik (Postgres + Redis + Server + Worker) und das Gateway
(`filehub-gateway`) werden aus `compose.auth.yml` (Repo-Root,
Phase-1-Bootstrap) auf das modulare Layout in `infra/authentik/compose.yml`
umgezogen. Endzustand: Authentik laeuft ausschliesslich aus dem Infra-
Modul, gesteuert ueber `just auth-up` / `just auth-down`.

**Abgrenzung zu Phasen A-F**: Authentik ist **keine App** im Sinne von
`apps/<id>/compose.yml` und wird **nicht** ueber `scripts/migrate-app.sh`
behandelt. Gruende:

- Authentik ist Identity-Provider-Infrastruktur. Ausfall macht
  Forward-Auth-Logins fuer alle geschuetzten Apps unmoeglich.
- Eigene Container-Gruppe (DB, Redis, Server, Worker) mit
  pg_dump/Redis-Dump-Pflicht; nicht abbildbar im generischen Cutover-Loop.
- Eigenes Wartungsfenster mit angekuendigter Login-Unverfuegbarkeit
  noetig.
- `scripts/migrate-app.sh authentik` bricht in jedem Modus mit exit 2
  ab. Es existiert weder `--allow-authentik` noch ein Justfile-Target.

Daraus folgt: dieser Cutover laeuft manuell anhand des hier
beschriebenen Ablaufs, **nicht** ueber `migrate-app.sh`.

## 2. Vorbedingungen

Alle Punkte muessen vor dem Cutover erfuellt sein:

| Punkt | Pflicht | Pruefung |
|---|---|---|
| Wartungsfenster angekuendigt | ja | Notification an alle Nutzer; alle Forward-Auth-Apps sind in dieser Zeit nicht erreichbar. |
| `AUTHENTIK_ENABLED=true` in `.env` | ja | `grep ^AUTHENTIK_ENABLED= .env`. `.env.example` bleibt auf `false` (gewollt). |
| Phasen A-F (inkl. Dozzle) abgeschlossen | ja | `just migration-status` -> alle 7 Apps `source=app`. |
| `just registry-audit` ohne FAIL | ja | exit 0. |
| `just runtime-audit` ohne FAIL | ja | erwarteter Authentik-Drift-WARN aus Phase-1-Bootstrap ist okay. |
| Disk Free fuer pg_dump | ja | mind. 1-2 GB frei unter `backups/`, je nach Authentik-DB-Groesse. |
| `.secrets/authentik.env` vorhanden | ja | `ls .secrets/authentik.env`. Inhalt (Secret Key, Postgres-Password) wird nicht veraendert. |

Wenn auch nur einer der Punkte rot ist: **kein Cutover**. Lieber Termin
verschieben.

## 3. Backup-Pflicht

Authentik wird unter keinen Umstaenden ohne frisches pg_dump
angefasst. Auch nicht "kurz mal".

```
FILEHUB_BACKUP_ONLY_APP=authentik scripts/backup.sh
```

Erwartete Artefakte unter `backups/<TS>/`:

| Datei | Quelle | Pflicht |
|---|---|---|
| `authentik-postgres.sql` | `pg_dump` im `filehub-authentik-db` | ja |
| `authentik-redis-dump.rdb` | `dump.rdb` aus `filehub-authentik-redis` | ja |
| `authentik-data.tar.gz` | Tar von `data/authentik/{media,custom-templates,certs}` | ja |

Zusaetzlich **manuell** aus der Authentik-UI exportieren:

- Admin -> System -> Export -> komplette Konfiguration (Applications,
  Providers, Outposts, Flows, Stages, Policies).
- Datei in `backups/<TS>/authentik-config-export.yaml` ablegen.
  (Dieser Export wird **nicht** automatisch erzeugt; ohne manuelles
  Klicken in der UI fehlt er.)

Vor dem Live-Schritt visuell verifizieren, dass Artefakte da und nicht
leer sind:

```
ls -lh backups/<TS>/authentik-*
```

Erwartete Mindestgroessen (Plausibilitaet):
- `authentik-postgres.sql`: >1 KB (leerer Dump waere Hinweis auf
  Connection-Problem).
- `authentik-redis-dump.rdb`: >0 Bytes.
- `authentik-data.tar.gz`: meistens 1-100 MB je nach Media-Inhalt.

Wenn ein Artefakt fehlt oder leer ist: **Cutover sofort abbrechen**.

## 4. Stop-Reihenfolge (compose.auth.yml)

Reihenfolge ist verbindlich. Gateway zuerst, damit keine Auth-Requests
mehr eintreffen. DB ganz am Ende, damit Server/Worker noch sauber
beenden koennen.

| Schritt | Container | Befehl |
|---|---|---|
| 1 | `filehub-gateway` | `docker compose -f compose.yml -f compose.auth.yml stop filehub-gateway` |
| 2 | `filehub-authentik-server` | `docker compose -f compose.yml -f compose.auth.yml stop authentik-server` |
| 3 | `filehub-authentik-worker` | `docker compose -f compose.yml -f compose.auth.yml stop authentik-worker` |
| 4 | `filehub-authentik-redis` | `docker compose -f compose.yml -f compose.auth.yml stop authentik-redis` |
| 5 | `filehub-authentik-db` | `docker compose -f compose.yml -f compose.auth.yml stop authentik-postgres` |

Anschliessend `rm -f` in derselben Reihenfolge:

```
docker compose -f compose.yml -f compose.auth.yml rm -f filehub-gateway
docker compose -f compose.yml -f compose.auth.yml rm -f authentik-server
docker compose -f compose.yml -f compose.auth.yml rm -f authentik-worker
docker compose -f compose.yml -f compose.auth.yml rm -f authentik-redis
docker compose -f compose.yml -f compose.auth.yml rm -f authentik-postgres
```

Wichtig:

- **Kein `down -v`**, kein `docker volume rm`. Die Bind-Mounts auf
  `data/authentik/*` muessen erhalten bleiben - die neue
  `infra/authentik/compose.yml` mountet dieselben Pfade.
- Nach `rm -f` mit `docker ps -a | grep authentik` pruefen, dass keine
  Reste existieren.

## 5. Start aus infra/authentik/compose.yml

Volume-Konsistenz vor dem Start verifizieren:

```
ls -lah data/authentik/postgres
ls -lah data/authentik/redis
ls -lah data/authentik/media
ls -lah data/authentik/custom-templates
ls -lah data/authentik/certs
```

Alle fuenf Verzeichnisse muessen existieren und nicht leer sein
(Postgres-Cluster-Dateien, Redis dump.rdb, etc.). `infra/authentik/compose.yml`
bindet exakt diese Pfade (relativ zur Compose-Datei als `../../data/authentik/*`),
sodass die Daten der alten Welt direkt uebernommen werden.

Start:

```
just auth-up
```

`auth-up` prueft selbst, ob `AUTHENTIK_ENABLED=true` in `.env` steht;
sonst bricht es mit Exit 1 ab. Hinter den Kulissen:

```
docker compose --env-file .env -f infra/authentik/compose.yml up -d
```

Erwartete Start-Reihenfolge (per `depends_on` mit `service_healthy`):

1. `authentik-postgres`
2. `authentik-redis`
3. `authentik-server`
4. `authentik-worker`

**Hinweis Gateway**: `infra/authentik/compose.yml` enthaelt aktuell
**keinen** `filehub-gateway`. Der Gateway-Service ist nur in
`compose.auth.yml` definiert. Siehe Abschnitt 11 (offene Fragen).
Variante fuer den Live-Cutover: Gateway separat ueber
`just gateway-up` aus `compose.auth.yml` starten, bis der Gateway in
ein eigenes Modul (z.B. `infra/gateway/compose.yml`) gezogen ist.

## 6. Healthcheck-Sequenz

In dieser Reihenfolge pruefen:

```
just auth-status
```
Erwartet: Container-States `Up (healthy)` fuer DB, Redis, Server,
Worker. `curl`-Zeile zeigt HTTP-Code `302` (Redirect auf Login).

```
just gateway-bootstrap-check
```
Erwartet: `POST-BOOTSTRAP` (Embedded Outpost antwortet mit Login-
Redirect, **nicht** `404 PRE-BOOTSTRAP`).

```
just gateway-status
```
Erwartet: `gateway-health` 200 oder 204, `gateway-root` 302 oder 200.

Manueller Login-Test:

1. Browser -> `http://127.0.0.1:9000/`.
2. Mit Admin-Credentials einloggen.
3. Admin-Interface oeffnen, Application-Liste muss vollstaendig sein.

Forward-Auth-Test auf einer Test-App (z.B. `filebrowser`):

1. Inkognito-Browser -> Gateway-URL der Test-App.
2. Erwartet: Redirect auf Authentik-Login, nach Login Zugriff auf App.
3. Logout aus Authentik testen.

Wenn ein Schritt failt: Rollback (Abschnitt 7).

## 7. Rollback

Rollback ist immer "neue Welt runter, alte Welt hoch". Volumes
ueberleben den Wechsel, weil beide Compose-Dateien dieselben
Bind-Mounts auf `data/authentik/*` verwenden.

### 7.1 Standard-Rollback (Container-Problem, Daten intakt)

```
just auth-down
docker compose -f compose.yml -f compose.auth.yml up -d \
  authentik-postgres authentik-redis authentik-server authentik-worker filehub-gateway
just auth-status
just gateway-bootstrap-check
```

### 7.2 DB-Korruption (pg_restore noetig)

Wenn Postgres in der neuen Welt nicht mehr sauber hochkommt
oder Daten verloren scheinen:

```
just auth-down
# alte Welt nur DB hoch:
docker compose -f compose.yml -f compose.auth.yml up -d authentik-postgres
# Restore in laufenden Container:
cat backups/<TS>/authentik-postgres.sql | \
  docker exec -i filehub-authentik-db psql -U authentik -d authentik
# Rest hochfahren:
docker compose -f compose.yml -f compose.auth.yml up -d
just auth-status
```

`pg_restore` direkt aus `.sql` ist nicht noetig: der Dump ist ein
Plaintext-SQL (siehe `scripts/backup.sh` -> `pg_dump` ohne `-F c`),
also `psql < dump.sql` reicht.

### 7.3 Redis-Verlust (dump.rdb zurueckkopieren)

```
just auth-down
# Container weg, alte Welt nur Redis hoch:
docker compose -f compose.yml -f compose.auth.yml up -d authentik-redis
docker exec filehub-authentik-redis redis-cli SHUTDOWN NOSAVE || true
# Volume-Dump ueberschreiben:
cp backups/<TS>/authentik-redis-dump.rdb data/authentik/redis/dump.rdb
chmod 600 data/authentik/redis/dump.rdb
# Container neu:
docker compose -f compose.yml -f compose.auth.yml up -d authentik-redis
docker compose -f compose.yml -f compose.auth.yml up -d
```

### 7.4 Wann nicht rollbacken

- Wenn die neue Welt **erfolgreich** Logins verarbeitet und im
  Anschluss neue Authentik-Daten geschrieben wurden, ist ein
  Rollback ein **Datenverlust-Risiko** (neue Logins, neue Token-
  Eintraege gehen verloren). Erst ein neues pg_dump aus der neuen
  Welt ziehen, dann entscheiden.

## 8. Was nicht passieren darf

- Authentik **ohne** `FILEHUB_BACKUP_ONLY_APP=authentik scripts/backup.sh`
  anfassen. Kein pg_dump = kein Cutover.
- Authentik im **gleichen Wartungsfenster** wie ein App-Cutover
  (Phasen A-F) migrieren. Beide Stoerungen ueberlagern sich, Root-Cause
  bei Problemen wird unklar.
- `AUTHENTIK_SECRET_KEY` oder `POSTGRES_PASSWORD` in
  `.secrets/authentik.env` aendern. Der Secret Key entschluesselt
  gespeicherte Provider-Geheimnisse; Aenderung macht alle Provider
  unbrauchbar.
- Volume-Verzeichnisse unter `data/authentik/*` loeschen, verschieben
  oder per `chown -R` umkippen.
- `docker compose down -v` oder `docker volume rm` auf irgendeiner
  Compose-Datei dieses Projekts ausfuehren.
- Beide Welten parallel starten. Beide Compose-Dateien definieren
  dieselben `container_name`-Werte; Docker bricht den zweiten Start
  ab und hinterlaesst halbe Stacks.
- Authentik-Image-Version waehrend des Cutovers anheben. Erst
  Cutover stabilisieren, dann separat Image-Update.

## 9. Verifikation nach Cutover

Cutover gilt als erfolgreich abgeschlossen, wenn alle folgenden
Punkte gruen sind:

| Pruefung | Erwartetes Ergebnis |
|---|---|
| `just auth-status` | DB/Redis/Server/Worker `Up (healthy)`, UI 302 |
| `just gateway-bootstrap-check` | `POST-BOOTSTRAP` |
| `just runtime-audit` | Authentik-Drift-WARN aus Phase 1 **verschwindet** (oder Begruendung schriftlich) |
| Admin-Login Authentik-UI | erfolgreich |
| Forward-Auth Test-App | Redirect -> Login -> App-Zugriff |
| Alle Provider-Anwendungen | erreichbar laut Admin-UI Application-Liste |
| User-Logins (mind. 1 Real-User) | erfolgreich |
| `docker ps` | alle Authentik-Container haben `state=running` aus `infra/authentik/compose.yml` (Label `com.docker.compose.project.config_files` enthaelt `infra/authentik/compose.yml`) |

Falls der Drift-WARN trotz Cutover bestehen bleibt: Audit-Logik in
`scripts/runtime-audit.sh` pruefen (vermutlich erwartet er noch die
alte Container-Source).

## 10. TODO vor naechstem Authentik-Cutover

Punkte, die heute fehlen und vor einer ernsthaften Live-Migration
geschlossen werden sollten:

- [ ] **Provider-Export-Script**: aktuell muss die Konfiguration
      manuell in der UI exportiert werden. Ideal: `scripts/authentik-config-export.sh`
      ueber Authentik-API mit Service-Token; Output nach
      `backups/<TS>/authentik-config-export.yaml`. Solange das fehlt,
      gehoert der manuelle Export zur Backup-Pflicht (Abschnitt 3).
- [ ] **Volume-Pfad-Audit** zwischen `compose.auth.yml` und
      `infra/authentik/compose.yml`. Beide Dateien definieren
      identische Bind-Mount-Targets (`data/authentik/*`), aber mit
      unterschiedlichem relativem Pfad (`./data/...` vs.
      `../../data/...`). Ein automatisches Diff-Skript sollte
      bestaetigen, dass beide auf denselben absoluten Pfad zeigen.
- [ ] **Gateway-Modularisierung**: `filehub-gateway` ist heute nur
      in `compose.auth.yml` definiert, nicht in
      `infra/authentik/compose.yml`. Vor dem finalen Cutover sollte
      entweder (a) der Gateway in `infra/authentik/compose.yml`
      aufgenommen oder (b) ein eigenes Modul `infra/gateway/compose.yml`
      angelegt werden. Aktuell wuerde nach `auth-up` der Gateway
      fehlen, falls man `compose.auth.yml` komplett abschaltet.
- [ ] **Health-Loop-Skript** analog zu `migrate-app.sh`: aktuell
      laufen alle Health-Checks manuell. Wuenschenswert:
      `scripts/migrate-authentik.sh` mit `--dry-run`, `--execute`,
      `--rollback`, Backup-Verifikation, Healthcheck-Loop und
      automatischem Rollback bei Health-Fail.
- [ ] **Runtime-Audit-Anpassung**: nach Cutover muss der
      Drift-WARN `AUTHENTIK_ENABLED=false, aber Authentik-Container
      laufen` weg sein, sobald `AUTHENTIK_ENABLED=true` gesetzt
      und die neue Welt aktiv ist. Pruefen, ob `runtime-audit.sh`
      diese Kombination korrekt erkennt.
- [ ] **Restore-Test**: ein dokumentierter Trockenlauf von
      `authentik-postgres.sql`-Restore in einem Sandbox-Container
      (nicht Live-DB) sollte mindestens einmal durchgespielt und
      unter `docs/restore-test-result-<TS>.md` protokolliert werden.
- [ ] **Image-Pin-Strategie**: heute steht `2024.10` an zwei Stellen
      (`compose.auth.yml`, `infra/authentik/compose.yml`). Single
      Source of Truth waere besser (z.B. `AUTHENTIK_IMAGE_TAG` in
      `.env`).

## 11. Offene Fragen / Diskrepanzen zwischen compose.auth.yml und infra/authentik/compose.yml

Beim Vergleich der beiden Compose-Dateien sind folgende Unterschiede
aufgefallen, die vor dem Live-Cutover geklaert werden muessen:

| Aspekt | compose.auth.yml | infra/authentik/compose.yml | Bewertung |
|---|---|---|---|
| `filehub-gateway`-Service | **enthalten** (Caddy 2.8-alpine, Port 3080 -> 8080) | **fehlt** | offen: Gateway muss separat gehandhabt werden, siehe TODO oben |
| `name:`-Direktive | fehlt (Projektname = Verzeichnisname `filehub`) | gesetzt auf `filehub` | konsistent, da Default ohnehin `filehub` |
| `filehub_net`-Netzwerk | inline definiert ohne `external` | `external: true` | beabsichtigt: Infra-Modul nutzt Netzwerk, das von App-/Root-Compose erzeugt wird. Pruefen, dass `filehub_net` zum Start-Zeitpunkt schon existiert |
| Bind-Mount-Pfade | `./data/authentik/*` | `../../data/authentik/*` | semantisch identisch, da `infra/authentik/compose.yml` zwei Verzeichnisse tief liegt. Trotzdem: automatisierter Diff-Check waere gut (siehe TODO Volume-Pfad-Audit) |
| `env_file`-Pfad | `.secrets/authentik.env` | `../../.secrets/authentik.env` | semantisch identisch, gleiche Datei |
| `caddy-gateway`-Volumes | `./data/caddy-gateway/{data,config}` | nicht referenziert | nur relevant fuer Gateway, der im Infra-Modul fehlt |
| `AUTHENTIK_PORT`-Default | `9000` | `9000` | identisch |
| `FILEHUB_GATEWAY_PORT`-Default | `3080` | nicht definiert (Gateway fehlt) | siehe oben |
| Networks-Block-Layout | `authentik_net` + `filehub_net` (beide inline) | identische Namen, `filehub_net` als `external` | Compose-kompatibel, nur Lebenszyklus unterschiedlich |
| Postgres-/Redis-/Server-/Worker-Service | identisch (Image, Healthcheck, env_file, depends_on) | identisch | OK |

**Konkrete Handlungspunkte** aus den Diskrepanzen:

1. Vor `just auth-up` muss `filehub_net` existieren (wird normalerweise
   durch `apps/<id>/compose.yml`-Stack oder durch
   `compose.yml`-Start erzeugt). Pruefung:
   `docker network ls | grep filehub_net`.
2. Solange Gateway nicht ins Infra-Modul gezogen ist, ist das
   Cutover-Ergebnis nicht "Authentik komplett aus
   `infra/authentik/compose.yml`", sondern "Authentik-Stack aus
   Infra-Modul + Gateway weiter aus `compose.auth.yml`".
   Das ist ein Zwischenzustand, der dokumentiert werden muss, sobald
   live geschaltet.
3. Image-Tag `ghcr.io/goauthentik/server:2024.10` ist in beiden
   Dateien hardcodiert. Solange synchron, kein Problem; bei naechstem
   Image-Update beide Stellen oder Variable einfuehren.

Erst wenn diese Punkte geklaert sind, kann ein konkreter Live-Termin
fuer den Authentik-Cutover gesetzt werden. Bis dahin bleibt der
Drift-WARN aus Phase-1-Bootstrap akzeptierter Normalzustand.
