# Roadmap

Stand: 2026-05-15. Filehub laeuft localhost-only. Aktuell 11 Container
gesund auf `127.0.0.1`, kein oeffentliches Binding.

## Phase 1 (abgeschlossen)

- Localhost-only Stack betreiben.
- Paperless, ConvertX, Homepage, Dozzle und Uptime Kuma initial
  einrichten.
- Uptime-Kuma-Checks anlegen.
- Lokales Backup ausfuehren und Restore-Ablauf dokumentiert testen.

## Phase 2 (abgeschlossen)

- restic/rclone Remote-Backup aktiviert.
- `filehub-backup.timer` taeglich 03:30 +/- 30min, mit flock-Schutz.
- ntfy-Notifications eingerichtet, Backup-Fehler-Alerts ueber
  `filehub-backup-alert@.service` (OnFailure).
- `backup-report.sh` und `storage-check.sh` ueber ntfy.
- restic-Retention als Dry-Run dokumentiert; Aktivierung bleibt
  bewusst zurueckgestellt (siehe [retention-policy.md](retention-policy.md)).
- Lokale Backup-Retention vorbereitet
  (`scripts/local-backup-retention.sh`, Doppel-Opt-in).
- Storage-Monitoring aktiv (`scripts/storage-check.sh`).
- Stirling Resource-Limits gesetzt (`cpus: 2.0`, `mem_limit: 4g`,
  `pids_limit: 512` in `compose.extensions.yml`).

## Phase 3 (offen, unveraendert)

- Reverse Proxy nur bei Bedarf aktivieren.
- Domain, HTTPS, Authentifizierung und Firewall-Regeln bewusst planen.
- Optional VPN statt oeffentlichem Reverse Proxy pruefen.
- Automatisierung fuer Backups und Healthchecks weiter ausbauen, ohne
  die zurueckgestellten Punkte vorzuziehen.

## Bewusst zurueckgestellt

Die folgenden drei Punkte sind technisch machbar, aber bewusst nicht
aktiv. Sie bringen zusaetzliche Komplexitaet und Risiko und werden erst
nach einer Stabilisierungsphase aktiviert, in der Backups,
Notifications und Storage-Monitoring nachweisbar mehrere Wochen ruhig
laufen.

### 9. Monatlicher Restore-Smoke-Timer

- Kein systemd-Timer.
- Wird manuell ausgeloest, siehe `docs/restore-test.md`.
- Grund: ein automatischer monatlicher Restore haelt waehrend des Laufs
  einen Lock auf das restic-Repo, kollidiert potentiell mit Backups und
  belegt Disk fuer den Restore-Pfad. Solange die ntfy-Kette frisch ist,
  ueberwiegt der Wert eines manuellen, beobachteten Laufs.

### 14. Periodischer ConvertX-E2E-Timer

- Kein systemd-Timer.
- Wird manuell via `scripts/convertx-e2e-run.sh` ausgeloest.
- Grund: ConvertX-E2E erzeugt Last und Test-Dateien, und die
  Fehlerklassen aus den letzten Laeufen sind noch in Klaerung. Erst
  wenn der E2E-Pfad stabil gruen laeuft, kommt ein Timer in Frage.

### 17. Image-Pinning auf Digests

- Aktuell laufen die Container auf `latest`-Tags.
- Renovate bzw. Dependabot werden nur vorbereitet, aber noch nicht
  aktiv geschaltet.
- Grund: Pinning auf Digests bringt eine kontinuierliche Pflegelast
  (Pull Requests, Tests, Restart-Fenster). Solange Phase 2 frisch ist
  und nicht jeder Update-Pfad auditiert wurde, ist ein bewusster
  manueller Update-Rhythmus risikoaermer.

## Nicht-Ziele

- Keine oeffentliche Standardbereitstellung.
- Keine Secrets im Git.
- Kein automatisches Loeschen produktiver Daten.
- Keine automatische Aktivierung der drei oben genannten Punkte ohne
  separate Entscheidung und Doku-Update.
