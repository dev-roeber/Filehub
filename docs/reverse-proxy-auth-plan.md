# Reverse-Proxy- und Auth-Plan (Phase 2)

Stand: 2026-05-15. **Plan, nicht umsetzen.** Filehub bleibt aktuell
localhost-only.

## Ziel

Definierte Subdomains pro App hinter einem Reverse-Proxy mit
vorgelagerter Authentifizierung. Erst aktivieren, wenn Auth-Schicht
steht und getestet ist.

## Subdomain-Schema

```text
paperless.example     -> Paperless-NGX
convertx.example      -> ConvertX
stirling.example      -> Stirling PDF
filebrowser.example   -> Filebrowser
dozzle.example        -> Dozzle
homepage.example      -> Homepage
uptime.example        -> Uptime-Kuma
```

Domain-Platzhalter `example` ersetzen, bevor Konfiguration produktiv
wird. TLS-Zertifikate via ACME (Let's Encrypt o.ae.).

## Reverse-Proxy

Caddy als Reverse-Proxy mit Authelia oder Authentik vorgeschaltet.

- **Pflicht-Auth** vor Dozzle, Filebrowser und Stirling. Diese Apps
  duerfen nie ohne Auth-Schicht erreichbar sein.
- Paperless und ConvertX haben eigene Logins, profitieren aber
  trotzdem von einer vorgelagerten SSO-/2FA-Schicht.
- Rate-Limit pro Domain.
- Access-Logs aktiv, getrennt pro vHost.

## Konflikt mit bestehendem Caddy

Auf dem Server laeuft bereits ein **anderer Caddy-Stack** auf 80/443.
Filehub darf diese Ports **nicht** doppelt belegen.

Optionen, ohne Konflikt:

- Bestehenden Caddy als zentralen Eintrittspunkt nutzen und Reverse-
  Proxy-Bloecke fuer Filehub-Subdomains dort definieren. Filehub-Caddy
  entfaellt oder bindet nur intern.
- Eigene Caddy-Instanz fuer Filehub auf abweichenden Ports (z.B. 8081/
  8443, bereits in `compose.proxy.yml` so vorgesehen), davor der
  bestehende Caddy als Frontproxy.

In beiden Faellen: **kein zweites Binding auf 80/443** durch Filehub.

## Alternative: kein Public-Exposure

Tailscale oder WireGuard, siehe `docs/remote-access.md`. Damit entfaellt
der gesamte Reverse-Proxy-Block. Empfohlener Startpunkt.

## Nicht-Aktionen

- Keine Aenderung an `compose.proxy.yml`.
- Kein Binding auf 80/443 fuer Filehub.
- Keine UFW-Oeffnung von 80/443.
- Keine produktiven Caddyfile-Eintraege.

Dieses Dokument ist reiner Plan.
