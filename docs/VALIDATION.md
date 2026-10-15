# Validation

This file records observed results, not intended behavior. Update the tested revision and relevant checks when the implementation changes.

## README screenshot refresh, October 13, 2026

Captured the packaged app matching `d22cc5a1fdc50229f428802426d708dbfa34afbc` on macOS 27.0.1 through Computer: real connected-account overview and App Settings, each 1400 × 1136 pixels. Replaced the generated README header with the account capture and added the settings capture. The user requested actual product content; captures retain the displayed account email, subscription reading, inactive windows, and unavailable credit states. No values were fabricated, cropped, or retouched. Computer returned JPEG bytes; macOS `sips -s format png` exported them to PNG. Text/EXIF chunks were removed without changing the compressed image payload. No credentials were visible. No sign-in, stored balance, or login setting was changed.

Both final captures were visually inspected for complete rendering. One intermediate account capture lacked its detail region and was replaced after recapture. Native menu capture timed out; the older menu asset is omitted from the README. PNG signatures, chunk checksums, dimensions, metadata removal with unchanged image payload, and both README image references passed. `git diff --check` passed. Swift tests, Release build, and packaging were not repeated for this documentation/assets-only change; the already packaged app was used. No additional runtime or accessibility claim is made from these images.

## Account sidebar and direct actions, October 13, 2026

Final tested code/test source SHA-256: `30a7879991f989bb11633bb160b5b42846e54b1af97ee97cc1ab72fb93e55661`; pre-review source was `ad51ec5f48608b024208d807b6b87e5f4686c1fc4cf5e46928adf1b9fcf7c23b`; visual checks used equivalent source before an EOF whitespace correction (`1170c79a56ae4c5bb7e45aee25aa7b65339122a01fb5270cfb00e3a4bbff11c2`) (the earlier integrated source before the zero-quota demo fixture was `6291a7b056477ccf94d17db3f7a885fdd00ca0f626471c08d832adfa0ed15ec0`), using the path/NUL/content/NUL procedure below. Baseline `9309a7f26139ffae21545240fd60196186258277` was inspected live: sidebar rows contained only identity/provider, and the Account dropdown mixed details, reconnect, Platform, billing, and removal. The revised sidebar shows complete current remaining quota with green above 20%, orange at 10% through 20%, and red below 10%. Unknown, inactive, stale, unavailable, and sign-in states are neutral. Quota zero, threshold boundaries, inactive exclusion, missing/nonfinite percentages, missing/future observation time, five-minute/reset expiry, mismatched account UUID, and credit exclusion are covered by eight focused contracts. The test-first invocation initially failed compilation because the new summary type did not yet exist; this was not an observed behavioral assertion failure on the old implementation.

- `swift test`: passed 58 tests (21 XCTest and 37 Swift Testing), zero failures. Eight new quota contracts include parameterized inputs.
- `swift build -c release`: passed for the final demo source (13.64 seconds); existing Keychain deprecation warnings retained.
- `scripts/package_app.sh`: passed with the configured local signer. Packaged app inspected with Computer on Apple silicon, macOS 27.0.1 (26A434), Apple Swift 6.4.
- Demo pointer/AX/screenshots verified green and orange quota rows, neutral missing readings, missing email fallback, long-email truncation with full identity available, direct account buttons, and disabled mutation commands. Details opened as an attached sheet and Return dismissed Done. Right-clicking a nonselected row opened Remove Account without changing selection; removal was disabled in demo. UUID binding and operation-race guards were source-reviewed.
- An intermediate uncommitted build clipped quota text and capacity tracks. Native column autoresizing and fitting corrected them without widening the sidebar; the corrected light appearance showed full text and trailing spacing. The final dark demo inspection verified the corrected spacing plus green, orange, measured red zero, and neutral unknown rows. The zero-quota fixture uses the existing research profile, with unavailable credit amounts and explicit fictional provenance.
- Native Zoom exercised a real resize, then restored the ordinary size. After the requested cap was added, the zoomed capture was 1920 × 1576 pixels instead of filling the display. Source caps ordinary content at 960 × 760 points, and the embedded Platform pane at 1280 × 900. Pixel dimensions are observed capture dimensions, not an independent display-scale measurement. Two coordinate drags did not establish a minimum-size resize; minimum-size behavior remains unverified.
- Normal operation verified a red low-quota row and retained identity. Both right-click removal and the sidebar Delete key opened an identity-specific confirmation; Cancel retained the account. An automatic refresh showed a neutral stale row, with Details available, then restored fresh quota. The direct Refresh control preserved an unfinished manual amount through completion; it was restored to its original empty value without Save or Clear.
- The direct API Credits control opened the isolated Platform sign-in page. Native Zoom was bounded to a 2560 × 1856 pixel capture, and Back restored the same account at the original 1400 × 1136 pixel capture size. No sign-in, Continue, or linking action was taken.
- Review correction: Billing is read-only and now remains enabled for a valid selected account during refresh, like Details. `openBilling` preserves its prior URL choice and checks profile validity rather than mutation state. Corrected source passed 58 tests, Release build (12.98 seconds), and canonical packaging. Computer inspection during a manual refresh verified Details and Billing enabled while Add, Reconnect, API Credits, and Refresh were disabled. The billing URL action was source-reviewed; no browser billing action was taken for this check.
- `git diff --check` and review of every changed source and documentation line: passed. Concurrent guidance, skill files, and design assets are excluded from this change.

Native review distinguishes observed AX names/roles/values and exercised keyboard controls from VoiceOver, contrast measurements, enlarged text, and real accessibility-preference transitions, which remain untested. Source checks found no continuous animation or new countdown timer; no measured performance claim is made. Apple [Context menus](https://developer.apple.com/design/human-interface-guidelines/context-menus), [Sidebars](https://developer.apple.com/design/human-interface-guidelines/sidebars), and [Windows](https://developer.apple.com/design/human-interface-guidelines/windows) informed the native controls. Actual removal, multi-account live removal identity, live reconnect, live Platform sign-in/balances, Intel/macOS 14 execution, and notarization remain unverified. No account, credentials, stored balance, or CLI login was changed by these checks.

## App Settings navigation, October 13, 2026

The baseline `9309a7f26139ffae21545240fd60196186258277` was inspected live before editing: General appeared as an account-list row and its screen retained the AI Usage Stats title. The changed app has an App Settings icon in the sidebar footer, no General row, native Startup/Usage form rows, and a title matching App Settings or the selected account. Settings remains inside the same window, as requested.

Initial settings code/test source SHA-256: `c97d9a5e3d417a2d348c35612e6f9011c0eacd78b49b74e2b75b33ed878577f2` (commit `57f43ab87a19afd705842f1e42864b74e5c6e637`). Corrected source SHA-256: `c1adca533036d6e38285ce99018390bb6dc0d160b7b06fff4bd67d88989ddf09`. Digests cover `Package.swift` and all Swift files in `Sources` and `Tests`, sorted by relative path, with UTF-8 path, NUL, contents, NUL for each file.

- `swift test`: passed 50 tests (21 XCTest and 29 Swift Testing), zero failures.
- `swift build -c release`: passed in 13.25 seconds; existing Keychain warnings retained.
- `scripts/package_app.sh`: passed with the existing local signer.
- Packaged `.app` inspected with Computer on Apple silicon, macOS 27.0.1: footer icon and settings layout, account-specific titles, return to both provider views, Command-comma, Tab focus on the settings icon and launch-at-login checkbox. Launch-at-login remained off and was not toggled. One native automation pipe interruption recovered with a fresh app-state read; the final state confirmed App Settings.
- An unsaved manual amount survived settings navigation and return to the same real account. The field was restored to its original empty value and collapsed without Save or Clear; no stored balance changed.
- `git diff --check` and every changed source/documentation line reviewed. No layout-only tests added.

Review correction: an initial load failure now has its own wrapped error and Retry Loading Accounts control, with Add Account disabled until loading succeeds. Manage Accounts returns from Settings to the account/error view; reopening a minimized window preserves its current screen. `--demo --demo-load-error --show-accounts` simulated a first load failure in the packaged app, without touching real storage. Computer verified the error, Settings navigation, Command-M and packaged-app reopen retaining App Settings, Manage Accounts returning to the error, Tab focus on Retry, and Space restoring fictional accounts. `--demo --demo-empty --show-accounts` showed successful empty setup with no error and no automatic settings navigation. Both fixture modes remain inside the existing demo path. Corrected source passed `swift test` (50 tests, zero failures), `swift build -c release` (12.48 seconds), and canonical packaging with the configured local signer.

Further review correction, source SHA-256 `2539baa18c3b8d92be061219bafce5d5494c60c2d6d2be0f2055a682bd7af41a`: Add Account and initial error/retry state now share the precise empty-accounts load-failure condition. A transient refresh error with retained profiles does not disable Add indefinitely; successful refresh loading clears its earlier diagnostic. Status-menu validation and execution reject active refresh/account changes as well as demo mode. `swift test` passed 50 tests, `swift build -c release` passed in 12.37 seconds, and canonical packaging passed. Real filesystem recovery was source-reviewed without inducing a storage failure; synthetic fixtures do not establish that provider/storage recovery path.

Apple's [Settings](https://developer.apple.com/design/human-interface-guidelines/settings) and [Sidebars](https://developer.apple.com/design/human-interface-guidelines/sidebars) guidance informed native navigation and form layout. No credentials, real account storage, provider sessions, purchases, or login settings were changed. Failed storage loading itself is covered by source review rather than corrupting real files; the UI failure and retry evidence is synthetic. Minimum-size resizing, live Platform return, VoiceOver, Intel, and macOS 14 remain unverified.

## Window activation, October 13, 2026

Tested code/test source SHA-256: `08f44ba2357bc2093b7f18cecf62b67d70405e0fe6610e166b506866b2e7ec35` (submitted commit `b4174fd620b990aeac6d4657e8520518efb54106`, merged as `b5330db61fe9bd287f042c360ebf7cc093a8dfd9`). Digest procedure is described above.

Baseline `9309a7f26139ffae21545240fd60196186258277` was packaged and opened with `open -n "dist/AI Usage Stats.app" --args --demo --show-accounts` on Apple silicon, macOS 27.0.1 (26A434). Computer inspection showed the existing Accounts and General screens; their title remained AI Usage Stats. The running baseline was absent from Computer's regular-app inventory after Command-Tab. Source inspection located the unconditional accessory policy in `AIUsageStatsApplication.main` and missing promotion in `ApplicationDelegate.showAccounts`. This inventory observation supports the reported app-switching problem; no screenshot of the switcher itself was captured.

The changed app appears in the regular-app inventory while Accounts is open, remains available after Command-M, and disappears from that inventory after Command-W without exiting. Reopening the packaged app restores the same account selection. Command-Tab from another app was exercised and the Accounts window remained available. Computer's subsequent app-state read can reopen a closed accessory app, so the close check used Finder state and the regular-app inventory without querying the closed target. Settings, credentials, and provider sessions were not changed. Attached-sheet closure is source-reviewed, not a tested authentication interaction.

- `swift test`: passed 50 tests (21 XCTest and 29 Swift Testing), zero failures.
- `swift build -c release`: passed in 13.64 seconds; existing Keychain deprecation warnings retained.
- `scripts/package_app.sh`: passed with the configured local signer. `plutil -lint`, `lipo -archs`, and `codesign --verify --deep --strict --verbose=2` passed for the packaged app; arm64, local development signing.
- `git diff --check`: passed. Every changed source line was reviewed. No layout-only tests were added.

Apple's [Windows guidance](https://developer.apple.com/design/human-interface-guidelines/windows) informed native close, minimize, and reopen behavior. Intel execution, macOS 14 execution, VoiceOver, authentication-sheet closure, and notarized distribution remain unverified.

## Initial implementation baseline

Verified October 9, 2026 on Apple silicon with macOS 27.0.1 (26A434), Apple Swift 6.4, and no external Swift package dependencies. These results describe the initial implementation before its first Git commit. Later changes require a new verification record; the digest below identifies this historical baseline.

Tested code-and-test source SHA-256:

```text
69c17b4ff0f92aaddf75ace1eaeb7f62afebdf560a7b8800a668debe45f28921
```

The digest covers `Package.swift` and all 19 Swift files in `Sources` and `Tests`, sorted by relative path. For each file the digest input is its relative UTF-8 path, a NUL byte, its contents, and a NUL byte. The digest was unchanged before and after final tests, Release build, and packaging.

| Command or check | Observed result |
| --- | --- |
| `swift test` | Passed: 21 tests, zero failures. 13 XCTest tests (8 Console parser, 5 Codex subprocess) and 8 Swift Testing contracts. Final cached debug build completed in 0.31 seconds. |
| `swift test --filter codexExecutableUsesNativeBundleOrNPMBinaryWithFinderEnvironment` | Passed: 1 focused Finder-path resolver test before the final full run. |
| `swift build -c release` | Passed without warnings. Clean Release build completed in 14.36 seconds. |
| `scripts/package_app.sh` | Passed. Created `dist/AI Usage Stats.app` and `dist/AI-Usage-Stats-0.1.0.zip`; cached Release build completed in 0.29 seconds. |
| `plutil -lint "dist/AI Usage Stats.app/Contents/Info.plist"` and `plutil -p` | Passed. Version 0.1.0, build 1, `com.parkerrex.ai-usage-stats`, executable `AIUsageStats`, macOS minimum 14.0, `LSUIElement = true`. |
| `codesign --verify --deep --strict --verbose=2 "dist/AI Usage Stats.app"` | Passed on the final moved bundle and bundled helper. |
| `codesign -d --verbose=2 "dist/AI Usage Stats.app"` | Reports an ad hoc signature and no TeamIdentifier. No Developer ID or notarization claim. |
| `lipo -archs` for `Contents/MacOS/AIUsageStats` and `Contents/MacOS/UsageCapture` | Both report `arm64`. Universal compilation and Intel runtime were not tested. |
| Per-file `git diff --no-index --check /dev/null` | Passed for 36 untracked text files. Binary assets skipped. No staging changes; an empty ordinary Git diff was not used as evidence. |
| Local Markdown link targets | Passed for 7 project documents. External provider references are recorded in the research reports. |

Initial local archive SHA-256:

```text
ad143c95bb7511404031fee7d81e729b153cacce25a8cf9a3d30887b4252ffda
```

The tests use synthetic data and fake CLI subprocesses. They verify field semantics, profile isolation, original Claude status-line preservation, settings symlinks, dated manual records, Console organization binding, currency conversion, missing fields, expired grants, malformed responses, Finder-path native CLI discovery, and subprocess timeouts and cleanup. They do not read real credentials or make account requests.

An additional synthetic invocation of the packaged `UsageCapture` preserved identical stdin and stdout and the original command's exit status 7, stored quota fields, omitted conversation metadata, and created a mode-0600 capture file in a disposable directory. Only disposable configuration and synthetic payloads were used.

## Liquid Glass redesign

Verified October 9, 2026 on the same Apple silicon Mac with macOS 27.0.1, macOS SDK 27.0, and Swift 6.4. The runtime target remains macOS 14+. Building the glass controls requires a macOS 26+ SDK; older supported systems use the plain native path. Older runtime execution was not tested.

Final redesign code-and-test source SHA-256:

```text
92fe1be979bb15eded7a8e99dd66ad7a7dafa4debe283cf31ac52f71806e3965
```

The same digest method described above now covers 22 files: `Package.swift` and 21 Swift files in `Sources` and `Tests`. The source digest was unchanged through the final test, Release build, and package checks. It identifies the tested source snapshot before publication.

| Command or check | Observed result |
| --- | --- |
| `swift test` | Passed: 21 tests, zero failures. 13 XCTest and 8 Swift Testing tests; cached debug rebuild 2.02 seconds. |
| `swift build -c release` | Passed without warnings; cached build 4.22 seconds. |
| `scripts/package_app.sh` | Passed; cached Release build 0.28 seconds. Produced the local app and ZIP. |
| `codesign --verify --deep --strict --verbose=2 "dist/AI Usage Stats.app"` | Passed on the final moved bundle and embedded helper. Local ad hoc signature. |
| `plutil -lint "dist/AI Usage Stats.app/Contents/Info.plist"` | Passed. Packaging retained version 0.1.0/build 1 and the macOS 14 runtime target. |
| `lipo -archs` for both bundled executables | Both report `arm64`. |
| `xcrun --sdk macosx --show-sdk-version` and `swift --version` | SDK 27.0 and Apple Swift 6.4. |

Final redesign local ZIP SHA-256:

```text
572e81d0924e3a4197c3bbfba66a05d47538c537705b571fb5f872a2208ab479
```

### Native observations

- Both demo accounts' main quota values, credit balances, and earned-reset expiry fit in the 440 × 540 panel without scrolling. The earlier 440 × 610 design required scrolling to finish the same two-account view.
- Light and dark validation-window captures show aligned values and readable account, credit, and reset rows. Details exposes exact dates and source records. Accounts, provider-specific Codex actions, the manual form, and Command-comma Settings were inspected. All manual form fields were reachable by scrolling.
- The app-only Reduce Transparency flag removed the glass command surface while preserving readable data. This tested the fallback path, not a global system preference change or execution on older macOS.
- Tab moved from Actions to the first Details control; Space expanded it; Tab reached its dashboard action; Shift-Tab returned to Details. The same Details control retained focus while a countdown changed from `2h` to `1h 58m` across a minute update.
- After the demo aged beyond five minutes, the reset grant's short date and countdown remained readable with Stale on a second line. Both accounts' main values still fit without scrolling.
- Expanded details initially allowed focus to move to a lower account offscreen. The final focus-reveal patch was checked in the running app: tabbing to Codex Details scrolled it into view, with the normalized scrollbar value moving from 0 to 0.05128.
- The real empty state was readable at 440 × 250. Connect Claude showed Name, the default `~/.claude` folder, and Choose Folder. Cancel created no profile and made no configuration writes.
- The actual status-item presentation was inspected as an accessibility popover. The public [menu-bar screenshot](../assets/screenshots/menu-bar.png) shows both demo accounts and the glass controls in the running native popover with the system's light appearance. All data in the capture is fictional. The app's dark launch flag controls validation windows; it is not evidence of a dark system popover.

The light/dark, stale, and minute-focus checks began on an earlier redesign snapshot; the final change added native focus reveal without changing layout or data updates. The focus-reveal and actual-popover checks used the frozen final source. [Design captures](../assets/design/) and the [critique](design/critique.md) retain that evidence.

No VoiceOver session, global Reduce Transparency/Increase Contrast/Reduce Motion transition, quantitative contrast measurement, older-macOS runtime, Intel runtime, or live signed-in billing read was verified. Escape dismissal was not established by the available post-dismiss accessibility response. No new app-overhead or notarization claim is made.

## Initial native checks

Native inspection used the packaged app's actual menu-bar popover, its normal empty state, and a disposable Claude configuration without user credentials. The popover initially showed its header at scroll position zero. Manual balance `12invalid` was rejected; `15.25` saved successfully while retaining the Purchased category. An unsaved account name survived refresh and a Console error update.

The official Console sign-in page loaded with Google and email controls. A signed-out direct read returned 403 and used the provider-page fallback; its bounded 20-second operation returned a readable error and re-enabled Read, Open Sign In, and Disconnect. No provider sign-in was performed and no live credit balance was fetched.

The disposable profile was removed through the native interface, and its original Claude settings were restored exactly. These native checks preceded the last controller-retirement and CLI-discovery changes; those final changes were compiled and tested on the source digest above. Controller release and live provider login remain runtime limits.

No live account balance, minimum-macOS runtime, Intel runtime, app-overhead measurement, Developer ID signature, notarization, or public distribution verification is claimed.

## Provider schema verification

On October 9, 2026, installed `codex-cli 0.160.0` was verified without authentication or account requests using an empty private profile:

```sh
schema_directory=$(mktemp -d)
mkdir -m 700 "$schema_directory/home"
env -u CODEX_ACCESS_TOKEN -u CODEX_API_KEY -u OPENAI_API_KEY \
  CODEX_HOME="$schema_directory/home" codex app-server generate-json-schema \
  --out "$schema_directory/schema"
```

Result: exit 0 using an empty private home. The generated account-rate-limit schema includes nullable account identity and limit maps, an authoritative integer reset-credit count, and optional credit details with Unix-second grant and expiry fields. This establishes schema compatibility with that installed CLI, not live account availability. See [the research record](research/codex.md).

The final Finder-path resolver selects the native executable at `/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex` on this machine. With an empty temporary `HOME` and `CODEX_HOME` and `PATH=/usr/bin:/bin:/usr/sbin:/sbin`, its `--version` command returned `codex-cli 0.162.0-alpha.2` and `app-server generate-json-schema --out <temporary-directory>` exited 0. The generated response retained usage, limit-map, and reset-credit properties. No authentication or account request was used. An earlier Node wrapper failed under that Finder path; the resolver now chooses the native binary and has a focused test for both bundle and official npm installations.

## Required checks

| Outcome | Check |
| --- | --- |
| Type-safe Swift 6 build | `swift build -c release` |
| Core behavior | `swift test`, with the actual pass count |
| Local native bundle | `scripts/package_app.sh` and bundle inspection |
| Metadata | `plutil -lint "dist/AI Usage Stats.app/Contents/Info.plist"`; inspect executable, bundle ID, minimum OS, and `LSUIElement` |
| Local signature | `codesign --verify --deep --strict --verbose=2 "dist/AI Usage Stats.app"` |
| Executable architecture | `lipo -archs "dist/AI Usage Stats.app/Contents/MacOS/AIUsageStats"` and the bundled `UsageCapture` helper |
| Menu-bar behavior | Open the packaged app and exercise panel open/dismiss, setup, refresh, failure state, and Quit |
| Provider isolation | Verify separate configuration directories retain separate labels, credentials, and readings |
| Data semantics | Verify percentages, dynamic durations, reset times, credit units, expiry, null fields, and stale timestamps |

Tests should cover meaningful contracts. Redacted fixtures do not establish live provider availability. An account refresh does not establish billing access. A successful signature check does not establish Developer ID signing or notarization.

## Remaining limits

- Legacy Claude status-line profiles depend on a new supported captured reading. The experimental direct connection requests quota after its own browser sign-in. A fresh usage-only grant and current quota were verified for one account; multiple live accounts and automatic renewal remain unverified.
- Codex app-server fields depend on CLI version and plan. Use returned durations and preserve unavailable values.
- Codex credit units, earned limit-reset counts, and monetary API prepaid credits are different data.
- Documented public APIs did not establish remaining API prepaid balances or all grant-expiry details. The experimental Claude Console path uses private billing endpoints. Manual entries remain dated and explicitly labelled.
- The experimental Claude Console connection reads private browser-facing billing endpoints. Typed parser tests do not establish live availability, successful sign-in, correct account membership, or a stable provider contract.
- New Claude subscription connections use app-owned grants in separate Keychain items. Legacy capture profiles follow their existing configuration directories. Codex profiles use separate app-owned `CODEX_HOME` directories; changing any default CLI login is outside monitoring scope.
- Local ad hoc packaging is available. Public signing, notarization, release hosting, and updates are not configured.

## Native first-run menu, October 10, 2026

Tested baseline `729ce41` plus the uncommitted working diff on `fix/native-first-run-menu`. The source snapshot uses the digest method above and covers 21 files, including `Package.swift` and 20 Swift files:

```text
d16747cea5eb21c0fd8743eed582bc604966bbc796725841c44bc06386779fb8
```

| Command | Observed result |
| --- | --- |
| `swift test` | Passed: 21 tests, zero failures. |
| `swift build -c release` | Passed; Release build completed in 9.04 seconds. |
| `scripts/package_app.sh` | Passed after the validation-only menu anchor change. Produced the local app and ZIP. |
| `plutil -lint "dist/AI Usage Stats.app/Contents/Info.plist"` | Passed. |
| `codesign --verify --deep --strict --verbose=2 "dist/AI Usage Stats.app"` | Passed on the packaged app and helper. Local ad hoc signing remains unchanged. |

The [old actual popover](../assets/design/flyout-before.png) reproduced the first-run presentation problem. The revised empty-account path uses a native menu containing Add Claude Account…, Add Codex Account…, Accounts…, Settings…, and Quit AI Usage Stats. It has no Refresh, generic Actions item, banner, technical paragraph, or footer.

The same real `NSMenu` was checked in an explicitly labelled [validation host](../assets/design/flyout-menu-validation.png), because the computer-use tool could not inspect the menu-only accessory app. Arrow Down selected Claude and then Codex; Return opened the Codex dialog. Pointer selection of Claude opened the Claude dialog. Cancel left the account list empty without authentication. This validates the menu component and command routing, not ordinary status-item pointer anchoring or an ordinary first-run menu screenshot.

A disposable local Claude configuration with `settings.json` containing `{}` was added solely to check the configured state. The normal `--show-panel` path produced a real [populated popover](../assets/design/flyout-configured-validation.png) with direct Refresh, Accounts, Settings, and Quit controls and no app-title banner or glass command group. The test profile was removed through the app; the account table became empty, and its temporary settings were verified restored to `{}`. User credentials and provider authentication were unchanged.

The fresh [usage overview](../assets/screenshots/usage-overview.png) was captured from the actual populated native popover. It shows both fictional demo accounts' quota, credit, and reset-expiry readings, the direct controls, and a Demo footer. The previous [menu-bar capture](../assets/screenshots/menu-bar.png) remains available as historical evidence.

Live sign-in, real provider balances, VoiceOver, and ordinary empty-menu pointer anchoring remain unverified. These native observations preceded the final local delivery checks below.

### Local delivery checks

Verified October 10, 2026 on Apple silicon with macOS 27.0.1 (26A434). The source digest remained `d16747cea5eb21c0fd8743eed582bc604966bbc796725841c44bc06386779fb8` through these checks. Upstream `main` remained at `729ce416334cb3c083573037ca90935f48e66a91`; no source rebase was needed.

| Command or check | Observed result |
| --- | --- |
| `swift test` | Passed: 21 tests, zero failures, comprising 13 XCTest and 8 Swift Testing tests. Debug build completed in 1.13 seconds. |
| `swift build -c release` | Passed; Release build completed in 4.79 seconds after waiting for the test build's SwiftPM lock. |
| `scripts/package_app.sh` | Passed; cached Release build completed in 0.30 seconds. Replaced the local app and ZIP. |
| `plutil -lint "dist/AI Usage Stats.app/Contents/Info.plist"` and `plutil -p` | Passed. Version 0.1.0/build 1, bundle ID `com.parkerrex.ai-usage-stats`, macOS minimum 14.0, and `LSUIElement = true` retained. |
| `codesign --verify --deep --strict --verbose=2 "dist/AI Usage Stats.app"` and `codesign -d --verbose=2` | Passed on the moved bundle and helper; ad hoc signature, no TeamIdentifier. |
| `lipo -archs "dist/AI Usage Stats.app/Contents/MacOS/AIUsageStats"` and `lipo -archs "dist/AI Usage Stats.app/Contents/MacOS/UsageCapture"` | Both report `arm64`. App icon and license are present in the bundle. |
| `open -n "dist/AI Usage Stats.app"` | Passed after quitting the previous development instance. The replaced workspace bundle launched normally without validation or demo flags. No separate installed copy was found. |
| `git diff --check` and review of all changed text and four new screenshots | Passed. Screenshots contain fictional demo data or a disposable local account with no credentials. |

Local delivery ZIP SHA-256: `8f780d75051fee77183d646136715f683de98de6fb197517422ec96ec7e5d394`.

The submitted commit is recorded in the pull request test plan. The checks above establish local arm64 packaging and launch; they add no new provider, VoiceOver, older-macOS, Intel, Developer ID, notarization, or public-release evidence.

## Claude first reading diagnosis, October 10, 2026

Baseline commit `2f0f54b` reproduced the reported unavailable usage after adding a Claude capture profile. The selected profile had a capture hook, but no capture file, zero usage windows, no observation timestamp, and an unavailable refresh state. A valid isolated helper fixture wrote two usage windows. The app already reloads capture files; timing alone does not explain the absent observation. The active Desktop process used an embedded stream-JSON CLI, and this check did not establish that it emits the supported status-line payload. No inference request was sent as a probe.

The initial authentication diagnosis needed correction. Running `claude auth status` with `CLAUDE_CONFIG_DIR` explicitly set to the default directory selected a different hashed Keychain service and reported no login. With the selector absent, the normal CLI reported signed in. Inspection of the installed Claude Code 2.1.295 credential selector confirmed this distinction; identical filesystem paths do not establish identical credential selection.

An authorized, noninteractive read of the exact default Keychain item succeeded. Its access token was expired and included the `user:profile` scope. One read-only `GET /api/oauth/usage` and one `GET /api/oauth/profile` returned HTTP 401. No refresh token was parsed, used, or written, and the existing CLI login was not changed. No local CLIProxyAPI installation or saved ProxyCLI credentials were found. These results establish an expired borrowed credential, not a successful fresh grant or signed-in quota read. Account identifiers, credentials, and provider response bodies are excluded from this record.

The changed connection follows an independent browser OAuth grant with direct quota reads and explicit connection feedback. Source inspection is recorded in [Claude research](research/claude.md). The later native check accepted the requested `user:profile`-only grant and returned current quota for one account, preserving the existing capture profile UUID and alias. Multiple live account bindings and automatic renewal remain unverified. Build, fixture, and packaging evidence follows. Native observations and live account availability are separate claims.

### Direct connection build and fixture evidence

Verified October 10, 2026 on Apple silicon with macOS 27.0.1 (26A434). Tested baseline `2f0f54be466bda8fe319a3cdb4048a25665e4347` plus the uncommitted direct-connection changes. The digest method above covers 24 files: `Package.swift` and 23 Swift files in `Sources` and `Tests`.

```text
c565e021ffbf944483ddb8db4952b1aa69553c534f3ba6bd832ea62a3522e065
```

| Command or check | Observed result |
| --- | --- |
| `swift test` | Passed: 29 tests, zero failures, comprising 13 XCTest and 16 Swift Testing tests. Debug build completed in 0.34 seconds. |
| `swift build -c release` | Passed; Release build completed in 11.84 seconds. |
| `scripts/package_app.sh` | Passed; cached Release build completed in 0.43 seconds. Produced the local app and ZIP. |
| `plutil -lint "dist/AI Usage Stats.app/Contents/Info.plist"` | Passed on the packaged bundle. |
| `codesign --verify --deep --strict --verbose=2 "dist/AI Usage Stats.app"` | Passed on the packaged app and helper. Local ad hoc signing. |
| `lipo -archs` for the bundled app and `UsageCapture` helper | Both report `arm64`. |
| `git diff --check` and changed-document local links | Passed. |

Eight new behavior tests verify requested `user:profile` scope, PKCE/state/expiry, unknown versus measured zero and inactive windows, profile identity and duplicate isolation, credential exclusion from account JSON, cancelled exchange, refresh uncertainty without replay while retaining the previous reading, removal during an in-flight quota read, and rejection of authentication, rate-limit, HTML, and redirected responses. Synthetic token responses omit optional unchanged scope metadata and exercise the private provider's response shape. The added overlap fixture verifies that metadata objects do not become quota rows, canonical windows are not duplicated by equivalent `limits` entries, unknown canonical values stay unknown, and model-scoped limits keep their weekly duration. No fixture is evidence of provider acceptance of the new grant.

The final packaged app executable SHA-256 is `ea179671760bdda869e33674ff39ce817551cbae54a29d5f1107caf88e2d4d6f`.

A standalone Swift 6 fixture compiled the actual callback listener and exercised real Network sockets. Invalid callback path and state returned HTTP 400 without consuming the listener; the valid state and code returned HTTP 200 and completed exactly one callback. The port could be rebound immediately afterward. These observations establish local callback behavior, not the provider's browser redirect or successful signed-in quota retrieval.

### Native subscription sign-in

On the same Mac, the packaged app showed the existing capture account's unavailable state and a recovery action. Check Usage retained that unavailable state without a fabricated observation timestamp. Reconnect opened the system browser and a native waiting window. The user completed the provider sign-in; the app's own `user:profile`-only grant was accepted, identity verification succeeded, and direct quota retrieval supplied a current observation. Accounts then showed Connected with quota available. The existing app profile UUID and alias were preserved.

The Accounts view before reconnect was visually inspected and showed readable connection feedback without overflow. The signed-in state and quota fields were inspected in the running native app. No public screenshot or account identifiers, email, credentials, or live quota values are included here.

After rebuilding with the parser correction, manual Refresh read the saved app-owned grant without reconnecting. It returned exactly three quota rows: 5 hours, 7 days, and a model-specific 7-day window. There was no breakdown metadata row or duplicate primary limit. Accounts showed a fresh observation timestamp and the verified provider email. This final check used the source digest and packaged executable above.

Keyboard Tab reached Refresh; subsequent Tab and Space opened Accounts. These control checks used the packaged app's explicitly labelled `--show-window` validation host so the native automation tool could bind to it. They establish the shared native controls, not ordinary status-item anchoring.

The final `--show-panel` launch used normal app mode without a validation window. Native accessibility inspection identified the actual `NSPopover`, and its screenshot was visually inspected. All three corrected quota rows fit without duplicate or metadata rows. Reset countdowns were visible; a genuinely missing reset remained unknown. API credit fields remained unavailable because the separate Console connection had not been completed. No public screenshot was saved.

This establishes one live account's authorization and quota read. It does not establish multiple live account bindings, automatic grant renewal, failed provider consent, a VoiceOver session, minimum-macOS runtime, Intel runtime, or live Console billing. An initial live response also exposed duplicate quota rows and a `seven_day_breakdown` metadata object displayed as an unavailable quota. The amended parser excludes metadata objects, keeps canonical quota windows when also represented in `limits`, and retains model-scoped weekly limits. The final source digest and 29-test results above include that correction.

### Pull request review corrections

Review of commit `ecb6b9a484a54d8ac7d36b59044363467c7b8d63` found two additional issues. Inactive provider limits were retained but still affected current percentages and reset freshness. A migrated OAuth profile also retained its obsolete status-line installation. The correction labels inactive rows as inactive, excludes them from current measurements and stale-reset decisions, and propagates activity flags from equivalent limits to canonical windows without replacing their values. It saves a valid browser grant before retiring only the migrated profile's unchanged wrapper. User replacements are preserved. Failed or incomplete cleanup retains its restoration record and reports the issue; later account loads can retry.

The reviewed source, using the same 24-file digest method, is:

```text
20bd6ead7ac7e3f0f05e1e9755dc7b284a54aafb2415dd5ee9fd321b08d9a187
```

| Command or check | Observed result |
| --- | --- |
| `swift test --filter ClaudeOAuthTests` | Passed: 10 tests, zero failures; debug build 6.16 seconds. |
| `swift test` | Passed: 31 tests, zero failures, comprising 13 XCTest and 18 Swift Testing tests; cached build 0.58 seconds. |
| `swift build -c release` | Passed; 18.95 seconds. |
| `scripts/package_app.sh` | Passed; cached Release build 0.51 seconds. |
| Packaged plist lint, deep strict signature verification, executable architecture, and `git diff --check` | Passed; app and helper remain local ad hoc signed arm64 binaries. |

The two new synthetic behavior tests cover exhausted inactive quotas with expired resets, duplicate activity flags, inactive-only responses, successful legacy command restoration, unrelated command preservation, changed wrapper fields, cleanup failures, and idempotent recovery without discarding the new grant.

The final packaged executable SHA-256 is `643bd12c2afb4f1af9d8438a58e49b35b70c24fa2a82dbd4dd59a0ca5ba9888d`.

Separately from fixtures, the authorized existing-profile cleanup ran on the new packaged app's first load. Hash-only checks confirmed restoration of the original status line, preservation of every non-status-line setting, removal of only the migrated profile's installation record, unchanged saved account profiles, and preservation of the shared capture helper. No saved command, settings content, credential, or account value was disclosed by those checks.

Native accessibility inspection of this corrected packaged build showed the model-specific quota marked `Inactive` and `Not current`. A subsequent sanitized persisted-state check confirmed an available provider reading less than five minutes old, with one current window and two explicitly inactive windows. The current observation retained the provider's activity flags, including flags applied to canonical windows. Completing the final manual Refresh click could not be established because the native automation bridge timed out; this is recorded as an environment limit, not a completed interaction. No public account screenshot was saved.

### Optional identity metadata and failed removal recovery

The next review of `441eeb0ffbb041efee57cbd623daf92c3cee2b66` found that an omitted organization object could reject an otherwise valid profile, and that failed account-file persistence could leave a listed profile without its deleted Keychain grant. The corrected parser always requires the account UUID, permits account-only initial identity, cross-checks any supplied token identity, retains a previously known organization on omission, and rejects explicit conflicts. Existing composite identity strings remain valid. Explicit removal retains the exact app-owned credential in memory and restores it when subsequent configuration persistence fails; restoration failure is reported rather than ignored.

The final 24-file source digest is:

```text
c9610f169d863d86d8121db14fe4b234bc5be7df6a4bbdc6ac7e054afc51c0ac
```

| Command or check | Observed result |
| --- | --- |
| `swift test --filter ClaudeOAuthTests` | Passed: 12 tests, zero failures; build 8.06 seconds. |
| `swift test` | Passed: 33 tests, zero failures, comprising 13 XCTest and 20 Swift Testing tests; cached build 1.23 seconds. |
| `swift build -c release` | Passed; 23.42 seconds. |
| `scripts/package_app.sh` | Passed; cached Release build 1.23 seconds. |
| Packaged plist lint, deep strict signature verification, executable architecture, and `git diff --check` | Passed; app and helper remain local ad hoc signed arm64 binaries. |

Two additional fixtures exercise initial account-only identity and successful owned renewal with optional organization data, retained known organization, explicit account/organization conflicts, restoration of the exact grant after failed configuration persistence, and successful subsequent account removal. Renewal and removal failure handling remain fixture evidence; the real account was not removed or reconnected for these checks.

The packaged executable SHA-256 is `16197873a2e73f2e3a968d568de17307509e45f3e6c54aea316c16d4b7ddab34`. The normal `--show-panel` app was relaunched. Sanitized persistence checks confirmed one unchanged profile, available state, and an observation less than five minutes old. No additional native automation claim or live organization-omission/renewal claim is made for this final parser and persistence correction.

### Verified email display and legacy financial isolation

Verified October 10, 2026 on the same Apple silicon Mac with macOS 27.0.1 (26A434). The 24-file source digest for this correction is:

```text
f11b59ffdca98d22db9d9427e419d44d86f71ba716ad143dfa971237fbec849f
```

| Command or check | Observed result |
| --- | --- |
| `swift test` | Passed: 34 tests, zero failures, comprising 13 XCTest and 21 Swift Testing tests; build 2.36 seconds. |
| `swift build -c release` | Passed; 11.66 seconds. |
| `scripts/package_app.sh` | Passed; cached Release build 0.30 seconds. |
| `plutil -lint "dist/AI Usage Stats.app/Contents/Info.plist"` | Passed; metadata retains version 0.1.0, build 1, menu-bar bundle behavior, and minimum macOS 14. |
| `codesign --verify --deep --strict --verbose=2 "dist/AI Usage Stats.app"` | Passed on the moved app and helper; local ad hoc signing. |
| `lipo -archs` for the packaged app and capture helper | Both report `arm64`; icon resource is present. |
| `git diff --check` | Passed. |

The added behavior fixture binds an unverified legacy profile to its first verified subscription identity. Earlier Console connections and observations are cleared; earlier manual balances move to saved pending values rather than becoming the verified account's current balances. Saving one balance confirms only that category. Responses with the old captured identity are rejected. Same-identity reconnect preserves confirmed financial data, and removing the account removes pending values. Native Console controllers retire before subscription reconnect; both service and model updates check the immutable identity captured when the controller opened, including a previously unknown identity. These remain synthetic isolation and confirmation checks; no real account was reconnected or removed for this correction.

Native demo checks visually inspected distinct Claude email headings, the full longer email in the overview, and the explicit unavailable-email state after scrolling. Accounts showed email-first rows with provider and saved alias beneath. The longer sidebar email truncated in the middle while its full value remained available in accessibility/help and the selected account description. Clicking the longer-email row and pressing Down selected the unavailable-email row correctly. These checks used fictional demo data in the packaged validation window. The final build adds a shared display formatter for nil, empty, or whitespace-only email values without changing saved profile data. A final normal-mode demo launch exposed the actual accessibility popover; visual inspection confirmed the email beneath the Claude header and preserved alias in the native layout. No public screenshots or real account values were saved.

The final packaged executable SHA-256 is `ad67e601c73e6dfe89e51bea4a20bbb4b6b465c1ccdfdaed6cf3dd9fd0c7314b`. The app was returned to normal real-account mode; a sanitized check confirmed saved profiles include verified Claude email metadata. Final real-mode native automation timed out after five seconds, so no additional real-mode visual inspection is claimed. Multiple live account binding, real Console billing, live renewal, VoiceOver, minimum-macOS runtime, Intel runtime, Developer ID signing, and notarization remain unverified.

### Recovery after sign-in persistence and Keychain cleanup failure

Review of `609033129a1b6a368f357a2ac3cde2a1bd7e1032` found that failed account-file persistence could suppress a second failure while removing a newly saved Keychain grant. The correction writes an empty, private UUID marker before saving a grant with no previous credential. Failed deletion preserves that identifier for retry after a successful configuration load or when preparing the next sign-in, including after restart. Background cleanup failures keep the marker and leave otherwise valid accounts available; interactive retry reports the cleanup error. Cleanup skips active sign-ins, ignores directories and symlinks, and preserves grants associated with committed, verified OAuth profiles. A legacy capture row alone does not establish that association. Existing-profile credential restoration failures are explicit and direct the user to reconnect. No credential contents enter the marker or account file.

The final 24-file source digest is:

```text
01e0aa0452e63e41094cb481a40b406ce6fbaae30ec8c1510aad2dc5d4e18782
```

| Command or check | Observed result |
| --- | --- |
| `swift test` | Passed: 35 tests, zero failures, comprising 13 XCTest and 22 Swift Testing tests; build 132.58 seconds. |
| `swift build -c release` | Passed; 201.65 seconds. |
| `scripts/package_app.sh` | Passed; cached Release build 14.03 seconds. |
| Packaged plist lint, deep strict signature verification, executable architecture, and `git diff --check` | Passed; both executables remain local ad hoc signed arm64 binaries. |

The new synthetic fixture forces account persistence and Keychain deletion to fail together, verifies a mode-0600 marker containing no credential data, and recreates the service to verify that blocked background cleanup leaves a committed account available. Interactive retry reports the same cleanup failure; a later load removes only the orphan grant. Repeated cleanup preserves the exact committed credential. UUID-named directories and symlinks remain untouched. Actual Keychain failure and live sign-in were not induced. The UI source is unchanged from the inspected email build. The new packaged app was launched in normal real-account mode; the prior native automation limit remains, and no additional visual check is claimed.

The packaged executable SHA-256 is `7b1ede2703a30017e86fae608be2d1b23218de14e0bf0105fbc0a0ab75babfd3`.

### Preserve capture recovery before removing a migrated account

Review of `a2f78278c1f8fe405339c43f9a0a8fe11d243dd6` identified an account-removal path that discarded a modified legacy wrapper's recovery record while its capture command remained active. The existing migration fixture was expanded before the production change. On that baseline, changing another status-line field while retaining the installed capture command, migrating to OAuth, and then removing the account deleted the profile, grant, and restoration record without stopping the command. The focused run failed one test with six assertion issues, including the missing removal error and lost profile, credential, and recovery record. The cause was the unchecked `ClaudeCaptureInstallation.remove` call in `UsageService.removeAccount`.

Removal now uses the existing checked retirement operation before deleting credentials or profile data. If the edited wrapper still runs the helper, removal reports the required repair steps and keeps the profile, grant, wrapper edits, and restoration record. Repairing the wrapper permits subsequent removal. User replacements remain untouched.

The final 24-file source digest is:

```text
8b3557bef2b4f0d4299ec85400a1c7d433a82bcd63d414e632584e49ae7ee51a
```

| Command or check | Observed result |
| --- | --- |
| `swift test --filter claudeMigrationRetiresOnlyItsOwnedCaptureAndPreservesEditsAndCleanupRecovery` on baseline production code with the added assertions | Failed as expected: one test, six assertion issues; build 56.57 seconds. |
| Same focused command after the correction | Passed: one test, zero failures; build 38.12 seconds. |
| `swift test` | Passed: 35 tests, zero failures, comprising 13 XCTest and 22 Swift Testing tests; cached build 5.12 seconds. |
| `swift build -c release` | Passed; 102.80 seconds. |
| `scripts/package_app.sh` | Passed; cached Release build 2.98 seconds. |
| Packaged plist lint, deep strict signature verification, executable architecture, and `git diff --check` | Passed; both executables remain local ad hoc signed arm64 binaries. |

No real account was removed or reconnected. The email UI source is unchanged from the inspected build, and the existing native automation and runtime coverage limits still apply.

The packaged executable SHA-256 is `2bd4ed41976a66788cb2b9b89f127a40dbef85fefc436dd2c4b8e22b0dd1b53e`. The final packaged app was returned to normal real-account mode.

### Preserve valid quota when a limit has no kind

Verified October 11, 2026 on Apple silicon with macOS 27.0.1. Review of `6f008f6d19444c888ae96a2e00d5a4b35369bf2c` identified a required `ClaudeUsageResponse.Limit.kind` field that rejected valid canonical quota windows when an experimental limit omitted that field. The existing overlapping-response fixture was expanded with missing, null, and blank kinds. Against that baseline production code, `swift test --filter claudeOverlappingQuotaShapesOmitMetadataAndUsePrimaryLimitsOnlyAsFallback` failed with `DecodingError.keyNotFound(kind)` after a 3.86-second build. The correction decodes kind optionally and skips incomplete entries before classifying them. Valid canonical and model-scoped readings retain their values, including unknown versus zero.

The tested working source uses the 24-file digest method above:

```text
f145352038c25fa89a3babe055254a5d37820d796bea52be9ee88854c060b008
```

| Command or check | Observed result |
| --- | --- |
| `swift test --filter claudeOverlappingQuotaShapesOmitMetadataAndUsePrimaryLimitsOnlyAsFallback` after the correction | Passed: one test, zero failures; build 3.00 seconds. |
| `swift test` | Passed: 35 tests, zero failures, comprising 13 XCTest and 22 Swift Testing tests; build 0.33 seconds. |
| `swift build -c release` | Passed; 13.90 seconds. |
| `scripts/package_app.sh` | Passed; cached Release build 0.49 seconds. |
| `plutil -lint "dist/AI Usage Stats.app/Contents/Info.plist"` and `plutil -p` | Passed; version 0.1.0/build 1, bundle ID, menu-bar behavior, and minimum macOS 14 retained. |
| `codesign --verify --deep --strict --verbose=2 "dist/AI Usage Stats.app"` and `codesign -d --verbose=2` | Passed on the moved app and helper; ad hoc signature with no TeamIdentifier. |
| `lipo -archs` for both packaged executables and icon resource inspection | Both report `arm64`; icon is present. |
| `git diff --check` | Passed. |
| `open -n "dist/AI Usage Stats.app" --args --show-panel` | Passed; packaged app launched in normal account mode. |

The packaged executable SHA-256 is `fea47f437af66be7d3c2af3ab6bcbfcb4ee10dd71c51dd951d1c6009069a4fe8`. No previous development instance was running when packaging began. The email UI source is unchanged from the visually inspected build. No additional real-mode visual check, provider sign-in, reconnect, removal, or quota probe was performed for this parser correction. The existing live-account, native-automation, Intel, minimum-macOS, VoiceOver, and distribution limits still apply.

### Preserve known account data during same-identity reconnect

Review of `6a0fbcd211e70f1801840329fa4a24f788ada138` identified unconditional snapshot deletion and replacement of a saved email with an omitted optional email in `UsageService.completeClaudeSignIn`. The existing `bindingLegacyIdentityIsolatesConsoleDataAndRequiresManualBalanceConfirmation` fixture was expanded to reconnect the same verified identity without email while its immediate usage request failed. `swift test --filter bindingLegacyIdentityIsolatesConsoleDataAndRequiresManualBalanceConfirmation` failed against baseline production with four assertion issues: lost email, unavailable instead of stale state, lost windows, and lost observation timestamp; build 4.69 seconds.

Same-identity reconnect now keeps the previous snapshot and falls back to its known verified email when the new email is missing or blank. Initial unverified legacy binding still clears the old snapshot and separate Console data and cannot inherit an unverified email. The final fixture also exercises a whitespace-only email and a second failed immediate usage request while preserving independently confirmed balances.

On October 11, 2026, on the same Apple silicon Mac with macOS 27.0.1, the final 24-file source digest was `4743b9daa1113446a5860451a3e4046c4e036ca3e3868a8c99800cedcc31ff50`.

| Command or check | Observed result |
| --- | --- |
| `swift test` | Passed: 35 tests, zero failures, comprising 13 XCTest and 22 Swift Testing tests; build 5.61 seconds. The expanded reconnect fixture passed. |
| `swift build -c release` | Passed; 8.43 seconds. |
| `scripts/package_app.sh` | Passed; cached Release build 0.48 seconds. |
| Packaged plist lint, deep strict signature verification, both executable architectures, icon resource, and `git diff --check` | Passed; local ad hoc signed arm64 app and helper. |
| `open -n "dist/AI Usage Stats.app" --args --show-panel` | Passed after quitting the exact prior development process; normal account mode. |

The final packaged executable SHA-256 is `138e0dfa4ceef4efb568d9141b1e87a824fce3ca110ca4b5c63800e3b0a36a2c`. These reconnect failures were exercised with synthetic fixtures. No real sign-in, reconnect, removal, or quota probe was performed. The email UI source and existing visual-check and runtime limits are unchanged.

## Native usage menu redesign, October 11, 2026

Tested uncommitted changes on baseline `80fb0b6`, branch `codex/native-usage-menu`. Code-and-test source SHA-256: `7c922494872e28f5f2f005a9575616d9f2b71fa4bacb4e01672c52574682ddfb`, using the sorted path/NUL/content/NUL procedure described above. Packaged executable SHA-256: `f92ea607ce26e3b6d86747e56ed4ba5e36c98fe82a8a2f368fc82b0701f40e08`. The build environment was Apple M1 Max, 64 GB memory, macOS 27.0.1 (26A434), Swift 6.4.

The populated status item now uses the same actual `NSMenu` as first run. Account headings use AppKit section headers, verified available at the macOS 14.0 deployment target in the installed SDK. Readings explicitly say percent used; the status-item summary retains remaining quota. The former custom popover, account overview, and countdown timer were removed. Native tracking owns selection and dismissal; model changes are applied on the next opening. README no longer presents the historical dashboard screenshot as current UI.

| Command | Observed result |
| --- | --- |
| `swift test` | Passed: 35 tests, zero failures; 13 XCTest tests and 22 Swift Testing contracts. Debug build completed in 4.24 seconds. |
| `swift build -c release` | Passed without warnings; final Release build completed in 11.47 seconds. |
| `scripts/package_app.sh` | Passed; cached Release build completed in 0.63 seconds. Created version 0.1.0, build 1 app and local ZIP. |
| `plutil -lint "dist/AI Usage Stats.app/Contents/Info.plist"` and `plutil -p` | Passed; bundle identifier `com.parkerrex.ai-usage-stats`, `LSMinimumSystemVersion = 14.0`, `LSUIElement = true`, and icon metadata present. |
| `codesign --verify --deep --strict --verbose=2 "dist/AI Usage Stats.app"` | Passed on the final moved bundle and helper. |
| `codesign -d --verbose=2 "dist/AI Usage Stats.app"` | Ad hoc signature; no TeamIdentifier. This is local bundle verification, not Developer ID trust or notarization. |
| `lipo -archs` for app and helper | Both `arm64`. Intel runtime and universal compilation were not exercised for this change. |
| `file "dist/AI Usage Stats.app/Contents/Resources/AppIcon.icns"` | Valid ICNS present. |
| `open -n "dist/AI Usage Stats.app" --args --demo --show-accounts` | Packaged app launched its existing Accounts window with fictional data after terminating the verified previous development process. |
| `open -n "dist/AI Usage Stats.app" --args --demo --show-menu` | Launch command returned success. Native menu opening was then checked with the diagnostic launch below. |

No provider parsing, authentication, credentials, or persistence code changed. Existing provider tests passed; that does not establish live provider behavior or native accessibility. Runtime menu evidence is recorded separately below. macOS 14 execution, Intel execution, live multi-account refresh during menu tracking, VoiceOver speech, and real system accessibility-preference transitions remain unverified. No performance measurements or distribution change are claimed.

### Native menu lifecycle diagnostic

`open -n "dist/AI Usage Stats.app" --stderr /tmp/ai-usage-stats-menu-baseline.log --args --demo --show-accounts --show-menu --menu-diagnostics` reached `NSMenuDelegate.menuWillOpen` in the unchanged package. The diagnostic reported `surface: native-menu`, a visible status item and visible status-button window, and an anchor frame. It contains no account values or credentials. This disproved the suspected failure to open an initially empty menu before delegate update on this tested macOS version. It does not establish the rendered menu's layout or colors.

### Native runtime evidence and limits

Native automation and a screenshot inspected the existing demo Accounts window. Its sidebar preserved the distinct fictional personal and research emails and explicit unavailable identity. The personal account showed `37% used` and `61% used`, with exact reset and observation dates. The same screenshot showed the unverified account's missing identity; this was an Accounts-window check, not a rendering check of the usage menu's unavailable rows.

The standard application menu exposed Manage Accounts… through accessibility. Selecting it returned the existing Accounts window without creating a duplicate. Accessibility Cancel dismissed the tracked menu. Arrow Down and Return sent through the native automation bridge while a menu was tracking were delivered to the underlying Accounts table and selected Codex instead. Native menu keyboard selection, Return activation, and Escape dismissal therefore remain unverified.

The native menu's actual visual appearance could not be captured through this automation bridge. A windowless app lookup timed out after five seconds; with Accounts open, the capture showed the Accounts window; a screenshot request during native menu tracking reported `Screenshot unavailable`. The lifecycle diagnostic above confirms native status-menu opening and anchoring, but gray section styling, informational-row legibility, long-email layout, scroll behavior, light/dark menu appearance, outside-click dismissal, and real accessibility-preference behavior remain unverified visually. No custom dashboard was retained or substituted as evidence.

The updated packaged app was restored to normal account mode using `open -n "dist/AI Usage Stats.app" --args --show-menu` after terminating the exact demo development process. No account setup, removal, sign-in, plan change, or purchase was performed. The final source digest remained unchanged after runtime checks. These changes remain uncommitted; no push, pull request, merge, or release was performed.

## Provider logos and readable metric columns, October 11, 2026

This continues the uncommitted `codex/native-usage-menu` changes on baseline `80fb0b6c925184f7ae9655de5387ac2e3a60eca2`. Final code-and-test SHA-256: `5d3c784840e63229e48d6449ae408631c269d734bcf6a116ddd44393c76a8264`. Source/resource/packaging SHA-256: `1bf21f340f2d902c70718c7315381a1d5bf47ebb262b4ebffef5ee7626f56b2a`, using sorted relative path/NUL/content/NUL for Package.swift, scripts/package_app.sh, every file under Sources, and Swift files under Tests. Packaged executable SHA-256: `684cb6d86a1083ccc7ea0a3d42d8f54209d8488b01d21ee026f2c60e90dc314f`.

The menu retains AppKit section headers and adds template Claude/OpenAI images from the local opencode checkout. Compact metric labels, semibold values, and secondary timing share native paragraph tab stops. Unknown expiry is still available in tooltip and Connection Details, while absent email uses the saved name in the heading without implying an unverified account UUID. Status and recovery text are concise. No provider, authentication, or credential code changed.

| Command or check | Observed result |
| --- | --- |
| `swift test` | Final source passed 35 tests: 13 XCTest plus 22 Swift Testing, zero failures. Debug build 2.50 seconds. |
| `swift build -c release` | Final source passed without warnings; 12.80 seconds. |
| `scripts/package_app.sh` | Passed; cached Release build 0.33 seconds. Version 0.1.0, build 1 local app and ZIP created with the generated SwiftPM resource bundle embedded. |
| `plutil -lint "dist/AI Usage Stats.app/Contents/Info.plist"` | Passed. |
| `codesign --verify --deep --strict --verbose=2 "dist/AI Usage Stats.app"` | Passed for final moved app and capture helper. Signing remains ad hoc for local use. |
| `lipo -archs` for app and capture helper | Both `arm64`. |
| `sips -g pixelWidth -g pixelHeight -g hasAlpha` for both packaged ProviderIcons PNGs | Both 96 by 96 pixels, alpha present. |
| Byte comparison of source and packaged ProviderIcons files | All six files matched: two PNGs, two SVG sources, LICENSE.txt, and NOTICE.txt. The bundle contains the opencode MIT notice, copyright, original asset paths, and source commit. |
| `git -C /Users/parkerrex/Developer/opencode diff --quiet HEAD -- packages/ui/LICENSE packages/ui/src/assets/icons/file-types/claude.svg packages/ui/src/assets/icons/provider/openai.svg` | Exit 0. Copied SVG/license source files match recorded source commit `388406238bd5ca15564a762840a2362c3a45bd9c`; opencode was not modified. |
| `open -n "dist/AI Usage Stats.app" --stderr /tmp/ai-usage-stats-provider-icons.log --args --demo --show-menu --menu-diagnostics` | Native menuWillOpen reached; diagnostic `providerIcons=4/4` verified all four fictional account headers have decoded images in the actual packaged app. Status item and anchor window were visible. |
| Normal launch with `--show-menu --menu-diagnostics` after stopping the exact demo process | Updated app restored to normal account mode; diagnostic confirms native menu opening and loaded header images without printing account values or credentials. |
| `git diff --check` | Passed. |

An offline AppKit text specimen used the production attributed titles and decoded resources. The temporary Swift harness compiled UsageMenu.swift and InterfaceFormatting.swift against the already built UsageCore, then wrote `/tmp/ai_usage_menu_text_preview.png`. Both agents inspected it: shared columns were legible without overlap, logos were recognizable, full long email text was retained, and currency, credits, and reset units stayed separate. The maximum metric attributed-title width was 378 points in this demo. This is evidence about text drawing and decoded assets, not an actual NSMenu screenshot, native section-header styling, menu image tint, tracking, or dismissal. Direct image drawing in the specimen retained source color; actual menu images are marked as templates.

The previously recorded native-menu capture and keyboard limitations still apply. No repeated CUA attempts or substitute dashboard were used. macOS 14, Intel runtime, VoiceOver, actual native-menu light/dark appearance, and accessibility-preference transitions remain unverified. No performance measurements, commit, push, pull request, merge, or release were performed.

## Compact provider preview and monthly grant integration, October 11, 2026

Tested integrated, uncommitted changes on `codex/native-usage-menu`, baseline `80fb0b6c925184f7ae9655de5387ac2e3a60eca2`. Code-and-test SHA-256: `8c5061287450fcad57f7b9aef332968dad76dab7d6b7d317460227461597bf62`. Source/resource/packaging SHA-256: `20fa6da8483852a37115986d519194e8f503e03853095ff063be1601ff201090`, using the sorted path/NUL/content/NUL procedure and file set described in the previous section. Tested packaged executable SHA-256: `6e9e5a8b1fae02ac791d6724e02f83cc78ac90cb34b26b32ee884e15eb3fc345`.

The populated native status button now uses one cached template image with provider logos and percentages instead of written provider names. Remaining-capacity aggregation, unknown quota, stale indicator, account counts, tooltip, and accessibility descriptions retain their meaning. ProviderIcons supplies the same decoded resources to menu headings and the preview. Bitmap representations are explicitly transparent at 1x and 2x, with point size set before creating each drawing context.

The isolated Console session reads selected-organization balance, plan linkage, and invoices using only GET. Invoice query parameters are preserved. Explicit monthly invoice origin must match the promotional grant's original USD amount, grant date, and expiry one-to-one. A plan allowance is never treated as remaining credit. Supplementary failures retain fresh purchased and unrelated promotional balances while preserving a dated, immediately marked stale last verified monthly reading. The same retained grant cannot also appear as a fresh generic grant or an unknown monthly placeholder. Generic promotions alone cannot hide the monthly placeholder or stored manual fallback; an identified provider monthly grant takes priority over that fallback. Stored manual data remains available in the editor.

Connect Monthly/API Credits… makes setup explicit. A provider-reported Not linked state changes the existing billing action to Open Claude Billing, which opens the official billing page for human linking or claiming. Monitoring never performs a claim, plan change, purchase, or provider mutation.

| Command or check | Observed result |
| --- | --- |
| Initial three-case monthly service fixture run | Compiled, then two passed and one assertion failed because a retained monthly grant still had an unknown monthly placeholder beside it. The placeholder was removed when a specific monthly grant exists; no assertion was weakened. Initial debug compilation took 465.41 seconds. |
| `swift test --filter 'identifiedMonthlyGrantOverridesManualFallbackWithoutRenamingOtherPromotions\|monthlyMetadataFailureRetainsDatedStaleGrantAndFreshPurchasedBalance\|genericPromotionsKeepMonthlyManualFallbackAndUnknownMonthlyState'` | Narrow rerun passed all 3 cases, zero failures; build 1.75 seconds. Fixtures cover organization changes, persisted stale state, original observation date, fresh purchased balances, unrelated promotions, and manual fallback precedence. |
| `swift test` | Integrated final source passed 45 tests, zero failures: 20 XCTest plus 25 Swift Testing. Build 55.64 seconds. |
| `swift build -c release` | Passed without warnings or errors; 163.45 seconds. During compilation a running Swift frontend and progressing build phases were observed; no compiler failure or performance claim is inferred from elapsed build time. |
| `OUTPUT_DIRECTORY=/tmp/ai-usage-stats-monthly-package scripts/package_app.sh` | Passed; cached build 10.38 seconds. Created the tested temporary version 0.1.0, build 1 app and ZIP before replacing the running development bundle. |
| `plutil -lint` and `codesign --verify --deep --strict --verbose=2` on the tested temporary app | Passed; resource bundle and capture helper included. Ad hoc local signing remains the distribution boundary. |
| `lipo -archs` on temporary app and helper | Both `arm64`. |
| Source/packaged ProviderIcons byte comparison | All six PNG/SVG/license/notice files matched. |
| `node --check /tmp/ai_usage_console_observation.js` | Passed for the Console observation script's Swift-decoded JavaScript. This checks syntax, not provider acceptance or a live session. |
| `git diff --check` | Passed. |

The production status-image specimen at `/tmp/ai_usage_status_image_preview.png` was inspected by both agents. Claude-only and Codex-only examples were 44 by 18 points; both providers 97 by 18; unknown quota 57 by 18; stale quota 106 by 18. Logos and digits were legible and separate. These dimensions are produced-image measurements, not a comparison of real status-item frames or a status-bar screenshot. Direct drawing in the specimen retains the source logo color; actual native controls supply template tint. Initial specimen iterations exposed opacity metadata and temporary tint-compositing problems; corrected transparent production representations and a stable-source recompilation produced the final inspected artifact. A temporary specimen compile interrupted by a source edit was repeated successfully; it was not a passing final verification.

The tested temporary bundle was copied into canonical `dist`, with executable and resources compared against the tested artifact and the copied signature reverified. The exact previous development process was terminated before normal `--show-accounts` launch. Profile configuration, browser sessions, and stored credentials were not altered by installation. Launch and process checks establish that the new packaged app runs; they do not establish visible layout through the unreliable native automation bridge.

Live monthly balance/invoice correlation in the app's isolated Platform session has not yet been observed. A saved Platform sign-in may already exist before its first Read; connection count alone does not establish authentication state. Browser inspection confirmed a monthly grant and a monthly invoice label, but raw response capture and the native app automation bridge were unreliable; this is not evidence that the new integration has completed a live read. Native keyboard/tint/appearance, macOS 14 and Intel execution, and multi-account live Console refresh remain unverified. The read-only matching and fallback results above are fixture evidence. Publishing disposition was subsequently authorized, but no publication or merge is claimed by these checks.

## One management window and distinct Platform authentication, October 11, 2026

Final tested uncommitted source on the same baseline and branch: code-and-test SHA-256 `795cd11d56255eb4eca1bdaecb1404d66db89e74686532ac50f144c4e7551a5c`; source/resource/packaging SHA-256 `c2fdbb8995170d62fc6afebf505c4e450d2f9fc958ed2dced50482eafa2be71a`; packaged executable SHA-256 `b7f8c4fd7ea640fb0d77460feadefed978ca29f84c90e75da05a388bfe10b64e`. Digest procedures remain as described above.

Settings now selects General inside Accounts, including the standard app-menu Settings… command and Command-comma. The status menu has one Manage Accounts… command and no Settings command. The Platform browser is a per-profile view controller embedded in the same detail area, with Back to Account and explicit platform.claude.com authentication separate from Claude subscription sign-in at claude.ai. Back restores the selected account, unfinished editor fields, and prior window size. The empty account list selects General. Removing the displayed Platform account detaches that pane rather than displaying its old session beside another account.

The per-profile WKWebsiteDataStore identifiers, account/organization guards, data reads, and browser parking remain intact. Closing the management window pauses/parks visible browser activity without signing out. Retiring a controller prevents later loads, cancels its waiters/task, and removes the observation handler. Subscription sign-in is now an attached sheet with its existing OAuth/loopback logic unchanged; ordinary dialogs use attached sheets too. No separate Settings or Platform window is created. Startup state is read through the existing ServiceManagement API; validation did not register or unregister launch-at-login.

| Command or check | Observed result |
| --- | --- |
| `swift test` | Passed 46 tests, zero failures: 21 XCTest plus 25 Swift Testing. Final debug build 2.62 seconds. Includes the no-provider-ID grant guard: missing IDs cannot become persistent monthly identities and suppress a different later promotion by array position. |
| `swift build -c release` | Passed without warnings/errors; 257.23 seconds. |
| `OUTPUT_DIRECTORY=/tmp/ai-usage-stats-management-package scripts/package_app.sh` | Passed; cached Release build 3.33 seconds. Created version 0.1.0, build 1 temporary app and ZIP. |
| `plutil -lint` on the temporary app | Passed. |
| `codesign --verify --deep --strict --verbose=2` on temporary and canonical copied apps | Both passed; helper verified. Signing remains ad hoc for local use. |
| `lipo -archs` for temporary app and helper | Both `arm64`. |
| ProviderIcons source/resource comparison | All six icon/source/license/notice files matched the packaged bundle. |
| Temporary-to-canonical bundle and ZIP byte comparison | Every bundle file and ZIP matched the tested artifacts after installation into `dist`. |
| `open -n "dist/AI Usage Stats.app" --args --show-accounts` | Returned success after terminating the exact prior development process. The updated normal app is running with Accounts requested. Sessions, stored profiles, and credentials were not removed or copied out. |
| `git diff --check` | Passed. |

Before replacement, one bounded `sample 67082 1 1 -file /tmp/ai-usage-stats-main-thread.sample.txt` examined the prior integrated app because native automation lookup timed out. Its main thread was idle in NSApplication.run/event routing, CFRunLoopServiceMachPort, and mach_msg2_trap; no app-code blocking or hang was observed in that one-second interval. Only main-thread function names were inspected, without secret values. This supports a tool-inspection limitation and does not prove visible window layout.

The observed live subscription dialog reported an account identity mismatch. That observation does not establish whether a separate Platform session was signed in elsewhere. A zero stored Console-connection count also does not establish authentication state before Read. Persistent Platform cookies were preserved during replacement so the embedded pane can reuse any existing sign-in. Live Platform credit retrieval, real monthly invoice correlation, and the new one-window keyboard/layout checks remain pending runtime review. Existing native-menu capture, older macOS, Intel, VoiceOver, and system accessibility-preference limits remain unchanged. Source/lifecycle review and builds are separate evidence from those live checks.

## Quiet Keychain checks and stable local signing, October 11, 2026

Tested uncommitted changes after `d255903226af40485aaba05406d1572be1915241`. Code/test SHA-256: `88db78e926fdf819141af8b96a47f4f6dfdf98d4065d5862344c153b9696ab44`; source/resource/packaging SHA-256: `1e51622389800ae76c22b1430ed16d798286812e0e7d8fe6ed382f075940e93b`; signed executable SHA-256: `4bec275dfead056499c0ca8815e37b868aa283959abfc2e206016174124d750a`. Earlier digest procedures apply.

Background file-based Keychain operations suppress interaction under a shared lock and restore the prior process policy, retaining LAContext/UI-fail checks. Denied reads preserve credentials and observations. Connection Details → Allow Keychain Access… explicitly reads the existing bound credential without OAuth/provider requests or replacement, preserves drafts while busy, then permits ordinary refresh. Fresh invoices also prevent recovery of an obsolete cached monthly grant when only link-state fails. That fixture's competing baseline run was canceled before execution; no baseline failure is claimed.

| Command/check | Observed result |
| --- | --- |
| `swift test` | 49 passed, zero failures: 21 XCTest plus 28 Swift Testing; build 104.92 seconds. |
| `swift build -c release` | Passed, 373.53 seconds; four unsuppressed deprecation diagnostics for retained legacy Keychain UI-policy/UI-fail APIs. |
| Canonical script with selected existing personal Apple Development identity | First bounded signing attempt passed; cached build 6.78 seconds. Public identity identifier remains only in ignored .local-signing-identity. No security workaround, ACL/trust/partition change, or certificate creation. |
| `plutil -lint`, `codesign --verify --deep --strict --verbose=2`, resource/byte comparison | Passed on temporary/canonical apps; helper and all six provider assets/notices included. Canonical app/ZIP match tested artifacts. Both executables are arm64. |
| Designated requirement and unlaunched resource-modified copy | Certificate plus bundle identifier; changed code hash with identical requirement and valid signature. Requirement SHA-256: `f744c98a159127b3cd4f458eb9851f19347e37cd31d7f5f516d8ebf18c8027d0`. Copy never launched. |
| `open -n "dist/AI Usage Stats.app" --args --show-accounts` | One normal signed launch; sole PID 74082. Tools did not invoke explicit recovery or query production credentials. |
| `git diff --check` | Passed. |

The user confirmed no automatic Keychain dialog appeared after this restart. CUA app lookup still timed out around 6.5 seconds, so repeated Check Usage, explicit permission recovery, keyboard/draft UI behavior, and live Platform monthly retrieval remain unverified through automation. Profiles, credentials, and browser sessions were retained.

Development signing is neither Developer ID distribution trust nor notarization. A change from ad hoc identity can require one explicit permission for existing items; the copy test does not establish real ACL acceptance across future certificates/builds. Deprecated APIs, older macOS/Intel execution, and broader runtime no-prompt behavior remain limitations.

## Login identity without account naming, October 11, 2026

Tested changes after `a38aa327af176fd6ebf5adb4f01731e29f732bb3` on `codex/use-account-login`. Accounts has no Name field, Save Name action, or add-account name prompt. The menu, sidebar, detail heading, and Platform pane use the verified login email for both providers; stored labels remain an honest unavailable-email fallback. Codex email comes from its existing validated account read, retains a known email only for the same identity, and cannot overwrite it after a different-account error. No credential, cookie, or profile migration was performed.

- `swift test`: 50 passed, zero failures (21 XCTest + 29 Swift Testing); final build 19.98 seconds. The focused Codex fixture verifies email persistence, omission, and rejection of another login.
- `swift build -c release`: passed in 106.03 seconds; four existing Keychain deprecation warnings retained.
- `CODE_SIGN_IDENTITY=<existing local identity> OUTPUT_DIRECTORY=/tmp/ai-usage-stats-login-package scripts/package_app.sh`: passed on the first bounded signing attempt; cached Release build 0.31 seconds.
- `plutil -lint`, `lipo -archs`, provider-resource comparison, and `codesign --verify --deep --strict --verbose=2`: passed; app/helper are arm64, version 0.1.0 build 1. The certificate-based designated requirement is identical to the prior canonical app. This is local development signing, not notarization.
- Canonical bundle/ZIP byte comparison passed before one normal `--show-accounts` launch, PID 77740. The exact previous development process was stopped; credentials and browser sessions were retained.
- `git diff --check`: passed.

Code/test SHA-256: `2e9345c5cafeb29c67382e4b8fe29292d5505277773f2b08bd5cd0ef358a8fb7`; source/resource/packaging SHA-256: `104f92216883a491516b58ac46d8430cb37cc551ad20f1cfaa97023957058fe0`; signed executable SHA-256: `2aabe6907b9f0630daffc10c3d7218f2adf7a0513d5aa28168cd8cdb785cb1f2`. Earlier digest procedures apply. On macOS 27.0.1, bundle-ID CUA inspection verified the login email in the actual Accounts sidebar/detail heading, no Name field or Save Name button, and an attached Claude add-account sheet with explanation/Cancel/Sign In and no name prompt. Cancel returned to the same account without starting authentication. The authentication-required state retained its prior reading; no automatic permission dialog was observed during these checks. Escape was blocked by the automation focus guard, so keyboard dismissal remains unverified. No private screenshot or account values are published. Intel/minimum-macOS execution, explicit Keychain recovery, and live Platform balances remain unverified. The baseline naming controls were confirmed in source; no automated baseline UI reproduction is claimed.

## Compact account overview, October 11, 2026

Baseline `f25601955ad9b2a64be12ed84e952e472e636f55` was inspected in the actual Accounts window. Three problems informed this focused change: diagnostics buried usage, simultaneous connection actions dominated the view, and paragraph-style values/reset times were hard to scan. Apple's [Layout](https://developer.apple.com/design/human-interface-guidelines/layout?changes=lat_3__1_2) and [Disclosure controls](https://developer.apple.com/design/human-interface-guidelines/disclosure-controls) guidance informed aligned important content and on-demand detail. No web UI, cards, progress bars, or provider changes were introduced.

Usage and Credits now have native aligned label/value/timing rows. One attention line and relevant recovery action replace diagnostic paragraphs; Account holds details, reconnect, Platform management, billing, and removal. Exact dates, errors, currency/reset units, and source information remain in tooltips/Connection Details. Manual entry stays collapsed and its existing fields are untouched by reading redraws.

- `swift test`: final source passed all 50 tests (21 XCTest + 29 Swift Testing), zero failures; cached build 2.49 seconds. No deletion-only tests added.
- `swift build -c release`: final source passed in 13.19 seconds; four existing Keychain deprecation warnings retained. An earlier Release was intentionally stopped before two reviewed presentation corrections; it is not claimed passing.
- `CODE_SIGN_IDENTITY=<existing local identity> OUTPUT_DIRECTORY=/tmp/ai-usage-stats-overview-package scripts/package_app.sh`: passed first bounded attempt; cached build 0.33 seconds.
- `plutil -lint`, `lipo -archs`, provider-resource comparison, `codesign --verify --deep --strict --verbose=2`, and canonical bundle/archive byte comparison: passed. App/helper arm64, version 0.1.0 build 1; certificate-based designated requirement unchanged. Local signing is not notarization.
- Exact prior development process stopped before dark demo `--demo --show-accounts --dark-appearance` launch. Credentials, profiles, and browser sessions retained.
- `git diff --check`: passed.

Code/test SHA-256: `e9eb3d4c756b1e7489d892a5df8a5fc4e59ce1f80e4ca254de9ff06a056de602`; source/resource/packaging SHA-256: `9b1cde21577ff39c210b4a210b5dff4eb79cd450f429bf88755e58b3113a93e9`; signed executable SHA-256: `576f31edbc3d0876fea663185b59619dd4ceeba1d67217b361d64f884037f758`. Earlier digest procedures apply. On macOS 27.0.1, dark-mode demo AX/screenshots verified populated Claude and Codex rows, aligned values/timing, distinct USD/credits/reset units, manual provenance/expiry, and unknown balance. All main readings fit the default window without scrolling, with no diagnostic paragraph or connection-button stack. A third-profile selection and bounded AX retry failed in the native automation pipe, so additional demo-profile/menu coverage is not claimed. The exact demo process was stopped before normal `--show-accounts` launch (PID 83850). Normal light-mode AX/screenshots verified aligned usage/unknown credits and one access-required notice with Review Access, fitting the default window. Account menu exposed Details/Reconnect/Platform/Billing/Remove. Details retained exact dates/source/errors; Tab then Space closed its Done button in the same window without invoking Keychain recovery. An unsaved manual amount survived Refresh, was restored to its original empty value, and the editor collapsed without Save/Clear. One capture failed after editing, but the next AX read verified the local value. Command-comma opened General in the same window, and account selection returned to the overview. No automatic permission dialog appeared; no credentials, sign-in, Platform session, purchases, or settings were changed. Long-email profile, VoiceOver/full menu keyboard behavior, older macOS/Intel execution, explicit permission recovery, and live Platform balances remain unverified.

## Window and Platform connection presentation, October 11, 2026

Changes after `a0953a3d21b32b3025bd727e978644f8116f0ad0`: window titled AI Usage Stats; Add Account below the scrollable list; compact native Platform wrapper with one instruction/action and a real organization picker only after discovery. The baseline Platform controller repeated instructions, showed premature actions and an empty picker, and lacked a clear next step. It was inspected live after the uncommitted title/footer build was installed, while that controller still matched the baseline source. Existing Apple Layout/Disclosure guidance informed this focused correction. The isolated browser, GET/account/org guards, cancellation/parking, and credential behavior remain intact. Discovered Platform login is clearly labeled, with the intended Claude account separately shown when different. Errors/dates remain in tooltips and on-demand details; supplemental fetch failure is still visible. Background refresh does not navigate or reveal the browser.

- `swift test`: final guarded source passed 50 tests (21 XCTest + 29 Swift Testing), zero failures; reported build 113.90 seconds.
- `swift build -c release`: passed, reported 928.09 seconds; four retained Keychain deprecation diagnostics. One bounded driver check found no stale prior process; compilation advanced and completed without a source workaround.
- Canonical `scripts/package_app.sh` with existing local signer and temporary output: passed. An initial 60-second cached-build timeout occurred before output-directory creation/signing. A longer build allowance kept signing separately bounded to 60 seconds; signing passed without security changes. Metadata, arm64 app/helper, provider resources, strict signature, and canonical bundle/archive bytes verified.
- Exact previous development process replaced by one normal `--show-accounts` launch, PID 200; current sessions/profile/credentials retained.
- `git diff --check`: passed.

Code/test SHA-256: `35afb6969fe9ebc0abfbe0e2e020087163426e87c834690b356c88f673560906`; signed executable SHA-256: `6e48dd5f53400ba2662ae205331b3dc74166e2e909015524c2bf8ec1308b67db`. Existing digest procedure applies. Two bounded bundle-ID CUA binds and a reset/global inventory check timed out. One `sample 200 1 1 -file /tmp/ai-usage-stats-final-main-thread.sample.txt` inspected main-thread function names only: NSApplication.run/event routing → CFRunLoopServiceMachPort → mach_msg2_trap, with the process alive and 0% CPU. No app-code startup block was observed in that interval; this does not prove visible layout. The user reported the installed layout is better; this is visual feedback, not complete control/keyboard/failure verification, so those interactions are not claimed checked; matching/other/unknown-email auto-return and selected/multiple-org flow are source-reviewed, not live-tested. Initial compile hit an NSViewController.title name collision, corrected by headingTitle; an obsolete test driver was canceled before the final identity/copy review fixes. Neither run is claimed passing. No new layout-only tests or signing-requirement experiment. Profiles, credentials, and browser sessions remain untouched. Older macOS/Intel, live selected/multiple-organization linkage, explicit permission recovery, and notarization limits remain unchanged.

PR6 review correction: Refresh Credits now refers only to the stored selected organization; a different selection says Switch Organization. Existing reads/binding behavior is unchanged. Corrective source passed 50 tests (21 XCTest + 29 Swift Testing), zero failures, build 136.30 seconds; Release passed in 246.32 seconds. Corrective canonical package passed (cached build 6.51 seconds); metadata, arm64 app/helper, provider resources, strict signature, and canonical bundle/archive bytes verified. Corrective executable SHA-256: `652267c7d4d8a3a22ffe4143e1588ff3642febf8741e8bedf2d239e779ca31bf`. PID 200 had already exited before installation; the initial open returned success without a surviving process. A single authorized startup check confirmed an active GUI session and found no app crash reports; one packaged launch returned 0 with empty stderr and a delayed 10-second check found canonical PID 3079 running. The earlier exit/absence cause is unknown; no raw-binary launch, trust/security change, credentials, or repeated diagnostic loops. Code/test SHA-256: `e2ac294b6d4abdf744a72240e17dcdf04160675fcb863d1f9f60336098963ad4`. The longer native inspection attempt also failed explicitly with “Sky Computer Use native pipe startup failed.” Review P1 remains an unresolved interaction-verification gap; user feedback does not prove selected/multiple-organization or email-match transitions.


## Repository Apple HIG skill, October 13, 2026

Reviewed documentation and the new skill as uncommitted changes after `6fe4d71a0e29e8a41665852ed09c470a6ba9c43a`. Adapted the source Apple HIG skill for this app's AppKit menu, single management window, account data, and isolated Platform sign-in. Browser measurement scripts and their Bun dependency were omitted. The rubric contains 18 native requirements with separate Apple and project authorities; catalog verification dates describe guidance review, not successful app tests.

Apple's design update index, applicable live HIG pages, and Apple-hosted documentation JSON informed the review. Current menu-bar guidance replaces the older popover recommendation in `docs/design/apple-guidance.md`. The macOS-specific accessibility table gives 28-point default and 20-point minimum controls. SDK availability claims retain their October 9 verification date.

| Command or inspection | Result |
| --- | --- |
| `python3 /Users/parkerrex/.codex/skills/.system/skill-creator/scripts/quick_validate.py .agents/skills/apple-hig-expert` | Passed: `Skill is valid!` |
| Local Markdown links, project source paths, rubric YAML and IDs | Passed; 18 unique requirement IDs and all referenced local paths exist. |
| Review for retained source-project paths and em dashes in the skill | Passed. |
| `git diff --no-index --check /dev/null` for each of the seven new skill files | No whitespace diagnostics. An initial check wrapper incorrectly required exit 0; the corrected wrapper accepts exit 1 for differing files only when both diagnostic streams are empty. |
| `git diff --check` | Passed for tracked documentation changes. |

Swift tests, Release build, packaging, and native interaction checks were skipped because this change contains only skill resources and documentation. No app accessibility, layout, performance, provider, or distribution result is claimed from this review.


## Native HIG improvements, October 13, 2026

Tested uncommitted changes after `0485bbec496a18c32cdecd96e087a586f7c586bf` on macOS 27.0.1, macOS 27.0 SDK, Apple Swift 6.4, arm64. Grok 4.7 implemented the source changes through the installed `agent` CLI (Grok Build), with separate ownership for credit formatting/copy, account layout/actions, and Settings focus. Codex orchestrated, reviewed every source diff, and performed verification. The Accounts worker reached its 32-turn limit after writing its complete diff; this is a worker execution limit, not a passing check. The orchestrator subsequently verified that source.

The preceding audit observed crowded actions, truncated demo emails, and Settings focus remaining in the account table. Its existing bundle was `bbcff5c645bb6416b06b23ef9f2fceaa74a1a66938e067d7b8bf21d44ba0b04f`; its exact build-to-commit provenance was not established. A separate formatter reproduction used `git show HEAD:Sources/AIUsageStats/InterfaceFormatting.swift` at the named baseline: six cases passed and the unknown available grant failed, displaying `available` instead of `Unknown`.

The header now contains Refresh and Account; unconnected Claude API setup is beside Credits. The sidebar is 228 points wide, with 66-point ordinary rows and 82-point wrapped rows. Settings focuses Launch at login and exposes a selected native gear state. Shared credit formatting distinguishes an available grant with unknown amount from zero and Unlimited. Production and demo fallback descriptions use accurate provider-specific explanations.

| Command or inspection | Observed result |
| --- | --- |
| Baseline `swift test` | Passed 58 tests: 21 XCTest plus 37 Swift Testing; build 2.92 seconds. |
| Final `swift test` | Passed the same 58 tests, zero failures; build 8.35 seconds. |
| `swift build -c release` | Passed in 27.51 seconds; four existing Keychain deprecation warnings retained. |
| `scripts/package_app.sh` | Passed using the existing configured local identity; cached Release build 0.34 seconds. |
| `codesign --verify --deep --strict --verbose=2 "dist/AI Usage Stats.app"` | Passed on the actual final bundle. |
| `lipo -archs "dist/AI Usage Stats.app/Contents/MacOS/AIUsageStats"`; `lipo -archs "dist/AI Usage Stats.app/Contents/MacOS/UsageCapture"`; `plutil -lint "dist/AI Usage Stats.app/Contents/Info.plist"` | Both executables arm64; metadata valid, version 0.1.0 build 1, macOS minimum 14.0, LSUIElement enabled. |
| Provider-resource byte comparison and app icon inspection | All six provider icon/source/license/notice files matched; AppIcon.icns present. |
| Temporary shared formatter verification | Seven cases passed: unknown available grant, measured zero, Unlimited, authentication failure wording, unavailable amount, credit units, and reset count. |
| Temporary native menu composition verification | Seven cases passed: unknown grant wording, absence of a falsely known amount, credit/reset units, exhausted quota, missing-email fallback, and read-only informational items. This constructs actual NSMenuItems but does not establish interactive status-menu behavior. |
| `git diff --check` | Passed. |

The focused executables were compiled against the Debug UsageCore module with these commands; the temporary scripts are local verification artifacts, not new repository test infrastructure:

```sh
swiftc -swift-version 6 -I .build/out/Products/Debug -L .build/out/Products/Debug -lUsageCore Sources/AIUsageStats/InterfaceFormatting.swift /tmp/ai_usage_credit_formatting_verification.swift -o /tmp/ai_usage_changed_credit_verification
/tmp/ai_usage_changed_credit_verification
swiftc -swift-version 6 -I .build/out/Products/Debug -L .build/out/Products/Debug -lUsageCore Sources/AIUsageStats/InterfaceFormatting.swift Sources/AIUsageStats/UsageMenu.swift Sources/AIUsageStats/ProviderIcons.swift /tmp/ai_usage_menu_verification.swift -o /tmp/ai_usage_menu_verification
/tmp/ai_usage_menu_verification
```

The menu harness initially expected colon-separated plain titles and reported three passes/four failures. AppKit replaces the item's plain title with the tab-separated attributed title. The corrected harness normalizes displayed whitespace and retains the same label/value assertions; its narrow rerun passed all seven. No production assertions or errors were suppressed.

Packaged inspection sessions used `open -n "dist/AI Usage Stats.app"` with `--demo --show-accounts`, then separately `--demo --show-accounts --dark-appearance`, `--demo --demo-empty --show-accounts`, and `--demo --demo-load-error --show-accounts`. Each previous development instance was terminated before the next launch. Native AX/screenshots verified full ordinary emails, complete two-line long identity, missing-email fallback, distinct quota/currency/credit/reset units, Unknown grant amount, the two-control header, Credits setup placement, and selected Settings appearance in light and dark modes. Command-comma focused the login checkbox in populated and empty states. Tab reached Account; Space opened it, Down selected Details, Return opened the sheet, and Return dismissed Done. One initial batched menu action hit an automation state-change error; the stepwise retry succeeded. Retry Loading Accounts restored the populated demo interface.

The normal final app was launched with `--show-accounts`. Its live unavailable-credit tooltip used the corrected Claude Platform explanation. An unsaved fictional amount of 13.25 survived Settings navigation and a completed ordinary read-only Refresh, with the selected manual category retained. The field was restored to its original empty value and collapsed without Save or Clear. A stale automation index was rejected during the first restore attempt; a fresh index successfully restored the field. Account removal displayed the intended account and focused Cancel; Cancel left the profile intact. No sign-in, balance save, startup preference change, explicit credential action, or Platform browser action was performed. The normal final instance remains running.

Source/test SHA-256: `3e5bc16edf56698481e1c8cfd0cf53362600befe152835e397c5600d67f82efc`; signed executable SHA-256: `d0bf09e80fa83c0189902f6ed01818dcb3de3c9f9f96f7639581089f1bc33783`. The source digest covers sorted repository-relative Swift paths under Sources and Tests plus Package.swift, hashing each path, NUL, content, NUL. A final comparison confirmed source remained identical to the tested/package inputs.

Direct status-menu tracking/keyboard behavior, minimum-window-size runtime layout, connected Platform action, VoiceOver speech, measured contrast, real accessibility-preference transitions, older macOS, Intel execution, and notarization remain unverified. Bounded resize attempts did not establish a changed window size, so no minimum-size pass is claimed. Existing native sizing/source review is separate evidence. Local signing verifies integrity, not public distribution trust.


## PR landing verification, October 14, 2026

Source commit `33365999cf86636b0907dc18c2ff29fd70e9f222` was rebased onto the merged HIG guidance at `cd5b094b82be89ca6267363bfdaf8fe5e3f1fcea`. The verification paragraph added afterward changes documentation only. The submitted source retains SHA-256 `3e5bc16edf56698481e1c8cfd0cf53362600befe152835e397c5600d67f82efc`, matching the October 13 native inspection.

After rebase, `swift test` passed 58 tests (21 XCTest plus 37 Swift Testing), zero failures, build 2.88 seconds. `swift build -c release` passed in 18.28 seconds with the four existing Keychain deprecation warnings. Canonical `scripts/package_app.sh`, using the existing configured signer and `OUTPUT_DIRECTORY=/tmp/ai_usage_pr_native_package`, passed. `codesign --verify --deep --strict --verbose=2 "/tmp/ai_usage_pr_native_package/AI Usage Stats.app"`, `lipo -archs` for its app executable, and `plutil -lint` for its Info.plist passed; the executable is arm64. The temporary formatter and menu checks were recreated after their prior /tmp source files were unavailable; both then passed seven cases against the rebased source.

The rebased packaged app was opened with `--demo --show-accounts` and separately `--demo --demo-load-error --show-accounts`. Native AX/screenshots verified readable ordinary and two-line identities, distinct credit/reset units and Unknown amount, Command-comma focusing Launch at login, selected Settings state clearing on account selection, and loading-error retry restoring accounts. Account → Down → Return opened Details, and Return dismissed Done. A startup inspection timeout and a process selector that required launch arguments were corrected before the comparison; no source workaround or trust change was made. Prior detailed draft/removal and appearance evidence remains tied to the unchanged source digest. Direct status-menu interaction, minimum-size runtime layout, VoiceOver, connected Platform flow, accessibility preference transitions, older macOS/Intel, and notarization remain unverified.

Local source review found no actionable regression. An optional Grok 4.7 read-only review did not finish and was stopped; it is not counted as passing verification. Implementation model attribution remains Grok 4.7 via agent/Grok Build; orchestration and completed review/verification were performed through Codex.


## Home reset calendar, October 14, 2026

Final verification used the uncommitted working tree after `b3a7d87208821d68b368e7a8f799b9d7324fd109`, on MacBookPro18,2, arm64, macOS 27.0.1 (26A434), the macOS 27 SDK, and Apple Swift 6.4. Implementation started from `0485bbec496a18c32cdecd96e087a586f7c586bf` plus the existing working-tree edits. An isolated managed worktree preserved that starting state. Each modified original file still matched the saved starting content before integration; unrelated edits and the subsequent account-navigation/documentation commits were retained. The source/test digest below identifies the actual checked inputs independently of commit history.

Grok 4.7 wrote the initial implementation through the installed `agent` CLI, identified locally as Grok Build 1.0.52. Separate workers owned UsageCore data, native Home views, and window integration. Grok stopped with HTTP 402, usage balance exhausted. The user authorized Codex to complete the work. Codex corrected compilation, reviewed the source and data contracts, fixed native pointer and accessibility issues, and performed the final checks. An independent source review identified ordinary Codex meter classification and passed earned-reset expiry defects; both fixes have focused retained tests. No new provider endpoint, model request probe, reset consumption, dependency, or distribution change was added.

Home is the default management-window surface, with two-week/month date navigation, account filtering, native event popovers, an account table, reported plan metadata, and provider window durations. Only current measured quota resets enter the calendar. Unknown, historical, inactive, failed, and sign-in states remain explicit. Earned reset expiry remains separate from quota reset dates and monetary credits.

| Command or inspection | Observed result |
| --- | --- |
| `swift test` in the original checkout after integration | Passed 84 tests: 21 XCTest, 54 UsageCore Swift Testing, and 9 native Home/formatting tests, zero failures; build 9.41 seconds. |
| `swift test --filter AIUsageStatsTests` in the isolated worktree | Passed all 9 focused tests. Tests cover actual native button hit testing/action dispatch, ordinary versus additional Codex meters, zero/unknown/partial readings, and independent earned-reset count and expiry freshness. |
| `swift build -c release` in the original checkout | Passed in 18.97 seconds. Existing Keychain deprecation warnings retained. |
| `scripts/package_app.sh` in the original checkout | Passed with the existing configured local identity; cached Release build 0.30 seconds. |
| `codesign --verify --deep --strict "dist/AI Usage Stats.app"` | Passed on the final bundle. |
| `plutil -lint "dist/AI Usage Stats.app/Contents/Info.plist"` | Passed. Bundle version 0.1.0 build 1, macOS minimum 14.0, LSUIElement enabled. |
| `lipo -archs "dist/AI Usage Stats.app/Contents/MacOS/AIUsageStats"` and the same command for `UsageCapture` | Both executables arm64. |
| Provider-resource comparison and app icon inspection | All six provider resources matched their source bytes; AppIcon.icns present. |
| `git diff --check` | Passed. |

Initial runs encountered compiler errors in new code and tests, including an identity member reference, SDK enum/accessibility names, a formatter name collision, tuple-array equality, and omitted fixture initializer arguments. Those errors were corrected; failed runs are not counted as passing verification. No assertion was weakened to hide a failure.

Packaged demo inspections used these arguments with `open -n "dist/AI Usage Stats.app"`; the prior development instance was closed between launches:

- `--demo-home --show-home`, and separately `--dark-appearance`: four fictional accounts, nine current resets, legible today date, one accessibility button per event, separate model-scoped limits, exact popover identity/dates, and quota/earned-reset units.
- `--demo-reading-states --show-home`: three current Claude events only; sign-in failure, historical Codex values, unknown data, and disabled demo reconnection/refresh actions.
- `--demo --demo-empty --show-home`: setup message and no calendar toolbar.
- `--demo --demo-load-error --show-home`: focused Retry Loading Accounts; Space restored populated readings and the toolbar.

Native actions verified click/Return popovers, Escape dismissal and focus return, View Account navigation, month switching, Next/Today date navigation, a period without reported resets, keyboard account filtering of both calendar and table, vertical table scrolling, and Command-comma focus on Launch at login without changing it. Settings-to-Home navigation retained the filter. Native Zoom was observed in the worktree build. Final light/dark appearance and accessibility trees were inspected; this does not establish measured contrast or VoiceOver speech.

Pointer-only hover was implemented with native tracking areas, but the automation did not establish its behavior in an active foreground window. Bounded drag attempts did not establish minimum-size layout or column resizing. A separate `--demo-home --show-menu` inspection timed out twice in computer-use state retrieval; its exact demo process was terminated and a normal Home inspection restored, so direct status-menu tracking is not claimed verified. Minimum macOS 14 runtime, Intel execution, actual accessibility-preference transitions, live multiple-account provider responses, sign-in/reconnection, preserved manual drafts across Home navigation, Platform browser transitions, and notarization remain unverified for this feature. Provider parsing, account separation, missing fields, failure handling, plan precedence, and persisted older snapshots were exercised with redacted fixtures and existing tests.

The normal final packaged app was launched with `--show-home`; a redacted native-state inspection confirmed selected Home, the calendar, and no demo label. It remains open for use. No sign-in, manual balance save, startup preference change, or credential action was performed through the UI. Normal monitoring retains its existing read-only behavior.

Source/test SHA-256: `268fceba2ee653c45af37be661b9d20282476b495b42a95b62973a57ef7a1c52`; signed executable SHA-256: `a4d405f1d19d99c322b4ecb441527300945d51207155538e7a36825ffd28487d`. The source digest covers sorted repository-relative Swift paths under Sources and Tests plus Package.swift, hashing each path, NUL, content, NUL. A final comparison confirmed unchanged checked/package inputs. The app and ZIP are local development artifacts; signature integrity does not establish Developer ID trust or notarization. The initial implementation pass ended before committing or publishing this feature.


## Home warning review corrections, October 14, 2026

PR #13 identified two recovery-warning errors at baseline `d778ce4d9419cc1e9b1a0ea652ffab7568952ce2`. In the packaged baseline, launch with `--demo-reading-states --show-home`, then filter to Claude personal: only its healthy table/calendar data remained, but the unavailable-reading warning stayed visible. `HomeViewController.render` evaluated all accounts instead of the filtered accounts. The retained `inactiveQuotasDoNotRequestRecovery` test also failed once on baseline production code: `HomeInterfaceFormatting.attentionNeeded` treated a valid inactive summary as unavailable. Its authentication-failure case still required recovery.

The warning now evaluates the same filtered accounts as the table and treats current inactive quotas as valid metadata. `swift test` passed 85 tests (21 XCTest, 54 UsageCore Swift Testing, 10 Home tests), zero failures, build 3.22 seconds. `swift build -c release` passed in 17.26 seconds; canonical packaging and strict signature validation passed. On macOS 27.0.1, the corrected packaged demo showed the warning for All accounts, omitted it for healthy Claude personal, and retained it for Claude studio requiring sign-in. The two source changes and focused test were reviewed; `git diff --check` passed. Earlier runtime and distribution limits remain in effect.

Corrected source/test SHA-256: `243d516f35b42860b7fb0ca5ec9eab8e6c8a7bdc9d53f06a900dcd4ae0e4f451`; signed executable SHA-256: `ee882db5670686f4dcb23b09b59d055e353ba089fd826951677f1cf2b1491a68`. This record describes the checked working-tree inputs after the named baseline; the PR records the committed tested revision.


## Stable account window and direct actions, October 14, 2026

Tested uncommitted changes after `7b4710fdde738aca84211e99476afa1f58619c9e` on macOS 27.0.1 (26A434), MacBookPro18,2, arm64, macOS 27 SDK, and Swift 6.4. Codex implemented and verified this focused follow-up using the project Apple HIG skill. Current Apple-hosted documentation JSON for [Windows](https://developer.apple.com/design/human-interface-guidelines/windows), [Buttons](https://developer.apple.com/design/human-interface-guidelines/buttons), and [Lists and tables](https://developer.apple.com/design/human-interface-guidelines/lists-and-tables) was checked for user resizing, standard controls, clear control meanings, and scrolling. The shared frame policy and direct account controls implement the user's requested product behavior; this is not an accessibility certification.

Baseline `swift test --filter accountNavigationPreservesTheUserWindowSize`, with the new test applied to unchanged baseline production code, failed with two frame assertions: a 1360 × 872 point native window frame became 700 × 572 points in account details and Settings. The cause was the per-surface limits and saved sizes in `AccountsWindowController.setSection`/`applyWindowLimits`. The corrected test passes across account, Settings, and Home navigation after a user resize.

All pages now use the shared 1020 × 640 minimum, 1280 × 780 default, and 1680 × 1040 maximum content range. Navigation changes the page without resizing the window. The Account actions menu is removed. Direct Refresh, Reconnect, Billing, and API credit controls sit on the account page; selectable Connection Details contains the previously hidden identity, source, exact dates, reading details, and recovery information. Plus/minus buttons below the sidebar provide setup and selected-account removal. Add uses an attached provider-choice sheet; removal retains the existing UUID-bound confirmation. Home and Settings disable removal. API-credit disconnection uses the existing identity-bound operation, blocks overlapping Console work, retains the isolated browser sign-in, and clears the obsolete credit error after a successful disconnect.

| Command or inspection | Observed result |
| --- | --- |
| `swift test` | Passed 87 tests, zero failures: 21 XCTest, 55 UsageCore Swift Testing, 11 native/formatting tests; final test build 3.12 seconds. |
| `swift build -c release` | Passed, initially 17.88 seconds and final cached check 0.30 seconds. Existing Keychain deprecation warnings retained. |
| `scripts/package_app.sh` | Passed using the existing local identity. |
| `codesign --verify --deep --strict "dist/AI Usage Stats.app"` | Passed on the actual new bundle. |
| `plutil -lint "dist/AI Usage Stats.app/Contents/Info.plist"` | Passed. |
| `git diff --check` | Passed. |
| New disconnection fixture test | Passed: disconnecting one Console connection preserves its manual balance, both profiles, and the other account's connection and automatic balance. No provider requests or real sign-in changes used. |

Packaged checks used `--demo-home --show-home`, the same flags with `--dark-appearance`, `--demo --demo-empty --show-home`, and `--demo --demo-load-error --show-home`, closing the earlier development instance between launches. Native light/dark inspection confirmed the direct actions, inline details, explicit fictional data, and sidebar symbols. Home, account, and Settings captures each measured 2560 × 1616 image pixels with popovers dismissed; the retained AppKit test supplies the separate point/frame evidence. A screenshot parser initially assumed PNG while the native tool returned JPEG, producing unusable dimensions; corrected JPEG decoding supplied the measurements above. No point dimensions are inferred from screenshot pixels.

Expanding the Codex manual editor created vertical overflow; the account scroll area reached its bottom while the window stayed the same size. Tab reached the settings control, and Command-comma focused Launch at login without changing it. Load-failure Retry was keyboard focused; Space restored Home. Plus/minus were correctly disabled for demo accounts and empty demo states.

In the normal app, plus opened the provider-choice sheet with Cancel focused; Escape cancelled it. Selecting the existing account enabled minus and the direct Refresh/Reconnect controls and exposed inline Allow Keychain Access. Minus opened the intended account-removal sheet with Cancel focused; Escape left the account selected and intact. Home and Settings disabled minus. No sign-in, account removal, credit disconnection, Keychain permission action, balance save, billing navigation, or startup preference change was performed through the UI. The native interactions above were observed; live connected-Console button operation, Platform navigation/Back, manual draft preservation, VoiceOver speech, minimum-size layout, accessibility-preference transitions, Intel execution, macOS 14 runtime, and notarization remain unverified for this follow-up.

The new fixture test initially failed compilation because its CreditBalance argument order put `asOf` before `source`; this was corrected without weakening assertions. Earlier failed runs are not passing results. Source/test SHA-256: `eeb517f3c61021f30847e4ebdf97a97f3daebb66f1834d8a957edbdac45eda46`; signed executable SHA-256: `0563658dabcd5531bc666decb6e94f0ee22eb1eeb22fe67d9dde1de91f1c0b3b`. The existing sorted path/NUL/content/NUL digest procedure applies. Documentation and skill context were updated to the final layout; source/package inputs were unchanged after verification.


## Design crit fixes and Liquid Glass linking, October 14, 2026

Tested revision `eac10b6` on branch `crit/fixes-2026-10-14`, with the merge commits `db0a5e7` (menu lane), `b914272` (Home lane), `d8e0e46` (window lane), `e03c6ce` and `1cd23f7` (crit skill fixes), on macOS 27.0.1 (26A434), Apple silicon, macOS 27 SDK, and Swift 6.4. The changes follow the [baseline crit](design/crits/2026-10-14-baseline.md) of revision `8e4f837`; the re-run is [2026-10-14-after](design/crits/2026-10-14-after.md). The status menu, Home, window chrome, vocabulary, and packaging changed in `git diff 8e4f837 -- Sources scripts`.

| Command or inspection | Observed result |
| --- | --- |
| `swift build` | Passed. |
| `swift test` | Passed. XCTest ran with 0 failures. Swift Testing passed 55 tests and 13 tests in its two reported runs. |
| `swift build -c release` | Passed. |
| `scripts/package_app.sh` | Passed. |
| `vtool -show-build` on the packaged executable, before the packaging fix | `minos 14.0`, `sdk 14.0`. SwiftPM records its default SDK, so current macOS kept the pre-Liquid Glass appearance. |
| `vtool -show-build` after the packaging fix | `minos 14.0`, `sdk 27.0`. The script now passes the build SDK to the linker, and the packaged window shows the Liquid Glass sidebar and toolbar. |

The re-run crit captured 17 demo surfaces in light and dark appearance from the packaged app with fictional demo data. Its register has 40 findings: 19 fixed, 7 unverified (changed in source only), and 14 open, with a worst open severity of 3 (calendar events clipped mid-glyph, HOME-12). Contrast values in the report were measured from the captures.

Not verified: keyboard paths (Tab order, Return and Escape on the Home popover, Command-1, Command-2, Command-[, Command-], Command-T, Command-N, arrow and Return on menu reading rows); VoiceOver speech for the sidebar, table, calendar events, and menu rows; surfaces that need pointer input (account page, Settings, add-account sheet, Claude sign-in sheet, Platform pane, empty-state add buttons); sidebar resize and collapse; the minimum 1020 × 640 point window and Month view; the status item glyph; real System Settings Increase Contrast and Reduce Transparency transitions; light system menu appearance. The HIG audit ran on the SDK 14 build before the packaging fix, so its materials and sidebar outcomes predate the Liquid Glass recapture. Earlier limits (live providers, Intel execution, macOS 14 runtime, notarization) remain in effect.


## Design crit round 3 fixes, October 14, 2026

Tested revision `d15aded` on branch `crit/round3-2026-10-14`, on macOS 27.0.1 (26A434), Apple silicon, macOS 27 SDK, and Swift 6.4. Three lanes with disjoint file ownership fixed the open findings of the [round 2 crit](design/crits/2026-10-14-after.md) and were merged in `0e00e8e` (calendar and table), `017d720` (sidebar and window), and `01c8705` (menu and strings), on top of `186908b`, which declares the File menu account commands in `WindowContracts.swift`. The re-run is [2026-10-14-round3](design/crits/2026-10-14-round3.md).

| Command or inspection | Observed result |
| --- | --- |
| `swift test` | Passed. Swift Testing passed 56 tests and 17 tests in its two reported runs; XCTest ran with 0 failures. |
| `swift build -c release` | Passed, with only the existing SecKeychain deprecation warnings. |
| `scripts/package_app.sh` | Passed. |
| `vtool -show-build` on the packaged executable | `minos 14.0`, `sdk 27.0`. |

New focused tests: `calendarEventTextFitsItsFrameAtTheMinimumColumnWidth` and `quotaCellTextFitsAtTheMinimumWindowWidth` (HomeLayoutTests) measure drawn text with `cell.cellSize`, because a tail-truncating field reports an intrinsic width about 4 points short and an intrinsic-size test passed while the app truncated. `sidebarRowsGiveTheIdentityItsOwnLineAndNameTheLimitingWindow` and `addAccountSheetFitsItsContentForEachProvider` (AccountNavigationTests); the sheet test fails against the round 2 sheet code. `lowestCurrentExcludesStaleAndSignInRequiredReadings` (AccountQuotaSummaryTests).

The crit captured 15 demo surfaces in light and dark appearance (30 PNGs with manifests) from the packaged app with fictional demo data. Its register has 51 findings: 29 fixed, 10 unverified, and 12 open, with a worst open severity of 2. Measured: status menu state lines 12.00:1 (2.25:1 before); sidebar state symbols 4.34:1 to 6.29:1 in light appearance (Low was 2.02:1); Home table and calendar Low triangle still 2.33:1 in light appearance (HOME-18).

Sidebar material (HOME-04): Finder, Music, and a minimal `NSSplitViewController` sidebar app linked against SDK 27 show the same flat, full-height sidebar as this app in inactive-window captures on this machine. Toolbar items render as Liquid Glass capsules.

Not verified: every surface that needs pointer input (account page, Settings, add-account and sign-in sheets, remove confirmation, Platform pane, File menu, popover, Month view, minimum window), because the shell has no Accessibility access; the status item glyph, number, and tooltip (MENU-07 is covered by a unit test only); keyboard paths; VoiceOver speech; key-window appearance; real Increase Contrast and Reduce Transparency (the `--increase-contrast` capture was pixel-identical to the light capture); light system menu appearance. Earlier limits (live providers, Intel execution, macOS 14 runtime, notarization) remain in effect.

## Design crit round 3 open findings fixed, October 14, 2026

Tested revision `c0a5078` on branch `claude/elastic-robinson-7919c3`, rebased onto `main` (`be9fcda`), on macOS 27.0.1 (26A434), Apple silicon, macOS 27 SDK, and Swift 6.4. The rebase dropped six crit skill commits that `main` already holds in squashed form (#15); the rebased tree is identical to the tree before the rebase. Four commits fix the 12 open findings of the [round 3 crit](design/crits/2026-10-14-round3.md) in its proposed batch order, and one more fixes a leftover the recapture found.

| Command or inspection | Observed result |
| --- | --- |
| `swift test` | Passed. Swift Testing passed 57 tests and 21 tests in its two reported runs. |
| `swift build -c release` | Passed, with only the existing SecKeychain deprecation warnings. |
| `scripts/package_app.sh` | Passed. `codesign --verify --strict` passed (ad hoc). |
| `vtool -show-build` on the packaged executable | `minos 14.0`, `sdk 27.0`, arm64. |

New or extended focused tests: `stateSymbolColorsReachThreeToOneInLightAppearance` (HOME-18); `quotaCellTextFitsAtTheMinimumWindowWidth` now also lays out the reading-states fixture (HOME-22), and on its first run found the Earned resets line `Stale · last read 14:54` (118 points) truncating in its 108 point column; `outdatedAndMissingReadingsUseOneWording` (ACCOUNT-05, HOME-08); `lowestLastKnownUsesOutdatedReadingsAndSkipsUnmeasuredOnes` (MENU-12); `accountWithoutReadingShowsAStateLineAndOpenAccount` (MENU-13); `sidebarStateSymbolFollowsTheEmphasizedSelection` (HOME-21); the account navigation test now checks the provider prefix for a shared email (HOME-19).

Recaptured with the crit skill's `capture_windows.swift` from the packaged app in demo mode, each fixture as its own instance, filtered by PID (8 surfaces in `.crit/2026-10-14-round3-fixes/captures/`): home (light, dark, `--increase-contrast`), home-states (light, dark), menu, menu-states, and `--demo` Home. Measured in light appearance with the most saturated symbol pixel: the Low triangle is #B66E33 at 3.99 to 4.02:1 on white in both the table and the calendar (2.33:1 before), and Limit reached is #B33B33 at 5.85:1. The sidebar uses the same color. A real AI Usage Stats instance with saved accounts was running from another checkout and was left alone, so the status item strip was not captured.

Not verified: the status item glyph and tooltip for the MENU-12 fallback (unit test only); the account page (ACCOUNT-05 is source and shared-function only); the View > Show Account submenu, which needs pointer or keyboard input (HOME-23, source only); keyboard Tab order from the sidebar Home row (HOME-20 is verified only as the absence of the event focus ring in captures); a key-window capture of a selected Low row (HOME-21, unit test only); the minimum 1020 × 640 point window on screen; VoiceOver speech. Earlier limits (live providers, Intel execution, macOS 14 runtime, notarization) remain in effect.

## 2026-10-14 public release 0.1.0

Product source `9dea07358a1f90b4edd1de4390084a8d9f45ccb7` (tag `v0.1.0`), packaged with the distribution mode from `build/developer-id-release` on macOS 27.0.1 (26A434), Apple silicon, Xcode 27 toolchain, macOS 27 SDK.

| Command or check | Result |
| --- | --- |
| `DISTRIBUTION=1 UNIVERSAL=1 VERSION=0.1.0 BUILD_NUMBER=1 CODE_SIGN_IDENTITY=<Developer ID SHA-1> scripts/package_app.sh` | Signed by Developer ID Application: RAPTURE ENTERTAINERS, INC. (9FL5S77YVH), `flags=0x10000(runtime)`, secure timestamp. |
| `scripts/create_xcode_archive.sh` then `xcodebuild -exportArchive` (developer-id, upload) | Uploaded; export succeeded. |
| `xcodebuild -exportNotarizedApp` | Accepted on the second attempt, about 30 seconds after upload. |
| `codesign --verify --deep --strict`, `xcrun stapler validate`, `spctl --assess --type execute` | Valid; stapled ticket validated; `accepted`, `source=Notarized Developer ID`. |
| `lipo -archs` on `AIUsageStats` and `UsageCapture` | `x86_64 arm64` for both. `vtool` reports minos 14.0, sdk 27.0. |
| `ditto -c -k --keepParent` release archive | `AI-Usage-Stats-0.1.0.zip`, SHA-256 `9228a0470e7882150302201a6fb7e5a329f216890ceff804e95f90105ae5f6a9`; an extracted copy passed Gatekeeper and stapler validation. |
| GitHub release `v0.1.0` asset download | Same SHA-256 as the local archive. |
| `brew style`, `brew audit --cask --online`, `brew livecheck` for `parkerrex/tap/ai-usage-stats` | No offenses; audit exit 0; livecheck reports 0.1.0. |

Not verified: a `brew install --cask` on a clean account, Intel runtime, macOS 14 and 15 runtime, and first-launch Keychain prompts for accounts saved by local development builds.

### 0.1.0 build 2 replaces the first upload

Owner testing found that Show in Menu Bar never showed more than one number per provider. PR #19 fixed it, and the 0.1.0 release was rebuilt before announcement. Product source `91a914d7fad0f99e5b8a78e8737f350be79c109d`; tag `v0.1.0` moved to it.

| Command or check | Result |
| --- | --- |
| `DISTRIBUTION=1 UNIVERSAL=1 VERSION=0.1.0 BUILD_NUMBER=2 …` then Xcode upload and `-exportNotarizedApp` | Accepted on the second attempt; `CFBundleVersion` 2. |
| `codesign --verify --deep --strict`, `xcrun stapler validate`, `spctl --assess` (app and extracted archive) | Valid; stapled; `source=Notarized Developer ID`. |
| Release archive | `AI-Usage-Stats-0.1.0.zip`, SHA-256 `e75e3c5d981231b3bc4555c51c6bc993d901aab6871094b982ef44f42b3fab31`; the GitHub download matches. |
| Cask `parkerrex/tap/ai-usage-stats` | Checksum updated; `brew audit --cask --online` exit 0; `brew fetch --cask` verified the download. |

Build 1 (SHA-256 `9228a047…5f6a9`) is no longer published.

## Quota overview from current readings, October 15, 2026

Phase 1 of the [usage analytics plan](https://github.com/ParkerRex/ai-usage-stats/pull/21): weekly totals, next reset, pace, usable time, account sorting, `No reset pending`, and Refresh Account. Checked on macOS 27.0.1 (26A434), Apple silicon, Swift 6.4, from a packaged ad hoc signed Release build.

| Command or check | Result |
| --- | --- |
| `swift build -j 4 --build-tests`, then `swift test --skip-build` | Both test runs passed: 68 and 22 tests, including six new `QuotaOverviewTests`. |
| `swift build -c release -j 4` | Build complete. |
| `scripts/package_app.sh` | Packaged and signature verified; ad hoc fallback. |
| Usability fix: model limits no longer decide usability; `swift build -j 4 --build-tests`, `swift test --skip-build`, `swift build -c release -j 4` | 68 and 22 tests passed, including a model-scoped window at 100% with general windows below 100% giving `.usable`; release build complete. Not repackaged or recaptured; the demo fixtures have no full model limit. |
| Inactive model windows and rebase onto `465b1ca` (#21, #22): `swift build -j 4 --build-tests`, `swift test --skip-build`, `swift build -c release -j 4` | All test runs passed (2, 2, 69, and 22 tests), including `inactiveModelWindowIsOutsideItsPool`; release build complete. Not repackaged or recaptured. |
| Codex review fixes (next reset with a missing reset time, usable time with an unmeasured general window, passed model resets, outdated `No reset pending`): `swift build -j 4 --build-tests`, `swift test --skip-build`, `swift build -c release -j 4`, `scripts/package_app.sh` | All test runs passed (2, 2, 69, and 22 tests) with new assertions for the first three; release build complete; packaged. `--demo-home --show-menu` still shows `No reset pending` for the current studio reading; `--demo-reading-states --show-home` is unchanged. No fixture has an outdated reading with zero use and no reset time, so the new outdated wording was checked by source only. |
| Adversarial review fixes (per-window freshness for totals, current readings without a weekly window outside the total, unnamed scoped weekly limits, usable time on Home after a passed model reset, account reload errors after Refresh Account, provider name read once by VoiceOver): `swift build -j 4 --build-tests`, `swift test --skip-build`, `swift build -c release -j 4`, `scripts/package_app.sh` | All test runs passed (2, 2, 71, and 22 tests) with two new tests; release build complete; packaged; demo Home and menu captures unchanged. |
| Codex review of 6f511b9 (weekly value kept when a reader marked the reading stale for another window's passed reset; `Usable time unknown` in the menu): same commands | All test runs passed (2, 2, 71, and 22 tests) with new assertions; the calendar still excludes stale readings; release build complete; packaged. No fixture shows `Usable time unknown` in the menu, so that wording was checked by source only. |
| Codex review of 249eed6 (recent stale readings from failed refreshes): `isFresh` again requires `.available`; same commands | All test runs passed (2, 2, 71, and 22 tests) with a failed-refresh assertion for totals and usability; release build complete; packaged. |
| `--demo-home --show-home`, window capture | Weekly Totals above Account Usage: Claude `175% of 200% left`, `Weekly · Fable 5` and `Weekly · Sonnet` rows, `Next reset +25%` with countdown, time, and account; Codex `17% of 200% left`, `Next reset +100%`. Weekly cells show `Under pace` or `Ahead of pace`; the exhausted Codex account shows `Usable in 2d 0h`; a measured-zero 5-hour window with no reset shows `No reset pending`. Earned resets stay in the Home table's Earned resets column and the menu's Earned resets row (Q8, unchanged). |
| `--demo-reading-states --show-home`, window capture | Claude `75% of 100% left, 1 account unknown` (sign-in required left out); `Weekly · Sonnet` `Unknown, 1 account unknown`; Codex `Unknown, 2 accounts unknown` and `Next reset Unknown` with one stale and one unread account. No unknown total shows 0%. |
| `--demo-home --show-menu`, menu capture (system dark appearance) | `Claude • All accounts` and `Codex • All accounts` sections with text rows only, aligned to the account rows; `Usable in 2d 0h · Sat 11:50` in the exhausted account's section; `No reset pending` timing. |

Not verified: keyboard and pointer interaction. `osascript` was refused permission to send keystrokes, so View > Sort Accounts, the Refresh Account toolbar item and File > Refresh Account (Shift-Command-R), arrow-key menu navigation, and VoiceOver reading of the totals grid were checked from source only. Sort order is covered by `soonestUsableOrderKeepsSavedOrderForTies`. Refresh Account was not run against a live account, and the account page with the new toolbar item was not captured, because no flag opens it without input.

## Usage history waves 0 to 2, October 15, 2026

Evidence from the pull request descriptions of [#22](https://github.com/ParkerRex/ai-usage-stats/pull/22) to [#31](https://github.com/ParkerRex/ai-usage-stats/pull/31), the waves 0 to 2 of the [usage analytics plan](USAGE-ANALYTICS-PLAN.md). Numbers are copied as each PR reported them; no check was repeated for this record. Real logs were read on the development Mac by temporary harnesses that printed aggregate counts only and were deleted before commit. No log content was printed or committed.

| PR | Tested revision and system | Tests and builds |
| --- | --- | --- |
| #22 Foundation: record types, `HistoryDatabase`, GRDB 7.11.1 and `facebook/zstd` 1.5.7 | 55812fb, macOS 27.0, Xcode 27.0, Swift 6.4, Apple silicon | `swift test -j 4`: all pass, 0 failures. `swift build -c release -j 4`: succeeds. Linux build not run locally. |
| #23 Phase 1 quota overview | 574aa27, macOS 27.0.1 (26A434), Apple silicon, Swift 6.4 | 2, 2, 71, and 22 tests passed; Release build and packaging. Details in [Quota overview from current readings](#quota-overview-from-current-readings-october-15-2026). |
| #24 Claude log parser | 9d59d3c, macOS 27.0.1, arm64, Swift 6.4 | 122 Swift Testing tests (27 in `UsageHistoryTests`, 8 of them Claude parser) and 21 XCTest tests passed, 0 failed. Release build complete. |
| #25 Quota forecast | 56ed74e, macOS 27.0.1, Swift 6.4 | Swift Testing 114 passed (19 in `UsageHistoryTests`, 16 of them forecast); XCTest 21, 0 failures. Earlier Linux run at 5d8720f: 17 tests passed. |
| #26 Command classifier | 9ad6996, macOS 27.0.1, arm64, Swift 6.4 | Swift Testing 125 (30 + 2 + 71 + 22), including `classifiesCommand` with 53 cases; XCTest 21, 0 failures. Release build complete. Baseline at c2a7622 put `case` pattern words in the program sequence; fixed with an allow list of program names. |
| #27 Codex log parser and Zstandard reader | a6eeb80, macOS 27.0.1, arm64, Swift 6.4 | Swift Testing 49 `UsageHistoryTests` (21 Codex parser and reader), 71, 22, 2; XCTest 21; 0 failures. Release build complete. |
| #29 Quota recorder and log ingestion | e09584d, macOS 27.0.1, Apple M1 Max; packaged-app and real-log measurements at ae01db7 | 49 + 5 + 71 + 22 Swift Testing tests passed, then 49 + 6 + 71 + 22 at e09584d. Release build complete. |
| #30 Home forecast | 69a5144, macOS 27.0.1 | `UsageHistoryTests` 49, `UsageHistoryStoreTests` 6, `UsageCoreTests` 71, `AIUsageStatsTests` 27, all pass. Release build complete. |
| #31 Models page | 2809ee0; packaged app last opened on a4bce09 | 152 tests passed (49 + 10 + 71 + 22). Release build passed. |

### Real-log counts

| Check | Result |
| --- | --- |
| Claude parser (#24), 2026-10-15 | 602 files (527 subagent files), 1,022 MB. 32,019 unique responses; 7,385 (23%) without a final usage line, 7,383 of them in subagent files. 974 turns. 28,562 Bash command events (28,033 succeeded, 524 failed, 5 unknown). 25,490 resumed rows compared with whole-file rows, 0 differ. Parse time 4.1 s on one thread. After the final-usage fix (9d59d3c): 32,161 unique responses, 7,387 without final usage. Plan reference from 2026-10-14: 29,422 responses. |
| Codex parser (#27), plain files | 121 files, 71,560 lines, 0 decode errors, 0 reader errors. 9,253 responses, 6,249 command events, 9,322 quota readings. A resumed read equals the full read in 121 of 121 files. |
| Codex parser (#27), compressed files | 259 files, 207,007 lines, 0 decode errors, 0 reader errors. 42,972 responses, 6,888 command events, 2 quota readings. A resumed read equals the full read in 259 of 259 files. Duration for all files: 95 s, debug build. |
| Integration harness (#29) | Claude 32,404 responses, 14,232 grep and 1,811 rg. Codex 251 grep and 2,954 rg. Codex quota readings: 9,324 matched to an account, 0 unmatched. |
| First ingestion in the packaged Release app (#29), fresh `history.sqlite` | 982 files read, 0 failed, in 23.8 s: 84,692 responses, 42,110 commands, 500 Codex quota readings. Peak resident memory 291 MB, sampled every 0.5 s. Database 36.3 MB plus a 2.0 MB write-ahead log. |
| Next refresh (#29) | 3 changed files read, 979 unchanged files skipped, in 0.11 s. |
| Main thread during first ingestion (#29) | `sample` for 3 s, 6 s after launch: the main thread was idle in the run loop in 1,537 of 1,537 samples. `LogIngestor` ran on a worker thread. |

The Codex grep count differs from the plan's reference of 34 grep and 1,936 rg. Plain Codex logs alone give 5 grep and 1,780 rg. 246 of the 251 grep commands are in compressed history, mostly from older models, and 194 of them are `git ... | grep` pipelines, which `CommandClassifier` counts as grep (#29). The plan's reference was counted another way; the difference is in classification rules and scope, not in which commands the parser emits (#27).

### Packaged-app views

- #30: `open -n "dist/AI Usage Stats.app" --args --demo-home --show-home` on macOS 27.0.1. A window screenshot showed both provider forecast blocks with demo data: drain rate, zero time, Last seen rows, solid history with a gap, dashed projection, Now rule, and the range pop-up showing Next 7 days. The Next 1 day range, the no-history line, and the unavailable-history line were rendered off screen and checked from images.
- #31: `--demo --show-home --show-models` opened the Models page with the demo subtitle and date range, and the Models row selected. The full page was also rendered off screen at 760 and 1020 points wide, plus the empty state.

### Not verified

- Keyboard navigation in the running app: Sort Accounts, Refresh Account, and menu arrow keys (#23); the Models page (#31, covered only by a unit test).
- VoiceOver output for the totals grid (#23), the Home forecast (#30), and the Models page (#31).
- Clicking the Home forecast range pop-up in the running app (#30).
- Refresh Account against a live account (#23).
- The menu's `Usable time unknown` row: no fixture shows it, so it was checked by source only (#23).
- The Home forecast with a real history database and live accounts (#30), and the Models page with real logs (#31). Both used demo or synthetic rows.
- A Codex account added while the app runs (#29, unit test only), Intel runtime (#27, #29), and a local Linux build of the foundation (#22).
