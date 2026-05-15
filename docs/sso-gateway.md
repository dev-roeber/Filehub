# Authentik-SSO-Gateway (Phase 1)

Stand: 2026-05-15. Filehub bleibt localhost-only. Phase 1 setzt
Authentik als Identity-Provider und einen zweiten Caddy als
Forward-Auth-Gateway vor die Filehub-Homepage. HTTP only, kein TLS.

## Zielbild

```text
User --> http://127.0.0.1:3080/ (Filehub Gateway, Caddy)
            |
            +-- forward_auth --> http://filehub-authentik-server:9000/outpost.goauthentik.io/auth/caddy
            |        (Login-Redirect auf Authentik wenn unauthentifiziert)
            v
        Homepage (Filehub Dashboard) --> Links auf Paperless, ConvertX, ...
```

Der Gateway-Caddy delegiert die Auth-Entscheidung pro Request an den
Authentik-Embedded-Outpost. Bei fehlender Session schickt Authentik
einen Login-Redirect zurueck. Nach erfolgreichem Login reicht der
Outpost Header-Informationen (`X-Authentik-Username`,
`X-Authentik-Email`, weitere `X-Authentik-*`) an den Gateway weiter,
der sie zu den Upstream-Backends durchschleift.

## Was Gateway-SSO ist

- Eine zentrale Anmeldung an Authentik schaltet **jeden** Pfad hinter
  dem Gateway frei.
- Backends sehen optional die Authentik-Header
  (`X-Authentik-Username`, `X-Authentik-Email`, ...). Damit lassen
  sich Audit-Logs und einfache Auto-Mappings bauen.
- Kein Backend muss sein eigenes Login-System abloesen. Die Vorbarriere
  ist additiv.

## Was Gateway-SSO NICHT ist

- Kein echtes OIDC-App-SSO. Paperless, ConvertX, Filebrowser und
  Stirling halten ihre eigenen Logins. Nutzer melden sich also
  weiterhin pro App separat an.
- Kein Token-Austausch mit den Apps. Die App-Sessions sind unabhaengig
  von der Authentik-Session.
- Phase 2 ist echtes OIDC pro App (App akzeptiert Authentik als
  Identity-Provider, kein App-eigenes User-Management mehr).

## Ports und URLs

Alles auf `127.0.0.1`:

| Komponente | Port | URL |
|---|---|---|
| Authentik UI | 9000 | `http://127.0.0.1:9000` |
| Filehub-Gateway (Caddy) | 3080 | `http://127.0.0.1:3080` |
| Paperless (direkt) | 8000 | `http://127.0.0.1:8000` |
| ConvertX (direkt) | 3000 | `http://127.0.0.1:3000` |
| Homepage (direkt) | 3001 | `http://127.0.0.1:3001` |
| Uptime-Kuma (direkt) | 3002 | `http://127.0.0.1:3002` |
| Filebrowser (direkt) | 3003 | `http://127.0.0.1:3003` |
| Stirling PDF (direkt) | 3004 | `http://127.0.0.1:3004` |
| Dozzle (direkt) | 9999 | `http://127.0.0.1:9999` |

Die direkten App-Ports bleiben fuer Admin- und Troubleshooting-
Zugriff bestehen. UFW erlaubt weiterhin nur 22/tcp.

## Phase-1-Beschraenkungen

- Nur die **Homepage** ist hinter dem Gateway. Links auf der Homepage
  zeigen weiterhin auf die direkten localhost-Ports der Apps.
- Subpath-Routing (z.B. `/paperless/`) wuerde absolute Asset-Pfade
  der Apps brechen (Paperless, ConvertX). Deshalb wird in Phase 2
  pro App eine eigene Subdomain genutzt
  (`paperless.filehub.local`, `convertx.filehub.local`, ...) via
  `/etc/hosts` oder echter DNS.
- Backend-Ports muessen weiterhin nur lokal binden. UFW darf 80/443
  nicht oeffnen. Der externe Caddy auf 80/443 (lh2gpx) bleibt
  unangetastet.
- Das Gateway laeuft ausschliesslich HTTP. Kein TLS in Phase 1, weil
  alles ueber Loopback und SSH-Tunnel angesprochen wird.

## Erst-Setup-Reihenfolge

1. `.secrets/authentik.env` mit starken Werten anlegen, Mode `600`.
   Siehe `docs/secrets.md` fuer die Liste der Variablen. Keine Werte
   in andere Dateien kopieren, kein Commit.
2. `just up-auth` startet `filehub-authentik-db`,
   `filehub-authentik-redis`, `filehub-authentik-server`,
   `filehub-authentik-worker` und `filehub-gateway`.
3. Browser oeffnen: `http://127.0.0.1:9000/if/flow/initial-setup/`.
   Falls der Bootstrap-User noch nicht via Environment angelegt
   wurde, hier den Admin-User finalisieren.
4. Bei aktivem `AUTHENTIK_BOOTSTRAP_PASSWORD` ist der Initial-Admin
   `akadmin`. Anmeldung mit dem in `.secrets/authentik.env`
   hinterlegten Passwort. Der Wert wird **nie** in Logs, Doku oder
   Commits ausgegeben.
5. In Authentik einmal pruefen: `Settings -> Outposts`. Der
   "Embedded Outpost" soll automatisch existieren und mit der
   Default-Provider-Konfiguration verbunden sein.
6. Test: `http://127.0.0.1:3080/` aufrufen. Es soll ein Redirect auf
   die Authentik-Login-Seite erfolgen. Nach erfolgreichem Login
   wird die Filehub-Homepage angezeigt.

## Phase-2-Plan

- Subdomains pro App (`paperless.filehub.local`, ...) via
  `/etc/hosts` oder echter DNS.
- TLS via interner CA (Caddy `tls internal`) oder Tailscale-TLS.
- Echtes OIDC-App-SSO pro App (Paperless, ConvertX, Filebrowser,
  Stirling, Dozzle). Backends akzeptieren Authentik als IdP.
- Caddy wird alleiniger Eingang. App-Ports binden nur noch im
  Compose-Netz, kein direktes Host-Binding mehr.
- UFW oeffnet 80/443 erst, wenn Auth-Schicht und TLS produktiv und
  getestet sind.

## Sicherheits-Hinweise

- Caddy reicht per Default keine Header durch. Im Caddyfile ist
  `copy_headers` auf eine Whitelist beschraenkt:
  `X-Authentik-Username`, `X-Authentik-Email`, `X-Authentik-Groups`,
  `X-Authentik-Uid` (und weitere `X-Authentik-*` nach Bedarf).
- Generische User-Header wie `Remote-User`, `Remote-Email`,
  `X-Forwarded-User` werden **nicht** ungefiltert an Backends
  weitergegeben. Sonst koennten Clients eigene Werte einschleusen
  oder zwei Auth-Quellen kollidieren.
- `trusted_proxies private_ranges` im Caddyfile sorgt dafuer, dass
  `forward_auth`-Antworten nur vom lokalen Outpost akzeptiert werden.
- Authentik-Postgres (`data/authentik/db`) und Authentik-Media
  (`data/authentik/media`) werden ab Phase 2 in den restic-Backup-
  Lauf aufgenommen. Siehe `docs/backup-schedule.md`.
- Authentik-UI niemals oeffentlich exponieren. Port 9000 bleibt
  localhost-only.

## Operative Befehle

| Kommando | Wirkung |
|---|---|
| `just up-auth` | Startet Authentik-Stack und Gateway-Caddy |
| `just down-auth` | Stoppt Authentik-Stack und Gateway-Caddy |
| `just restart-auth` | Neustart des Authentik-Stacks |
| `just logs-auth` | Logs von Authentik-Server/-Worker/-DB/-Redis |
| `just auth-status` | Healthcheck Authentik (HTTP 9000) |
| `just gateway-status` | Healthcheck Gateway (HTTP 3080, Auth-Redirect erwartet) |

## Troubleshooting

- Redirect-Loop auf `/outpost.goauthentik.io/...`: Outpost im
  Authentik-UI pruefen, Provider-Auswahl gegen den richtigen
  Embedded-Outpost setzen.
- 502 vom Gateway: `just logs-auth` und Status der
  `filehub-authentik-server`-Container pruefen. Authentik braucht
  einige Sekunden Startzeit nach dem DB-Migrationslauf.
- Header kommen am Backend nicht an: `copy_headers`-Whitelist im
  Gateway-Caddyfile pruefen, Backend-Logs gegen tatsaechliche
  Request-Header abgleichen.
