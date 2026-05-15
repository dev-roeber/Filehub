#!/usr/bin/env bash
# homepage-apply.sh
# Promote config/homepage/services.generated.yaml -> config/homepage/services.yaml
# Safe overwrite with backup, validation and optional container restart.
# Exit codes:
#   0 OK
#   2 generated file missing
#   3 restart failed
#   4 validation failed
set -euo pipefail

cd "$(dirname "$0")/.."

SRC="config/homepage/services.generated.yaml"
DST="config/homepage/services.yaml"
DO_RESTART=0
SHOW_HELP=0

for arg in "$@"; do
  case "$arg" in
    --restart) DO_RESTART=1 ;;
    -h|--help) SHOW_HELP=1 ;;
    *) echo "WARN: unknown arg: $arg" >&2 ;;
  esac
done

if [[ "$SHOW_HELP" -eq 1 ]]; then
  cat <<'EOF'
Usage: scripts/homepage-apply.sh [--restart] [--help]

Promotes config/homepage/services.generated.yaml to config/homepage/services.yaml.
Creates a timestamped backup of the existing services.yaml.
With --restart, restarts the filehub-homepage container after apply.

Exit codes:
  0 success
  2 services.generated.yaml missing (run: just homepage-generate)
  3 container restart failed (config already applied)
  4 validation failed
EOF
  exit 0
fi

# Step 1: source must exist
if [[ ! -f "$SRC" ]]; then
  echo "ERROR: $SRC not found. Run 'just homepage-generate' first." >&2
  exit 2
fi

# Step 2: basic validation
if [[ ! -s "$SRC" ]]; then
  echo "ERROR: $SRC is empty." >&2
  exit 4
fi

NON_EMPTY_LINES=$(grep -cvE '^[[:space:]]*(#.*)?$' "$SRC" || true)
if [[ "$NON_EMPTY_LINES" -lt 5 ]]; then
  echo "ERROR: $SRC has too few content lines ($NON_EMPTY_LINES < 5)." >&2
  exit 4
fi

if ! grep -qE '^[[:space:]]*-[[:space:]]' "$SRC"; then
  echo "ERROR: $SRC has no list entry (no line starting with '- ')." >&2
  exit 4
fi

# Optional: deep YAML validation if PyYAML present
if python3 -c "import yaml" >/dev/null 2>&1; then
  if ! python3 -c "import sys, yaml; yaml.safe_load(open('$SRC'))" 2>/tmp/homepage-apply-yaml.err; then
    echo "ERROR: PyYAML safe_load failed:" >&2
    cat /tmp/homepage-apply-yaml.err >&2 || true
    exit 4
  fi
else
  echo "INFO: pyyaml not available, skipped deep YAML check"
fi

# Step 3: backup existing destination
if [[ -f "$DST" ]]; then
  BACKUP="${DST}.bak.$(date +%Y%m%d-%H%M%S)"
  cp "$DST" "$BACKUP"
  echo "Backup: $BACKUP"
fi

# Step 4: diff summary (must not fail pipeline)
if [[ -f "$DST" ]]; then
  echo "--- Diff (services.yaml -> services.generated.yaml, max 40 lines) ---"
  diff -u "$DST" "$SRC" | head -40 || true
  echo "--- end diff ---"
else
  echo "INFO: no existing $DST, fresh write"
fi

# Step 5: atomic write
cp "$SRC" "${DST}.tmp"
mv "${DST}.tmp" "$DST"
echo "Applied: $SRC -> $DST"

# Step 7: optional restart
if [[ "$DO_RESTART" -eq 1 ]]; then
  CONTAINER="filehub-homepage"
  # Best-effort: derive container name from config/apps.yml if present
  if [[ -f "config/apps.yml" ]] && command -v python3 >/dev/null 2>&1 && python3 -c "import yaml" >/dev/null 2>&1; then
    DERIVED=$(python3 - <<'PY' 2>/dev/null || true
import yaml
try:
    data = yaml.safe_load(open("config/apps.yml")) or {}
except Exception:
    data = {}
# Try a few common shapes
def find(d):
    if isinstance(d, dict):
        for k, v in d.items():
            if k == "homepage" and isinstance(v, dict):
                for key in ("container", "container_name", "name"):
                    if key in v and isinstance(v[key], str):
                        return v[key]
            r = find(v)
            if r:
                return r
    elif isinstance(d, list):
        for it in d:
            r = find(it)
            if r:
                return r
    return None
n = find(data)
if n:
    print(n)
PY
)
    if [[ -n "${DERIVED:-}" ]]; then
      CONTAINER="$DERIVED"
    fi
  fi
  echo "Restarting container: $CONTAINER"
  if ! docker restart "$CONTAINER"; then
    echo "WARN: docker restart $CONTAINER failed. Config remains applied (no rollback)." >&2
    exit 3
  fi
  echo "Restart OK: $CONTAINER"
fi

exit 0
