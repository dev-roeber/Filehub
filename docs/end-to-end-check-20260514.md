# Filehub End-to-End-Check 2026-05-14

## Web-UIs

| Service | URL | Status | HTTP |
|---|---|---|---|
| Paperless | http://127.0.0.1:8000 | UP | 302 (Login-Redirect) |
| ConvertX | http://127.0.0.1:3000 | UP | 302 (Login-Redirect) |
| Homepage | http://127.0.0.1:3001 | UP | 200 |
| Uptime Kuma | http://127.0.0.1:3002 | UP | 302 |
| Filebrowser | http://127.0.0.1:3003 | UP | 200 |
| Stirling PDF | http://127.0.0.1:3004 | UP | 401 (Login aktiv) |
| Dozzle | http://127.0.0.1:9999 | UP | 200 |

## Paperless

- Dokumenttypen: 9
- Tags: 13
- Korrespondenten: 9
- Dokumente: 1 (Smoke-Test-Dokument)
- Baseline-Skript idempotent (`scripts/setup-paperless-baseline.sh`).
- API-Token-Flow funktioniert.

## ConvertX

- Container healthy, JWT_SECRET gesetzt, `ACCOUNT_REGISTRATION=false`.
- `AUTO_DELETE_EVERY_N_HOURS=24` aktiv.
- `LANGUAGE=de`, `FFMPEG_ARGS=-preset veryfast`, `MAX_CONVERT_PROCESS=2`.
- CPU 2.0, RAM 4g.
- Toolchain im Container: ffmpeg 7.1, pandoc 3.1, LibreOffice 25.2,
  ImageMagick 7.1, GraphicsMagick 1.4, vips 8.16, Inkscape 1.4.
- Echte Konvertierungen via UI: manueller Testplan in
  `docs/convertx-manual-e2e.md`, Testdateien generiert
  (`data/convertx-test/input/`).

## Filebrowser

- HTTP 200, Healthcheck OK.
- Testdatei `data/filebrowser/root/e2e-test.txt` (38 Byte) angelegt,
  in der UI unter `/srv/e2e-test.txt` sichtbar.
- Mounts korrekt: `/srv`, `/srv/paperless-consume`, `/srv/pdf-work`.
- Kein Zugriff auf `.env` oder `.secrets/`.

## Stirling PDF

- HTTP 401 (Login aktiv) wie erwartet.
- Healthcheck OK.
- Test-PDFs `test.pdf` + `test2.pdf` unter `data/convertx-test/input/`
  vorbereitet fuer Merge/Split.

## Uptime Kuma

11/11 Monitore UP:

```text
 1 UP  Filehub Paperless        200 - OK
 2 UP  Filehub ConvertX         200 - OK
 3 UP  Filehub Homepage         200 - OK
 4 UP  Filehub Dozzle           200 - OK
 5 UP  Filehub Uptime Kuma      200 - OK
 6 UP  Filehub Gotenberg        200 - OK
 7 UP  Filehub Tika             200 - OK
 8 UP  Filehub PostgreSQL       (TCP)
 9 UP  Filehub Redis            (TCP)
10 UP  Filehub Filebrowser      200 - OK
11 UP  Filehub Stirling PDF     200 - OK
```

## Security

- `just security-check`: keine Public Bindings.
- UFW aktiv, nur 22/tcp offen.
- `just secrets-audit`: alle Pruefungen bestanden.
- ConvertX hat Resource-Limits (2 CPU, 4 GB RAM).

## Backup

- Timer aktiv, naechster Lauf Fri 2026-05-15 03:45.
- Pfade enthalten Filebrowser, Stirling, `compose.extensions.yml`.
- `data/convertx-test/output/` ist gitignored und nicht im restic-Set.
