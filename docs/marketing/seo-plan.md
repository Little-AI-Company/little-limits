# SEO plan for the product website

Status: plan, written 2026-10-16. The product is being renamed from AI Usage Stats to **Limits Left**, with the subtitle "Usage limits for Claude and Codex, in your Mac's menu bar", at **limitsleft.com**. The site in `website/` is not deployed yet. The repository stays at github.com/ParkerRex/ai-usage-stats. See [Name and domain](#name-and-domain).

This plan follows the vendored skills `seo-plan`, `seo-cluster`, `seo-sxo`, and `seo-geo` (see [`.agents/skills/CLAUDE-SEO-VENDOR.md`](../../.agents/skills/CLAUDE-SEO-VENDOR.md)). It had no paid keyword data. Search demand comes from autocomplete and forum research on 2026-10-16 and from web searches on the same day. There are no search volumes, so priorities below are judgments, not measurements. Replace them with Search Console data once the site is live.

## Goal

Get people who search for Claude or Codex limits, or for a way to watch those limits on a Mac, to find the site, trust it, and install the app. The app is free, so success is installs and GitHub stars, not revenue.

Keep the site the way it is: static HTML, no scripts, no trackers. Every SEO change below fits inside that.

## Audience

| Person | What they search | What they need from us |
| --- | --- | --- |
| Heavy Claude Pro or Max user who hit a limit | "claude limit reset time", "claude weekly limit reset", "claude 5 hour limit" | When the limit comes back, in plain words, with a link to Anthropic's own page |
| Developer who uses both Claude Code and Codex | "claude codex usage monitor", "codex usage limits", "how to check claude code usage left" | One place to see both, and how each tool reports usage |
| Person with more than one account (work and personal, or two Max plans) | "claude usage tracker mac", "multiple claude accounts usage" | Every account side by side, without switching logins |
| Terminal tool user (ccusage, Claude Code Usage Monitor) | "ccusage alternative", "codexbar alternatives" | A fair comparison: what each tool measures and when to use which |
| Privacy-minded developer | "claude usage menu bar mac" plus reading the privacy section | Exactly what the app reads and stores, and proof it sends nothing |
| Someone asking an AI assistant | "what's a good app to track Claude usage on Mac" | Clear, quotable facts about the app that an answer engine can cite |

## Search intents

| Intent | Example queries | Page type that fits (from the results we saw) |
| --- | --- | --- |
| Informational: how limits work | claude usage limits, claude 5 hour limit, codex usage limits | Explainer article with a dated table and official links |
| Informational: when it resets | claude limit reset time, claude weekly limit reset, codex limit reset | Short answer first, then how to find your own reset time |
| Informational: how to check | how to check claude code usage left | Step-by-step guide |
| Commercial: find a tool | claude usage tracker mac, claude usage menu bar mac, claude usage monitor mac, codex usage tracker mac, claude codex usage monitor, claude code usage dashboard | Product page, GitHub repository, guide that ends in the app |
| Commercial: compare | ccusage alternative, codexbar alternatives | Comparison page with a table |
| Navigational (not targeted) | ccusage, codexbar, claude login | None. Do not try to rank for other products' names on their own |

What the results looked like on 2026-10-16:

- Limit and reset queries return Anthropic and OpenAI help pages, news about limit changes, GitHub issues, and many guides written by other tracking apps (usagebar.com, vibeisland.app, sessionwatcher.com, inventivehq.com). The guides are the pages we compete with. Most do not date their facts and some disagree with each other. A dated page that links the official source is the gap.
- "claude usage menu bar mac" returns GitHub repositories and Mac App Store listings, not websites. The GitHub README is a landing page for these queries, so its first lines, description, and topics matter as much as the home page.
- "ccusage alternative" returns AlternativeTo and comparison pages written by other tools (SessionWatcher, a VS Code extension, Tokenade). One of them ranks its own product without saying the author made it. A comparison that discloses who wrote it and stays fair is the gap.

## Keyword clusters

Four hubs. Each query has one owning page, so pages do not compete with each other. Slugs never contain the product name, so a later rename would not change any URL.

### Hub 1: Claude limits (informational)

| Page | Status | Owns these queries |
| --- | --- | --- |
| `/articles/claude-usage-limits-explained` (hub) | Being written | claude usage limits, claude 5 hour limit, claude code usage limits, claude pro and max limits |
| `/articles/claude-limit-reset-time` | Being written | claude limit reset time, claude weekly limit reset, when does claude reset |
| `/articles/check-claude-code-usage-left` | Backlog | how to check claude code usage left, claude code /usage, claude usage settings page |

### Hub 2: Codex limits (informational)

| Page | Status | Owns these queries |
| --- | --- | --- |
| `/articles/codex-usage-limits` (hub) | Being written | codex usage limits, codex 5 hour limit, codex weekly limit, codex limit reset (until the reset page exists) |
| `/articles/codex-limit-reset-time` | Backlog | codex limit reset, codex limit reset time, how to check codex usage left, codex /status |

### Hub 3: Tracking on a Mac (commercial)

| Page | Status | Owns these queries |
| --- | --- | --- |
| Home `/` (hub) | Live in repo | limits left, limits left mac, limitsleft.com, claude and codex usage menu bar app |
| `/articles/track-claude-code-and-codex-usage-on-mac` | Being written | claude usage tracker mac, claude usage menu bar mac, claude usage monitor mac, codex usage tracker mac, claude codex usage monitor, claude code usage tracker, claude code usage monitor, claude code usage dashboard, claude usage widget mac |
| `/articles/track-multiple-claude-and-codex-accounts` | Backlog | multiple claude accounts usage, claude usage across accounts, two claude max accounts |
| `/articles/ccusage-alternative` | Backlog | ccusage alternative, ccusage gui, ccusage mac app |
| `/articles/codexbar-alternatives` | Backlog | codexbar alternatives, codexbar alternative |
| `/articles/claude-usage-apps-for-mac` | Backlog | best claude usage tracker mac, claude usage apps mac |

"claude usage widget mac": the app has no Notification Center widget. The tracking article should say so and say what the menu bar number does instead. Never claim a widget.

### Hub 4: Your own history (differentiator)

| Page | Status | Owns these queries |
| --- | --- | --- |
| `/privacy` | Backlog | what the app reads and stores (trust page, not a traffic page) |
| `/articles/claude-code-and-codex-log-files` | Backlog | claude code logs location, claude code history deleted after 30 days, codex session logs location |
| `/articles/forecast-weekly-usage` | Backlog | will i run out of claude usage this week, claude usage pace |
| `/articles/compare-models-on-your-own-work` | Backlog | claude vs codex models in my own work, claude code model speed |

## How the home page and the four articles fit

The home page is the product hub. The four articles in progress are the two informational hubs (Claude limits, Codex limits), one spoke (Claude reset time), and the main commercial guide. Every article links to the home page once, in the body, where the app answers the reader's problem ("to see this for every account in your menu bar, ..."). Not in every paragraph.

Requirements for the four articles, and for every later one:

1. Answer the query in the first two sentences, before any background.
2. Put a visible "Checked on YYYY-MM-DD" line next to any provider fact (limits, reset rules, plan names), with a link to the official page. Official sources to use: Anthropic's [How do usage and length limits work?](https://support.claude.com/en/articles/11647753-how-do-usage-and-length-limits-work), [Use Claude Code with your Pro or Max plan](https://support.claude.com/en/articles/11145838-use-claude-code-with-your-pro-or-max-plan), [What is a limit reset?](https://support.claude.com/en/articles/17007452-what-is-a-limit-reset), OpenAI's [Codex pricing](https://developers.openai.com/codex/pricing) and [Paid weekly Work and Codex rate limit resets](https://help.openai.com/en/articles/20001507-paid-weekly-work-and-codex-rate-limit-resets).
3. Use question headings that match real queries ("When does the weekly limit reset?").
4. Use one table where it helps (plan, window, how it resets, where to check).
5. Link to the hub, to one or two sibling articles, and to the home page, with descriptive anchor text.
6. Say what the app does not do where it matters (no widget, reads undocumented Claude endpoints, never buys resets).
7. Add `Article` JSON-LD with `datePublished`, `dateModified`, and the author.

Changes to the home page (small, all static):

| Change | Why |
| --- | --- |
| Title becomes "Limits Left: Usage limits for Claude and Codex, in your Mac's menu bar" | The current title is only the product name, so it says nothing to someone searching for the job. The subtitle carries the descriptive words |
| Add `<link rel="canonical" href="https://limitsleft.com/">` | Prevents the Pages preview URL from competing |
| Add `SoftwareApplication` JSON-LD: name, `operatingSystem` "macOS 14 or later", `applicationCategory` "DeveloperApplication", `offers` price 0, `license`, `downloadUrl`, `softwareVersion`, author, `sameAs` the GitHub repository | Entity clarity for search and answer engines. A JSON-LD block is data, not a script, so it does not run and the `script-src 'none'` policy does not block it. Check for console errors after adding it |
| Add a short "Guides" list in the body linking the hub articles | Today articles are linked only from the footer |
| Keep the FAQ as visible text. Do not add `FAQPage` markup for rich results | FAQ rich results were retired in May 2026 per the vendored `seo-plan` notes; the visible Q and A still helps readers and answer engines |

## Backlog

In priority order. "Why it can win" is a judgment from the results seen on 2026-10-16.

| # | Page | Target queries | Intent | Why it can win | Internal links |
| --- | --- | --- | --- | --- | --- |
| 1 | `/articles/ccusage-alternative`: "ccusage alternative for Mac: a menu bar app for quota left" | ccusage alternative, ccusage gui, ccusage mac app | Commercial | Results are vendor pages, one with an undisclosed conflict. We can be the fair one. The tools measure different things, so the honest answer is often "use both" | To home, tracking guide, log files article, Models comparison. From tracking guide, Claude limits hub |
| 2 | `/articles/codexbar-alternatives`: "CodexBar alternatives for Mac" | codexbar alternatives, codexbar alternative | Commercial | CodexBar is well known, so people search for alternatives. Few pages answer it beyond listings | To home, tracking guide, multiple accounts article, apps roundup. From tracking guide, Codex hub |
| 3 | `/articles/check-claude-code-usage-left`: "How to check how much Claude Code usage you have left" | how to check claude code usage left, claude code /usage | Informational, near commercial | A step guide covering every method (`/usage`, Settings > Usage, status line, menu bar) with screenshots. Many results cover only one method | To Claude limits hub, reset time article, home. From both Claude articles, tracking guide |
| 4 | `/articles/track-multiple-claude-and-codex-accounts`: "Track usage across several Claude and Codex accounts" | multiple claude accounts usage, claude usage across accounts | Commercial | Multi-account with combined weekly totals is the app's clearest difference. Other multi-account tools switch logins; this one only watches | To home, tracking guide, forecast article, CodexBar page. From home "Guides", tracking guide |
| 5 | `/privacy`: "What Limits Left reads and stores" | trust page | Trust | Turns the README's history section into a page that comparison pages and answer engines can cite. Few competitors say exactly what they store | To log files article, home. From home privacy section, every comparison page |
| 6 | `/articles/codex-limit-reset-time`: "When do Codex limits reset?" | codex limit reset, codex limit reset time, codex /status | Informational | Mirror of the Claude reset article. OpenAI's reset rules changed in 2026 (the Plus 5-hour limit came back on 2026-08-25, per press reports), so dated pages are scarce. Split it from the Codex hub only if the hub does not already rank for these queries | To Codex hub, home, check usage article. From Codex hub |
| 7 | `/articles/claude-usage-apps-for-mac`: "Apps that show Claude usage in the Mac menu bar, compared" | best claude usage tracker mac, claude usage apps mac, claude usage widget mac | Commercial | A roundup with one criteria table: price, open source, providers, multiple accounts, how it signs in (copied cookie, OAuth, CLI), notarized. Disclose at the top that we make one of the apps | To home, ccusage page, CodexBar page, privacy. From tracking guide |
| 8 | `/articles/claude-code-and-codex-log-files`: "Where Claude Code and Codex keep their logs, and how long" | claude code logs location, claude code history deleted after 30 days, codex session logs location | Informational | Exact paths and the 30-day default cleanup ([Claude Code data retention](https://code.claude.com/docs/en/data-usage#data-retention)) are specific, citable facts. Leads into why a local history is useful | To privacy, Models comparison, home. From privacy, ccusage page |
| 9 | `/articles/forecast-weekly-usage`: "Will you run out before the weekly reset? Reading your pace" | will i run out of claude usage this week, claude usage pace | Informational | Explains pace and forecast with the app's own chart. Low competition; good for answer engines | To both reset articles, multiple accounts, home. From reset articles |
| 10 | `/articles/compare-models-on-your-own-work`: "Compare Claude and Codex models on your own work" | claude vs codex for coding (long tail), claude code model speed | Informational | "Claude vs Codex" is crowded with opinion. A page about measuring your own logs (speed, steps per turn, thinking share, command habits) is different and shows the Models page | To log files, privacy, home. From log files, ccusage page |
| 11 | `/articles/claude-pro-vs-max-limits`: only if needed | claude pro vs max limits | Informational | Write it only if Search Console shows these queries landing on the Claude hub with poor position. Otherwise the hub covers it. Plan details change often, so it costs upkeep | To Claude hub, reset article, home |

### Rules for comparison pages

Comparison pages (items 1, 2, 7) are the most likely to convert and the most likely to go wrong.

- Say at the top that the page is written by the maker of Limits Left.
- Describe each competitor from its own site or README, link to it, and date the check. Facts seen on 2026-10-16:
  - ccusage ([ccusage.com](https://ccusage.com/)): free, MIT, a command-line tool that reads local logs from many coding tools (Claude Code, Codex, and more) and reports tokens and estimated cost. It does not show provider-reported quota left.
  - CodexBar ([github.com/steipete/CodexBar](https://github.com/steipete/CodexBar)): free, MIT, macOS 14 or later, a menu bar app covering many providers (its repository image says 105) with session and weekly windows, local cost estimates, widgets, and a command-line tool. Also has a Linux app.
  - Others to verify before writing: Claude Code Usage Monitor, Claude Usage Tracker (claudetracker.com), ClaudeUsageBar, ClaUse Bar, SessionWatcher (paid), usagebar.com (paid).
- Lead with what the other tool does better. For example: CodexBar covers far more providers and has widgets; ccusage works in a terminal, in scripts, and across many agents. Then say where this app fits: Claude and Codex only, several accounts each, combined weekly totals and pace, forecast, Models page, nothing uploaded.
- Never claim a competitor is unsafe, slow, or broken without a dated, linked source.
- Use "alternative" and "compared with" in titles. Never "vs" headlines that read as attacks, and never a competitor's logo.
- Add a "Last checked" date and a line inviting corrections through GitHub issues. Recheck every quarter.

### Publishing order

| Weeks after launch | Work |
| --- | --- |
| 0 to 2 | limitsleft.com on Cloudflare Pages, the rename, robots.txt, sitemap.xml, llms.txt, home page changes, the four articles, Search Console and Bing setup |
| 2 to 6 | Backlog 1 to 4 |
| 6 to 12 | Backlog 5 to 8 |
| 12 to 24 | Backlog 9 and 10; decide on 11 from data; first quarterly recheck of all dated facts |

About one page every one to two weeks. Each page needs something first-hand (a real screenshot, a real reading, a real path on a Mac), not a rewrite of other guides.

## Internal links

- Every article links to its hub, and every hub links to all its articles.
- Every article links to the home page once, in the body.
- Every page is reachable from the home page in two clicks (home, Articles list, article).
- `articles/index.html` groups articles under the four hub names once there are more than six.
- Anchor text describes the target ("Claude weekly reset time"), never "click here".

## Technical basics for launch

| Item | Detail |
| --- | --- |
| `website/robots.txt` | Allow all, and name the sitemap. Allow the search crawlers that decide citations: `OAI-SearchBot` (ChatGPT search), `Claude-SearchBot` (Claude search), `PerplexityBot`. Training crawlers (`GPTBot`, `ClaudeBot`, `Google-Extended`, `CCBot`) are a separate choice; allowing them suits an open source project that wants to be known |
| `website/sitemap.xml` | Home, Articles list, each published article, privacy page, with `lastmod`. Leave out `404.html` and `_template.html` |
| Canonical links | Every page, on `https://limitsleft.com`. Replace `https://example.com` in the article template and articles |
| `noindex` | Keep it on the template and on drafts. Remove it when an article is published (the README steps already say this) |
| Social image | Absolute URLs on `https://limitsleft.com` for `og:image` and `twitter:image`. Regenerate `social-preview.png` with the new name |
| Speed | Already fast: static, no scripts, sized images. Keep it that way |

## GEO and AI answers

Google's own guidance (in the vendored `seo-geo` skill) is that optimizing for AI search is still SEO. The steps below are plain SEO done carefully, aimed at being quoted correctly.

### Citable facts

Keep these facts identical on the home page, the README, the privacy page, and `llms.txt`. Answer engines repeat what is stated plainly and consistently.

- Limits Left (formerly AI Usage Stats) is a free, open source (MIT) macOS menu bar app that shows how much Claude and Codex subscription quota is left on every account.
- It requires macOS 14 or later, is built as a universal app for Apple silicon and Intel, and is signed and notarized by Apple. Until [`docs/VALIDATION.md`](../VALIDATION.md) records runtime tests on Intel and on macOS 14 and 15, do not publish "runs on" claims for those; say "built for" instead, and update this fact when the tests exist.
- Install with `brew install --cask parkerrex/tap/ai-usage-stats` or from GitHub Releases.
- It shows 5-hour, weekly, and model limits with reset times, and combines weekly quota across accounts of the same provider.
- It keeps a usage history only on the Mac, built from Claude Code and Codex logs, storing derived facts only (no prompts, replies, or command text).
- It never buys credits, changes plans, or sends AI requests to check usage, and has no telemetry.
- It is not affiliated with Anthropic or OpenAI. Claude readings use endpoints Anthropic has not documented.

### Entity clarity

- One name, spelled the same everywhere. One sentence that says what it is, in the first 60 words of the home page and README.
- `SoftwareApplication` JSON-LD on the home page, `sameAs` the GitHub repository. `Person` for the author on articles.
- The GitHub repository description and topics match the citable facts (topics such as `macos`, `menu-bar`, `claude`, `codex`, `usage-tracker`).
- Brand mentions matter more than links for answer engines. Earn them honestly: a Show HN post, a post in r/ClaudeAI where it answers a real question, an entry in relevant awesome lists, and a Homebrew cask that already exists. No paid mentions, no mention farming.

### llms.txt

Add `website/llms.txt`: the site title, the one-line description, the citable facts, and links to the home page, privacy page, and hub articles. It costs a few minutes. Google says it ignores the file, and no major AI provider has confirmed using it, so treat it as optional and expect nothing from it. Update it with each release, like the version line on the home page.

### Checking AI answers

Once a month, ask the same ten questions in ChatGPT search, Perplexity, Claude, and Google AI Mode (for example "how do I see Claude usage left on my Mac", "ccusage alternative with a menu bar", "when does the Claude weekly limit reset"). Record whether the site or repository is cited and whether the facts are correct, in a dated table in `docs/marketing/`. Manual, a few minutes, no tools.

## Measurement

The app promises no telemetry, and the site follows the same rule: no analytics scripts, no cookies, no pixels. The Content Security Policy in `website/_headers` already blocks scripts. Do not turn on Cloudflare Web Analytics, which adds a script.

Free tools that need nothing on the page:

| Tool | Setup | What to watch |
| --- | --- | --- |
| Google Search Console | Domain property for limitsleft.com, verified with a DNS TXT record in Cloudflare. Submit `sitemap.xml` | Impressions, clicks, and position by query and page; indexed pages; which queries land on which page (to catch two pages competing) |
| Bing Webmaster Tools | Import the site from Search Console. Submit the sitemap | Same, for Bing, which also feeds Copilot and other assistants |
| GitHub | Repository Insights > Traffic, and release asset download counts (command below) | Visits referred by the site, downloads per release, stars |
| Manual AI check | See above | Citations and accuracy |

Downloads per release:

```sh
gh api repos/ParkerRex/ai-usage-stats/releases --jq '.[] | {tag_name, downloads: [.assets[].download_count]}'
```

Homebrew publishes aggregate install counts, including casks from public third-party taps ([Homebrew analytics](https://docs.brew.sh/Analytics)). Look for `parkerrex/tap/ai-usage-stats` in the [30-day cask install feed](https://formulae.brew.sh/api/analytics/cask-install/30d.json). It was not listed on 2026-10-16 (the same tap's `parkerrex/tap/mac-stats` was), so it may not have counted installs yet. Users who turned Homebrew analytics off are never counted, so treat the number as a lower bound.

Targets to set after the first four weeks of data, not before. Without search volumes any number now would be invented. What to expect in order: all published pages indexed within a few weeks; impressions first on long-tail queries (comparison and "how to check" pages); clicks later on the reset and limits articles, where competition is highest.

Review once a month: queries with many impressions and low click rate (rewrite the title and description), pages ranking 8 to 20 (improve and add internal links), and queries that land on the wrong page (adjust links or merge).

## Risks

| Risk | What to do |
| --- | --- |
| Trademark | Never use "Claude" or "Codex" in the product name, domain, logo, or app icon. Describe them only as services the app works with ("for Claude and Codex accounts"). Keep "Not affiliated with Anthropic or OpenAI" on every page. No provider logos. In comparisons, name other products only to describe them, never to imply endorsement |
| Provider facts change often | Limits, plan names, and reset rules changed several times in 2026 (press reports describe blanket Claude limit resets, and OpenAI brought back the Plus 5-hour limit on 2026-08-25, also per press reports). Date every fact, link the official page, recheck the limit and reset articles monthly and after any provider announcement, and update `dateModified` only when content really changes |
| Undocumented endpoints | Never call the Claude readings official. Keep the "experimental" wording from the README |
| Unfair or stale comparisons | Follow the comparison rules above. A stale comparison hurts trust more than having none |
| Thin or generic content | Every page needs first-hand material. Do not publish pages that only restate other guides |
| Two pages competing for one query | Each query has one owning page (tables above). Check Search Console monthly |
| Over-claiming | No widget, no Windows, no auto account switching, no API cost tracking beyond connected Claude API credits. Say so where readers expect it |
| Brand confusion with the old name | See below |

## Name and domain

The owner chose **Limits Left** and **limitsleft.com**. The subtitle is "Usage limits for Claude and Codex, in your Mac's menu bar". The name contains neither "Claude" nor "Codex", so it meets the trademark rule above.

### How the name supports the "limits" queries

- The biggest query groups are about limits: "claude usage limits", "claude limit reset time", "codex usage limits", "codex limit reset". The brand says the same word people search, so a result titled "When does the Claude weekly limit reset? | Limits Left" reads as one subject, not as an ad for an unrelated product. That tends to help click rate.
- The name alone does not rank a page. Google does not give a ranking boost for a keyword in a domain name. The articles still have to answer the query.
- Put the subtitle words in the home page title, H1, description, and JSON-LD `description`. The name says "limits"; the subtitle says "Claude", "Codex", "Mac", and "menu bar", which the commercial queries need.
- Article titles end with "| Limits Left". Do not add "limits" to titles a second time just because the brand has it.

### Brand searches

- "Limits Left" is a plain English phrase. A web search on 2026-10-16 found no app with that exact name (closest: "Left - Countdown Tools" for iPhone and "Limit" by Freedom). Brand queries will still mix with general ones, so the home page should rank for "limits left mac", "limits left app", and "limitsleft", not for the bare phrase alone.
- Use the name the same way everywhere: "Limits Left", two words, both capitalized. The domain is the one-word form.
- Register the name where people look: the GitHub repository description and website field (set to limitsleft.com), the Homebrew cask description, release notes, and the app's About window.
- In Search Console, filter queries that contain "limits left" or "limitsleft" to track brand demand separately from topic demand.

### Moving off the old name

The site has not launched under the old name, so there is no domain to redirect. But the GitHub repository, the Homebrew cask (`parkerrex/tap/ai-usage-stats`), release files (`AI-Usage-Stats-<version>.zip`), and early mentions use "AI Usage Stats".

1. Change the name in the app, README, website, social image, JSON-LD, citable facts, and `llms.txt` in one release, so readers never see two names for one product without an explanation.
2. Say "formerly AI Usage Stats" once on the home page, in the README, and in `llms.txt` for at least a year, so search and answer engines connect the two names. Add the old name as `alternateName` in the `SoftwareApplication` JSON-LD.
3. The repository stays github.com/ParkerRex/ai-usage-stats. Use it as the `sameAs` link. If the cask or release file names change later, keep the old cask name working and update the install command on every page together.
4. Keep the same article paths. Slugs avoid the product name.
5. If the domain ever changes again: 301 redirects for every path, Search Console's Change of Address tool, and the new domain added in Bing.
