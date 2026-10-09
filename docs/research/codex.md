# Codex account data

Verified 2026-10-09 against official documentation and public `openai/codex` revision `52950c592404f11cc245a83a27fb02f2c23bc0c1`. No real credentials were inspected and no account requests were made.

## Recommended integration

Use the documented [Codex app-server interface](https://learn.chatgpt.com/docs/app-server) through a Swift `Process` and newline-delimited JSON over standard input/output. Use `codex app-server --listen stdio://`, a private working directory, and a private `CODEX_HOME` per profile. Initialize before calling account methods. Account reads need no agent thread or model turn.

Connect each account through an independent browser login in a persistent app-owned `CODEX_HOME`; let that CLI instance own refresh and storage. Configure `cli_auth_credentials_store = "keyring"` in that home's `config.toml` before `codex login`. Keyring mode fails if unavailable rather than falling back to plaintext. Avoid logging into or out of the user's normal Codex home. Detect login through `account/read`, since Keychain credentials need no `auth.json` file.

The first release omits auth snapshot import and external token lifecycle management. Each account signs in independently through Codex.

Executable resolution prefers native Codex binaries in installed application bundles. It also checks native `PATH` candidates and the official npm package's platform vendor binary. Node entry-point wrappers cannot rely on Finder's limited `PATH`; select the known native binary rather than starting a login shell or parsing arbitrary wrappers. Never invoke a shell with interpolated credential text.

## Read protocol

These sanitized examples follow the [public account schemas](https://github.com/openai/codex/tree/52950c592404f11cc245a83a27fb02f2c23bc0c1/codex-rs/app-server-protocol/schema/typescript/v2). Do not include a `jsonrpc` property. Send the next request after receiving the previous result; route server requests and notifications separately from matching response IDs.

```json
{"id":1,"method":"initialize","params":{"clientInfo":{"name":"ai_usage_stats","title":"AI Usage Stats","version":"0.1.0"}}}
{"method":"initialized","params":{}}
{"id":3,"method":"account/read","params":{"refreshToken":false}}
{"id":4,"method":"account/rateLimits/read","params":{}}
```

`account/read` returns:

```json
{"id":3,"result":{"account":{"type":"chatgpt","email":"example@example.com","planType":"pro"},"requiresOpenaiAuth":true}}
```

Rate-limit response example, with invented values:

```json
{
  "id":4,
  "result":{
    "ordinaryUsageAllowed":true,
    "accountId":"<account-id>",
    "rateLimits":{
      "limitId":"codex",
      "limitName":null,
      "primary":{"usedPercent":25,"windowDurationMins":300,"resetsAt":1791540000},
      "secondary":{"usedPercent":40,"windowDurationMins":10080,"resetsAt":1791800000},
      "credits":{"hasCredits":true,"unlimited":false,"balance":"250.50"},
      "planType":"plus"
    },
    "rateLimitsByLimitId":null,
    "rateLimitResetCredits":{
      "availableCount":2,
      "credits":[{
        "id":"<reset-credit-id>",
        "resetType":"codexRateLimits",
        "status":"available",
        "grantedAt":1791000000,
        "expiresAt":1793592000,
        "title":"Rate-limit reset",
        "description":null
      }]
    }
  }
}
```

Prefer `rateLimitsByLimitId` when present; fall back to `rateLimits`. Support optional primary and secondary windows, optional durations, and optional timestamps. Label by the returned duration rather than assuming every account has five-hour and weekly limits. [Current pricing](https://learn.chatgpt.com/docs/pricing) says Pro has no five-hour limit.

`usedPercent` means used capacity. Remaining capacity is `max(0, min(100, 100 - usedPercent))`. `resetsAt`, `grantedAt`, and `expiresAt` are Unix seconds in the app-server schema. Countdowns use `max(0, resetsAt - now)`. Reaching zero triggers a refresh; it does not prove the server reset or permission to run work. The public schema explicitly forbids inferring permission from percentages or reset times.

`rateLimitResetCredits.availableCount` is authoritative; the detail list may be capped. Null or missing details mean only the count is known. An empty list means details were returned without available rows. An explicitly null expiry means the credit does not expire; an omitted expiry remains unknown. Never manufacture a date. If only details fail, retain the successfully fetched usage and count. The [account processor](https://github.com/openai/codex/blob/52950c592404f11cc245a83a27fb02f2c23bc0c1/codex-rs/app-server/src/request_processors/account_processor/rate_limit_resets.rs) follows this fallback.

Use request IDs to match responses; do not mistake server requests or notifications for responses. The first release uses CLI-managed authentication rather than `chatgptAuthTokens`, so it does not implement external token refresh. Authentication failures should request a new independent login for that profile.

## Authentication isolation

[Official authentication guidance](https://learn.chatgpt.com/docs/auth) documents `CODEX_HOME/auth.json` and OS credential storage. File storage, keyring, automatic fallback, and ephemeral storage are separate modes.

The [public auth-file schema](https://github.com/openai/codex/blob/52950c592404f11cc245a83a27fb02f2c23bc0c1/codex-rs/login/src/auth/storage.rs) includes this common ChatGPT shape:

```json
{
  "auth_mode":"chatgpt",
  "OPENAI_API_KEY":null,
  "tokens":{
    "id_token":"<id-token-jwt>",
    "access_token":"<access-token-jwt>",
    "refresh_token":"<refresh-token>",
    "account_id":"<account-id>"
  },
  "last_refresh":"2026-10-09T00:00:00Z"
}
```

There is no common OAuth `expires_at` field here. The access-token JWT's `exp` claim is an expiry hint in Unix seconds. Decoding a JWT does not verify its authenticity. The [token parser](https://github.com/openai/codex/blob/52950c592404f11cc245a83a27fb02f2c23bc0c1/codex-rs/login/src/token_data.rs) reads plan/account claims under `https://api.openai.com/auth`.

Never run managed-auth app-server with a copied refreshable file while leaving the source session active. Even a rate-limit read calls auth resolution, which may refresh proactively. The [auth manager](https://github.com/openai/codex/blob/52950c592404f11cc245a83a27fb02f2c23bc0c1/codex-rs/login/src/auth/manager.rs) persists replacement access and refresh tokens and classifies `refresh_token_reused` as a permanent failure. Its guarded reload observes its own storage, so two separate copies can diverge. Copying to a temporary home alone does not solve this.

Each app profile should have a UUID, its own CLI Keychain record, and its own app-server process/environment. Keep credential bytes out of logs, arguments, repository files, diagnostics, and UI text. Never modify the user's normal Codex auth file. Do not call logout or reset consumption during monitoring.

In managed Keychain mode the [auth storage implementation](https://github.com/openai/codex/blob/52950c592404f11cc245a83a27fb02f2c23bc0c1/codex-rs/login/src/auth/storage.rs) uses service `Codex Auth` and account key `cli|` plus the first 16 hexadecimal characters of SHA-256 of the canonical `CODEX_HOME` path. Persistent distinct homes therefore receive distinct records. Serialize browser logins because the default callback uses `localhost:1455`. Create each home with mode `0700` and its configuration with `0600`; never copy the user's normal config/auth into it.

Set the child process working directory to the private profile home. Remove inherited `CODEX_ACCESS_TOKEN`, `CODEX_API_KEY`, and `OPENAI_API_KEY` for both login and usage subprocesses. The current auth manager honors `CODEX_ACCESS_TOKEN` before persisted credentials, so `CODEX_HOME` alone does not guarantee profile isolation. Match a returned account identity to the profile's bound identity before presenting its usage.

## Credit meanings and availability

| Value | Meaning | Availability |
| --- | --- | --- |
| Window percentage and reset time | Included subscription quota | App-server rate-limit windows, when returned |
| `credits.balance` | Codex/ChatGPT credit units | Optional string; parse with `Decimal`, preserve null |
| `credits.unlimited` | Server-reported unlimited credit access | Display “Unlimited”; do not invent a numeric balance |
| Reset credit count and expiry | Earned, redeemable quota resets | `rateLimitResetCredits`, optional |
| Purchased versus promotional Codex credits | Credit origin or grant history | No split or grant expiry in `CreditsSnapshot` |
| OpenAI API spend | Billed API USD over a selected time range | Documented Costs API with Admin credential |
| OpenAI API prepaid balance and grant expirations | Remaining API billing credits | No documented balance/grant endpoint established by this research |

[Pricing documentation](https://learn.chatgpt.com/docs/pricing) distinguishes additional Codex credits from usage billed through an API key. [The student offer](https://developers.openai.com/community/students) explicitly says its Codex credits are not API credits. Do not convert the returned balance to dollars or combine it with API billing.

The documented [Costs API](https://developers.openai.com/api/reference/resources/admin/subresources/organization/subresources/usage/methods/costs) is `GET https://api.openai.com/v1/organization/costs?start_time=<unix-seconds>` with an Admin bearer key. Results contain `amount.value` and `amount.currency` inside daily `data[].results[]` buckets; paginate `has_more`/`next_page`. It measures cost, not remaining prepaid credit. [Admin APIs](https://developers.openai.com/api/docs/guides/admin-apis) require Admin keys, separate from regular API and ChatGPT credentials.

Show unavailable balance/expiry plainly and link to the user's [API billing page](https://platform.openai.com/settings/organization/billing/overview). A manually recorded balance can be supported as explicitly manual, with a recorded date; it must not be labeled live or computed as lifetime purchases minus a partial cost query.

### Browser-session investigation

Anonymous access to the official Platform billing page on October 9, 2026 reached a sign-in page or a Cloudflare challenge. A public application script URL was observed, but its contents could not be retrieved. A current prepaid-balance or grant-expiry contract was not established. The historical `/dashboard/billing/credit_grants` hint remains unverified, including its host, session mechanism, organization binding, units, and expiry fields.

OpenAI API balances therefore remain explicitly manual. A future integration must establish the current billing response in an isolated, signed-in Platform session and distinguish remaining prepaid credits from spend, purchase history, and subscription quotas. No user credentials or authenticated account requests were used in this research.

## Direct HTTP source, intentionally unused

The public [backend client](https://github.com/openai/codex/blob/52950c592404f11cc245a83a27fb02f2c23bc0c1/codex-rs/backend-client/src/client/rate_limit_resets.rs) calls `GET https://chatgpt.com/backend-api/wham/usage` and `GET https://chatgpt.com/backend-api/wham/rate-limit-reset-credits` with bearer authentication and `ChatGPT-Account-Id`. These are internal service endpoints, not the documented public API contract; the app should use app-server instead.

Its raw keys are `rate_limit.primary_window.used_percent`, `limit_window_seconds`, `reset_at`, optional `credits.balance`, `rate_limit_reset_credits.available_count`, and reset detail `granted_at`/`expires_at` RFC3339 strings. App-server converts these to the camelCase response above. This source confirms field meanings without requiring the app to own undocumented requests.

## Verification limit

Installed `codex-cli 0.160.0` compatibility was checked using `codex app-server generate-json-schema` with an empty private `CODEX_HOME` and stripped credential environment variables. It exited `0`; generated `v2/GetAccountRateLimitsResponse.json` contains `accountId`, `rateLimitsByLimitId`, reset `availableCount`, detail rows, and Unix-second `expiresAt`. No auth file, Keychain item, or account endpoint was read. Research did not verify live plan fields, credit balance, reset availability, or account-specific errors.

The initial client review confirmed camelCase quota windows and reset-credit fields. It also reproduced a launch-failure crash caused by creating a suspended `DispatchSourceTimer` before a throwing `Process.run()`: a standalone Swift reproduction exited `133` in libdispatch. Construct the timer after launch succeeds. Closing a subprocess must retain a bounded escalation/reaping path if it ignores `SIGTERM`; canceling its deadline before graceful termination can otherwise leave it alive.

Five focused subprocess tests passed in the initial implementation's final 21-test run. Synthetic `/bin/sh` fixtures exercise the read-only JSONL sequence, account-ID mismatch, private working directory, removal of synthetic ambient credential overrides, executable launch failure, timeout/reaping, and cleanup of a child that ignores `SIGTERM`. A separate native-executable test covers Finder's limited `PATH` and official npm fallback. No real credentials or account network requests were used. See [validation](../VALIDATION.md) for the source digest and native schema checks.
