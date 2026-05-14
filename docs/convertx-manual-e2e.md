# ConvertX End-to-End-Test

ConvertX hat keine stabile public API; intern laeuft Authentifizierung
ueber ein JWT-Cookie nach `/login`. Mit diesem Cookie sind `/upload`,
`/convert`, `/results/:jobId` und der Datei-Download per `curl` problemlos
nutzbar — wir machen genau das.

## Automatisierter Lauf

```bash
./scripts/convertx-e2e-run.sh
```

Verwendet `.secrets/convertx.env` (Admin-Email und -Passwort, Mode 600,
nicht im Git). Loggt sich ein, legt fuer jeden Test eine neue ConvertX-Job-ID
an, lädt eine Testdatei hoch, startet die Conversion, wartet auf
`status=completed` in der internen SQLite und kopiert das Ergebnis nach
`data/convertx-test/output/`.

Aktuell abgedeckt (14/14 gruen):

- Bild: PNG/JPG/SVG nach WEBP/PNG, HEIC nach JPEG
- Dokument: DOCX/TXT nach PDF (libreoffice), MD nach PDF/HTML (pandoc),
  PDF nach PNG (imagemagick)
- Audio: WAV nach MP3 und OGG (ffmpeg)
- Video: MP4 nach WEBM und GIF (ffmpeg)

## Vorbereitung der Testdateien

```bash
./scripts/prepare-convertx-test-files.sh
```

Erzeugt unter `data/convertx-test/input/`:

- `test.png`, `test.jpg`, `test.svg`
- `test.pdf`, `test.txt`, `test.md`, `test.csv`
- `test.docx`
- `test.wav` (1s Sinus 22050 Hz)
- `test.mp4` (2s, 320x240, 10 fps)
- `test.heic` (libheif-Beispieldatei, falls Netz verfuegbar)

## UI-Optionalkontrolle

Per SSH-Tunnel oder lokal: `http://127.0.0.1:3000`. Login mit dem Konto
aus `.secrets/convertx.env`. Sinnvoll fuer manuelle Spot-Checks:

- iPhone-HEIC und iPhone-MOV von Hand hochladen (echte Quellen).
- Calibre-Konvertierung EPUB nach PDF.
- Massen-Upload mehrerer Dateien.

## Fehlerquellen

- ConvertX setzt `FFMPEG_ARGS` VOR `-i`. Audio bricht, wenn das Encoding-
  Optionen wie `-preset veryfast` enthaelt. Defaultwert ist deshalb leer.
- Beim Recreate des Containers bleibt `data/convertx/mydb.sqlite` erhalten,
  weil `data/convertx/` als Bind-Mount eingehaengt ist. Beim ersten Start
  ohne User wuerde `/register` blockiert sein (`ACCOUNT_REGISTRATION=false`).
  Falls noetig: `ACCOUNT_REGISTRATION=true` setzen, registrieren, danach
  wieder `false`.

## Cleanup

`CONVERTX_AUTO_DELETE_EVERY_N_HOURS=24` raeumt Eintraege im ConvertX-Verlauf
nach 24 Stunden auf. Trotzdem keine sensiblen Dateien in ConvertX uploaden —
fuer Archivierung ist Paperless zustaendig.
