# Vendored claude-seo skills

Source: https://github.com/AgriciDaniel/claude-seo at commit `4b99de2f7de7e7d5247042e5fb5b4ea9368ef734`, MIT license (copied into each skill folder).

Vendored for the product website in `website/`: `seo-plan`, `seo-cluster`, `seo-audit`, `seo-technical`, `seo-schema`, `seo-sitemap`, `seo-page`, `seo-content`, `seo-content-brief`, `seo-geo`, `seo-images`, `seo-sxo`. Each is linked from `.claude/skills/`.

Not vendored: the plugin's Python helper scripts and agents, and skills that need paid data APIs or do not apply to a single-language static site (DataForSEO, Google APIs, backlinks, local, maps, ecommerce, hreflang, image generation, programmatic, drift).

Shared references: `seo/references/` holds the three upstream files that vendored skills link to (`eeat-framework.md`, `eeat-scoring-guide.md`, `schema-types.md`), with the LICENSE. `seo-content` links to them by relative path instead of `${CLAUDE_PLUGIN_ROOT}`.

Fallbacks for the omitted helper scripts:

| Upstream helper | Use instead |
| --- | --- |
| `render_page.py`, `fetch_page.py` | `curl -sSL --max-redirs 3 --proto '=http,https' <url>` or the web fetch tool; the site is static HTML, so raw and rendered HTML match. |
| `parse_html.py`, `metadata_template.py` | `python3 -I -c` with `html.parser` from the standard library to read the title, meta tags, headings, links, images, and JSON-LD blocks. |
| `sitemap_discovery.py` | Read `robots.txt` and `sitemap.xml` with `curl`; validate with `xmllint --noout`. |
| `agentic_check.py`, `agent_ux_check.py` | Compare visible text in the raw HTML with the page; check that every important fact is in the HTML, not only in images. |
| `pagespeed_check.py`, Google, Matomo, DataForSEO, backlink helpers | Skip; they need accounts or paid APIs. Note the gap in the report. |
| `content_humanize.py`, `seo_updates.py`, `iptc_ai_label.py`, `google_report.py`, `drift_*` | Skip; do the review by reading, and write findings as Markdown. |

Fetch safety: upstream helpers block private-network targets. Without them, fetch only public `http` or `https` URLs of the site under review or of cited sources, plus a named local preview; never fetch private-network, link-local, or `file:` addresses or follow redirects to them.

Changes from upstream: one note under each skill's front matter pointing to the fallbacks and fetch safety rules above, and relative links in `seo-content` to the shared references. Reviewed before vendoring: the skills contain no network calls, telemetry, or credential requests of their own; their only executable references are the omitted helper scripts.

To update: copy the same skill folders from a newer upstream commit, keep the note and LICENSE, and update the commit above.
