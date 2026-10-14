# AI Usage Stats project profile

Use this profile for the native macOS app. `AGENTS.md` defines architecture and verification; `docs/STRATEGY.md` defines scope; `docs/NATIVE-DESIGN.md` defines the current interface. `docs/design/apple-guidance.md` records source research, and `docs/VALIDATION.md` records observed behavior and remaining limits.

## Surfaces and ownership

| Surface | Source | Review focus |
| --- | --- | --- |
| Status item and native menu | `Sources/AIUsageStats/ApplicationDelegate.swift`, `UsageMenu.swift`, `StatusItemImage.swift` | Compact summary, stable menu tracking, commands, dismissal, keyboard selection |
| Accounts window and sidebar | `Sources/AIUsageStats/AccountsWindowController.swift`, `AccountSidebarCellView.swift`, `AccountReadingView.swift` | Stable selection, aligned readings, disclosure, manual edits, window lifecycle |
| App Settings | `Sources/AIUsageStats/GeneralSettingsViewController.swift` | Startup and refresh settings, Command-comma, return to account context |
| Subscription sign-in | `Sources/AIUsageStats/ClaudeSignInWindowController.swift` | Attached sheet, external browser, cancellation, clear account identity |
| Experimental Platform credits | `Sources/AIUsageStats/ClaudePlatformViewController.swift` | Isolated browser, account and organization context, Back, failure and recovery |
| Account data and refresh | `Sources/UsageCore/`, `Sources/AIUsageStats/ApplicationModel.swift` | Accurate units, identity, freshness, unknown values, account separation |

Paths in this table are repository-relative; adjacent filenames share the preceding directory.

## Status menu

The status item opens an actual `NSMenu` in first-run, populated, and account-load failure states. Keep readings as native noninteractive items, account headings as native section headers, and commands as ordinary menu items. The native gray account section header is the documented exception to the restriction on gray subtitles. Do not substitute a dashboard, custom menu views, progress bars, cards, or a popover for the current menu.

Keep stored account order. Build readings and reset countdowns before tracking, then preserve the open menu even if refresh completes or an account changes. The next opening applies new data. AppKit owns sizing, scrolling, selection, Escape, and outside-click dismissal. Test those behaviors rather than reimplementing them.

The compact template image uses provider logos and remaining-capacity percentages. Expanded usage rows say **used**. Preserve that distinction in text, tooltips, and accessible values. Unknown quota uses `?`; stale or sign-in state uses `!`. Recreate the status image only when its displayed summary changes. The system may hide a menu bar extra when space is constrained; report discoverability concerns without expanding this utility into a new Dock or window product.

## Accounts and settings

Use the single existing management window with its stable account sidebar. App Settings and the Platform pane share that window. Preserve selection and unfinished manual edits across refresh and navigation. Command-comma opens settings, Command-W closes, Command-M minimizes, and reopening restores the existing window. Verify Command-Tab return while the management window is open and accessory activation after it closes, including attached sheets.

Use direct native account buttons and inline scrollable Connection Details. Preserve the window frame across Home, accounts, App Settings, and Platform. Add/remove use plus/minus buttons below the account list; retain the removal confirmation. App Settings is a screen inside the management window; do not impose the sizing and window-button rules for a separate dedicated Settings window on it without recognizing this local choice.

## Readings, identity, and privacy

- Use verified provider email where available; saved names are fallbacks, not verified identity. Missing email remains explicit in details.
- Keep subscription percentages and reset times separate from API currency, promotional grants, Codex credit units, and earned reset counts.
- Preserve zero, unknown, unsupported, inactive, expired, stale, and failed states. A refresh must not make manual data newly confirmed or hide a failed reading behind an old value.
- Keep exact dates, time zone, provenance, and recovery diagnostics available through keyboard-accessible inline Connection Details; tooltips alone are insufficient.
- Platform authentication is separate from Claude subscription sign-in. Keep the intended account, discovered login, selected organization, experimental status, and recovery action understandable. Background refresh must not navigate or reveal the browser.
- Monitoring stays read-only. Review must not buy credits, change plans, consume a model request, alter a CLI login, or expose credentials.

## Verification paths

Follow `AGENTS.md` for required checks. For changed native UI, package with `scripts/package_app.sh`, quit the previous development instance, and launch the packaged app. Use existing demo fixtures where suitable:

```sh
open -n "dist/AI Usage Stats.app" --args --demo --show-menu
open -n "dist/AI Usage Stats.app" --args --demo --show-accounts --dark-appearance
```

These are separate inspection sessions, not commands to start simultaneous instances. `--show-panel` aliases the menu; it does not display a custom panel. `--increase-contrast` selects an app appearance and does not prove a real system-preference transition. Demo fixtures do not prove live sign-in or provider behavior.

Exercise the affected task with pointer and keyboard plus relevant empty, unavailable, stale, and failure states. Inspect long or missing identities, long menus, window resizing, focus restoration, and refresh stability when they affect the change. Record VoiceOver and real accessibility preference checks separately. A local launch does not prove macOS 14, Intel, trusted distribution, or notarization.
