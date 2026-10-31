# Contributing

Small, well-explained contributions are welcome. You are responsible for every submitted line, including work produced with AI tools. Read the diff, verify the behavior, and remove anything the change does not need.

## Choose one change

Check current `main` and existing issues before starting. Keep one purpose per commit and exclude unrelated dependency updates, formatting, and refactors. Stay within the [product scope](docs/STRATEGY.md). Discuss substantial features or architecture changes first; small fixes do not need prior permission.

Read [AGENTS.md](AGENTS.md) for the module map, data boundaries, native workflow, and required checks. Those rules apply to human and AI-assisted contributions.

These are not planned:

- Telemetry, an updater framework, or recurring GitHub Actions.
- Dependencies beyond GRDB and facebook/zstd.
- Web views for account, settings, or monitoring controls.
- Purchasing credits, changing plans, or spending model requests to probe usage.
- Storing or logging prompts, replies, tool output, file contents, or command text.
- Changing or replacing the user's Claude or Codex CLI login.
- Inferring remaining credit dollars from token totals, API costs, or usage percentages.

## Establish and verify behavior

For a bug fix, reproduce the problem on a named baseline commit before editing. Record repeatable steps, expected behavior, observed result, and the source location of the cause. Only claim a baseline failure when you observed it. State the gap when you lack that evidence.

Define an observable result and choose the cheapest reliable check that could detect a failure. Reuse existing tests. Do not add unit or integration tests unless a maintainer asks for one; an end-to-end check of the packaged app is the way to add coverage. Do not add code comments. Do not mirror implementation or create extra production layers to support tests.

Follow the [build instructions](README.md#build-from-source) and [verification requirements](AGENTS.md#verification). Preserve type safety and Swift concurrency checking. Update relevant docs in the same commit. For native UI, exercise the packaged app and record the actual views and interactions checked. Review screenshots for private account information before sharing.

For provider work, identify the source and whether an endpoint is official or private. Use redacted fixtures. Preserve account isolation, missing-data states, and authentication failures. Never change a user's active CLI login to test monitoring.

Performance claims require measured baseline and changed Release builds under comparable conditions. Include commits, hardware, OS, workload, duration, results, tradeoffs, and limits. Estimates are not measurements.

## Land the change

Maintainers and their agents commit straight to `main`; there are no branches or pull requests ([AGENTS.md: Shipping on main](AGENTS.md#shipping-on-main)).

1. Commit on a detached `origin/main`. One purpose per commit, with a short conventional subject naming the behavior change, such as `fix: preserve account identity during refresh`, `feat: show credit expiry`, or `docs: clarify local builds`.
2. Write the body for a reader who has not seen the work: the concrete problem and resulting behavior, then the cause and fix. For a bug fix, name the baseline commit and the reproduction. List manual checks you ran and their results, such as the packaged app views and interactions. End with an accurate AI model and harness disclosure, or state that no AI tools were used. Do not guess model details or publish private maintainer research.
3. A `feat`, `fix`, or `perf` commit ends with a `Customer-note:` trailer for the changelog, or `Customer-note: none (<reason>)`.
4. Read every line of `git show HEAD`. Passing checks do not replace review.
5. Run `scripts/push_main.sh` (`--package` for UI, lifecycle, resource, or packaging changes). It rebases, runs the checks on the exact commit, records them as `Tested:` trailers, and pushes `main`. See [docs/push-main.md](docs/push-main.md).

Never include tokens, Keychain items, OAuth grants, `accounts.json`, the usage history database, raw Claude Code or Codex logs, or screenshots that show account emails, organization names, or balances.

### From a fork

Without push access, open a pull request from your fork with the same content: the problem, the fix, the checks you ran, and the disclosure. A maintainer reads it, lands it on `main` with the push script, credits you with a `Co-authored-by:` trailer, and closes the pull request with a link to the commit.

## Revert

When `main` is wrong, revert first and discuss after.

- Run `scripts/push_main.sh --revert <sha> --reason "<what broke>"`. It reverts the commit on `origin/main`, checks the result, and pushes it.
- The body names the original commit, what broke, and what must be true to reland. Reland as a new commit.
- A bug already in a release: revert on `main`, then cut a patch release. There is no updater; users get it through the cask.

Every commit on `main` is one change that its `Tested:` trailers describe, so any change reverts as one commit. [Data compatibility](AGENTS.md#data-compatibility) keeps that safe for stored data.

## Follow through

Whoever pushed a commit watches its GitHub Actions run on `main`. A red run is fixed or reverted within the hour. Verify review findings against the source; fix real findings in a follow-up commit and explain false positives with specific evidence.
