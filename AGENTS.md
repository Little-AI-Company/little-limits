# AI Usage Stats

Build a small native macOS menu bar utility for viewing Claude and Codex account usage. Keep the product focused, fast, and understandable without developer knowledge.

## Repository map

- `Package.swift`: Swift 6, macOS 14 minimum, Swift Package Manager, no external dependencies.
- `Sources/AIUsageStats/`: AppKit status item, account panel, settings, and app lifecycle.
- `Sources/UsageCore/`: account identity, provider data, usage windows, credit balances, and refresh state.
- `Sources/UsageCapture/`: quota-only Claude status-line capture and preservation of the existing command.
- `Tests/UsageCoreTests/`: focused behavior tests.
- `Resources/`: app metadata and generated icon.
- `scripts/package_app.sh`: canonical local Release app packaging.
- `docs/STRATEGY.md`, `docs/NATIVE-DESIGN.md`: product scope and native interface criteria.
- `docs/VALIDATION.md`, `docs/RELEASING.md`: observed evidence, limits, and packaging procedure.
- `docs/research/`: source research and provider limitations.

## Working method

- Read the affected code and current repository state before editing. Preserve unrelated work.
- Define the observable result and use the cheapest reliable check that could disprove it. Reuse existing checks before adding tests.
- Use precise types, professional names, explicit ownership, and direct error handling. Avoid speculative abstractions and compatibility layers.
- Preserve Swift 6 concurrency checking. AppKit state belongs on the main actor; file and network work must not block UI updates.
- Follow the AppKit and SwiftPM architecture. Account and settings controls remain native. The experimental Claude Console sign-in uses an isolated browser session; do not add web views for ordinary app controls, SwiftUI, an Xcode project, or external dependencies.
- Use one agent for work that fits one pass. When parallel work is explicitly requested, assign file ownership first and coordinate shared APIs. Never revert another contributor's changes.
- Questions ask for answers, not changes. Follow the user's scope and publishing disposition.

## Data and privacy

- Preserve account identity across refreshes. Never mix credentials or readings between accounts.
- Keep subscription usage percentages and reset times separate from monetary credit balances and credit expiry.
- Distinguish measured zero from unknown, unsupported, expired, and failed data. Show timestamps and stale state where relevant.
- Do not invent a provider endpoint or present a private endpoint as an official supported API. Claude Console integration is experimental. Ground its field meanings in `docs/research/`, preserve unknown values, and keep its session isolated from subscription CLI capture.
- Never display, log, commit, or include credentials in screenshots. Never change the user's Claude or Codex login as a side effect of monitoring.
- Keep monitoring read-only. Do not purchase credits, alter plans, consume model requests as a probe, or add telemetry.

## Native interface

- Use standard AppKit controls, menu behavior, keyboard access, and accessibility labels. Consult current Apple HIG guidance for the affected interaction.
- Keep the interface information-dense. No decorative cards or pills, gray subtitle lines above sections, em dashes, or continuous animations.
- Preserve stable account order and identity during refresh. Redraw only when displayed state changes.
- Validate changed UI in the running `.app`. Compilation does not prove layout, focus, accessibility, or menu-bar behavior.

## Build and run

```sh
swift build
swift test
scripts/package_app.sh
open -n "dist/AI Usage Stats.app"
```

These are available commands, not a requirement to run all four for every edit. Packaging builds in Release mode using the selected local signing identity, with ad hoc signing as the fallback. Launch through the packaged `.app`; a raw `swift run AIUsageStats` does not establish bundle behavior. Quit the previous development instance before comparing builds.

## Verification

| Change | Required evidence |
| --- | --- |
| Documentation only | Review changed lines and check referenced commands and links. Run `git diff --check` when Git is available. |
| Swift code | Run `swift test` and `swift build -c release`. Retain tests for meaningful contracts and plausible failures. |
| Native UI or lifecycle | Also package and open the app. Exercise the changed control, keyboard access, and empty or failure state. Record actual visual checks and macOS version. |
| Provider parsing or refresh | Also verify representative responses, missing fields, account separation, stale data, and authentication failures. Use redacted fixtures and authorized read-only requests. |
| Credentials | Verify isolation and storage behavior. Never weaken security or print credentials to diagnose a test. |
| Experimental Console credits | Verify account and organization binding, separate purchased and promotional amounts, currency minor units, expiry, unknown scope, stale data, and failed sign-in. Never rename every promotional grant as the monthly subscription grant. |
| Packaging | Inspect the actual bundle, metadata, executable architecture, icon, and signature. See `docs/RELEASING.md`. |
| Performance | Compare baseline and changed Release builds under the same conditions. Record hardware, OS, duration, refresh state, measurements, and limits. |

Classify failures before changing code: compiler, assertion, crash, timing, environment, provider, or signing. Use a narrow rerun and scoped diagnostics. Do not weaken assertions or hide errors to make checks pass. Repeat affected checks after a rebase or cherry-pick; avoid repeated full runs without new evidence.

Report exact commands, results, tested revision, skipped checks, and material limits. A build, launch, visual check, and trusted distribution are separate claims. Universal compilation does not establish Intel runtime or minimum-macOS coverage. Put durable evidence in `docs/VALIDATION.md`.

## Contributions and releases

Follow [CONTRIBUTING.md](CONTRIBUTING.md) and the [PR template](.github/pull_request_template.md). Keep each PR focused, read every changed line, and tie proof to the submitted revision. Use a short conventional title, such as `fix: preserve account identity during refresh`.

Rebase onto current `main` before opening a ready-for-review PR. Include observed baseline reproduction for bug fixes, exact verification results, and an accurate model and harness disclosure. Merge only with authorization.

Reuse `scripts/package_app.sh`. Local ad hoc signing does not provide Developer ID trust or notarization. Do not publish a release, add recurring workflows, enable an updater, or change distribution configuration merely because checks passed.
