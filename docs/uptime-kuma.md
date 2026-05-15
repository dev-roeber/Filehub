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

## Automatische Monitor-Anlage (empfohlen)

Nach dem initialen Admin-Konto koennen die Filehub-Monitore automatisch angelegt werden.

Voraussetzung: `.secrets/uptime-kuma.env` (git-ignored) mit:

```env
UPTIME_KUMA_URL=http://127.0.0.1:3002
UPTIME_KUMA_USER=<dein Admin-Username>
UPTIME_KUMA_PASSWORD=<dein Admin-Passwort>
```

Datei-Modus `600`, Verzeichnis `700`. Die Datei wird durch `.gitignore` ausgeschlossen und darf niemals committed werden.

Start:

```bash
./scripts/setup-uptime-kuma-monitors.sh
```

Eigenschaften:

- Idempotent: bestehende Monitore werden anhand des Namens gefunden und aktualisiert, nicht dupliziert.
- Setzt fuer jeden Monitor: `interval=60`, `maxretries=2`, `retryInterval=60`, `timeout=20`, HTTP-Methode `GET`, akzeptierte Statuscodes `200-299`, Tag `filehub`.
- Legt einen Tag `filehub` an, falls noch nicht vorhanden.
- Loggt keine Passwoerter.

Wenn `.secrets/uptime-kuma.env` fehlt, fragt das Skript Username und Passwort interaktiv ab (`read -s` fuer das Passwort).

Eingesetzt werden:

| Name | Typ | Ziel |
|---|---|---|
| Filehub Paperless | HTTP | `http://paperless-webserver:8000` |
| Filehub ConvertX | HTTP | `http://convertx:3000` |
| Filehub Homepage | HTTP | `http://homepage:3000` |
| Filehub Dozzle | HTTP | `http://dozzle:8080` |
| Filehub Uptime Kuma | HTTP | `http://uptime-kuma:3001` |
| Filehub Gotenberg | HTTP | `http://paperless-gotenberg:3000/health` |
| Filehub Tika | HTTP | `http://paperless-tika:9998/` |
| Filehub PostgreSQL | Port | `paperless-db:5432` |
| Filehub Redis | Port | `paperless-redis:6379` |

Status nach Lauf in der Uptime-Kuma-UI pruefen. Erster Heartbeat sollte innerhalb 1-2 Minuten gruen werden.

Wenn das Script mit `Incorrect username or password.` abbricht, ist meist der Username nicht `admin`, sondern der waehrend des initialen Setups gewaehlte Name. Korrektur in `.secrets/uptime-kuma.env`, dann erneut starten.

### Username Sicher Aus DB Pruefen

Wenn der Username vergessen wurde, kann er direkt aus `data/uptime-kuma/kuma.db` gelesen werden. Es werden nur `id` und `username` ausgegeben, keine Passwort-Hashes:

```bash
sqlite3 data/uptime-kuma/kuma.db "SELECT id, username FROM user;"
```

Achtung: Wenn der Container laeuft und im WAL-Modus schreibt, kann das Schreiben aus dem Host gegen die DB blockiert sein. Fuer reines Lesen ist das ok.

Beim initialen Setup kann es vorkommen, dass Uptime Kuma einen trailing space im Username speichert. In dem Fall hilft:

```bash
docker stop filehub-uptime-kuma
sqlite3 data/uptime-kuma/kuma.db "UPDATE user SET username = TRIM(username) WHERE id = 1;"
docker start filehub-uptime-kuma
```

### Passwort Vergessen

Reset ueber das offizielle Tool ist interaktiv und haengt im offline-Container am Socket-Disconnect. Stattdessen kann der Hash direkt geschrieben werden, sobald der Container gestoppt ist:

```bash
docker stop filehub-uptime-kuma
PW="$(openssl rand -base64 24 | tr -d '/+=' | cut -c1-32)"
# PW lokal in einen Passwortmanager kopieren, NICHT in shell-history oder logs schreiben.
.venv-uptime-kuma/bin/pip install --quiet bcrypt
PASSWORD="$PW" .venv-uptime-kuma/bin/python -c "
import os, sqlite3, bcrypt
h = bcrypt.hashpw(os.environ['PASSWORD'].encode(), bcrypt.gensalt(rounds=10)).decode()
con = sqlite3.connect('data/uptime-kuma/kuma.db')
con.execute('UPDATE user SET password = ? WHERE id = 1', (h,))
con.commit()"
docker start filehub-uptime-kuma
```

Danach `.secrets/uptime-kuma.env` mit dem neuen Passwort aktualisieren und das Setup-Skript erneut starten. Vorher unbedingt ein Backup der DB anlegen, z. B. nach `.secrets/kuma.db.bak.<ts>`.

## Lokale Statuspage

Eine lokale, nicht-publizierte Statuspage fasst alle Filehub-Monitore zusammen.
Sie ist nur ueber `http://127.0.0.1:3002` erreichbar und nicht oeffentlich, weil
Uptime Kuma localhost-gebunden laeuft.

Eigenschaften:

- Slug:  `filehub-local`
- Titel: `Filehub Local Status`
- Monitor-Gruppe: `Filehub` mit allen 11 Filehub-Monitoren
- Aufruf: `http://127.0.0.1:3002/status/filehub-local`

### Automatische Anlage

```bash
./scripts/setup-uptime-kuma-statuspage.sh
```

Das Skript ist idempotent: existiert die Page bereits, wird sie aktualisiert.
Es bindet automatisch alle Monitore mit Praefix `Filehub ` ein.

Hinweis zum `published`-Flag: Die `uptime-kuma-api`-Library akzeptiert
`published=False` beim Speichern, Uptime Kuma persistiert die Page jedoch
trotzdem als `published=True`. Da der gesamte Filehub-Stack ausschliesslich an
`127.0.0.1` gebunden ist und keine oeffentliche Erreichbarkeit existiert,
bleibt die Page faktisch lokal. Wer das Flag erzwingen will, kann es in der
UI nach dem Lauf manuell auf "Unpublished" setzen.

### Manuell anlegen (Klick-Anleitung)

1. `Settings -> Status Pages -> New Status Page`.
2. Slug: `filehub-local`, Title: `Filehub Local Status`.
3. `Add Group` -> Name `Filehub`.
4. Alle 11 Filehub-Monitore in diese Gruppe ziehen
   (`Filehub Paperless`, `Filehub ConvertX`, `Filehub Homepage`, `Filehub Dozzle`,
   `Filehub Uptime Kuma`, `Filehub Gotenberg`, `Filehub Tika`, `Filehub Filebrowser`,
   `Filehub Stirling PDF`, `Filehub PostgreSQL`, `Filehub Redis`).
5. `Save`. Nicht publizieren (`Published` aus, soweit moeglich).
6. Aufruf: `http://127.0.0.1:3002/status/filehub-local`.

## Daten Sichern

Die Uptime-Kuma-Daten liegen unter `data/uptime-kuma`. `scripts/backup.sh` sichert dieses Verzeichnis als Teil von `observability-data.tar.gz`. Damit sind Monitor-Konfigurationen und Heartbeat-Historie im taeglichen Backup enthalten.

## Manueller Fallback: Klick-Anleitung

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

## Notifications via ntfy

Stand: 2026-05-15. ntfy ist als Push-Kanal fuer Filehub aktiv (siehe
[notifications.md](notifications.md)). Uptime Kuma wird mit ntfy
bevorzugt **automatisch** ueber die `uptime-kuma-api` Python-Library
(`>=1.2.1`) verkabelt. Die UI-Anleitung weiter unten bleibt als Fallback
gueltig.

### Automatische Einrichtung (empfohlen)

Voraussetzungen:

- `.secrets/uptime-kuma.env` mit `UPTIME_KUMA_URL`, `UPTIME_KUMA_USER`,
  `UPTIME_KUMA_PASSWORD` (siehe Abschnitt oben).
- `.secrets/ntfy.env` mit `NTFY_SERVER_URL` und `NTFY_TOPIC`.
  Optional `NTFY_PRIORITY_DEFAULT` (`min|low|default|high|max`).

Start:

```bash
./scripts/setup-uptime-kuma-notifications.sh
```

Optional einen Test-Push ausloesen:

```bash
RUN_TEST=1 ./scripts/setup-uptime-kuma-notifications.sh
```

Eigenschaften:

- Idempotent: existiert eine Notification mit Name `Filehub ntfy`,
  wird sie aktualisiert (kein Duplikat).
- `isDefault=True` und `applyExisting=True`: die Notification wird an
  alle bestehenden und neuen Monitore gehaengt.
- Zusaetzlich wird jeder Monitor mit Praefix `Filehub ` explizit ueber
  `edit_monitor(notificationIDList=...)` an die Notification gebunden,
  ohne IDs zu duplizieren.
- Loggt keine Secrets oder Topic-Werte.
- Bricht sicher ab, wenn Pflichtvariablen fehlen oder die API einen
  Fehler liefert. Keine direkten DB-Zugriffe.

Library-Version 1.2.1 erwartet fuer `NotificationType.NTFY` die Felder
`ntfyserverurl` (string), `ntfytopic` (string) und `ntfyPriority`
(int 1..5). Bei aelteren oder neueren Library-Versionen koennen die
Feldnamen abweichen; in dem Fall in
`.venv-uptime-kuma/lib/python*/site-packages/uptime_kuma_api/notification_providers.py`
unter `NotificationType.NTFY` nachschlagen und das Script anpassen.

### Manuelle Einrichtung (Fallback)

1. Uptime Kuma in der UI oeffnen: `http://127.0.0.1:3002`.
2. Oben rechts auf das Profil-Symbol -> `Settings`.
3. Linke Sidebar -> `Notifications`.
4. `Setup Notification` bzw. `Add` klicken.
5. Notification Type: `ntfy`.
6. Felder ausfuellen:
   - **Friendly Name**: `Filehub ntfy`.
   - **ntfy Server URL**: Wert aus `.secrets/ntfy.env` (`NTFY_SERVER`).
   - **ntfy Topic**: Wert aus `.secrets/ntfy.env` (`NTFY_TOPIC`).
   - Priority und Tags optional, default reicht.
   - Falls der Broker Authentifizierung erzwingt, Token aus
     `.secrets/ntfy.env` (`NTFY_TOKEN`) eintragen.
7. **Default enabled** anhaken, damit die Notification automatisch
   fuer alle Filehub-Monitore aktiv ist und auch neue Monitore sie
   erben.
8. `Test` klicken. Auf dem abonnierten ntfy-Client muss eine
   Test-Nachricht ankommen. Wenn nicht: Server-URL, Topic und Netzwerk
   pruefen.
9. `Save`.

### Verifikation

- Im Monitor-Detail (`Edit` eines bestehenden Monitors) erscheint
  `Filehub ntfy` unter `Notifications` und ist angehakt.
- Einen Monitor testweise auf eine kaputte URL setzen und nach Ablauf
  der Retry-Schwelle die Push-Nachricht pruefen. Danach Monitor wieder
  korrigieren.

### Sicherheit

- Werte aus `.secrets/ntfy.env` werden nur in der Uptime-Kuma-UI
  eingetragen, nicht in Issues, Commits oder Screenshots.
- Bei Topic-Rotation muss die Notification in der UI aktualisiert
  werden, sonst gehen Alarme an das alte Topic.
- Uptime Kuma selbst bleibt localhost-only. Es gibt kein neues
  oeffentliches Binding.
