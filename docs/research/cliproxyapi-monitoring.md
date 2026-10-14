# CLIProxyAPI monitoring research

The largest improvement for AI Usage Stats is a Home calendar combined with an account comparison table. Our app already receives multiple quota windows, model-specific Claude limits, Codex credit balances, and earned quota-reset counts. The useful additions are clearer presentation, retained plan metadata, and precise distinctions between quota resets, credit expirations, and subscription dates.

Source review on October 13, 2026 covers AI Usage Stats at `0485bbec496a18c32cdecd96e087a586f7c586bf`, CLIProxyAPI at `bf9341629ef2300ac9d846a2e80fe2756f63a671`, and its Management Center at `390718ecfec90b674fed474862e497522273e129`. These are implementation findings, not verified provider contracts. No provider requests, credentials, model requests, reset consumption, or application execution were used. Existing local documentation and skill changes were preserved.

## What the screenshot contributes

The supplied screenshot makes several accounts comparable through aligned columns for session, weekly, model-specific weekly limits, and manual resets. It places a plan and a date beside each account and pairs reset countdowns with exact timestamps. Those information choices can improve our Home view without copying the web interface or credential filenames.

The current Management Center implements matching quota features, but its current [QuotaPage](https://github.com/router-for-me/Cli-Proxy-API-Management-Center/blob/390718ecfec90b674fed474862e497522273e129/src/features/quota/QuotaPage.tsx#L324-L430) uses provider tabs and a card grid. The screenshot's exact repository and revision remain unidentified.

## Features already present and actual gaps

| Feature | Current AI Usage Stats | Useful next step |
| --- | --- | --- |
| Remaining percentage and next reset | Stored used percentages and reset dates; remaining summaries are already calculated | Put icon, remaining percentage, and window name on each calendar event |
| Claude model limits | Dynamically parses quota-bearing `seven_day_*` objects and scoped `limits[]`, including model name and activity | Show all returned model limits in the account table and hover details |
| Codex named quota meters | Reads `rateLimitsByLimitId` with legacy fallback and provider window durations | Keep scope and duration in calendar data; do not assume every primary window is five hours |
| Codex credits and earned resets | Separates credit units from dollars; retains reset count, grant status, expiry, and explicit nonexpiry | Show available reset count and earliest known expiry separately from quota |
| Plan | Codex decodes plan fields but drops them from snapshots; Claude profile retains identity without plan flags | Retain optional provider plan metadata, with unknown values preserved |
| Unknown, inactive, failed, and stale readings | Explicit snapshot states and inactive-window exclusion; sidebar has text and severity | Carry these states into Home and keep accounts visible when no reset can be placed |
| Refresh coordination | Per-account work reuse and account generation guards already exist | Reuse the coordinator for Home rather than introducing a second polling system |

Local evidence: [Claude parsing](../../Sources/UsageCore/ClaudeOAuthClient.swift), lines 276–369; [Claude profile](../../Sources/UsageCore/ClaudeOAuthClient.swift), lines 217–231; [Codex parsing](../../Sources/UsageCore/CodexClient.swift), lines 23–116 and 187–202; [account summaries](../../Sources/UsageCore/AccountQuotaSummary.swift); [refresh coordination](../../Sources/UsageCore/UsageService.swift), lines 466–491, 543, and 595.

Upstream displays remaining quota as `100 - used` for both [Claude](https://github.com/router-for-me/Cli-Proxy-API-Management-Center/blob/390718ecfec90b674fed474862e497522273e129/src/features/quota/providers/claude/ClaudeQuotaBody.tsx#L45-L76) and [Codex](https://github.com/router-for-me/Cli-Proxy-API-Management-Center/blob/390718ecfec90b674fed474862e497522273e129/src/features/quota/providers/codex/CodexQuotaBody.tsx#L174-L205). Home should say Remaining quota consistently, while preserving the existing menu's explicit used wording.

## Calendar and hover behavior

Use only current, provider-reported next reset timestamps in the first implementation. A window without a known time stays in the account table with Time unavailable. An explicitly inactive window says Inactive and does not become a calendar reset. A missing time alone does not establish No reset pending.

A calendar event needs account identity and window scope as well as its icon and percentage. Several limits can reset simultaneously for one account. Hover can expose the full identity, plan, all relevant windows, exact dates with time zone, and reading timestamp. Clicking the event or pressing Return after keyboard selection should expose the same details; hover cannot be the only access path. Apple recommends [compact anchored popovers](https://developer.apple.com/design/human-interface-guidelines/popovers) and [keyboard access](https://developer.apple.com/design/human-interface-guidelines/keyboards).

The first reset does not necessarily restore account availability. A five-hour quota can reset while a weekly quota remains exhausted, and a model limit applies to its named model. Use Next reset with the specific window, rather than Available again.

Use local calendar arithmetic for date boundaries and daylight-saving changes. The upstream [timeline model](https://github.com/router-for-me/Cli-Proxy-API-Management-Center/blob/390718ecfec90b674fed474862e497522273e129/src/features/quota/quotaTimelineModel.ts#L121-L185) also attaches remaining percentages only to the currently observed window. If recurrence is added later, label future occurrences as forecasts and omit invented percentages.

Keep stable saved account order by default. An explicit filter or sort can offer provider, account identity, or next reset. The upstream [search and sorting logic](https://github.com/router-for-me/Cli-Proxy-API-Management-Center/blob/390718ecfec90b674fed474862e497522273e129/src/features/quota/logic.ts#L52-L117) provides a useful reference, but our public account identities should replace credential filenames.

## Dates and labels that require care

**Earned reset expiration is not replenishment.** Current upstream [reset-credit rendering](https://github.com/router-for-me/Cli-Proxy-API-Management-Center/blob/390718ecfec90b674fed474862e497522273e129/src/features/quota/providers/codex/CodexQuotaBody.tsx#L128-L165) uses each grant's expiry. No next-grant schedule is established by the inspected fields. Show 2 available and Earliest expiry, never Reset arrives on that date. Its [recovery sorter](https://github.com/router-for-me/Cli-Proxy-API-Management-Center/blob/390718ecfec90b674fed474862e497522273e129/src/features/quota/resetSchedule.ts#L77-L118) includes expiry as a recovery instant; that interpretation should not be ported.

**A subscription end date does not prove renewal.** Codex enrichment reads a private subscriptions endpoint or falls back to `active_until` metadata. The source establishes an active-until date, not a promised payment or replenishment. Keep any future subscription date outside quota reset events and label its actual meaning. [Subscription lookup](https://github.com/router-for-me/Cli-Proxy-API-Management-Center/blob/390718ecfec90b674fed474862e497522273e129/src/features/quota/providers/codex/data.ts#L318-L359), [JWT field extraction](https://github.com/router-for-me/CLIProxyAPI/blob/bf9341629ef2300ac9d846a2e80fe2756f63a671/internal/api/handlers/management/auth_files.go#L926-L937).

**Plan multipliers are not established fields here.** The Claude resolver produces Team, Max, Pro, or Free from profile flags, with incomplete data left unknown. It does not establish Max 20x. Codex maps plan codes to frontend labels such as Pro 200 and Pro 100; the screenshot's Pro 20x is not a measured multiplier. Retain plan codes and verified descriptions without inventing capacity weights. [Claude plan resolution](https://github.com/router-for-me/Cli-Proxy-API-Management-Center/blob/390718ecfec90b674fed474862e497522273e129/src/features/quota/providers/claude/data.ts#L150-L174), [Codex label mapping](https://github.com/router-for-me/Cli-Proxy-API-Management-Center/blob/390718ecfec90b674fed474862e497522273e129/src/features/quota/providers/codex/CodexQuotaBody.tsx#L53-L66).

**Model names must follow actual scope.** The upstream Fable parser recognizes provider scope metadata, but a legacy field can instead hold dollar-denominated cloud-session credits. Do not rename every legacy grant or limit Fable 5. Our current dynamic parser is the better starting point. [Scope and legacy-field distinction](https://github.com/router-for-me/Cli-Proxy-API-Management-Center/blob/390718ecfec90b674fed474862e497522273e129/src/features/quota/providers/claude/data.ts#L41-L114).

## Later monitoring candidates

Claude extra usage spending could be shown separately from prepaid credit balances. Upstream divides `monthly_limit` and `used_credits` by 100 to display dollars. Validate those monetary units and account binding before integrating them; a spending cap is not a remaining prepaid balance. This also requires a scope decision because the current product excludes general spending analytics. [Fields](https://github.com/router-for-me/Cli-Proxy-API-Management-Center/blob/390718ecfec90b674fed474862e497522273e129/src/types/quota.ts#L122-L138), [conversion](https://github.com/router-for-me/Cli-Proxy-API-Management-Center/blob/390718ecfec90b674fed474862e497522273e129/src/features/quota/providers/claude/ClaudeQuotaBody.tsx#L34-L40).

Additional Codex meters, such as code review, can use our existing named-meter path if the installed CLI actually returns them. Do not promise a meter based only on an HTTP implementation in another app. [Upstream window classification](https://github.com/router-for-me/Cli-Proxy-API-Management-Center/blob/390718ecfec90b674fed474862e497522273e129/src/features/quota/providers/codex/data.ts#L66-L289).

xAI is a possible future provider. Upstream separates weekly quota from monthly monetary billing, but its paid-account fallback sends a model request with a one-token ping. That fallback conflicts with read-only monitoring. Any xAI adapter must use validated account reads and retain unavailable data when they fail. The inspected URLs are private implementation evidence, not an official usage API. [Billing endpoints](https://github.com/router-for-me/Cli-Proxy-API-Management-Center/blob/390718ecfec90b674fed474862e497522273e129/src/utils/quota/constants.ts#L155-L178), [model-request fallback](https://github.com/router-for-me/Cli-Proxy-API-Management-Center/blob/390718ecfec90b674fed474862e497522273e129/src/features/quota/providers/xai/data.ts#L104-L149).

Monitoring an already-running CLIProxyAPI instance could be a separate connection option. Its v8 management API lists credentials and forwards account-specific upstream requests. The management key also permits writes, and token resolution can refresh server-owned credentials. This needs a defined set of permitted read operations and explicit account binding; it does not justify embedding a Go proxy or reusing another app's refresh tokens. [v8 routes](https://github.com/router-for-me/CLIProxyAPI/blob/bf9341629ef2300ac9d846a2e80fe2756f63a671/internal/api/server_management_v8.go#L17-L50), [credential-selected forwarding](https://github.com/router-for-me/CLIProxyAPI/blob/bf9341629ef2300ac9d846a2e80fe2756f63a671/internal/api/handlers/management/api_tools.go#L136-L175).

## Functions outside this monitoring app

Keep proxy routing, failover, model translation, account rotation, credential editing, and quota-reset consumption outside Home. The screenshot's Reset quota control [consumes a grant](https://github.com/router-for-me/Cli-Proxy-API-Management-Center/blob/390718ecfec90b674fed474862e497522273e129/src/features/quota/providers/codex/data.ts#L492-L539). Even the upstream usage-queue GET [pops records](https://github.com/router-for-me/CLIProxyAPI/blob/bf9341629ef2300ac9d846a2e80fe2756f63a671/internal/api/handlers/management/usage.go#L23-L42), so it is unsuitable for passive monitoring alongside another dashboard.

Both source repositories use MIT licenses. Future substantial source reuse must preserve the applicable notices: [backend license](https://github.com/router-for-me/CLIProxyAPI/blob/bf9341629ef2300ac9d846a2e80fe2756f63a671/LICENSE), [frontend license](https://github.com/router-for-me/Cli-Proxy-API-Management-Center/blob/390718ecfec90b674fed474862e497522273e129/LICENSE).

## Proposed first implementation

Build Home from the existing profiles, snapshots, quota summaries, provider icons, and refresh coordinator. Start with known next quota resets and a flat account table showing every returned window. Table columns or sections must adapt to actual window scopes; Fable 5 is example data, not a required column for every account. Keep plan optional; retain available Codex plan data and add Claude plan fields within the existing profile read. Preserve account identity and unknown values during enrichment.

Provide month and two-week layouts, account/provider filtering, exact dates plus countdowns, and the same details through pointer and keyboard. Missing or stale readings remain visible in the table without becoming fabricated calendar events. Credits and any subscription dates remain separate information.

The two revised ImageGen concepts use fictional data and proposed layout:

- [Month calendar with account comparison](../../assets/design/home-calendar-explorations/month-account-comparison.png)
- [Two-week calendar with account comparison](../../assets/design/home-calendar-explorations/two-week-account-comparison.png)

They are visual explorations, not running UI or accessibility evidence. Provider integration and app code were not changed in this research pass.
