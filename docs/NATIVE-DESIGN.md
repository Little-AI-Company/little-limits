# Native design

AI Usage Stats is an AppKit menu bar utility. A status item opens a standard native menu when no accounts are connected, and a focused account overview once accounts exist. Native windows handle account setup and settings. `LSUIElement` keeps ordinary use out of the Dock.

## First run

Use an actual `NSMenu` with direct Add Claude Account… and Add Codex Account… commands, followed by Accounts…, Settings…, and Quit. AppKit owns its appearance, keyboard selection, sizing, and dismissal. Explain Claude browser sign-in and Codex CLI sign-in in the corresponding setup dialog, rather than a technical paragraph in the menu.

Do not show a title banner, disabled Refresh control, generic Actions dropdown, empty dashboard, or refresh footer. A load failure has its own error and retry commands; it is not treated as a fresh account list. After removing the last account, the next ordinary click returns to this menu.

## Account panel

The populated overview is 440 points wide and fits its content up to a maximum height of 540 points. Direct native Refresh, Accounts…, Settings…, and Quit controls precede compact aligned account rows. Percentages explicitly show capacity left. Reset countdowns sit beside each quota; credit amounts retain their currency or unit and known expiry.

Keep subscription quota, API money, Codex credit units, and earned reset counts separate. Missing values remain unavailable. Manual amounts retain a visible Manual label. Preserve old readings with their stale or sign-in state when a refresh fails.

A visible Details control exposes exact time-zone-aware dates, observation sources, grant scope, original amounts, and recovery instructions. Show one concise freshness state per account rather than repeating full timestamps beside every value. Authentication failures and stale values remain visible without expanding Details.

Main readings use compact rows. Demo accounts exercise distinct Claude emails, a long email, and an unavailable email alongside Codex readings. Scrolling accommodates additional accounts and expanded details. Account sections and controls retain their identity during countdown updates; only the displayed values change. Keyboard focus on Details or its dashboard action scrolls that control into view when expansion places it below the viewport. Validate focus and scroll behavior in the running app instead of inferring it from the source.

Use semantic AppKit colors, modest text weights, and separators. No decorative cards, pills, gray subtitles above sections, or continuous animations. Demo mode is explicitly labelled and used for public captures.

## System controls and appearance

`NSMenu` owns the first-run command surface, and `NSPopover` owns the populated overview's presentation and material. Use standard AppKit controls and their system appearance. Do not add custom glass control enclosures, popover backgrounds, gradients, or blur animations.

System components handle Reduce Transparency, Increase Contrast, and Reduce Motion. The app-only `--increase-contrast` launch flag selects a high-contrast appearance without changing system settings; it does not establish that a real preference transition was tested.

The runtime target remains macOS 14+. Building requires Swift 6; the current verification environment uses the macOS 27 SDK and Swift 6.4. Older runtime execution remains unverified.

Use current intrinsic Mac control sizes and Auto Layout. System components supply ordinary interaction and Reduce Motion behavior; the app adds no custom spatial animation. Appearance and accessibility results belong in [VALIDATION.md](VALIDATION.md).

## Account editing

Accounts uses a sidebar for stable account selection and an Add Account menu. The editor separates the account name, relevant connection actions, and manual credit records. Connection Details keeps configuration paths and identity information available without crowding the main form. Settings keeps launch-at-login and refresh behavior in a small native window.

The Manual balance disclosure has persistent field labels for Category, Amount, Confirmed, and optional expiration. Automatic provider readings remain distinct from stored manual fallback records. Refresh must preserve an unfinished edit and the selected category. Remove Account remains separate from routine Save actions and uses the existing confirmation.

The experimental Claude Console connection uses a separate browser window for official sign-in and its isolated billing session. The monitoring interface remains native. Keep organization selection, experimental status, authentication failure, and the recovery action understandable.

## Interaction and accessibility

Test first-run commands through an ordinary status-item click, including arrow-key/Return selection, Escape and outside-click dismissal, provider-dialog cancellation, and account loading failure. Keep the populated popover anchored to the status item and close it before opening account or settings windows. Test reopening after the app becomes inactive and placement near screen edges. Preserve keyboard focus and scroll position during timer and refresh updates.

Symbol-only controls need accessible names and tooltips. Details must have a readable title and expose its account and expanded state. Quotas, units, dates, unavailable readings, and errors need text equivalents. Standard controls must remain reachable by keyboard; source labels alone do not establish VoiceOver behavior.

Inspect light and dark appearances, Reduce Transparency, Increase Contrast, Reduce Motion, long names, empty/error states, disclosure, and keyboard traversal. Record which checks actually ran. `--show-panel` follows the same state selection as ordinary use. `--show-window` is explicitly labeled a validation window; it is not evidence of the real first-run surface. A window-mode capture or successful build does not prove menu-bar behavior or measured contrast.

## Design references

The [initial critique](design/critique.md) identifies the original overflow, timestamp repetition, alignment, disclosure, editor hierarchy, and focus risks. The [first-run flyout review](design/flyout-review.md) records why the subsequent empty dashboard was replaced with a native menu. [Apple guidance](design/apple-guidance.md) records the October 9, 2026 source review and verified SDK availability.

Primary references: [Popovers](https://developer.apple.com/design/human-interface-guidelines/popovers), [Materials](https://developer.apple.com/design/human-interface-guidelines/materials), [Menus](https://developer.apple.com/design/human-interface-guidelines/menus), [Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility), and [Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass).
