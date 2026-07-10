#!/usr/bin/env python3
"""Bake the martian landscape texture from a real Curiosity panorama.

Downloads PIA26671 (Curiosity Views Gale Crater's Rim, NASA/JPL-Caltech/MSSS,
public domain), crops the full composition — sky, crater-rim range, plain,
foreground crags — then:

  * cuts the sky away along the skyline (per-column red-vs-blue detection,
    median + low-pass smoothed, feathered) so the range silhouettes over stars
  * grades it toward dusk: dusky peaks brightening into a warm rust plain
  * vignettes the plain below the floor line for depth and UI legibility
  * wrap-blends the ends so the strip tiles seamlessly

Writes mars_land.png. In Main.gd the texture is split at LAND_SPLIT (the
floor row): mountains render behind the parked rockets, the plain renders in
front so pillar bottoms sink into the ground.

Run from the repo root:  python3 tools/make_mars_land.py
"""

import io
import statistics
import urllib.request

from PIL import Image, ImageEnhance

SOURCE = "https://images-assets.nasa.gov/image/PIA26671/PIA26671~orig.jpg"
FLOOR_ROW = 235   # keep in sync with LAND_SPLIT in Main.gd (235/450)


def tileable_rgba(im: Image.Image, fade_frac: float = 0.10) -> Image.Image:
    # wrap-blend: crossfade the strip's tail over its head so it tiles seamlessly
    w, h = im.size
    f = int(w * fade_frac)
    body = im.crop((0, 0, w - f, h))
    head = body.crop((0, 0, f, h))
    tail = im.crop((w - f, 0, w, h))
    mask = Image.new("L", (f, 1))
    mask.putdata([int(255 * x / (f - 1)) for x in range(f)])  # 0=tail .. 255=head
    body.paste(Image.composite(head, tail, mask.resize((f, h))), (0, 0))
    return body


def main() -> None:
    with urllib.request.urlopen(SOURCE) as r:
        img = Image.open(io.BytesIO(r.read())).convert("RGB")

    # inside the mosaic scallops: sky -> rim range -> plain -> foreground crags
    band = img.crop((2400, 400, 20000, 2200)).resize((4400, 450), Image.LANCZOS)
    W, H = band.size
    px = band.load()

    # skyline: rock is red-shifted vs the blue-grey sky; require a run so
    # haze speckle can't fake an edge
    RUN = 14
    skylines = []
    for x in range(W):
        skyline, run = H, 0
        for y in range(H):
            r, g, b = px[x, y]
            if (r - b) > -15:
                run += 1
                if run >= RUN:
                    skyline = y - RUN + 1
                    break
            else:
                run = 0
        skylines.append(skyline)
    K = 10
    sm = [int(statistics.median(skylines[max(0, x - K):x + K + 1])) for x in range(W)]
    LP = 30  # the range is distant — fine teeth are noise at game scale
    sm = [sum(sm[max(0, x - LP):x + LP + 1]) / len(sm[max(0, x - LP):x + LP + 1]) for x in range(W)]

    alpha = Image.new("L", (W, H), 255)
    al = alpha.load()
    FEATHER = 5
    for x in range(W):
        top = int(sm[x])
        for y in range(top):
            al[x, y] = 0
        for f in range(FEATHER):
            yy = top - 1 - f
            if 0 <= yy < H:
                al[x, yy] = int(255 * (1 - (f + 1) / (FEATHER + 1)))

    # dusk grade: dusky peaks brighten into the warm plain; vignette below floor
    avg_sky = sum(sm) / len(sm)
    for y in range(H):
        if y < FLOOR_ROW:
            t = max(0.0, (y - avg_sky) / (FLOOR_ROW - avg_sky))
            dark = 0.55 + 0.45 * min(1.0, t)
        else:
            dark = 1.0 - 0.30 * ((y - FLOOR_ROW) / (H - FLOOR_ROW))
        for x in range(W):
            r, g, b = px[x, y]
            px[x, y] = (int(min(255, r * 1.20 * dark)),
                        int(min(255, g * 0.95 * dark)),
                        int(min(255, b * 0.80 * dark)))

    band = ImageEnhance.Color(band).enhance(1.12)
    band.putalpha(alpha)
    tileable_rgba(band).resize((4000, 450), Image.LANCZOS).save("mars_land.png")
    print("wrote mars_land.png")


if __name__ == "__main__":
    main()
