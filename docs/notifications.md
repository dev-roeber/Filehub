# Notifications via ntfy

Stand: 2026-05-15. Filehub nutzt ntfy als primaeren Push-Kanal fuer
Backup-Fehler und Storage-Warnungen. Der Stack laeuft localhost-only,
ntfy lebt ausserhalb davon und wird ueber HTTPS an einen ntfy-Broker
(self-hosted oder ntfy.sh) gesendet.

## Geheimnis-Datei

Alle ntfy-Parameter liegen in `.secrets/ntfy.env`. Die Datei ist
git-ignored, Modus `600`, Besitz `sebastian:sebastian`. Verzeichnis
`.secrets/` hat Modus `700`.

Verwendete Variablennamen (Werte stehen nur in der Datei, nicht hier
und nicht in Logs):

- `NTFY_ENABLED`
- `NTFY_SERVER`
- `NTFY_TOPIC`
- `NTFY_TOKEN`
- `NTFY_PRIORITY_DEFAULT`
- `NTFY_TAGS_DEFAULT`

Das Topic ist der einzige Schutz vor dem Mitlesen durch Dritte. Es muss
unraetbar sein und darf nirgendwo veroeffentlicht werden: nicht in
Issues, nicht in Commits, nicht in Screenshots, nicht in Doku, nicht in
Logs. Topic gehoert in den Passwortmanager des Hauptbenutzers.

## Test

```bash
scripts/notify.sh "Filehub" "Testnachricht" "default"
```

Das Skript liest `.secrets/ntfy.env`, baut die Anfrage und sendet sie
ohne Topic-Echo an Stdout. Wenn `NTFY_ENABLED=false`, wird sofort und
ohne Netzwerkaufruf zurueckgekehrt.

## ntfy-App abonnieren

1. ntfy-App installieren (iOS oder Android).
2. In der App: `Add subscription`.
3. Server-URL gemaess `NTFY_SERVER` eintragen.
4. Topic-Namen gemaess `NTFY_TOPIC` eintragen.
5. Optional: Token in der App hinterlegen, falls der Broker
   Authentifizierung erzwingt.
6. Nach `scripts/notify.sh`-Test pruefen, ob die Push-Nachricht auf
   dem Geraet ankommt.

## Integrationen

- **Backup-Fehler**: `scripts/backup-alert.sh` wird ueber
  `deploy/systemd/filehub-backup-alert@.service` als `OnFailure` von
  `filehub-backup.service` ausgeloest. Details in
  [backup-schedule.md](backup-schedule.md).
- **Backup-Report**: `scripts/backup-report.sh` sendet nach jedem
  erfolgreichen Lauf eine kurze Statuszeile.
- **Storage-Warnung**: `scripts/storage-check.sh` prueft Repo- und
  Disk-Verbrauch und schickt eine Warnung, wenn Schwellen ueberschritten
  werden.
- **Uptime Kuma**: manuell in der UI verkabelt, siehe
  [uptime-kuma.md](uptime-kuma.md).

## Abschalten

`NTFY_ENABLED=false` in `.secrets/ntfy.env` setzen. Alle Skripte
respektieren diesen Schalter und werden zum No-Op, ohne Fehler zu
werfen. Damit bleibt der systemd-`OnFailure`-Pfad funktionsfaehig, aber
stumm.

## Sicherheits-Hinweise

- Topic nie oeffentlich teilen.
- Nur HTTPS-Broker verwenden.
- Keine Klartext-Werte aus `.secrets/ntfy.env` in Doku, Issues oder
  Chat-Verlaeufe uebernehmen.
- Backups von `.secrets/` enthalten die ntfy-Daten und sind wie Secrets
  zu behandeln.
- Bei Topic-Leak: Topic in der ntfy-App und in `.secrets/ntfy.env`
  rotieren und das alte Abo loeschen.
