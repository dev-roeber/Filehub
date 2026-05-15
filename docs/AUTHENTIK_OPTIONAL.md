# Authentik als optionales Modul

Authentik ist in Filehub ein optionales Infrastrukturmodul, keine Pflicht-
Komponente. Die Plattform laeuft ohne Authentik vollstaendig; alle Apps sind
standalone betreibbar.

## Default: deaktiviert

In der zentralen Konfiguration ist Authentik standardmaessig aus:

```
AUTHENTIK_ENABLED=false
```

Solange dieser Wert nicht aktiv auf `true` gesetzt und das Modul gestartet
wird, gibt es keinen Authentik-Container, keinen Authentik-Healthcheck und
keine Authentik-Forward-Auth in der Gateway-Konfiguration. Es findet kein
Auto-Start statt -- weder beim `just up` noch beim Reboot.

## Aktivierung

```
just auth-up
```

Startet die Authentik-Stack (Server, Worker, PostgreSQL, Redis) gemaess
`infra/authentik`. `AUTHENTIK_ENABLED=true` wird im lokalen State gesetzt.

## Deaktivierung

```
just auth-down
```

Stoppt den Authentik-Stack. Die zugehoerigen Volumes bleiben erhalten, damit
eine spaetere Reaktivierung ohne Datenverlust moeglich ist.

## Status

```
just auth-status
```

Zeigt, ob Authentik laeuft, gesund ist und welche Forward-Auth-Routen aktuell
aktiv sind.

## Caddy-Snippets pro App

In jedem App-Verzeichnis liegen zwei Caddy-Snippets, beide initial inaktiv:

- `caddy.disabled` -- direkter Reverse-Proxy ohne SSO.
- `caddy.authentik.disabled` -- Reverse-Proxy mit Authentik-Forward-Auth.

Aktivierung erfolgt durch bewusstes Umbenennen zu `caddy` (z. B.
`mv caddy.authentik.disabled caddy`). Erst dadurch nimmt das Gateway das
Snippet in die generierte Caddy-Konfiguration auf. Authentik-Schutz fuer eine
App ist also eine bewusste Entscheidung pro App, nicht ein globaler Schalter.

## Konsequenz fuer den Betrieb

- Apps funktionieren ohne Authentik. Direktzugriff ueber `127.0.0.1:<port>`
  oder ueber das Gateway ohne SSO.
- Authentik schuetzt nur Apps, deren `caddy.authentik`-Snippet aktiv ist
  und nur, wenn `AUTHENTIK_ENABLED=true` und der Stack laeuft.
- Backup von Authentik passiert nur, wenn das Modul aktiv ist (siehe
  `docs/BACKUP.md`).

## Verweise

- `docs/sso-gateway.md` -- detaillierte Beschreibung der SSO-Integration
  und der Authentik-Forward-Auth.
- `docs/ARCHITECTURE.md` -- Einordnung von Authentik als Infrastruktur.
- `docs/SECURITY.md` -- Authentik als zusaetzliche Schutzschicht.
