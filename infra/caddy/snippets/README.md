# Caddy Snippets

Reverse-Proxy-Snippets fuer die einzelnen Filehub-Apps. Die eigentlichen
Snippet-Dateien liegen **nicht** in diesem Verzeichnis, sondern pro App unter:

```
apps/<id>/caddy.disabled            # Reverse-Proxy ohne Auth
apps/<id>/caddy.authentik.disabled  # Reverse-Proxy mit Authentik forward_auth
```

## Standard: deaktiviert

Beide Varianten enden auf `.disabled` und werden vom Gateway-Caddyfile
(`config/caddy/filehub-gateway.Caddyfile`) **nicht** automatisch geladen.
Filehub liefert die Snippets aus, ohne sie zu aktivieren - so bleibt der
Default-Stack ohne SSO erreichbar.

## Aktivierung

1. Gewuenschte Variante per Umbenennung scharfschalten:
   ```sh
   # Ohne Auth:
   mv apps/paperless/caddy.disabled apps/paperless/caddy

   # Mit Authentik forward_auth:
   mv apps/paperless/caddy.authentik.disabled apps/paperless/caddy.authentik
   ```
2. Im Gateway-Caddyfile importieren, z. B.:
   ```caddyfile
   import apps/paperless/caddy
   ```
   bzw. fuer die Authentik-Variante:
   ```caddyfile
   import apps/paperless/caddy.authentik
   ```
3. Caddy reloaden (`docker compose exec filehub-caddy caddy reload ...`
   oder Container neu starten).

Es darf jeweils nur **eine** Variante pro App aktiv sein.

## Helper: `scripts/caddy-enable.sh` / `scripts/caddy-disable.sh`

Statt manuell zu kopieren oder umzubenennen, gibt es einen Helper, der das
gewuenschte Snippet nach `infra/caddy/snippets/enabled/<app>.caddy`
**kopiert** (nicht symlinkt, damit der Caddy-Volume-Mount stabil bleibt):

```sh
# Plain (ohne Auth, Default):
scripts/caddy-enable.sh paperless
# oder:           scripts/caddy-enable.sh paperless plain

# Mit Authentik forward_auth:
scripts/caddy-enable.sh paperless authentik

# Ueberschreiben (Default: exit 4 wenn Ziel schon existiert):
scripts/caddy-enable.sh paperless plain --force

# Wieder deaktivieren (idempotent):
scripts/caddy-disable.sh paperless
```

Exit-Codes von `caddy-enable.sh`: `2` = App unbekannt, `3` = Snippet fehlt,
`4` = Ziel existiert (nutze `--force`). Wenn der Container `filehub-gateway`
laeuft, wird zusaetzlich `caddy validate` ausgefuehrt; ein Reload wird
**nicht** automatisch ausgeloest.

Justfile-Targets: `just caddy-enable <app>`, `just caddy-enable-auth <app>`,
`just caddy-disable <app>`, `just caddy-list`.

## Path-Strip-Konvention

Jede App ist ueber ein Pfad-Prefix erreichbar (`/paperless/*`,
`/convertx/*`, ...). Das Snippet stripped den Prefix vor dem
`reverse_proxy`-Upstream.

**Ausnahme Homepage:** Homepage laeuft als Root (`handle /*`) ohne
`strip_prefix`, weil gethomepage Assets unter `/` erwartet. Zusaetzlich
setzt das Snippet `header_up Host localhost`, damit die
`HOMEPAGE_ALLOWED_HOSTS`-Validation greift.

## Authentik

Die `caddy.authentik.disabled`-Variante setzt einen funktionierenden
Authentik-Outpost (`filehub-authentik-server:9000`) sowie
`AUTHENTIK_ENABLED=true` voraus. Details, Outpost-Setup und
Default-Off-Begruendung siehe [docs/AUTHENTIK_OPTIONAL.md](../../../docs/AUTHENTIK_OPTIONAL.md).
