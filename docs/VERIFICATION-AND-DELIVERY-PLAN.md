# Verification and delivery plan

Date: 2026-10-20. Status: implemented, except PR 2, which waits for evidence.

Superseded on 2026-10-30 for how changes land: there are no pull requests, branches, or required `Check` status any more. Commits go straight to `main` through `scripts/push_main.sh` ([docs/push-main.md](push-main.md)), and `ci.yml` runs only after a push. The test, data, and revert rules below still hold. The ruleset proposed under Settings change was never applied. The `main` ruleset that replaces it only blocks deletion and force pushes and requires linear history.

- PR 1 landed as ParkerRex/little-limits#73. Its first run found a real bug: reset times truncated on a 12-hour clock. Fixed in ParkerRex/little-limits#74.
- PR 3 is the PR that adds this file. The rules live in AGENTS.md (Verification, Tests, Data compatibility), CONTRIBUTING.md (Revert), and docs/RELEASING.md.
- The settings change (squash merge only, and a `main` ruleset that requires `Check`) is not applied yet. It needs the repository owner.
- Known flake: on 2026-10-20, 1 of 4 Linux runs crashed inside SwiftPM 6.4's `swift-build` engine while planning the zstd C sources (segmentation fault in `discoveredClangToolInfo`), before any test ran. A rerun passed. If it repeats, run the Linux job with `swift test --build-system native`.
Source practice: the T3 Code testing and delivery profile in `maintainer-profiles`
(`projects/t3code-testing-and-delivery.md`, revision `ca21599`).

Goal: merge a PR quickly and revert it quickly. Checks must prove something real
and must not change result on their own.

## What we take from T3 Code

1. CI runs on every PR and on every push to `main`. A new push cancels the old PR run. Runs on `main` are never cancelled.
2. One aggregate check named `Check` is the only required status. Adding a job later needs no settings change.
3. Squash merge only, linear `main`, one concern per PR, conventional title. Then any change is one `git revert`.
4. A revert is an ordinary PR with a fixed body: original PR and SHA, reason, condition for relanding. A reland is a new PR.
5. Stored data moves forward only, and readers tolerate newer data. Then reverting code never needs reverting data.
6. Agents run focused tests locally. CI owns the full suite.
7. Green CI does not prove behavior CI cannot exercise. T3 reverted fourteen desktop fixes that passed CI but were never run in a real build (pingdotgg/t3code#22222). For us that is the packaged `.app`.
8. Test rules: test a contract or a real failure. Doubles only at process, network, clock, filesystem, and Keychain boundaries. Fakes fail on calls the test did not configure. No snapshots, no coverage target. Delete tests that protect nothing.

Not taken: path-based job skipping, sharding, merge queue, nightly channel, preview deploys, size and trust labels, coverage. They solve problems of a large monorepo with many contributors.

## Current state

Measured on `c2faff6`, macOS 27.0, Xcode 27.1, Swift 6.4, Apple silicon.

| Item | Observed |
| --- | --- |
| CI | None. `.github/` holds only the PR template. |
| Branch protection | None. `gh api .../branches/main/protection` returns 404. No rulesets. |
| Merge methods | Merge, squash, and rebase all allowed. Branches are not deleted on merge. |
| History | Linear. 70 of 73 first-parent commits end in `(#N)`. The 3 direct pushes are from 2026-10-09 to 2026-10-14. No reverts yet. |
| Tests | 195 tests (21 XCTest, 174 Swift Testing). All pass. |
| Test time | Cold `swift test` with build: 66 s. Warm: 7 s. One warm run took 53 s at 10% CPU; it did not repeat. |
| Hermetic | `git status` is clean after `swift test`. Tests write only to temporary directories. |
| Local rule | AGENTS.md asks every Swift change to run the full `swift test` and `swift build -c release`. |

Data compatibility today, read from source:

- `accounts.json` (`Sources/UsageCore/Storage.swift:75`): top-level keys use `decodeIfPresent`, and `JSONDecoder` ignores unknown keys. An older build reads a newer file. If decoding fails, `load()` throws and nothing is saved over the file (`UsageService.swift:171`), so no data is lost.
- One revert hazard: the stored enums `Provider`, `AccountSource`, `SnapshotState`, `CreditUnit`, and `CreditSource` (`Models.swift`) are plain `String` raw values. If a PR writes a new case and is then reverted, the older build cannot decode `accounts.json` and shows no accounts until the user upgrades again.
- History database (`HistoryDatabase.swift`): GRDB migrations, forward only. GRDB lets an older build open a database with migrations it does not know. Its inserts still have to succeed, so new columns must be nullable or have a default. The database is derived from local logs, so a reset migration (as in `v3-reread-logs-for-command-attribution`) is acceptable.

Test risks found, not yet observed failing:

- Date and timezone dependence. `calendarEventTextFitsItsFrameAtTheMinimumColumnWidth` (`HomeLayoutTests.swift:174`) uses `Date()`, `Calendar.current`, and `DemoFixtures`, which call `Date()` again internally (`DemoFixtures.swift:16`). Month mode depends on the day of the month the test runs. CI runs in UTC; local runs do not.
- Wall-clock timing. `CodexClientTests.swift:69-87` assert a real child process ends in under 3 s. `CodexClientTests.swift:207` waits `Task.sleep(100 ms)` before removing an account. Shared macOS runners are slower than a local Mac, so these are the most likely flakes.

## Proposed changes

Three PRs and one settings change. Each PR has one purpose and reverts alone.

### PR 1. `ci: build, test, and package on every pull request`

Add `.github/workflows/ci.yml`:

- Triggers: `pull_request`, and `push` to `main`. `permissions: contents: read`.
- Concurrency: `group: ci-${{ github.event.pull_request.number || github.sha }}`, `cancel-in-progress: ${{ github.event_name == 'pull_request' }}`.
- Job `macos` on the `xcode-27` runner image, timeout 30 min, Xcode 27.1 selected by exact path so the toolchain does not change under us. The standard `macos-26` image has only Xcode 26, which cannot build `UsageMenu.swift:73` (a macOS 27 SDK symbol). No `.build` cache: a stale cache is one more way for a check to change on its own. Add one only if run time becomes a problem. Steps:
  1. `scripts/package_app.sh` (Release build, bundle, ad hoc signature; there is no signing identity on the runner).
  2. `codesign --verify --strict "dist/Little Limits.app"`.
  3. `swift test`.
  4. `git diff --exit-code`. Fails if a test or the packaging step changed a tracked file.
- Job `linux`, timeout 10 min, official Swift container at a pinned version: `swift test`. On Linux only `UsageHistory` builds (`Package.swift:3`). This keeps cloud sessions working; nothing protects that today.
- Job `Check`, `if: always()`, `needs: [macos, linux]`. Fails unless both succeeded. A skipped or cancelled job reports success to branch protection, so this job has to check the results itself.

No path filters. Most PRs touch Swift, and a skip rule is one more thing that can be wrong. The repository is public, so macOS runner minutes are free.

Local verification, 2026-10-20, Xcode 27.1 (27A9275, the same build as the runner's `Xcode_27.1.app`):

- macOS steps in a fresh clone: packaging 4 min 35 s with dependency fetch, signature valid, `swift test` 66 s with 195 tests passing, `git diff --exit-code` clean. The app icon was not regenerated.
- Linux: `swift:6.4.0-noble` container, `swift test` 1 min 24 s, 50 tests passing. Run on arm64; the GitHub runner is x86_64.
- `Check` logic: exits 0 only when both results are `success`; `skipped`, `failure`, and `cancelled` each exit 1.

Still unverified until the first GitHub run: the x86_64 Linux build and the `xcode-27` preview image itself.

### PR 2. `test: fix the date and time used by tests`

- `DemoFixtures` takes `now` as a parameter instead of calling `Date()`.
- Tests that use a calendar pass a fixed date, a fixed `TimeZone`, and a fixed `Calendar`, not `Date()` and `Calendar.current`.
- Leave the Codex process timing tests as they are for now. They test timeout behavior, which needs real time. If one flakes on CI, replace the `Task.sleep` with an explicit signal that the wait has started.

Observable outcome: the same tests pass with `TZ=UTC` and `TZ=Pacific/Kiritimati`, on any date. Check: run `swift test` under both timezones before and after.

Only do this PR if PR 1's first runs or the two-timezone check show a failure. Otherwise move the rule into PR 3 and fix the code when it breaks.

### PR 3. `docs: write the test, CI, data, and revert rules`

AGENTS.md:

- Verification table. Swift code: run focused tests for the touched target (`swift test --filter <Target>Tests`). CI runs the full suite, the Release build, and packaging. Native UI: still package and open the app locally, because CI cannot exercise layout, focus, or menu-bar behavior.
- Test rules from item 8 above, plus: pass `now`, calendar, and timezone as inputs; wait on a completion signal, never a sleep.
- Data rules: add `accounts.json` fields as optional with `decodeIfPresent`; never rename or remove a stored key; a new case in a stored enum ships reader support in an earlier release than the writer. Add history database columns as nullable or defaulted; never change the meaning of an existing column.

CONTRIBUTING.md, a short "Revert" section:

- Revert first when `main` is wrong; discuss after.
- Use GitHub's Revert button or `git revert <sha>` on a new branch. Title `revert: <original title> (#N)`.
- Body: original PR and SHA, what broke, and the condition for relanding. Reland as a new PR.
- A bug already in a release: revert on `main`, then cut a patch release. There is no updater, so users get the fix through the cask.

docs/RELEASING.md: release only a `main` commit whose `Check` passed.

The PR template already asks for exact commands, observed results, UI checks, and the model disclosure. No change.

### Settings change (Parker must authorize; apply after PR 1 merges so `Check` exists)

- Repository: squash merge only, squash commit title from the PR title, delete branches on merge.
- Ruleset on `main`: require a PR with zero approvals, require status check `Check` only, do not require the branch to be up to date, require linear history, block force pushes and deletion. No bypass: release preparation already goes through PRs (ParkerRex/little-limits#70).

## Order

PR 1, then the settings change, then PR 3. PR 2 only if evidence calls for it.
