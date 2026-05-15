# Update-Runbook

Stand: 2026-05-15. Gilt fuer Image-Updates der Filehub-Services.

## Vorbereitung

1. **Backup sicherstellen.** Entweder manuell:

   ```bash
   just backup
   ```

   oder auf den naechsten Timer warten (siehe `docs/backup-schedule.md`).
2. **Restic-Repo pruefen:**

   ```bash
   restic check
   ```

3. Optional: Variable `REQUIRE_BACKUP_BEFORE_UPDATE=true` (noch nicht
   implementiert, empfohlen falls das Update-Skript erweitert wird). Sie
   wuerde `just update-safe` zwingen, vorher ein frisches Backup-Result
   in `backups/` zu pruefen.

## Update-Schritte

```bash
just update-safe
```

Das Rezept fuehrt nacheinander aus:

- `just backup` (Sicherung vor Aenderung).
- `docker compose pull` (neue Images ziehen).
- `docker compose up -d` (rolling restart).
- Health-Check der Container.

Anschliessend Spot-Check pro App:

- Paperless: Login, Dokument-Liste laedt.
- ConvertX: Login, Format-Matrix sichtbar.
- Stirling: Login, eine Operation testen.
- Filebrowser: Login, Verzeichnis sichtbar.
- Dozzle/Homepage: Dashboard laedt.
- Uptime-Kuma: alle Checks gruen.

## Rollback

Falls ein Service nach Update kaputt ist:

1. **Image auf konkreten Vorgaenger pinnen:**

   ```bash
   docker compose pull <service>@sha256:<alter-digest>
   docker compose up -d <service>
   ```

   Der alte Digest steht im vorherigen Run-Log oder in
   `docker image ls --digests`.
2. **Daten-Rollback** ueber Restic, siehe `docs/backup-restore.md` und
   `docs/restore-test.md`.

## Image-Pruning

`PRUNE_OLD_IMAGES` bleibt Opt-in (Default `false`). Erst aktivieren,
wenn ein Rollback-Pfad ueber Digests dokumentiert und getestet ist.
Sonst sind alte Images nach dem Update unwiederbringlich weg.

## Renovate / Dependabot

- Automerge ist deaktiviert und bleibt deaktiviert.
- Vor jedem Merge:
  1. Backup (frisch).
  2. `docker compose pull` (nur den betroffenen Service).
  3. Health-Check.
  4. Rollback-Pfad pruefen (alter Digest dokumentiert).
- Erst dann Merge, dann `just update-safe`.
