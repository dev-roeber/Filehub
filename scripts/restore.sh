#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

backup_dir="${1:-}"
if [[ -z "$backup_dir" || ! -d "$backup_dir" ]]; then
  echo "Nutzung: scripts/restore.sh backups/YYYYmmdd-HHMMSS" >&2
  exit 1
fi

echo "Vorsicht: Restore kann bestehende Daten überschreiben."
echo "Dieses Script führt absichtlich keinen automatischen Restore aus."
echo "Prüfe zuerst den Backup-Inhalt:"
find "$backup_dir" -maxdepth 1 -type f -printf '  %f\n'
echo
echo "Empfohlener manueller Ablauf:"
echo "1. scripts/backup.sh ausführen und Pre-Restore-Backup sichern."
echo "2. Stack stoppen: just down"
echo "3. Zielverzeichnisse manuell verschieben, nicht löschen."
echo "4. Tar-Dateien gezielt entpacken und Rechte prüfen."
echo "5. DB-Dump nach Prüfung in paperless-db importieren."
echo "6. Stack starten und logs/health prüfen."
