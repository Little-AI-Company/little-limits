# Vendored claude-seo skills

Source: https://github.com/AgriciDaniel/claude-seo at commit `4b99de2f7de7e7d5247042e5fb5b4ea9368ef734`, MIT license (copied into each skill folder).

Vendored for the product website in `website/`: `seo-plan`, `seo-cluster`, `seo-audit`, `seo-technical`, `seo-schema`, `seo-sitemap`, `seo-page`, `seo-content`, `seo-content-brief`, `seo-geo`, `seo-images`, `seo-sxo`. Each is linked from `.claude/skills/`.

Not vendored: the plugin's Python helper scripts and agents, and skills that need paid data APIs or do not apply to a single-language static site (DataForSEO, Google APIs, backlinks, local, maps, ecommerce, hreflang, image generation, programmatic, drift).

Changes from upstream: one note under each skill's front matter saying that the helper scripts are absent and to fetch pages with built-in tools instead. Reviewed before vendoring: the skills contain no network calls, telemetry, or credential requests of their own; their only executable references are the omitted helper scripts.

To update: copy the same skill folders from a newer upstream commit, keep the note and LICENSE, and update the commit above.
