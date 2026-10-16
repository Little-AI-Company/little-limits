"""Write the Limits Left wordmark and lockup SVGs from outlined glyph data.

Usage: make_wordmark.py <outline.txt> <icon.png> <output_dir>
"""
import base64
import os
import sys

outline_path, icon_path, output_dir = sys.argv[1:4]
with open(outline_path) as handle:
    bounds_line, path_data = handle.read().split("\n", 1)
path_data = path_data.strip()
min_x, min_y, width, height = (float(v) for v in bounds_line.split())
with open(icon_path, "rb") as handle:
    icon_uri = "data:image/png;base64," + base64.b64encode(handle.read()).decode("ascii")

INK_LIGHT = "#39203C"  # plum ink, for light grounds
INK_DARK = "#F4EEF5"   # site dark-mode text, for dark grounds
CAP_HEIGHT = 703       # Schibsted Grotesk cap height at size 1000


def number(value):
    return f"{value:.1f}".rstrip("0").rstrip(".")


def write(name, svg):
    with open(os.path.join(output_dir, name), "w") as handle:
        handle.write(svg + "\n")


def wordmark(ink):
    view_box = f"{number(min_x)} {number(min_y)} {number(width)} {number(height)}"
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{view_box}" '
        f'width="{number(width / 10)}" height="{number(height / 10)}" role="img" aria-label="Limits Left">'
        f"<title>Limits Left</title>"
        f'<path fill="{ink}" d="{path_data}"/></svg>'
    )


def lockup(ink):
    # The tile is 2.1 cap heights tall; caps are centered on it; the gap is 0.24 of the tile.
    tile = round(CAP_HEIGHT * 2.1)
    gap = round(tile * 0.24)
    baseline = tile / 2 + CAP_HEIGHT / 2
    text_x = tile + gap - min_x
    total_width = tile + gap + width
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" '
        f'viewBox="0 0 {number(total_width)} {tile}" width="{number(total_width / 10)}" height="{number(tile / 10)}" '
        f'role="img" aria-label="Limits Left">'
        f"<title>Limits Left</title>"
        f'<image width="{tile}" height="{tile}" href="{icon_uri}"/>'
        f'<path fill="{ink}" transform="translate({number(text_x)} {number(baseline)})" d="{path_data}"/></svg>'
    )


write("limits-left-wordmark.svg", wordmark(INK_LIGHT))
write("limits-left-wordmark-dark.svg", wordmark(INK_DARK))
write("limits-left-lockup.svg", lockup(INK_LIGHT))
write("limits-left-lockup-dark.svg", lockup(INK_DARK))
