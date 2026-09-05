"""Generate MYCOSIX brand imagery with pure Python + Pillow.

All imagery is procedural (mushroom clusters, moss, straw, powder, jar, bag,
box) so the site ships with no broken or missing images and no fabricated
photographs of real people. Oyster mushrooms are drawn as layered fan-shaped
caps growing in clusters.
"""
import math
import os
import random

from PIL import Image, ImageDraw, ImageFilter, ImageFont

W = 1400
H = 1000

OUT_IMAGES = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "images")
OUT_PRODUCTS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "products")
os.makedirs(OUT_IMAGES, exist_ok=True)
os.makedirs(OUT_PRODUCTS, exist_ok=True)

rng = random.Random(42)

# ---------- palette ----------
CREAM = (245, 241, 232)
CREAM_DEEP = (236, 229, 214)
FOREST = (47, 61, 44)
MOSS = (74, 93, 68)
MOSS_MID = (108, 128, 96)
MOSS_SOFT = (220, 228, 211)
EARTH = (138, 125, 108)
CHARCOAL = (35, 37, 31)

CAP_LIGHT = (238, 231, 218)
CAP_MID = (218, 206, 187)
CAP_DARK = (186, 170, 148)
GILL = (242, 235, 222)


def clamp(v, a, b):
    return max(a, min(b, v))


def hex_color(rgb, a=255):
    r, g, b = rgb
    return "#" + format((r << 16) | (g << 8) | b, "06x")


# ---------- drawing primitives ----------

def radial_light(img, cx, cy, radius, color, alpha, edge=0.8):
    """Soft radial glow overlay."""
    ov = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(ov)
    steps = 40
    for i in range(steps, 0, -1):
        t = i / steps
        r = radius * t
        a = int(alpha * (1 - t) ** edge)
        d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=color + (a,))
    img.alpha_composite(ov)


def grain(img, amount=10, alpha=22):
    """Film-like grain overlay."""
    noise = Image.effect_noise(img.size, amount).convert("L")
    ov = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ov.paste(noise, (0, 0))
    mask = ov.split()[0].point(lambda p: p * alpha // 255)
    ov.putalpha(mask)
    img.alpha_composite(ov)


def vignette(img, strength=0.42):
    ov = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(ov)
    w, h = img.size
    maxd = math.hypot(w / 2, h / 2)
    steps = 60
    for i in range(steps):
        t = i / steps
        r = maxd * (0.25 + 0.75 * t)
        a = int(255 * strength * (t ** 3))
        d.ellipse([w / 2 - r, h / 2 - r, w / 2 + r, h / 2 + r], outline=(0, 0, 0, a), width=2)
    img.alpha_composite(ov)


def base(w=W, h=H, color=CREAM):
    im = Image.new("RGBA", (w, h), color)
    return im


# ---------- moss / foliage ----------

def paint_moss(im, box, density=1.0):
    """Soft mossy green blobs filling box."""
    d = ImageDraw.Draw(im)
    x0, y0, x1, y1 = box
    n = int(90 * density)
    for _ in range(n):
        x = rng.uniform(x0, x1)
        y = rng.uniform(y0, y1)
        r = rng.uniform(8, 40) * density
        shade = rng.choice([MOSS, MOSS_MID, FOREST])
        a = rng.randint(90, 170)
        ov = Image.new("RGBA", im.size, (0, 0, 0, 0))
        dd = ImageDraw.Draw(ov)
        for i in range(3, 0, -1):
            rr = r * i / 3
            aa = a // (4 - i)
            dd.ellipse([x - rr, y - rr, x + rr, y + rr], fill=shade + (aa,))
        im.alpha_composite(ov)


def paint_straw(im, box, density=1.0):
    """Warm straw lines (substrate)."""
    d = ImageDraw.Draw(im)
    x0, y0, x1, y1 = box
    n = int(260 * density)
    for _ in range(n):
        x = rng.uniform(x0, x1)
        y = rng.uniform(y0, y1)
        ang = rng.uniform(-0.5, 0.5)
        ln = rng.uniform(8, 30)
        color = rng.choice([(203, 181, 137), (187, 163, 119), (216, 195, 152), (168, 145, 104)])
        d.line(
            [x, y, x + ln * math.cos(ang), y + ln * math.sin(ang)],
            fill=color + (rng.randint(120, 190),),
            width=rng.randint(1, 2),
        )


def paint_gills(im, cx, cy, r, color=GILL):
    """Radiating gill lines under a cap."""
    d = ImageDraw.Draw(im)
    for i in range(14):
        ang = math.pi + (i - 7) * 0.14 + rng.uniform(-0.03, 0.03)
        x2 = cx + math.cos(ang) * r * 0.8
        y2 = cy + math.sin(ang) * r * 0.8
        d.line([cx, cy, x2, y2], fill=color + (150,), width=rng.randint(1, 2))


def paint_oyster_cap(im, cx, cy, r, shade_light, shade_mid, shade_dark):
    """A fan/pleurotoid cap viewed from the side — the oyster signature."""
    ov = Image.new("RGBA", im.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(ov)
    # cap body (ellipse, top half)
    d.pieslice([cx - r, cy - r * 1.15, cx + r, cy + r * 0.9], 180, 360, fill=shade_light + (255,))
    d.pieslice([cx - r * 0.92, cy - r * 1.05, cx + r * 0.92, cy + r * 1.0], 180, 360, fill=shade_mid + (255,))
    # darker rim toward the stem
    d.ellipse([cx - r * 0.7, cy - r * 0.25, cx + r * 0.7, cy + r * 0.75], fill=shade_dark + (255,))
    # subtle top sheen
    d.pieslice([cx - r * 0.8, cy - r * 1.1, cx + r * 0.8, cy - r * 0.15], 190, 350, fill=CAP_LIGHT + (70,))
    im.alpha_composite(ov)


def paint_oyster_cluster(im, cx, cy, scale=1.0, n=5, seed=None):
    """Cluster of overlapping oyster caps, always inside the canvas."""
    local = random.Random(seed if seed is not None else 7)
    w, h = im.size
    for i in range(n):
        spread = scale * rng.uniform(0.4, 0.9)
        ang = rng.uniform(0, math.pi * 2)
        x = cx + math.cos(ang) * spread
        y = cy + math.sin(ang) * spread * 0.7
        r = scale * rng.uniform(0.18, 0.32)
        # keep fully on canvas
        x = clamp(x, r, w - r)
        y = clamp(y, r * 0.9, h - r)
        shade = local.choice(
            [
                (CAP_LIGHT, CAP_MID, CAP_DARK),
                (CAP_MID, CAP_DARK, (150, 132, 110)),
                (CAP_LIGHT, CAP_MID, CAP_MID),
            ]
        )
        paint_oyster_cap(im, x, y, r, shade[0], shade[1], shade[2])
        paint_gills(im, x, y, r)


def grow_bed(im, cx, cy, w_bed, n, seed):
    """A bed of mushrooms: dark base, straw, then clusters."""
    d = ImageDraw.Draw(im)
    x0, y0, x1, y1 = cx - w_bed / 2, cy - 90, cx + w_bed / 2, cy + 90
    ov = Image.new("RGBA", im.size, (0, 0, 0, 0))
    dd = ImageDraw.Draw(ov)
    dd.ellipse([x0, y0 - 20, x1, y1 + 20], fill=(40, 44, 38, 120))
    im.alpha_composite(ov)
    paint_straw(im, (x0, y0 - 10, x1, y1), density=0.7)
    paint_moss(im, (x0, y0 - 40, x1, y1 + 10), density=0.5)
    paint_oyster_cluster(im, cx - w_bed * 0.25, y0, scale=90, n=n // 2, seed=seed)
    paint_oyster_cluster(im, cx + w_bed * 0.25, y0 + 12, scale=80, n=n // 2, seed=seed + 1)
    paint_oyster_cluster(im, cx, y0 - 10, scale=70, n=max(1, n // 3), seed=seed + 2)


# ---------- scenes ----------

def scene_hero():
    im = base()
    # deep moss gradient background
    ov = Image.new("RGBA", im.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(ov)
    for y in range(0, im.size[1], 4):
        t = y / im.size[1]
        c = (
            int(46 + 30 * (1 - t)),
            int(58 + 34 * (1 - t)),
            int(48 + 26 * (1 - t)),
        )
        d.rectangle([0, y, im.size[0], y + 4], fill=c + (255,))
    im.alpha_composite(ov)
    # glowing light from top-right
    radial_light(im, int(W * 0.78), int(H * 0.22), 900, (200, 215, 180), 90, edge=2.2)
    # bottom moss floor
    paint_moss(im, (0, H * 0.7, W, H), density=1.6)
    paint_straw(im, (0, H * 0.66, W, H * 0.8), density=0.5)
    # a large cluster near center-left, in the light
    paint_oyster_cluster(im, int(W * 0.36), int(H * 0.62), scale=250, n=11, seed=11)
    paint_oyster_cluster(im, int(W * 0.55), int(H * 0.72), scale=160, n=6, seed=12)
    # mist
    ov = Image.new("RGBA", im.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(ov)
    d.ellipse([-200, H * 0.45, W + 200, H * 0.95], fill=(235, 232, 215, 40))
    im.alpha_composite(ov)
    vignette(im, 0.35)
    grain(im, 12, 26)
    return im


def scene_moss_close():
    im = base()
    ov = Image.new("RGBA", im.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(ov)
    for y in range(0, im.size[1], 6):
        t = y / im.size[1]
        c = (
            int(50 + 36 * (1 - t)),
            int(64 + 40 * (1 - t)),
            int(50 + 30 * (1 - t)),
        )
        d.rectangle([0, y, im.size[0], y + 6], fill=c + (255,))
    im.alpha_composite(ov)
    radial_light(im, int(W * 0.2), int(H * 0.2), 700, (190, 210, 170), 80, edge=2)
    paint_moss(im, (0, 0, W, H), density=2.0)
    paint_oyster_cluster(im, int(W * 0.5), int(H * 0.6), scale=190, n=8, seed=21)
    paint_oyster_cluster(im, int(W * 0.72), int(H * 0.5), scale=110, n=4, seed=22)
    grain(im, 10, 22)
    vignette(im, 0.4)
    return im


def scene_harvest_hands():
    im = base(W, H)
    d = ImageDraw.Draw(im)
    # warm skin-toned hands (abstract) lifting a cluster
    hand1 = (212, 168, 132)
    hand2 = (196, 150, 116)
    ov = Image.new("RGBA", im.size, (0, 0, 0, 0))
    dd = ImageDraw.Draw(ov)
    # left palm
    dd.ellipse([W * 0.16, H * 0.58, W * 0.42, H * 0.78], fill=hand1 + (255,))
    # right palm
    dd.ellipse([W * 0.58, H * 0.58, W * 0.84, H * 0.78], fill=hand2 + (255,))
    # fingers
    for fx in [0.2, 0.26, 0.32]:
        dd.rounded_rectangle([W * fx, H * 0.5, W * (fx + 0.045), H * 0.66], radius=18, fill=hand1 + (255,))
    for fx in [0.64, 0.70, 0.76]:
        dd.rounded_rectangle([W * fx, H * 0.5, W * (fx + 0.045), H * 0.66], radius=18, fill=hand2 + (255,))
    im.alpha_composite(ov)
    # cluster cradled between
    paint_oyster_cluster(im, int(W * 0.5), int(H * 0.6), scale=210, n=9, seed=31)
    paint_straw(im, (0, H * 0.75, W, H), density=0.5)
    paint_moss(im, (0, H * 0.78, W, H), density=1.0)
    grain(im, 11, 24)
    vignette(im, 0.38)
    return im


def scene_shelf():
    im = base()
    # warm light wall
    ov = Image.new("RGBA", im.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(ov)
    d.rectangle([0, 0, W, int(H * 0.32)], fill=(212, 196, 168, 90))
    im.alpha_composite(ov)
    # shelf board
    d = ImageDraw.Draw(im)
    d.rounded_rectangle([0, int(H * 0.52), W, int(H * 0.60)], radius=10, fill=(120, 100, 78))
    d.rounded_rectangle([0, int(H * 0.60), W, int(H * 0.615)], radius=6, fill=(96, 80, 62))
    # baskets
    bx = [int(W * 0.16), int(W * 0.5), int(W * 0.82)]
    for cx in bx:
        dd = ImageDraw.Draw(im)
        dd.ellipse([cx - 150, int(H * 0.38), cx + 150, int(H * 0.58)], fill=(150, 128, 100))
        dd.ellipse([cx - 140, int(H * 0.36), cx + 140, int(H * 0.52)], fill=(168, 146, 116))
        paint_straw(im, (cx - 130, int(H * 0.36), cx + 130, int(H * 0.52)), density=0.6)
        paint_oyster_cluster(im, cx, int(H * 0.36), scale=90, n=4, seed=41 + cx)
    grain(im, 10, 22)
    vignette(im, 0.4)
    return im


def scene_dark_portrait():
    im = base()
    ov = Image.new("RGBA", im.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(ov)
    for y in range(0, im.size[1], 5):
        t = y / im.size[1]
        c = (int(22 + 18 * t), int(26 + 20 * t), int(22 + 16 * t))
        d.rectangle([0, y, im.size[0], y + 5], fill=c + (255,))
    im.alpha_composite(ov)
    radial_light(im, int(W * 0.5), int(H * 0.3), 640, (200, 205, 175), 55, edge=2.4)
    paint_oyster_cluster(im, int(W * 0.5), int(H * 0.58), scale=210, n=8, seed=51)
    grain(im, 14, 30)
    vignette(im, 0.5)
    return im


def scene_packaging():
    im = base()
    ov = Image.new("RGBA", im.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(ov)
    for y in range(0, im.size[1], 5):
        t = y / im.size[1]
        c = (int(230 - 60 * t), int(222 - 60 * t), int(204 - 50 * t))
        d.rectangle([0, y, im.size[0], y + 5], fill=c + (255,))
    im.alpha_composite(ov)
    radial_light(im, int(W * 0.5), int(H * 0.3), 700, (255, 252, 244), 90, edge=1.8)
    # kraft box
    d = ImageDraw.Draw(im)
    d.rounded_rectangle([int(W * 0.3), int(H * 0.34), int(W * 0.7), int(H * 0.72)], radius=14, fill=(196, 168, 126))
    d.rounded_rectangle([int(W * 0.3), int(H * 0.34), int(W * 0.7), int(H * 0.72)], radius=14, outline=(160, 136, 100), width=3)
    d.rounded_rectangle([int(W * 0.33), int(H * 0.4), int(W * 0.67), int(H * 0.5)], radius=10, fill=(176, 148, 110))
    d.text((int(W * 0.5), int(H * 0.45)), "MYCOSIX", fill=(70, 62, 48), anchor="mm")
    # lid
    d.rounded_rectangle([int(W * 0.32), int(H * 0.30), int(W * 0.68), int(H * 0.36)], radius=8, fill=(176, 148, 110))
    # mushrooms peeking out
    paint_oyster_cluster(im, int(W * 0.5), int(H * 0.32), scale=110, n=5, seed=61)
    grain(im, 9, 20)
    vignette(im, 0.32)
    return im


def scene_fry():
    im = base()
    ov = Image.new("RGBA", im.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(ov)
    for y in range(0, im.size[1], 5):
        t = y / im.size[1]
        c = (int(206 + 22 * t), int(178 + 26 * t), int(140 + 30 * t))
        d.rectangle([0, y, im.size[0], y + 5], fill=c + (255,))
    im.alpha_composite(ov)
    radial_light(im, int(W * 0.5), int(H * 0.4), 650, (255, 240, 200), 70, edge=2)
    # pan
    d = ImageDraw.Draw(im)
    d.ellipse([int(W * 0.24), int(H * 0.5), int(W * 0.76), int(H * 0.78)], fill=(56, 56, 54))
    d.ellipse([int(W * 0.27), int(H * 0.52), int(W * 0.73), int(H * 0.76)], fill=(80, 78, 74))
    # sizzling slices
    for i in range(12):
        a = rng.uniform(0, math.pi * 2)
        rr = rng.uniform(0.05, 0.22)
        x = W * 0.5 + math.cos(a) * rr * W
        y = H * 0.64 + math.sin(a) * rr * H * 0.7
        s = rng.uniform(14, 26)
        dd = ImageDraw.Draw(im)
        dd.ellipse([x - s, y - s * 0.6, x + s, y + s * 0.6], fill=rng.choice([(196, 160, 96), (176, 138, 82), (214, 180, 120)]))
        dd.ellipse([x - s * 0.5, y - s * 0.3, x + s * 0.5, y + s * 0.3], fill=(240, 220, 170))
    grain(im, 10, 24)
    vignette(im, 0.4)
    return im


def scene_dried():
    im = base()
    ov = Image.new("RGBA", im.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(ov)
    for y in range(0, im.size[1], 6):
        t = y / im.size[1]
        c = (int(218 - 30 * t), int(204 - 30 * t), int(178 - 26 * t))
        d.rectangle([0, y, im.size[0], y + 6], fill=c + (255,))
    im.alpha_composite(ov)
    radial_light(im, int(W * 0.5), int(H * 0.35), 620, (250, 244, 228), 80, edge=2)
    d = ImageDraw.Draw(im)
    # glass jar
    d.rounded_rectangle([int(W * 0.38), int(H * 0.34), int(W * 0.62), int(H * 0.74)], radius=22, fill=(238, 232, 214))
    d.rounded_rectangle([int(W * 0.38), int(H * 0.34), int(W * 0.62), int(H * 0.74)], radius=22, outline=(190, 180, 160), width=3)
    # lid
    d.rounded_rectangle([int(W * 0.36), int(H * 0.28), int(W * 0.64), int(H * 0.35)], radius=8, fill=(140, 116, 88))
    # dried slices inside
    for i in range(18):
        x = rng.uniform(W * 0.40, W * 0.60)
        y = rng.uniform(H * 0.40, H * 0.70)
        s = rng.uniform(10, 20)
        dd = ImageDraw.Draw(im)
        dd.ellipse([x - s, y - s * 0.7, x + s, y + s * 0.7], fill=rng.choice([(180, 150, 100), (160, 130, 86), (200, 172, 120)]))
    # label
    d.rounded_rectangle([int(W * 0.41), int(H * 0.5), int(W * 0.59), int(H * 0.66)], radius=8, fill=(250, 246, 236))
    d.text((int(W * 0.5), int(H * 0.55)), "DRIED", fill=(120, 96, 64), anchor="mm", font=ImageFont.load_default())
    d.text((int(W * 0.5), int(H * 0.62)), "Oyster", fill=(120, 96, 64), anchor="mm", font=ImageFont.load_default())
    grain(im, 10, 22)
    vignette(im, 0.36)
    return im


def scene_powder():
    im = base()
    ov = Image.new("RGBA", im.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(ov)
    for y in range(0, im.size[1], 6):
        t = y / im.size[1]
        c = (int(222 - 26 * t), int(210 - 26 * t), int(186 - 20 * t))
        d.rectangle([0, y, im.size[0], y + 6], fill=c + (255,))
    im.alpha_composite(ov)
    radial_light(im, int(W * 0.5), int(H * 0.3), 600, (252, 248, 236), 85, edge=2)
    d = ImageDraw.Draw(im)
    # bowl + mound
    d.ellipse([int(W * 0.4), int(H * 0.56), int(W * 0.6), int(H * 0.74)], fill=(150, 132, 108))
    d.ellipse([int(W * 0.43), int(H * 0.56), int(W * 0.57), int(H * 0.68)], fill=(212, 200, 176))
    d.ellipse([int(W * 0.42), int(H * 0.5), int(W * 0.58), int(H * 0.62)], fill=(188, 174, 148))
    d.ellipse([int(W * 0.46), int(H * 0.52), int(W * 0.54), int(H * 0.58)], fill=(160, 146, 120))
    # scattered powder flecks
    for i in range(60):
        x = rng.uniform(W * 0.35, W * 0.65)
        y = rng.uniform(H * 0.62, H * 0.8)
        d.point((x, y), fill=(168, 152, 124))
    grain(im, 11, 24)
    vignette(im, 0.36)
    return im


def scene_pickle():
    im = base()
    ov = Image.new("RGBA", im.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(ov)
    for y in range(0, im.size[1], 5):
        t = y / im.size[1]
        c = (int(216 - 20 * t), int(182 - 24 * t), int(130 - 14 * t))
        d.rectangle([0, y, im.size[0], y + 5], fill=c + (255,))
    im.alpha_composite(ov)
    radial_light(im, int(W * 0.5), int(H * 0.32), 600, (255, 236, 190), 75, edge=2)
    d = ImageDraw.Draw(im)
    # jar
    d.rounded_rectangle([int(W * 0.34), int(H * 0.36), int(W * 0.66), int(H * 0.76)], radius=24, fill=(206, 168, 116))
    d.rounded_rectangle([int(W * 0.34), int(H * 0.36), int(W * 0.66), int(H * 0.76)], radius=24, outline=(172, 136, 92), width=3)
    d.rounded_rectangle([int(W * 0.32), int(H * 0.30), int(W * 0.68), int(H * 0.38)], radius=8, fill=(128, 96, 64))
    # chunks
    for i in range(14):
        x = rng.uniform(W * 0.37, W * 0.63)
        y = rng.uniform(H * 0.42, H * 0.72)
        s = rng.uniform(9, 18)
        dd = ImageDraw.Draw(im)
        dd.rounded_rectangle([x - s, y - s * 0.8, x + s, y + s * 0.8], radius=5, fill=rng.choice([(198, 138, 74), (186, 124, 62), (212, 158, 92)]))
    # spice flecks
    for i in range(80):
        x = rng.uniform(W * 0.36, W * 0.64)
        y = rng.uniform(H * 0.40, H * 0.74)
        d.point((x, y), fill=rng.choice([(120, 60, 30), (150, 90, 40), (90, 40, 20)]))
    grain(im, 11, 24)
    vignette(im, 0.38)
    return im


def scene_jar():
    im = base()
    ov = Image.new("RGBA", im.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(ov)
    for y in range(0, im.size[1], 5):
        t = y / im.size[1]
        c = (int(226 - 34 * t), int(216 - 32 * t), int(196 - 26 * t))
        d.rectangle([0, y, im.size[0], y + 5], fill=c + (255,))
    im.alpha_composite(ov)
    radial_light(im, int(W * 0.5), int(H * 0.3), 620, (255, 250, 240), 85, edge=2)
    d = ImageDraw.Draw(im)
    d.rounded_rectangle([int(W * 0.40), int(H * 0.36), int(W * 0.60), int(H * 0.72)], radius=20, fill=(240, 234, 218))
    d.rounded_rectangle([int(W * 0.40), int(H * 0.36), int(W * 0.60), int(H * 0.72)], radius=20, outline=(186, 176, 156), width=3)
    d.rounded_rectangle([int(W * 0.38), int(H * 0.30), int(W * 0.62), int(H * 0.37)], radius=8, fill=(146, 120, 90))
    for i in range(10):
        x = rng.uniform(W * 0.42, W * 0.58)
        y = rng.uniform(H * 0.42, H * 0.68)
        s = rng.uniform(12, 22)
        dd = ImageDraw.Draw(im)
        dd.ellipse([x - s, y - s * 0.7, x + s, y + s * 0.7], fill=rng.choice([(204, 178, 138), (188, 158, 118)]))
    grain(im, 9, 20)
    vignette(im, 0.34)
    return im


# ---------- renders ----------

SCENES = {
    "hero.jpg": scene_hero,
    "moss_close.jpg": scene_moss_close,
    "harvest_hands.jpg": scene_harvest_hands,
    "shelf.jpg": scene_shelf,
    "dark_portrait.jpg": scene_dark_portrait,
    "packaging.jpg": scene_packaging,
    "fry.jpg": scene_fry,
    "dried.jpg": scene_dried,
    "powder.jpg": scene_powder,
    "pickle.jpg": scene_pickle,
    "jar.jpg": scene_jar,
}

if __name__ == "__main__":
    for name, fn in SCENES.items():
        im = fn().convert("RGB")
        path = os.path.join(OUT_IMAGES, name)
        im.save(path, quality=88)
        print("images", name, im.size)

    # product images (reuse scenes + tighter crops)
    products = {
        "oyster_bouquet.jpg": "hero.jpg",
        "oyster_cluster.jpg": "moss_close.jpg",
        "oyster_harvest.jpg": "harvest_hands.jpg",
        "oyster_fry.jpg": "fry.jpg",
        "oyster_dried.jpg": "dried.jpg",
        "oyster_powder.jpg": "powder.jpg",
        "oyster_pickle.jpg": "pickle.jpg",
    }
    for name, src in products.items():
        src_path = os.path.join(OUT_IMAGES, src)
        im = Image.open(src_path).convert("RGB")
        w, h = im.size
        # center crop to 4:3 then resize to 900x675
        target = (900, 675)
        ar_src = w / h
        ar_t = target[0] / target[1]
        if ar_src > ar_t:
            nw = int(h * ar_t)
            x0 = (w - nw) // 2
            im = im.crop((x0, 0, x0 + nw, h))
        else:
            nh = int(w / ar_t)
            y0 = (h - nh) // 2
            im = im.crop((0, y0, w, y0 + nh))
        im = im.resize(target, Image.LANCZOS)
        im.save(os.path.join(OUT_PRODUCTS, name), quality=88)
        print("products", name, im.size)

    print("ALL DONE")
