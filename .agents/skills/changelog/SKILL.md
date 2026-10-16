---
name: changelog
description: Write the Limits Left changelog for a public release, in CHANGELOG.md and on the website page limitsleft.com/changelog. Use when a version is released or about to be, or when asked to update the changelog, release notes, or what's new.
metadata:
  adapted-from: little-worker .agents/skills/roles/dev/whats-new-update/SKILL.md and packages/console/app/changelog/STYLE.md (2026-10-16), changed from dated entries without versions to one section per app version
---

# Changelog

The changelog tells a person what they can do now, what works better, and what was fixed, in each version of the app. It is not a record of our work. People read it on [limitsleft.com/changelog](https://limitsleft.com/changelog/), in `CHANGELOG.md` on GitHub, and in the GitHub release notes. Write for a person who uses the app and does not write code.

Two files hold the same entries, newest version first:

| File | Purpose |
| --- | --- |
| `CHANGELOG.md` | Markdown copy, read on GitHub |
| `website/changelog/index.html` | The page at `/changelog`, served by Cloudflare Pages |

## When to write

Write one section for each public release: a version with a `v<version>` tag and a GitHub release (see `docs/RELEASING.md`). A local, test, or ad hoc signed build gets no section. Write it in the release PR or in a PR right after it, so the page is live when people upgrade. A version section is final once it ships: to correct it, change the words, never the version or date.

## Where the facts come from

1. Find the previous release tag and its date:

   ```sh
   git fetch --tags origin
   git tag --list 'v*' --sort=-v:refname | head -1
   gh release view v<previous> --json publishedAt,body
   ```

2. List the PRs merged since then. Use the date of the previous tag, and keep only PRs that are in `git log --oneline v<previous>..origin/main`:

   ```sh
   gh pr list --state merged --search "merged:>=YYYY-MM-DD" --limit 200 --json number,title,mergedAt
   git log --oneline v<previous>..origin/main
   ```

3. Read the summary of each `feat`, `fix`, and `perf` PR with `gh pr view <number>`. The summary says what changed for the person. Read the code only when the summary leaves it unclear.
4. If the GitHub release notes for the new version are already drafted, read them too. The changelog and the release notes must agree.
5. Leave out PRs that a person using the app cannot notice: design crit reports, docs, tests, tooling, skills, the website, SEO, and release preparation. Say in the PR description which PRs you left out and why, one line each.

## How to write

Group changes by what a person notices, not by PR. Several PRs can make one bullet, and one PR can make two.

### The voice

- Say "you". Never say "we", "our team", or "I".
- Use words a person can say out loud without explaining them. No programming words: no API, endpoint, bundle ID, Keychain service, fixture, refactor, regression.
- Short sentences in the present tense. One idea in each sentence.
- Say what a person sees and does, not how the code works.
- Let the change carry the news. No "excited", "huge", "powerful", or exclamation marks.
- No em dashes. Use a period, a comma, or a colon.
- Name keys as Apple does: Command-R, Shift-Command-R, Return, Escape.

### Names

- Put each window, page, section, button, menu item, and setting in bold, spelled exactly as the app spells it, including `…`: **Settings**, **Refresh Account**, **Reconnect…**, **Window > Zoom**. Check a name with `grep -rn '"<name>' Sources` before you use it.
- Use the app's own words for its ideas: 5-hour limit, weekly limit, model limit, earned reset, Weekly Totals, forecast, reset calendar. Do not say quota pool, window role, or session window.
- Claude, Claude Code, and Codex are the products the app reads. Name them when the change is about one of them.

### A version section

```markdown
## 0.2.1 (2026-10-16)

One or two sentences: the main news of this version.

### New

- **Place:** What you can do now, and where to find it.

### Improved

### Fixed

### Changed
```

- The heading is the version without `v`, then the date the GitHub release was published, as `YYYY-MM-DD`, in the owner's time zone.
- Groups come in this order, and an empty group is left out:

  | Group | Use it when |
  | --- | --- |
  | New | A person can do something they could not do before |
  | Improved | Something they already did is faster, clearer, or easier |
  | Fixed | Something that was wrong now works. Say what works now, not what was broken |
  | Changed | Something was renamed, moved, or went away. Say where it went |

- Each bullet starts with its place in bold and a colon: **Home:**, **Menu bar number:**, **Models:**, **Settings:**. Then one to three sentences.
- A change to something new in the same version is part of that new item, not a fix.
- No PR numbers, branch names, commit types, build numbers, or file names.
- Do not repeat the install command. The website and README own it. When a release changes how people upgrade, as the rename did, say what to do in one bullet, with the same commands as the GitHub release notes.

### Good and bad

| Good | Bad | Why it is bad |
| --- | --- | --- |
| **Menu bar number:** It now shows the lowest of your accounts' 5-hour and weekly limits. | fix: count only general windows in the menu bar number | A commit title, and "general windows" is a code word |
| **Home:** Tab reaches the forecast, the account table, and the calendar events. | Recalculate the key view loop after render | Says how the code works |
| **Models:** Model names are easy to read, such as Opus 5.5. | Added modelDisplayName formatting (MODELS-02) | A function name and a crit finding ID |

## Update both files

1. In `CHANGELOG.md`, add the new section above the previous version.
2. In `website/changelog/index.html`, add the same section at the top of the `.prose` block. Copy the markup of the version below it: an `<h2 id="v<version>">`, the date line with `<time datetime="YYYY-MM-DD">`, the lead paragraph, then an `<h3>` and a `<ul>` for each group. Use `<strong>` for bold, `<code>` for a command, and `&amp;` for `&`.
3. The words in both files match. Only the markup differs.
4. In `website/sitemap.xml`, set the `<lastmod>` of `https://limitsleft.com/changelog/` to the release date.
5. Do not change `softwareVersion` or the hero version in `website/index.html` here. `website/README.md` (Update for each release) owns those.

## Check

- Each bullet traces to a merged PR in `v<previous>..origin/main`. If you cannot point to the change that makes a sentence true, take the sentence out.
- Each bold name matches a string in `Sources/`.
- No em dashes, and no "we":

  ```sh
  grep -n "$(printf '\342\200\224')" CHANGELOG.md website/changelog/index.html
  grep -n -i -w 'we' CHANGELOG.md website/changelog/index.html
  ```

- The HTML parses and the sitemap is valid XML:

  ```sh
  python3 -c "import html.parser,sys; html.parser.HTMLParser().feed(open(sys.argv[1]).read())" website/changelog/index.html
  xmllint --noout website/sitemap.xml
  ```

- Serve the site, open the page, and check it in light and dark appearance and at a narrow window width:

  ```sh
  python3 -m http.server -d website 8127
  curl -s -o /dev/null -w '%{http_code}\n' http://localhost:8127/changelog/
  ```

  Stop the server when you are done.
- Run `git diff --check`, read every changed line, and open the PR with the title `docs: add the <version> changelog`.
