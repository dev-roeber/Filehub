# Getaggter Backup-Lauf Ergebnis 2026-05-14

## Zusammenfassung

Manueller systemd-Lauf nach Umstellung auf `--tag filehub-full` erfolgreich. Neuer Snapshot traegt den Tag direkt. Retention bleibt deaktiviert, Dry-Run zeigt nun das erwartete Bild.

## Service-Lauf

Aufruf:

```bash
sudo systemctl start filehub-backup.service
```

Status: OK (`status=0/SUCCESS`).

Laufzeit ca. 57 Sekunden (restic-Phase 0:43). Beim Index-Upload trat ein kurzer Google-Drive Rate-Limit (`rateLimitExceeded`) bzw. `HTTP 500` auf, rclone/restic haben nach 1.37 s erfolgreich retryt. Kein Abbruch.

Lokaler Backup-Pfad:

```text
/home/sebastian/Repos/Filehub/backups/20260514-205536
```

Lokale Dateien:

```text
convertx-data.tar.gz        805 B
filehub-config.tar.gz        21K
observability-data.tar.gz   7.9K
paperless-data.tar.gz        12K
paperless-postgres.sql      248K
```

## Neuer Snapshot

Snapshot-ID:

```text
bc2ef9a9
```

Tag `filehub-full` vorhanden: ja, direkt vom `restic backup`-Aufruf.

Statistik:

```text
Files: 56 new, 0 changed, 0 unmodified
Added to the repository: 401.913 KiB (81.527 KiB stored)
processed 56 files, 492.711 KiB in 0:43
```

## Snapshot-Bestand

`filehub-full`:

```text
474a5cf9  2026-05-14 18:59:31  434.413 KiB
255d9f76  2026-05-14 20:01:37  459.508 KiB
b00156dc  2026-05-14 20:16:40  472.382 KiB
bc2ef9a9  2026-05-14 20:55:46  492.711 KiB
```

`filehub-smoke-test` weiterhin getrennt:

```text
96ccefac  2026-05-14 18:49:05  47 B
```

## Retention-Dry-Run

```bash
restic forget --tag filehub-full --group-by host,tags \
  --keep-daily 7 --keep-weekly 4 --keep-monthly 6 --dry-run
```

Status: OK, kein `--prune`, keine Loeschung.

Ergebnis:

- Gruppe: 1 (`host=dev-roeber`, `tags=filehub-full`).
- Behalten: 2 (`474a5cf9`, `bc2ef9a9`).
- Wuerde entfernt: 2 (`255d9f76`, `b00156dc`).
- Smoke-Snapshot `96ccefac` bleibt unangetastet (anderes Tag-Set).

`RESTIC_APPLY_RETENTION` weiterhin nicht gesetzt.

## Timer

Aktiv (`active (waiting)`, enabled).

Naechster geplanter Lauf:

```text
Fri 2026-05-15 03:45:55 CEST
```

## Risiken

- Google-Drive Rate-Limits beim Index-Upload sind real und treten unter Last auf. rclone/restic faengt sie ueber Retries ab, ein groesserer Lauf koennte sie kumulieren.
- Retention bleibt deaktiviert. Speicher waechst weiter, solange `RESTIC_APPLY_RETENTION=true` nicht bewusst gesetzt ist.
- Bei einem realen Retention-Lauf wuerden `255d9f76` und `b00156dc` entfernt; das ist heute korrekt, weil drei Snapshots am gleichen Tag entstanden sind und Policy `keep-daily 7` nur den juengsten je Tag haelt. Bei stabiler Tagesfrequenz veraendert sich das Bild taeglich neu.

## Naechster Schritt

Den naechsten automatischen Lauf am 2026-05-15 03:45 verifizieren und pruefen, ob der neue Snapshot direkt das Tag `filehub-full` traegt. Wenn die Policy ueber mehrere Tage hinweg das erwartete Bild liefert, `RESTIC_APPLY_RETENTION=true` separat freigeben.
