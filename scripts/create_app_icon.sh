#!/bin/bash
set -euo pipefail

repository_directory="$(cd "$(dirname "$0")/.." && pwd)"
source_image="${1:-$repository_directory/assets/app-icon.png}"
output_icon="${2:-$repository_directory/Resources/AppIcon.icns}"
if [[ ! -f "$source_image" ]]; then
    printf 'Icon source does not exist: %s\n' "$source_image" >&2
    exit 1
fi

temporary_directory="$(mktemp -d "${TMPDIR:-/tmp}/ai-usage-stats-icon.XXXXXX")"
trap 'rm -rf "$temporary_directory"' EXIT
iconset="$temporary_directory/AppIcon.iconset"
mkdir -p "$iconset" "$(dirname "$output_icon")"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$source_image" --out "$iconset/icon_${size}x${size}.png" >/dev/null
    doubled_size=$((size * 2))
    sips -z "$doubled_size" "$doubled_size" "$source_image" --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil --convert icns --output "$output_icon" "$iconset"
printf 'Created %s\n' "$output_icon"
