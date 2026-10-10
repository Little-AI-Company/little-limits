![AI Usage Stats](assets/repository-header.png)

Claude and Codex usage, reset countdowns, and API credits in your menu bar. Keep several accounts in one place without replacing your everyday CLI login.

**Native AppKit · macOS 14+ runtime · Swift 6 · No external Swift dependencies**

With no accounts, clicking the menu bar item opens a standard macOS menu with direct account setup commands. After setup, aligned account rows keep quotas and balances easy to compare. Details shows exact dates and sources; Refresh, Accounts, Settings, and Quit are directly accessible through native controls.

## What it reads

| Source | Data | Connection |
| --- | --- | --- |
| Claude subscription (experimental) | Quota remaining and reset countdowns | Separate browser sign-in for each app account, followed by direct quota reads. Uses private OAuth endpoints. |
| Claude Console (experimental) | Purchased API balances and promotional grants, including returned scope and expiry | Separate Console sign-in for each account. Uses private billing endpoints. |
| Codex | Usage windows, credit units, and earned quota resets with expiry | Automatic reads through the installed native CLI's app-server interface. |
| OpenAI API | Prepaid balance and optional expiry | Manual entry with a source date and a link to official billing. |

Subscription limits, API money, and Codex credit units stay separate. Missing readings show as unavailable; old readings retain their timestamps and stale state. Promotional grants keep their reported scope instead of all being labelled monthly credits.

## Screenshot

<a href="assets/screenshots/usage-overview.png"><img src="assets/screenshots/usage-overview.png" alt="AI Usage Stats menu bar panel showing demo Claude and Codex accounts" width="520"></a>

Demo data in the running native app.

## Build and install

The app targets macOS 14 or later. Building requires Swift 6. Verification used the macOS 27 SDK and Swift 6.4; macOS 14 runtime remains untested. Claude subscription connections use a browser sign-in. Codex connections require the installed Codex CLI.

```sh
git clone https://github.com/ParkerRex/ai-usage-stats.git
cd ai-usage-stats
scripts/package_app.sh
open "dist/AI Usage Stats.app"
```

For local installation, move `dist/AI Usage Stats.app` to Applications and open that copy. Quit an older instance before launching a new build.

Packaging produces an ad hoc signed app and ZIP for local use. Public downloads are not available yet, and the local build is not notarized. See [local packaging](docs/RELEASING.md) for version and architecture options.

## Connect accounts

On first run, click the menu bar item and choose **Add Claude Account…** or **Add Codex Account…**. The setup dialog explains the selected connection source and prerequisites. Choose **Accounts…** to manage existing accounts, then select an account in the sidebar to edit its name, connection, or manual balances.

- **Claude:** choose **Add Claude Account…**, give it a name, and complete sign-in in the browser. The app requests usage after sign-in and keeps this account separate from your everyday Claude Code login. No terminal session or model response is needed. Existing status-line capture profiles remain available; reconnect one to switch it to direct reads while preserving its name and profile identity.
- **Claude API credits:** select the Claude account, choose **Connect API Credits**, sign in to the official Console, and choose the organization. Purchased balances and promotional grants are separate from Claude subscription quota.
- **Codex:** choose **Add Account → Connect Codex** and complete its official CLI login. Each profile uses a separate app-owned `CODEX_HOME`. Finish one login before starting another.
- **Manual balances:** expand **Manual balance**, select an API credit category, and enter its amount, confirmation date, and optional expiry from the billing dashboard.

The experimental subscription connection stores its own OAuth grant in a separate Keychain item for each app account. It does not refresh, replace, or export your existing Claude Code credentials. Reconnecting an older capture profile restores its previous status line when the app's wrapper is unchanged. User replacements are preserved; incomplete cleanup retains its recovery record and shows an account-specific message. If sign-in or refresh fails, the connection shows the error and a recovery action. Provider-reported inactive quotas remain visible as inactive and do not affect current usage summaries.

The Console connection keeps its login in a separate persistent WebKit store for each app account. It does not export cookies into the saved account file. Disconnecting stops automatic reads while retaining the browser login for reconnecting. Removing a Codex profile removes monitoring data and leaves the CLI login intact.

The app only monitors usage. It does not purchase credits or send model requests as a probe. There is no telemetry.

## Current limits

Claude subscription and Console connections are experimental. Their private endpoints can change. A new usage-only grant and current subscription quota were verified for one account on the tested Mac. Multiple live accounts, automatic renewal, and live Console billing retrieval remain unverified. Returned fields depend on the account, plan, and provider version. OpenAI API prepaid balances use manual entries.

Read the [validation record](docs/VALIDATION.md), [Claude sources](docs/research/claude.md), and [Codex sources](docs/research/codex.md) for the checked behavior and data boundaries. [Product scope](docs/STRATEGY.md) and [native design](docs/NATIVE-DESIGN.md) explain the intended direction.

Contributions are welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md) and [AGENTS.md](AGENTS.md). [MIT licensed](LICENSE), copyright 2026 Parker Rex.
