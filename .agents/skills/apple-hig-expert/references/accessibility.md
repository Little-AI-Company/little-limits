# Native accessibility review

Applicable Apple sources reviewed October 13, 2026. Use AppKit accessibility semantics, native inspection, and real task execution. CSS pixels, ARIA, browser zoom, and DOM capture are not evidence for this app's ordinary controls.

## Names, values, and navigation

Check the accessible name, role, value, state, and actions of each affected control. Standard AppKit controls provide much of this behavior, but labels still need verification. A tooltip is not an accessible name. Give symbol-only controls meaningful names and expose the composed status image as provider names, remaining quota, and stale or sign-in status.

Test complete tasks with VoiceOver when relevant. Confirm reading order groups account identity with its own usage and credits. Unknown data, manual provenance, monetary units, quota meaning, and failures need accurate spoken equivalents. Do not infer useful speech from attributed menu text alone.

Test keyboard selection, Return activation, Escape dismissal, tab order, visible focus, and restoration after a sheet or detail dialog closes. Preserve command selection during refresh and unfinished fields during account redraws. Exact dates and diagnostics must be reachable through Connection Details because pointer tooltips alone cannot provide keyboard access. Check Full Keyboard Access or other assistive input where it affects the task, and mark unavailable checks untested.

## Native control sizes

The HIG Accessibility page's platform table gives macOS a **28 by 28 point default control size** and a **20 by 20 point minimum**. Its custom typography table gives macOS a **13-point default** and **10-point minimum**. These recommendations are not instructions to flatten AppKit's component-specific metrics or make all text equally small.

The Buttons page also gives a general 44 by 44 point hit-region recommendation. Record both context and source: use the macOS-specific guidance for a Mac review instead of applying the general value as a universal menu-row or button height. Prefer native sizing; inspect actual hit regions, spacing, focus, and operability when a custom or unusually small control needs review. A 14-point logo or 12-point status percentage is not itself a control hit region. Convert screenshot pixels to points only with a known capture scale.

## Legibility and display settings

Use the current HIG Accessibility contrast table and Accessibility Inspector guidance for actual font size and weight. Apple lists 4.5:1 for text up to 17 points, and 3:1 for 18-point or bold text. Record the effective foreground, background, appearance, font, and measurement method. Do not treat source color names, a screenshot impression, or an unmeasured translucent background as a contrast pass. If using WCAG directly for an additional criterion, name its rule and scope separately.

Convey quota, unknown values, stale readings, and failures through text or symbols as well as color. Inspect light and dark appearance, selected and disabled states, Increase Contrast, Reduce Transparency, and Reduce Motion. For custom behavior, verify `NSWorkspace` accessibility preferences and updates through `accessibilityDisplayOptionsDidChangeNotification` on `NSWorkspace.shared.notificationCenter`.

Apple recommends supporting larger text, ideally enlargement to at least 200 percent. Do not assume iOS Dynamic Type APIs apply to this AppKit implementation. Record the available native text or magnification behavior and any layout limits; a system font alone does not prove enlargement support. Test long text and accessible reading paths without silently shrinking important information.

Keep the interface predictable and concise. Avoid time-limited messages, continuous motion, or hiding account failures automatically. Keep the relevant recovery action nearby and preserve context through sign-in, failure, and return navigation.

Sources: [Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility), [VoiceOver](https://developer.apple.com/design/human-interface-guidelines/voiceover), [Buttons](https://developer.apple.com/design/human-interface-guidelines/buttons), [Typography](https://developer.apple.com/design/human-interface-guidelines/typography), [Motion](https://developer.apple.com/design/human-interface-guidelines/motion).
