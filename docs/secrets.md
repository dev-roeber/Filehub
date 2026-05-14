# Secrets-Inventar

Diese Datei dokumentiert, welche Secrets im Filehub-Stack existieren, wo sie liegen
und wie sie behandelt werden muessen. **Keine Werte** stehen hier.

## Ablageorte

| Datei | Mode | Inhalt | Restore-kritisch |
|---|---|---|---|
| `.env` | 600 | Compose-Umgebungsvariablen (DB-Passwoerter, JWT-Secret, Restic-Passphrase) | ja |
| `.secrets/uptime-kuma.env` | 600 | Uptime-Kuma Admin-Credentials | ja |
| `.secrets/paperless.env` | 600 | Paperless API-Token, Admin-Credentials | ja |
| `.secrets/convertx.env` | 600 | optional, Hinweise zum ConvertX-Admin | nein |
| `.secrets/filebrowser.env` | 600 | Filebrowser Admin-Passwort (lokal generiert) | ja |
| `.secrets/stirling-pdf.env` | 600 | Stirling PDF Initial-Login | ja |
| `~/.config/rclone/rclone.conf` | 600 | Google-Drive Token fuer restic via rclone | ja |

`.secrets/` selbst hat Mode `700`. Alle drei Pfade `.env`, `.secrets/`, `.venv-*/`
sind in `.gitignore` ausgeschlossen und duerfen niemals committed werden.

## Restore-kritische Secrets

Ohne diese ist ein Restore aus dem Backup unmoeglich oder unvollstaendig:

1. **`RESTIC_PASSWORD`** — Repository ist sonst kryptografisch unzugaenglich.
2. **`PAPERLESS_SECRET_KEY`** — Django-Schluessel fuer Sessions/Token, sollte
   zwischen Restore und Original identisch bleiben.
3. **`PAPERLESS_ADMIN_PASSWORD`** — initialer Admin-Login.
4. **`CONVERTX_JWT_SECRET`** — bestehende ConvertX-Sessions werden sonst ungueltig.
5. **Uptime-Kuma Admin** — Zugang zur UI; Reset siehe `docs/uptime-kuma.md`.
6. **Filebrowser Admin** — initialer Login.
7. **Stirling PDF Admin** — initialer Login.

## Passwortmanager-Pflicht

In den Passwortmanager (z. B. Bitwarden, 1Password) gehoeren:

- Restic-Passphrase
- Paperless Admin
- Uptime-Kuma Admin
- ConvertX Admin (UI-Login, nicht JWT-Secret)
- Filebrowser Admin
- Stirling PDF Admin
- Google Drive App-Credential bzw. rclone-Token (falls extern verwaltet)

Lokal in `.secrets/` reichen Backups nicht, weil eine zerstoerte Festplatte ohne
externen Speicher alles mit verliert.

## Pruefen

```bash
just secrets-audit
```

Das Script prueft Existenz, Datei-Modes und ob die wichtigsten Variablen in `.env`
gesetzt sind. Es gibt keine Werte aus.

## Reset

- Uptime Kuma: `docs/uptime-kuma.md` Abschnitt "Passwort vergessen".
- Paperless: `docker exec filehub-paperless-webserver python3 manage.py changepassword sebastian`.
- ConvertX: UI-Login -> Profil -> Passwort.
- Filebrowser: `docs/filebrowser.md`.
- Stirling PDF: `docs/stirling-pdf.md`.

## Backup-Relevanz

`scripts/backup.sh` sichert standardmaessig **NICHT** `.env` oder `.secrets/`.
Das ist gewollt. Wer ein Disaster-Recovery-Backup mit Secrets braucht, setzt
`INCLUDE_ENV_IN_BACKUP=true` bewusst — und nur fuer einen kontrollierten Lauf in
eine verschluesselte Senke. Standardweg bleibt: Secrets liegen im
Passwortmanager und werden bei Bedarf manuell neu deployed.
