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
- Hardening-Plan und Alternativen (Socket-Proxy, Dozzle ohne Actions,
  statische Homepage-Discovery) stehen in
  `docs/docker-socket-hardening.md`.

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
- **Ressourcenlimits gesetzt:** `cpus: 2.0`, `mem_limit: 4g`,
  `pids_limit: 512`. Details und Hintergrund in
  `docs/stirling-pdf.md`.

## ConvertX

- Login aktiv, `ACCOUNT_REGISTRATION=false` nach Initial-Setup.
- `ALLOW_UNAUTHENTICATED=false`, `HTTP_ALLOWED=true` (nur fuer localhost).
- `cpus: 2.0`, `mem_limit: 4g`, `MAX_CONVERT_PROCESS=2`.
- Video-Konvertierung ist CPU-/RAM-lastig; keine grossen Stresstests.
- `AUTO_DELETE_EVERY_N_HOURS=24` raeumt UI-Verlauf auf, ist aber kein
  Ersatz fuer datenschutzgerechte Archivierung — sensible Dokumente
  gehoeren in Paperless, nicht in den ConvertX-Verlauf.
- Vor Public-Exposition: Auth-Schicht (Caddy/OAuth) und Rate-Limit
  zwingend vorlagern.

## Benachrichtigungen (ntfy)

Das ntfy-Topic ist ein **Secret**. Wer den Topic-Namen kennt, kann
Nachrichten lesen **und** senden, solange der Server keinen
Auth-Layer hat. Konsequenzen:

- Topic-Name niemals committen, nicht in Issues/PRs posten.
- Topic-Name nur in `.secrets/` (Mode 600) oder im Passwortmanager.
- Bei Verdacht auf Leak: Topic wechseln, alle Sender/Empfaenger neu
  konfigurieren.

## Authentik-SSO-Gateway (Phase 1)

Stand 2026-05-15. Details: `docs/sso-gateway.md`.

- Gateway-Login ist **kein** App-SSO. Paperless, ConvertX, Filebrowser
  und Stirling behalten ihre eigenen Logins. Das Gateway-Login ist
  eine zusaetzliche Vorbarriere, kein Ersatz.
- Backend-Ports (3000-3004, 8000, 9999) muessen weiterhin
  localhost-only binden. UFW erlaubt aktuell nur 22/tcp und darf in
  Phase 1 nicht fuer 80/443 geoeffnet werden.
- Filebrowser, Dozzle und Stirling duerfen niemals oeffentlich
  werden, weder direkt noch ueber das Gateway, solange kein TLS und
  kein echtes OIDC pro App produktiv ist.
- Caddy `forward_auth` reicht nur eine Whitelist von Headern an
  Backends durch (`X-Authentik-Username`, `X-Authentik-Email`,
  `X-Authentik-Groups`, `X-Authentik-Uid`). Generische Header wie
  `Remote-User` oder `X-Forwarded-User` bleiben blockiert.
- Backends muessen Authentik-Header validieren, statt blind
  `Remote-User` zu vertrauen. Solange das Backend ein eigenes Login
  hat, bleibt das Backend-Login die maßgebliche Auth.
- Authentik-Secrets liegen ausschliesslich in
  `.secrets/authentik.env` (Mode `600`). Nicht in Compose-Dateien,
  nicht im Repo, nicht im Backup-Default.
- `AUTHENTIK_BOOTSTRAP_PASSWORD` wird im laufenden Betrieb **nicht
  mehr** ausgewertet. Authentik liest die Bootstrap-Variablen nur
  beim ersten Start, wenn noch kein Admin-User existiert. Nach
  erfolgreichem Initial-Setup sollte das Bootstrap-Passwort rotiert
  und der Bootstrap-Eintrag aus `.secrets/authentik.env` entfernt
  werden, oder bewusst als Notnagel stehen bleiben.
- Authentik-UI (Port 9000) bleibt localhost-only. Kein Public-Bind,
  auch nicht ueber das Gateway.

## Backups

Restic-Backups sind verschlüsselt, aber nur belastbar, wenn Restore regelmäßig getestet wird. Das restic-Passwort und die rclone-Konfiguration sind kritisch und dürfen nicht im Git landen.
