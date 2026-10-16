#!/bin/bash
# Builds a macOS .icns from two 1024 px masters already placed on the app icon grid.
# Usage: create_app_icon.sh <master.png> <small_master.png> <output.icns>
# The small master fills the 16 and 32 px slots, where the detailed master does not read.
# Every other slot, from 64 to 1024 px, is resized from the detailed master.
set -euo pipefail

if [[ $# -ne 3 ]]; then
    printf 'usage: create_app_icon.sh <master.png> <small_master.png> <output.icns>\n' >&2
    exit 64
fi
master="$1"; small_master="$2"; output_icon="$3"
for source_image in "$master" "$small_master"; do
    if [[ ! -f "$source_image" ]]; then
        printf 'Icon source does not exist: %s\n' "$source_image" >&2
        exit 1
    fi
done

temporary_directory="$(mktemp -d "${TMPDIR:-/tmp}/limits-left-icon.XXXXXX")"
trap 'rm -rf "$temporary_directory"' EXIT
iconset="$temporary_directory/AppIcon.iconset"
mkdir -p "$iconset" "$(dirname "$output_icon")"
# Slot name, pixel size, source.
while read -r slot pixels source_image; do
    sips -z "$pixels" "$pixels" "$source_image" --out "$iconset/$slot.png" >/dev/null
done <<SLOTS
icon_16x16 16 $small_master
icon_16x16@2x 32 $small_master
icon_32x32 32 $small_master
icon_32x32@2x 64 $master
icon_128x128 128 $master
icon_128x128@2x 256 $master
icon_256x256 256 $master
icon_256x256@2x 512 $master
icon_512x512 512 $master
icon_512x512@2x 1024 $master
SLOTS
iconutil --convert icns --output "$output_icon" "$iconset"
printf 'Created %s\n' "$output_icon"
