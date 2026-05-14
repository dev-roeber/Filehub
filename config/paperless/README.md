# Paperless-Konfiguration

Paperless wird über `compose.paperless.yml` und `.env` konfiguriert.

Persistente Pfade:

- `data/paperless/consume`
- `data/paperless/data`
- `data/paperless/media`
- `data/paperless/export`
- `data/postgres`
- `data/redis`

Die Weboberfläche bindet initial nur an `127.0.0.1:${PAPERLESS_PORT:-8000}`.
