# Notifications Roadmap

Stand: 2026-05-14. Aktuell laufen keine Notifications. Stack ist
Single-User + lokal, daher zunaechst Pull-basiert (Homepage + Uptime Kuma).

## Geplante Kanaele

### ntfy

- Self-hosted oder ntfy.sh.
- Uptime Kuma kann ntfy direkt ansprechen.
- Topic-Namen sollten unraetbar gewaehlt werden, sonst ist die Notification
  oeffentlich lesbar.
- Push auf iOS via ntfy-App.

### Mail

- SMTP-Daten gehoeren in `.secrets/notify.env`.
- Uptime Kuma + cron-Mail (postfix lokal) als Fallback.
- Auf Single-User-Stack reicht ein Provider mit App-Passwort.

## Geplante Trigger

- **Backup-Fehler** — wenn `scripts/backup.sh` mit Exit != 0 endet
  (systemd `OnFailure=`).
- **Restic-Repo nicht erreichbar** — Healthcheck im Backup-Skript.
- **Uptime-Alarme** — alle Monitore in Uptime Kuma, mit Mindest-Downtime
  von 2 Minuten, um Flapping zu vermeiden.
- **TLS-Cert-Ablauf** — nur relevant, sobald Caddy Public-Mode laeuft.

## Nicht jetzt aktivieren

- Bevor Notifications scharfgeschaltet werden, sollte eine ruhige Baseline
  von zwei Wochen ohne falsche Alarme stehen.
- Keine produktiven Webhooks vor `.secrets/notify.env`.
- Reverse Proxy + Auth zuerst, bevor Notifications auf Public-Channels
  laufen.

## Schritte

1. ntfy-Topic + App einrichten.
2. Uptime Kuma -> Notification -> ntfy hinzufuegen.
3. Backup-Service `OnFailure=notify-backup-fail.service` ergaenzen.
4. Erst danach Monitor-fuer-Monitor scharf schalten.
