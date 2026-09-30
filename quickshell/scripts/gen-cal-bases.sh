#!/usr/bin/env bash
# Import the CLEAN calendar background images (artwork + "SUN..SAT" header, day
# numbers already removed) into assets/cal/ for CornerHud.qml, which overlays the
# correct, year-aware numbers at runtime. Numbers are NEVER baked → no yearly redo.
#
# Source: clean PNGs named month{1..12}.png (default ~/Downloads/new_calendar).
# Re-encoded to JPEG q92 — at the HUD's ~180px display width this is visually
# identical to the source PNG but keeps the dir ~8MB instead of ~96MB.
#
# Grid geometry, measured on the 1408x3054 clean template (mirrored as fractions
# in CornerHud.qml so it is resolution-independent):
#   column (Sun..Sat) centre, fraction of width  = 0.16889 + i*0.11243  (i=0..6)
#   week-row centre,          fraction of height  = 0.76752 + w*0.03222  (w=0..5)
set -e
SRC="${1:-$HOME/Downloads/new_calendar}"
OUT="$(dirname "$0")/../assets/cal"
mkdir -p "$OUT"
for n in $(seq 1 12); do
  in="$SRC/month$n.png"
  [ -f "$in" ] || { echo "skip month$n (no $in)"; continue; }
  magick "$in" -quality 92 "$OUT/month$n.jpg"
  echo "wrote $OUT/month$n.jpg"
done
