# Native design

AI Usage Stats is an AppKit menu bar utility. A status item opens one standard native menu for first run and connected accounts. One native management window handles account setup, Claude Platform connections, and App Settings. Subscription sign-in uses an attached sheet and the external browser. `LSUIElement` keeps menu-only use out of the Dock. Opening the management window promotes the app to regular activation so Command-Tab can return to it after another app takes focus. Minimized windows remain open; closing the window returns the app to accessory activation after any attached sheet ends. Command-W closes the window, Command-M minimizes it, and reopening restores the same window.

## Vocabulary

One name per concept in every surface: status item, status menu, sidebar, Home, calendar, popover, account page, alerts, tooltips, and accessibility text. Adopted after the [2026-10-14 crit](design/crits/2026-10-14-baseline.md) (HOME-08).

| Concept | Use | Do not use |
| --- | --- | --- |
| Subscription quota percentage | Remaining: `51% left` (`InterfaceFormatting.remaining`) with `Low` or `Limit reached` when applicable | `used`, `remaining` as a value suffix |
| Usage windows | `5-hour`, `Weekly`, model-scoped `Weekly · Fable 5` | `5 hours`, `7 days`, `Model limit`, `Fable 5 weekly`, `Weekly (Fable 5)` |
| Unknown reset | `Reset time unknown` | `Reset unknown`, `Time unavailable` |
| Codex reset grants | `Earned resets`, value `2 available`, timing `Next expires in 12d` | `Quota resets`, `Quota reset` |
| Failed authentication | State `Sign-in required`, command `Reconnect…` | `Subscription access required`, `Sign-in is required before…` |
| Old reading | Value prefix `Last known`, state `Stale · last read 11:09` | `Usage stale`, `Stale usage reading`, `Stale historical reading` |
| No reading | `Unavailable`, with the reason in the tooltip | `Usage unavailable.` without a reason |
| Provider does not report a value | `Not supported` in secondary label color | bold `Not supported`, `Not applicable` |
| Claude API billing | `API Credits`; the sign-in site is `Claude Platform` | `Claude Console`, `API billing`, `Platform sign-in`, `Manage Claude Platform…` |
| Refresh every account | `Refresh All` (Command-R) | `Refresh`, `Check Usage` when the action refreshes every account |
| Open the window | `Open AI Usage Stats` | `Manage Accounts…` |
| App settings | Command `Settings…`, page title `Settings` | `App Settings`, a gear-only entry point |
| Add an account | `Add Claude Account…`, `Add Codex Account…`; keep the verb through the flow | `Connect Claude…` then `Sign In…` |

Page headings use title case. Error text says what happened and what to do next.

## First run

Use an actual `NSMenu` with direct Add Claude Account… and Add Codex Account… commands, followed by Manage Accounts… and Quit. AppKit owns its appearance, keyboard selection, sizing, and dismissal. Explain Claude browser sign-in and Codex CLI sign-in in the corresponding setup dialog, rather than a technical paragraph in the menu.

Do not show a title banner, disabled Refresh control, generic Actions dropdown, empty dashboard, or refresh footer. A load failure has its own error and retry commands; it is not treated as a fresh account list. After removing the last account, the next ordinary click returns to this menu.

## Account usage menu

Use the actual status item's `NSMenu` for populated accounts. Each account begins with `NSMenuItem.sectionHeader(title:)`, available on macOS 14, displaying a 16-point provider logo, provider name, and verified email, such as `Claude • personal@example.invalid`. This native gray section label is an explicit exception to the general restriction on gray subtitles. When email is absent, show the saved account name and put `Email unavailable` in its tooltip and Connection Details. Missing email does not imply an unverified account identity. Never present an alias or account identifier as a verified email. Preserve stored account order and separate each account with a standard menu separator.

Readings are ordinary, noninteractive menu items with semantic label text. Use no custom menu views, progress bars, cards, pills, dashboard controls, or custom backgrounds. Indent data beneath each heading. Native attributed titles use shared tab stops to align compact labels, semibold values, and secondary timing: `5-hour   12% used   Resets in 1h 1m`. Weekly and model-scoped readings use the same percentage meaning. Keep unknown expiry in tooltip and Connection Details instead of repeating it on every unavailable credit row. Retain known expiry, manual status, financial units, and at most one concise usage state plus one Console attention row. The compact status-item summary retains its existing remaining-capacity meaning. It shows only provider template logos and percentages, with no written provider names; full names and quota meaning remain in tooltip and accessibility text.

Keep subscription quota, API money, Codex credit units, and earned reset counts separate. Preserve unknown values, inactive quotas, reset countdowns, expiry, original grant amounts, manual labels, stale readings, authentication failures, and recovery instructions. Freshness and provider details remain available in native item tooltips and the existing Accounts window's Connection Details. Exact dates include the time zone. One Manage Accounts… command opens the single existing Accounts window; Refresh and Quit remain standard status-menu commands. The standard app-menu Settings… command and Command-comma open App Settings inside Manage Accounts.

Build the menu's current readings and countdowns immediately before AppKit begins tracking. Keep that menu unchanged while open, including during provider refresh and account changes, so keyboard selection remains stable. The next opening applies current model data. There is no countdown repaint timer. AppKit supplies keyboard selection, scrolling for long menus, Escape, and outside-click dismissal.

## Compact status preview

Use one native status-item button with a composed template image: 14-point provider logos, 12-point monospaced percentages, a 3-point icon/value gap, and a 9-point gap between providers. The button title is empty when accounts exist. Unknown quota remains `?`, stale or sign-in state retains `!`, and no-account fallback remains `AI`.

Aggregate the lowest remaining quota across current windows and all accounts for each provider, preserving the existing calculation. A typed summary of provider, remaining percentage, and stale state is compared with the displayed summary before drawing; unchanged refresh results do not recreate the image. Draw 1x and 2x bitmap representations once per changed summary. The final image is a template so the native button supplies light, dark, and selected tint. The same shared ProviderIcons loader supplies account headings and the preview.

## Provider logo resources

The Claude asterisk and OpenAI knot used for Codex come from the local opencode UI assets, with their source SVGs preserved alongside offline-rendered transparent PNGs. AppKit displays the PNG alpha silhouettes as template menu images. On macOS 27+, request `preferredImageVisibility = .visible` because AppKit otherwise typically hides menu-item images. This availability check leaves the macOS 14 deployment target intact.

SwiftPM includes the ProviderIcons resource directory. Packaging copies its generated resource bundle into the app's Contents/Resources. Loading first discovers that bundle through Bundle.main; Bundle.module is a lazy fallback for SwiftPM development. The bundle includes the opencode MIT license, copyright, original source paths, and source commit in NOTICE.txt. Packaging and runtime need no SVG renderer. See [RELEASING.md](RELEASING.md).

## System controls and appearance

`NSMenu` owns status-item presentation and tracking in every account state. Use standard AppKit controls and system appearance for the single Accounts window and its App Settings screen. System components handle Reduce Transparency, Increase Contrast, and Reduce Motion. The app adds no custom spatial animation.

The app-only `--increase-contrast` launch flag selects a high-contrast appearance without changing system settings; it does not establish that a real preference transition was tested. `--dark-appearance` requests the app's dark appearance for validation. The runtime target remains macOS 14+. Building requires Swift 6; the current verification environment uses the macOS 27 SDK and Swift 6.4. Older runtime execution remains unverified.

Appearance and accessibility results belong in [VALIDATION.md](VALIDATION.md).

## Account editing

The AI Usage Stats window uses a sidebar for stable account selection, with native plus and minus buttons below the scrollable list and App Settings beside them. Plus opens an attached provider-choice sheet; minus removes the selected account only after confirmation. Minus is disabled on Home, App Settings, and empty or busy states. The sidebar context menu and Delete key retain the same UUID-bound confirmation. Ordinary email addresses fit on one line; longer identities can use two lines while full identity remains in tooltips and accessibility text.

The scrollable account page leads with aligned Usage and Credits rows, prominent values, and short reset/expiry timing. Refresh, Reconnect, and Billing are direct buttons. Connect or Manage API Credits and connected-only Disconnect API Credits sit beside Credits. The Account actions dropdown is removed. Inline, selectable Connection Details retain account identity, verified email, reported plan, configuration path where applicable, observation time, exact reset/expiry dates, source descriptions, and errors. Explicit Allow Keychain Access stays in this section for subscription OAuth profiles; Review Access scrolls there. This action reads the existing saved credential and may show a system permission dialog; it does not reconnect automatically. API-credit disconnection retains the isolated Platform sign-in and saved manual balances. Manual balance remains collapsed until needed.

The bottom settings control opens native Startup and Usage rows, moves keyboard focus to Launch at login, and remains selected until another page is selected. The window title follows Home, the selected account, or App Settings. Returning to the same account preserves unfinished manual edits. Reading startup state does not register or unregister a login item. Subscription confirmation and ordinary dialogs remain attached sheets; OAuth callback and account guards remain unchanged.

Sidebar rows show the lowest remaining current quota only when every active window has a finite percentage and a known, current observation time. Green means more than 20% remains; orange means 10% through 20%; red means less than 10%. Numeric text and the static native capacity indicator share the semantic color. Zero remains a measured red zero. Unknown, inactive, stale, unavailable, and sign-in states have neutral text and no capacity indicator. Expired resets and readings at least five minutes old are stale. Credits do not affect quota color. Accessible labels and tooltips identify the account, limiting window, and last observation; unchanged display values do not reload the table.

The management window has one size range across Home, account details, App Settings, and Platform: 1020 × 640 point minimum, 1280 × 780 point default, and 1680 × 1040 point maximum content size. Initial placement fits the available screen. Navigation preserves the current frame and user resize; content scrolls when needed. Native Zoom uses the shared caps.

The Manual balance disclosure has persistent field labels for Category, Amount, Confirmed, and optional expiration. Automatic provider readings remain distinct from stored manual fallback records. Refresh must preserve an unfinished edit and the selected category. Remove Account remains separate from routine Save actions and uses the existing confirmation.

Credit formatting uses the same unknown-amount rule in the menu, account readings, and details: an available grant without a reported amount shows Unknown. This does not change measured zero, Unlimited, failure labels, or units. Claude’s unavailable API balances and grants explain the separate Platform connection; OpenAI API balances explain manual entry.

The experimental Claude Platform connection uses an embedded browser pane inside Manage Accounts for official sign-in and its isolated billing session. The monitoring interface remains native. Keep organization selection, experimental status, authentication failure, and the recovery action understandable. Connect API Credits… makes monthly-grant setup explicit and names platform.claude.com authentication as separate from Claude subscription sign-in at claude.ai. The compact native wrapper has Back, one account context and instruction, and one primary Continue/Connect/Refresh Credits action; choosing a different saved organization explicitly says Switch Organization. The labeled organization picker appears only after organizations are discovered; Connect requires a valid selection. Reload Sign-in, on-demand details, and connected-only Disconnect live in a Connection menu. Short status messages retain full errors/dates in tooltips and details. The per-profile Platform controller is embedded in the existing detail area with Back, which preserves the selected account and unfinished edits. An interactive read may return to the overview only while its pane is visible, supplemental fetches succeeded, and the discovered nonempty Platform email matches the verified Claude email after trimming and case-insensitive comparison; other/unknown logins keep their explicit context and Back; background refresh never navigates the user or reveals the browser. Provider navigation does not probe or connect automatically. The same window keeps its current size for the browser and on Back. Closing it pauses/parks the visible browser without changing its persistent WebKit session. App Settings is available from the sidebar footer; an empty account list shows account setup instead of opening settings automatically. No separate Settings or Platform window is retained. When the provider reports an eligible plan as Not linked, the existing billing command opens Claude Settings > Billing for human linking or claiming; the app performs only reads. The same isolated Platform session reads selected-organization balance, plan linkage, and invoices, preserving invoice query parameters. Supplemental failures preserve good purchased balances and a visibly stale, dated last verified monthly reading. Unrelated promotions cannot suppress a monthly placeholder or saved manual fallback.

## Home reset calendar

Home is the first sidebar row and the default view when Manage Accounts opens the window. Dock reopening preserves the active screen. All pages share the window size range described above; selecting Home does not resize the window.

Use a Monday-first two-week or month calendar, native date navigation, account filtering, and Refresh All. Each event shows a provider icon, remaining percentage, short account identity, quota scope, and local reset time. Short identities are distinct within a provider; full identity and exact time remain in accessibility text and the anchored native popover. Events come only from current, active windows with finite measured percentages and future reset dates. Readings at least five minutes old, missing or future observation times, failed authentication, unavailable snapshots, or a passed current quota reset exclude that account from the calendar. A missing percentage excludes that window while other known windows remain visible.

Hover, click, or Return opens the account popover; Escape and outside clicks dismiss it. View Account uses the existing UUID-bound sidebar route. The native account table has resizable, scrolling columns and preserves saved order, selection, and scroll position across unchanged readings. Account filtering applies to the table and calendar. Model and named additional meters retain their scope. Plan names are reported metadata; Max and Pro do not imply a 20x multiplier.

Keep current, historical, unknown, inactive, unavailable, and sign-in states explicit. Measured zero alone says Limit reached. Earned reset count uses its own observation time; a known earned reset expiry passing after that observation makes the count historical without subtracting from it. Earned reset expiry stays in the table and popover, separate from calendar quota resets and monetary balances. Empty and load-failure views show their setup or retry message without calendar controls. Demo fixtures disable provider refresh, reconnection, and account mutation.

`--show-home` and `--show-accounts` open Home. `--demo-home` supplies four fictional accounts; `--demo-reading-states` adds sign-in failure, stale, and missing readings. Either fixture flag enables demo isolation without an additional `--demo`. Existing empty/load-error flags take precedence. These flags support local verification and do not establish live-provider behavior.

## Interaction and accessibility

Test ordinary status-item clicks for populated and first-run menus, including arrow-key/Return command selection, Escape, outside-click dismissal, provider-dialog cancellation, and account loading failure. Test reopening after the app becomes inactive, placement near screen edges, long/missing emails, and preservation of the selected command while a refresh completes.

Quotas, units, dates, unavailable readings, and errors have native text equivalents. Menu items retain exact values and dates in tooltips. Inline Connection Details in Accounts supplies extended readings and recovery diagnostics through selectable native text and direct controls for keyboard access. Source text alone does not establish VoiceOver behavior.

Inspect light and dark appearances, Reduce Transparency, Increase Contrast, Reduce Motion, empty/error states, and keyboard navigation. Record which checks actually ran. `--show-menu` opens the real status menu; `--show-panel` remains an alias. `--show-home` and `--show-accounts` open Home in the existing Accounts window for inspection. The obsolete custom `--show-window` overview host is removed. A window capture or successful build does not prove menu-bar behavior or measured contrast.

## Design references

The [initial critique](design/critique.md) identifies the original overflow, timestamp repetition, alignment, disclosure, editor hierarchy, and focus risks. The [first-run flyout review](design/flyout-review.md) records why the subsequent empty dashboard was replaced with a native menu. [Apple guidance](design/apple-guidance.md) records the October 13, 2026 HIG review and the October 9 SDK availability checks. The repository's [Apple HIG skill](../.agents/skills/apple-hig-expert/SKILL.md) provides focused native design and accessibility review guidance.

Primary references: [The menu bar](https://developer.apple.com/design/human-interface-guidelines/the-menu-bar), [Materials](https://developer.apple.com/design/human-interface-guidelines/materials), [Menus](https://developer.apple.com/design/human-interface-guidelines/menus), [Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility), and [Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass).
