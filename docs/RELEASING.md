# Local packaging and releases

The canonical packaging command is `scripts/package_app.sh`. It creates a local development bundle and archive. There is no configured public release or automatic updater.

## Local build

From the repository root:

```sh
swift test
scripts/package_app.sh
plutil -lint "dist/AI Usage Stats.app/Contents/Info.plist"
codesign --verify --deep --strict --verbose=2 "dist/AI Usage Stats.app"
lipo -archs "dist/AI Usage Stats.app/Contents/MacOS/AIUsageStats"
lipo -archs "dist/AI Usage Stats.app/Contents/MacOS/UsageCapture"
open -n "dist/AI Usage Stats.app"
```

The script builds all Release products, embeds `AIUsageStats` and the `UsageCapture` helper, generates `Resources/AppIcon.icns` if absent or older than `assets/app-icon.png` (`assets/app-icon.png` is composed from `assets/branding/nervous-gauge-artwork.png` with `swift scripts/compose_app_icon.swift`, which places the artwork in the macOS 824 px rounded-square grid), copies the license, metadata, and generated SwiftPM provider-icon resource bundle, signs the helper and bundle with the selected local identity, verifies the signature, and creates a ZIP using `ditto`.

Use the same existing code-signing certificate for successive development builds. `CODE_SIGN_IDENTITY` overrides the identity stored as a single line in the ignored `.local-signing-identity` file. List available identities with `security find-identity -v -p codesigning`, then select the intended personal development identity by its certificate hash. This file contains only a public certificate identifier, never a private key or credential. Packaging does not create certificates, change Keychain trust, or edit private-key access controls.

Without a selected identity, packaging falls back to ad hoc signing and prints a warning. Ad hoc code is identified by its changing code hash, which can invalidate a previous Keychain permission after a rebuild. Switching from ad hoc signing to a certificate can also require one explicit permission for existing items. Background checks suppress Keychain dialogs and preserve the saved sign-in when permission is unavailable. An explicit account permission action reads the existing credential without initiating OAuth sign-in or replacing the grant.

Defaults are version `0.1.0`, build `1`, bundle ID `com.parkerrex.ai-usage-stats`, macOS minimum `14.0`, and output directory `dist`. The bundle is a menu bar agent with `LSUIElement` enabled.

To override local package values:

```sh
VERSION=0.1.1 BUILD_NUMBER=2 scripts/package_app.sh
OUTPUT_DIRECTORY=/tmp/ai-usage-stats-package scripts/package_app.sh
UNIVERSAL=1 scripts/package_app.sh
```

`VERSION` must have three numeric components, `BUILD_NUMBER` must be positive, and `UNIVERSAL` must be `0` or `1`. Packaging replaces the previous app and same-version archive in the selected output directory. Quit a running development instance before replacing it.

Universal compilation targets Apple silicon and Intel. Record actual runtime checks separately; do not infer Intel or macOS 14 execution from a successful build on another machine.

## Provider menu icons

The bundle embeds `Contents/Resources/AIUsageStats_AIUsageStats.bundle`, containing `ProviderIcons/claude.png`, `ProviderIcons/codex.png`, their original SVGs, and the opencode MIT LICENSE.txt and attribution NOTICE.txt. The source resource directory is `Sources/AIUsageStats/Resources/ProviderIcons`. These pre-rendered resources require no external image converter when building or packaging.

Verify both images and attribution in the actual app bundle, not only `.build`. AppKit loads this bundle through Bundle.main before considering the SwiftPM development fallback. The PNGs contain alpha, are 96 by 96 pixels, and display at 16 by 16 points as template images.

## Capture helper location

Connecting a Claude profile copies the packaged helper to `~/Library/Application Support/AI Usage Stats/UsageCapture`. Its status-line configuration points to this stable copy, so moving the app bundle does not break capture. Keep that helper while a Claude configuration uses it.

Removing a Claude profile restores its original status-line setting only when the current setting still matches the app's installed command and options. Later user edits are preserved. Existing settings-file symlinks are preserved during installation and restoration.

Do not delete or replace a Claude configuration directory during packaging. The bundle's path and the provider's profile directory are separate resources.

The experimental Console connection keeps a separate persistent WebKit data store per app profile. Packaging does not export cookies, copy browser sessions into the bundle, or delete those stores. Console account metadata and credit observations remain local app data outside the bundle.

## Distribution boundary

Local signing, including Apple Development or ad hoc signing, verifies bundle integrity. It does not provide Developer ID trust or notarization and does not make the archive suitable for public distribution.

A future public release requires an explicitly authorized distribution procedure, a Developer ID signature, notarization, verification of the final archive, and runtime evidence. Do not describe current local archives as signed and notarized downloads. Keep certificates, private keys, credentials, and private account data out of the repository and bundle.

Record exact commands, results, artifact version, tested source revision, OS, and limits in [VALIDATION.md](VALIDATION.md) before claiming a release was verified.
