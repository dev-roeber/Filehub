# Filehub Gateway (Infra)

Eigenstaendiges Infra-Modul fuer den Caddy-Reverse-Proxy. Ersetzt
mittelfristig den `filehub-gateway`-Service aus `compose.auth.yml`.

## Status

- **Definiert**: infra/gateway/compose.yml
- **Aktiv aus**: compose.auth.yml (Phase-1-Bootstrap)
- **Cutover**: noch nicht ausgefuehrt, siehe
  `docs/GATEWAY_MIGRATION_RUNBOOK.md`.

## Architektur-Entscheidung

Authentik (`infra/authentik/`) und Gateway (`infra/gateway/`) bleiben
**modular getrennt**:

- Authentik ist Identity-Provider, hat eigene DB/Redis/Helper-Container.
- Gateway ist Reverse-Proxy mit eigenem Caddyfile und Daten-/Config-
  Volumes.
- Beide koennen zusammenarbeiten, aber das Gateway-Modul setzt **keine**
  harte `depends_on`-Beziehung auf Authentik. Der bisherige Eintrag
  `depends_on.authentik-server` aus `compose.auth.yml` ist hier
  entfernt, weil Cross-Project-Health-Conditions in Docker Compose nicht
  funktionieren.

Wenn Authentik benoetigt wird (Forward-Auth-Routen im Caddyfile), muss
`just auth-up` vor `just gateway-up` aus diesem Modul laufen.

## Inhalt

| Datei | Zweck |
|---|---|
| `compose.yml` | Caddy-Container, Bind-Mounts, filehub_net (external) |
| `.env.example` | Platzhalter: `FILEHUB_GATEWAY_PORT`, `TZ` |
| `README.md` | dieses Dokument |

Keine `backup.include`: das Gateway hat keine eigenen Daten, die
gesichert werden muessten. Die Caddyfile liegt unter
`config/caddy/filehub-gateway.Caddyfile` (Teil des `filehub-config`-
Backups). `data/caddy-gateway/{data,config}` sind Caddy-interne
Zertifikats- und Settings-Caches; werden ueber Restic-Globalbackup
mitgenommen.

## Volume-Pfade

Bind-Mounts (semantisch identisch zu `compose.auth.yml`):

| Mount | Quelle (root) | Quelle (infra) |
|---|---|---|
| `:/etc/caddy/Caddyfile:ro` | `./config/caddy/filehub-gateway.Caddyfile` | `../../config/caddy/filehub-gateway.Caddyfile` |
| `:/data` | `./data/caddy-gateway/data` | `../../data/caddy-gateway/data` |
| `:/config` | `./data/caddy-gateway/config` | `../../data/caddy-gateway/config` |

Beide Pfade aufloesen zu denselben absoluten Pfaden, weil das
Infra-Compose zwei Ebenen unter dem Repo-Root liegt.

## Netzwerk

Gateway haengt am externen `filehub_net`. Voraussetzung: das Netzwerk
existiert. Pre-Check vor dem Start:

```
docker network ls | grep filehub_net
```

Falls nicht vorhanden:
```
docker network create filehub_net
```

## Start / Stop (nach Cutover)

```
docker compose --env-file ../../.env -f compose.yml up -d
docker compose --env-file ../../.env -f compose.yml stop
docker compose --env-file ../../.env -f compose.yml logs -f
```

Ein dediziertes Justfile-Target fuer das Infra-Modul wird im Cutover-
Commit ergaenzt; aktuell laufen die bestehenden Targets `just
gateway-up/down/restart/logs/reload` weiter gegen `compose.auth.yml`.

## Healthcheck

`wget -qO- http://localhost:8080/_health` muss "ok" liefern. Der
Caddyfile-Block `handle /_health { respond "ok" 200 }` ist dafuer
zustaendig und braucht keine Authentik.

## Was dieses Modul NICHT macht

- Es startet kein Authentik.
- Es definiert keine Authentik-Routen ueber das Caddyfile hinaus.
- Es loescht keine Volumes.
- Es ist kein Drop-in-Replacement fuer compose.auth.yml insgesamt -
  nur fuer den Gateway-Service.
