# Apple design guidance

Reviewed 2026-10-09 for a Swift 6 AppKit menu bar utility with a macOS 14 minimum. This is design and API research, not a claim that the running app passes accessibility or HIG review.

## Current sources

Apple's [design update index](https://developer.apple.com/design/whats-new/) lists the macOS 27 design kit on September 17, 2026, menu icon guidance on June 8, 2026, and Liquid Glass updates for buttons and toolbars on December 16, 2025. HIG pages and their Apple-hosted documentation JSON were reviewed on October 9, 2026 because several HTML pages require JavaScript.

## Recommended structure

Use one status-item-anchored panel for the frequent task: compare available account usage. Keep setup and detailed account editing in native windows. Apple's [Popovers](https://developer.apple.com/design/human-interface-guidelines/popovers) guidance calls for a small number of related tasks, a clear anchor, and a size that fits the contents. Preserve outside-click dismissal and Escape. Dismiss the account panel before opening setup windows.

Use a compact heading and primary Refresh control above the account list. Put secondary application commands together, keeping Accounts and Settings easy to discover. A native menu can reduce command crowding; this is a product choice, not a requirement to hide every action. Apple's [Toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars) guidance prioritizes frequent actions, logical groups, and restrained backgrounds. This panel does not require a full document toolbar.

For an action menu, use concise command labels and separators between related groups. Apple's current [Menus](https://developer.apple.com/design/human-interface-guidelines/menus) guidance uses icons sparingly to clarify common actions, with icons on every item in a group or none. Prefer recognizable system symbols; an uncertain icon is less helpful than a clear label.

Each account should keep a stable identity row, followed by aligned usage-window labels, numeric percentages, and reset text. Percentages should say whether they represent used or remaining quota. Use monospaced digits for values. Keep credit balances, currency, expiry, and observation dates separate from subscription percentages. Keep stale or failed states visible beside the last available reading. Put lengthy diagnostics and provenance behind a native disclosure; hiding them must not hide an authentication failure. These decisions follow the repository's account and privacy contracts.

Keep the information dense, with separators between accounts and no decorative cards, pills, gray section subtitles, continuous animation, or em dashes. Use semantic AppKit colors and ordinary content surfaces.

## Liquid Glass

Apple's [Materials](https://developer.apple.com/design/human-interface-guidelines/materials) guidance reserves Liquid Glass for important controls and navigation above content. Apply it sparingly. Account readings are content, so repeated glass account containers would weaken their hierarchy. Use the regular variant for text-bearing controls; clear is intended for visually rich media backgrounds and does not suit this numeric list.

Standard AppKit controls, menus, and presentations adopt the current system design when built with a current SDK. Apple's [Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass) specifically recommends removing custom visual effect backgrounds added to popover content. Let `NSPopover` own the presentation shell. If a custom primary control needs glass, prefer the native glass button style before adding a bespoke container. Keep the data region readable and avoid layering glass on glass.

## Verified AppKit APIs

Availability was checked in the installed macOS 27 SDK's AppKit headers. Glass container declarations share `NSGlassEffectView.h`; there is no separate `NSGlassEffectContainerView.h` in this SDK.

| API | Availability | Applicable use |
| --- | --- | --- |
| `NSButton.bezelStyle = .glass` | macOS 26+ | A primary control that floats above content; preserve native interaction and sizing. |
| `NSGlassEffectView` | macOS 26+ | A custom functional control surface when standard controls are insufficient. |
| `contentView`, `cornerRadius`, `tintColor`, `style` | macOS 26+ | Configure glass with its actual content inside; `style` supports `.regular` and `.clear`. |
| `NSGlassEffectView.effectIsInteractive` | macOS 27+ | Optional system interaction feedback; default is false. Requires its own availability check. |
| `NSGlassEffectContainerView.contentView`, `spacing` | macOS 26+ | Batch nearby custom glass views; default zero spacing batches without intentional merging. |
| `NSView.prefersCompactControlSizeMetrics` | macOS 26+ | Available for dense legacy layouts, but prefer current intrinsic control sizes unless a measured problem requires this. |
| `NSBackgroundExtensionView` | macOS 26+ | Extends imagery beneath sidebars or inspectors; unnecessary for an account statistics list. |

For a custom glass view, set `contentView`; a sibling background does not guarantee correct legibility or ordering. Apple explains this in [NSGlassEffectView](https://developer.apple.com/documentation/appkit/nsglasseffectview) and its [AppKit design session](https://developer.apple.com/videos/play/wwdc2025/310/). Nearby glass views should share an [NSGlassEffectContainerView](https://developer.apple.com/documentation/appkit/nsglasseffectcontainerview) to share rendering work and avoid sampling one another.

Guard macOS 26 APIs with `if #available(macOS 26.0, *)`, and macOS 27 interaction feedback separately. On macOS 14 and 15, use the standard native control appearance. Do not add a SwiftUI or browser implementation for ordinary controls.

## Accessibility and verification

System components adapt to Reduce Transparency, Reduce Motion, and appearance settings automatically. Custom drawing or animation must consult `NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency`, `accessibilityDisplayShouldReduceMotion`, and `accessibilityDisplayShouldIncreaseContrast`. Observe `NSWorkspace.accessibilityDisplayOptionsDidChangeNotification` through `NSWorkspace.shared.notificationCenter` when custom behavior depends on these settings. [Reduce Transparency](https://developer.apple.com/documentation/appkit/nsworkspace/accessibilitydisplayshouldreducetransparency) requires opaque backgrounds when enabled; [Reduce Motion](https://developer.apple.com/documentation/appkit/nsworkspace/accessibilitydisplayshouldreducemotion) calls for avoiding large spatial animations.

Use standard Mac control sizes and Auto Layout. Do not turn a general touch-target recommendation into a universal 44-point Mac control height. Current AppKit control metrics vary by size and can change with the OS. Add accessible names and tooltips to symbol-only controls, preserve focus during refresh, and test keyboard access to every action. Use text as well as color to communicate usage, failure, and stale data. These recommendations follow Apple's [Buttons](https://developer.apple.com/design/human-interface-guidelines/buttons) and [Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility) guidance.

Inspect the packaged app through the status item in light and dark appearance, Reduce Transparency, Increase Contrast, and Reduce Motion. Exercise an empty list, long account names, unavailable percentages, authentication failures, stale credits, scrolling, disclosure, keyboard activation, and dismissal. Record the macOS version and observed behavior in `docs/VALIDATION.md`; compilation alone does not verify any of these.
