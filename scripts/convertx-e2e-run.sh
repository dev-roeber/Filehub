#!/usr/bin/env bash
# Echte E2E-Conversions ueber die ConvertX-HTTP-API.
# Benoetigt: .secrets/convertx.env mit CONVERTX_ADMIN_EMAIL/PASSWORD,
# laufenden filehub-convertx-Container auf 127.0.0.1:3000.
# Output: data/convertx-test/output/<id>_<name>.<ext>, plus Tabelle stdout.

set -euo pipefail
cd "$(dirname "$0")/.."

# shellcheck disable=SC1091
source .secrets/convertx.env

BASE="http://127.0.0.1:3000"
COOKIES="$(mktemp)"
OUT="data/convertx-test/output"
IN="data/convertx-test/input"
mkdir -p "$OUT"

trap 'rm -f "$COOKIES"' EXIT

login() {
  curl -s -c "$COOKIES" -b "$COOKIES" \
    -X POST "$BASE/login" \
    -H 'Content-Type: application/x-www-form-urlencoded' \
    --data-urlencode "email=$CONVERTX_ADMIN_EMAIL" \
    --data-urlencode "password=$CONVERTX_ADMIN_PASSWORD" \
    -o /dev/null -w "%{http_code}\n"
}

new_job() {
  # GET / sets a fresh jobId cookie
  curl -s -c "$COOKIES" -b "$COOKIES" "$BASE/" -o /dev/null
  awk '$6=="jobId"{print $7}' "$COOKIES"
}

run_one() {
  local label="$1" src="$2" target_ext="$3" converter="$4"
  local jobid http
  jobid=$(new_job)
  http=$(curl -s -b "$COOKIES" -c "$COOKIES" \
    -X POST "$BASE/upload" \
    -F "file=@${src}" -o /dev/null -w '%{http_code}')
  if [[ "$http" != "200" ]]; then
    printf '%-30s FAIL upload http=%s\n' "$label" "$http"
    return 1
  fi
  http=$(curl -s -b "$COOKIES" -c "$COOKIES" \
    -X POST "$BASE/convert" \
    --data-urlencode "convert_to=${target_ext},${converter}" \
    --data-urlencode "file_names=[\"$(basename "$src")\"]" \
    -o /dev/null -w '%{http_code}')
  # wait for status=completed in db (max 60s)
  local i status
  for i in $(seq 1 60); do
    status=$(docker exec filehub-convertx sh -c "cd /app && bun -e 'import db from \"./dist/src/db/db\"; const r=db.query(\"SELECT status FROM jobs WHERE id=?\").get($jobid); process.stdout.write((r&&r.status)||\"\");'" 2>/dev/null || true)
    [[ "$status" == "completed" ]] && break
    [[ "$status" == "failed" ]] && break
    sleep 1
  done
  # find produced file
  local outfile
  outfile=$(docker exec filehub-convertx sh -c "ls /app/data/output/2/$jobid/ 2>/dev/null | head -1" || true)
  if [[ -z "$outfile" ]]; then
    printf '%-30s FAIL convert status=%s\n' "$label" "$status"
    return 1
  fi
  local dest="$OUT/${label}.${target_ext}"
  docker cp "filehub-convertx:/app/data/output/2/$jobid/$outfile" "$dest" >/dev/null
  local size
  size=$(stat -c%s "$dest")
  printf '%-30s OK    %s (%s bytes)\n' "$label" "$dest" "$size"
}

echo "Login: $(login)"

# Bild
run_one "img_png2webp"  "$IN/test.png"  "webp" "imagemagick"
run_one "img_jpg2png"   "$IN/test.jpg"  "png"  "imagemagick"
run_one "img_jpg2webp"  "$IN/test.jpg"  "webp" "imagemagick"
run_one "img_svg2png"   "$IN/test.svg"  "png"  "inkscape"

# Dokumente
run_one "doc_docx2pdf"  "$IN/test.docx" "pdf"  "libreoffice"
run_one "doc_txt2pdf"   "$IN/test.txt"  "pdf"  "libreoffice"
run_one "doc_md2pdf"    "$IN/test.md"   "pdf"  "pandoc"
run_one "doc_md2html"   "$IN/test.md"   "html" "pandoc"
run_one "doc_pdf2png"   "$IN/test.pdf"  "png"  "imagemagick"

# Audio
run_one "aud_wav2mp3"   "$IN/test.wav"  "mp3"  "ffmpeg"
run_one "aud_wav2ogg"   "$IN/test.wav"  "ogg"  "ffmpeg"

# Video
run_one "vid_mp42webm"  "$IN/test.mp4"  "webm" "ffmpeg"
run_one "vid_mp42gif"   "$IN/test.mp4"  "gif"  "ffmpeg"

# HEIC synthetisch erzeugen und konvertieren
if ! [[ -f "$IN/test.heic" ]]; then
  docker exec filehub-convertx sh -c 'cd /tmp && magick -size 64x64 gradient:blue-red test.heic' || true
  docker cp filehub-convertx:/tmp/test.heic "$IN/test.heic" 2>/dev/null || true
fi
[[ -f "$IN/test.heic" ]] && run_one "img_heic2jpg"  "$IN/test.heic" "jpeg" "libheif"

echo "Fertig."
