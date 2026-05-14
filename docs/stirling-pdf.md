# Stirling PDF

Stirling PDF laeuft auf `127.0.0.1:3004`. Lokales Werkzeug fuer PDF-Operationen.

## Zugriff

Per SSH-Tunnel oder lokal:

```text
http://127.0.0.1:3004
```

Login mit `SECURITY_INITIALLOGIN_USERNAME` und `_PASSWORD` aus
`.secrets/stirling-pdf.env` (Mode 600, gitignored). Passwort sofort in den
Passwortmanager uebernehmen.

## Login aktiv

`SECURITY_ENABLELOGIN=true` und `DISABLE_ADDITIONAL_FEATURES=false`.
Wer ohne Login durchstarten will, muss das bewusst aendern.

## Typische Workflows

- **PDF mergen** — mehrere PDFs in eine Datei.
- **PDF splitten** — nach Seitenbereich oder Seitenanzahl.
- **Seiten drehen** — falls Scan falsch herum.
- **PDF komprimieren** — Speicherplatz reduzieren.
- **Bilder/PDF konvertieren** — JPG/PNG <-> PDF, einfache OCR.

## Mounts

| Container-Pfad | Host-Pfad |
|---|---|
| `/usr/share/tessdata` | `data/stirling/trainingData` |
| `/configs` | `data/stirling/extraConfigs` |
| `/customFiles` | `data/stirling/customFiles` |
| `/logs` | `data/stirling/logs` |
| `/pipeline` | `data/stirling/pipeline` |
| `/tmp/filehub-pdf-work` | `data/stirling/work` |

`data/stirling/work` ist auch in Filebrowser unter `/srv/pdf-work` gemountet,
so dass PDFs einfach zwischen den Tools getauscht werden koennen.

## Sicherheit

- Login aktiv, kein anonymer Zugriff.
- Kein Public Binding.
- Upload-Risiko: schadhafte PDFs koennen bei OCR/Konvertierung Ressourcen
  belasten. Container hat 0 explizite Limits; bei Bedarf `mem_limit` setzen.
