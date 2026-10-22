# Local packaging and releases

The canonical packaging command is `scripts/package_app.sh`. It creates a local development bundle and archive. Public releases follow [Public release](#public-release); there is no automatic updater.

## Local build

From the repository root:

```sh
swift test
scripts/package_app.sh
plutil -lint "dist/Little Limits.app/Contents/Info.plist"
codesign --verify --deep --strict --verbose=2 "dist/Little Limits.app"
lipo -archs "dist/Little Limits.app/Contents/MacOS/AIUsageStats"
lipo -archs "dist/Little Limits.app/Contents/MacOS/UsageCapture"
open -n "dist/Little Limits.app"
```

The script builds all Release products, embeds `AIUsageStats` and the `UsageCapture` helper, builds the app icons (see [App icons](#app-icons)), copies the license, metadata, and generated SwiftPM provider-icon resource bundle, signs the helper and bundle with the selected local identity, verifies the signature, and creates a ZIP using `ditto`.

Use the same existing code-signing certificate for successive development builds. `CODE_SIGN_IDENTITY` overrides the identity stored as a single line in the ignored `.local-signing-identity` file. List available identities with `security find-identity -v -p codesigning`, then select the intended personal development identity by its certificate hash. This file contains only a public certificate identifier, never a private key or credential. Packaging does not create certificates, change Keychain trust, or edit private-key access controls.

Without a selected identity, packaging falls back to ad hoc signing and prints a warning. Ad hoc code is identified by its changing code hash, which can invalidate a previous Keychain permission after a rebuild. Switching from ad hoc signing to a certificate can also require one explicit permission for existing items. Background checks suppress Keychain dialogs and preserve the saved sign-in when permission is unavailable. An explicit account permission action reads the existing credential without initiating OAuth sign-in or replacing the grant.

Version and build default to `CFBundleShortVersionString` and `CFBundleVersion` in `Resources/Info.plist`. Raise both for each public release; build numbers only increase (0.1.0 shipped as build 2, 0.2.0 as build 3). Other defaults are bundle ID `com.parkerrex.ai-usage-stats` (kept from the app's first name, AI Usage Stats; see [Names](#names)), macOS minimum `14.0`, and output directory `dist`. The bundle is a menu bar agent with `LSUIElement` enabled.

To override local package values:

```sh
VERSION=0.2.1 BUILD_NUMBER=4 scripts/package_app.sh
OUTPUT_DIRECTORY=/tmp/little-limits-package scripts/package_app.sh
UNIVERSAL=1 scripts/package_app.sh
```

`VERSION` must have three numeric components, `BUILD_NUMBER` must be positive, and `UNIVERSAL` must be `0` or `1`. Packaging replaces the previous app and same-version archive in the selected output directory. Quit a running development instance before replacing it.

Universal compilation targets Apple silicon and Intel. Record actual runtime checks separately; do not infer Intel or macOS 14 execution from a successful build on another machine.

## App icons

The bundle icon is Paper. Night is an alternate that the running app shows when the person picks it in Settings; see [NATIVE-DESIGN.md](NATIVE-DESIGN.md). Every master is a 1024 px PNG already placed on the macOS icon grid by `scripts/compose_icon_master.sh` from the full-bleed artwork in `assets/branding/app-icon/artwork/`. See [assets/branding/README.md](../assets/branding/README.md) for how the artwork was made.

| Output | 64 to 1024 px slots | 16 and 32 px slots |
| --- | --- | --- |
| `Resources/AppIcon.icns` (bundle icon, `CFBundleIconFile`) | `assets/app-icon.png` (Paper) | `assets/branding/app-icon/paper-small.png` |
| `Resources/AppIconNight.icns` | `assets/branding/app-icon/night.png` | `assets/branding/app-icon/night-small.png` |

`scripts/create_app_icon.sh <master.png> <small_master.png> <output.icns>` resizes each slot with `sips` into an `AppIcon.iconset` and runs `iconutil`. The small master is a simplified drawing with three ticks, a thick needle, and larger eyes, which stays readable where the detailed master blurs; it fills `icon_16x16`, `icon_16x16@2x`, and `icon_32x32`. Packaging rebuilds an `.icns` when it is missing or older than one of its masters, then copies both into `Contents/Resources`. The output is byte-for-byte reproducible from the same masters. To inspect a packaged icon:

```sh
iconutil -c iconset -o /tmp/AppIcon.iconset "dist/Little Limits.app/Contents/Resources/AppIcon.icns"
sips -g pixelWidth /tmp/AppIcon.iconset/*.png
```

The website favicons, touch icon, header lockups, and social image are copies of the same artwork; [website/README.md](../website/README.md) lists their sources.

## Provider menu icons

The bundle embeds `Contents/Resources/AIUsageStats_AIUsageStats.bundle`, containing `ProviderIcons/claude.png`, `ProviderIcons/codex.png`, their original SVGs, and the opencode MIT LICENSE.txt and attribution NOTICE.txt. The source resource directory is `Sources/AIUsageStats/Resources/ProviderIcons`. These pre-rendered resources require no external image converter when building or packaging.

Verify both images and attribution in the actual app bundle, not only `.build`. AppKit loads this bundle through Bundle.main before considering the SwiftPM development fallback. The PNGs contain alpha, are 96 by 96 pixels, and display at 16 by 16 points as template images.

## Capture helper location

Connecting a Claude profile copies the packaged helper to `~/Library/Application Support/AI Usage Stats/UsageCapture`. The folder keeps the app's earlier name so existing capture configurations keep working. Its status-line configuration points to this stable copy, so moving the app bundle does not break capture. Keep that helper while a Claude configuration uses it.

Removing a Claude profile restores its original status-line setting only when the current setting still matches the app's installed command and options. Later user edits are preserved. Existing settings-file symlinks are preserved during installation and restoration.

Do not delete or replace a Claude configuration directory during packaging. The bundle's path and the provider's profile directory are separate resources.

The experimental Console connection keeps a separate persistent WebKit data store per app profile. Packaging does not export cookies, copy browser sessions into the bundle, or delete those stores. Console account metadata and credit observations remain local app data outside the bundle.

## Public release

Public releases are signed with the Developer ID Application certificate of RAPTURE ENTERTAINERS, INC. (team `9FL5S77YVH`), notarized by Apple, and published as a GitHub release and a Homebrew cask in `ParkerRex/homebrew-tap`. Local Apple Development or ad hoc builds are never published.

1. Build the universal, hardened-runtime package from a clean `main` commit whose `Check` passed in CI:

   ```sh
   DISTRIBUTION=1 UNIVERSAL=1 \
     CODE_SIGN_IDENTITY='Developer ID Application: RAPTURE ENTERTAINERS, INC. (9FL5S77YVH)' \
     OUTPUT_DIRECTORY="$PWD/dist/release" scripts/package_app.sh
   ```

   `DISTRIBUTION=1` refuses any identity other than Developer ID Application and signs the helper and app with `--options runtime --timestamp`. With `NOTARY_PROFILE` set to a saved `xcrun notarytool store-credentials` profile, the script also notarizes, staples, validates, and runs a Gatekeeper assessment before creating the final archive.

2. Without a notary profile, notarize through the Xcode account that is signed in to the release team. Wrap the signed app, upload it, and export the notarized app after Apple accepts it:

   ```sh
   scripts/create_xcode_archive.sh 'dist/release/Little Limits.app' 'dist/release/Little Limits.xcarchive'
   xcodebuild -exportArchive -archivePath 'dist/release/Little Limits.xcarchive' \
     -exportPath dist/release/upload -exportOptionsPlist build/XcodeUploadOptions.plist
   xcodebuild -exportNotarizedApp -archivePath 'dist/release/Little Limits.xcarchive' -exportPath dist/release/notarized
   ```

   `build/XcodeUploadOptions.plist` (ignored) sets `method` `developer-id`, `destination` `upload`, `signingStyle` `manual`, `signingCertificate` to the certificate SHA-1, and `teamID` `9FL5S77YVH`. Upload success is not acceptance; `-exportNotarizedApp` succeeds only after Apple accepts the submission.

3. Verify the notarized app before archiving it: `codesign --verify --deep --strict`, `xcrun stapler validate`, `spctl --assess --type execute --verbose=2`, and `lipo -archs` on both executables. Create the release archive with `ditto -c -k --keepParent` and record its `shasum -a 256`.

4. Publish the archive as `Little-Limits-<version>.zip` on a `v<version>` GitHub release, then update the cask in `ParkerRex/homebrew-tap` with the version and SHA-256. Install with `brew install --cask parkerrex/tap/<cask>` on a clean account to confirm. The cask is `Casks/little-limits.rb`.

5. Add the version to `CHANGELOG.md` and `website/changelog/index.html` with the [changelog skill](../.agents/skills/changelog/SKILL.md), in the release PR or right after it. Keep the GitHub release notes in line with it.

Keep certificates, private keys, notarization credentials, and private account data out of the repository and bundle. Changing the signing team from a local development identity to the release team can make macOS ask once for access to saved Keychain sign-ins.

Record exact commands, results, artifact version, tested source revision, OS, and limits in [VALIDATION.md](VALIDATION.md) before claiming a release was verified.

## Names

The app was published as AI Usage Stats through 0.2.0 and as Limits Left in 0.2.1. It is now Little Limits, part of the little family with Little Worker and Little CI. The bundle `Little Limits.app`, the archive `Little-Limits-<version>.zip`, the cask `little-limits`, and the repository `Little-AI-Company/little-limits` carry the current name. GitHub redirects the old `ParkerRex/little-limits`, `ParkerRex/limits-left`, and `ParkerRex/ai-usage-stats` URLs, including release downloads, as long as no new repository takes those names. Link to `Little-AI-Company/little-limits` in new docs, pages, and the cask. The site stays on limitsleft.com until a family domain replaces it.

These names stay the same on purpose:

- Bundle ID `com.parkerrex.ai-usage-stats`. Saved Keychain sign-ins, preferences, the login item, and the Claude Platform WebKit data are bound to it.
- The Keychain service `AI Usage Stats Claude OAuth`, which holds saved Claude sign-ins.
- The data folder `~/Library/Application Support/AI Usage Stats` and the helper at `~/Library/Application Support/AI Usage Stats/UsageCapture`. Usage history lives in the folder, and Claude status-line configurations point to the helper.
- Swift target, product, module, and executable names (`AIUsageStats`, `UsageCore`, and the others).

### Rename to Little Limits

Steps for the first release as Little Limits, in addition to [Public release](#public-release). The 0.2.1 rename to Limits Left used the same steps; its evidence is in [VALIDATION.md](VALIDATION.md).

1. Build, notarize, and verify as usual. Publish `Little-Limits-<version>.zip` on the `v<version>` GitHub release.
2. In `ParkerRex/homebrew-tap`, add `Casks/little-limits.rb`. Copy `Casks/limits-left.rb` and change only the token to `little-limits`, `version`, `sha256`, the `url` file name to `Little-Limits-#{version}.zip`, the `url` and `homepage` repository to `Little-AI-Company/little-limits`, `name` to `Little Limits`, and the artifact to `app "Little Limits.app"`. Keep `uninstall quit: "com.parkerrex.ai-usage-stats"` and the same `zap trash` paths.
3. In the same tap commit, delete `Casks/limits-left.rb` and set `cask_renames.json` to `{"ai-usage-stats": "little-limits", "limits-left": "little-limits"}`, so `brew upgrade` moves existing installs to the new token.
4. Confirm on a Mac that has `parkerrex/tap/limits-left` 0.2.1 installed: `brew update && brew upgrade --cask` replaces `Limits Left.app` with `Little Limits.app`, saved accounts and history are still present without a new sign-in, Claude capture still updates, and Launch at login keeps its setting. Then confirm `brew install --cask parkerrex/tap/little-limits` on a clean account.
5. If you installed by hand, quit **Limits Left** and move it to the Trash after you install Little Limits. Say this in the release notes.
