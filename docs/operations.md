# Betrieb

## Start und Stopp

```bash
just up
just down
just restart
```

Ohne `just`:

```bash
docker compose -f compose.yml -f compose.paperless.yml -f compose.convertx.yml -f compose.observability.yml up -d
docker compose -f compose.yml -f compose.paperless.yml -f compose.convertx.yml -f compose.observability.yml down
```

## Checks

```bash
just doctor
just health
just ps
just logs
```

`doctor.sh` prüft Docker, Compose, `.env`, Ports, Datenverzeichnisse, Swap, freien Speicher, UFW und offensichtliche Public Bindings.

## Updates

```bash
just backup
just update
just health
```

`scripts/update.sh` führt `pull` und `up -d` aus. Alte Images werden nur entfernt, wenn `PRUNE_OLD_IMAGES=true` gesetzt ist.

## Monitoring

Uptime Kuma sollte lokale Checks für diese URLs bekommen:

- `http://127.0.0.1:8000`
- `http://127.0.0.1:3000`
- `http://127.0.0.1:3001`
- `http://127.0.0.1:9999`
- `http://127.0.0.1:3002`

Dozzle bleibt nur lokal erreichbar, weil Logs sensible Inhalte enthalten können.

## Speicherplatz

Regelmäßig prüfen:

```bash
df -h
docker system df
du -sh data backups
```

Kein Script verwendet `docker compose down -v`.

## Tika Healthcheck

`paperless-tika` hat seit der Hardening-Stufe einen Docker-Healthcheck. Tika selbst bringt kein `curl` und kein `wget` mit; der Check nutzt deshalb `bash` mit `/dev/tcp/localhost/9998` und prueft die HTTP-Antwortzeile. Dadurch erscheint Tika in `docker compose ps` mit `(healthy)` und blockt Paperless beim Start nicht unnoetig (`condition: service_healthy`).

Falls der Check unerwartet `unhealthy` meldet, manuell pruefen:

```bash
docker exec filehub-paperless-tika bash -c 'timeout 5 bash -c "exec 3<>/dev/tcp/localhost/9998 && printf \"GET / HTTP/1.0\\r\\n\\r\\n\" >&3 && head -1 <&3"'
```

Erwartet wird `HTTP/1.1 200 OK`.

## Operative just-Befehle

Zusaetzlich zu Start/Stopp gibt es Befehle fuer Backup, Snapshots und Security:

```bash
just snapshots                  # restic snapshots --compact
just backup-dry-run-retention   # Retention-Vorschau, kein Loeschen
just backup-check               # restic check
just backup-restore-smoke-info  # Pfade und Doku-Verweise
just ports                      # Listening-Ports auf 127.0.0.1 und 0.0.0.0
just security-check             # doctor + Verweis auf docs/security.md
```

Diese Befehle geben keine Secrets aus.

## Taeglicher Blick ins Monitoring

1. Uptime Kuma im Browser oeffnen: `http://127.0.0.1:3002` (ggf. via SSH-Tunnel `ssh -L 3002:127.0.0.1:3002 sebastian@SERVER_IP`).
2. Im Dashboard nach roten Monitoren oder gelben Heartbeats suchen.
3. Wenn ein Monitor rot ist:
   - In Dozzle (`http://127.0.0.1:9999`) die Logs des betroffenen Containers pruefen.
   - `just ps` und `just health` fuer den schnellen Stack-Ueberblick.
   - Wenn ein Restart noetig scheint, gezielt `docker compose restart <service>` statt globalem `just restart`.
4. Mindestens woechentlich:
   - `just snapshots`
   - `just backup-dry-run-retention`
   - `just ports`

Notifications in Uptime Kuma erst aktivieren, wenn alle Monitore stabil gruen sind.
