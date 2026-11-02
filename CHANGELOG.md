# Changelog

What changed in each public release of Little Limits, newest first. The same entries are on [limitsleft.com/changelog](https://limitsleft.com/changelog/). Downloads are on [GitHub Releases](https://github.com/Little-AI-Company/little-limits/releases). Version 0.2.1 was released as Limits Left, and earlier versions as AI Usage Stats.

To add a release, follow the [changelog skill](.agents/skills/changelog/SKILL.md).

## 0.4.0 (2026-11-02)

Little Limits can now tell you when to use your quota, not only how much is left: state words for each limit, a morning digest, nudges before weekly quota resets unused, and a warning before an account runs out. Claude Code, Codex and Claude Desktop can also ask Little Limits where each account stands.

### New

- **Limits:** Each limit says **Use soon** when a lot of weekly quota would reset unused, **Low** at 20% or less, **Almost out** at 5% or less, and **Limit reached** at 0%. Red now starts at **Almost out** instead of at 20%. Close to a reset, **Low** and **Almost out** stay plain, because the quota comes back soon.
- **Morning digest:** Turn on **Send a morning digest at** in **Settings** to get one notification each morning with what is left on every account and which to use first. You choose the time and whether it comes **On weekdays only**. If your Mac is asleep, it comes when the Mac wakes, up to 4 hours late.
- **Nudges:** Turn on **Nudge when at least** in **Settings** and choose 15%, 25% or 40%. Little Limits then tells you when about that much of an account's week would reset unused at your pace. Nudges come at most twice for each weekly limit and four times a week, and never at night.
- **Burn list:** In **Settings**, add tasks worth spending leftover quota on, for Claude, Codex or either. A nudge shows the top task for that account and has a **Copy Task** button. Little Limits never runs a task.
- **Run-out warning:** Turn on **Warn when an account will run out and another has room** in **Settings** to hear before an account runs out, with the account of the same kind to switch to.
- **Menu bar number:** In **Show in Menu Bar**, choose **Use First per Provider** to see the weekly percent left on the account to use first, with the reason in its tooltip. Turn on **Color Low Numbers** to show low numbers in orange, nearly empty ones in red, and quota to use soon in your accent color.
- **AI assistants:** **Settings** shows the command to add Little Limits to Claude Code, Codex or Claude Desktop, each with a **Copy** button. They can then ask what is left on each account, when it resets, and which account to use now. A `status` command prints the same table in Terminal. Answers come from the last refresh and say how old they are.

### Improved

- **Models:** The page opens in about a second instead of ten or more. While it loads, the Little Limits character watches its gauge needle.
- **Home:** The menu, Home and the account list show the same percentage left, with one decimal when it matters. A small amount left no longer shows as 0% in the menu. A weekly limit that is already reached no longer shows a pace line.
- **Tooltips:** Tooltips describe quota as what is left, never as what is used.
- **App icon:** The Paper and Night icons are redrawn to match the rest of the little family: the same gauge character, with soft inked lines, a black hoodie and dot eyes.

### Fixed

- **Readings:** A reading that is exactly five minutes old shows as out of date in the menu bar, the menu and the account page alike.
- **Codex history:** Codex usage history from before you added an account is kept even when one of its logs could not be read the first time.
- **API credits:** The monthly Claude API grant says when the current grant expires.

## 0.3.0 (2026-10-31)

The app is now called Little Limits, with new Paper and Night icons. Reset times on Home also fit on a 12-hour clock.

### Fixed

- **Home:** Reset times in the account table fit at the smallest window width on a 12-hour clock, such as "Today 6:22 PM". A reset that already happened says "Reset passed".

### Changed

- **Name:** Limits Left is now Little Limits. Your accounts, sign-ins, settings, and usage history stay. With Homebrew, `brew update && brew upgrade --cask` moves you to the new name. If you installed by hand, quit **Limits Left** and move it to the Trash after you install Little Limits.
- **App icon:** New Paper and Night icons. Paper replaces Enamel. **Settings** has an **App icon** choice of Paper or Night, and if you chose Enamel before, you now have Paper.

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

- **Name:** AI Usage Stats is now Limits Left. Your accounts, sign-ins, settings, and usage history stay. With Homebrew, `brew update && brew upgrade --cask` moves you to the new name. If you installed by hand, quit **AI Usage Stats** and move it to the Trash after you install Limits Left.

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
