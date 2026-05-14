# Uptime Kuma

Uptime Kuma laeuft als Teil des Observability-Stacks nur lokal:

```text
http://127.0.0.1:3002
```

Der Container ist im Docker-Netzwerk `filehub_net` und kann die anderen Filehub-Dienste ueber Docker-DNS erreichen. Fuer Uptime Kuma werden keine oeffentlichen Bindings erzeugt.

## Initiales Setup

1. Falls du remote arbeitest, SSH-Tunnel oeffnen:

   ```bash
   ssh -L 3002:127.0.0.1:3002 sebastian@SERVER_IP
   ```

2. Im Browser oeffnen:

   ```text
   http://127.0.0.1:3002
   ```

3. Sprache und Zeitzone waehlen.
4. Admin-Konto anlegen: Username + starkes Passwort.
5. Passwort nur in einem Passwortmanager speichern. Keine Admin-Zugangsdaten in `.env`, Doku-Dateien oder Git ablegen.
6. Nach Login: Settings -> General -> Timezone auf `Europe/Berlin`, Theme nach Wunsch.
7. Settings -> Security -> Disable Auth bleibt `off`.

## Monitor Anlegen: Klick-Anleitung

Fuer jeden Monitor in der Tabelle weiter unten:

1. Dashboard -> `Add New Monitor`.
2. Monitor Type:
   - `HTTP(s)` fuer URLs (siehe HTTP-Liste).
   - `TCP Port` fuer DB/Cache (siehe TCP-Liste).
3. Friendly Name: aus Tabelle uebernehmen, z. B. `Filehub Paperless`.
4. URL bzw. Hostname/Port: aus Tabelle uebernehmen.
5. Heartbeat Interval: `60` Sekunden.
6. Retries: `2`.
7. Heartbeat Retry Interval: `30` Sekunden.
8. Request Timeout: `10` Sekunden.
9. Accepted Status Codes (HTTP): `200-299` und `300-399`.
10. Tags: ein einheitlicher Tag pro Stack, z. B. `filehub`.
11. Notifications: vorerst leer lassen, bis alle Monitore stabil gruen sind.
12. `Save`.

Pruefe nach jedem Anlegen, dass der erste Heartbeat innerhalb von 1-2 Minuten gruen wird. Wenn nicht, Logs in Dozzle (`http://127.0.0.1:9999`) pruefen und ggf. die Fallback-URL aus dem Abschnitt unten verwenden.

## Gruppen

Optional in Uptime Kuma:

- `Filehub Core`: Paperless, ConvertX, Homepage.
- `Filehub Internal`: Gotenberg, Tika.
- `Filehub Observability`: Dozzle, Uptime Kuma Self.
- `Filehub Data`: PostgreSQL, Redis.

Gruppe via `Add New Monitor -> Type: Group` und Monitore in der Sidebar per Drag and Drop einordnen.

## Monitore

Eine automatische Monitor-Anlage wird hier bewusst nicht verwendet, weil dafuer Admin-Credentials, eine authentifizierte Session oder direkte Datenbankzugriffe noetig waeren. Das waere fuer dieses Setup unnoetig riskant.

Lege diese HTTP-Monitore manuell in der Uptime-Kuma-Oberflaeche an. Bevorzugt werden interne Docker-DNS-Namen, weil Uptime Kuma im selben Docker-Netzwerk laeuft.

| Name | Typ | URL | Erwartung |
|---|---|---|---|
| Filehub Paperless | HTTP(s) | `http://paperless-webserver:8000` | HTTP 200-399 |
| Filehub ConvertX | HTTP(s) | `http://convertx:3000` | HTTP 200-399 |
| Filehub Homepage | HTTP(s) | `http://homepage:3000` | HTTP 200-399 |
| Filehub Dozzle | HTTP(s) | `http://dozzle:8080` | HTTP 200-399 |
| Filehub Uptime Kuma | HTTP(s) | `http://uptime-kuma:3001` | HTTP 200-399 |
| Filehub Gotenberg | HTTP(s) | `http://paperless-gotenberg:3000/health` | HTTP 200-399 |
| Filehub Tika | HTTP(s) | `http://paperless-tika:9998/` | HTTP 200-399 |

Hinweis: Innerhalb des Uptime-Kuma-Containers nutzt Uptime Kuma Port `3001`. Der Host-Port `127.0.0.1:3002` gilt nur ausserhalb des Containers auf dem Docker-Host.

Optionale TCP-Monitore fuer interne Abhaengigkeiten:

| Name | Typ | Host | Port |
|---|---|---:|
| Filehub PostgreSQL | Port | `paperless-db` | `5432` |
| Filehub Redis | Port | `paperless-redis` | `6379` |

Empfohlene Einstellungen:

- Intervall: `60s`
- Retries: `2`
- Retry-Intervall: `30s`
- Timeout: `10s`
- Benachrichtigungen erst aktivieren, wenn alle Monitore stabil gruen sind

## Fallback-URLs

Falls Docker-DNS in einem Monitor nicht funktioniert, nutze lokale Host-URLs:

| Name | Fallback-URL |
|---|---|
| Filehub Paperless | `http://127.0.0.1:8000` |
| Filehub ConvertX | `http://127.0.0.1:3000` |
| Filehub Homepage | `http://127.0.0.1:3001` |
| Filehub Dozzle | `http://127.0.0.1:9999` |
| Filehub Uptime Kuma | `http://127.0.0.1:3002` |

## Checks

```bash
docker compose -f compose.yml -f compose.paperless.yml -f compose.convertx.yml -f compose.observability.yml ps uptime-kuma
curl -I http://127.0.0.1:3002
just health
```
