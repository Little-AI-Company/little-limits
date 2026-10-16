# Repository assets

The branding files were generated with the built-in ImageGen tool on October 9, 2026.

- `app-icon.png`: 1024 × 1024 PNG. The Enamel app icon, the bundle icon since October 16, 2026, and the master for its 64 to 1024 px slots. It is `branding/explorations/icon-variations/enamel.png`; see `branding/explorations/README.md` for how it was made. `branding/app-icon/` holds the Small size master for the 16 and 32 px slots and the Night alternate. The icon prompt below describes the first icon, which has been replaced.
- `repository-header.png`: 2172 × 724 PNG. Black background with the same usage indicator, the title "AI Usage Stats", and the line "Claude. Codex. One menu."

Both outputs were inspected visually. The header text matches the requested spelling and punctuation. The mark follows minimal monochrome design conventions and does not reproduce the Vercel triangle.

## README screenshots

`screenshots/usage-overview.png` and `screenshots/app-settings.png` are Computer captures of the packaged app on October 13, 2026, macOS 27.0.1. Each is 1400 × 1136 pixels, exported as PNG with text/EXIF metadata removed. Image content was not cropped, retouched, or generated. The app source matches `d22cc5a1fdc50229f428802426d708dbfa34afbc`; the captures use the existing connected Claude account rather than demo fixtures. They show the account email and observed subscription quota, with unsupported credit readings still unavailable. Images were inspected for complete rendering and credentials before inclusion. No sign-in, stored balance, or login setting was changed.

The older `screenshots/menu-bar.png` is not used in the README. Native menu capture timed out; no current menu capture is claimed. The generated repository header remains a branding asset, while the README leads with the actual account overview.

## Generation mode

Built-in `image_gen.imagegen`; opaque black backgrounds. The icon was generated without input images. The header was generated using `assets/app-icon.png` as a mark reference. Original generated files were copied into this directory without raster editing.

## Icon prompt

```text
Use case: logo-brand
Asset type: production macOS app icon, square 1024 by 1024 image
Primary request: Create an original, extremely simple usage indicator logo for "AI Usage Stats", inspired by the severe minimal monochrome design discipline of Vercel, without using or resembling Vercel's triangle mark.
Scene/backdrop: perfectly flat pure black square background extending to every edge.
Subject: a compact white geometric precision usage indicator made of exactly two stacked horizontal gauge rows. Each row is a single substantial white rectangular line segment and a detached tiny white square at its right end. Upper bar is longer, lower bar is shorter. Both rows have identical thickness, square corners, align on the left, and are separated by a clear black gap. The detached terminal squares line up vertically. This is one simple coherent original symbol.
Style/medium: flat sharp geometric vector-like graphic rendered as a PNG, precise edges, intentional restraint.
Composition/framing: centered single mark, generous padding, symbol occupies roughly the central 46 percent of the square width and 24 percent height, strong readability at 16 to 32 pixels.
Color palette: pure black and pure white only.
Constraints: no text, no rounded icon enclosure, no gradient, no shadow, no texture, no outline, no stars, no triangles, no robot, no brain, no circuit, no tiny decoration, no mockup, no watermark. Deliver the square icon only.
```

## Repository header prompt

```text
Use case: logo-brand
Asset type: production GitHub repository header, wide 3:1 landscape image
Primary request: Design a stark, polished monochrome branding header for the macOS menu bar app AI Usage Stats, in the severe minimal typographic design discipline associated with Vercel. Keep the identity original; no Vercel triangle or Vercel wordmark.
Input images: Image 1 is a reference image for the app's original usage indicator mark. Match this exact white mark: two stacked horizontal gauge bars, top longer than lower, left aligned, equal rectangular thickness and square corners; one detached white square to the right of each bar, terminal squares vertically aligned.
Scene/backdrop: pure flat black edge-to-edge background.
Composition/framing: wide 3:1 canvas. A single generous centered horizontal lockup: reference mark on the left, large crisp white text AI Usage Stats on the right. Beneath the main title only, a small restrained white secondary line: Claude. Codex. One menu. Ample black margins. Mark and typography together occupy the central two thirds of the banner width. Precise clean alignment.
Style/medium: premium minimal graphic design, flat vector-like shapes and exceptionally sharp contemporary sans-serif typography like a restrained Swiss grotesk. Title medium-bold and clear, secondary line regular-weight.
Text (verbatim): "AI Usage Stats"
Secondary text (verbatim): "Claude. Codex. One menu."
Color palette: black background, white mark and white text only.
Constraints: exact spelling and punctuation; only the two specified text lines. No extra subtitle above the main title. No cards, no pills, no gradients, no textures, no glows, no stars, no robots, no brain symbols, no triangles, no dashboard screenshot, no watermark. Deliver only the wide header graphic.
```
