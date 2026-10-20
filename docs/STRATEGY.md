# Product scope

Little Limits shows the available Claude and Codex usage state for several accounts in a small native macOS menu bar panel, and keeps a local record of that usage that the user owns. The [usage analytics plan](USAGE-ANALYTICS-PLAN.md) defines the history, forecast, and model behavior features.

## Information to show

For each account, show the provider, a stable account label, subscription usage percentages, reset countdowns, and the time of the last reading. Keep account order stable while data refreshes. Support the windows the provider returns rather than assuming every plan has the same duration.

The management window opens to Home. Its two-week or month calendar places each current, provider-reported quota reset on its local date, with the provider icon, remaining percentage, and account identity. Hover or activate an event to inspect that account and open its existing management view. An aligned account table shows reported plans, quota windows, earned reset counts, and observation times. Account filtering applies to both views. Calendar percentages are the latest reading, not predicted capacity on the reset date. Do not repeat resets into future cycles or infer plan multipliers.

Show monetary API credit balances and expiry separately from subscription limits. Show Codex credit units separately from dollars. Earned Codex limit resets are a count with their own expiry, not a purchased credit balance. Never infer remaining prepaid dollars from token totals, API costs, or a subscription usage percentage.

Unknown, unsupported, failed, and stale readings must remain recognizable. A missing percentage is not zero. A reset time is not an account billing date. A credit expiry is not a quota reset time.

## Usage history

The app records every successful quota reading and reads local Claude Code and Codex logs on this Mac. Home shows a remaining-quota forecast; the Models page shows per-model behavior. History stays in a local database. Logs yield derived facts only: counts, lengths, categories, and argument-free program names. Prompts, replies, tool output, file contents, and command text are never stored. Behavior metrics are grouped by model, never by account. Gaps in history remain gaps.

## Sources and account isolation

Claude subscription connections use a separate browser OAuth grant for each app profile and request usage immediately after sign-in. The app stores its own credential in Keychain and reads private usage and profile endpoints directly. This integration is experimental. A new usage-only grant and live quota retrieval were verified for one account; multiple live accounts and automatic renewal still need verification. An account must not require a terminal conversation to produce its first reading.

Bind the grant to the required provider account UUID and any known organization UUID, independently of the editable account name. Preserve a known organization when a later response omits it; reject explicit conflicts. Keep refresh requests, credential storage, and readings separate for each profile. Failed account removal must preserve its saved profile and app-owned grant or explicitly report failed credential recovery. Never rotate another application's refresh token, replace its login, or change its settings as a monitoring side effect.

Existing Claude Code status-line capture profiles remain supported. Capture belongs to the selected configuration directory; the helper preserves the previous command and stores quota fields rather than conversation data. Reconnecting a capture profile to the browser flow preserves its app profile identity and name, then retires only its unchanged capture wrapper after saving the new connection. Preserve user edits and retain restoration metadata when cleanup cannot finish. A capture profile still needs an actual status-line observation before it has usage data.

Retain provider-reported inactive quotas as non-current data. Label them inactive and exclude them from current percentages, measured-reading state, and quota-reset freshness decisions. Missing activity flags retain their existing current behavior.

Codex subscription readings come from the installed Codex CLI's app-server interface. The app creates a separate `CODEX_HOME` for each account and supplies a login command for that directory. Credentials remain under the Codex CLI's authentication ownership. Monitoring must not copy refresh credentials or replace the default CLI account.

The experimental Claude Console connection reads billing data using the account's isolated browser session. Its private Console endpoints are not a supported public API. Keep purchased balances separate from individual promotional grants, retain currencies and grant expiries, and display grant scope rather than assuming every promotion is a subscription grant. Console access is separate from the subscription OAuth grant and legacy status-line capture.

Provider APIs do not expose every requested billing value. Manual, dated API credit entries and official billing links remain available when automatic data is unsupported. Manual data must be labelled and must not acquire a fresh timestamp merely because a refresh occurred.

The [research reports](research/) record source details and limits. Treat provider behavior as versioned and verify it against current responses before expanding support.

## Keep the product small

Use AppKit, SwiftPM, and system frameworks. New analytics pages may use SwiftUI and Swift Charts inside the AppKit window. The only package dependencies are GRDB and facebook/zstd, pinned exactly. Require macOS 14 and Swift 6. Keep refresh work from blocking the main actor, avoid overlapping work, and keep the closed panel inexpensive. Redraw when displayed state changes. Use no continuous animation, telemetry, updater framework, or recurring GitHub Actions. Use the system browser for the experimental subscription sign-in and an isolated browser session for Console credits. Keep account, settings, and monitoring controls native.

Monitoring is read-only. Exclude storing model conversations, model-request probes, buying credits, changing plans, consuming earned resets, replacing a user's CLI login, and general spending analytics. Broader features require a separate product decision.

## Success criteria

- Several configured accounts keep their own labels and readings.
- A supported response produces the correct percentage and reset countdown.
- Credits and expiry use the provider's actual units and retain their source date.
- A missing field, expired reading, or failed connection remains visible without fabricated values.
- Native keyboard navigation, accessibility, and menu-bar behavior work in the packaged app.
- Local build and packaging work with only the pinned GRDB and zstd packages.
