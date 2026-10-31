# Claude data sources

Official-page research was verified October 9, 2026 without account requests. Public client source and the installed Claude Code credential selector were inspected October 10. The initial authorized check made one usage request and one profile request using an expired existing access token; both returned 401, without using its refresh token or changing that login. Later, the user completed the app's own browser sign-in with `user:profile` scope, and a direct quota read succeeded for one account. See [validation](../VALIDATION.md) for the evidence and limits.

## Monthly API credits

Anthropic announced monthly API credits on October 7, 2026, alongside Haiku 5.5. The official tiers are **Max 5x: $100 USD** and **Max 20x: $200 USD**. There is no Max 10x tier in the current sources. Team receives $20 per Standard seat and $100 per Premium seat, pooled up to $500. [Announcement](https://www.anthropic.com/claude-haiku-5-5)

Eligibility: an active eligible plan in good standing, at least seven days after joining; web, iOS, and Android subscriptions qualify. Free, Pro, and Enterprise do not. Max requires the subscriber; Team requires Owner or Primary Owner. The destination Console organization requires Owner, Admin, or Billing access. Claim in claude.ai Billing by linking one Console organization after reviewing the Supplemental Credit Terms. Each organization can receive credits from one plan; changing the link requires support. No Console payment card is required. The rollout can take several days. Monitoring does not complete this claim flow or accept terms.

Credits cover direct Claude API, Playground, Managed Agents, and Agent SDK. Personally running `claude -p` with an API key from the linked Console organization qualifies as Agent SDK usage. Subscription-authenticated `-p` instead consumes subscription quota. Interactive Code, Claude-app extra usage, cloud-provider API calls, and Code runs launched by an IDE, Desktop, or GitHub Action are excluded. June's Agent SDK credit offer is a different, unavailable offer. [Eligibility and coverage](https://support.claude.com/en/articles/17154008-monthly-api-credits-for-max-and-team-plans)

Credits arrive shortly after subscription payment, expire at billing-cycle end, and do not roll over. Annual plans receive monthly grants and expiry. Included credits are consumed before purchased credits. Every workspace/key in the linked organization shares them. Auto-reload watches the purchased balance, even when included credits remain. Cancellation, an ineligible downgrade, or refund stops new grants; existing grants remain until expiry. Upgrading 5x to 20x grants prorated credits immediately, except Google Play may deliver them by next renewal. Team seat changes affect the next billing month's pool.

API spend caps reset on the first of the calendar month, independently of credit renewal. Credits do not enlarge subscription limits. Console Settings > Billing > Promotional credits shows amounts and expiry. When exhausted, purchased credits continue usage; otherwise API calls stop until more credit arrives. Invoiced organizations continue normal billing. [Lifecycle](https://platform.claude.com/docs/en/about-claude/api-credits-for-subscribers)

Purchased Console credits are a separate balance, usable for API, Playground, and Claude Code. They expire one year after purchase and are non-refundable. [Purchased credit billing](https://support.claude.com/en/articles/8977456-how-do-i-pay-for-my-claude-api-usage)

Claude **usage credits**, formerly called extra usage, are another separate balance: pay-as-you-go continuation after subscription limits. They are not the new included API grants. Session limits reset every five hours; weekly limits also apply. [Claude usage credits](https://support.claude.com/en/articles/12429409-manage-usage-credits-for-paid-claude-plans)

## Legacy supported subscription observation

Claude Code's local `statusLine` command receives JSON on stdin:

```json
{
  "rate_limits": {
    "five_hour": { "used_percentage": 23.5, "resets_at": 1738425600 },
    "seven_day": { "used_percentage": 41.2, "resets_at": 1738857600 }
  }
}
```

Percentages are used, from 0 to 100. Reset times are Unix epoch seconds. Each window is optional; the entire object appears for Pro/Max only after the first API response. Expired windows disappear. This is separate from context-window percentage.

A small local helper can persist only quota fields, app profile ID, and observation time, then preserve the existing status line's stdout. The native app reads that file without provider credentials. Write atomically, restrict permissions, and discard transcript paths and conversation fields. Do not replace an existing status line silently.

The status-line capture still stores quota fields only. Since October 2026 a separate usage history reads Claude Code session logs on the Mac (`~/.claude/projects/<cwd-slug>/<sessionId>.jsonl`, including `subagents/`) and stores derived facts only, per Decision 2 of the [usage analytics plan](../USAGE-ANALYTICS-PLAN.md#2-what-is-stored-from-logs): per response the model, times, token counts, and tool call counts; per shell command its length, line count, classification, and program names with every argument removed. Session, turn, response (`message.id`), and command (`tool_use` id) identifiers are copied from the logs so a reread replaces rows instead of adding them. A project is a salted hash of the full working directory path. Prompts, replies, tool output, file contents, command text, and folder names are never stored. The log format is not a documented interface; the field meanings come from key names and counts observed on the development Mac, listed in the plan's [local log findings](../USAGE-ANALYTICS-PLAN.md#claude-code). Claude Code removes local transcripts after 30 days by default (`cleanupPeriodDays`), so the history keeps facts the logs no longer hold. [Data retention](https://code.claude.com/docs/en/data-usage#data-retention)

The status line runs locally without consuming tokens. It updates after assistant messages and certain local events. `refreshInterval` re-runs the script, but does not guarantee a new server quota reading. Treat saved data as an observation, with an age. Calculate countdown locally; expiry alone does not establish a fresh zero-percent reading. [Status line contract](https://code.claude.com/docs/en/statusline)

For independent refresh, the unmodified CLI's `/usage` command displays plan limits for Pro, Max, Team, and Enterprise. `/status` displays account identity. A bounded PTY session can invoke these without app-owned tokens or a model prompt. This is an implementation option, not a documented machine-readable interface. Do not assume `claude -p '/usage'` invokes the interactive command. [Official commands](https://code.claude.com/docs/en/commands)

CodexBar's PTY implementation parses `Current session`, `Current week (all models)`, optional model windows, percentage text, and reset text. TUI redraws, loading screens, notices without quotas, and whether percentage means used or remaining all need handling. Use successful quota observations only; do not convert a parser failure into zero usage. [Reference implementation](https://github.com/steipete/CodexBar/blob/main/Sources/CodexBarCore/Providers/Claude/ClaudeStatusProbe.swift)

## Multiple accounts and credentials

Official CLI account isolation uses one `CLAUDE_CONFIG_DIR` per account. Each directory has its own subscription login, settings, and session history. macOS credentials use Keychain, with a directory-specific entry; fallback `.credentials.json` uses mode 0600. The default directory is `~/.claude`, but an unset configuration selector and an explicit selector for that same path can select different Keychain entries. App-owned subscription OAuth grants and isolated Console sign-ins are separate from those CLI profiles.

`ANTHROPIC_API_KEY`, `ANTHROPIC_AUTH_TOKEN`, helper credentials, profiles, and subscription login have precedence rules. Do not infer the credential's account from a configuration display label. Verify the selected token's identity separately from `/status` and local account metadata. A `claude setup-token` token is for model requests, not a general account-data credential. The app should bind each configured CLI directory to an explicit profile and keep identity verification separate from display labels. [CLI authentication](https://code.claude.com/docs/en/authentication)

`claude auth status` is an official read-only command, JSON by default. It reports `authMethod` and `configDirectory` (the latter requires v2.1.268+), with exit 0 for signed in and 1 otherwise. Recheck account identity because a user can change the account inside a configured directory. [CLI reference](https://code.claude.com/docs/en/cli-reference)

The current official rule is: “developers may not collect, store, or intermediate Claude.ai credentials or session tokens”. It says sign-in must complete through Anthropic's flow and prohibits third-party Claude.ai login. It does not explicitly exempt read-only monitoring. A user signing into the unmodified CLI is permitted. The experimental app-owned flow below does not establish an official supported third-party authentication contract. [Authentication and credential use](https://code.claude.com/docs/en/legal-and-compliance)

## Supported API reporting

For a linked Console organization, public read-only reporting endpoints include:

| GET endpoint on `https://api.anthropic.com` | Purpose |
| --- | --- |
| `/v1/organizations/usage_report/messages` | Historical tokens and tool usage |
| `/v1/organizations/cost_report` | Historical USD costs, decimal strings in cents |

Use `anthropic-version: 2023-06-01` and a supported Admin API credential: Admin key in `x-api-key`, `org:admin` OAuth, or eligible non-workspace personal/service key. Ordinary workspace keys do not work. Individual accounts cannot use the Admin API. Cost supports daily buckets, usage supports minute/hour/day buckets. Results typically lag five minutes; sustained polling once per minute is supported. These reports measure API usage, not subscription quota. [Reporting API](https://platform.claude.com/docs/en/manage-claude/usage-cost-api)

No public endpoint for the new grant's remaining balance, individual grants, or expiry was found in the official documentation index or reporting reference. Absence is a research result, not proof an internal endpoint does not exist. Plan allowance and a user-provided renewal date can be shown as configured information. Subtracting total API cost from allowance is not a reliable live credit balance because of proration, shared organizations, purchases, and expiry.

## Experimental direct subscription connection

The current connection uses an independent browser OAuth grant and direct quota reads. Existing capture profiles remain available. The change addresses a first-reading failure: importing a configuration and installing a status line cannot supply quota if no supported status-line payload is emitted. Refreshing the app can reload a capture; it cannot create one.

These contracts are observed in public client code, not supported public APIs. Source inspection establishes the request shape. A later signed-in check established grant acceptance and live quota for one account on the tested Mac; it does not establish a stable provider contract.

CodexBar uses `GET https://api.anthropic.com/api/oauth/usage` with bearer authorization, JSON Accept, and `anthropic-beta: oauth-2025-04-20`. Optional `five_hour`/`seven_day` objects contain `utilization` and ISO-8601 string `resets_at`; named model windows and `limits[]` can add scopes. A limit entry may contain `kind`, `group`, `percent`, `resets_at`, `is_active`, and `scope.model.{id,display_name}`. `extra_usage` can contain `is_enabled`, `monthly_limit`, `used_credits`, `utilization`, and `currency`; credit amounts are cents. These are extra-usage fields, not monthly API grants. `/api/oauth/profile` provides identity. The current reader also tries an optional inventory query; that is unnecessary for ordinary percentages. [Pinned CodexBar reader](https://github.com/steipete/CodexBar/blob/6e118bdb5782707bfb0dfd0453d3483e3b216cd0/Sources/CodexBarCore/Providers/Claude/ClaudeOAuth/ClaudeOAuthUsageFetcher.swift#L60-L146)

A `limits[]` entry with `kind` `weekly_scoped` and no `scope.model` is a weekly limit on part of the account. The app stores it as the window `limit_<n>_weekly_scoped` (`<n>` is its position in `limits[]`), titled `7 days`, and never treats it as the general weekly window. Named windows (`seven_day_<name>`) carry quota fields (`utilization` or `resets_at`); `seven_day_breakdown` is metadata without them and is not a window.

### Source comparison and authentication

CLIProxyAPI at `3de4e248f6bb12fc7dfafb183404f3b248578922` keeps a separate OAuth credential for each Claude account and organization. Its core does not implement a direct `/api/oauth/usage` reader. Quotio at `a8fda5cf71bc199363bfe9788791d8f92b983471` supplies the relevant reader: bearer authorization, JSON Accept, `anthropic-beta: oauth-2025-04-20`, and `User-Agent: claude-code/2.1.0`. It preserves missing windows and parses used percentages independently from monetary information. [Quotio request](https://github.com/nguyenphutrong/quotio/blob/a8fda5cf71bc199363bfe9788791d8f92b983471/apps/cli/src/providers/catalog/oauth_primary.rs#L598-L627), [window parser](https://github.com/nguyenphutrong/quotio/blob/a8fda5cf71bc199363bfe9788791d8f92b983471/apps/cli/src/providers/catalog/oauth_primary.rs#L397-L505).

The app follows CLIProxyAPI's authorization-code flow with PKCE and random state. The observed authorization URL is `https://claude.ai/oauth/authorize`; exchange and refresh use `https://platform.claude.com/v1/oauth/token`. The registered client identifier is `9d1c250a-e61b-44d9-88ed-5944d1962f5e`, with redirect `http://localhost:54545/callback`. The app listens only on loopback during sign-in, validates the returned state, and closes the listener on completion or cancellation. It does not run an inference proxy. [Provider constants](https://github.com/router-for-me/CLIProxyAPI/blob/3de4e248f6bb12fc7dfafb183404f3b248578922/internal/auth/claude/anthropic_auth.go#L23-L35), [authorization parameters](https://github.com/router-for-me/CLIProxyAPI/blob/3de4e248f6bb12fc7dfafb183404f3b248578922/internal/auth/claude/anthropic_auth.go#L323-L340), [PKCE](https://github.com/router-for-me/CLIProxyAPI/blob/3de4e248f6bb12fc7dfafb183404f3b248578922/internal/auth/claude/pkce.go#L21-L55).

The app requests only `user:profile`. Quotio checks for that scope and rejects inference-only setup tokens; CodexBar recognizes provider errors requiring it. Both reference applications request broader scopes for their own authorization flow. Their source does not prove that a fresh profile-only grant is accepted. The later app validation accepted that minimal scope and returned current quota for one account. The app must still report rejection rather than silently widen permissions; multiple live account grants and automatic renewal remain unverified. [Quotio scope check](https://github.com/nguyenphutrong/quotio/blob/a8fda5cf71bc199363bfe9788791d8f92b983471/apps/cli/src/providers/catalog/oauth_primary.rs#L308-L324), [CodexBar scope rejection](https://github.com/steipete/CodexBar/blob/6e118bdb5782707bfb0dfd0453d3483e3b216cd0/Sources/CodexBarCore/Providers/Claude/ClaudeUsageFetcher.swift#L367-L373).

Verify identity using the exact credential's `/api/oauth/profile` response: required `account.uuid`, `account.email` or `email_address`, and optional `organization.uuid`. The token response can supply `account.uuid/email_address` and `organization.uuid/name`; cross-check supplied account and organization metadata before using it to strengthen the initial binding. Email is a display label. An initial grant with no organization data binds to its known account UUID alone. Existing account/organization bindings remain valid when a later profile omits organization data. Preserve known identity and reject an explicitly conflicting account or organization. [Quotio identity parser](https://github.com/nguyenphutrong/quotio/blob/a8fda5cf71bc199363bfe9788791d8f92b983471/apps/cli/src/providers/catalog/oauth_primary.rs#L508-L556).

### Credential ownership and refresh

Store the app's own grant in its own Keychain item per profile. Refresh only that grant. Serialize refresh per account and persist an uncertainty flag before making the request: the provider can consume a refresh token even when the response or local save is lost. Store the returned access token, refresh token, expiry, and cleared flag together. An unresolved flag requires reconnecting instead of repeating the previous refresh token. Account removal or replacement during an in-flight request must prevent that result from being attached to a different profile. [Quotio refresh safeguards](https://github.com/nguyenphutrong/quotio/blob/a8fda5cf71bc199363bfe9788791d8f92b983471/apps/cli/src/accounts/service.rs#L790-L930), [CLIProxyAPI uncertainty handling](https://github.com/router-for-me/CLIProxyAPI/blob/3de4e248f6bb12fc7dfafb183404f3b248578922/internal/auth/claude/anthropic_auth.go#L122-L132).

Explicit account removal retains the exact app-owned credential until configuration persistence succeeds. If persistence fails after Keychain deletion, restore that credential; a restoration failure must report that the account remains listed but needs reconnecting. Never use this recovery path for another application's credentials.

When equivalent `limits` entries report activity for canonical quota windows, preserve that flag without replacing canonical percentages or reset times. Explicit `is_active: false` remains visible as inactive provider data; it does not determine a current quota percentage or stale reset state. Missing activity flags stay current. After a legacy capture profile has a saved independent grant, retire its app-installed wrapper with the existing command-preservation check. Keep its restoration record if settings differ but the app's command still runs, or if cleanup cannot be saved; retry on a later account load without discarding the successful grant.

Borrowed CLI credentials are a separate source. A valid existing access token can be read without rotating it, but copying its refresh token into another Keychain item does not make the grant independent. Quotio deliberately avoids refreshing native credentials because rotation can sign out the owning client. A read-only source must remain read-only and retain its account boundary. The implemented connection obtains a new grant rather than importing another client's refresh credentials. [Quotio ownership rule](https://github.com/nguyenphutrong/quotio/blob/a8fda5cf71bc199363bfe9788791d8f92b983471/apps/cli/src/providers/catalog/oauth_primary.rs#L1-L6).

The installed Claude Code 2.1.295 source distinguishes absent and explicit selectors. With both `CLAUDE_CONFIG_DIR` and `CLAUDE_SECURESTORAGE_CONFIG_DIR` absent, the production service is `Claude Code-credentials`. A nonempty selector adds the first eight lowercase SHA256 hex characters of its raw NFC-normalized value. The secure-storage selector takes precedence; an explicitly empty secure-storage selector chooses the bare service. Do not expand, trim, standardize, or resolve the selector before hashing. Explicitly selecting the default filesystem path still chooses a hashed service. Therefore a signed-out result from that explicit profile does not establish that the normal default CLI login is signed out. Custom profiles must never fall back to the default service. These rules were checked in the installed executable; they are private implementation details, not a public storage contract.

### Keychain prompts

Sign-ins live in the file-based Keychain. `LAContext` alone does not suppress its ACL dialogs, so background operations turn off `SecKeychainSetUserInteractionAllowed` for the length of the call and restore it after (`ClaudeKeychainAccess.withPromptsSuppressed(unless:)`). The setting is process-wide, so every Keychain operation, including an explicitly interactive one, takes the same lock.

### Other private web references

The web path uses `Cookie: sessionKey=…` against `https://claude.ai/api/organizations`, `/account`, and `/organizations/{id}/usage`. Optional `/organizations/{id}/overage_spend_limit` reports extra-usage spending, while `/organizations/{id}/prepaid/credits` returns `{amount,currency}` with amount in cents. This prepaid balance belongs to Claude usage credits, not the linked Console grant. Browser-cookie import and app storage of the session token carry the policy boundary above. Cloud promotional fields seen in usage responses are another credit type and must not be relabeled as API grants. [Web implementation](https://github.com/steipete/CodexBar/blob/main/Sources/CodexBarCore/Providers/Claude/ClaudeWeb/ClaudeWebAPIFetcher.swift)

## Automatic Console credits: viable undocumented route

An older public xbar client calls `GET https://platform.claude.com/api/organizations/{ConsoleOrgID}/prepaid/credits`, using the **Console** `sessionKey` cookie and dividing `amount` by 100. This is a distinct host, session, and organization from claude.ai usage credits. The older implementation does not establish how October grants are represented. [Primary implementation](https://github.com/AdrianNarloch/xbar-anthropic-credits-balance/blob/main/anthropic_balance.1m.sh)

To check the new grants, the current first-party Console billing page and its referenced public scripts were fetched anonymously on October 9. The deployed query uses that same `/prepaid/credits` path, requires `BillingView` permission, and caches for five minutes. It exposes `promo_tranches`, filters out expired tranches, and aggregates their granted and remaining integer minor-unit amounts. `last_paid_purchase_cents` marks a paid purchase. A grant can be API-only when `scope.kind` is `scoped`, `scope.applies_to` includes product `api`, and excludes `code_api` or products starting `claude_code`. [First-party billing query code](https://platform.claude.com/_next/static/chunks/2ajrzehzwss2v.js)

The deployed promotional table reads this shape:

```text
promo_tranches[]:
  id
  granted_amount_minor_units
  remaining_amount_minor_units
  currency
  expires_at
  granted_at
  scope:
    kind: scoped | unscoped
    applies_to[]:
      product
      model_family
      model_version
```

The table shows grant amounts, scope, expiry, and grant date in UTC. Read-only `/api/quirky-lollipop/organizations/{ConsoleOrgID}/link-state` (optional `?include_linkable_plans=true`) decodes `eligible`/`linked`/`ineligible`, `plan`, and `monthly_credit_usd_cents`, with optional terms and linkable organizations. The balance response also includes `amount`, `currency`, and purchased `tranches[]`. The UI separates unexpired matching-currency purchased and promotional sums; its main balance figure excludes promotions. `amount` alone is not monthly credit remaining. [First-party credit and link-state code](https://platform.claude.com/_next/static/chunks/2sbi75j44z7i1.js)

This is evidence that automatic grant balance/expiry retrieval is technically possible, not a tested account integration. It does not prove all `promo_tranches` belong to the subscription benefit; other promotional grants may coexist. Keep grants separate unless their origin is established. Browser responses must confirm the actual schema, currency, organization identity, and linkage before marking the data current.

The current first-party request wrapper includes browser credentials and device-binding refusal/retry handling. Cookie replay alone may no longer suffice. [First-party request wrapper](https://platform.claude.com/_next/static/chunks/3bqxfyy50canj.js)

Live validation requires an isolated Console browser session, provider-hosted sign-in, and confirmed organization membership. Read only the selected organization's billing responses; return monetary fields and observation time to the native app. Never purchase, redeem, link organizations, or adjust billing during monitoring. No authenticated account request was used in this research.


## Implemented Console observation

`ClaudeConsoleClient` supplies a fixed account discovery URL and UUID-validated balance URL. `ClaudeConsoleAccount` decodes `/api/account` memberships and organization identities. `ClaudeConsoleBalance` parses raw JSON supplied by the isolated browser, without cookies or tokens in UsageCore.

The decoder sums explicit unexpired purchased `tranches` per currency, keeps every unexpired promotional tranche with original and remaining amounts and exact provided dates, and excludes expired grants. Zero remaining grants remain visible. Unknown scope is labeled unavailable; known non-API scope is omitted from the API credit adapter. It does not infer a monthly grant from the plan label or aggregate balance. Missing currency and missing purchased lists stay unknown. Missing expiry does not imply perpetual validity. Malformed amounts, currencies, dates, duplicate grant IDs, HTML login responses, and unsafe organization identifiers reject the observation. Currency conversion follows integer minor units rather than binary floating point.

Eight focused fixture tests, including purchased amount consistency and duplicate-ID boundaries, passed as part of the initial implementation's final 21-test run. Browser login and live Console responses have not been verified with a user account. See [validation](../VALIDATION.md) for the tested source digest and limits.

Current first-party `/api/account` recovery uses plain same-origin fetch with browser credentials. Billing query wrappers additionally supply `anthropic-client-platform: web_console`, device identity, client build/version, and expected account context; device-binding refusal can be HTTP 503 with `session_device_binding_unavailable`. Do not invent or export those values. The browser integration should preserve its isolated provider session, verify membership and selected organization, and reject HTML or redirected login responses. Observing only the exact read-only billing responses from the official page is a possible fallback if direct same-origin fetch is refused.

### Monthly grant identification, October 11

The first-party billing query also fetches `GET /api/organizations/{ConsoleOrgID}/invoices?limit=25`, with additional pages selected by `page`. Its response contains an `invoices` array. The invoice table gives the provided `name` precedence over its generic `type` label, shows `effective_at` and `expires_at`, and formats `amount` as USD minor units. An authorized browser inspection observed an explicit `API credit (Max 20x)` name on the claimed monthly benefit's invoice. No account identifiers, amounts, or dates are retained here. [Invoice query](https://platform.claude.com/_next/static/chunks/2ajrzehzwss2v.js), [Invoice table](https://platform.claude.com/_next/static/chunks/2sbi75j44z7i1.js)

The decoder recognizes exact `API credit (Max 5x)`, `API credit (Max 20x)`, and `API credit (Team)` invoice names. Max 20x was observed in the signed-in table; the other two labels are expected counterparts for documented plans and have not been observed live. It correlates a reference to an API-supported USD promotional tranche only when original amount, grant timestamp, and expiry timestamp all match exactly and the match is unique in both directions. This is a correlation, not a provider-supplied tranche identifier. It preserves each matched tranche's actual remaining amount and expiry, including measured zero. Multiple matched tranches remain separate, which accommodates prorated grants.

Missing records, unknown names, nonmatching amounts or dates, unknown scope, conflicting currency, and ambiguous matches leave promotional grants generic. Invoice parsing currently expects numeric integer USD minor units and ISO-8601 string timestamps. The authenticated raw response has not yet been verified; source inspection and redacted fixture tests establish the implemented contract. Only the first invoice page is requested, so an absent reference cannot establish a zero monthly balance.

Optional link-state data establishes whether the selected Console organization is linked, eligible, or ineligible and can report its plan allowance. The allowance is explanatory text, never a remaining balance or original grant amount. Link-state and invoices carry the selected organization binding and cannot be attached to another organization's balance. Supplementary request or parsing failures must leave the successful purchased and promotional observation intact. Persisted credit rows require no new configuration fields.
