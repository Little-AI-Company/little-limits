# Native visual design

Applicable Apple sources reviewed October 13, 2026. Apply these decisions alongside `docs/NATIVE-DESIGN.md`; distinguish local product choices from Apple's guidance.

## Menus and icons

Apple recommends a menu for a menu bar extra unless its functionality is too complex. Keep this app's actual `NSMenu`, native account section headers, standard separators, and concise commands. Use ellipses when a command requires further input. Reserve icons for clear purposes and apply a consistent treatment within each command group. Provider identity logos in account headings are distinct from command icons.

The status item uses template imagery so AppKit supplies light, dark, and selected tint. Keep its width restrained because menu bar space is limited. Retain full provider names and percentage meaning in its tooltip and accessibility text. The menu bar glyph size is not the interactive hit region.

## Type, color, and layout

- Use `NSFont` system metrics and standard AppKit control sizes. Use monospaced digits where changing numbers need stable alignment, rather than making the entire interface monospaced.
- Prefer semantic AppKit colors such as label, secondary label, separator, and window background colors. Check light, dark, selected, disabled, and increased-contrast states against actual rendered backgrounds.
- Align labels, values, and reset or expiry timing. Maintain the distinction between used quota in menu rows and remaining quota in the status item.
- Use intrinsic sizing and Auto Layout rather than importing a web grid or assuming a universal 8-point grid. Check long emails, missing identity, localized text, and available window sizes.
- Apple advises keeping critical information and controls away from the bottom of a Mac window that may extend offscreen. The sidebar footer is the existing local navigation choice; verify access through standard menu commands and keyboard paths instead of moving controls without task evidence.
- Preserve the project's dense interface, no decorative cards or pills, no gray subtitles beyond native account section headers, no em dashes, and no continuous animations.

## Liquid Glass

Start with standard AppKit controls, menus, and sheets. On current systems they adopt system appearance with the appropriate SDK. Let AppKit supply materials and interaction feedback; avoid overlaying custom backgrounds that defeat native appearance.

Apple reserves Liquid Glass for functional navigation and controls above content. Usage readings are content, so repeated glass account containers are inappropriate. For a justified custom functional surface, prefer the regular variant; clear is for visually rich backgrounds. Group related custom effects with AppKit's native container only when custom glass is actually needed. Do not add glass solely to modernize a numeric list.

Preserve macOS 14 support. Check the installed SDK declarations and current Apple API documentation before adding a newer API; guard its exact availability and keep ordinary native fallback behavior. `docs/design/apple-guidance.md` records prior SDK checks separately from HIG source review.

Inspect real Reduce Transparency, Increase Contrast, Reduce Motion, and appearance changes. Standard components adapting automatically does not prove custom drawing or actual preference transitions were tested. A performance claim requires comparable Release measurements under the repository's verification rules.

Sources: [The menu bar](https://developer.apple.com/design/human-interface-guidelines/the-menu-bar), [Menus](https://developer.apple.com/design/human-interface-guidelines/menus), [Typography](https://developer.apple.com/design/human-interface-guidelines/typography), [Color](https://developer.apple.com/design/human-interface-guidelines/color), [Layout](https://developer.apple.com/design/human-interface-guidelines/layout), [Materials](https://developer.apple.com/design/human-interface-guidelines/materials), [Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass).
