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

The custom domain is not bought yet. After it is:

1. Add it under the Pages project's Custom domains.
2. Change the `og:image` and `twitter:image` values to absolute URLs on that domain, because some link previews ignore relative image URLs.
3. Replace `https://example.com` in each article's canonical link with the domain.

## Update for each release

The hero names the current version: "Version 0.2.0 for macOS 14 or later" in `index.html`. Change it when a new version is released. Download instructions name the file as `AI-Usage-Stats-<version>.zip` and link to the latest release, so they need no change.

## Add an article

1. Copy `articles/_template.html` to `articles/<article-slug>.html`. Use lowercase words joined by hyphens, such as `articles/track-claude-limits-on-mac.html`.
2. Replace every `ARTICLE_` placeholder: the title (in `<title>`, `og:title`, and `<h1>`), the description (in `description` and `og:description`), the summary, the date (both the `datetime` attribute and the visible text), and the body.
3. Set the canonical link to the article's final address. Until the domain exists, keep `https://example.com` and only change the slug.
4. Delete the `<meta name="robots" content="noindex">` line, so search engines can index the article.
5. Add the article to the top of the list in `articles/index.html`, using the commented example there. The "No articles yet" line hides itself once the list has an item.
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
