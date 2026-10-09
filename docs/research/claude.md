# Claude data sources

Verified October 9, 2026. Official pages were opened, not inferred from search snippets. No user credentials were read or account requests made.

## Monthly API credits

Anthropic announced monthly API credits on October 7, 2026, alongside Haiku 5.5. The official tiers are **Max 5x: $100 USD** and **Max 20x: $200 USD**. There is no Max 10x tier in the current sources. Team receives $20 per Standard seat and $100 per Premium seat, pooled up to $500. [Announcement](https://www.anthropic.com/claude-haiku-5-5)

Eligibility: an active eligible plan in good standing, at least seven days after joining; web, iOS, and Android subscriptions qualify. Free, Pro, and Enterprise do not. Max requires the subscriber; Team requires Owner or Primary Owner. The destination Console organization requires Owner, Admin, or Billing access. Claim in claude.ai Billing by linking one Console organization. Each organization can receive credits from one plan; changing the link requires support. No Console payment card is required. The rollout can take several days.

Credits cover direct Claude API, Playground, Managed Agents, and Agent SDK. Personally running `claude -p` with an API key from the linked Console organization qualifies as Agent SDK usage. Subscription-authenticated `-p` instead consumes subscription quota. Interactive Code, Claude-app extra usage, cloud-provider API calls, and Code runs launched by an IDE, Desktop, or GitHub Action are excluded. June's Agent SDK credit offer is a different, unavailable offer. [Eligibility and coverage](https://support.claude.com/en/articles/17154008-monthly-api-credits-for-max-and-team-plans)

Credits arrive shortly after subscription payment, expire at billing-cycle end, and do not roll over. Annual plans receive monthly grants and expiry. Included credits are consumed before purchased credits. Every workspace/key in the linked organization shares them. Auto-reload watches the purchased balance, even when included credits remain. Cancellation, an ineligible downgrade, or refund stops new grants; existing grants remain until expiry. Upgrading 5x to 20x grants prorated credits immediately, except Google Play may deliver them by next renewal. Team seat changes affect the next billing month's pool.

API spend caps reset on the first of the calendar month, independently of credit renewal. Credits do not enlarge subscription limits. Console Settings > Billing > Promotional credits shows amounts and expiry. When exhausted, purchased credits continue usage; otherwise API calls stop until more credit arrives. Invoiced organizations continue normal billing. [Lifecycle](https://platform.claude.com/docs/en/about-claude/api-credits-for-subscribers)

Purchased Console credits are a separate balance, usable for API, Playground, and Claude Code. They expire one year after purchase and are non-refundable. [Purchased credit billing](https://support.claude.com/en/articles/8977456-how-do-i-pay-for-my-claude-api-usage)

Claude **usage credits**, formerly called extra usage, are another separate balance: pay-as-you-go continuation after subscription limits. They are not the new included API grants. Session limits reset every five hours; weekly limits also apply. [Claude usage credits](https://support.claude.com/en/articles/12429409-manage-usage-credits-for-paid-claude-plans)

## Supported subscription observation

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

The status line runs locally without consuming tokens. It updates after assistant messages and certain local events. `refreshInterval` re-runs the script, but does not guarantee a new server quota reading. Treat saved data as an observation, with an age. Calculate countdown locally; expiry alone does not establish a fresh zero-percent reading. [Status line contract](https://code.claude.com/docs/en/statusline)

For independent refresh, the unmodified CLI's `/usage` command displays plan limits for Pro, Max, Team, and Enterprise. `/status` displays account identity. A bounded PTY session can invoke these without app-owned tokens or a model prompt. This is an implementation option, not a documented machine-readable interface. Do not assume `claude -p '/usage'` invokes the interactive command. [Official commands](https://code.claude.com/docs/en/commands)

CodexBar's PTY implementation parses `Current session`, `Current week (all models)`, optional model windows, percentage text, and reset text. TUI redraws, loading screens, notices without quotas, and whether percentage means used or remaining all need handling. Use successful quota observations only; do not convert a parser failure into zero usage. [Reference implementation](https://github.com/steipete/CodexBar/blob/main/Sources/CodexBarCore/Providers/Claude/ClaudeStatusProbe.swift)

## Multiple accounts and credentials

Official CLI account isolation uses one `CLAUDE_CONFIG_DIR` per account. Each directory has its own subscription login, settings, and session history. macOS credentials use Keychain, with a directory-specific entry; fallback `.credentials.json` uses mode 0600. The default directory is `~/.claude`. Two keyless Console sign-ins are an exception: their profiles live outside the CLI configuration directory.

`ANTHROPIC_API_KEY`, `ANTHROPIC_AUTH_TOKEN`, helper credentials, profiles, and subscription login have precedence rules. Do not infer active account/billing from a saved subscription token alone. `/status` identifies the active source. A `claude setup-token` token is for model requests, not a general account-data credential. The app should bind each configured CLI directory to an explicit profile and keep identity verification separate from display labels. [CLI authentication](https://code.claude.com/docs/en/authentication)

`claude auth status` is an official read-only command, JSON by default. It reports `authMethod` and `configDirectory` (the latter requires v2.1.268+), with exit 0 for signed in and 1 otherwise. Recheck account identity because a user can change the account inside a configured directory. [CLI reference](https://code.claude.com/docs/en/cli-reference)

The current official rule is: “developers may not collect, store, or intermediate Claude.ai credentials or session tokens”. It says sign-in must complete through Anthropic's flow and prohibits third-party Claude.ai login. It does not explicitly exempt read-only monitoring. A user signing into the unmodified CLI is permitted. Prefer quota-only local observations and CLI-owned authentication. [Authentication and credential use](https://code.claude.com/docs/en/legal-and-compliance)

## Supported API reporting

For a linked Console organization, public read-only reporting endpoints include:

| GET endpoint on `https://api.anthropic.com` | Purpose |
| --- | --- |
| `/v1/organizations/usage_report/messages` | Historical tokens and tool usage |
| `/v1/organizations/cost_report` | Historical USD costs, decimal strings in cents |

Use `anthropic-version: 2023-06-01` and a supported Admin API credential: Admin key in `x-api-key`, `org:admin` OAuth, or eligible non-workspace personal/service key. Ordinary workspace keys do not work. Individual accounts cannot use the Admin API. Cost supports daily buckets, usage supports minute/hour/day buckets. Results typically lag five minutes; sustained polling once per minute is supported. These reports measure API usage, not subscription quota. [Reporting API](https://platform.claude.com/docs/en/manage-claude/usage-cost-api)

No public endpoint for the new grant's remaining balance, individual grants, or expiry was found in the official documentation index or reporting reference. Absence is a research result, not proof an internal endpoint does not exist. Plan allowance and a user-provided renewal date can be shown as configured information. Subtracting total API cost from allowance is not a reliable live credit balance because of proration, shared organizations, purchases, and expiry.

## Undocumented HTTP references

These contracts are observed in public client code, not supported public APIs. They should not be the default authentication design.

CodexBar uses `GET https://api.anthropic.com/api/oauth/usage` with bearer authorization, JSON Accept, and `anthropic-beta: oauth-2025-04-20`. Optional `five_hour`/`seven_day` objects contain `utilization` and ISO-8601 string `resets_at`; named model windows and `limits[]` can add scopes. A limit entry may contain `kind`, `group`, `percent`, `resets_at`, `is_active`, and `scope.model.{id,display_name}`. `extra_usage` can contain `is_enabled`, `monthly_limit`, `used_credits`, `utilization`, and `currency`; credit amounts are cents. These are extra-usage fields, not monthly API grants. `/api/oauth/profile` provides identity. The source also uses a reset-grant opt-in query; that is unnecessary for ordinary percentages. [OAuth implementation](https://github.com/steipete/CodexBar/blob/main/Sources/CodexBarCore/Providers/Claude/ClaudeOAuth/ClaudeOAuthUsageFetcher.swift)

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
