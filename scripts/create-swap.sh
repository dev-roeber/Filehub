#!/usr/bin/env bash
set -euo pipefail

size="${1:-4G}"

if swapon --show | awk 'NR > 1 {found=1} END {exit found ? 0 : 1}'; then
  echo "Swap ist bereits aktiv. Es wird nichts angelegt."
  swapon --show
  exit 0
fi

case "$size" in
  4G|5G|6G|7G|8G) ;;
  *) echo "ERROR: Größe muss zwischen 4G und 8G liegen, z. B. 4G." >&2; exit 1 ;;
esac

echo "Lege /swapfile mit $size an. Hinweis: Swap hilft bei Lastspitzen, ersetzt aber keinen RAM."
sudo fallocate -l "$size" /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile

if ! grep -qE '^/swapfile\s+none\s+swap\s+sw\s+0\s+0' /etc/fstab; then
  echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab >/dev/null
fi

swapon --show
