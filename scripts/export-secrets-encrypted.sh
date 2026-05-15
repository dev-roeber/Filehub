#!/usr/bin/env bash
# Erstellt ein verschluesseltes Archiv aus .env und .secrets/.
# Standard: verschluesselung MUSS konfiguriert sein - sonst bricht das Script ab.
# Es wird nie ein unverschluesseltes Archiv liegen gelassen.
set -euo pipefail
cd "$(dirname "$0")/.."

age_recipient="${AGE_RECIPIENT:-}"
gpg_recipient="${GPG_RECIPIENT:-}"

if [[ -z "$age_recipient" && -z "$gpg_recipient" ]]; then
  cat >&2 <<EOF
ERROR: weder AGE_RECIPIENT noch GPG_RECIPIENT gesetzt.

Beispiel:
  AGE_RECIPIENT=age1xyz...  scripts/export-secrets-encrypted.sh
oder:
  GPG_RECIPIENT=you@example  scripts/export-secrets-encrypted.sh

Ohne Recipient wuerde das Archiv unverschluesselt liegen - das ist verboten.
EOF
  exit 2
fi

ts=$(date +%Y%m%d-%H%M%S)
out_dir="backups/secrets"
mkdir -p "$out_dir"
chmod 700 "$out_dir"

tmp=$(mktemp -d -t filehub-secrets-XXXXXX)
trap 'rm -rf "$tmp"' EXIT
chmod 700 "$tmp"

tar -C . -cf "$tmp/secrets.tar" .env .secrets 2>/dev/null
chmod 600 "$tmp/secrets.tar"

if [[ -n "$age_recipient" ]]; then
  command -v age >/dev/null || { echo "ERROR: 'age' nicht installiert." >&2; exit 3; }
  out="$out_dir/filehub-secrets-${ts}.tar.age"
  age -r "$age_recipient" -o "$out" "$tmp/secrets.tar"
elif [[ -n "$gpg_recipient" ]]; then
  command -v gpg >/dev/null || { echo "ERROR: 'gpg' nicht installiert." >&2; exit 3; }
  out="$out_dir/filehub-secrets-${ts}.tar.gpg"
  gpg --batch --yes --encrypt --recipient "$gpg_recipient" \
    --output "$out" "$tmp/secrets.tar"
fi

chmod 600 "$out"
echo "Verschluesseltes Secrets-Archiv: $out"
echo "Bitte in externen, sicheren Speicher kopieren (Passwortmanager-Backup, Hardware-Stick)."
