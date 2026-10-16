#!/bin/bash
# Places full-bleed square icon artwork on the macOS app icon grid.
# Usage: compose_icon.sh <artwork.png> <output_1024.png> <output_256.png>
# Result: 1024 px transparent canvas, 824 px rounded-square body inset 100 px with a
# 185.4 px corner radius, and a drop shadow 10 px down, 10 px blur, 30 percent black.
# Requires ImageMagick 7 (magick) and librsvg (rsvg-convert).
set -euo pipefail
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
