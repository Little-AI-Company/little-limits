# Little Limits

Build a small native macOS menu bar utility for viewing Claude and Codex account usage. Keep the product focused, fast, and understandable without developer knowledge.

## Rules for every agent

These rules apply to every agent and every person here. Parker set them on 2026-10-31 for the move to trunk-based development. When one of them conflicts with an older sentence anywhere in this repository, this section wins.

### Code

- Build what the task needs now, not what it might need later.
- When you delete code, leave no trace of it: no shim, re-export, `_unused` rename, "removed" note, or test that it stays deleted.
- Leave style to the formatter and linter. Do not reflow, reorder or rename lines the change does not need.
- To learn how a dependency behaves, read its source (`.build/checkouts/` after `swift package resolve`, or a clone under `/tmp`), not only its docs.
- Scratch files go in `/tmp` or `.build/`, never beside the code.
- Never edit a policy, baseline, threshold or allowance to silence a failing check.

### Tests

- Never write a new unit test or integration test unless the person explicitly asked for that test. You may write a new end-to-end or system-level test: the packaged `.app` opened and the changed control exercised, as the [Verification](#verification) table says.
- Integration tests stay only where they were asked for: the `UsageHistory` parsers against redacted real logs, `UsageCore` account separation, and `UsageHistoryStore` database compatibility.
- When a change breaks an existing test, fix it, or delete it when an end-to-end check or the compiler already covers what it checked. Delete a test that no longer protects anything.
- A test checks behaviour through the code's real interface. It never reads source, docs or config text to look for words, and never asserts wiring, call order or that the code mirrors the implementation.
- A test never waits on a timer or a sleep. It waits on the event, a completion signal or a test clock. A flaky test is fixed or deleted, never retried or given a longer timeout.
- Doubles only at a process, network, clock, filesystem or keychain boundary. A fake fails on a call the test did not configure.
- Pass `now`, the calendar, the locale, and the time zone as inputs. CI runs in UTC with a 12-hour US clock; a test that depends on the Mac's settings passes locally and fails there.
- CI does not open the app. For layout, focus, and menu-bar behavior, the packaged app is the check.

### Comments

- Never add a new code comment. Put the why in a name, a type, a test, the commit message, or `docs/adr/` for a decision. Existing comments are being removed; never add one back to a file you touch.
- A directive a tool reads is not a comment and stays: the shebang, `# shellcheck disable`, `// MARK:`, and `// swift-tools-version`.
- Doc comments (Swift `///`, shell file headers) are comments too. A script that prints its own header as `--help` gets a `usage()` heredoc instead.

### Shared company rules

- A plan, crit, review, research or decision is a page on the HQ wiki (`Little-AI-Company/little-worker-hq`: `wiki/`, `explorations/`, or the MCP server at `https://hq.thelittleworker.com/mcp`), never a Claude Doc or artifact as the record. A follow-up found during work becomes a roadmap item there the same day.
- Plain words. No em dashes. No jargon without saying what it is. One thing has one name everywhere.
- Never on your own: send, publish, post, spend, change a price, release to users or contact anyone. Agents propose; Parker acts. Never print or commit a key, token or credential.
- Heavy work (an app build, `swift test`, packaging) runs on the M4, never by hand on Parker's M1. From a cloud session, reach the M4 with little-worker's `scripts/m4-ssh-setup.sh`, then `ssh m4`.

## Repository map

- `Package.swift`: Swift 6, macOS 14 minimum, Swift Package Manager. Dependencies: GRDB (macOS only) and facebook/zstd, pinned exactly.
- `Sources/AIUsageStats/`: AppKit status item, account panel, settings, and app lifecycle.
- `Sources/UsageCore/`: account identity, provider data, usage windows, credit balances, and refresh state.
- `Sources/UsageCapture/`: quota-only Claude status-line capture and preservation of the existing command.
- `Sources/UsageHistory/`: usage history record types, log parsers, command classifier, and forecast. Foundation and zstd only; builds on Linux.
- `Sources/UsageHistoryStore/`: GRDB usage history database. macOS only.
- `Tests/`: focused behavior tests, one target per source target.
- `scripts/push_main.sh`: the only way a change lands on `main`. See [Shipping on main](#shipping-on-main) and [docs/push-main.md](docs/push-main.md).
- `.github/workflows/ci.yml`: after each push to `main`, GitHub's runners package, verify the signature, and run the full tests on macOS, and run the `UsageHistory` tests on Linux. Nobody waits for it.
- `Resources/`: app metadata and generated icon.
- `scripts/package_app.sh`: canonical local Release app packaging.
- `docs/STRATEGY.md`, `docs/NATIVE-DESIGN.md`: product scope and native interface criteria.
- `docs/VALIDATION.md`, `docs/RELEASING.md`: observed evidence, limits, and packaging procedure.
- `CHANGELOG.md`, `website/changelog/`: what changed in each public release. Write them with the [changelog skill](.agents/skills/changelog/SKILL.md).
- `docs/research/`: source research and provider limitations.
- `docs/USAGE-ANALYTICS-PLAN.md`: usage history features, settled decisions, and the work split.
- `docs/VERIFICATION-AND-DELIVERY-PLAN.md`: the test, data, and revert rules and where they came from. Its pull request flow ended on 2026-10-30.

## Working method

- Read the affected code and current repository state before editing. Preserve unrelated work.
- Define the observable result and use the cheapest reliable check that could disprove it. Reuse existing checks before adding tests.
- Use precise types, professional names, explicit ownership, and direct error handling. Avoid speculative abstractions and compatibility layers.
- Preserve Swift 6 concurrency checking. AppKit state belongs on the main actor; file and network work must not block UI updates.
- Follow the AppKit and SwiftPM architecture. Account and settings controls remain native. The experimental Claude Console sign-in uses an isolated browser session; do not add web views for ordinary app controls, an Xcode project, or dependencies beyond GRDB and zstd. New analytics pages may use SwiftUI and Swift Charts inside the AppKit window; account and settings controls stay AppKit.
- Use one agent for work that fits one pass. When parallel work is explicitly requested, assign file ownership first and coordinate shared APIs. Never revert another contributor's changes.
- Questions ask for answers, not changes. Follow the user's scope and publishing disposition.

## Data and privacy

- Preserve account identity across refreshes. Never mix credentials or readings between accounts.
- Keep subscription usage percentages and reset times separate from monetary credit balances and credit expiry.
- Distinguish measured zero from unknown, unsupported, expired, and failed data. Show timestamps and stale state where relevant.
- Do not invent a provider endpoint or present a private endpoint as an official supported API. Claude Console integration is experimental. Ground its field meanings in `docs/research/`, preserve unknown values, and keep its session isolated from subscription CLI capture.
- Never display, log, commit, or include credentials in screenshots. Never change the user's Claude or Codex login as a side effect of monitoring.
- Keep monitoring read-only. Do not purchase credits, alter plans, consume model requests as a probe, or add telemetry.
- Usage history reads local Claude Code and Codex logs and stores derived facts only. Never store or log prompts, replies, tool output, file contents, or command text. Logs never leave the Mac.
- `ProjectKey` is a salted 64-bit FNV-1a hash of the full working-directory path. It groups records by project without storing folder names, and keeps apart folders whose last component is the same. It does not protect against someone who holds both the database and its salt and guesses paths.

## Native interface

- Use standard AppKit controls, menu behavior, keyboard access, and accessibility labels. Consult current Apple HIG guidance for the affected interaction.
- For interface design and accessibility reviews, use the repository's [Apple HIG skill](.agents/skills/apple-hig-expert/SKILL.md), adapted for this app's native macOS surfaces and data contracts.
- Keep the interface information-dense. No decorative cards or pills, gray subtitle lines above sections, em dashes, or continuous animations.
- Preserve stable account order and identity during refresh. Redraw only when displayed state changes.
- Validate changed UI in the running `.app`. Compilation does not prove layout, focus, accessibility, or menu-bar behavior.

## Build and run

```sh
swift build
swift test
scripts/package_app.sh
open -n "dist/Little Limits.app"
```

These are available commands, not a requirement to run all four for every edit. Packaging builds in Release mode using the selected local signing identity, with ad hoc signing as the fallback. Launch through the packaged `.app`; a raw `swift run AIUsageStats` does not establish bundle behavior. Quit the previous development instance before comparing builds.

## Verification

| Change | Required evidence |
| --- | --- |
| Documentation only | Review changed lines and check referenced commands and links. Run `git diff --check` when Git is available. |
| Swift code | Run focused tests for the touched target while you work, such as `swift test --filter UsageCoreTests`. `scripts/push_main.sh` runs the full `swift test` on the exact commit before it pushes. GitHub Actions runs the Release build and packaging after the push. |
| Native UI or lifecycle | Also package and open the app. Exercise the changed control, keyboard access, and empty or failure state. Record actual visual checks and macOS version. |
| Provider parsing or refresh | Also verify representative responses, missing fields, account separation, stale data, and authentication failures. Use redacted fixtures and authorized read-only requests. |
| Credentials | Verify isolation and storage behavior. Never weaken security or print credentials to diagnose a test. |
| Experimental Console credits | Verify account and organization binding, separate purchased and promotional amounts, currency minor units, expiry, unknown scope, stale data, and failed sign-in. Never rename every promotional grant as the monthly subscription grant. |
| Packaging | Inspect the actual bundle, metadata, executable architecture, icon, and signature. See `docs/RELEASING.md`. |
| Performance | Compare baseline and changed Release builds under the same conditions. Record hardware, OS, duration, refresh state, measurements, and limits. |

Classify failures before changing code: compiler, assertion, crash, timing, environment, provider, or signing. Use a narrow rerun and scoped diagnostics. Do not weaken assertions or hide errors to make checks pass. Repeat affected checks after a rebase or cherry-pick; avoid repeated full runs without new evidence.

Report exact commands, results, tested revision, skipped checks, and material limits. A build, launch, visual check, and trusted distribution are separate claims. Universal compilation does not establish Intel runtime or minimum-macOS coverage. Put durable evidence in `docs/VALIDATION.md`.

### Data compatibility

Any commit on `main` must be revertible without touching user data.

- `accounts.json`: add a field as optional and decode it with `decodeIfPresent`. Never rename or remove a stored key.
- A new case in a stored enum (`Provider`, `AccountSource`, `SnapshotState`, `CreditUnit`, `CreditSource`) makes an older build unable to read `accounts.json`. Ship the reader in a release before any build writes the case.
- History database: add columns as nullable or with a default, and never change the meaning of an existing column. An older build opens a newer database and still writes to it. The database is derived from local logs, so a migration may clear it to force a reread.
- Raise `CommandClassifier.version` whenever a classification rule changes. Stored command rows keep the version that produced them, and a row whose source log is gone is never reclassified.
- Preferences keep their stored values; never rename a stored raw value. The stored icon choice (`AppIconChoice`) keeps the raw value `enamel` for Paper, the bundle icon's name before the Little Limits artwork, and a missing or unknown value reads as Paper. `MenuBarAccountIDs` lists the accounts with their own menu bar number. The first version stored hidden accounts under `MenuBarHiddenAccountIDs` instead; the app converts that key once against the loaded accounts, so accounts added later are not chosen, and then removes it.

## Shipping on main

Everyone, human or agent, commits straight to `main`. There are no pull requests, branches, stacks, batch landings, release freezes or CI gates (Parker, 2026-10-31). Two people and their agents work here and the product has few users, so a bad commit costs one revert and a gate costs every commit its wait. We revert instead of adding gates.

- One commit, one purpose, landed in the same session that wrote it. Split big work into commits that each stand alone: the stored field first, then the readers, then the writers, then the setting, then the cleanup. A thread never holds more than a few hours of unpushed work.
- Every commit leaves `main` releasable: no half-wired screen, no stored field without its reader. Unfinished work that must land ships inert, behind a default-off setting; `accounts.json` and the history database stay revertible (see [Data compatibility](#data-compatibility)).
- Commit on a detached `origin/main` or a worktree of it. Never push a branch. A branch the harness creates for a session stays local.
- Use `type(scope): summary` subjects (`feat`, `fix`, `perf`, `docs`, `chore`, `refactor`, `test`); the body says what changed and why. A `feat`, `fix`, or `perf` commit ends with a trailer `Customer-note: <one or two plain sentences>` that says what a person using the app can do now, or `Customer-note: none (<reason>)`. The scopes `release`, `website`, `ci`, `test`, and `repo` need none. The [changelog skill](.agents/skills/changelog/SKILL.md) writes each release from these notes.
- Read every line of the diff before you push. Passing checks do not replace reading it.
- Push only with `scripts/push_main.sh`. It rebases onto `origin/main`, runs `git diff --check` and, when the commit touches Swift, resources, scripts, or the package, the full `swift test` on that exact commit: on this Mac, or on the M4 over `ssh m4` from a cloud session. `--package` adds packaging for UI, lifecycle, resource, or packaging changes; `--verify` checks HEAD and pushes nothing. It writes a `Tested:` trailer naming the tree that passed, and pushes, retrying when `main` moved. `--no-swift "<why>"` is always allowed and always recorded. Never write a `Tested:` line by hand, never push `main` another way, never force-push, amend or rewrite a pushed commit. See [docs/push-main.md](docs/push-main.md).
- After the push nobody waits. GitHub Actions (`ci.yml`) builds, packages and tests the commit on macOS 27 until the M4 runs macOS 27. A red `main` is fixed forward or reverted within the hour by whoever pushed it, and by whoever sees it when the author is gone after 30 minutes: `scripts/push_main.sh --revert <sha> --reason "<why>"`. Nobody asks first. A rerun that passes with no code change is a flaky test to fix, not a pass.
- Native UI still needs the packaged app checked by hand before the push, as the Verification table says. Put evidence in the commit body and `docs/VALIDATION.md`, not in a separate review.
- Only Parker changes the `main` ruleset (no deletion, no force-push, linear history, no required status) and repository settings.
- Outside contributors cannot push. A pull request from a fork is read as a proposal, landed as one commit with the push script and a `Co-authored-by:` trailer, then closed with a link to the commit.

Releases follow [docs/RELEASING.md](docs/RELEASING.md). Follow [CONTRIBUTING.md](CONTRIBUTING.md) for evidence and disclosure.

Reuse `scripts/package_app.sh`. Local ad hoc signing does not provide Developer ID trust or notarization. Do not publish a release, add recurring workflows, enable an updater, or change distribution configuration merely because checks passed.
