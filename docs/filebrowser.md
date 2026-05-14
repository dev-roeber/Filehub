# Filebrowser

Filebrowser laeuft auf `127.0.0.1:3003`. Lokaler Web-Dateimanager fuer
Uploads in Paperless-Consume und PDF-Arbeitsordner.

## Zugriff

Per SSH-Tunnel oder lokal:

```text
http://127.0.0.1:3003
```

Login mit Username/Passwort aus `.secrets/filebrowser.env` (Mode 600,
gitignored). Passwort sollte sofort in den Passwortmanager uebernommen
werden, weil `.secrets/` nicht extern gesichert wird.

## Mounts

| Container-Pfad | Host-Pfad | Zweck |
|---|---|---|
| `/srv` | `data/filebrowser/root` | freier Arbeitsbereich |
| `/srv/paperless-consume` | `data/paperless/consume` | Upload in Paperless |
| `/srv/pdf-work` | `data/stirling/work` | Austausch mit Stirling PDF |
| `/database` | `data/filebrowser/database` | Filebrowser-DB |
| `/config` | `config/filebrowser` | Konfiguration |

**Wichtig:** Es gibt keinen Mount auf die Repo-Wurzel und keinen Zugriff auf
`.env` oder `.secrets/`. Filebrowser sieht nur seinen Sandkasten.

## Passwort zuruecksetzen

```bash
docker stop filehub-filebrowser
PW="$(openssl rand -base64 24 | tr -d '/+=' | cut -c1-32)"
# PW lokal in den Passwortmanager kopieren, NICHT in Logs ablegen.
docker run --rm -v "$(pwd)/data/filebrowser/database:/database" \
  --entrypoint filebrowser filebrowser/filebrowser:s6 \
  users update admin --password "$PW" -d /database/filebrowser.db
sudo chown -R 1000:1000 data/filebrowser
docker start filehub-filebrowser
# Anschliessend .secrets/filebrowser.env aktualisieren.
```

## Backup

`scripts/backup.sh` sichert `data/filebrowser` und `config/filebrowser` als
`filebrowser-data.tar.gz`. Die Filebrowser-DB enthaelt Benutzer und
Konfiguration; keine Dokumente selbst, weil die unter `/srv` mit Paperless
und Stirling geteilt werden.

## Sicherheit

- Kein Public Binding. Filebrowser kann Dateien ueberschreiben und loeschen.
- Nicht ohne zusaetzliche Auth oeffentlich exponieren.
- Im Container hat Filebrowser nur Zugriff auf die explizit gemounteten Pfade.
