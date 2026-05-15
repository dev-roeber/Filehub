set shell := ["bash", "-cu"]

compose_core := "docker compose -f compose.yml -f compose.paperless.yml -f compose.convertx.yml"
compose_all := "docker compose -f compose.yml -f compose.paperless.yml -f compose.convertx.yml -f compose.observability.yml"
compose_ext := "docker compose -f compose.yml -f compose.paperless.yml -f compose.convertx.yml -f compose.observability.yml -f compose.extensions.yml"
compose_proxy := "docker compose -f compose.yml -f compose.paperless.yml -f compose.convertx.yml -f compose.observability.yml -f compose.proxy.yml --profile proxy"
compose_auth := "docker compose -f compose.yml -f compose.paperless.yml -f compose.convertx.yml -f compose.observability.yml -f compose.extensions.yml -f compose.auth.yml"

init:
    ./scripts/init.sh

pull:
    {{compose_all}} pull

up:
    {{compose_all}} up -d

up-core:
    {{compose_core}} up -d

up-observability:
    {{compose_all}} up -d

up-proxy:
    {{compose_proxy}} up -d caddy

down:
    {{compose_all}} down

restart:
    {{compose_all}} restart

logs:
    {{compose_all}} logs -f --tail=200

ps:
    {{compose_all}} ps

health:
    ./scripts/health.sh

doctor:
    ./scripts/doctor.sh

update:
    ./scripts/update.sh

backup:
    ./scripts/backup.sh

backup-install-timer:
    sudo install -m 0644 deploy/systemd/filehub-backup.service /etc/systemd/system/filehub-backup.service
    sudo install -m 0644 deploy/systemd/filehub-backup.timer /etc/systemd/system/filehub-backup.timer
    sudo systemctl daemon-reload

backup-enable-timer:
    sudo systemctl enable --now filehub-backup.timer

backup-disable-timer:
    sudo systemctl disable --now filehub-backup.timer

backup-timer-status:
    systemctl status filehub-backup.timer --no-pager
    systemctl list-timers filehub-backup.timer --no-pager

backup-logs:
    journalctl -u filehub-backup.service -n 200 --no-pager

backup-run-now:
    sudo systemctl start filehub-backup.service

snapshots:
    @set -a && . ./.env && set +a && restic snapshots --compact

backup-dry-run-retention:
    @set -a && . ./.env && set +a && restic forget --tag filehub-full --group-by host,tags --keep-daily "${BACKUP_RETENTION_DAILY:-7}" --keep-weekly "${BACKUP_RETENTION_WEEKLY:-4}" --keep-monthly "${BACKUP_RETENTION_MONTHLY:-6}" --dry-run --compact

backup-check:
    @set -a && . ./.env && set +a && restic check

backup-restore-smoke-info:
    @echo "Restore-Smoke-Pfad: /home/sebastian/Repos/Filehub-restic-restore-smoke"
    @echo "Ablauf siehe docs/restore-test.md und docs/cloud-backup-result-*.md"

ports:
    @ss -tlnp 2>/dev/null | awk 'NR==1 || /127\.0\.0\.1|0\.0\.0\.0/' || sudo ss -tlnp

security-check:
    ./scripts/doctor.sh
    @echo "---"
    @echo "UFW-Status und Public Bindings sind oben aufgefuehrt."
    @echo "Pruefe zusaetzlich: docs/security.md"

tunnel-help:
    @echo "ssh -L 3000:127.0.0.1:3000 -L 8000:127.0.0.1:8000 -L 9999:127.0.0.1:9999 -L 3001:127.0.0.1:3001 -L 3002:127.0.0.1:3002 -L 3003:127.0.0.1:3003 -L 3004:127.0.0.1:3004 sebastian@SERVER_IP"

secrets-audit:
    ./scripts/secrets-audit.sh

up-extensions:
    {{compose_ext}} up -d filebrowser stirling-pdf

down-extensions:
    {{compose_ext}} stop filebrowser stirling-pdf
    {{compose_ext}} rm -f filebrowser stirling-pdf

restart-extensions:
    {{compose_ext}} restart filebrowser stirling-pdf

logs-extensions:
    {{compose_ext}} logs -f --tail=200 filebrowser stirling-pdf

up-all:
    {{compose_ext}} up -d

ps-all:
    {{compose_ext}} ps

health-all:
    ./scripts/health.sh

# --- Operations: Reports + Cleanup + Notifications ---

notify-test:
    ./scripts/notify.sh --title "Filehub ntfy test" --message "Manueller Test via justfile" --tags "white_check_mark,filehub"

backup-report:
    ./scripts/backup-report.sh

backup-report-notify:
    ./scripts/backup-report.sh --notify

storage-check:
    ./scripts/storage-check.sh

audit-report:
    ./scripts/audit-report.sh

registry-audit:
    ./scripts/registry-audit.sh

registry-audit-quiet:
    ./scripts/registry-audit.sh --quiet

runtime-audit:
    ./scripts/runtime-audit.sh

runtime-audit-quiet:
    ./scripts/runtime-audit.sh --quiet

runtime-audit-strict:
    ./scripts/runtime-audit.sh --strict

migration-status:
    ./scripts/migration-status.sh

gateway-migration-status:
    ./scripts/gateway-migration-status.sh

gateway-migration-status-quiet:
    ./scripts/gateway-migration-status.sh --quiet

gateway-migration-status-json:
    ./scripts/gateway-migration-status.sh --json

migrate-dry-run app:
    ./scripts/migrate-app.sh {{app}} --dry-run

migrate-plan app:
    ./scripts/migrate-app.sh {{app}} --print-commands

migrate-rollback-plan app:
    ./scripts/migrate-app.sh {{app}} --rollback-plan

backup-age app:
    ./scripts/backup-age.sh {{app}}

migrate-execute-homepage:
    ./scripts/migrate-app.sh homepage --execute --yes-i-am-sure

migrate-execute-filebrowser:
    ./scripts/migrate-app.sh filebrowser --execute --yes-i-am-sure

migrate-execute-stirling-pdf:
    ./scripts/migrate-app.sh stirling-pdf --execute --yes-i-am-sure

migrate-execute-convertx:
    ./scripts/migrate-app.sh convertx --execute --yes-i-am-sure

migrate-execute-uptime-kuma:
    ./scripts/migrate-app.sh uptime-kuma --execute --yes-i-am-sure

migrate-execute-dozzle:
    ./scripts/migrate-app.sh dozzle --execute --yes-i-am-sure

# Paperless Multi-Container-Cutover. Erfordert Wartungsfenster und alle
# erweiterten Preflight-Checks. Nicht idempotent. Kein Auto-Rollback ohne
# DB-Snapshot.
migrate-execute-paperless-careful:
    ./scripts/migrate-app.sh paperless --execute --yes-i-am-sure --allow-paperless

audit-report-notify:
    ./scripts/audit-report.sh --notify

local-backup-retention-dry-run:
    ./scripts/local-backup-retention.sh

local-backup-retention-apply:
    LOCAL_BACKUP_RETENTION_APPLY=true ./scripts/local-backup-retention.sh --apply

stirling-cleanup-dry-run:
    ./scripts/stirling-cleanup.sh

stirling-cleanup-apply:
    STIRLING_CLEANUP_APPLY=true ./scripts/stirling-cleanup.sh --apply

backup-alert-test:
    ./scripts/backup-alert.sh --test

backup-alert-install-unit:
    sudo install -m 0644 deploy/systemd/filehub-backup-alert@.service /etc/systemd/system/filehub-backup-alert@.service
    sudo install -m 0644 deploy/systemd/filehub-backup.service /etc/systemd/system/filehub-backup.service
    sudo systemctl daemon-reload

update-safe:
    @echo "1) backup (manuell)";  ./scripts/backup.sh
    @echo "2) pull";               {{compose_ext}} pull
    @echo "3) up -d";               {{compose_ext}} up -d
    @echo "4) health";              ./scripts/health.sh

setup-uptime-kuma-notifications:
    ./scripts/setup-uptime-kuma-notifications.sh

setup-uptime-kuma-statuspage:
    ./scripts/setup-uptime-kuma-statuspage.sh

setup-paperless-saved-views:
    ./scripts/setup-paperless-saved-views.sh

# --- Authentik SSO Gateway (Phase 1, localhost-only) ---

up-auth:
    {{compose_auth}} up -d authentik-postgres authentik-redis authentik-server authentik-worker filehub-gateway

down-auth:
    {{compose_auth}} stop filehub-gateway authentik-server authentik-worker authentik-redis authentik-postgres
    {{compose_auth}} rm -f filehub-gateway authentik-server authentik-worker authentik-redis authentik-postgres

restart-auth:
    {{compose_auth}} restart authentik-server authentik-worker filehub-gateway

logs-auth:
    {{compose_auth}} logs -f --tail=200 authentik-server authentik-worker filehub-gateway

auth-status:
    @{{compose_auth}} ps authentik-postgres authentik-redis authentik-server authentik-worker
    @echo "---"
    @curl -fsS -o /dev/null -w 'authentik-ui (http://127.0.0.1:9000): %{http_code}\n' --max-time 5 http://127.0.0.1:9000/ || true

gateway-status:
    @{{compose_auth}} ps filehub-gateway
    @echo "---"
    @curl -fsS -o /dev/null -w 'gateway-health (http://127.0.0.1:3080/_health): %{http_code}\n' --max-time 5 http://127.0.0.1:3080/_health || true
    @curl -fsS -o /dev/null -w 'gateway-root  (http://127.0.0.1:3080/):         %{http_code}\n' --max-time 5 http://127.0.0.1:3080/ || true

# Read-only Check: unterscheidet zwischen PRE-BOOTSTRAP (404 vom Embedded Outpost)
# und POST-BOOTSTRAP (302 mit Login-Redirect auf Authentik). Aendert nichts.
gateway-bootstrap-check:
    ./scripts/gateway-bootstrap-check.sh

# --- Modulare App-Kommandos (apps/<id>/) ---

app-list:
    @./scripts/app.sh list

app-up app:
    ./scripts/app.sh up {{app}}

app-down app:
    ./scripts/app.sh down {{app}}

app-restart app:
    ./scripts/app.sh restart {{app}}

app-logs app:
    ./scripts/app.sh logs {{app}}

app-status app:
    ./scripts/app.sh status {{app}}

app-pull app:
    ./scripts/app.sh pull {{app}}

app-update app:
    ./scripts/app.sh update {{app}}

app-health app:
    ./scripts/app.sh health {{app}}

apps-status:
    @./scripts/app.sh apps-status

infra-status:
    @./scripts/app.sh infra-status

# --- Authentik (optional, default deaktiviert) ---
# auth-up startet Authentik nur, wenn AUTHENTIK_ENABLED=true gesetzt ist;
# andernfalls erfolgt eine Warnung und kein Container-Start.

auth-up:
    @set -a && . ./.env && set +a && \
      if [ "${AUTHENTIK_ENABLED:-false}" = "true" ]; then \
        docker compose --env-file .env -f infra/authentik/compose.yml up -d; \
      else \
        echo "AUTHENTIK_ENABLED!=true - keine Aktion. Siehe docs/AUTHENTIK_OPTIONAL.md."; \
        exit 1; \
      fi

auth-down:
    docker compose --env-file .env -f infra/authentik/compose.yml stop
    docker compose --env-file .env -f infra/authentik/compose.yml rm -f

auth-restart:
    docker compose --env-file .env -f infra/authentik/compose.yml restart

auth-logs:
    docker compose --env-file .env -f infra/authentik/compose.yml logs -f --tail=200

# --- Gateway (Caddy) ---
# Konvention: <komponente>-<aktion>. Bestehende up-auth/down-auth/logs-auth/
# restart-auth-Targets weiter oben bleiben als Aliase erhalten und arbeiten
# zusaetzlich Authentik+Gateway gemeinsam ueber compose.auth.yml.

gateway-up:
    docker compose --env-file .env -f compose.auth.yml up -d filehub-gateway

gateway-down:
    docker compose --env-file .env -f compose.auth.yml stop filehub-gateway
    docker compose --env-file .env -f compose.auth.yml rm -f filehub-gateway

gateway-restart:
    docker compose --env-file .env -f compose.auth.yml restart filehub-gateway

gateway-logs:
    docker compose --env-file .env -f compose.auth.yml logs -f --tail=200 filehub-gateway

gateway-reload:
    # Caddy reload via admin API ist deaktiviert (admin off); Container-Restart
    # als einziger zuverlaessiger Weg.
    docker restart filehub-gateway

# --- Modulares Backup ---

backup-app app:
    ./scripts/app.sh backup-app {{app}}

backup-all:
    ./scripts/app.sh backup-all

homepage-generate:
    ./scripts/homepage-from-registry.py

homepage-apply:
    ./scripts/homepage-apply.sh

homepage-apply-restart:
    ./scripts/homepage-apply.sh --restart

# --- Caddy Snippet Helper ---

caddy-enable app:
    ./scripts/caddy-enable.sh {{app}} plain

caddy-enable-auth app:
    ./scripts/caddy-enable.sh {{app}} authentik

caddy-disable app:
    ./scripts/caddy-disable.sh {{app}}

caddy-list:
    @./scripts/caddy-list.sh
