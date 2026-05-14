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

## Backups

Restic-Backups sind verschlüsselt, aber nur belastbar, wenn Restore regelmäßig getestet wird. Das restic-Passwort und die rclone-Konfiguration sind kritisch und dürfen nicht im Git landen.
