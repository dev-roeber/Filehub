# Architektur

Filehub ist ein modularer Docker-Compose-Stack auf einem einzelnen Host.

```text
User
  -> SSH-Tunnel
  -> 127.0.0.1 Ports
  -> Docker Services
  -> interne Dienste
  -> lokale und optionale restic/rclone Backups
```

## Komponenten

- Paperless-ngx verarbeitet Dokumente, OCR, Tags, Suche und Medien.
- PostgreSQL speichert die Paperless-Datenbank.
- Redis dient Paperless als Broker/Cache.
- Apache Tika und Gotenberg ermöglichen Office- und E-Mail-Verarbeitung.
- ConvertX konvertiert Dateien lokal.
- Dozzle zeigt Container-Logs.
- Uptime Kuma überwacht lokale Endpunkte.
- Homepage bietet eine lokale Übersicht.
- restic und rclone sind für verschlüsselte lokale oder Remote-Backups vorbereitet.
- Caddy ist vorbereitet, aber nicht Teil des Standardstarts.

## Netzwerk

Alle Container teilen sich das interne Docker-Netzwerk `filehub_net`. Nur Webdienste, die ein Browser-UI brauchen, werden am Host gebunden, und zwar ausschließlich an `127.0.0.1`.

Interne Dienste wie PostgreSQL, Redis, Tika und Gotenberg haben keine Host-Portfreigabe.

## Persistenz

Persistente Daten liegen unter `data/`. Backups liegen unter `backups/` und werden wegen möglicher sensibler Inhalte nicht committed.

Das Repository liegt initial unter `/home/sebastian/Repos/Filehub`. `/opt/stacks` existierte beim Setup nicht; `/opt/stacks/filehub` bleibt als späterer Deploy-Pfad dokumentiert.
