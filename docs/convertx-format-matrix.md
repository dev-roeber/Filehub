# ConvertX Formatmatrix

Stand: 2026-05-14. ConvertX laeuft auf `127.0.0.1:3000` mit Tools
ffmpeg/ffprobe, pandoc, LibreOffice, ImageMagick, GraphicsMagick, vips,
Inkscape, libheif im Container.

Status-Spalte:

- **OK** — automatisiert per HTTP-API erfolgreich konvertiert (`scripts/convertx-e2e-run.sh`)
- **manuell offen** — Toolchain vorhanden, automatischer Lauf steht aus
- **nicht unterstuetzt** — Toolchain im Container nicht vorhanden

Testdateien siehe `scripts/prepare-convertx-test-files.sh` -> `data/convertx-test/input/`.
Outputs aus dem E2E-Lauf liegen in `data/convertx-test/output/` (gitignored).

## Bilder

| Quelle | Ziel | Status | Converter | Output | Bemerkung |
|---|---|---|---|---|---|
| PNG | WEBP | OK | imagemagick | 1.4 KB | |
| JPG | PNG | OK | imagemagick | 8.6 KB | |
| JPG | WEBP | OK | imagemagick | 2.5 KB | |
| SVG | PNG | OK | inkscape | 1.8 KB | |
| HEIC | JPEG | OK | libheif | 404 KB | Source: libheif Beispieldatei |
| WEBP | JPG | manuell offen | imagemagick | — | Toolchain vorhanden |
| PNG | PDF | manuell offen | imagemagick | — | Toolchain vorhanden |

## Dokumente

| Quelle | Ziel | Status | Converter | Output | Bemerkung |
|---|---|---|---|---|---|
| DOCX | PDF | OK | libreoffice | 23.6 KB | |
| TXT | PDF | OK | libreoffice | 14.8 KB | |
| MD | PDF | OK | pandoc | 6.7 KB | |
| MD | HTML | OK | pandoc | 108 B | |
| PDF | PNG | OK | imagemagick | 4.2 KB | |
| CSV | JSON | manuell offen | dasel | — | |
| EPUB | PDF | manuell offen | calibre/pandoc | — | |
| HTML | PDF | manuell offen | libreoffice/pandoc | — | |

## Audio

| Quelle | Ziel | Status | Converter | Output | Bemerkung |
|---|---|---|---|---|---|
| WAV | MP3 | OK | ffmpeg | 4.5 KB | nach FFMPEG_ARGS-Fix |
| WAV | OGG | OK | ffmpeg | 4.8 KB | nach FFMPEG_ARGS-Fix |
| M4A | MP3 | manuell offen | ffmpeg | — | iPhone-Aufnahme als Source |

## Video

| Quelle | Ziel | Status | Converter | Output | Bemerkung |
|---|---|---|---|---|---|
| MP4 | WEBM | OK | ffmpeg | 9.7 KB | 2s Clip |
| MP4 | GIF | OK | ffmpeg | 99 KB | 2s Clip |
| MOV | MP4 | manuell offen | ffmpeg | — | iPhone-Clip als Source |
| WEBM | MP4 | manuell offen | ffmpeg | — | |

## Wichtiger Fix: FFMPEG_ARGS

ConvertX setzt `FFMPEG_ARGS` VOR `-i`, nicht hinter. `-preset veryfast`
ist deshalb keine Encoding-Option mehr, sondern wird als ungueltige
Decoding-Option interpretiert. ffmpeg bricht damit alle Audio-Conversions
ab ("Codec AVOption preset (Encoding preset) is not a decoding option").

Konsequenz: `CONVERTX_FFMPEG_ARGS=""` (leer) in `.env` und `.env.example`,
`compose.convertx.yml` mit `${CONVERTX_FFMPEG_ARGS:-}` als Default.
Video laeuft auch ohne Preset stabil.

## Sicherheitshinweise

- Keine Hardware-Acceleration aktiv.
- ConvertX-Container hat `cpus: 2.0` und `mem_limit: 4g`.
- `MAX_CONVERT_PROCESS=2`: maximal zwei parallele Jobs.
- Video-Massentests sind explizit nicht vorgesehen.

## Cleanup

`CONVERTX_AUTO_DELETE_EVERY_N_HOURS=24` setzt das interne Aufraeumintervall
auf 24 Stunden. Sensible Dateien gehoeren trotzdem nicht in ConvertX, sondern
in Paperless mit echter Datenverwaltung.
