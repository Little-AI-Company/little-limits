---
name: ux-heuristics
description: 'Evaluate Limits Left usability with Krug''s "Don''t Make Me Think" laws and Nielsen''s 10 heuristics, adapted for a native macOS menu bar utility. Use for a usability audit, "users are confused", navigation or labeling problems, or "is this easy to use". Covers severity ratings, the Quick Diagnostic, and heuristic conflicts. For Apple platform requirements, see apple-hig-expert. For a full screenshot-backed review, see crit.'
license: MIT
metadata:
  author: wondelai
  version: "1.6.0-ai-usage-stats"
  adapted-from: little-worker .agents/skills/ux-heuristics (2026-10-14)
---

# UX Heuristics Framework

Practical usability principles for evaluating and improving user interfaces. Users don't read, they scan; they don't make optimal choices, they satisfice; they don't figure out how things work, they muddle through.

## Core Principle

**"Don't Make Me Think"** — every page should be self-evident. If something requires thinking, it's a usability problem. Users have limited patience and cognitive bandwidth, so design for the scanning, satisficing, and muddling-through behavior described above.

## Native macOS adaptation

The source framework and its references were written for websites. Translate before applying:

| Web term | Limits Left equivalent |
| --- | --- |
| Site / page | The status menu, the Limits Left window, and its current sidebar page (Home, an account, App Settings, Platform) |
| Permanent navigation | The window sidebar and the status menu command group |
| Search | Not a product feature. Score the "find it" row as: can someone locate a named account or reading without recall? |
| Back button | Sidebar reselection, the Platform pane Back button, Escape for menus, popovers, and sheets |
| Hover-only information | Tooltips and the calendar popover. Every tooltip fact must also be reachable by keyboard and VoiceOver |
| 44 px tap target | Not applicable. Use the macOS sizes in [apple-hig-expert](../apple-hig-expert/references/accessibility.md) |
| Loading spinner | Refresh state text and timestamps. This app avoids continuous animation |

The primary task is a glance: "how much Claude and Codex quota do I have left, on which account, and when does it reset?" The secondary tasks are adding an account, recovering from a failed reading, and checking API credits. Judge every finding by its effect on those tasks.

## Scoring

Use the Quick Diagnostic as a diagnostic, not a target score. Start at 10 and subtract 2 per failed row whose worst finding is severity 3 or 4, otherwise subtract 1. Report the failed rows and the findings behind them. Prioritize observed task impact and acceptance evidence; do not invent fixes merely to reach 10/10.

For a full review, hand findings to the [crit register](../crit/references/register-schema.md). Preserve stable finding IDs across rounds; Crit owns the register format.

## Krug's Usability Principles

Laws 1-3 are Krug's Three Laws of Usability; #4, the Trunk Test, is his navigation orientation check.

### 1. Don't Make Me Think

**Core concept:** Every question mark that pops into a user's head adds cognitive load and distracts from the task.

**Why it works:** Users are on a mission — they don't want to puzzle over labels or decode clever marketing language. The less thinking required, the more likely they complete the task.

**Key insights:**
- Clever names lose to clear names every time
- Marketing-speak creates friction; plain language removes it
- Unfamiliar categories force users to stop and interpret
- Ambiguous links and buttons cause hesitation

**Product applications:**

| Context | Application | Example |
|---------|-------------|---------|
| **Navigation labels** | Self-evident names | "Get directions" not "Calculate route to destination" |
| **CTAs** | Action verbs users understand | "Sign in" not "Access your account portal" |
| **Error states** | Tell users what to do next | "Check your email format" not "Validation error" |

**Copy patterns:**
- Action-oriented buttons: verb + noun ("Create account", "Download report")
- Avoid jargon: "Save" not "Persist", "Remove" not "Disassociate"
- If a label needs explanation, simplify the label

**Ethical boundary:** Clarity should serve users — never use plain language as a veneer to hide unfavorable terms.

See: [references/krug-principles.md](references/krug-principles.md) when you need the full Krug method — scanning/satisficing/muddling psychology, the goodwill reservoir, homepage and tagline guidance, and the $0 usability-testing protocol (how many users, the test script).

### 2. It Doesn't Matter How Many Clicks

**Core concept:** The myth says "users leave after 3 clicks." In reality users don't mind clicks if each one is painless, obvious, and confidence-building.

**Why it works:** Cognitive effort per click matters more than click count. Users abandon when they lose confidence, not when they run out of patience for clicking.

**Key insights:**
- Each click should be painless, obvious, and confidence-building
- Three mindless clicks beat one click that requires deliberation
- Shallow nav with clear labels beats deep nav with vague ones

**Product applications:**

| Context | Application | Example |
|---------|-------------|---------|
| **Checkout flows** | Make each step obvious | Clear step indicators with descriptive labels |
| **Settings** | Clear categories over flat lists | "Account > Security > Change password" (3 confident clicks) |
| **Onboarding** | Small, clear steps | Wizard with one clear action per step |

**Copy patterns:**
- Progress indicators: "Step 2 of 4: Shipping details"
- Confirmations at each step: "Great, your email is verified. Now let's set up your profile."
- Clear link text: "View all running shoes" not "Click here"

**Ethical boundary:** Never use extra steps to bury cancellation flows — every click should move users toward their goal, not away from it.

### 3. Get Rid of Half the Words

**Core concept:** Remove half the words on each page, then half of what's left. Brevity makes useful content prominent and respects the user's time.

**Key insights:**
- Happy-talk ("Welcome to our website!") wastes space
- Instructions nobody reads should be removed
- "Please" and "Kindly" and polite fluff add noise
- Shorter pages mean less scrolling and faster scanning

**Product applications:**

| Context | Application | Example |
|---------|-------------|---------|
| **Landing pages** | Cut welcome copy, lead with value | Remove "Welcome to..." paragraphs |
| **Error messages** | State problem and fix, nothing more | "Password too short (min 8 chars)" |
| **Empty states** | Action-oriented, minimal | "No results. Try a different search." |

**Copy patterns:**
- Before: "Please kindly note that you will need to enter your password in order to proceed to the next step." → After: "Enter your password to continue."
- Before: "We've received your message and will get back to you as soon as possible." → After: "Message sent. We'll reply within 24 hours."

**Ethical boundary:** Brevity must not omit critical information — concise disclosures for pricing, terms, and data usage are a user right.

### 4. The Trunk Test

**Core concept:** Drop a user on any random page (like being released from a car trunk at a random spot) — they should instantly answer six orientation questions: What site is this? What page? What are the major sections? What are my options here? Where am I in the hierarchy? Where's search?

**Why it works:** Good navigation gives constant orientation. Users who can't tell where they are feel lost and leave.

Apply it as the navigation check: page titles must match the link the user clicked, a "you are here" indicator (highlighted nav item, bold breadcrumb) must be present, and section headings must orient ("Your Account > Billing" not just "Settings").

**Ethical boundary:** Navigation labels must honestly represent site structure — never use misleading labels to funnel users into marketing pages.

See: [references/krug-principles.md](references/krug-principles.md) when running the Trunk Test or designing navigation — it maps each of the six questions to the page element that answers it, plus breadcrumb and permanent-navigation rules.

## Nielsen's 10 Usability Heuristics

### 1. Visibility of System Status
Keep users informed through timely feedback. Every action needs acknowledgment — progress bars for uploads, confirmations for submissions, skeleton screens for loading. Silent failures destroy trust. Copy pattern: "Saving..." → "Saved".

### 2. Match Between System and Real World
Speak users' language: "Sign in" not "Authenticate", "Search" not "Query." Follow real-world metaphors (trash bin, shopping cart) and natural ordering (street → city → state → zip).

### 3. User Control and Freedom
Provide clear "emergency exits." Undo beats "Are you sure?" dialogs — users click through confirmations without reading. Every flow needs cancel/exit, and back buttons must never break.

### 4. Consistency and Standards
Same words, styles, and behaviors mean the same thing throughout. Internal consistency (your app) plus external consistency (platform conventions: logo top-left, search top-right). One term per concept — "Projects" everywhere, never mixed with "Workspaces."

### 5. Error Prevention
Prevent problems before they occur: constrained inputs (date pickers over text fields), autocomplete, sensible defaults, "unsaved changes" warnings. Slips (accidental wrong action) and mistakes (wrong intention) need different prevention.

### 6. Recognition Rather Than Recall
Minimize memory load — show options, don't require memorization. Breadcrumbs, recent searches, pre-filled fields, dropdowns with decoded values. Working memory holds ~7 items; recognition is far easier than recall.

### 7. Flexibility and Efficiency of Use
Serve both novices and experts: keyboard shortcuts, bulk actions, saved searches, command palettes (Cmd+K). Progressive disclosure keeps it simple for beginners while experts access full power.

### 8. Aesthetic and Minimalist Design
Every element must earn its place — when everything screams for attention, nothing stands out. Show what matters now, hide what doesn't. One primary CTA per page.

### 9. Help Users Recognize, Diagnose, and Recover from Errors
Error messages need three parts: what happened, why, and how to fix it. Plain language ("Connection failed" not "ECONNREFUSED"), specific ("Password must be 8+ characters" not "Invalid"), never blame the user, preserve their input.

### 10. Help and Documentation
Help should be searchable, task-focused ("How to..." not technical reference), and contextual (tooltips, inline hints, guided tours).

See: [references/nielsen-heuristics.md](references/nielsen-heuristics.md) when auditing against a specific heuristic — it expands each of the 10 into good-implementation / common-violation / severity tables with copy patterns and ethical boundaries.

## Severity Rating Scale

Rate each issue found in an audit:

| Severity | Rating | Description | Priority |
|----------|--------|-------------|----------|
| **0** | Not a problem | Disagreement, not usability issue | Ignore |
| **1** | Cosmetic | Minor annoyance, low impact | Fix if time |
| **2** | Minor | Causes delay or frustration | Schedule fix |
| **3** | Major | Significant task failure | Fix soon |
| **4** | Catastrophic | Prevents task completion | Fix immediately |

Weigh three factors: **frequency** (how often it occurs), **impact** (how severe when it occurs), **persistence** (one-time or ongoing).

See: [references/audit-template.md](references/audit-template.md) when running a full heuristic evaluation — a structured per-screen template that captures issues, severity, and recommended fixes in a consistent format.

## Common Mistakes

| Mistake | Why It Fails | Fix |
|---------|-------------|------|
| **Mystery meat navigation** | Icons without labels force guessing | Add text labels alongside icons |
| **Too many choices** | Decision paralysis slows users | Reduce to 7 plus/minus 2 items |
| **No "you are here" indicator** | Users feel lost in the hierarchy | Highlight current section in nav and breadcrumbs |
| **No inline validation** | Submit, error, scroll cycle frustrates | Validate on blur with specific messages |
| **Unclear required fields** | Users confused about what's mandatory | Mark optional fields, not required |
| **Wall of text** | Nobody reads dense paragraphs | Break up with headings, bullets, whitespace |
| **Jargon in labels** | Users don't speak your internal language | User-test all labels, use plain language |
| **No loading indicators** | Users think the system is broken | Show spinner, progress bar, or skeleton screen |
| **Tiny tap targets** | Mobile users misclick constantly | Minimum 44x44 px touch targets |
| **Hover-only information** | Mobile and keyboard users miss it | Don't hide critical info behind hover |
| **No undo** | Users afraid to take any action | Provide undo for all non-destructive actions |
| **Poor error messages** | "Invalid input" tells users nothing | Explain what's wrong and how to fix it |
| **Low contrast text** | Unreadable for many users | WCAG AA minimum (4.5:1 contrast) |
| **Inconsistent nav location** | Users can't find navigation | Fixed position, same place on every page |
| **Broken back button** | Violates the browser contract | Never hijack or break browser history |

For accessibility (contrast, keyboard, VoiceOver, focus, display preferences), use the native guidance in [apple-hig-expert](../apple-hig-expert/references/accessibility.md).

## Quick Diagnostic

| Question | If No | Action |
|----------|-------|--------|
| Can I tell which surface and which account this is immediately? | Users are lost | Window title, selected sidebar row, account heading |
| Is the main action obvious? | Users don't know what to do | Visual hierarchy, single primary CTA |
| Is the navigation clear? | Users can't find their way | Apply the Trunk Test, add "you are here" indicators |
| Can I find a named account or reading without recall? | Goal-driven users are blocked | Stable order, identity in every heading, filter where lists grow |
| Does the system show what's happening? | Users lose trust and re-click | Loading states, confirmations, progress |
| Are error messages helpful? | Users get stuck | Plain language with a specific fix |
| Can users undo or go back? | Users are afraid to act | Undo, cancel, and back options everywhere |
| Does it work without hover, by keyboard and VoiceOver? | Keyboard and assistive users excluded | Keyboard paths and accessible text for every tooltip fact |
| Are all interactive elements labeled? | Users guess at icons | Text labels or descriptive tooltips |
| Does anything make me stop and think "huh?" | Cognitive load too high | Simplify — if it needs explanation, redesign it |

## Heuristic Conflicts

Heuristics sometimes contradict each other. When they do:
- **Simplicity vs. Flexibility**: use progressive disclosure
- **Consistency vs. Context**: consistent patterns, contextual prominence
- **Efficiency vs. Error Prevention**: prefer undo over confirmation dialogs
- **Discoverability vs. Minimalism**: primary actions visible, secondary hidden

See: [references/heuristic-conflicts.md](references/heuristic-conflicts.md) when two heuristics pull in opposite directions and the four rules above don't settle it — resolution frameworks with worked trade-off examples.

## Dark Patterns Recognition

Dark patterns violate heuristics deliberately to manipulate users: forced continuity (hard to cancel), roach motel (easy in, hard out), confirmshaming (guilt-based options), hidden costs (surprise fees at checkout).

This app is read-only monitoring and must not sell, upsell, or nudge plan changes. Treat any such pattern as a severity 3 finding.

## When to Use Each Method

| Method | When | Time | Findings |
|--------|------|------|----------|
| Heuristic evaluation | Before user testing | 1-2 hours | Major violations |
| User testing | After heuristic fixes | 2-4 hours | Real behavior |
| A/B testing | When optimizing | Days-weeks | Statistical validation |
| Analytics review | Ongoing | 30 min | Patterns and problems |

## Further Reading

Based on usability principles developed by Steve Krug and Jakob Nielsen:

- [*"Don't Make Me Think, Revisited"*](https://www.amazon.com/Dont-Make-Think-Revisited-Usability/dp/0321965515?tag=wondelai00-20) by Steve Krug
- [*"Rocket Surgery Made Easy"*](https://www.amazon.com/Rocket-Surgery-Made-Easy-Yourself/dp/0321657292?tag=wondelai00-20) by Steve Krug (DIY usability testing)
- [*"10 Usability Heuristics for User Interface Design"*](https://www.nngroup.com/articles/ten-usability-heuristics/) by Jakob Nielsen (Nielsen Norman Group)

## About the Author

**Steve Krug** is a usability consultant whose *Don't Make Me Think* (2000, revised 2014) is the most widely read book on web usability. He demonstrated that usability testing doesn't require a lab or large budget — just watching a few real users try to accomplish tasks.

**Jakob Nielsen, PhD** is co-founder of the Nielsen Norman Group and author of the 10 Usability Heuristics (1994), still the most-used framework for heuristic evaluation worldwide. *The New York Times* called him "the guru of Web page usability."
