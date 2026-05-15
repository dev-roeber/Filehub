# Docker-Socket Hardening

Stand: 2026-05-15. Filehub laeuft localhost-only.

## Aktueller Zustand

Zwei Container mounten den Docker-Socket `/var/run/docker.sock` read-only:

- **Homepage** zur Container-Discovery fuer das Dashboard.
- **Dozzle** zum Log-Streaming.

## Risiko

Auch ein read-only-Mount des Docker-Sockets ist effektiv root-equivalent
auf dem Host. Wer den Socket lesen kann, sieht:

- Alle Container, deren Env-Variablen (inkl. moeglicher Secrets in Env).
- Logs aller Container.
- Netzwerke, Volumes, Image-Listen.

Read-only verhindert nur Operationen wie `docker exec`/`docker run` ueber
denselben Socket, nicht den Informationsabfluss. Siehe Doku des
`linuxserver/docker-socket-proxy`-Images.

Solange Filehub strikt auf `127.0.0.1` bindet und UFW nur 22/tcp freigibt,
ist das Risiko begrenzt. Sobald ein Dienst extern erreichbar wird, muss
der direkte Socket-Mount weg.

## Alternativen

### tecnativa/docker-socket-proxy

Vorgeschalteter Proxy, der nur eine Whitelist von Endpoints freigibt.
Empfohlene Mindestkonfiguration fuer Homepage + Dozzle:

```text
CONTAINERS=1
IMAGES=1
NETWORKS=1
SERVICES=1
TASKS=1
POST=0
```

Homepage und Dozzle reden dann ueber TCP gegen den Proxy, der Socket
selbst wird nur in den Proxy-Container gemountet.

### Dozzle ohne Actions

```yaml
environment:
  DOZZLE_NO_ACTIONS: "true"
```

Schaltet Container-Aktionen (Start/Stop/Restart) im UI ab. Reduziert den
Schaden, falls jemand Zugriff auf das Dozzle-UI bekommt.

### Homepage mit eingeschraenkter docker-Konfiguration

- Auto-Discovery deaktivieren.
- Stattdessen statische `services.yaml` pflegen.
- `docker:`-Block in `settings.yaml` entfernen, falls Socket nicht
  benoetigt wird.

## Migrationsplan

Drei Stufen, nichts wird jetzt aktiviert.

1. **Doku/Risiko-Assessment** (dieses Dokument).
2. **`compose.socket-proxy.yml` als Profil vorbereiten**, nicht
   aktivieren. Inkl. Netzwerk, Proxy-Service, Anpassung der Dozzle/
   Homepage-Konfiguration auf TCP-Endpoint.
3. **Cutover**: Proxy aktivieren, Homepage + Dozzle gegen Proxy
   testen, anschliessend alte Socket-Mounts aus `compose.yml` entfernen.

## Schlussempfehlung

Erst aktivieren, wenn Reverse-Proxy- und Auth-Phase 2 ansteht (siehe
`docs/reverse-proxy-auth-plan.md`). Solange Filehub nur ueber
SSH-Tunnel oder Tailscale erreichbar ist, ist der direkte Socket-Mount
vertretbar, aber dokumentiert.
