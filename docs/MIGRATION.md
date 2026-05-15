# Migration zur modularen App-Plattform

Diese Doku beschreibt den nicht-destruktiven Umbau von Filehub auf die
modulare Struktur `apps/<id>/` und `infra/<id>/`. **Es wurden keine
bestehenden Container, Volumes oder Daten gelöscht.**

## Was sich geaendert hat

| Bereich | Vorher | Nachher |
|---|---|---|
| App-Compose | `compose.<app>.yml` im Repo-Root | zusaetzlich `apps/<id>/compose.yml` (eigenstaendig) |
| Authentik | `compose.auth.yml` (mit Gateway) | zusaetzlich `infra/authentik/compose.yml` (ohne Gateway) |
| Backup | Hardcoded tar-Aufrufe in `scripts/backup.sh` | zusaetzlich `apps/<id>/backup.include` + Modus `FILEHUB_BACKUP_ONLY_APP` |
| Just | `up-core`, `up-extensions`, `up-auth`, ... | zusaetzlich `app-up <app>`, `apps-status`, `auth-up`, `gateway-up`, ... |
| Caddy | `config/caddy/filehub-gateway.Caddyfile` | zusaetzlich `apps/<id>/caddy.disabled` + `caddy.authentik.disabled` |

**Beide Welten laufen parallel.** Die alten Compose-Dateien und Just-Targets
bleiben funktional - es ist kein Reboot, kein `down/up` und keine
Datenmigration noetig.

## Was NICHT angefasst wurde

- Bestehende Container-Namen (`filehub-paperless-webserver`, `filehub-convertx`, ...).
- Bestehende Volumes (`./data/...`).
- Public/Local-Bindings (alle weiterhin `127.0.0.1`).
- Bestehende Daten in `data/`.
- Restic-Repository und Snapshot-Historie.

## Kompatibilitaet

- `docker compose -f compose.paperless.yml ...` funktioniert unveraendert.
- `docker compose -f apps/paperless/compose.yml --env-file .env ...` ist der neue Weg.
- Beide referenzieren **denselben** Container per `container_name`,
  also nicht zwei Instanzen parallel starten.

## Migration eines bestehenden Stacks

Kein erzwungener Schritt. Wenn du auf die neuen Kommandos umsteigen willst:

1. Pruefe, dass `apps/<id>/compose.yml` validiert:
   ```
   docker compose --env-file .env -f apps/<id>/compose.yml config
   ```
2. Stoppe die App ueber den alten Weg, starte sie ueber den neuen Weg:
   ```
   just down-extensions     # alt
   just app-up filebrowser  # neu
   ```
3. Volumes und Daten sind unveraendert - dieselben Bind-Mounts greifen.

## Authentik-Modul-Umstieg

`compose.auth.yml` (mit Gateway) bleibt fuer den Phase-1-Bootstrap aktiv.
`infra/authentik/compose.yml` enthaelt nur die 4 Authentik-Services ohne Gateway.

Solange `compose.auth.yml` aktiv ist, **nicht** parallel `infra/authentik/compose.yml`
starten - sie wuerden um die gleichen Container-Namen konkurrieren.

Empfohlener Umstieg (optional, nur wenn der Caddy-Gateway separat verwaltet
werden soll):

1. `just down-auth` (alter Pfad stoppt Authentik + Gateway).
2. `just gateway-up` (Gateway separat starten ueber compose.auth.yml -- vorbereitet).
3. `just auth-up` (Authentik ueber infra/authentik/compose.yml, AUTHENTIK_ENABLED=true noetig).

## Rollback

```
git revert <commit-sha>  # einzelne Commits ruecknehmen
```

Alle 8 Refactoring-Commits sind isoliert und einzeln revertierbar.
Da keine Daten geloescht wurden, bleibt der Betrieb in jeder Variante stabil.
