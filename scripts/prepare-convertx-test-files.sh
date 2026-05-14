#!/usr/bin/env bash
# Erzeugt kleine Testdateien fuer manuelle ConvertX/Stirling-Tests.
# Nutzt Tools aus dem ConvertX-Container, damit auf dem Host nichts installiert sein muss.
set -euo pipefail
cd "$(dirname "$0")/.."

OUT="data/convertx-test/input"
mkdir -p "$OUT" "data/convertx-test/output"

run_in_convertx() {
  docker exec -w /work filehub-convertx sh -c "$1"
}

# Mounten geht via docker exec nicht; stattdessen kleine Dateien im Container erzeugen
# und mit docker cp herausholen.
TMP="/tmp/convertx-prep"
docker exec filehub-convertx sh -c "rm -rf $TMP && mkdir -p $TMP"

echo "[1/8] PNG-Testbild"
docker exec filehub-convertx sh -c "magick -size 320x240 gradient:blue-red -pointsize 24 -gravity center -annotate 0 'Filehub Test' $TMP/test.png"

echo "[2/8] JPG-Testbild"
docker exec filehub-convertx sh -c "magick $TMP/test.png $TMP/test.jpg"

echo "[3/8] PDF"
docker exec filehub-convertx sh -c "echo 'Filehub Test PDF\nZeile zwei' | enscript -p - 2>/dev/null | ps2pdf - $TMP/test.pdf 2>/dev/null || magick -size 600x800 xc:white -pointsize 30 -gravity center -annotate 0 'Filehub Test PDF' $TMP/test.pdf"

echo "[4/8] TXT + Markdown + CSV"
docker exec filehub-convertx sh -c "printf 'Filehub Test\nZeile zwei\nUmlaute: aeoeuess\n' > $TMP/test.txt"
docker exec filehub-convertx sh -c "printf '# Filehub Test\n\n* eins\n* zwei\n\n**fett**\n' > $TMP/test.md"
docker exec filehub-convertx sh -c "printf 'a,b,c\n1,2,3\n4,5,6\n' > $TMP/test.csv"

echo "[5/8] DOCX (via Pandoc)"
docker exec filehub-convertx sh -c "pandoc $TMP/test.md -o $TMP/test.docx" || echo "WARN: DOCX fehlgeschlagen"

echo "[6/8] WAV (1s Sinus)"
docker exec filehub-convertx sh -c "ffmpeg -y -hide_banner -loglevel error -f lavfi -i 'sine=frequency=440:duration=1' -ac 1 -ar 22050 $TMP/test.wav"

echo "[7/8] MP4 (2s, 320x240, 10fps)"
docker exec filehub-convertx sh -c "ffmpeg -y -hide_banner -loglevel error -f lavfi -i 'testsrc=duration=2:size=320x240:rate=10' -pix_fmt yuv420p $TMP/test.mp4"

echo "[8/8] SVG"
docker exec filehub-convertx sh -c "cat > $TMP/test.svg <<EOF
<svg xmlns='http://www.w3.org/2000/svg' width='200' height='100'>
  <rect width='200' height='100' fill='lightblue'/>
  <text x='100' y='55' text-anchor='middle' font-size='20'>Filehub</text>
</svg>
EOF"

for f in test.png test.jpg test.pdf test.txt test.md test.csv test.docx test.wav test.mp4 test.svg; do
  docker cp "filehub-convertx:$TMP/$f" "$OUT/$f" 2>/dev/null || echo "WARN: $f nicht kopiert"
done

docker exec filehub-convertx sh -c "rm -rf $TMP"

echo
echo "Testdateien in $OUT:"
ls -lh "$OUT" | tail -n +2
