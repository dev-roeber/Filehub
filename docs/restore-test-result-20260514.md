# Restore-Test Ergebnis 2026-05-14

## Zusammenfassung

Der isolierte Restore-Test wurde erfolgreich durchgefuehrt. Der produktive Filehub-Stack wurde nicht gestoppt, nicht ueberschrieben und blieb waehrend des Tests erreichbar.

## Verwendetes Backup

```text
/home/sebastian/Repos/Filehub/backups/20260514-172748
```

Gepruefte Backup-Dateien:

- `paperless-postgres.sql`
- `paperless-data.tar.gz`
- `convertx-data.tar.gz`
- `filehub-config.tar.gz`
- `observability-data.tar.gz`

Alle Archive waren lesbar. Der PostgreSQL-Dump war vorhanden und nicht leer.

## Testpfad

```text
/home/sebastian/Repos/Filehub-restore-test
```

Der Testpfad enthaelt eigene Daten unter:

```text
/home/sebastian/Repos/Filehub-restore-test/data
```

Groesse der verbleibenden Testdaten:

```text
51M
```

## Isolation

Verwendetes Compose-Projekt:

```text
filehub_restore_test
```

Verwendetes Test-Netzwerk:

```text
filehub_restore_test_net
```

Verwendete Test-Container:

- `filehub-restore-test-paperless-db`
- `filehub-restore-test-paperless-redis`
- `filehub-restore-test-paperless-tika`
- `filehub-restore-test-paperless-gotenberg`
- `filehub-restore-test-paperless-webserver`
- `filehub-restore-test-convertx`

Verwendete Test-Ports:

- Test-Paperless: `127.0.0.1:18000`
- Test-ConvertX: `127.0.0.1:13000`

## PostgreSQL-Dump

Status: OK.

Der Dump wurde mit `psql -v ON_ERROR_STOP=1` in den isolierten Test-DB-Container importiert.

Schnellpruefung:

```text
public tables: 72
```

## Paperless-Daten

Status: OK.

`paperless-data.tar.gz` wurde in den isolierten Testpfad entpackt. Test-Paperless startete mit der wiederhergestellten Datenstruktur und antwortete per HTTP.

HTTP-Check:

```text
http://127.0.0.1:18000/ -> OK
```

## ConvertX-Daten

Status: OK.

`convertx-data.tar.gz` wurde in den isolierten Testpfad entpackt. Test-ConvertX startete mit der wiederhergestellten Datenstruktur und antwortete per HTTP.

HTTP-Check:

```text
http://127.0.0.1:13000/ -> OK
```

## Produktiver Stack

Status: OK.

Der produktive Filehub-Stack lief waehrend und nach dem Test weiter. `just health` meldete OK fuer:

- Paperless
- ConvertX
- Homepage
- Dozzle
- Uptime Kuma
- Paperless DB
- Paperless Redis

## Testcontainer Nach Abschluss

Status: gestoppt.

Nach Abschluss wurde nur das Test-Compose-Projekt gestoppt:

```text
docker compose -p filehub_restore_test ... down
```

Danach liefen keine Container mit Prefix:

```text
filehub-restore-test-
```

Das Test-Netzwerk wurde entfernt. Die Testdaten wurden bewusst behalten.

## Verbleibende Testdaten

Die Testdaten bleiben vorerst erhalten:

```text
/home/sebastian/Repos/Filehub-restore-test/data
```

Hinweis: Einige Dateien gehoeren Container-Usern, insbesondere unter `data/postgres` und `data/redis`. Das ist fuer Postgres/Redis-Testdaten erwartbar.

## Risiken Und Hinweise

- Dieser Test prueft Import, Entpackbarkeit und HTTP-Startfaehigkeit. Er ersetzt keinen fachlichen Volltest aller Paperless-Dokumente und OCR-Indizes.
- Der Test verwendete eigene temporaere Test-Secrets. Fuer einen maximal realistischen Paperless-Restore kann der originale `PAPERLESS_SECRET_KEY` relevant sein; dieser wurde hier bewusst nicht in die Doku uebernommen.
- Die Testdaten enthalten wiederhergestellte Anwendungsdaten und bleiben sensibel.
- Produktive Daten wurden nicht veraendert.

## Ergebnis

Restore-Test bestanden.
