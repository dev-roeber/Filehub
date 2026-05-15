# apps/grafana

Grafana OSS als eigenstaendiges App-Modul (Visualisierung / Dashboards).

## Zweck

Dashboards und Visualisierung fuer Metriken aus dem Filehub-Stack
(z. B. Prometheus, Loki, Postgres). Lauscht lokal auf Port 3005.

## Ports

- Host: `127.0.0.1:3005` (konfigurierbar via `GRAFANA_PORT`)
- Container: `3000`

## Start / Stop / Logs / Health

```
just app-up grafana
just app-down grafana
just app-logs grafana
just app-health grafana
```

Alternativ direkt via docker compose:

```
docker compose --env-file ../../.env -f apps/grafana/compose.yml up -d
docker compose --env-file ../../.env -f apps/grafana/compose.yml down
docker compose --env-file ../../.env -f apps/grafana/compose.yml logs -f
bash apps/grafana/healthcheck.sh
```

## Initial-Admin

`GF_SECURITY_ADMIN_USER` und `GF_SECURITY_ADMIN_PASSWORD` werden NUR bei der
Erst-Initialisierung (leeres `data/grafana`) wirksam. Nach dem ersten Start
muss das Passwort ueber die Grafana-UI (Profil > Change Password) oder per
`grafana-cli admin reset-admin-password <neu>` im Container geaendert werden.
Spaetere Aenderungen der ENV-Werte haben keinen Effekt mehr.

Standardwerte stammen aus `FILEHUB_ADMIN_USER` / `FILEHUB_ADMIN_PASSWORD`
in der Root-`.env`. Bitte lokal ein eigenes Secret setzen, keine
Klartext-Passwoerter committen.

## Daten / Backup

Persistente Pfade (siehe `backup.include`):

- `data/grafana` - Grafana-DB (sqlite), Plugins, Sessions
- `config/grafana/provisioning` - optionales Provisioning (datasources, dashboards)
- `apps/grafana/compose.yml`
- `apps/grafana/.env.example`

## Provisioning (optional)

Unter `config/grafana/provisioning/` koennen Unterordner `datasources/`,
`dashboards/`, `notifiers/`, `plugins/` mit YAML-Dateien abgelegt werden.
Grafana liest diese beim Start. Mount erfolgt read-only.

## Reverse-Proxy

- `caddy.disabled` - Vorlage fuer Caddy-Snippet ohne Auth.
- `caddy.authentik.disabled` - Vorlage mit Authentik forward_auth (optional).

Aktivierung durch Umbenennen (Endung `.disabled` entfernen) und Einbindung
im Gateway-Caddyfile.

## Image-Pin

Image ist aktuell hart auf `grafana/grafana:11.4.0` gesetzt. Spaetere
Aktualisierung idealerweise ueber `GRAFANA_IMAGE` in der `.env` steuern.
