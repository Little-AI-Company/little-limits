# Changelog

What changed in each public release of Limits Left, newest first. The same entries are on [limitsleft.com/changelog](https://limitsleft.com/changelog/). Downloads are on [GitHub Releases](https://github.com/ParkerRex/limits-left/releases). Versions before 0.2.1 were released as AI Usage Stats.

To add a release, follow the [changelog skill](.agents/skills/changelog/SKILL.md).

## 0.2.1 (2026-10-16)

The app is now called Limits Left. This release also brings a new icon, a more accurate menu bar number, and clearer words across the app.

### New

- **App icon:** A new icon, Enamel. **Settings** has an **App icon** choice of Enamel or Night. Night shows in the Dock and app switcher while a Limits Left window is open, and in **About Limits Left**. Finder keeps Enamel.
- **App menu:** **About Limits Left**, **Hide Limits Left**, **Hide Others**, and **Show All** are in the app menu, and **Zoom** is in the **Window** menu.

### Improved

- **Home:** **Account Usage** now comes right after **Weekly Totals**, so your accounts show without scrolling. The forecast and the reset calendar follow.
- **Home:** Tab reaches the forecast, the account table, and the calendar events.
- **Home:** **Previous**, **Next**, **Today**, **Month**, and **2 Weeks** scroll the reset calendar into view.
- **Forecast:** Labels say **Usage rate**, **Weekly total reaches 0%**, and **Updated**. Claude and Codex labels line up, and the chart lines are easier to see, also with Increase Contrast.
- **Models:** Model names are easy to read, such as Opus 5.5 instead of the name in the log. Models with few requests stay full strength and say "(under 5,000)", and the bars are easier to see.
- **Old readings:** The **Updated** column on Home shows when an account was last read, or says **Stale** or **Unavailable**. An old earned reset count reads "Last known 2 available" instead of "Last known 2".
- **Stale accounts:** The account page says to choose **Refresh Account** to read the account again, and every status line names **Refresh Account**.

### Fixed

- **Menu bar number:** It now shows the lowest of your accounts' 5-hour and weekly limits. A limit for one model no longer lowers it. That limit still has its own row in the menu.
- **Account page:** **Earned resets** is one line, and each credit expiry shows once in **Connection Details**.

### Changed

- **Name:** AI Usage Stats is now Limits Left. Your accounts, sign-ins, settings, and usage history stay. With Homebrew, `brew upgrade` moves you to the new name.

## 0.2.0 (2026-10-15)

A private usage history that stays on your Mac. Released as AI Usage Stats.

### New

- **Weekly totals:** Home and the menu show how much weekly limit is left across all your Claude accounts, and across all your Codex accounts. You also see the next reset and what it gives back, whether an account is ahead of pace, and when an account at its limit can be used again.
- **Forecast:** Home shows how fast your weekly total is going down, when it reaches zero, and a chart of recent use with a projection over the next 1 or 7 days.
- **Models:** A new page shows how each model works in your own Claude Code and Codex sessions, such as output speed, steps per turn, and the commands it runs.
- **Accounts:** Sort accounts by most remaining or soonest usable. Refresh one account from its page with Shift-Command-R.

### Improved

- **Privacy:** The history reads Claude Code and Codex logs on your Mac, including older compressed Codex logs, and keeps only counts, lengths, and categories. It never keeps prompts, replies, command text, file contents, or folder names, and nothing leaves your Mac.
- **First launch:** The app reads your existing logs in the background. This takes from about half a minute to a couple of minutes, and you can use the app meanwhile.

## 0.1.0 (2026-10-14)

The first public release. Released as AI Usage Stats.

### New

- **Menu bar:** The remaining limit for Claude and Codex. Choose **Show in Menu Bar** to give the accounts you use their own numbers.
- **Status menu:** Every account's 5-hour, weekly, and model limits, with reset times. **Reconnect…** shows when an account needs to sign in again.
- **Home:** An account table and a reset calendar. Drag accounts in the sidebar to change their order.
- **Accounts:** Add Claude accounts by signing in in your browser. Add Codex accounts by signing in in Terminal, or use the Codex sign-in already on your Mac.
- **API credits:** See Claude API credits with a separate Claude Platform sign-in. This is experimental.
- **Read only:** The app never buys credits, changes plans, or sends AI requests to check your usage.
