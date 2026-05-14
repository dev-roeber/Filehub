# ConvertX Setup

ConvertX laeuft hinter `127.0.0.1:3000`. Erreichbar per SSH-Tunnel oder lokal.

## Compose-Konfiguration

`compose.convertx.yml` setzt:

- `JWT_SECRET` aus `.env`
- `ACCOUNT_REGISTRATION=false` (Standard nach Initial-Setup)
- `MAX_CONVERT_PROCESS=2`
- Port nur `127.0.0.1:3000`
- CPU/Memory-Limits: 2 CPU, 4 GB

## Initiales Setup

1. **Einmalig** Registrierung temporaer erlauben, falls noch kein Admin existiert:
   `ACCOUNT_REGISTRATION=true` in `.env` setzen, `just restart`.
2. UI oeffnen: `http://127.0.0.1:3000`, Admin-Konto anlegen.
3. Wert sofort wieder auf `false` setzen, `just restart`.
4. Admin-Passwort in den Passwortmanager uebernehmen.

## Smoke-Test

```bash
./scripts/convertx-smoke-test.sh
```

Prueft:

- HTTP 200 auf `/`
- Container `(healthy)` in `docker compose ps`
- Keine `ERROR` in den letzten 100 Log-Zeilen
- Konfig: `ACCOUNT_REGISTRATION` ist `false`

Eine echte Konvertierung wird **nicht** automatisch ausgeloest, weil ConvertX
fuer Uploads eine authentifizierte Session braucht und die API nicht stabil
ohne UI-Login nutzbar ist.

## Manueller Test-Plan

In der UI:

1. **HEIC -> JPG** — Test mit Foto aus dem Smartphone.
2. **PNG -> WEBP** — verlustfreie Komprimierung pruefen.
3. **DOCX -> PDF** — Office-Dokument konvertieren.
4. **PDF -> JPG** — einzelne Seite als Bild exportieren.

Nach jedem Test pruefen, dass der Download startet und die Datei aufgeraeumt wird.

## Auto-Delete

`AUTO_DELETE_EVERY_N_HOURS` ist im Compose nicht gesetzt; ConvertX nutzt den
eigenen Default. Bei Bedarf in `compose.convertx.yml` ergaenzen, z. B.:

```yaml
AUTO_DELETE_EVERY_N_HOURS: "24"
```

## Sicherheit

- Keine sensiblen Uploads in ConvertX legen, solange die Instanz nicht
  vertraulichkeitsverpflichtet betrieben wird.
- Zugriff nur ueber localhost/Tunnel.
- `JWT_SECRET` ist in `.env` und gehoert zu den restore-kritischen Secrets.
