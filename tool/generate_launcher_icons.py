#!/usr/bin/env python3
"""Generate the Android launcher icons for Material Wallet.

Run from anywhere:

    python3 tool/generate_launcher_icons.py

It (re)creates, under ``android/app/src/main/res``:

* ``mipmap-anydpi-v26/ic_launcher.xml`` and ``ic_launcher_round.xml`` —
  adaptive-icon descriptors.
* ``values/ic_launcher_background.xml`` + ``drawable/ic_launcher_background.xml``
  — the brand-colour background layer.
* ``mipmap-<density>/ic_launcher_foreground.png`` — the white wallet glyph on a
  transparent 108dp canvas (content kept inside the safe zone).
* ``mipmap-<density>/ic_launcher.png`` and ``ic_launcher_round.png`` —
  full-bleed legacy icons for launchers that ignore adaptive icons.

Everything is drawn procedurally with Pillow, so no external assets are needed.
"""

from __future__ import annotations

import os
from PIL import Image, ImageDraw

# Brand colour from lib/core/theme/app_theme.dart (ColorScheme seed).
BRAND = (79, 70, 229, 255)          # #4F46E5
BRAND_DARK = (49, 41, 168, 255)     # slightly darker for a subtle gradient
WHITE = (255, 255, 255, 255)

RES_ROOT = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "android", "app", "src", "main", "res",
)

# Density bucket -> legacy icon size in px (48dp base).
DENSITIES = {
    "mdpi": 48,
    "hdpi": 72,
    "xhdpi": 96,
    "xxhdpi": 144,
    "xxxhdpi": 192,
}

# Adaptive-icon layers are 108dp; the inner 72dp is the visible mask area and
# the 66dp circle is the guaranteed safe zone.
FOREGROUND_SCALE = 108 / 48  # foreground px per dp relative to legacy size


def _rounded_rect(draw, box, radius, fill) -> None:
    draw.rounded_rectangle(box, radius=radius, fill=fill)


def _gradient(size: int) -> Image.Image:
    grad = Image.new("RGBA", (1, size))
    for y in range(size):
        t = y / max(size - 1, 1)
        grad.putpixel(
            (0, y),
            tuple(int(BRAND[i] * (1 - t) + BRAND_DARK[i] * t) for i in range(4)),
        )
    return grad.resize((size, size))


def draw_wallet(size: int, *, background: bool) -> Image.Image:
    """Draw a wallet glyph. When [background] the canvas is opaque + rounded."""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))

    if background:
        mask = Image.new("L", (size, size), 0)
        ImageDraw.Draw(mask).rounded_rectangle(
            (0, 0, size - 1, size - 1), radius=int(size * 0.22), fill=255
        )
        img.paste(_gradient(size), (0, 0), mask)

    draw = ImageDraw.Draw(img)

    # Wallet body: a rounded rectangle with a card flap and a clasp dot.
    m = size * 0.24            # side margin
    top = size * 0.30
    body_w = size - 2 * m
    body_h = size * 0.40
    r = size * 0.07
    _rounded_rect(draw, (m, top, m + body_w, top + body_h), int(r), WHITE)

    # Folded flap on top of the body (slightly inset and raised).
    flap_h = size * 0.14
    _rounded_rect(
        draw,
        (m + body_w * 0.10, top - flap_h * 0.75, m + body_w, top + flap_h * 0.5),
        int(r * 0.9),
        WHITE,
    )

    # Clasp: a small brand-coloured circle on the right, punched out of the body.
    clasp_r = size * 0.055
    cx = m + body_w - body_w * 0.16
    cy = top + body_h * 0.62
    draw.ellipse((cx - clasp_r, cy - clasp_r, cx + clasp_r, cy + clasp_r),
                 fill=BRAND)
    return img


def draw_foreground(size: int) -> Image.Image:
    """White wallet glyph centred on a transparent 108dp canvas."""
    return draw_wallet(size, background=False)


def draw_round(size: int) -> Image.Image:
    """Legacy round icon: gradient disc with the wallet glyph on top."""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).ellipse((0, 0, size - 1, size - 1), fill=255)
    img.paste(_gradient(size), (0, 0), mask)

    inner = draw_wallet(int(size * 0.62), background=False)
    off = (size - inner.size[0]) // 2
    img.alpha_composite(inner, (off, off))
    return img


def ensure_dir(path: str) -> None:
    os.makedirs(path, exist_ok=True)


def write_adaptive_xml() -> None:
    anydpi = os.path.join(RES_ROOT, "mipmap-anydpi-v26")
    ensure_dir(anydpi)
    template = (
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '    <background android:drawable="@color/ic_launcher_background"/>\n'
        '    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>\n'
        '</adaptive-icon>\n'
    )
    for name in ("ic_launcher.xml", "ic_launcher_round.xml"):
        with open(os.path.join(anydpi, name), "w", encoding="utf-8") as fh:
            fh.write(template)


def write_background() -> None:
    hex_color = "#%02X%02X%02X" % BRAND[:3]

    values = os.path.join(RES_ROOT, "values")
    ensure_dir(values)
    color_xml = (
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<resources>\n'
        f'    <color name="ic_launcher_background">{hex_color}</color>\n'
        '</resources>\n'
    )
    with open(os.path.join(values, "ic_launcher_background.xml"), "w",
              encoding="utf-8") as fh:
        fh.write(color_xml)

    # A real shape drawable rather than a @color alias: the
    # <drawable android:drawable="@color/..."/> indirection is not reliably
    # resolved as an adaptive-icon background on every launcher, which makes the
    # launcher fall back to the generic Android robot icon.
    drawable = os.path.join(RES_ROOT, "drawable")
    ensure_dir(drawable)
    shape = (
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<shape xmlns:android="http://schemas.android.com/apk/res/android"\n'
        '    android:shape="rectangle">\n'
        f'    <solid android:color="{hex_color}"/>\n'
        '</shape>\n'
    )
    with open(os.path.join(drawable, "ic_launcher_background.xml"), "w",
              encoding="utf-8") as fh:
        fh.write(shape)


def main() -> None:
    write_adaptive_xml()
    write_background()

    for density, px in DENSITIES.items():
        folder = os.path.join(RES_ROOT, f"mipmap-{density}")
        ensure_dir(folder)

        draw_wallet(px, background=True).save(
            os.path.join(folder, "ic_launcher.png"))
        draw_round(px).save(os.path.join(folder, "ic_launcher_round.png"))

        # Adaptive foreground: 108dp canvas (scale up from the 48dp base).
        fg_px = int(round(px * FOREGROUND_SCALE))
        canvas = Image.new("RGBA", (fg_px, fg_px), (0, 0, 0, 0))
        glyph = draw_foreground(int(fg_px * 0.60))
        off = (fg_px - glyph.size[0]) // 2
        canvas.alpha_composite(glyph, (off, off))
        canvas.save(os.path.join(folder, "ic_launcher_foreground.png"))

        print(f"wrote mipmap-{density}: legacy {px}px, foreground {fg_px}px")


if __name__ == "__main__":
    main()

