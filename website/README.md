# Product website

A static page for AI Usage Stats: `index.html`, `styles.css`, and `images/`. There is no build step, no JavaScript, and no external fonts, scripts, analytics, or trackers. Fonts are the macOS system faces: SF Pro Rounded for headings through `ui-rounded`, which Safari supports, and SF Pro for text. Other browsers show headings in SF Pro or their own sans-serif. All asset URLs are relative.

The hero gauge is inline SVG in `index.html`, drawn after the app icon. Its needle sweeps once on load, and stays still when the visitor asks for reduced motion.

## Preview

From the repository root:

```sh
python3 -m http.server -d website 8000
```

Then open <http://localhost:8000>. Light and dark mode follow the system setting.

## Images

The files in `images/` are copies of repository assets, resized with `sips -Z` and recompressed so the page stays light:

| File | Source |
| --- | --- |
| `home-1600.png`, `home-800.png` | `assets/screenshots/home.png` |
| `models-1600.png`, `models-800.png` | `assets/screenshots/models.png` |
| `status-menu-661.png`, `status-menu-330.png` | `assets/screenshots/status-menu.png` |
| `favicon-32.png`, `favicon-64.png`, `apple-touch-icon.png` | `assets/app-icon.png` |
| `forecast-1260.png`, `forecast-630.png` | Codex forecast area of `assets/screenshots/home.png`, cropped at 1260 x 300 from (330, 605) |
| `social-preview.png` | `assets/branding/social-preview.png` |

When a screenshot in `assets/` changes, regenerate its copies here, for example:

```sh
sips -Z 1600 assets/screenshots/home.png --out website/images/home-1600.png
sips -Z 800 assets/screenshots/home.png --out website/images/home-800.png
```

## Deploy

Any static host works, such as GitHub Pages, Cloudflare Pages, or Netlify. Publish the contents of this folder as the site root.

For GitHub Pages, deploy the `website/` folder with a Pages workflow, or copy its contents to the branch that Pages serves.

The custom domain is not bought yet. After it is, add a `CNAME` file with the domain to this folder (for GitHub Pages) and change the `og:image` and `twitter:image` values in `index.html` to absolute URLs on that domain, because some link previews ignore relative image URLs.
