#!/usr/bin/env python3
"""Restyles Kenney's Blaster Kit colormap to IONFALL's palette (PLAN §4:
mixed packs share one look). Saturated body colours become dark gunmetal,
greys become light steel, and the brightest warm/pink detail swatches become
glowing ion cyan (also written to an emission map).

    python3 tools/recolor_colormap.py <kenney colormap.png> art/weapons/kenney/
"""
import colorsys
import sys
from pathlib import Path

from PIL import Image

ION = (79 / 255, 227 / 255, 255 / 255)


def recolor(rgb):
    r, g, b = (c / 255 for c in rgb)
    h, s, v = colorsys.rgb_to_hsv(r, g, b)
    if s > 0.3 and v > 0.25:
        # Kenney paints bodies in saturated colours: they become dark
        # gunmetal; the brightest warm/pink detail swatches become ion glow.
        if v > 0.93 and (h < 0.17 or h > 0.8):
            return tuple(round(c * 255) for c in ION), True
        k = 0.55 + 0.45 * v
        return (round(0.15 * k * 255), round(0.19 * k * 255), round(0.25 * k * 255)), False
    # Neutral: cool light steel.
    lum = (0.3 * r + 0.59 * g + 0.11 * b) ** 0.9
    return (round(lum * 0.9 * 255), round(lum * 0.95 * 255), round(min(1.0, lum * 1.02) * 255)), False


def main():
    src, out = Path(sys.argv[1]), Path(sys.argv[2])
    im = Image.open(src).convert("RGB")
    color = Image.new("RGB", im.size)
    emit = Image.new("RGB", im.size)
    cache = {}
    for y in range(im.size[1]):
        for x in range(im.size[0]):
            p = im.getpixel((x, y))
            if p not in cache:
                cache[p] = recolor(p)
            c, glow = cache[p]
            color.putpixel((x, y), c)
            emit.putpixel((x, y), c if glow else (0, 0, 0))
    color.save(out / "colormap_ion.png")
    emit.save(out / "colormap_ion_emission.png")


if __name__ == "__main__":
    main()
