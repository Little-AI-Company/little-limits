# Product website

A static site for AI Usage Stats. There is no build step, no JavaScript, and no external fonts, scripts, analytics, or trackers.

| Path | Purpose |
| --- | --- |
| `index.html`, `styles.css` | Home page and the one stylesheet every page uses |
| `images/` | Resized copies of repository assets |
| `articles/index.html` | Article list |
| `articles/_template.html` | Starting point for a new article |
| `404.html` | Page for missing addresses |
| `_headers` | Cloudflare Pages security and cache headers |

Fonts are the macOS system faces: SF Pro Rounded for headings through `ui-rounded`, which Safari supports, and SF Pro for text. Other browsers show headings in SF Pro or their own sans-serif.

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

The custom domain is not bought yet. After it is, add it under the Pages project's Custom domains, then run the command under "Set the domain" below.

## Search engine optimization

Every absolute URL (canonical link, Open Graph and Twitter images, JSON-LD, `sitemap.xml`, `robots.txt`, `llms.txt`) uses the placeholder origin `https://SITE_ORIGIN`, because the domain is not bought yet.

### Set the domain

From the repository root, replace the placeholder everywhere with the real origin (macOS `sed`; on Linux drop the `''` after `-i`):

```sh
grep -rl 'https://SITE_ORIGIN' website | xargs sed -i '' 's#https://SITE_ORIGIN#https://your-domain.example#g'
```

Then check that `grep -r SITE_ORIGIN website` prints nothing. Run it after the last article is added, or run it again.

| File | Purpose |
| --- | --- |
| `robots.txt` | Allows all crawlers, including AI crawlers, and links the sitemap |
| `sitemap.xml` | Lists the home page, the article list, and each article. Add an entry for every new article |
| `llms.txt` | Short product summary and page links for AI assistants. Add each new article |
| `_headers` | Sends `X-Robots-Tag: noindex` for `404.html` |

Home carries `SoftwareApplication` and `FAQPage` JSON-LD. The `FAQPage` text must match the visible Questions section word for word, so edit both together, and update `softwareVersion` with each release. Article pages carry `Article` and `BreadcrumbList` JSON-LD from the template. The Content Security Policy needs no change for JSON-LD, because an `application/ld+json` script is data and never runs.

Keep titles under 60 characters and descriptions between 140 and 160.

## Update for each release

The hero names the current version: "Version 0.2.0 for macOS 14 or later" in `index.html`. Change it when a new version is released. Download instructions name the file as `AI-Usage-Stats-<version>.zip` and link to the latest release, so they need no change.

## Add an article

1. Copy `articles/_template.html` to `articles/<article-slug>.html`. Use lowercase words joined by hyphens, such as `articles/track-claude-limits-on-mac.html`.
2. Replace every `ARTICLE_` placeholder: the title (in `<title>`, the Open Graph and Twitter tags, the JSON-LD, and `<h1>`), the description (in the meta tags and the JSON-LD), `ARTICLE_SLUG` (in the canonical link and JSON-LD), `ARTICLE_DATE_ISO` as `YYYY-MM-DD` (in the meta tag and JSON-LD), the summary, the visible date (with its `datetime` attribute), and the body.
3. Keep `https://SITE_ORIGIN` in the canonical link. See "Set the domain".
4. Delete the `<meta name="robots" content="noindex">` line, so search engines can index the article.
5. Add the article to the top of the list in `articles/index.html`, using the commented example there, and add it to `sitemap.xml` and `llms.txt`. The "No articles yet" line hides itself once the list has an item.
6. Put any new images in `images/` with `width`, `height`, and `alt` set. Keep claims in line with the repository README.

## Images

The files in `images/` are copies of repository assets, resized with `sips -Z` and recompressed so the page stays light:

| File | Source |
| --- | --- |
| `home-1600.png`, `home-800.png` | `assets/screenshots/home.png` |
| `models-1600.png`, `models-800.png` | `assets/screenshots/models.png` |
| `status-menu-661.png`, `status-menu-330.png` | `assets/screenshots/status-menu.png` |
| `forecast-1260.png`, `forecast-630.png` | Codex forecast area of `assets/screenshots/home.png`, cropped at 1260 x 300 from (330, 605) |
| `favicon-32.png`, `favicon-64.png`, `apple-touch-icon.png` | `assets/app-icon.png` |
| `social-preview.png` | `assets/branding/social-preview.png` |

When a screenshot in `assets/` changes, make new copies under new names, for example:

```sh
sips -Z 1600 assets/screenshots/home.png --out website/images/home-v2-1600.png
sips -Z 800 assets/screenshots/home.png --out website/images/home-v2-800.png
```
