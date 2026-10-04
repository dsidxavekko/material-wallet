#!/usr/bin/env python3
"""Bake the pre-rendered app icon from the ``icon/`` folder into Android.

Unlike ``tool/generate_launcher_icons.py`` (which draws the wallet glyph
procedurally), this script uses the finished, high-resolution artwork that
lives in the sibling ``icon/`` directory:

* ``icon/app_icon_1024.png``            -> full-bleed legacy launcher icon
* ``icon/app_icon_foreground_1024.png`` -> adaptive-icon foreground layer
* ``icon/preview_legacy_rounded_512.png``-> legacy round launcher icon

Run from anywhere::

    python3 tool/apply_app_icon.py

It (re)creates, under ``android/app/src/main/res``:

* ``mipmap-anydpi-v26/ic_launcher.xml`` and ``ic_launcher_round.xml`` —
  adaptive-icon descriptors pointing at the new foreground.
* ``values/ic_launcher_background.xml`` + ``drawable/ic_launcher_background.xml``
  — the brand-colour background layer.
* ``mipmap-<density>/ic_launcher.png`` / ``ic_launcher_round.png`` — legacy
  icons, resampled from the 1024/512 px sources.
* ``mipmap-<density>/ic_launcher_foreground.png`` — the transparent wallet
  glyph on a 108dp canvas, scaled to each density bucket.
* ``playstore-icon.png`` — 512x512 full-bleed store listing icon.
"""

from __future__ import annotations

import os

from PIL import Image

# Source artwork (the sibling ``icon/`` folder next to the project root).
PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ICON_DIR = os.path.join(os.path.dirname(PROJECT_ROOT), "icon")

FULL_ICON = os.path.join(ICON_DIR, "app_icon_1024.png")
FOREGROUND = os.path.join(ICON_DIR, "app_icon_foreground_1024.png")
ROUND_ICON = os.path.join(ICON_DIR, "preview_legacy_rounded_512.png")

# Brand colour from lib/core/theme/app_theme.dart (ColorScheme seed).
BRAND = (79, 70, 229, 255)          # #4F46E5

RES_ROOT = os.path.join(PROJECT_ROOT, "android", "app", "src", "main", "res")

# Density bucket -> legacy icon size in px (48dp base).
DENSITIES = {
    "mdpi": 48,
    "hdpi": 72,
    "xhdpi": 96,
    "xxhdpi": 144,
    "xxxhdpi": 192,
}

# Adaptive-icon layers are 108dp; the legacy base is 48dp.
FOREGROUND_SCALE = 108 / 48


def _load(path: str) -> Image.Image:
    if not os.path.exists(path):
        raise FileNotFoundError(f"missing icon source: {path}")
    return Image.open(path).convert("RGBA")


def _resize(img: Image.Image, size: int) -> Image.Image:
    return img.resize((size, size), Image.LANCZOS)


def _build_foreground(size: int) -> Image.Image:
    """Foreground glyph scaled into the 108dp canvas, centred."""
    src = _load(FOREGROUND)
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    # The 1024px foreground already contains the correct safe-zone padding,
    # so a straight resize keeps the glyph proportionally placed.
    canvas.alpha_composite(_resize(src, size))
    return canvas


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
        '<!-- Real shape drawable (not a @color alias): a '
        '<drawable android:drawable="@color/..."/>\n'
        '     indirection is not reliably resolved as an adaptive-icon background '
        'on every\n'
        '     launcher, which makes the launcher fall back to the generic Android '
        'robot. -->\n'
        '<shape xmlns:android="http://schemas.android.com/apk/res/android"\n'
        '    android:shape="rectangle">\n'
        f'    <solid android:color="{hex_color}"/>\n'
        '</shape>\n'
    )
    with open(os.path.join(drawable, "ic_launcher_background.xml"), "w",
              encoding="utf-8") as fh:
        fh.write(shape)


def main() -> None:
    full = _load(FULL_ICON)
    round_src = _load(ROUND_ICON)

    write_adaptive_xml()
    write_background()

    for density, px in DENSITIES.items():
        folder = os.path.join(RES_ROOT, f"mipmap-{density}")
        ensure_dir(folder)

        _resize(full, px).save(os.path.join(folder, "ic_launcher.png"))
        _resize(round_src, px).save(os.path.join(folder, "ic_launcher_round.png"))

        fg_px = int(round(px * FOREGROUND_SCALE))
        _build_foreground(fg_px).save(
            os.path.join(folder, "ic_launcher_foreground.png"))

        print(f"wrote mipmap-{density}: legacy {px}px, foreground {fg_px}px")

    # Google Play store listing icon (512x512, full-bleed, no rounding).
    playstore = os.path.join(PROJECT_ROOT, "android", "playstore-icon.png")
    _resize(full, 512).convert("RGB").save(playstore, format="PNG")
    print(f"wrote {playstore} (512x512)")


if __name__ == "__main__":
    main()
