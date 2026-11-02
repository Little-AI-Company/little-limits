# Little Limits in the Little Worker cast style, November 2, 2026

Parker, 2026-11-02: "our app icons set and character is dated. it's using a different animation/illustration style than we have in the Little-worker project. pls update so that it follows the branding more akin to https://thelittleworker.com/brand". He asked for a character specific to Little Limits, a GitHub social preview, and a loading illustration.

Two Codex jobs, run in order, each in its own empty folder, with the built-in image tool (`codex exec --sandbox workspace-write --skip-git-repo-check -C <empty-folder> -i <ref> ... - < <this prompt>`). Attach as references, from the Little Worker repository's brand files (the ones `https://thelittleworker.com/brand` serves):

- Lou's character sheet (`lou-character-sheet.png`) and pose sheet (`lou-pose-sheet.png`)
- Lou at rest, waving and done (`lou-rest-1024.png`, `lou-wave-1024.png`, `lou-done-1024.png`)
- The Little Worker GitHub social preview (`github-social-preview-1280x640.png`) and the Mac app icon (`app-icon-mac-1024.png`)
- This repository's current `assets/branding/app-icon/artwork/paper.png`, for the object and colors only

Job 2 also attaches the sheet that job 1 made, first.

## What changes from the October 29 drawing

The October 29 art copied an earlier, flatter version of Lou: flat vector fills, even outlines, glossy oval eyes with a white highlight, and a ribbed turtleneck. The cast on the brand page now looks like this, and the new drawing must match it:

- Hand-inked dark line art (about #121312), slightly soft and pencil-like, with a little weight variation. Not a vector outline of even width.
- Soft painted shading that gives the object head real volume: the casing shows its depth on one side, the face has a gentle shadow along the rim. Still calm and clean, no glossy highlights, no glow.
- Small solid black dot eyes, slightly taller than wide, with NO white highlight. A small curved smile; open with a little pink tongue when happy. Soft pink blush (#FDD4BB range).
- A black hoodie with a hood behind the neck and two short drawstrings, soft dark grey shading. Puffy white cartoon gloves. White sneakers when the feet show.
- The figure stands on a flat soft pastel circle over warm Paper (#FBFAF7). Little Limits keeps its butter circle (#F6ECC6), so it reads apart from Lou's pink circle and the Sand ground.
- Lots of empty space. No sparkles, motion lines, props, text, letters or logos unless a job below asks for them.

## The character: the gauge

The head is a round dial gauge, about as big as Lou's TV head relative to the body.

- A thick black bezel ring, with its depth visible on one side like the side of Lou's TV casing.
- A warm cream dial face (#FDF5EA) inside the bezel.
- Five short dark tick marks along the top arc of the dial, left to right.
- A short dark needle on a small round hub at the dial's center, pointing at the LEFTMOST tick: a little is left. This is the brand detail and must read at 64 px.
- The face sits on the lower half of the dial, below the hub: two dot eyes, blush, smile.

Personality: calm, honest and a little cheeky about how much is left. It checks the gauge for you so you never run out by surprise.

## Job 1: character sheet

Save `gauge-character-sheet.png`, 1536 x 1024, laid out like Lou's character sheet: a turnaround (front, three-quarter, side, back) on the left, eight expressions in a grid (calm, happy, laughing, thinking, surprised, worried with the needle at empty, sleepy, delighted with the needle swinging to full), and a pose library of eight small full-body poses (idle, waving, looking at a laptop, checking a wristwatch, holding up a hand to say "wait", stretching, sitting, sleeping). No words, labels, numbers, swatch names or title anywhere on the sheet.

## Job 2: finals from the sheet

All 1024 x 1024 PNG, on model with the attached sheet and with each other.

1. `icon.png`: the app icon artwork, full bleed, no rounded square, no shadow, no text. Head and shoulders facing the viewer, at rest with a calm closed smile, hands together in front like `lou-rest-1024.png`, on the butter circle over Paper. The head fills about 60 percent of the width. The bezel, ticks and low needle read at 64 px.
2. `icon-small.png`: for 16 and 32 px. The head only, filling about 70 percent of the square, on the butter circle. Thicker lines, three ticks, a thicker needle, bigger eye dots, almost no shading.
3. `rest.png`: the same as `icon.png` with a little more space round the figure, like `lou-rest-1024.png`.
4. `wave.png`: head and shoulders, waving with the right hand, happy open smile, like `lou-wave-1024.png`.
5. `walk.png`: full body walking cheerfully to the right in three-quarter view, on the butter circle, whole figure visible with margin.
6. `mark.png`: the head alone facing the viewer, calm smile, on plain Paper, filling about 75 percent of the square.
7. `loading-blank.png`: exactly the `icon.png` drawing, facing straight at the viewer so the dial is a true circle, but with NO needle, NO hub and NO eyes. Keep the ticks, the blush and the smile. The app draws the needle and the eyes on top and animates them.

View each file at full size and at 64, 32 and 16 px before saving it under its name.
