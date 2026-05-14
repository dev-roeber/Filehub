# Paperless-ngx Setup und Baseline

Paperless-ngx laeuft hinter `127.0.0.1:8000`. Erreichbar nur per SSH-Tunnel
oder lokal auf dem Server.

## Erstes Setup

1. Tunnel oeffnen (`docs/ssh-tunnel.md`).
2. `http://127.0.0.1:8000` im Browser oeffnen.
3. Login mit `${PAPERLESS_ADMIN_USER}` aus `.env`. Initial-Passwort steht in
   `.env`/Passwortmanager, **nicht** in dieser Doku.
4. Passwort nach Wahl in Paperless aendern, dann in den Passwortmanager
   uebernehmen.

## API-Token erzeugen

1. UI -> oben rechts -> "Mein Profil" -> "API-Auth-Token".
2. Token erstellen, anzeigen, in `.secrets/paperless.env` ablegen:

```env
PAPERLESS_URL=http://127.0.0.1:8000
PAPERLESS_USERNAME=sebastian
PAPERLESS_PASSWORD=
PAPERLESS_TOKEN=<token>
```

Dateimodus `600`. Datei ist gitignored.

Alternativ holt das Setup-Script den Token via `/api/token/` selbst, wenn nur
`PAPERLESS_USERNAME` und `PAPERLESS_PASSWORD` gesetzt sind.

## Baseline ausfuehren

```bash
./scripts/setup-paperless-baseline.sh
```

Das Skript ist idempotent und legt Dokumenttypen, Tags und Korrespondenten
nur an, wenn sie noch nicht existieren. Bestehende Daten werden nie
geloescht oder umbenannt.

Angelegt werden:

**Dokumenttypen:** Rechnung, Vertrag, Brief, Steuerunterlage, Versicherung,
Garantie, Lohnabrechnung, Kontoauszug, Sonstiges.

**Tags:** Privat, Wichtig, Steuer, Rechnung, Vertrag, Versicherung,
Garantie, Gesundheit, Arbeit, Auto, Wohnung, To-Review, Archiviert.

**Korrespondenten:** Finanzamt, Krankenkasse, Bank, Versicherung,
Arbeitgeber, Vodafone, Telekom, Amazon, Sonstiges.

## Consume-Ordner

Pfad auf dem Host:

```text
data/paperless/consume
```

Dateien, die hier abgelegt werden, werden von Paperless verarbeitet und im
Anschluss aus dem Verzeichnis entfernt (Paperless verschiebt sie nach
`media/`). Filebrowser mounted denselben Pfad unter `/srv/paperless-consume`,
so dass Upload ueber den Browser moeglich ist.

## OCR-Sprache

`PAPERLESS_OCR_LANGUAGE: deu+eng` ist im Compose gesetzt. Dokumente werden
zunaechst deutsch, dann englisch erkannt. Aenderungen erfordern Container-
Neustart.

## Empfohlener Workflow fuer den ersten Import

1. Steuerunterlagen vom letzten Jahr scannen oder als PDF sammeln.
2. Per Filebrowser oder direkt per `cp` in `data/paperless/consume` legen.
3. In der Paperless-UI "Posteingang" pruefen, Tags/Dokumenttyp ergaenzen.
4. Nach Pruefung Tag `Archiviert` setzen, `To-Review` entfernen.

## Backup-Relevanz

`scripts/backup.sh` sichert `data/paperless` komplett als
`paperless-data.tar.gz` lokal und in restic. Postgres-Dump separat.
Sessions/Token sind nur in Paperless gespeichert; das `PAPERLESS_SECRET_KEY`
gehoert zu den restore-kritischen Secrets (`docs/secrets.md`).
