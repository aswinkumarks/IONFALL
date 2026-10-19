#!/usr/bin/env python3
"""Paints IONFALL's armour suit over the Kenney Animated Characters 3 UV
layout (256 x 256 atlas: head top-left, skin top-right, shirt bottom-left,
trousers bottom-right, shoes middle-right). Writes the albedo and an
emission mask; the game colours the mask per player (SkinnedRig).

    python3 tools/gen_suit.py art/characters/kenney/
"""
import sys
from pathlib import Path

from PIL import Image, ImageDraw

WHITE = (214, 222, 230)
PLATE = (186, 196, 206)
SEAM = (70, 78, 90)
DARK = (44, 50, 60)
DARKER = (30, 34, 42)
VISOR = (12, 16, 22)


def panel_lines(d, box, step, color, vertical=True):
    x0, y0, x1, y1 = box
    if vertical:
        for x in range(x0 + step, x1, step):
            d.line([(x, y0), (x, y1)], fill=color, width=1)
    else:
        for y in range(y0 + step, y1, step):
            d.line([(x0, y), (x1, y)], fill=color, width=1)


def main():
    out = Path(sys.argv[1])
    img = Image.new("RGB", (256, 256), DARK)
    glow = Image.new("L", (256, 256), 0)
    d = ImageDraw.Draw(img)
    g = ImageDraw.Draw(glow)

    # Head (0..160 x 0..120): helmet shell with a wide dark visor over the face.
    d.rectangle([0, 0, 159, 119], fill=WHITE)
    panel_lines(d, (0, 0, 159, 119), 20, PLATE)
    d.rectangle([30, 34, 130, 82], fill=VISOR)
    d.line([(30, 34), (130, 34)], fill=SEAM, width=2)
    g.rectangle([34, 76, 126, 81], fill=255)  # visor underglow
    d.rectangle([0, 100, 159, 119], fill=DARK)  # neck seal

    # Skin areas (arms/hands, right column): gunmetal sleeves with bands.
    d.rectangle([160, 0, 255, 189], fill=DARK)
    panel_lines(d, (160, 0, 255, 189), 12, DARKER, vertical=False)
    for y in (24, 150):
        g.rectangle([160, y, 255, y + 3], fill=255)

    # Shoes (160..205 x 32..130): heavy boots.
    d.rectangle([160, 32, 205, 130], fill=DARKER)
    d.rectangle([160, 110, 205, 130], fill=SEAM)

    # Shirt (0..150 x 120..256): white chest/back plates, dark seams,
    # an accent strip down the centre.
    d.rectangle([0, 120, 152, 255], fill=WHITE)
    for x0 in (8, 80):
        d.rectangle([x0, 132, x0 + 62, 200], outline=SEAM, width=2)
    d.rectangle([0, 205, 152, 255], fill=PLATE)
    panel_lines(d, (0, 205, 152, 255), 16, SEAM)
    d.rectangle([70, 120, 80, 255], fill=DARK)
    g.rectangle([72, 130, 78, 200], fill=255)
    g.rectangle([0, 201, 152, 203], fill=255)  # belt line

    # Trousers (152..256 x 190..256): dark leg armour, knee plates, stripe.
    d.rectangle([152, 190, 255, 255], fill=DARK)
    for x0 in (160, 210):
        d.rectangle([x0, 214, x0 + 30, 234], fill=PLATE, outline=SEAM)
    g.rectangle([152, 192, 255, 194], fill=255)

    img.save(out / "suit.png")
    glow.save(out / "suit_emission.png")


if __name__ == "__main__":
    main()
