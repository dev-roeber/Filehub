# Remote-Zugriff

Stand: 2026-05-15. Filehub ist localhost-only. UFW erlaubt nur 22/tcp.

## Aktueller Stand

Remote-Zugriff erfolgt ausschliesslich ueber SSH-Local-Forward:

```bash
ssh -L 3000:127.0.0.1:3000 user@server
```

Pro App ein Forward. Siehe `docs/ssh-tunnel.md`.

## Optionen im Vergleich

| Option | Aufwand | Angriffsflaeche | Public-Exposure | Auth |
|---|---|---|---|---|
| SSH-Tunnel | sehr gering | nur SSH (22/tcp) | nein | SSH-Key |
| Tailscale | gering | nur Tailscale-Daemon | nein (Mesh) | Identity-Provider |
| WireGuard (self-hosted) | mittel | UDP-Port offen | ja (1 Port) | Pre-shared Keys |
| Cloudflare Tunnel + Access | mittel | keine eingehenden Ports | ja (via CF) | CF Access (SSO) |
| Caddy + Authelia/Authentik | hoch | 80/443 offen | ja | SSO + 2FA |

### SSH-Tunnel

Vorteile: Bereits etabliert, nur 22/tcp offen, kein zusaetzlicher Daemon.
Nachteile: Pro Port ein Forward, mobil unkomfortabel.

### Tailscale

Vorteile: Mesh-VPN, kein eingehender Port am Server noetig, ACLs pro
Geraet, mobile Clients vorhanden, einfache Installation.
Nachteile: Abhaengigkeit von Tailscale-Control-Plane (Headscale waere
self-hosted Alternative).

### WireGuard (self-hosted)

Vorteile: Vollstaendig self-hosted, performant.
Nachteile: UDP-Port muss offen sein, Key-Management manuell, kein
Identity-Provider.

### Cloudflare Tunnel + Access

Vorteile: Keine eingehenden Ports am Server, SSO via CF Access, DDoS-
Schutz, Logging.
Nachteile: Abhaengigkeit von Cloudflare, Traffic geht durch deren
Edge, App-Latenzen.

### Caddy + Authelia/Authentik

Vorteile: Voll im Eigenbetrieb, klassisches Reverse-Proxy-Setup mit
SSO/2FA.
Nachteile: 80/443 offen, Public Surface, hoher Wartungsaufwand,
Auth-Schicht muss korrekt vor jedem Service stehen. Siehe
`docs/reverse-proxy-auth-plan.md`.

## Empfehlung

Naechster Schritt: **Tailscale** auf Server und Endgeraeten installieren.

- Kein eingehender Port noetig (UFW bleibt restriktiv).
- Apps weiter auf `127.0.0.1` binden, Zugriff ueber Tailscale-IP des
  Servers via lokalen Tunnel (`tailscale serve` oder zusaetzliches Bind
  an Tailscale-Interface).
- ACLs pro Geraet pflegen, kein Catch-All.

**Kein oeffentlicher Reverse-Proxy ohne Auth.** Solange Dozzle,
Filebrowser und Stirling nicht hinter Authelia/Authentik o.ae. stehen,
keine Public-Freigabe.

Dieses Dokument enthaelt bewusst **keine Installationsanleitung**.
Installation und Konfiguration erfolgen separat.
