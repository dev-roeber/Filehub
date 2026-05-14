# Roadmap

## Phase 1

- Localhost-only Stack betreiben.
- Paperless, ConvertX, Homepage, Dozzle und Uptime Kuma initial einrichten.
- Uptime-Kuma-Checks anlegen.
- Lokales Backup ausführen und Restore-Ablauf dokumentiert testen.

## Phase 2

- restic/rclone Remote-Backup aktivieren.
- Backup-Retention im Betrieb prüfen.
- Restore-Test aus Remote-Backup durchführen.
- Update-Prozess nach erster Betriebswoche nachschärfen.

## Phase 3

- Reverse Proxy nur bei Bedarf aktivieren.
- Domain, HTTPS, Authentifizierung und Firewall-Regeln bewusst planen.
- Optional VPN statt öffentlichem Reverse Proxy prüfen.
- Automatisierung für Backups und Healthchecks ergänzen.

## Nicht-Ziele

- Keine öffentliche Standardbereitstellung.
- Keine Secrets im Git.
- Kein automatisches Löschen produktiver Daten.
