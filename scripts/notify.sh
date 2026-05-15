#!/usr/bin/env bash
# Sendet Filehub-Notifications via ntfy. Topic kommt aus .secrets/ntfy.env
# und wird NIE in Logs oder stdout ausgegeben.
set -euo pipefail
cd "$(dirname "$0")/.."

title="Filehub"
message=""
priority=""
tags=""
quiet=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --title)     title="$2"; shift 2 ;;
    --message)   message="$2"; shift 2 ;;
    --priority)  priority="$2"; shift 2 ;;
    --tags)      tags="$2"; shift 2 ;;
    --quiet)     quiet=1; shift ;;
    -h|--help)
      cat <<USAGE
notify.sh --title T --message M [--priority default|high|low|min|max] [--tags tag1,tag2]
USAGE
      exit 0
      ;;
    *) echo "ERROR: unbekanntes Argument: $1" >&2; exit 2 ;;
  esac
done

if [[ -z "$message" ]]; then
  echo "ERROR: --message ist erforderlich." >&2
  exit 2
fi

env_file=".secrets/ntfy.env"
if [[ ! -f "$env_file" ]]; then
  [[ "$quiet" -eq 1 ]] || echo "notify: $env_file fehlt - no-op."
  exit 0
fi

# shellcheck disable=SC1090
set -a; source "$env_file"; set +a

if [[ "${NTFY_ENABLED:-false}" != "true" ]]; then
  [[ "$quiet" -eq 1 ]] || echo "notify: NTFY_ENABLED!=true - no-op."
  exit 0
fi

server_url="${NTFY_SERVER_URL:-https://ntfy.sh}"
topic="${NTFY_TOPIC:-}"
if [[ -z "$topic" ]]; then
  echo "notify: NTFY_TOPIC fehlt - kann nicht senden." >&2
  exit 1
fi

prio="$priority"
if [[ -z "$prio" ]]; then prio="${NTFY_PRIORITY_DEFAULT:-default}"; fi

http_code=$(curl -sS -o /tmp/.notify-resp.$$ -w '%{http_code}' \
  -X POST "${server_url}/${topic}" \
  -H "Title: ${title}" \
  -H "Priority: ${prio}" \
  ${tags:+-H "Tags: ${tags}"} \
  --data-binary "${message}" \
  || true)
rm -f /tmp/.notify-resp.$$

if [[ "$http_code" =~ ^2 ]]; then
  [[ "$quiet" -eq 1 ]] || echo "notify: ok (http $http_code)"
  exit 0
else
  echo "notify: send failed (http ${http_code:-?})" >&2
  exit 1
fi
