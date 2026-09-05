"""Generate favicon and PWA icons for MYCOSIX."""
import os

from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.abspath(__file__))
WEB = os.path.join(ROOT, "..", "web")
os.makedirs(os.path.join(WEB, "icons"), exist_ok=True)

FOREST = (47, 61, 44)
MOSS = (74, 93, 68)
CREAM = (245, 241, 232)
CAP = (238, 231, 218)


def draw_mark(size, background=None):
    """A stylised 'M' whose serifs read as mushroom caps on a moss tile."""
    im = Image.new("RGBA", (size, size), background if background else (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    u = size / 512.0
    # moss rounded tile
    r = int(96 * u)
    if background is None:
        d.rounded_rectangle([r, r, size - r, size - r], radius=int(120 * u), fill=MOSS)
    else:
        d.rounded_rectangle([r, r, size - r, size - r], radius=int(120 * u), fill=FOREST)
    # left mushroom cap (part of the M's left serif)
    d.pieslice(
        [96 * u, 120 * u, 250 * u, 300 * u],
        180, 360, fill=CAP,
    )
    # right mushroom cap (part of the M's right serif)
    d.pieslice(
        [262 * u, 120 * u, 416 * u, 300 * u],
        180, 360, fill=CAP,
    )
    # middle peak of the M
    d.polygon(
        [
            (256 * u - 34 * u, 120 * u),
            (256 * u + 34 * u, 120 * u),
            (256 * u, 240 * u),
        ],
        fill=CAP,
    )
    # stems — the M's legs
    d.rounded_rectangle([120 * u, 250 * u, 178 * u, 400 * u], radius=24 * u, fill=CAP)
    d.rounded_rectangle([334 * u, 250 * u, 392 * u, 400 * u], radius=24 * u, fill=CAP)
    # subtle darker rim on caps
    d.arc([96 * u, 120 * u, 250 * u, 300 * u], 180, 360, fill=(186, 170, 148), width=int(10 * u))
    d.arc([262 * u, 120 * u, 416 * u, 300 * u], 180, 360, fill=(186, 170, 148), width=int(10 * u))
    return im


def save_png(im, path):
    im.save(path)
    print("icon", os.path.relpath(path, ROOT), im.size)


if __name__ == "__main__":
    mark = draw_mark(512, background=CREAM)
    save_png(mark, os.path.join(WEB, "favicon.png"))
    for s in (192, 512):
        im = draw_mark(s)
        save_png(im, os.path.join(WEB, "icons", f"Icon-{s}.png"))
    for s in (192, 512):
        # maskable: full-bleed forest tile so the icon never gets clipped
        im = draw_mark(s, background=FOREST)
        save_png(im, os.path.join(WEB, "icons", f"Icon-maskable-{s}.png"))
    print("ALL DONE")
