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
