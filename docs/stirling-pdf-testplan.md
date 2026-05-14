# Stirling PDF Testplan

Stirling PDF (`127.0.0.1:3004`) wird ueber die UI bedient. Die API
existiert, ist aber an die Login-Session gekoppelt. Fuer Single-User-Setup
reicht ein UI-Testplan mit vorbereiteten Test-PDFs.

## Test-PDFs vorbereiten

```bash
./scripts/prepare-convertx-test-files.sh
```

erzeugt `data/convertx-test/input/test.pdf`. Fuer Merge-Tests einfach eine
Kopie:

```bash
cp data/convertx-test/input/test.pdf data/convertx-test/input/test2.pdf
```

Beide Dateien lassen sich entweder direkt im Stirling-UI hochladen oder
via Filebrowser nach `data/stirling/work` legen.

## Klickpfade

### Merge

1. Stirling UI -> "Organize" -> "Merge PDFs".
2. `test.pdf` + `test2.pdf` hochladen.
3. "Merge" druecken.
4. Ergebnis-PDF herunterladen.

Erwartet: doppelte Seitenanzahl im Ergebnis.

### Split

1. Stirling UI -> "Organize" -> "Split PDF".
2. Ergebnis-PDF aus Merge-Test hochladen.
3. Splitmodus: nach Seitenanzahl, 1.
4. ZIP mit Einzelseiten laden.

### Rotate

1. "General" -> "Rotate PDF".
2. `test.pdf` hochladen, 90 Grad nach rechts.
3. Ergebnis-PDF pruefen.

### Compress

1. "General" -> "Compress PDF".
2. `test.pdf` hochladen, Standardkompression.
3. Ergebnis-PDF pruefen.

## Aufraeumen

`data/stirling/work` ist das interne Arbeitsverzeichnis und wird vom
Container automatisch verwaltet. Bei groesseren OCR-/Konvertierungsjobs kann
es waehrend des Laufs anwachsen; nach Abschluss raeumt Stirling selbst auf.

## Ressourcenrisiko

- OCR und Kompression sind RAM-/CPU-lastig, vor allem bei vielen Seiten.
- Keine Limits gesetzt; auf 16-GB-Host bei einzelnen PDFs unkritisch.
- Bei Massenverarbeitung Limits via Compose ergaenzen.

## Bei Fehlern

- Healthcheck: `docker inspect -f '{{.State.Health.Status}}' filehub-stirling-pdf`.
- Logs in Dozzle: Container `filehub-stirling-pdf`.
