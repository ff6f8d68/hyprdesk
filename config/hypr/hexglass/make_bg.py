#!/usr/bin/env python3
"""
Hexglass background generator.

Renders the desktop gradient as a full-screen image:
    radial-gradient(circle at 50% 100%,
        #ac81ff 0%, #5d458f 25%, #1a1435 65%, #0a0715 100%)
plus the sparse star field from the HTML reference (4 stars per 300x300 tile,
opacity ~0.4). Output is used by hyprlock (background path) and the GDM
greeter (baked into the theme gresource).
"""

import os
import random
from PIL import Image

W, H = 1920, 1080
OUT = os.path.join(os.path.expanduser("~"), ".config", "hypr", "hexglass", "hex-bg.png")

# Stops exactly as in the HTML, with byte values
STOPS = [
    (0.00, (0xAC, 0x81, 0xFF)),  # ac81ff
    (0.25, (0x5D, 0x45, 0x8F)),  # 5d458f
    (0.65, (0x1A, 0x14, 0x35)),  # 1a1435
    (1.00, (0x0A, 0x07, 0x15)),  # 0a0715
]

CX, CY = W / 2.0, float(H)          # circle at 50% 100%
RADIUS = (CX ** 2 + H ** 2) ** 0.5  # distance to the farthest corner


def gradient_row(width):
    """One scanline of the radial gradient."""
    row = bytearray(width * 3)
    for x in range(width):
        t = ((x - CX) ** 2 + (0 - CY) ** 2) ** 0.5 / RADIUS
        # find surrounding stops
        for i in range(len(STOPS) - 1):
            t0, c0 = STOPS[i]
            t1, c1 = STOPS[i + 1]
            if t <= t1 or i == len(STOPS) - 2:
                f = 0.0 if t1 == t0 else min(max((t - t0) / (t1 - t0), 0.0), 1.0)
                r = int(c0[0] + (c1[0] - c0[0]) * f)
                g = int(c0[1] + (c1[1] - c0[1]) * f)
                b = int(c0[2] + (c1[2] - c0[2]) * f)
                break
        o = x * 3
        row[o] = r
        row[o + 1] = g
        row[o + 2] = b
    return bytes(row)


def main():
    img = Image.new("RGB", (W, H))
    px = img.load()
    for y in range(H):
        row = gradient_row(W)
        for x in range(W):
            o = x * 3
            px[x, y] = (row[o], row[o + 1], row[o + 2])

    # ── star field: 4 stars per 300x300 tile (like the HTML), scaled opacity ──
    stars = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    spx = stars.load()
    rng = random.Random(0xA5C81FF)  # deterministic: same sky every boot
    tiles_x = W // 300 + 1
    tiles_y = H // 300 + 1
    for ty in range(tiles_y):
        for tx in range(tiles_x):
            ox, oy = tx * 300, ty * 300
            # anchor points from the HTML: (20,30) (40,70) (90,40) (160,120)
            # plus jitter so the tiling doesn't read as a grid
            for ax, ay, big in ((20, 30, False), (40, 70, False),
                                (90, 40, True), (160, 120, False)):
                x = ox + ax + rng.randint(-8, 8)
                y = oy + ay + rng.randint(-8, 8)
                if not (0 <= x < W and 0 <= y < H):
                    continue
                alpha = rng.randint(90, 200)          # HTML layer is 0.4 overall
                size = 2 if (big and rng.random() < 0.5) else 1
                if size == 1:
                    spx[x, y] = (255, 255, 255, alpha)
                else:
                    for dx in (0, 1):
                        for dy in (0, 1):
                            if 0 <= x + dx < W and 0 <= y + dy < H:
                                a = alpha if (dx == dy) else alpha // 2
                                spx[x + dx, y + dy] = (255, 255, 255, a)

    img = Image.alpha_composite(img.convert("RGBA"), stars).convert("RGB")
    img.save(OUT, "PNG")
    print("wrote", OUT, img.size)


if __name__ == "__main__":
    main()
