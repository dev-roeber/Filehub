# Notifications Roadmap

Stand: 2026-05-15. Filehub laeuft localhost-only. Notifications laufen
ueber ntfy als primaeren Push-Kanal. Mail ist noch nicht eingerichtet.

## Status der Kanaele

### ntfy (aktiv)

- Setup abgeschlossen, siehe [notifications.md](notifications.md).
- `.secrets/ntfy.env` mit Modus `600` vorhanden, Variablennamen
  `NTFY_ENABLED`, `NTFY_SERVER`, `NTFY_TOPIC`, `NTFY_TOKEN`,
  `NTFY_PRIORITY_DEFAULT`, `NTFY_TAGS_DEFAULT`.
- `scripts/notify.sh` als zentraler Sender.
- Backup-Fehler-Alerts ueber `filehub-backup-alert@.service` als
  `OnFailure` von `filehub-backup.service`, Skript
  `scripts/backup-alert.sh`.
- Backup-Report ueber `scripts/backup-report.sh` /
  `just backup-report`.
- Storage-Warnungen ueber `scripts/storage-check.sh`.
- Topic gehoert in den Passwortmanager und wird nirgendwo
  veroeffentlicht.

### Mail (offen)

- Kanal noch nicht eingerichtet.
- SMTP-Daten gehoeren spaeter in `.secrets/notify-mail.env`
  (Modus `600`), Variablennamen werden bei Einrichtung festgelegt.
- Zielbild: Mail als Fallback, falls ntfy-Push nicht ankommt
  (z. B. Geraet offline ueber laengeren Zeitraum).
- Auf Single-User-Stack reicht ein Provider mit App-Passwort.

## Naechste Schritte

1. Uptime Kuma manuell mit ntfy verkabeln (UI, nicht API), siehe
   [uptime-kuma.md](uptime-kuma.md). Default-fuer-alle-Monitore
   anhaken, Test-Notification ausloesen.
2. Stabilitaets-Beobachtung: zwei Wochen ohne falsche Alarme als
   Voraussetzung, bevor weitere Notification-Regeln scharfgeschaltet
   werden.
3. Mail-Kanal einrichten, sobald ein konkreter Bedarf entsteht
   (z. B. Push-Ausfall, Dauer-Offline-Geraet).
4. TLS-Cert-Ablauf-Alerts werden erst relevant, wenn Caddy in einem
   Public-Mode laeuft. Aktuell ist Filehub localhost-only und damit
   irrelevant.

## Bewusst nicht aktiviert

- Keine produktiven Webhooks ausserhalb von ntfy.
- Keine oeffentliche ntfy-Topic-Veroeffentlichung.
- Kein Reverse Proxy nur fuer Notifications.
- Keine automatische Mail-Bridge vor `.secrets/notify-mail.env`.
