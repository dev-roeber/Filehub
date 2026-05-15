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
