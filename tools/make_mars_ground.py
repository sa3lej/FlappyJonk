#!/usr/bin/env python3
"""Bake the martian ground textures from real NASA rover photos.

Downloads two Curiosity Mastcam shots from the NASA image library, crops a
band from each, wrap-blends the ends so they tile seamlessly, warms the
color grade toward classic rust, and writes:

  mars_ground.jpg  — the near ground strip (PIA11242)
  mars_far.jpg     — the distant dune sea on the horizon (PIA20755)

Run from the repo root:  python3 tools/make_mars_ground.py
Both images are NASA/JPL-Caltech/MSSS, public domain.
"""

import io
import urllib.request

from PIL import Image, ImageEnhance

SOURCES = {
    "PIA11242": "https://images-assets.nasa.gov/image/PIA11242/PIA11242~orig.jpg",
    "PIA20755": "https://images-assets.nasa.gov/image/PIA20755/PIA20755~orig.jpg",
}


def fetch(pia: str) -> Image.Image:
    with urllib.request.urlopen(SOURCES[pia]) as r:
        return Image.open(io.BytesIO(r.read())).convert("RGB")


def tileable(img: Image.Image, fade_frac: float = 0.12) -> Image.Image:
    # wrap-blend: crossfade the strip's tail over its head so it tiles seamlessly
    w, h = img.size
    f = int(w * fade_frac)
    body = img.crop((0, 0, w - f, h))
    head = body.crop((0, 0, f, h))
    tail = img.crop((w - f, 0, w, h))
    mask = Image.new("L", (f, 1))
    mask.putdata([int(255 * x / (f - 1)) for x in range(f)])  # 0=tail .. 255=head
    body.paste(Image.composite(head, tail, mask.resize((f, h))), (0, 0))
    return body


def warm(img: Image.Image, r=1.22, g=0.97, b=0.82, sat=1.15) -> Image.Image:
    ch = list(img.split())
    ch[0] = ch[0].point(lambda v: min(255, int(v * r)))
    ch[1] = ch[1].point(lambda v: min(255, int(v * g)))
    ch[2] = ch[2].point(lambda v: min(255, int(v * b)))
    return ImageEnhance.Color(Image.merge("RGB", ch)).enhance(sat)


def main() -> None:
    near = fetch("PIA11242")  # 4336x2224, rippled ground with rock slabs
    band = near.crop((0, 350, 4336, 1450)).resize((2600, 660), Image.LANCZOS)
    warm(tileable(band)).save("mars_ground.jpg", quality=87)

    far = fetch("PIA20755")  # 9091x1089 panorama, dark dune ripples
    band2 = far.crop((0, 430, 7500, 1030)).resize((2000, 160), Image.LANCZOS)
    warm(tileable(band2), r=1.18, g=0.92, b=0.78).save("mars_far.jpg", quality=87)
    print("wrote mars_ground.jpg + mars_far.jpg")


if __name__ == "__main__":
    main()
