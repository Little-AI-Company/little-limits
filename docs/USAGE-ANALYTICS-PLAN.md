# Usage analytics plan

Status: all decisions settled 2026-10-15. No implementation has started. Work follows the waves in Decision 10.

## Goal

Expand the app from a current-quota monitor into a local record of Claude and Codex usage that the user owns. Three capabilities:

1. Quota history and a forecast across accounts.
2. Per-model behavior metrics from local Claude Code and Codex logs.
3. Analysis of inline programs that models run through the shell.

All data stays on the Mac. No third-party service, no telemetry, no server.

Source material: three screenshots of Theo's quota dashboard and "How each model behaves" charts (October 2026). His data came from a request database in ClickHouse. This plan replaces that with local log files and an embedded database.

## Current state

- Each account keeps only its latest reading. A refresh replaces the previous snapshot in `accounts.json` (`UsageService.swift:650`). No history exists.
- Home already has a reset calendar, an account table with earned reset counts, and account filtering.
- Claude per-model weekly windows (`seven_day_*`) are already parsed (`ClaudeOAuthClient.swift:345`).
- Codex earned quota-reset counts are already parsed (credit unit `resets`).
- Nothing reads `~/.claude/projects` or `~/.codex/sessions`.
- Refresh runs on a 300 second timer (`ApplicationDelegate.swift:204`).

## Local log findings

Observed on 2026-10-14 on the development Mac. Only key names and counts were inspected, never content.

### Claude Code

- Location: `~/.claude/projects/<cwd-slug>/<sessionId>.jsonl`, with subagent logs in `<sessionId>/subagents/`. 558 files, 942 MB, data from 2026-06-09.
- One line per content block. Lines of one API response share `message.id`. 29,422 unique responses.
- Real `output_tokens` appears only on the last line of a response (`stop_reason` not null). Group by `message.id` and take the largest value.
- 25% of responses, almost all subagent responses, never get a final usage line.
- Thinking tokens: `message.usage.output_tokens_details.thinking_tokens`.
- Timing: per-line `timestamp` only. No stream start or response duration. Output speed can only be approximated.
- Tool calls: `message.content[].type == "tool_use"`. Shell commands are in `input.command` on `Bash` calls.
- No quota percentages in normal entries. Claude quota history must come from the app's own readings.
- Account identity appears in only some sessions.
- Claude Code deletes logs after 30 days by default.

### Codex

- Location: `~/.codex/sessions/YYYY/MM/DD/rollout-<ts>-<uuid>.jsonl` and `~/.codex/archived_sessions/`.
- Recent files are plain `.jsonl` (115 files, 470 MB). Older files are rewritten as Zstandard `.jsonl.zst` (258 files, 555 MB, May to October 2026).
- Model and effort per turn: `turn_context.payload.model`, `.effort`.
- Tokens per response: `token_usage_record.payload.usage`, including `reasoning_output_tokens`. Older files use `token_count.payload.info.last_token_usage`.
- Turn timing: `task_complete.payload.duration_ms` and `time_to_first_token_ms`.
- Shell commands: `item_completed.payload.item.command` with `exit_code`.
- Quota history: `token_count.payload.rate_limits.primary.used_percent`, `resets_at`, `window_minutes`. This allows a Codex quota backfill.
- Account identity: `session_meta.payload.creator_account_id`.
- A file only grows while active. Later it can be moved or compressed, so a byte offset is valid only until then.

### Platform

- macOS ships SQLite 3.54 (`/usr/bin/sqlite3`, `import SQLite3`).
- Apple's Compression framework has no Zstandard support. It offers LZ4, zlib, LZMA, Brotli, LZFSE, and newer Apple formats only.

## Feature list

Phase 1 uses data the app already has. Phase 2 adds quota history. Phase 3 adds log ingestion. Phase 4 adds inline program analysis.

### Quota and forecast

| ID | Feature | Evidence | Local implementation | Phase |
|---|---|---|---|---|
| Q1 | Total remaining across accounts | "90% / 600% remaining" | Sum of (100 - used) over each account's 7-day window | 1 |
| Q2 | Total per model each week | "7-day Fable 5 584%" | Same sum over existing `seven_day_*` windows | 1 |
| Q3 | Time until an exhausted account is usable | "back in 8h 58m" in red | Latest reset time among the account's windows at 100% used | 1 |
| Q4 | Pace indicator | "Ahead of pace", "Under pace" | Used % compared with the elapsed share of the window | 1 |
| Q5 | Next reset and its gain | "+24% in 1d 4h", "Next reset +100% Tue 9:59 PM" | Earliest reset across accounts; gain is that account's used % | 1 |
| Q6 | Sort accounts | "Ledger" and "Default" menus | Sort by soonest usable or most remaining. No grouping modes | 1 |
| Q7 | Window rows with relative and absolute reset, dimmed when none pending | Per-account rows | Mostly exists. Verify "no reset pending" is its own state | 1 |
| Q8 | Resets remaining | "Resets remaining: --" | Exists for Codex in the Home table. Verify placement | 1 |
| Q9 | Refresh one account | "Refresh quota" | Add a native Refresh control on the account page. `UsageService.refreshAccount(id:)` exists; the UI has only Refresh All | 1 |
| Q10 | Last seen | "Last seen Oct 13, 1:00 PM" | Last time the reading changed, from history. Not the last fetch | 2 |
| Q11 | Drain rate | "~7.7% per hour" | Slope of total remaining over a recent period, ignoring reset jumps | 2 |
| Q12 | Remaining chart with projection | Solid history, dashed projection, "Now" line | History table plus a line chart | 2 |
| Q13 | Time the total reaches zero | "Pool reaches 0% Fri 4:56 AM" | Step forward hourly: subtract drain rate, add reset gains | 2 |
| Q14 | Forecast range | "Next 7 days" | Pop-up menu: 1 day or 7 days | 2 |
| Q15 | One bar split by account | Phone mockup segmented bar | Home window only | Later |
| Q16 | Account search | "Search by filename or email" | Home already filters accounts. Extend only if needed | Later |
| Q17 | Forecast settings | Collapsed disclosure | Fixed defaults until use shows a need | Not planned |
| Q18 | Reset limits button | "Reset limits" | Spends a reset. Monitoring stays read-only | Not planned |

### Model behavior

All Phase 3. Metrics are per model, never per account.

| ID | Metric | Evidence | Computation | Caveat |
|---|---|---|---|---|
| M1 | Output speed, tokens/s | "Output speed, tok/s" | Both providers: output tokens, thinking included, / (response's last log line - previous prompt or tool result) | Includes the wait before the first token. Label approximate; compare within one provider |
| M2 | Steps per turn | "Steps per turn" | Claude: responses from a human prompt to `end_turn`. Codex: `task_started` to `task_complete` | None |
| M3 | grep instead of rg | "Uses grep instead of rg" | Classify shell search commands | Definition depends on Decision 7 |
| M4 | Piped into head or tail | "Commands piped into head or tail" | Pattern match on the command | None |
| M5 | git status runs per commit | "git status runs per commit" | `git status` count / successful `git commit` count | Success from exit code or `is_error` |
| M6 | Shell command length | "Mean shell command length, chars" | Character count | Heredocs skew the mean |
| M7 | Thinking share of output | "Thinking share of output tokens" | Claude `thinking_tokens`, Codex `reasoning_output_tokens`, over output tokens | Excludes responses with no final usage |
| M8 | Parallel tool calls | "Responses with parallel tool calls" | Claude: more than one `tool_use` per `message.id` | Codex runs one `exec` call that may start several commands. Footnote the difference |
| M9 | Small sample warning | "Models with under 5k requests are noisy" | Store counts. Dim models under a threshold | None |

### Inline programs

All Phase 4.

| ID | Feature | Evidence | Computation |
|---|---|---|---|
| P1 | Share of commands running inline code, Python and JavaScript | "Programs instead of commands" | Detect `python3 - <<`, `python -c`, `node -e`, heredocs into node |
| P2 | Saved script runs, counted separately | "Running a saved script file does not count" | Detect `python3 path.py` |
| P3 | Split by project | "outside the busiest project" | Working directory folder name |
| P4 | Purpose of inline Python | "Edits a file in place", "Reads JSON", "Writes a new file", "Other" | Ordered keyword rules |
| P5 | Script length | "median Opus 5.5 script is 16 lines" | Line count of the heredoc body, median and 90th percentile |

### Storage foundation

| ID | Component | Purpose | Phase |
|---|---|---|---|
| S1 | History database | One SQLite file in `~/Library/Application Support/AI Usage Stats/` | 2 |
| S2 | Quota observation recorder | Add a row for every successful reading (Decision 6) | 2 |
| S3 | Codex quota backfill | Read `rate_limits` from rollout logs. Match `creator_account_id` to the account's `providerAccountID` | 2 |
| S4 | Log ingestor | Runs on the refresh timer. Tracks a byte offset per file, rescans for new files, rereads a file after it moves. Each read resumes at the first line of the file's last response, which may still be growing; records emitted again replace the earlier ones | 3 |
| S5 | Claude log parser | Groups lines by `message.id` into response records | 3 |
| S6 | Codex log parser | Joins usage to model through `turn_id` | 3 |
| S7 | Command classifier | Pure function from a command string to stored facts | 3 |
| S8 | Forecast calculation | Pure function from observations to projection and events | 2 |

## Open decisions

Mark each decision with the chosen option and date. A decision is settled only when the Decision line is filled in. Each decision cites the screenshot evidence it rests on: S1 is "How each model behaves", S2 is "Programs instead of commands", S3 is the quota dashboard with the phone mockup.

### 1. Database layer

- Screenshot evidence: the source post says every Claude and Codex request went into a ClickHouse database. Every chart in S1 and S2 is a count, share, mean, or median grouped by model over that store. An embedded SQL database is the local equivalent.

- Options: raw SQLite C API; GRDB (Swift layer on system SQLite); DuckDB; SwiftData.
- Considerations: derived data is small (tens of thousands of rows per month), so SQLite is fast enough. GRDB adds typed records, migrations, and change observation for SwiftUI. DuckDB adds a large C++ build and reads `.zst` directly. SwiftData has no SQL aggregates.
- Recommendation: GRDB.
- Decision: GRDB, 2026-10-14. Use a `DatabasePool` in write-ahead log mode, `DatabaseMigrator` for schema versions, `Codable` records, and `ValueObservation` for live UI updates. This is the project's first external dependency.

### 2. What is stored from logs

- Screenshot evidence: each stored field maps to a chart.
  - S1: "Uses grep instead of rg", "Commands piped into head or tail", "git status runs per commit", "Mean shell command length, chars".
  - S2: Python and JavaScript split; "Running a saved script file does not count"; "What the inline Python does" with four groups that "come from keywords in the code"; "The median Opus 5.5 script is 16 lines"; "outside the busiest project".
  - S1 footnote: for Codex, "each command inside a code-mode script counts as one shell command". Store one record per Codex command execution, not per `exec` call.

- Options: derived facts only (flags, counts, lengths, categories); derived facts plus the argument-free program sequence; raw command text.
- Considerations: prompts, replies, tool output, and file contents are never stored under any option. Derived facts keep the database free of secrets that appear in commands. A metric added later cannot be computed for logs that the source tools have already deleted. Raw text would make the database as sensitive as the logs, and it would outlive them.
- Recommendation: derived facts plus the program sequence.
- Decision: derived facts plus program sequence, 2026-10-14.
  - Per command: model, provider, time, project folder name, character length, line count, search program (grep, rg, none), pipe into head or tail, git status, git commit with success, inline interpreter (Python, JavaScript, none), saved script run, inline script purpose, inline script line count.
  - Program sequence: pipeline and command-list program names with all arguments removed, for example `grep | head`, `git status`, `python3 <<heredoc`. The only kept words after a program name are subcommands from a fixed allow list (such as `git status`, `git commit`); everything else is dropped.
  - Every record carries a classifier version. When rules change, recompute records whose source logs still exist; older records keep their earlier classification.

### 3. Compressed Codex logs

- Screenshot evidence: S1 and S2 compare older Codex models (GPT-5.5, GPT-5.6 Sol) beside current ones, and S1 notes "Models with under 5k requests are noisy". On the development Mac, GPT-5.5 and GPT-5.6 Sol appear only in compressed logs; plain logs contain only GPT-6.1 Sol and GPT-6 Astra. Without a decoder, those comparisons are impossible and fewer models reach a useful sample size.

- Options: official `facebook/zstd` Swift package (product `libzstd`); vendor the decoder source as a C target; skip `.zst` files; run an installed `zstd` command.
- Considerations: Codex compresses a session when it is archived (204 of 258 compressed files are in `archived_sessions`) and in irregular batches, not at a fixed age. Without a decoder, the app loses May to October 2026 history and any session archived before ingestion reads it.
- Recommendation: official package.
- Decision: official `facebook/zstd` package pinned to a release tag, 2026-10-14. Decompress as a stream and parse line by line; never load a whole file into memory. Second external dependency.

### 4. Where trends appear

- Screenshot evidence: S3 places the forecast chart directly above the per-account list on one page, and the phone mockup puts the pooled weekly figure above per-account rows. S1 and S2 are a separate report titled "How each model behaves" with no account in it.

- Options: a new tab in the Home window; a separate window; both.
- Considerations: the menu bar stays quota only. SwiftUI is now allowed, so Swift Charts in an AppKit window is possible.
- Recommendation: forecast in Home; model behavior in its own sidebar item.
- Decision: forecast in Home, new "Models" sidebar item, 2026-10-14.
  - Home gains a forecast summary and chart above the reset calendar.
  - "Models" is a new section in the management window sidebar (`AccountsWindowController.swift:7`). It holds model behavior (M1 to M9) and inline programs (P1 to P5).
  - New pages are SwiftUI views in `NSHostingController` inside the existing AppKit window, with Swift Charts.
  - The menu bar shows text rows only, such as total remaining, time until usable, and next reset. No charts in the menu.

### 5. Forecast rules

- Screenshot evidence (S3):
  - "90% / 600% remaining" is the sum of the 7-day limit column (0 + 0 + 90 + 0 + 0 + 0) for six Claude accounts, and the chart axis tops out at 600%. The total is 7-day only and capped at account count times 100%.
  - "7-day Fable 5 584%" is the sum of the Fable column (100 + 94 + 100 + 100 + 90 + 100). It appears as text in the provider header, not as a chart line.
  - "Claude, 6 credentials" groups accounts by provider.
  - "Next reset +100% Tue 9:59 PM" is the "ping" account resetting from 0% remaining. The gain equals that account's current used amount.
  - The dashed projection falls at a constant rate through nights, which matches an hourly average that includes idle time.
  - Percentages are remaining, not used. The forecast uses remaining.

- Sub-questions: separate Claude and Codex totals (recommended: always separate); which windows count (7-day only, or 5-hour too); drain rate lookback (24 hours, 7 days); per-model weekly forecast or total only.
- Recommendation: separate providers, 7-day window, 24 hour lookback, total only at first.
- Decision: as recommended, 2026-10-14.
  - Claude and Codex totals are always separate. Their percentages measure different quotas.
  - Only the 7-day window feeds the total and forecast. The 5-hour window affects only per-account availability (Q3).
  - Drain rate is computed per account, then summed: each account's increase in used percentage between its own consecutive current readings, over the last 24 hours, divided by the hours covered, including idle time. Intervals that contain that account's reset, or that start or end on a missing, failed, or stale reading, are skipped. Accounts joining or leaving the pooled total therefore never register as drain. With less than 24 hours of history, use all available history and say so.
  - Reset rule: at an account's reset, the projected total gains that account's used percentage as of now. This slightly underestimates the gain because future use cannot be assigned to a specific account. The total never falls below 0 or rises above the account count times 100%.
  - Per-model weekly windows show a pooled total as text (Q2) but get no forecast line at first.
  - Unknown readings: the total and its denominator include only accounts with a current, available 7-day reading. Accounts with a missing, unsupported, failed, or stale reading are left out and counted beside the total, for example "90% / 500% remaining, 1 account unknown". A stale last-known value never counts as current. With no current readings, the total is unknown, not 0%.

### 6. Quota history recording

- Screenshot evidence (S3): the solid history line before "Now", "Last seen" on each account, and "~7.7% per hour" all require stored readings over time. The current app keeps only the latest reading.

- Options: OAuth usage endpoint on the existing 300 second refresh; status-line capture; both.
- Considerations: readings are recorded only when the app is running. Gaps must show as gaps, not as zero or as a straight line.
- Recommendation: record whatever the existing refresh produces, from any source.
- Decision: record every successful reading, keep the 300 second refresh, 2026-10-14.
  - One history row per successful reading from any source: Claude OAuth, Claude status-line capture, Codex app-server, and the Codex log backfill. Each row carries its source.
  - A missing row is a gap. Charts show gaps as gaps, never as zero or a joined line.
  - Expected volume: about 288 rows per account per day, about 630,000 rows per year for 6 accounts.
  - The Claude OAuth poll stays at 300 seconds to limit load on a private endpoint.

### 7. Metric definitions

- Screenshot evidence:
  - S1 "Uses grep instead of rg": Claude 91 to 100%, Codex 0 to 2%. Counting shell commands only reproduces this on local data: Claude about 90% (12.5k grep, 1.3k rg), Codex 1.7% (34 grep, 1,936 rg).
  - S1 footnote: "tok/s is output tokens per second of streaming, thinking included. For Codex the stream opens before the first token, so compare speed within one provider."
  - S1 reports mean command length. S2 reports a median for script lines.
  - S1 "Responses with parallel tool calls": GPT-6.1 Sol 17%, GPT-6 Astra 3%. In local Codex logs, 3% of responses have two or more tool calls, but 15% run an `exec` with two or more commands, mostly GPT-6.1 Sol.
  - S1 footnote: "Steps per turn counts model calls before the agent stops and replies, in sessions with tool use."
- Decision: 2026-10-14.
  - M3 grep instead of rg: shell commands only. Claude's Grep tool is not counted. The footnote states this.
  - M1 output speed: one rule for both providers. Output tokens, thinking included, divided by the time from the previous prompt or tool result to the response's last log line. Labeled approximate, with the "compare within one provider" note.
  - M6 command length: mean as the headline, median beside it.
  - M8 parallel tool calls: Claude counts responses with two or more `tool_use` blocks. Codex also counts an `exec` call that runs two or more commands. The footnote states the Codex rule.
  - M2 steps per turn: Theo's definition as written. Only sessions with at least one tool call.

### 8. Retention

- Screenshot evidence: S1 and S2 compare model generations side by side (Opus 5 and Opus 5.5, Fable 5 and Fable 5.1, GPT-5.5 and GPT-6.1 Sol), and S1 warns that models "with under 5k requests are noisy". Generation comparisons need months of history. S3 shows only a few days of quota history before "Now".
- Options: keep forever; keep a fixed number of months; user setting.
- Recommendation: keep forever. Derived data is small.
- Decision: keep forever, 2026-10-14. Expected size is tens of MB per year. Thin old quota readings to hourly only if size becomes a measured problem.

### 9. Phase 1 scope

- Screenshot evidence: every element of the S3 phone mockup ("12% left", "Ahead of pace", "Under pace", "+24% in 1d 4h", per-account rows with percentage and reset time) and the S3 "back in 8h 58m" and sort controls derive from current readings without history.
- Which of Q1 to Q9 ship first, and whether Phase 1 ships before the database exists.
- Recommendation: ship Q1 to Q7 without any database, in parallel with the database foundation.
- Decision: Phase 1 (Q1 to Q7 and Q9, plus verifying Q8) runs in parallel with the `UsageHistory` foundation, 2026-10-14. Phase 1 changes Home, the menu, and pure functions in `UsageCore`; the foundation is a new target, so they share no files. Phase 2 forecast UI starts after Phase 1 lands, because both change Home.

### 10. Work split for parallel workflows

- Screenshot evidence: the three screenshots map onto separate streams. S3 is quota and forecast, S1 is model behavior, S2 is the command classifier.
- Constraint: the development Mac is already busy, so streams that do not need macOS run as cloud sessions. Cloud sessions run Linux.
  - Nothing in the current package builds on Linux. `UsageCore` imports Security, LocalAuthentication, CryptoKit, and Darwin (`ClaudeOAuthClient.swift`, `CodexClient.swift`, `Storage.swift`), and `AIUsageStats` imports AppKit.
  - GRDB lists Apple platforms only. Its README says Linux support "is not automatically tested, and not officially maintained." Cloud work must not depend on it.
  - Claude and Codex logs never leave the Mac. Cloud sessions use small synthetic fixtures written from the field list in "Local log findings".
- Decision: one owner and one PR per stream, merged in wave order, 2026-10-15.
  - Two history targets instead of one:
    - `UsageHistory`: record types, the classifier's input and output types, both log parsers, the Zstandard line reader, the command classifier, and the forecast. Depends only on Foundation and `libzstd`. Never imports `UsageCore`, GRDB, or an Apple-only framework. Builds and tests on Linux and macOS.
    - `UsageHistoryStore`: GRDB schema, migrations, reads and writes, and per-file read positions. macOS only.
  - `Package.swift` declares the macOS-only targets inside `#if os(macOS)`, so `swift test` on Linux builds only `UsageHistory` and its tests.
  - Account matching stays on the Mac. The Codex parser emits quota readings keyed by `creator_account_id`; stream 2a maps them to app accounts.
  - Each parser PR is checked on the Mac against the real logs before merge, using the counts in this document as reference: 29,422 Claude responses; Claude shell searches about 12.5k grep and 1.3k rg; Codex 34 grep and 1,936 rg. Only counts are compared, never content.

| Wave | Stream | Runs on | Owns | Depends on |
|---|---|---|---|---|
| 0 | Foundation | Mac | `Package.swift` (GRDB, `facebook/zstd`, Linux target split), `UsageHistory` record and classifier types, `UsageHistoryStore` schema version 1 (quota readings, responses, shell commands, file read positions), cloud environment setup | Nothing |
| 1 | Phase 1 quota display | Mac | Pure functions in `UsageCore` (total remaining, time until usable, pace, next reset), Home and menu files | Nothing |
| 1 | Claude log parser | Cloud | `UsageHistory/ClaudeLogParser.swift`, tests, fixtures | Foundation merged |
| 1 | Codex log parser | Cloud | `UsageHistory/CodexLogParser.swift`, `UsageHistory/ZstandardLineReader.swift`, Codex quota reading extraction, tests, fixtures | Foundation merged |
| 1 | Command classifier | Cloud | `UsageHistory/CommandClassifier.swift`, tests | Foundation merged |
| 1 | Forecast | Cloud | `UsageHistory/QuotaForecast.swift`, tests | Foundation merged |
| 2a | App integration | Mac | Quota recorder in `UsageHistoryStore`, log ingestion on the refresh timer, Codex account matching, hooks in `UsageService` and `ApplicationModel` | Wave 1 |
| 2b | Home forecast UI | Mac | New SwiftUI files for the Home forecast | Phase 1 and 2a |
| 2b | Models page | Mac | New SwiftUI files for the Models page, metric queries, sidebar item | 2a |
| 3 | Documents and app check | Mac | `README.md`, `docs/research/claude.md`, `VALIDATION.md`; checks in the running `.app` | Everything |

- Order on the Mac: one local stream builds at a time. Foundation goes first because cloud sessions start from `main`, so it must merge before wave 1 starts. Phase 1 then runs on the Mac while the four cloud streams run. Stream 2b runs its two streams one after the other.
- Phase 1 moved from wave 0 to wave 1 so the Mac never builds two streams at once.
- The parsers do not call the command classifier. A parser emits each shell command as an event that holds the command text in memory only. Stream 2a classifies the event and stores the resulting facts; command text is never written. The four cloud streams therefore share only the types Foundation writes.

## Cloud environment

Source: [Claude Code cloud environments](https://code.claude.com/docs/en/cloud-environments.md), read 2026-10-15.

- Each cloud session is a fresh Ubuntu 24.04 x86_64 VM with about 4 CPUs, 16 GB of memory, and 30 GB of disk. Swift is not installed.
- The default "Trusted" network access allows github.com and swift.org but not `download.swift.org`, where the toolchain is hosted. Installing Swift fails until that host is allowed.
- A setup script runs once per environment. The resulting file system is cached for about seven days when the script finishes in about five minutes. The Swift 6.4.0 toolchain archive is 1.1 GB, so the first session must confirm that setup is cached.
- Settings live on claude.ai/code: environment selector, then the settings icon on the environment.

Configuration for the "Swift Mac App Dev" environment, created 2026-10-15. Cloud sessions for this repository use it, not "Default":

1. Network access: Custom, keep the default list, add `download.swift.org`.
2. Setup script. It installs the same Swift version as the development Mac, in the layout used by the official Swift container images:

```bash
#!/bin/bash
set -euo pipefail
SWIFT_VERSION=6.4.0
if ! swift --version 2>/dev/null | grep -q "swift-${SWIFT_VERSION}-RELEASE"; then
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    binutils git gnupg2 libc6-dev libcurl4-openssl-dev libedit2 libgcc-13-dev \
    libncurses-dev libpython3-dev libsqlite3-0 libstdc++-13-dev libxml2-dev \
    libz3-dev pkg-config tzdata unzip zlib1g-dev
  curl -fsSL "https://download.swift.org/swift-${SWIFT_VERSION}-release/ubuntu2404/swift-${SWIFT_VERSION}-RELEASE/swift-${SWIFT_VERSION}-RELEASE-ubuntu24.04.tar.gz" \
    | tar -xz --directory / --strip-components=1
fi
swift --version
```

3. Before wave 1, start one cloud session that runs `swift --version`, then `swift test` on `main` after Foundation merges. Record the setup duration and whether the second session starts without reinstalling. Wave 1 does not start until both pass.

Rules for every cloud brief:

- State that the session runs Linux, and name the exact checks: `swift build --target UsageHistory` and `swift test`.
- State that real Claude and Codex logs are not available and must not be requested. Use synthetic fixtures.
- Name the files the stream owns. The session pushes its branch and opens a ready-for-review PR against `main`.
- Never commit `Package.swift` or `Package.resolved` changes. On Linux, SwiftPM can rewrite `Package.resolved` without the macOS-only GRDB pin.

## Tests to keep

Only behavior that can plausibly break:

- Command classifier against small redacted command samples.
- Forecast: reset jumps, zero crossing, gaps in history.
- Claude response grouping by `message.id`, including responses with no final usage line.
- Codex quota backfill does not attach readings to the wrong account.

## Documents to update

`docs/STRATEGY.md` and `AGENTS.md` are updated with this plan, before implementation, so the new dependencies, SwiftUI pages, and log reading are within the documented scope when they land. `README.md` and `docs/research/claude.md` still describe the original scope and are updated in wave 3, with `VALIDATION.md` evidence.
