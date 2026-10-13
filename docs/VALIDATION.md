# Validation

This file records observed results, not intended behavior. Update the tested revision and relevant checks when the implementation changes.

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
