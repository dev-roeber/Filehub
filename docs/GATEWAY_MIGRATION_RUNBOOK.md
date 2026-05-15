# Gateway Migration Runbook

Runbook fuer den Cutover des `filehub-gateway`-Service von
`compose.auth.yml` auf das eigenstaendige Infra-Modul
`infra/gateway/compose.yml`. **Kein Authentik-Eingriff**.

Letztes Update: 2026-05-15. Cutover noch nicht ausgefuehrt.

## Warum Gateway nicht in Authentik liegt

- Authentik ist Identity-Provider mit DB, Redis, Server-, Worker-Container.
- Gateway ist Reverse-Proxy mit eigenem Caddyfile, eigenem Daten-/
  Config-Volume.
- Beide arbeiten zusammen, aber sind funktional getrennt.
- Wenn Gateway in `infra/authentik/compose.yml` waere, wuerde jeder
  Authentik-Wartungsschritt auch das Gateway treffen. Genau das soll
  vermieden werden.

Folge: Authentik-Cutover (separate Phase) und Gateway-Cutover (dieser
Runbook) laufen in **getrennten** Wartungsfenstern.

## Aktueller Zustand

```
just gateway-migration-status
```

Erwartete Ausgabe (Stand 2026-05-15):
```
CONTAINER     filehub-gateway
RUN           yes (state=running)
HEALTH        healthy
SOURCE        root
PORTS         127.0.0.1:3080->8080/tcp
CONFIG_FILES  ... compose.auth.yml
SAFE          yes
```

`filehub-gateway` laeuft also aus dem Phase-1-Bootstrap
(`compose.auth.yml`). Volumes (`./data/caddy-gateway/{data,config}`)
und Caddyfile (`./config/caddy/filehub-gateway.Caddyfile`) sind bind-
mounts auf identische Pfade in `compose.auth.yml` und
`infra/gateway/compose.yml`.

## Zielzustand

`filehub-gateway` laeuft ausschliesslich aus
`infra/gateway/compose.yml`. `compose.auth.yml` behaelt den Gateway-
Block als Rollback-Reserve, wird aber nicht mehr aktiv gestartet.

`just runtime-audit` meldet danach:
```
OK gateway filehub-gateway laeuft aus infra/gateway/ (Cutover erledigt, state=running)
```

## Preflight (vor Cutover, alle muessen gruen sein)

```
just registry-audit                                                    # 0 FAIL
just runtime-audit                                                     # 0 FAIL, INFO gateway=root erwartet
just gateway-status                                                    # gateway-health 200
just gateway-migration-status                                          # SAFE=yes, SOURCE=root
just gateway-bootstrap-check                                           # POST-BOOTSTRAP
docker compose --env-file .env -f infra/gateway/compose.yml config -q  # OK
docker network ls | grep filehub_net                                   # vorhanden (external)
curl -fsS http://127.0.0.1:3080/_health                                # "ok"
just secrets-audit                                                     # alle Pruefungen bestanden
```

Falls ein FAIL auftaucht: **kein Cutover**.

## Cutover-Schritte (NICHT ausfuehren ohne Wartungsfenster)

```
# 1) Config-Sicherung (Caddyfile + caddy-data Volumes liegen im
#    Restic-Globalbackup; zusaetzlich kurzer Diff sichern)
cp config/caddy/filehub-gateway.Caddyfile config/caddy/filehub-gateway.Caddyfile.bak.$(date +%Y%m%d-%H%M%S)

# 2) Root-Gateway aus compose.auth.yml stoppen
docker compose --env-file .env -f compose.yml -f compose.auth.yml stop filehub-gateway
docker compose --env-file .env -f compose.yml -f compose.auth.yml rm -f filehub-gateway

# 3) Infra-Gateway hochfahren
docker compose --env-file .env -f infra/gateway/compose.yml up -d

# 4) Caddy-Config-Validate (im Container)
docker exec filehub-gateway caddy validate --config /etc/caddy/Caddyfile

# 5) HTTP-Probe
curl -fsS http://127.0.0.1:3080/_health   # "ok"
curl -fsS -o /dev/null -w '%{http_code}\n' http://127.0.0.1:3080/   # 200 oder 302 (Authentik-Redirect)

# 6) Authentik-/Gateway-Bootstrap-Check
just gateway-bootstrap-check               # POST-BOOTSTRAP

# 7) Drift-Audit
just runtime-audit
# Erwartet: OK gateway filehub-gateway laeuft aus infra/gateway/
```

## Rollback

Wenn ein Schritt 3-6 fehlschlaegt:

```
# 1) Infra-Gateway stoppen
docker compose --env-file .env -f infra/gateway/compose.yml stop
docker compose --env-file .env -f infra/gateway/compose.yml rm -f

# 2) Root-Gateway aus compose.auth.yml wieder starten
docker compose --env-file .env -f compose.yml -f compose.auth.yml up -d filehub-gateway

# 3) HTTP-Probe
curl -fsS http://127.0.0.1:3080/_health

# 4) Gateway-Bootstrap-Check
just gateway-bootstrap-check

# 5) Drift-Audit
just runtime-audit
# Erwartet: INFO gateway filehub-gateway laeuft aus compose.auth.yml (Rollback)
```

Volumes bleiben in beiden Richtungen erhalten - `data/caddy-gateway/`
ist bind-mount, Docker fasst die Daten nicht an.

## Was nicht passieren darf

- Cutover ohne Authentik-Verfuegbarkeit: Forward-Auth bricht und alle
  geschuetzten Routen liefern 502. Daher Authentik vor Gateway-Cutover
  via `just auth-status` verifizieren.
- Parallelstart von `compose.auth.yml`-Gateway und
  `infra/gateway/compose.yml`-Gateway: Docker blockt durch denselben
  `container_name`, der Fehlversuch ist trotzdem stoerend.
- Loeschen von `data/caddy-gateway/{data,config}`: die `data/`-Volumes
  enthalten Caddy-eigene Zertifikate und Settings. Nicht anfassen.
- Veraendern des `Caddyfile`-Inhalts im selben Schritt wie der Cutover.
  Erst Cutover, dann separate Caddyfile-Aenderung.

## Diskrepanzen zwischen compose.auth.yml und infra/gateway/compose.yml

| Punkt | compose.auth.yml | infra/gateway/compose.yml | Aufloesung |
|---|---|---|---|
| `depends_on` auf authentik-server | ja, `condition: service_healthy` | bewusst entfernt | siehe README |
| Bind-Mount-Praefix | `./config/...` | `../../config/...` | semantisch identisch (Compose-Datei eine Ebene tiefer) |
| `name: filehub` | nicht gesetzt | gesetzt (Default-Projekt) | konsistent, kein Verhaltensunterschied |
| `filehub_net` | inline + namen | `external: true` | beide referenzieren dasselbe Docker-Netz |
| Image-Tag `caddy:2.8-alpine` | hardcoded | hardcoded | Folgeschritt: ueber ENV-Variable parametrisieren |

Volume-Pfad-Diff-Check kann manuell oder ueber ein Helper-Script
(noch nicht vorhanden, separater Folgeschritt) verifiziert werden:

```
realpath ./config/caddy/filehub-gateway.Caddyfile
realpath infra/gateway/../../config/caddy/filehub-gateway.Caddyfile
# beide muessen dieselben absoluten Pfade liefern
```

## Naechster Schritt nach erfolgreichem Cutover

- `compose.auth.yml` bleibt vorerst unveraendert (Rollback-Reserve).
- Authentik-Sonderphase wird **NACH** dem Gateway-Cutover freigegeben.
  Siehe `docs/AUTHENTIK_MIGRATION_RUNBOOK.md`.
- Caddyfile-Pflege bleibt unter `config/caddy/`.

## Verweise

- `infra/gateway/README.md` - Aufbau des Infra-Moduls.
- `docs/AUTHENTIK_MIGRATION_RUNBOOK.md` - kommt nach diesem Cutover.
- `docs/MODULAR_RUNTIME_MIGRATION.md` - Gesamt-Migrationsplan.
- `scripts/gateway-migration-status.sh` - Status-Tool.
