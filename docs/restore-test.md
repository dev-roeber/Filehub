# Restore-Test

Dieses Dokument beschreibt einen kontrollierten Restore-Test. Der aktive Filehub-Stack unter `/home/sebastian/Repos/Filehub` darf dabei nicht gestoppt, ueberschrieben oder veraendert werden.

## Ziel

Der Restore-Test soll pruefen:

- PostgreSQL-Dump ist importierbar.
- Paperless-Datenarchiv ist entpackbar.
- ConvertX-Datenarchiv ist entpackbar.
- Test-Container starten isoliert.
- Test-Paperless ist per HTTP erreichbar.

## Grundregeln

- Separater Testpfad:

  ```text
  /home/sebastian/Repos/Filehub-restore-test
  ```

- Eigenes Compose-Projekt: `filehub_restore_test`
- Eigene Test-Ports, nur auf `127.0.0.1`
- Eigene Datenpfade im Testverzeichnis
- Kein `down -v` und kein Loeschen produktiver Daten

## Test-Ports

| Dienst | Produktiv | Restore-Test |
|---|---:|---:|
| Paperless | `8000` | `18000` |
| ConvertX | `3000` | `13000` |

Homepage, Dozzle und Uptime Kuma sind fuer den Restore-Test nicht noetig.

## Backup Auswaehlen

```bash
cd /home/sebastian/Repos/Filehub
ls -la backups
```

Beispiel-Backup:

```text
backups/20260514-172748
```

Erwartete Dateien:

```text
paperless-postgres.sql
paperless-data.tar.gz
convertx-data.tar.gz
filehub-config.tar.gz
```

## Testpfad Vorbereiten

```bash
mkdir -p /home/sebastian/Repos/Filehub-restore-test
cd /home/sebastian/Repos/Filehub-restore-test
```

Projektdateien ohne produktive Secrets, Daten und Backups kopieren:

```bash
rsync -a \
  --exclude '.git' \
  --exclude '.env' \
  --exclude 'data' \
  --exclude 'backups' \
  /home/sebastian/Repos/Filehub/ \
  /home/sebastian/Repos/Filehub-restore-test/
```

Eigene Test-`.env` erstellen:

```bash
cp .env.example .env
chmod 600 .env
```

Mindestens anpassen:

```env
PAPERLESS_PORT=18000
CONVERTX_PORT=13000
PAPERLESS_SECRET_KEY=restore-test-random-value
PAPERLESS_ADMIN_USER=restoretest
PAPERLESS_ADMIN_PASSWORD=restore-test-random-value
PAPERLESS_DBPASS=restore-test-random-value
POSTGRES_PASSWORD=restore-test-random-value
CONVERTX_JWT_SECRET=restore-test-random-value
RESTIC_REPOSITORY=
RESTIC_PASSWORD=
```

Fuer einen echten Test sollten die `restore-test-random-value` Werte durch temporaere Zufallswerte ersetzt werden. Diese Test-`.env` nicht committen.

## Daten Entpacken

```bash
mkdir -p data
tar -xzf /home/sebastian/Repos/Filehub/backups/20260514-172748/paperless-data.tar.gz
tar -xzf /home/sebastian/Repos/Filehub/backups/20260514-172748/convertx-data.tar.gz
```

Pruefen:

```bash
test -d data/paperless
test -d data/convertx
test -s /home/sebastian/Repos/Filehub/backups/20260514-172748/paperless-postgres.sql
```

## Compose-Isolation Erzwingen

Die produktiven Compose-Dateien enthalten feste `container_name` Werte und ein fest benanntes Docker-Netzwerk. Deshalb reicht `-p filehub_restore_test` allein nicht aus. Lege im Testpfad eine Override-Datei an:

```bash
cat > compose.restore-test.yml <<'YAML'
name: filehub_restore_test

networks:
  filehub_net:
    name: filehub_restore_test_net

services:
  paperless-db:
    container_name: filehub-restore-test-paperless-db
    volumes:
      - ./data/postgres:/var/lib/postgresql/data

  paperless-redis:
    container_name: filehub-restore-test-paperless-redis
    volumes:
      - ./data/redis:/data

  paperless-tika:
    container_name: filehub-restore-test-paperless-tika

  paperless-gotenberg:
    container_name: filehub-restore-test-paperless-gotenberg

  paperless-webserver:
    container_name: filehub-restore-test-paperless-webserver
    ports:
      - "127.0.0.1:${PAPERLESS_PORT:-18000}:8000"
    volumes:
      - ./data/paperless/data:/usr/src/paperless/data
      - ./data/paperless/media:/usr/src/paperless/media
      - ./data/paperless/export:/usr/src/paperless/export
      - ./data/paperless/consume:/usr/src/paperless/consume

  convertx:
    container_name: filehub-restore-test-convertx
    ports:
      - "127.0.0.1:${CONVERTX_PORT:-13000}:3000"
    volumes:
      - ./data/convertx:/app/data
YAML
```

Alle folgenden Compose-Befehle nutzen diese Variable:

```bash
RESTORE_TEST_COMPOSE="docker compose -p filehub_restore_test -f compose.yml -f compose.paperless.yml -f compose.convertx.yml -f compose.restore-test.yml"
```

## Isoliertes Compose-Projekt Starten

```bash
docker compose \
  -p filehub_restore_test \
  -f compose.yml \
  -f compose.paperless.yml \
  -f compose.convertx.yml \
  -f compose.restore-test.yml \
  up -d paperless-db paperless-redis paperless-tika paperless-gotenberg
```

Status pruefen:

```bash
docker compose \
  -p filehub_restore_test \
  -f compose.yml \
  -f compose.paperless.yml \
  -f compose.convertx.yml \
  -f compose.restore-test.yml \
  ps
```

## PostgreSQL-Dump Importieren

Nur in den Test-DB-Container importieren:

```bash
set -a
source .env
set +a

docker compose \
  -p filehub_restore_test \
  -f compose.yml \
  -f compose.paperless.yml \
  -f compose.convertx.yml \
  -f compose.restore-test.yml \
  exec -T paperless-db \
  sh -lc 'psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB"' \
  < /home/sebastian/Repos/Filehub/backups/20260514-172748/paperless-postgres.sql
```

Falls die Test-Datenbank bereits Objekte enthaelt, den Testpfad neu aufsetzen. Niemals produktive Volumes loeschen.

## Test-Webdienste Starten

```bash
docker compose \
  -p filehub_restore_test \
  -f compose.yml \
  -f compose.paperless.yml \
  -f compose.convertx.yml \
  -f compose.restore-test.yml \
  up -d paperless-webserver convertx
```

## HTTP-Checks

```bash
curl -fsS http://127.0.0.1:18000/ >/dev/null
curl -fsS http://127.0.0.1:13000/ >/dev/null
```

## Test Beenden

Nur den Test-Stack stoppen:

```bash
docker compose \
  -p filehub_restore_test \
  -f compose.yml \
  -f compose.paperless.yml \
  -f compose.convertx.yml \
  -f compose.restore-test.yml \
  down
```

Testdaten erst nach dokumentiertem Ergebnis archivieren oder bewusst entfernen. Produktive Daten bleiben unangetastet.

## Erfolgskriterien

- Test-DB-Import ohne Fehler.
- Paperless-Datenarchiv entpackt.
- ConvertX-Datenarchiv entpackt.
- Test-Container laufen unter eigenem Compose-Projekt.
- Test-Containernamen beginnen mit `filehub-restore-test-`.
- Test-Netzwerk heisst `filehub_restore_test_net`.
- Test-Paperless antwortet auf `127.0.0.1:18000`.
- Produktiver Filehub-Stack lief waehrenddessen weiter.
