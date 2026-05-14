# Lokale Backups: Aufbewahrung und Cleanup

Lokale Backups unter `backups/<timestamp>/` werden derzeit nicht automatisch geloescht. Das ist Absicht: solange das Cloud-Backup nicht ueber laengere Zeit zuverlaessig laeuft und der Cloud-Restore-Smoke regelmaessig gruen ist, bleiben die lokalen Pakete als zweite Linie liegen.

## Strategie

1. Cloud-Backups via `scripts/backup.sh` + systemd-Timer laufen taeglich.
2. Cloud-Restore-Smoke wird mindestens monatlich gepruft (siehe `docs/restore-test.md`).
3. Solange Schritt 2 noch jung ist (weniger als 30 Tage stabil), bleiben alle lokalen Backups erhalten.
4. Danach kann eine separate, bewusste lokale Retention definiert werden, z. B. `keep last 7 lokale Backups`.

## Nichts automatisch loeschen

Es gibt aktuell keinen Cron-, systemd- oder Skript-Pfad, der lokale Backups loescht. Eine lokale Retention wird erst eingefuehrt, wenn:

- Die Cloud-Backups stabil laufen.
- Der Cloud-Restore-Smoke mehrfach erfolgreich war.
- Eine Policy explizit beschlossen und in dieser Doku festgehalten ist.

## Manuelles Aufraeumen (vorlaeufig nicht empfohlen)

Wenn lokal Speicher knapp wird, manuell pruefen:

```bash
du -sh /home/sebastian/Repos/Filehub/backups/*
df -h
```

Vor jedem Loeschen pruefen, ob der entsprechende Inhalt mindestens als restic-Snapshot vorliegt:

```bash
set -a && . /home/sebastian/Repos/Filehub/.env && set +a
restic snapshots --tag filehub-full --compact
```

Ein Loeschen ist nur dann vertretbar, wenn die Inhalte nachweisbar als Snapshot existieren UND der letzte Cloud-Restore-Smoke gruen war. Selbst dann zuerst per `mv` in einen separaten Quarantaene-Pfad verschieben und erst nach mehreren Tagen entfernen.

## Risiken

- Lokale Backups enthalten `paperless-postgres.sql` und tar-Archive mit Anwendungsdaten. Sie sind sensibel und sollten nicht unbedacht kopiert oder geteilt werden.
- Ohne Cleanup waechst der lokale Speicherbedarf monoton. Bei kleinem Datenvolumen ist das vorerst unkritisch, sollte aber beobachtet werden.
- Eine spaetere automatische Retention darf nie ohne dokumentierten Dry-Run und Opt-in eingefuehrt werden.

## Naechster Schritt

Nach 30 Tagen stabilen Cloud-Backups eine konkrete lokale Retention-Policy formulieren, z. B.:

- Behalte die letzten 7 lokalen Backup-Verzeichnisse.
- Loesche aeltere nur, wenn ein erfolgreicher Cloud-Restore-Smoke innerhalb der letzten 30 Tage dokumentiert ist.

Diese Policy bleibt manuell aufrufbar (kein Default-Cron), bis sie sich bewaehrt hat.
