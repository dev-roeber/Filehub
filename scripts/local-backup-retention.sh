#!/usr/bin/env bash
# Lokale Backup-Retention. Default Dry-Run. Loescht NIE ohne expliziten Opt-in
# (LOCAL_BACKUP_RETENTION_APPLY=true UND CLI-Flag --apply).
# Policy: keep last 7 + alles juenger als 14 Tage.
set -euo pipefail
cd "$(dirname "$0")/.."

apply=0
[[ "${1:-}" == "--apply" ]] && apply=1

KEEP_LAST=${LOCAL_BACKUP_KEEP_LAST:-7}
KEEP_DAYS=${LOCAL_BACKUP_KEEP_DAYS:-14}

mapfile -t backups < <(ls -1dt backups/2* 2>/dev/null || true)
total=${#backups[@]}

if [[ "$total" -eq 0 ]]; then
  echo "Keine lokalen Backups in backups/ gefunden."
  exit 0
fi

echo "Lokale Backups: $total"
printf '%-30s %10s %20s\n' "Ordner" "Groesse" "Alter"
printf '%-30s %10s %20s\n' "------" "-------" "-----"

now=$(date +%s)
delete_list=()
keep_list=()

for i in "${!backups[@]}"; do
  b="${backups[$i]}"
  size=$(du -sh "$b" 2>/dev/null | awk '{print $1}')
  m=$(stat -c %Y "$b")
  age_days=$(( (now - m) / 86400 ))
  printf '%-30s %10s %18sd\n' "$b" "$size" "$age_days"
  if (( i < KEEP_LAST )) || (( age_days < KEEP_DAYS )); then
    keep_list+=("$b")
  else
    delete_list+=("$b")
  fi
done

echo
echo "Policy: keep last $KEEP_LAST + keep younger than $KEEP_DAYS days."
echo "Zu behalten:  ${#keep_list[@]}"
echo "Zu loeschen:  ${#delete_list[@]}"
for d in "${delete_list[@]:-}"; do
  [[ -n "$d" ]] && echo "  - $d"
done

if [[ "$apply" -ne 1 ]]; then
  echo
  echo "Dry-Run. Kein Loeschen. Mit --apply UND LOCAL_BACKUP_RETENTION_APPLY=true scharfstellen."
  exit 0
fi

if [[ "${LOCAL_BACKUP_RETENTION_APPLY:-false}" != "true" ]]; then
  echo "ERROR: --apply gegeben, aber LOCAL_BACKUP_RETENTION_APPLY!=true. Abbruch." >&2
  exit 2
fi

# Schutz: aktiven (juengsten) Backup nie loeschen.
youngest="${backups[0]}"
for d in "${delete_list[@]:-}"; do
  if [[ -z "$d" || "$d" == "$youngest" ]]; then continue; fi
  echo "Loesche $d"
  rm -rf -- "$d"
done
echo "Lokale Retention angewendet."
