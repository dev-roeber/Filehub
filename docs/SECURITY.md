# Security

Filehub ist ein Single-User-Setup (sebastian). Die folgenden Konventionen
gelten plattformweit; pro App ergaenzen die jeweiligen READMEs ggf. weitere
Punkte.

## Zentrale Admin-Defaults

Damit App-Provisionierung und Audit funktionieren, gibt es zentrale Admin-
Defaults:

- `FILEHUB_ADMIN_USER=admin`
- `FILEHUB_ADMIN_PASSWORD=<set-local-secret>`

Diese Werte werden ausschliesslich in `.env` oder Dateien unter `.secrets/`
gehalten und sind im `.gitignore` ausgenommen. Sie tauchen niemals im Repo,
in Commits oder in Logs auf. Beispieldateien wie `.env.example` verwenden den
Platzhalter `<set-local-secret>`.

## Risiko: gemeinsames Passwort

Die zentrale Default-Anmeldung ist bequem, aber ein Risiko: ein
kompromittiertes Passwort betrifft alle Apps gleichzeitig. Mittelfristig
sollte pro App ein separates Passwort vergeben werden, sobald die jeweilige
App das sauber unterstuetzt. Migrationsschritte stehen in den App-READMEs.

Hinweis Grafana: `FILEHUB_ADMIN_PASSWORD` aus `.env` wirkt fuer Grafana
ausschliesslich als Init-Wert beim ersten Container-Start. Sobald
`data/grafana/grafana.db` existiert, ignoriert Grafana den ENV-Wert -
spaetere Aenderungen an `FILEHUB_ADMIN_PASSWORD` aendern das laufende
Grafana-Admin-Passwort **nicht**. Wechsel via Grafana-UI oder
`grafana-cli` (siehe docs/APPS.md).

## Netzwerk-Bindings

- Alle App-Ports binden lokal an `127.0.0.1`.
- Public-Bindings (`0.0.0.0` oder externe Interfaces) sind zu vermeiden.
- Externer Zugriff laeuft ausschliesslich ueber das optionale Gateway
  (`infra/gateway`), idealerweise hinter Authentik oder VPN.

## Authentik als zusaetzliche Schutzschicht

Authentik ist optional (siehe `docs/AUTHENTIK_OPTIONAL.md`) und wirkt als
zusaetzliche Schutzschicht vor den Apps. Die App-internen Logins bleiben
unabhaengig davon bestehen -- Authentik ersetzt sie nicht, sondern setzt
einen vorgelagerten Auth-Layer.

## Secrets-Hygiene

- `.env`-Dateien und `.secrets/*.env` werden nicht ins Repo committed.
- Vor jedem Commit pruefen, dass keine Tokens, Cookies, Passwoerter oder
  privaten Schluessel mitgeführt werden.
- Beispiel- und Templatedateien verwenden ausschliesslich Platzhalter,
  z. B. `FILEHUB_ADMIN_PASSWORD=<set-local-secret>`.
- Restic-Repo-Passwoerter und Cloud-Credentials liegen unter `.secrets/`
  und werden verschluesselt gesichert (siehe `docs/encrypted-secrets-backup.md`).

## Docker-Socket

Wo moeglich werden Container ohne direkten `docker.sock`-Zugriff betrieben.
Wenn ein Mount noetig ist (Dozzle, Homepage), wird er read-only durchgereicht
und ueber einen Socket-Proxy gehaertet. Details: `docs/docker-socket-hardening.md`.

## Verweise

- `docs/secrets.md` -- Secrets-Verwaltung.
- `docs/security.md` -- bestehende Security-Notizen (kleines s).
- `docs/sso-gateway.md` -- Forward-Auth via Authentik.
- `docs/docker-socket-hardening.md` -- Docker-Socket-Haertung.
