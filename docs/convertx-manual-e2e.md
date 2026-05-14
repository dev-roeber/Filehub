# ConvertX manueller End-to-End-Test

ConvertX bietet keine stabile, dokumentierte API fuer Upload + Conversion
ohne aktive UI-Session. Deshalb laeuft der End-to-End-Test ueber die UI,
mit vorbereiteten Testdateien.

## Vorbereitung

```bash
./scripts/prepare-convertx-test-files.sh
```

Erzeugt unter `data/convertx-test/input/`:

- `test.png`, `test.jpg`, `test.svg`
- `test.pdf`
- `test.txt`, `test.md`, `test.csv`
- `test.docx`
- `test.wav`
- `test.mp4` (2 Sekunden, 320x240, 10 fps)

Diese Dateien sind harmlos und enthalten keine echten Daten.

Outputs landen unter `data/convertx-test/output/` (im `.gitignore`).

## UI oeffnen

Per SSH-Tunnel oder lokal:

```text
http://127.0.0.1:3000
```

Login mit Admin-Konto (siehe `.secrets/convertx.env`, falls eingerichtet).

## Test-Klickpfade

Fuer jede Konvertierung:

1. "Choose files" / "Upload" -> Testdatei waehlen.
2. Zielformat auswaehlen.
3. "Convert" druecken.
4. Wenn fertig: Download starten.
5. Datei nach `data/convertx-test/output/` ablegen oder direkt auf den Host
   speichern.

### Bilder

- [ ] `test.png` -> WEBP
- [ ] `test.jpg` -> PNG
- [ ] `test.jpg` -> WEBP
- [ ] `test.svg` -> PNG
- [ ] HEIC vom iPhone -> JPG (optional, eigener Upload)

### Dokumente

- [ ] `test.docx` -> PDF
- [ ] `test.txt` -> PDF
- [ ] `test.md` -> PDF
- [ ] `test.md` -> HTML
- [ ] `test.pdf` -> JPG
- [ ] `test.pdf` -> PNG

### Audio

- [ ] `test.wav` -> MP3
- [ ] `test.wav` -> OGG

### Video

- [ ] `test.mp4` -> WEBM
- [ ] `test.mp4` -> GIF (nur kurze Clips)

## Erwartete Beobachtungen

- Jeder Job startet einen Worker im Container; max. 2 parallel.
- Ausgaben unter 5 MB Quellgroesse sollten innerhalb weniger Sekunden fertig sein.
- Bei Video kann der Container kurzzeitig 100 % einer CPU verbrauchen,
  bleibt aber unter 4 GB RAM (`mem_limit`).

## Bei Fehlern

- Dozzle oeffnen: `http://127.0.0.1:9999` -> Container `filehub-convertx`.
- Healthcheck: `docker inspect -f '{{.State.Health.Status}}' filehub-convertx`.
- Logs: `just logs filehub-convertx`.

## Cleanup

`CONVERTX_AUTO_DELETE_EVERY_N_HOURS=24` raeumt Eintraege im ConvertX-Verlauf
nach 24 Stunden auf. Trotzdem keine sensiblen Dateien in ConvertX uploaden,
denn der Verlauf ist anderer Logik unterworfen als ein dokumentenechtes
Archiv (dafuer ist Paperless da).

## Hinweis zur Automatisierung

Eine automatisierte E2E-Pipeline ueber HTTP-API ist bewusst nicht
implementiert: ConvertX nutzt JWT-Cookies, CSRF-aehnliche Mechanismen und
unstabile Endpunkte. Eine Headless-Browser-Loesung (Playwright o. ae.) ist
fuer einen Single-User-Stack ueberdimensioniert.
