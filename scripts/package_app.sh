#!/bin/bash
set -euo pipefail

repository_directory="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repository_directory"
output_directory="${OUTPUT_DIRECTORY:-$repository_directory/dist}"
version="${VERSION:-$(plutil -extract CFBundleShortVersionString raw Resources/Info.plist)}"
build_number="${BUILD_NUMBER:-$(plutil -extract CFBundleVersion raw Resources/Info.plist)}"
universal="${UNIVERSAL:-0}"
signing_identity="${CODE_SIGN_IDENTITY:-}"
if [[ -z "$signing_identity" && -f .local-signing-identity ]]; then
    IFS= read -r signing_identity < .local-signing-identity || [[ -n "$signing_identity" ]]
fi
signing_identity="${signing_identity:--}"

if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ || ! "$build_number" =~ ^[1-9][0-9]*$ ]]; then
    printf 'VERSION must contain three numeric components; BUILD_NUMBER must be a positive integer.\n' >&2
    exit 1
fi
if [[ "$universal" != 0 && "$universal" != 1 ]]; then
    printf 'UNIVERSAL must be 0 or 1.\n' >&2
    exit 1
fi

build_arguments=(-c release)
if [[ "$universal" == 1 ]]; then
    build_arguments+=(--arch arm64 --arch x86_64)
fi
swift build "${build_arguments[@]}"
binary_directory="$(swift build "${build_arguments[@]}" --show-bin-path)"
if [[ ! -f Resources/AppIcon.icns || assets/app-icon.png -nt Resources/AppIcon.icns ]]; then
    scripts/create_app_icon.sh
fi

mkdir -p "$output_directory"
temporary_directory="$(mktemp -d "$output_directory/.package.XXXXXX")"
trap 'rm -rf "$temporary_directory"' EXIT
application="$temporary_directory/AI Usage Stats.app"
mkdir -p "$application/Contents/MacOS" "$application/Contents/Resources"
install -m 755 "$binary_directory/AIUsageStats" "$application/Contents/MacOS/AIUsageStats"
install -m 755 "$binary_directory/UsageCapture" "$application/Contents/MacOS/UsageCapture"
cp Resources/Info.plist "$application/Contents/Info.plist"
cp Resources/AppIcon.icns "$application/Contents/Resources/AppIcon.icns"
cp LICENSE "$application/Contents/Resources/LICENSE.txt"
cp -R "$binary_directory/AIUsageStats_AIUsageStats.bundle" "$application/Contents/Resources/AIUsageStats_AIUsageStats.bundle"
plutil -replace CFBundleShortVersionString -string "$version" "$application/Contents/Info.plist"
plutil -replace CFBundleVersion -string "$build_number" "$application/Contents/Info.plist"
plutil -lint "$application/Contents/Info.plist"
codesign --force --sign "$signing_identity" --timestamp=none "$application/Contents/MacOS/UsageCapture"
codesign --force --sign "$signing_identity" --timestamp=none "$application"
codesign --verify --deep --strict --verbose=2 "$application"

destination="$output_directory/AI Usage Stats.app"
if [[ -e "$destination" ]]; then
    rm -rf "$destination"
fi
mv "$application" "$destination"
archive="$output_directory/AI-Usage-Stats-$version.zip"
ditto -c -k --keepParent "$destination" "$archive"
printf 'Packaged %s\nArchive: %s\n' "$destination" "$archive"
printf 'Local development build only. This archive is not a notarized public release.\n'
if [[ "$signing_identity" == - ]]; then
    printf 'Ad hoc signing changes Keychain identity when code changes. Set CODE_SIGN_IDENTITY or .local-signing-identity for stable local access.\n'
fi
