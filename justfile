set shell := ["bash", "-cu"]

compose_core := "docker compose -f compose.yml -f compose.paperless.yml -f compose.convertx.yml"
compose_all := "docker compose -f compose.yml -f compose.paperless.yml -f compose.convertx.yml -f compose.observability.yml"
compose_proxy := "docker compose -f compose.yml -f compose.paperless.yml -f compose.convertx.yml -f compose.observability.yml -f compose.proxy.yml --profile proxy"

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

tunnel-help:
    @echo "ssh -L 3000:127.0.0.1:3000 -L 8000:127.0.0.1:8000 -L 9999:127.0.0.1:9999 -L 3001:127.0.0.1:3001 -L 3002:127.0.0.1:3002 sebastian@SERVER_IP"
