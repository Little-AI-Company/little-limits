# 0001. History database rereads

- Status: accepted
- Date: 2026-10-31, recording decisions made from 2026-10-15 on
- Code: `Sources/UsageHistoryStore/HistoryDatabase.swift`, `Sources/UsageHistoryStore/LogIngestor.swift`, `Sources/AIUsageStats/HomeForecastHistory.swift`

## Context

Most of the usage history database is derived from local Claude Code and Codex logs, which stay on the Mac and can be read again: responses, commands and Codex quota backfill. Two things exist only in the database: the quota readings the app records from its own refreshes, and facts from logs that Claude Code or Codex has since deleted. So a migration never deletes those rows; to make the app read logs again it clears read positions. The repository history is short (back to 2026-10-15), so these rules were kept here instead of in comments beside the migrations.

## Decision

A migration may clear read positions to force a reread, instead of rewriting stored rows.

- `v2` adds `codexBackfillAccount`, the Codex account links ingestion has applied. Quota backfill matches log readings to app accounts when it reads them, so an account linked after its logs were read needs them read again. A newly linked account rereads every Codex log, and unique keys make that reread add only the new account's readings.
- A Codex account id that two app accounts share is given to neither, because a reading cannot say which account it belongs to.
- `v3-quota-reading-index` exists because the Home forecast reads the readings observed since a time; without the index, every committed change scans the whole quota history. The latest reading per account already walks the primary key, which starts with the account.
- The latest-reading-per-account query relies on SQLite's documented bare-column rule: with `MAX()` in an aggregate, the other selected columns come from the row that holds the maximum.
- `v3-reread-logs-for-command-attribution` cleared every read position once, because Codex commands moved to the response active when they started. Position keys are a hash of the path, which does not tell Codex logs from Claude logs, so all of them were cleared.
- `v4-completed-classifier-version` stores the classifier version applied by the last scan with no failures. Commands keep classification facts only, so newer classifier rules mean reading every log again. Rows stored before the version was recorded may come from any older version.
- A failed reread starts over next time. The classifier version is recorded only after a scan with no failures, and new Codex account links only after a run that read every Codex log, so the next run reads every log again.
- A log missing from a scan keeps its older facts. When a scan with no failures records a new classifier version, or a run records new Codex account links, the read positions of logs it did not find are dropped in the same transaction, so such a log is read, and reclassified, if it returns.

Conflict rules:

- A quota reading never changes after it is observed, so a repeated insert is ignored.
- A later read can complete a response or command, such as its final usage line or its exit status, so a repeated insert replaces the row.
- A newer read position for the same path replaces the old one.

## Consequences

- A migration or a new classifier version costs one full reread of the logs, about 2 GB of logs on the development Mac on 2026-10-14 (see [Local log findings](../USAGE-ANALYTICS-PLAN.md#local-log-findings)).
- Facts from a log that Claude Code or Codex has since deleted are kept as they were, with the classifier version that produced them.
- An older build opens a newer database and still writes to it, as [AGENTS.md: Data compatibility](../../AGENTS.md#data-compatibility) requires.
