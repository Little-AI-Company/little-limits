# Contributing

Small, well-explained contributions are welcome. You are responsible for every submitted line, including work produced with AI tools. Read the diff, verify the behavior, and remove anything the change does not need.

## Choose one change

Check current `main`, existing issues, and open PRs before starting. Keep one purpose per PR and exclude unrelated dependency updates, formatting, and refactors. Stay within the [product scope](docs/STRATEGY.md). Discuss substantial features or architecture changes first; small fixes do not need prior permission.

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

For a bug fix, reproduce the problem on a named baseline commit before editing. Record repeatable steps, expected behavior, observed result, and the source location of the cause. Only claim a baseline failure when you observed it. State the gap when updating an existing PR without that evidence.

Define an observable result and choose the cheapest reliable check that could detect a failure. Reuse existing tests. Add a test when it protects a meaningful contract, catches a plausible regression, or exercises a consequential failure. Do not mirror implementation or create extra production layers to support tests.

Follow the [build instructions](README.md#build-from-source) and [verification requirements](AGENTS.md#verification). Preserve type safety and Swift concurrency checking. Update relevant docs in the same PR. For native UI, exercise the packaged app and record the actual views and interactions checked. Review screenshots for private account information before sharing.

For provider work, identify the source and whether an endpoint is official or private. Use redacted fixtures. Preserve account isolation, missing-data states, and authentication failures. Never change a user's active CLI login to test monitoring.

Performance claims require measured baseline and changed Release builds under comparable conditions. Include commits, hardware, OS, workload, duration, results, tradeoffs, and limits. Estimates are not measurements.

## Prepare the pull request

1. Fetch upstream and rebase your contribution branch onto latest `main`.
2. Repeat affected checks after a rebase or cherry-pick. Record baseline and tested head revisions.
3. Read every line of the diff and description. Passing checks do not replace review.
4. Open a ready-for-review PR, not a draft, using the [template](.github/pull_request_template.md).

Never include tokens, Keychain items, OAuth grants, `accounts.json`, the usage history database, raw Claude Code or Codex logs, or screenshots that show account emails, organization names, or balances.

Use a short conventional title naming the behavior change, such as `fix: preserve account identity during refresh`, `feat: show credit expiry`, or `docs: clarify local builds`.

Open the description with the concrete problem and resulting behavior, then explain the cause and fix. Under the test plan, list exact commands and results, pass counts when available, tested revision, failures, skips, and material limits. Check boxes only for completed verification. End with an accurate AI model and harness disclosure, or state that no AI tools were used. Do not guess model details or publish private maintainer research.

## Revert

When `main` is wrong, revert first and discuss after.

- Use GitHub's Revert button, or `git revert <sha>` on a new branch. Title: `revert: <original title> (#N)`.
- Body: the original PR and commit, what broke, and what must be true to reland.
- Reland as a new PR.
- A bug already in a release: revert on `main`, then cut a patch release. There is no updater; users get it through the cask.

Every merge is one squashed commit that passed `Check`, so any change reverts as one commit. [Data compatibility](AGENTS.md#data-compatibility) keeps that safe for stored data.

## Follow through

Maintain the branch, resolve conflicts, and verify review findings against the source. Fix real findings and explain false positives with specific evidence. When asked to monitor a PR, inspect checks and comments newer than the last push and stay quiet while nothing has changed. Stop when the configured review bots are green on the latest commit.

Merge only with the disposition authorized by the maintainer or user. Otherwise leave the PR open and report its state.
