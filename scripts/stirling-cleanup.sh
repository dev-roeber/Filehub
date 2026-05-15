#!/usr/bin/env bash
# Loescht Dateien in data/stirling/work, die aelter als STIRLING_CLEANUP_AGE_HOURS
# (Default 24h) sind. Default Dry-Run.
set -euo pipefail
cd "$(dirname "$0")/.."

apply=0
[[ "${1:-}" == "--apply" ]] && apply=1

dir="data/stirling/work"
age_hours=${STIRLING_CLEANUP_AGE_HOURS:-24}
age_min=$(( age_hours * 60 ))

if [[ ! -d "$dir" ]]; then
  echo "$dir nicht vorhanden - nichts zu tun."
  exit 0
fi

mapfile -t old_files < <(find "$dir" -mindepth 1 -type f -mmin +"$age_min" 2>/dev/null)
total=$(find "$dir" -mindepth 1 -type f 2>/dev/null | wc -l)

echo "Verzeichnis: $dir"
echo "Dateien insgesamt: $total"
echo "Aelter als ${age_hours}h: ${#old_files[@]}"
for f in "${old_files[@]:-}"; do
  [[ -n "$f" ]] && echo "  - $f"
done

if [[ "$apply" -ne 1 ]]; then
  echo
  echo "Dry-Run. Mit --apply UND STIRLING_CLEANUP_APPLY=true scharfstellen."
  exit 0
fi

if [[ "${STIRLING_CLEANUP_APPLY:-false}" != "true" ]]; then
  echo "ERROR: --apply gegeben, aber STIRLING_CLEANUP_APPLY!=true. Abbruch." >&2
  exit 2
fi

for f in "${old_files[@]:-}"; do
  [[ -n "$f" ]] && rm -f -- "$f"
done
# leere Unterverzeichnisse aufraeumen
find "$dir" -mindepth 1 -type d -empty -delete 2>/dev/null || true
echo "Stirling-Cleanup angewendet."
