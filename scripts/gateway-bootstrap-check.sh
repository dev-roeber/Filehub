#!/usr/bin/env bash
# Read-only Check fuer den Authentik-Gateway-Status.
# Unterscheidet zwischen:
#   PRE-BOOTSTRAP       -> Embedded Outpost hat noch keine Application (404)
#   POST-BOOTSTRAP      -> Forward-Auth redirected auf Authentik (302)
#   POST-BOOTSTRAP-AUTH -> Forward-Auth liefert ohne Redirect 200
#   UNKNOWN             -> alles andere
# Aendert nichts. Sendet nichts an ntfy.
set -uo pipefail

resp=$(curl -sS -o /dev/null -w '%{http_code}|%{redirect_url}' --max-time 5 http://127.0.0.1:3080/ 2>/dev/null || echo "000|")
code=${resp%%|*}
redirect=${resp#*|}
health=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 5 http://127.0.0.1:3080/_health 2>/dev/null || echo "000")
authentik=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 5 http://127.0.0.1:9000/ 2>/dev/null || echo "000")

printf 'gateway /_health : %s\n' "$health"
printf 'gateway /        : %s\n' "$code"
printf 'authentik /      : %s\n' "$authentik"
[[ -n "$redirect" ]] && printf 'redirect_url     : %s\n' "$redirect"

if [[ "$health" = "200" && "$code" = "404" ]]; then
  echo "STATE=PRE-BOOTSTRAP (Embedded Outpost hat noch keine Application -> docs/sso-gateway.md Checkliste abarbeiten)"
  exit 0
elif [[ "$health" = "200" && "$code" = "302" ]] && echo "$redirect" | grep -q '127\.0\.0\.1:9000'; then
  echo "STATE=POST-BOOTSTRAP (Login-Redirect auf $redirect)"
  exit 0
elif [[ "$health" = "200" && "$code" = "200" ]]; then
  echo "STATE=POST-BOOTSTRAP-AUTH (200 - bereits eingeloggt oder Forward-Auth ohne Redirect)"
  exit 0
else
  echo "STATE=UNKNOWN (health=$health code=$code authentik=$authentik)"
  exit 1
fi
