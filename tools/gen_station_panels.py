#!/usr/bin/env python3
"""Station's panel textures (our own work): one 1024 px tile of hull plating
as colour, normal and occlusion/roughness maps, for StationLook. The panel
grid alone (tools/gen_textures.gd) is colour only, so the walls lit flat;
these give the plating depth: bevelled seams, inset sub-panels, vents and
bolts in the normal map, grime in the seams. Deterministic.

    python3 tools/gen_station_panels.py   # writes art/textures/station_panel_*.png
"""
from pathlib import Path

import numpy as np
from PIL import Image

N = 1024
CELLS = 2  # 2 x 2 large panels per tile, like panel_grid.png
OUT = Path(__file__).resolve().parent.parent / "art" / "textures"
rng = np.random.default_rng(7)

y, x = np.mgrid[0:N, 0:N].astype(np.float32)
height = np.ones((N, N), np.float32)
occl = np.ones((N, N), np.float32)
tone = np.ones((N, N), np.float32)
rough = np.full((N, N), 0.55, np.float32)


def box_sdf(px, py, x0, y0, x1, y1):
    """Signed distance (px) to the box, negative inside."""
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    hx, hy = (x1 - x0) / 2, (y1 - y0) / 2
    dx, dy = np.abs(px - cx) - hx, np.abs(py - cy) - hy
    outside = np.hypot(np.maximum(dx, 0), np.maximum(dy, 0))
    return outside + np.minimum(np.maximum(dx, dy), 0)


def bevel(d, width):
    """0 at the edge rising to 1 `width` px inside (smooth)."""
    t = np.clip(-d / width, 0, 1)
    return t * t * (3 - 2 * t)


cell = N // CELLS
seam = 5
covered = np.zeros((N, N), bool)  # inside some panel (else seam)
KINDS = [[0, 1], [2, 0]]  # inset, vents, split plates
for cy in range(CELLS):
    for cx in range(CELLS):
        x0, y0 = cx * cell + seam, cy * cell + seam
        x1, y1 = (cx + 1) * cell - seam, (cy + 1) * cell - seam
        d = box_sdf(x, y, x0, y0, x1, y1)
        inside = d < 0
        covered |= inside
        b = bevel(d, 10)
        height = np.where(inside, np.minimum(height, 0.55 + 0.45 * b), height)
        # Panel tone and wear vary panel to panel.
        tone = np.where(inside, tone * rng.uniform(0.93, 1.05), tone)
        kind = KINDS[cy][cx]
        if kind == 0:  # an inset sub-panel
            m = 48
            d2 = box_sdf(x, y, x0 + m, y0 + m, x1 - m, y1 - m)
            height = np.where(d2 < 0, height - 0.12 * bevel(d2, 6), height)
            occl = np.where(np.abs(d2) < 3, occl * 0.8, occl)
        elif kind == 1:  # vent slots
            vx0, vx1 = x0 + 70, x1 - 70
            for i in range(6):
                sy = y0 + 150 + i * 26
                d2 = box_sdf(x, y, vx0, sy, vx1, sy + 10)
                height = np.where(d2 < 0, height - 0.35 * bevel(d2, 3), height)
                occl = np.where(d2 < 0, occl * 0.55, occl)
                rough = np.where(d2 < 0, 0.8, rough)
        else:  # a split into two plates
            mid = (y0 + y1) / 2
            d2 = np.abs(y - mid) - 2
            height = np.where((d2 < 0) & inside, height - 0.25, height)
            occl = np.where((d2 < 2) & inside, occl * 0.75, occl)
        # Corner bolts.
        for bx, by in ((x0 + 22, y0 + 22), (x1 - 22, y0 + 22), (x0 + 22, y1 - 22), (x1 - 22, y1 - 22)):
            r = np.hypot(x - bx, y - by)
            height = np.where(r < 7, height + 0.08 * np.sqrt(np.clip(1 - (r / 7) ** 2, 0, 1)), height)
            occl = np.where((r > 6) & (r < 9), occl * 0.85, occl)

# Seams: deep, dark and rough.
in_seam = ~covered
height = np.where(in_seam, 0.0, height)
occl = np.where(in_seam, 0.35, occl)
rough = np.where(in_seam, 0.85, rough)

# Fine grime: low-frequency noise (upsampled random), darker near seams.
def noise(scale, amp):
    small = rng.random((N // scale, N // scale)).astype(np.float32)
    img = Image.fromarray((small * 255).astype(np.uint8)).resize((N, N), Image.BICUBIC)
    return (np.asarray(img, np.float32) / 255 - 0.5) * amp

grime = noise(64, 0.10) + noise(16, 0.06) + noise(4, 0.03)
blur_occl = np.asarray(Image.fromarray((occl * 255).astype(np.uint8)).resize((N // 8, N // 8), Image.BILINEAR)
                       .resize((N, N), Image.BICUBIC), np.float32) / 255
albedo = np.clip(0.78 * tone * (0.75 + 0.25 * blur_occl) + grime, 0, 1)
rough = np.clip(rough + grime * 0.8, 0.2, 0.95)

# Normal map from the height (tangent space, +Y up, as Godot reads it).
h = height * 6.0
gx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * 0.5
gy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * 0.5
nrm = np.dstack([-gx, gy, np.ones_like(h)])
nrm /= np.linalg.norm(nrm, axis=2, keepdims=True)

OUT.mkdir(parents=True, exist_ok=True)
gray = (albedo * 255).astype(np.uint8)
Image.fromarray(np.dstack([gray, gray, (np.clip(albedo * 1.02, 0, 1) * 255).astype(np.uint8)])).save(OUT / "station_panel_albedo.png")
Image.fromarray(((nrm * 0.5 + 0.5) * 255).astype(np.uint8)).save(OUT / "station_panel_normal.png")
orm = np.dstack([occl, rough, np.zeros_like(occl)])
Image.fromarray((np.clip(orm, 0, 1) * 255).astype(np.uint8)).save(OUT / "station_panel_orm.png")
print("wrote", *(OUT / f"station_panel_{k}.png" for k in ("albedo", "normal", "orm")))
