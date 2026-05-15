# apps/whisper-asr

Speech-to-Text Webservice basierend auf OpenAI Whisper
(Image: onerahmet/openai-whisper-asr-webservice, CPU-Variante).

## Zweck

Stellt eine HTTP-API zur Transkription von Audio-/Videodateien bereit.
OpenAPI-Doku unter `/docs`, Transkription via POST `/asr`.

## Port

Lokal erreichbar unter `http://127.0.0.1:9001/` (Host-Port 9001 -> Container 9000).
Port 9000 ist bereits durch filehub-authentik-server belegt.

## Modellgroessen (ASR_MODEL)

| Modell  | Groesse   | RAM-Bedarf  |
|---------|-----------|-------------|
| tiny    | ~75 MB    | ~1 GB       |
| base    | ~150 MB   | ~2 GB       |
| small   | ~500 MB   | ~3 GB       |
| medium  | ~1.5 GB   | ~5 GB       |
| large   | ~3 GB     | ~10 GB      |

WARNUNG: hoher RAM/CPU-Bedarf, insbesondere ab medium. CPU-Transkription
ist deutlich langsamer als Realtime. Fuer Production grosser Modelle
GPU-Variante (-gpu-Tag) erwaegen.

## Erst-Start

Beim ersten Start wird das gewaehlte Modell heruntergeladen
(`/root/.cache/whisper`). Je nach Netz und Modellgroesse dauert das
mehrere Minuten. Healthcheck `start_period` ist daher auf 120s gesetzt.

## Betrieb

```
just app-up whisper-asr
just app-down whisper-asr
just app-logs whisper-asr
just app-health whisper-asr
```

Oder direkt:

```
docker compose --env-file .env -f apps/whisper-asr/compose.yml up -d
docker compose --env-file .env -f apps/whisper-asr/compose.yml logs -f
bash apps/whisper-asr/healthcheck.sh
```

## Beispiel-Request

```
curl -F "audio_file=@sample.mp3" \
  "http://127.0.0.1:9001/asr?encode=true&task=transcribe&output=json"
```

## Backup

Der Modellcache (`data/whisper-asr/cache`) ist GROSS und REPRODUZIERBAR
(Neuer Download beim Start, falls leer) und ist daher standardmaessig
NICHT in `backup.include` enthalten. Im Backup sind lediglich
Arbeitsdaten und Compose-/Env-Beispiel.

## Authentik (optional)

`caddy.authentik.disabled` ist eine Vorlage fuer forward_auth via
Authentik-Outpost. Aktivierung durch Umbenennen zu `.caddy.authentik`
und Einbinden im Gateway-Caddyfile.

## Sicherheit

Image enthaelt KEINE Auth-Daten oder Admin-Credentials. Schutz erfolgt
ausschliesslich auf Gateway-Ebene (Caddy + optional Authentik).
Port ist im Compose an 127.0.0.1 gebunden, also nicht direkt von aussen
erreichbar.
