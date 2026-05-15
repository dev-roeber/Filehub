# Filehub Monitoring

Schlanker Monitoring-Stack:

- **Prometheus** (`filehub-prometheus`, Port 9090) -- Time-Series-DB,
  scraped Node + cAdvisor alle 15s, Retention 30 Tage.
- **Node-Exporter** (`filehub-node-exporter`, Port 9100) -- Host-
  Metriken (CPU, RAM, Disk, Net, Filesystem, Load, Uptime).
- **cAdvisor** (`filehub-cadvisor`, Port 9080) -- Container-Metriken
  (pro Docker-Container: CPU, RAM, Net, FS, Restart-Count).

Visualisierung in **Grafana** ueber Datasource `Prometheus`, die per
Provisioning unter `config/grafana/provisioning/datasources/` definiert
ist. Dashboards (Node Exporter Full + Docker/cAdvisor) liegen ebenfalls
als Provisioning-Files im Grafana-Modul.

## Start / Stop

```
docker compose --env-file ../../.env -f compose.yml up -d
docker compose --env-file ../../.env -f compose.yml stop
docker compose --env-file ../../.env -f compose.yml logs -f
```

Oder ueber Justfile (siehe Plattform-Root):

```
just monitoring-up
just monitoring-down
just monitoring-status
```

## Endpoints (alle 127.0.0.1)

| Service | URL | Zweck |
|---|---|---|
| Prometheus UI | http://127.0.0.1:9090/ | TSDB + PromQL-Ad-hoc-Queries |
| Prometheus Health | http://127.0.0.1:9090/-/healthy | Container-Health |
| Node Exporter | http://127.0.0.1:9100/metrics | Host-Metriken (raw) |
| cAdvisor | http://127.0.0.1:9080/ | Container-Metriken-UI |
| cAdvisor Metrics | http://127.0.0.1:9080/metrics | Container-Metriken (raw) |

## Volumes / Bind-Mounts

- Prometheus-TSDB: `data/prometheus/` (~ 100-500 MB pro Monat).
- Prometheus-Config: `config/prometheus/prometheus.yml` (ro).
- Node-Exporter: host-Pfade `/proc`, `/sys`, `/` read-only.
- cAdvisor: `/`, `/var/run`, `/sys`, `/var/lib/docker`, `/dev/disk`
  read-only. **Privileged** wegen Kernel-Cgroups-Zugriff.

## Sicherheit

- Alle Ports binden auf 127.0.0.1 -- kein Public-Zugriff.
- cAdvisor laeuft **privileged** (Standard fuer Container-Metriken).
- Node-Exporter mountet `/` read-only (kein Schreib-Zugriff auf Host).
- Keine Authentifizierung auf Prometheus/Node/cAdvisor -- Zugriff nur
  via SSH-Tunnel / Gateway.

## Was dieses Modul NICHT macht

- Keine Log-Aggregation (kein Loki).
- Kein Alertmanager (Alerts laufen weiter ueber Uptime-Kuma).
- Kein Tracing (kein Tempo).
- Keine externen Probes (Blackbox-Exporter optional spaeter).
