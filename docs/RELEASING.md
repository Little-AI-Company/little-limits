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

The script builds all Release products, embeds `AIUsageStats` and the `UsageCapture` helper, generates `Resources/AppIcon.icns` if absent or older than `assets/app-icon.png`, copies the license and metadata, signs the helper and bundle ad hoc, verifies the signature, and creates a ZIP using `ditto`.

Defaults are version `0.1.0`, build `1`, bundle ID `com.parkerrex.ai-usage-stats`, macOS minimum `14.0`, and output directory `dist`. The bundle is a menu bar agent with `LSUIElement` enabled.

To override local package values:

```sh
VERSION=0.1.1 BUILD_NUMBER=2 scripts/package_app.sh
OUTPUT_DIRECTORY=/tmp/ai-usage-stats-package scripts/package_app.sh
UNIVERSAL=1 scripts/package_app.sh
```

`VERSION` must have three numeric components, `BUILD_NUMBER` must be positive, and `UNIVERSAL` must be `0` or `1`. Packaging replaces the previous app and same-version archive in the selected output directory. Quit a running development instance before replacing it.

Universal compilation targets Apple silicon and Intel. Record actual runtime checks separately; do not infer Intel or macOS 14 execution from a successful build on another machine.

## Capture helper location

Connecting a Claude profile copies the packaged helper to `~/Library/Application Support/AI Usage Stats/UsageCapture`. Its status-line configuration points to this stable copy, so moving the app bundle does not break capture. Keep that helper while a Claude configuration uses it.

Removing a Claude profile restores its original status-line setting only when the current setting still matches the app's installed command and options. Later user edits are preserved. Existing settings-file symlinks are preserved during installation and restoration.

Do not delete or replace a Claude configuration directory during packaging. The bundle's path and the provider's profile directory are separate resources.

The experimental Console connection keeps a separate persistent WebKit data store per app profile. Packaging does not export cookies, copy browser sessions into the bundle, or delete those stores. Console account metadata and credit observations remain local app data outside the bundle.

## Distribution boundary

Ad hoc signing verifies local bundle integrity. It does not provide Developer ID trust or notarization and does not make the archive suitable for public distribution.

A future public release requires an explicitly authorized distribution procedure, a Developer ID signature, notarization, verification of the final archive, and runtime evidence. Do not describe current local archives as signed and notarized downloads. Keep certificates, private keys, credentials, and private account data out of the repository and bundle.

Record exact commands, results, artifact version, tested source revision, OS, and limits in [VALIDATION.md](VALIDATION.md) before claiming a release was verified.
