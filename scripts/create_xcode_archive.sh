#!/bin/bash
set -euo pipefail

# Wrap a previously packaged app. Xcode's archive schema is not a published API;
# keep this wrapper small and validate local export with the installed Xcode.
if [[ "$#" != 2 ]]; then
    printf 'Usage: %s application.app output.xcarchive\n' "$0" >&2
    exit 1
fi
application="${1%/}"
archive="${2%/}"
if [[ ! -d "$application" || "$application" != *.app || "$archive" != *.xcarchive ]]; then
    printf 'Provide an existing .app directory and a new .xcarchive path.\n' >&2
    exit 1
fi
if [[ -e "$archive" || -L "$archive" ]]; then
    printf 'Archive already exists: %s\n' "$archive" >&2
    exit 1
fi
application_name="$(basename "$application")"
application="$(cd "$application" && pwd -P)"
application_plist="$application/Contents/Info.plist"
package_type="$(plutil -extract CFBundlePackageType raw "$application_plist")"
if [[ "$package_type" != APPL ]]; then
    printf 'The source must be an application bundle with CFBundlePackageType APPL.\n' >&2
    exit 1
fi
bundle_identifier="$(plutil -extract CFBundleIdentifier raw "$application_plist")"
version="$(plutil -extract CFBundleShortVersionString raw "$application_plist")"
build_number="$(plutil -extract CFBundleVersion raw "$application_plist")"
display_name="$(plutil -extract CFBundleName raw "$application_plist")"
codesign --verify --deep --strict "$application"
signature_details="$(codesign --display --verbose=4 "$application" 2>&1)"
signing_identity="$(printf '%s\n' "$signature_details" | sed -n 's/^Authority=//p' | head -1)"
team_identifier="$(printf '%s\n' "$signature_details" | sed -n 's/^TeamIdentifier=//p')"

archive_parent="$(dirname "$archive")"
mkdir -p "$archive_parent"
archive_parent="$(cd "$archive_parent" && pwd -P)"
archive="$archive_parent/$(basename "$archive")"
if [[ "$archive_parent" == "$application" || "$archive_parent" == "$application/"* ]]; then
    printf 'The archive must be outside the source application.\n' >&2
    exit 1
fi
temporary_directory="$(mktemp -d "$archive_parent/.archive.XXXXXX")"
trap 'rm -rf "$temporary_directory"' EXIT
staged_archive="$temporary_directory/Application.xcarchive"
mkdir -p "$staged_archive/Products/Applications"
ditto "$application" "$staged_archive/Products/Applications/$application_name"
archive_plist="$staged_archive/Info.plist"
plutil -create xml1 "$archive_plist"
plutil -insert ArchiveVersion -integer 2 "$archive_plist"
plutil -insert CreationDate -date "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$archive_plist"
plutil -insert Name -string "$display_name" "$archive_plist"
plutil -insert SchemeName -string "$display_name" "$archive_plist"
plutil -insert ApplicationProperties -dictionary "$archive_plist"
plutil -insert ApplicationProperties.ApplicationPath -string "Applications/$application_name" "$archive_plist"
plutil -insert ApplicationProperties.CFBundleIdentifier -string "$bundle_identifier" "$archive_plist"
plutil -insert ApplicationProperties.CFBundleShortVersionString -string "$version" "$archive_plist"
plutil -insert ApplicationProperties.CFBundleVersion -string "$build_number" "$archive_plist"
if [[ -n "$signing_identity" ]]; then
    plutil -insert ApplicationProperties.SigningIdentity -string "$signing_identity" "$archive_plist"
fi
if [[ "$team_identifier" =~ ^[A-Z0-9]{10}$ ]]; then
    plutil -insert ApplicationProperties.Team -string "$team_identifier" "$archive_plist"
fi
plutil -lint "$archive_plist"
codesign --verify --deep --strict "$staged_archive/Products/Applications/$application_name"
mv "$staged_archive" "$archive"
printf 'Created %s\n' "$archive"
if [[ -n "$signing_identity" ]]; then
    printf 'Signing identity: %s\n' "$signing_identity"
else
    printf 'No certificate identity is present; distribution export requires Developer ID signing.\n'
fi
printf 'Archive creation does not upload, notarize, or publish the app.\n'
