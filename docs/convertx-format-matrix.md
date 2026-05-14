# ConvertX Formatmatrix

Stand: 2026-05-14. ConvertX laeuft auf `127.0.0.1:3000` mit Tools
ffmpeg/ffprobe, pandoc, LibreOffice, ImageMagick, GraphicsMagick, vips,
Inkscape im Container.

Status-Spalte:

- **OK** — in der UI erfolgreich getestet
- **manuell offen** — Toolchain vorhanden, aber UI-Test steht noch aus
- **nicht unterstuetzt** — Toolchain im Container nicht vorhanden
- **nicht getestet** — Variante nicht im Standard-Testplan

Testdateien siehe `scripts/prepare-convertx-test-files.sh` -> `data/convertx-test/input/`.

## Bilder

| Quelle | Ziel | Status | Bemerkung | Risiko |
|---|---|---|---|---|
| PNG | WEBP | manuell offen | ImageMagick + vips | niedrig |
| JPG | PNG | manuell offen | ImageMagick | niedrig |
| JPG | WEBP | manuell offen | ImageMagick | niedrig |
| WEBP | JPG | manuell offen | ImageMagick | niedrig |
| HEIC | JPG | manuell offen | Foto vom iPhone als Source nutzen | niedrig |
| SVG | PNG | manuell offen | Inkscape vorhanden | niedrig |
| PNG | PDF | manuell offen | ImageMagick | niedrig |

## Dokumente

| Quelle | Ziel | Status | Bemerkung | Risiko |
|---|---|---|---|---|
| DOCX | PDF | manuell offen | LibreOffice headless | mittel |
| TXT | PDF | manuell offen | pandoc + LibreOffice | niedrig |
| MD | PDF | manuell offen | pandoc | niedrig |
| MD | HTML | manuell offen | pandoc | niedrig |
| CSV | JSON | manuell offen | nur, wenn ConvertX UI das anbietet | niedrig |
| PDF | JPG | manuell offen | ImageMagick + Ghostscript | niedrig |
| PDF | PNG | manuell offen | ImageMagick + Ghostscript | niedrig |
| EPUB | PDF | manuell offen | pandoc | mittel |
| HTML | PDF | manuell offen | pandoc/LibreOffice | mittel |

## Audio

| Quelle | Ziel | Status | Bemerkung | Risiko |
|---|---|---|---|---|
| WAV | MP3 | manuell offen | ffmpeg | niedrig |
| MP3 | OGG | manuell offen | ffmpeg | niedrig |
| M4A | MP3 | manuell offen | iPhone-Aufnahme als Source | niedrig |

## Video

| Quelle | Ziel | Status | Bemerkung | Risiko |
|---|---|---|---|---|
| MP4 | WEBM | manuell offen | ffmpeg, kurze Clips (< 30s) | mittel |
| MOV | MP4 | manuell offen | ffmpeg | mittel |
| WEBM | MP4 | manuell offen | ffmpeg | mittel |
| MP4 | GIF | manuell offen | ffmpeg, sehr kurze Clips | hoch (RAM bei vielen Frames) |

## Sicherheitshinweise

- Keine Hardware-Acceleration aktiv. `CONVERTX_FFMPEG_ARGS=-preset veryfast`
  haelt CPU-Last in vertretbarem Rahmen.
- ConvertX-Container hat `cpus: 2.0` und `mem_limit: 4g`. Damit kann ein
  einzelner Konvertierungslauf den Host nicht voll auslasten.
- `MAX_CONVERT_PROCESS=2`: maximal zwei parallele Jobs.
- Video-Massentests sind explizit nicht vorgesehen.

## Cleanup

`CONVERTX_AUTO_DELETE_EVERY_N_HOURS=24` setzt das interne Aufraeumintervall
auf 24 Stunden. Sensible Dateien gehoeren trotzdem nicht in ConvertX, sondern
in Paperless mit echter Datenverwaltung.
