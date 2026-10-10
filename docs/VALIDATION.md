# Validation

This file records observed results, not intended behavior. Update the tested revision and relevant checks when the implementation changes.

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

The final packaged executable SHA-256 is `ad67e601c73e6dfe89e51bea4a20bbb4b6b465c1ccdfdaed6cf3dd9fd0c7314b`. Multiple live account binding, real Console billing, live renewal, VoiceOver, minimum-macOS runtime, Intel runtime, Developer ID signing, and notarization remain unverified.
