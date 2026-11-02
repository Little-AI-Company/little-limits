#!/bin/bash
set -euo pipefail

if [[ "$#" != 1 || ! "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    printf 'Usage: %s <version>, for example 0.3.1\n' "$0" >&2
    exit 1
fi
version="$1"
repository_directory="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repository_directory"
release_directory="$repository_directory/dist/release"
signing_identity="${CODE_SIGN_IDENTITY:-Developer ID Application: RAPTURE ENTERTAINERS, INC. (9FL5S77YVH)}"
download_url='https://github.com/Little-AI-Company/little-limits/releases/download/v#{version}/Little-Limits-#{version}.zip'
fail() {
    printf '%s\n' "$1" >&2
    exit 1
}

[[ "$(uname -s)" == Darwin ]] || fail 'Run this on the Mac that signs releases (the M4).'
[[ -n "${NOTARY_PROFILE:-}" || -f build/XcodeUploadOptions.plist ]] ||
    fail 'Set NOTARY_PROFILE to a saved notarytool profile, or create build/XcodeUploadOptions.plist (docs/RELEASING.md).'
git fetch --quiet origin main
[[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/main)" ]] || fail 'HEAD must be the current origin/main.'
[[ -z "$(git status --porcelain)" ]] || fail 'The working tree must be clean.'
grep -qF "## $version (" CHANGELOG.md || fail "CHANGELOG.md has no $version section. Write and land it first (.agents/skills/changelog/SKILL.md)."
current_version="$(plutil -extract CFBundleShortVersionString raw Resources/Info.plist)"
[[ "$current_version" != "$version" && "$(printf '%s\n%s\n' "$current_version" "$version" | sort -V | tail -1)" == "$version" ]] ||
    fail "$version must be newer than $current_version."
base_commit="$(git rev-parse HEAD)"
build_number=$(($(plutil -extract CFBundleVersion raw Resources/Info.plist) + 1))

trap 'git checkout --quiet -- Resources/Info.plist' EXIT
sed -i.bak -E \
    -e "/CFBundleShortVersionString/{n;s|<string>.*</string>|<string>$version</string>|;}" \
    -e "/<key>CFBundleVersion</{n;s|<string>.*</string>|<string>$build_number</string>|;}" \
    Resources/Info.plist
rm -f Resources/Info.plist.bak
[[ "$(plutil -extract CFBundleShortVersionString raw Resources/Info.plist)" == "$version" &&
    "$(plutil -extract CFBundleVersion raw Resources/Info.plist)" == "$build_number" ]] || fail 'Could not set the version in Resources/Info.plist.'

rm -rf "$release_directory"
DISTRIBUTION=1 UNIVERSAL=1 CODE_SIGN_IDENTITY="$signing_identity" OUTPUT_DIRECTORY="$release_directory" scripts/package_app.sh
application="$release_directory/Little Limits.app"
if [[ -z "${NOTARY_PROFILE:-}" ]]; then
    archive_path="$release_directory/Little Limits.xcarchive"
    scripts/create_xcode_archive.sh "$application" "$archive_path"
    xcodebuild -exportArchive -archivePath "$archive_path" -exportPath "$release_directory/upload" -exportOptionsPlist build/XcodeUploadOptions.plist
    for attempt in $(seq 1 60); do
        if export_output="$(xcodebuild -exportNotarizedApp -archivePath "$archive_path" -exportPath "$release_directory/notarized" 2>&1)"; then
            break
        fi
        grep -q 'is processing and not ready' <<<"$export_output" || fail "$export_output"
        [[ "$attempt" != 60 ]] || fail 'Apple has not finished notarizing after 30 minutes. Run this again later.'
        printf 'Apple is still notarizing the upload; checking again in 30 seconds (%s of 60).\n' "$attempt"
        sleep 30
    done
    application="$release_directory/notarized/Little Limits.app"
fi

codesign --verify --deep --strict --verbose=2 "$application"
xcrun stapler validate "$application"
spctl --assess --type execute --verbose=2 "$application"
lipo -verify_arch "$application/Contents/MacOS/AIUsageStats" arm64 x86_64
lipo -verify_arch "$application/Contents/MacOS/UsageCapture" arm64 x86_64
lipo -verify_arch "$application/Contents/Helpers/little-limits" arm64 x86_64
[[ "$(plutil -extract CFBundleShortVersionString raw "$application/Contents/Info.plist")" == "$version" ]] || fail "The app is not version $version."
archive="$release_directory/Little-Limits-$version.zip"
rm -f "$archive"
ditto -c -k --keepParent "$application" "$archive"
sha256="$(shasum -a 256 "$archive" | cut -d' ' -f1)"
notes="$release_directory/notes.md"
{
    awk -v heading="## $version (" 'index($0, heading) == 1 { found = 1; next } found && /^## / { exit } found && (started || NF) { started = 1; print }' CHANGELOG.md
    # shellcheck disable=SC2016
    printf '\nSHA-256 of Little-Limits-%s.zip: `%s`. Signed with Developer ID and notarized by Apple.\n' "$version" "$sha256"
} >"$notes"

git commit --quiet -am "release: $version" -m "Raises the version to $version (build $build_number)."
scripts/push_main.sh
release_commit="$(git rev-parse HEAD)"
[[ "$(git rev-parse HEAD^)" == "$base_commit" ]] || fail "main moved while building. $release_commit is landed but $archive was built from $base_commit; run this again."

sed_script="s/^( *version ).*/\\1\"$version\"/;s/^( *sha256 ).*/\\1\"$sha256\"/"
printf '\nLittle Limits %s (build %s) is built, notarized and landed on main as %s.\nArtifact: %s\nSHA-256: %s\n' "$version" "$build_number" "$release_commit" "$archive" "$sha256"
printf '\nParker, step 1. Publish the release:\n\n'
printf "gh release create v%s '%s' --repo Little-AI-Company/little-limits --target %s --title 'Little Limits %s' --notes-file '%s'\n" "$version" "$archive" "$release_commit" "$version" "$notes"
printf '\nStep 2. Casks/little-limits.rb needs exactly these lines:\n\n  version "%s"\n  sha256 "%s"\n  url "%s"\n' "$version" "$sha256" "$download_url"
printf '\nThe url line stays as it is. Apply it and push the tap:\n\n'
printf "cd \"\$(brew --repository parkerrex/tap)\" && git pull -q --ff-only && grep -qF '%s' Casks/little-limits.rb && sed -i '' -E '%s' Casks/little-limits.rb && git commit -qam 'little-limits %s' && git push\n" "$download_url" "$sed_script" "$version"
