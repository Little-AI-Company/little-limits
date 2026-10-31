#!/bin/bash
set -euo pipefail
usage() {
  cat >&2 <<'USAGE'
Usage: compose_icon_master.sh <artwork.png> <output_1024.png> <output_256.png>
USAGE
  exit 1
}
[[ $# -eq 3 ]] || usage
command -v magick >/dev/null && command -v rsvg-convert >/dev/null || {
  printf 'compose_icon_master.sh requires ImageMagick 7 (magick) and librsvg (rsvg-convert).\n' >&2
  exit 1
}
artwork="$1"; output="$2"; preview="$3"
temporary="$(mktemp -d)"
trap 'rm -rf "$temporary"' EXIT
rgba="-define png:color-type=6"
printf '%s' '<svg xmlns="http://www.w3.org/2000/svg" width="824" height="824"><rect width="824" height="824" rx="185.4" fill="white"/></svg>' > "$temporary/body.svg"
rsvg-convert -b black "$temporary/body.svg" -o "$temporary/body-mask.png"
magick "$artwork" -resize 824x824! \( "$temporary/body-mask.png" -alpha off \) \
  -compose CopyOpacity -composite $rgba "$temporary/body.png"
magick -size 1024x1024 xc:none "$temporary/body.png" -geometry +100+100 -compose Over -composite $rgba "$temporary/placed.png"
magick "$temporary/placed.png" -alpha extract -background black -alpha shape -channel A -evaluate multiply 0.30 +channel \
  -blur 0x10 -page +0+10 -background none -flatten $rgba "$temporary/shadow.png"
magick "$temporary/shadow.png" "$temporary/placed.png" -compose Over -composite -strip $rgba -define png:compression-level=9 "$output"
magick "$output" -resize 256x256 -strip $rgba -define png:compression-level=9 "$preview"
