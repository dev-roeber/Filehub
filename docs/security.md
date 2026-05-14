# Sicherheit

Filehub startet initial nur auf localhost. Es gibt keine öffentlichen App-Portfreigaben.

## Grundregeln

- Alle Webdienste binden an `127.0.0.1`.
- Keine Bindings wie `0.0.0.0:8000` oder `8000:8000`.
- `.env` niemals committen.
- Secrets stark und eindeutig halten.
- Paperless enthält sensible Dokumente und muss wie ein vertraulicher Datenspeicher behandelt werden.
- Dozzle bleibt lokal, weil Logs Secrets oder personenbezogene Daten enthalten können.
- Reverse Proxy, Domain, HTTPS und zusätzliche Authentifizierung sind Phase 2.
- Backups regelmäßig erstellen und Restore testen.

## Firewall

UFW ist auf dem Server aktiv und erlaubt nach Live-Prüfung nur SSH. Docker kann eigene iptables-Regeln setzen; deshalb ist die lokale Bind-Adresse die wichtigste Schutzlinie gegen versehentliche Exposition.

## SSH

Remote-Zugriff erfolgt über SSH-Tunnel. App-Ports werden nicht in UFW geöffnet.

## Caddy

`compose.proxy.yml` nutzt ein Compose-Profil und bindet standardmäßig nur an localhost-Ports `8081` und `8443`. Die Datei `config/caddy/Caddyfile.example` ist ein Beispiel und keine produktive Freigabe.

## Docker-Socket-Mounts

Dozzle und Homepage mounten den Docker-Socket `read-only`:

- `dozzle`: liest Container-Status und Logs.
- `homepage`: liest Container-Status fuer das Dashboard.

`read-only` reduziert das Risiko, hebt es aber nicht auf. Wer den Socket lesen kann, sieht alle Container, deren Env-Variablen (inkl. moeglicher Secrets in Env), Logs und Netzwerke. Read-only verhindert nur `docker exec` oder `docker run` ueber denselben Socket, nicht das Auslesen sensibler Informationen.

Konsequenzen:

- Diese Dienste bleiben strikt auf `127.0.0.1`. Aktuell ist das durch Compose-Bindings sichergestellt.
- Bei spaeterer Public-Exponierung zuerst eine Auth-Schicht (Caddy/OAuth/Basic-Auth + Rate-Limiting) vorlagern. Ohne Auth keine Public-Freigabe.
- Reverse-Proxy darf keinen direkten Container-Port ueber `0.0.0.0` durchschleifen.
- Vor jeder Veroeffentlichung pruefen, ob der Socket-Mount fuer den jeweiligen Dienst noch noetig ist.

## Filebrowser

Filebrowser hat Schreib- und Loeschrechte auf den gemounteten Pfaden
(`data/filebrowser/root`, `data/paperless/consume`, `data/stirling/work`).
Es ist KEIN Mount auf `.env`, `.secrets/`, das Repo-Root oder Compose-Dateien
gesetzt. Trotzdem gilt:

- Kein Public Binding ohne zusaetzliche Auth/Reverse Proxy.
- Wer den UI-Login hat, kann Dateien in Paperless einspielen und Stirling-
  Arbeitsverzeichnisse manipulieren.
- Admin-Passwort gehoert in den Passwortmanager.

## Stirling PDF

- Login ist via `SECURITY_ENABLELOGIN=true` aktiv. Kein anonymer Zugriff.
- Kein Public Binding.
- PDFs koennen bei OCR/Konvertierung Ressourcen verbrauchen; bei
  oeffentlicher Exposition zwingend Auth + Rate-Limit vorlagern.

## Backups

Restic-Backups sind verschlüsselt, aber nur belastbar, wenn Restore regelmäßig getestet wird. Das restic-Passwort und die rclone-Konfiguration sind kritisch und dürfen nicht im Git landen.
