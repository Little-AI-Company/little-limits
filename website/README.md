# Product website

A static site for Little Limits, usage limits for Claude and Codex in your Mac's menu bar. There is no build step, no JavaScript, and no external fonts, scripts, analytics, or trackers.

| Path | Purpose |
| --- | --- |
| `index.html`, `styles.css` | Home page and the one stylesheet every page uses |
| `images/` | Resized copies of repository assets |
| `articles/index.html` | Article list |
| `articles/_template.html` | Starting point for a new article |
| `changelog/index.html` | What changed in each release, the same entries as `CHANGELOG.md` |
| `404.html` | Page for missing addresses |
| `_headers` | Cloudflare Pages security and cache headers |

Fonts are self-hosted in `fonts/` (see `fonts/README.md`): Schibsted Grotesk for headings and Inter for text. Until they load, or if they fail, the page uses the macOS system faces (SF Pro Rounded through `ui-rounded` for headings, SF Pro for text) and then other sans-serif fonts.

The hero gauge is inline SVG in `index.html`, drawn after the app icon. Its needle sweeps once on load, and stays still when the visitor asks for reduced motion.

Asset URLs are relative, except in `404.html`. The host serves that page for a missing address at any depth, so its URLs start at the site root (`/styles.css`).

## Preview

From the repository root:

```sh
python3 -m http.server -d website 8000
```

Then open <http://localhost:8000>. Light and dark mode follow the system setting. This server does not apply `_headers` and does not serve `404.html` for missing pages; Cloudflare Pages does.

## Deploy on Cloudflare Pages

Connect the repository in the Cloudflare dashboard (Workers & Pages, Create, Pages, Connect to Git) with these build settings:

| Setting | Value |
| --- | --- |
| Production branch | `main` |
| Framework preset | None |
| Build command | none (leave empty) |
| Build output directory | `.` |
| Root directory (advanced) | `website` |

Every push to `main` then deploys the site, and other branches get preview URLs.

To deploy from a terminal instead, from the repository root:

```sh
npx wrangler pages deploy website
```

Wrangler asks you to sign in to Cloudflare and to pick or create the Pages project the first time.

`_headers` sets a Content Security Policy that allows only the site's own files and no scripts, plus `X-Content-Type-Options`, `Referrer-Policy`, `Permissions-Policy`, and `X-Frame-Options`. HTML and CSS are cached for 5 minutes. Files under `/images/` and `/fonts/` are cached for a year, so a changed image needs a new file name (for example `home-v2-1600.png`) and an updated reference in the HTML.

Add the custom domain limitsleft.com under the Pages project's Custom domains.

## Search engine optimization

Every absolute URL (canonical link, Open Graph and Twitter images, JSON-LD, `sitemap.xml`, `robots.txt`, `llms.txt`) uses the origin `https://limitsleft.com`. Article addresses have no `.html`, because Cloudflare Pages redirects `.html` addresses to the extensionless ones. Article files keep the `.html` extension on disk.

| File | Purpose |
| --- | --- |
| `robots.txt` | Allows all crawlers, including AI crawlers, and links the sitemap |
| `sitemap.xml` | Lists the home page, the article list, the changelog, and each article. Add an entry for every new article |
| `llms.txt` | Short product summary and page links for AI assistants. Add each new article |
| `_headers` | Sends `X-Robots-Tag: noindex` for `404.html` |

Home carries `SoftwareApplication` and `FAQPage` JSON-LD. The `FAQPage` text must match the visible Questions section word for word, so edit both together, and update `softwareVersion` with each release. Article pages carry `Article` and `BreadcrumbList` JSON-LD from the template. The Content Security Policy needs no change for JSON-LD, because an `application/ld+json` script is data and never runs.

Keep titles under 60 characters and descriptions between 140 and 160.

## Update for each release

The hero names the current version: "Version 0.3.0 for macOS 14 or later" in `index.html`, alongside `softwareVersion` in its JSON-LD and the version in `llms.txt`. Change all three when a new version is released. Download instructions name the file as `Little-Limits-<version>.zip` and link to the latest release, so they need no change.

Add the release to `changelog/index.html` and `CHANGELOG.md` together, as the [changelog skill](../.agents/skills/changelog/SKILL.md) describes.

## Add an article

1. Copy `articles/_template.html` to `articles/<article-slug>.html`. Use lowercase words joined by hyphens, such as `articles/track-claude-limits-on-mac.html`.
2. Replace every `ARTICLE_` placeholder: the title (in `<title>`, the Open Graph and Twitter tags, the JSON-LD, and `<h1>`), the description (in the meta tags and the JSON-LD), `ARTICLE_SLUG` (in the canonical link and JSON-LD), `ARTICLE_DATE_ISO` as `YYYY-MM-DD` (in the meta tag and JSON-LD), the summary, the visible date (with its `datetime` attribute), and the body.
3. Use `https://limitsleft.com/articles/<article-slug>` (no `.html`) in the canonical link.
4. Delete the `<meta name="robots" content="noindex">` line, so search engines can index the article.
5. Add the article to the top of the list in `articles/index.html`, using the commented example there, and add it to `sitemap.xml` and `llms.txt`. The "No articles yet" line hides itself once the list has an item.
6. Put any new images in `images/` with `width`, `height`, and `alt` set. Keep claims in line with the repository README.

## Images

The files in `images/` are copies of repository assets, resized with `sips -Z` and recompressed so the page stays light:

| File | Source |
| --- | --- |
| `home-1600.webp`, `home-800.webp` | `assets/screenshots/home.png` |
| `models-1600.webp`, `models-800.webp` | `assets/screenshots/models.png` |
| `status-menu-661.webp`, `status-menu-330.webp` | `assets/screenshots/status-menu.png` |
| `forecast-1260.webp`, `forecast-630.webp` | Codex forecast block rendered from the `--demo-home` fixture in light appearance at 630 pt wide (2x), cropped to 1260 x 460 |
| `little-limits-favicon-32.png`, `little-limits-favicon-64.png` | `assets/branding/app-icon/paper-small.png`, cropped to the icon body |
| `little-limits-touch-icon.png` | `assets/branding/app-icon/artwork/paper.png` |
| `little-limits-lockup-light.png`, `little-limits-lockup-dark.png` | `assets/branding/lockup/`, trimmed to 84 px tall (3x the 28 pt header) |
| `little-limits-social-preview.jpg` | `assets/branding/social-preview.png` |

When a screenshot in `assets/` changes, make new copies under new names, for example:

```sh
sips -Z 1600 assets/screenshots/home.png --out website/images/home-v2-1600.png
sips -Z 800 assets/screenshots/home.png --out website/images/home-v2-800.png
```
