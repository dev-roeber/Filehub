# Authentik (optional)

Authentik ist ein **optionales** Infrastrukturmodul. Default: **deaktiviert**.
Apps laufen ohne Authentik vollstaendig standalone.

## Aktivierung (nur bei Bedarf)

1. `.secrets/authentik.env` mit Bootstrap-Secrets anlegen (Mode 600):
   ```
   AUTHENTIK_SECRET_KEY=<set-local-secret>
   AUTHENTIK_BOOTSTRAP_PASSWORD=<set-local-secret>
   AUTHENTIK_BOOTSTRAP_TOKEN=<set-local-secret>
   POSTGRES_PASSWORD=<set-local-secret>
   AUTHENTIK_POSTGRESQL__PASSWORD=<set-local-secret>
   ```
2. In Root-`.env`: `AUTHENTIK_ENABLED=true`.
3. Start: `just auth-up` (entspricht `docker compose --env-file .env -f infra/authentik/compose.yml up -d`).
4. Initial-UI-Bootstrap: http://127.0.0.1:9000/if/flow/initial-setup/
   - Empfohlener Admin: `${FILEHUB_ADMIN_USER}` aus Root-`.env`.

## Deaktivierung

```
just auth-down
```

Daten unter `data/authentik/{postgres,redis,media,custom-templates,certs}` bleiben erhalten - Restart laedt den vorherigen Zustand.

## Backup

Authentik-Daten werden im Backup-Paket gesichert **wenn aktiv** oder **per explizitem Befehl**:
- `scripts/backup.sh` erkennt laufende Authentik-Container und fuehrt `pg_dump` + `BGSAVE` + Volume-tar aus.
- `just backup-app authentik` erzwingt die Sicherung unabhaengig vom Aktivierungsstatus.

Details: `docs/BACKUP.md` und `docs/AUTHENTIK_OPTIONAL.md`.

## Netzwerke

- `authentik_net` (intern, nur Authentik-Services)
- `filehub_net` (external) - nur `authentik-server` ist daran angebunden, damit das Filehub-Gateway den Outpost erreichen kann.

## Kein Pflicht-Dependency

- Apps starten/stoppen/sichern unabhaengig von Authentik.
- Caddy-Snippets fuer Authentik-geschuetzte Varianten liegen als `caddy.authentik.disabled` pro App; nur bei bewusster Umbenennung aktiv.
