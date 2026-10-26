#!/usr/bin/env python3
"""Draws the app icon and the DMG window background into Resources/.

Needs Pillow and the Inter font. The outputs are committed, so this only has
to run again after changing the artwork:

    python3 scripts/make-assets.py [path/to/Inter-SemiBold.otf]
"""
import math
import sys
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

RESOURCES = Path(__file__).resolve().parent.parent / "Resources"
FONT = sys.argv[1] if len(sys.argv) > 1 else "/usr/share/fonts/opentype/inter/Inter-SemiBold.otf"

# DMG window size in points, and where Finder places the two icons.
DMG_SIZE = (660, 400)
APP_POS = (180, 185)
APPLICATIONS_POS = (480, 185)


def vertical_gradient(size, top, bottom):
    w, h = size
    img = Image.new("RGB", size)
    draw = ImageDraw.Draw(img)
    for y in range(h):
        t = y / max(h - 1, 1)
        draw.line([(0, y), (w, y)], fill=tuple(round(a + (b - a) * t) for a, b in zip(top, bottom)))
    return img


def rounded_mask(size, box, radius, scale=4):
    """Antialiased rounded-rectangle mask, drawn large and scaled down."""
    big = Image.new("L", (size[0] * scale, size[1] * scale), 0)
    ImageDraw.Draw(big).rounded_rectangle([c * scale for c in box], radius * scale, fill=255)
    return big.resize(size, Image.LANCZOS)


def draw_x(size, center, arm, width, scale=4):
    """Antialiased X made of two round-capped strokes, as an L mask."""
    big = Image.new("L", (size[0] * scale, size[1] * scale), 0)
    draw = ImageDraw.Draw(big)
    cx, cy = center[0] * scale, center[1] * scale
    a, w = arm * scale, width * scale
    for dx in (a, -a):
        p1, p2 = (cx - dx, cy - a), (cx + dx, cy + a)
        draw.line([p1, p2], fill=255, width=round(w))
        for px, py in (p1, p2):
            draw.ellipse([px - w / 2, py - w / 2, px + w / 2, py + w / 2], fill=255)
    return big.resize(size, Image.LANCZOS)


def app_icon():
    size = (1024, 1024)
    # Apple's icon grid: an 824 pt rounded square centered on the canvas.
    box = (100, 100, 924, 924)
    radius = 185

    icon = Image.new("RGBA", size, (0, 0, 0, 0))
    shape = rounded_mask(size, box, radius)

    shadow = Image.new("RGBA", size, (0, 0, 0, 0))
    shadow.putalpha(shape.point(lambda v: v * 0.35))
    shadow = shadow.filter(ImageFilter.GaussianBlur(18))
    icon.alpha_composite(shadow, (0, 12))

    body = vertical_gradient(size, (94, 160, 255), (88, 64, 230)).convert("RGBA")
    # Soft glass highlight fading out from the top edge.
    highlight = Image.new("L", size, 0)
    hd = ImageDraw.Draw(highlight)
    for y in range(box[1], 560):
        t = (y - box[1]) / (560 - box[1])
        hd.line([(0, y), (size[0], y)], fill=round(60 * (1 - t) ** 2))
    body = Image.composite(Image.new("RGBA", size, (255, 255, 255, 255)), body, highlight)
    body.putalpha(shape)
    icon.alpha_composite(body)

    # Thin bright rim, like light catching the edge of glass.
    inner = rounded_mask(size, (box[0] + 6, box[1] + 6, box[2] - 6, box[3] - 6), radius - 6)
    rim = ImageChops.subtract(shape, inner)
    rim_layer = Image.new("RGBA", size, (255, 255, 255, 0))
    rim_layer.putalpha(rim.point(lambda v: v * 0.45))
    icon.alpha_composite(rim_layer)

    x_mask = draw_x(size, (512, 512), 175, 112)
    x_shadow = Image.new("RGBA", size, (20, 10, 90, 0))
    x_shadow.putalpha(x_mask.point(lambda v: v * 0.35).filter(ImageFilter.GaussianBlur(14)))
    icon.alpha_composite(x_shadow, (0, 14))
    x_layer = Image.new("RGBA", size, (255, 255, 255, 0))
    x_layer.putalpha(x_mask)
    icon.alpha_composite(x_layer)

    icon.save(RESOURCES / "AppIcon.png")


def dmg_background(scale):
    w, h = DMG_SIZE[0] * scale, DMG_SIZE[1] * scale
    img = vertical_gradient((w, h), (246, 247, 252), (226, 230, 244)).convert("RGBA")

    # Faint color glows behind the icon spots. Blur only the alpha, so the
    # edges fade to the glow color rather than to grey.
    r = 110 * scale
    for (x, y), color in ((APP_POS, (120, 110, 255)), (APPLICATIONS_POS, (110, 170, 255))):
        alpha = Image.new("L", (w, h), 0)
        ImageDraw.Draw(alpha).ellipse([x * scale - r, y * scale - r, x * scale + r, y * scale + r], fill=60)
        glow = Image.new("RGBA", (w, h), color + (0,))
        glow.putalpha(alpha.filter(ImageFilter.GaussianBlur(45 * scale)))
        img.alpha_composite(glow)

    # Arrow from the app to Applications.
    draw = ImageDraw.Draw(img)
    color = (120, 126, 160, 255)
    y = APP_POS[1] * scale
    x1, x2 = (APP_POS[0] + 95) * scale, (APPLICATIONS_POS[0] - 95) * scale
    stroke = 6 * scale
    head = 22 * scale
    draw.line([(x1, y), (x2 - head // 2, y)], fill=color, width=stroke)
    draw.ellipse([x1 - stroke / 2, y - stroke / 2, x1 + stroke / 2, y + stroke / 2], fill=color)
    draw.polygon([(x2, y), (x2 - head, y - head * 0.8), (x2 - head, y + head * 0.8)], fill=color)

    font = ImageFont.truetype(FONT, 22 * scale)
    text = "Drag Quitty to Applications"
    tw = draw.textlength(text, font=font)
    draw.text(((w - tw) / 2, 318 * scale), text, font=font, fill=(70, 74, 100, 255))

    suffix = "" if scale == 1 else f"@{scale}x"
    img.convert("RGB").save(RESOURCES / f"dmg-background{suffix}.png")


if __name__ == "__main__":
    app_icon()
    dmg_background(1)
    dmg_background(2)
    print("Wrote", ", ".join(sorted(p.name for p in RESOURCES.glob("*.png"))))
