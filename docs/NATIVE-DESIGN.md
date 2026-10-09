# Native design

AI Usage Stats is an AppKit menu bar utility. A status item opens a focused account panel; native windows handle account setup and settings. `LSUIElement` keeps ordinary use out of the Dock.

## Account panel

The populated panel is 440 × 540 points; the empty state is 440 × 250. Plain account sections use compact aligned rows with monospaced values. Percentages explicitly show capacity left. Reset countdowns sit beside each quota; credit amounts retain their currency or unit and known expiry.

Keep subscription quota, API money, Codex credit units, and earned reset counts separate. Missing values remain unavailable. Manual amounts retain a visible Manual label. Preserve old readings with their stale or sign-in state when a refresh fails.

A visible Details control exposes exact time-zone-aware dates, observation sources, grant scope, original amounts, and recovery instructions. Show one concise freshness state per account rather than repeating full timestamps beside every value. Authentication failures and stale values remain visible without expanding Details.

The default view makes the two demo accounts' main readings visible together. Scrolling accommodates more accounts and expanded details. Account sections and controls retain their identity during countdown updates; only the displayed values change. Keyboard focus on Details or its dashboard action scrolls that control into view when expansion places it below the viewport. Validate focus and scroll behavior in the running app instead of inferring it from the source.

Use semantic AppKit colors, modest text weights, and separators. No decorative cards, pills, gray subtitles above sections, or continuous animations. The empty state explains account setup and contains no fictional readings. Demo mode is explicitly labelled and used for public captures.

## Liquid Glass and system appearance

`NSPopover` owns the panel presentation. On macOS 26 and later, one native `NSGlassEffectView` with the regular style contains the functional Refresh and Actions controls. Account readings use an ordinary content surface. No tinted glass, interactive effects, repeated glass account containers, or custom blur animations are added.

On macOS 14 and 15, the command group uses standard native controls. Reduce Transparency and Increase Contrast also select the plain surface on newer systems. The group observes accessibility display-option changes. The app-only `--reduce-transparency` and `--increase-contrast` launch flags exercise this fallback without changing system settings; they do not establish that a real preference transition was tested.

The runtime target remains macOS 14+, but compilation requires a macOS 26+ SDK that declares the glass APIs, such as Xcode 26+. An availability guard preserves the older runtime path; it does not make the APIs compile with an older SDK. The redesign was built with the macOS 27 SDK and Swift 6.4. Older runtime execution remains unverified.

Use current intrinsic Mac control sizes and Auto Layout. System components supply ordinary interaction and Reduce Motion behavior; the app adds no custom spatial animation. Appearance and accessibility results belong in [VALIDATION.md](VALIDATION.md).

## Account editing

Accounts uses a sidebar for stable account selection and an Add Account menu. The editor separates the account name, relevant connection actions, and manual credit records. Connection Details keeps configuration paths and identity information available without crowding the main form. Settings keeps launch-at-login and refresh behavior in a small native window.

The Manual balance disclosure has persistent field labels for Category, Amount, Confirmed, and optional expiration. Automatic provider readings remain distinct from stored manual fallback records. Refresh must preserve an unfinished edit and the selected category. Remove Account remains separate from routine Save actions and uses the existing confirmation.

The experimental Claude Console connection uses a separate browser window for official sign-in and its isolated billing session. The monitoring interface remains native. Keep organization selection, experimental status, authentication failure, and the recovery action understandable.

## Interaction and accessibility

Keep the popover anchored to the status item, dismiss it outside or with Escape, and close it before opening account or settings windows. Test reopening after the app becomes inactive and placement near screen edges. Preserve keyboard focus and scroll position during timer and refresh updates.

Symbol-only controls need accessible names and tooltips. Details must have a readable title and expose its account and expanded state. Quotas, units, dates, unavailable readings, and errors need text equivalents. Standard controls must remain reachable by keyboard; source labels alone do not establish VoiceOver behavior.

Inspect light and dark appearances, Reduce Transparency, Increase Contrast, Reduce Motion, long names, empty/error states, disclosure, and keyboard traversal. Record which checks actually ran. A window-mode capture or successful build does not prove menu-bar behavior or measured contrast.

## Design references

The [initial critique](design/critique.md) identifies the original overflow, timestamp repetition, alignment, disclosure, editor hierarchy, and focus risks. [Apple guidance](design/apple-guidance.md) records the October 9, 2026 source review and verified SDK availability.

Primary references: [Popovers](https://developer.apple.com/design/human-interface-guidelines/popovers), [Materials](https://developer.apple.com/design/human-interface-guidelines/materials), [Menus](https://developer.apple.com/design/human-interface-guidelines/menus), [Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility), [Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass), and [NSGlassEffectView](https://developer.apple.com/documentation/appkit/nsglasseffectview).
