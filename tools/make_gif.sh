#!/usr/bin/env sh
# Assemble frames saved by tools/capture.gd into docs/demo.gif (needs ffmpeg).
# Usage: tools/make_gif.sh /path/to/frames [width]
set -e
FRAMES="${1:?frames directory}"
WIDTH="${2:-640}"
OUT="$(dirname "$0")/../docs/demo.gif"
ffmpeg -y -loglevel error -framerate 30 -i "$FRAMES/f%04d.png" \
  -vf "fps=15,scale=${WIDTH}:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=128:stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=4:diff_mode=rectangle" \
  "$OUT"
echo "wrote $OUT ($(du -h "$OUT" | cut -f1))"
