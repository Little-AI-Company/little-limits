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
distribution="${DISTRIBUTION:-0}"

if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ || ! "$build_number" =~ ^[1-9][0-9]*$ ]]; then
    printf 'VERSION must contain three numeric components; BUILD_NUMBER must be a positive integer.\n' >&2
    exit 1
fi
if [[ "$universal" != 0 && "$universal" != 1 ]]; then
    printf 'UNIVERSAL must be 0 or 1.\n' >&2
    exit 1
fi
if [[ "$distribution" != 0 && "$distribution" != 1 ]]; then
    printf 'DISTRIBUTION must be 0 or 1.\n' >&2
    exit 1
fi
if [[ "$distribution" == 1 ]]; then
    # Accept a certificate hash or name; distribution needs the Developer ID Application certificate.
    identity_name="$(security find-identity -v -p codesigning | awk -v identity="$signing_identity" \
        '$2 == identity { line = $0; sub(/^[^"]*"/, "", line); sub(/"$/, "", line); print line }')"
    identity_name="${identity_name:-$signing_identity}"
    if [[ "$identity_name" != 'Developer ID Application:'* ]]; then
        printf 'DISTRIBUTION=1 requires a Developer ID Application signing identity.\n' >&2
        exit 1
    fi
fi

build_arguments=(-c release)
# SwiftPM's default build system records SDK 14.0 in the binary, which makes current
# macOS keep the pre-Liquid Glass appearance. Record the SDK actually used to build.
sdk_version="$(xcrun --sdk macosx --show-sdk-version)"
build_arguments+=(-Xlinker -platform_version -Xlinker macos -Xlinker 14.0 -Xlinker "$sdk_version")
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
# Distribution builds use hardened runtime and a secure timestamp, which notarization requires.
signing_arguments=(--force --sign "$signing_identity")
if [[ "$distribution" == 1 ]]; then
    signing_arguments+=(--options runtime --timestamp)
else
    signing_arguments+=(--timestamp=none)
fi
codesign "${signing_arguments[@]}" "$application/Contents/MacOS/UsageCapture"
codesign "${signing_arguments[@]}" "$application"
codesign --verify --deep --strict --verbose=2 "$application"
if [[ "$distribution" == 1 && -n "${NOTARY_PROFILE:-}" ]]; then
    submission_archive="$temporary_directory/notarization.zip"
    ditto -c -k --keepParent "$application" "$submission_archive"
    xcrun notarytool submit "$submission_archive" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$application"
    xcrun stapler validate "$application"
    spctl --assess --type execute --verbose=2 "$application"
fi

destination="$output_directory/AI Usage Stats.app"
if [[ -e "$destination" ]]; then
    rm -rf "$destination"
fi
mv "$application" "$destination"
archive="$output_directory/AI-Usage-Stats-$version.zip"
ditto -c -k --keepParent "$destination" "$archive"
printf 'Packaged %s\nArchive: %s\n' "$destination" "$archive"
if [[ "$distribution" != 1 ]]; then
    printf 'Local development build only. This archive is not a notarized public release.\n'
elif [[ -z "${NOTARY_PROFILE:-}" ]]; then
    printf 'Developer ID signed with hardened runtime, not yet notarized. Notarize through Xcode with scripts/create_xcode_archive.sh (see docs/RELEASING.md) or set NOTARY_PROFILE.\n'
fi
if [[ "$signing_identity" == - ]]; then
    printf 'Ad hoc signing changes Keychain identity when code changes. Set CODE_SIGN_IDENTITY or .local-signing-identity for stable local access.\n'
fi
