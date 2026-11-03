#!/usr/bin/env python3
"""WCAG contrast of text as it was actually composited, read from a capture.

Token pairs (qml-design-lint) assume opaque colours; translucent ink over a
wallpaper does not. This reads a PNG (a `cortetsu realm qa` capture) and, for
each box around one run of text, takes the background as the most common
colour in the box and the text as the pixel farthest from it in luminance.
Antialiasing only lowers the measured text contrast, so a pass is a pass.

Usage: measure-composited-contrast.py IMAGE NAME:X,Y,W,H [NAME:X,Y,W,H ...]
Needs ImageMagick (`magick`), which `cortetsu realm qa` already requires.
"""
import subprocess
import sys
from collections import Counter


def luminance(rgb):
    def channel(c):
        c /= 255
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
    r, g, b = (channel(c) for c in rgb)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def ratio(a, b):
    hi, lo = sorted((luminance(a), luminance(b)), reverse=True)
    return (hi + 0.05) / (lo + 0.05)


def pixels(image, x, y, w, h):
    raw = subprocess.run(["magick", image, "-crop", f"{w}x{h}+{x}+{y}", "+repage", "-depth", "8", "rgb:-"],
                         check=True, capture_output=True).stdout
    return [tuple(raw[i:i + 3]) for i in range(0, len(raw) - 2, 3)]


def main(argv):
    if len(argv) < 3:
        sys.exit(__doc__)
    image = argv[1]
    for spec in argv[2:]:
        name, box = spec.split(":", 1)
        x, y, w, h = (int(v) for v in box.split(","))
        px = pixels(image, x, y, w, h)
        background = Counter(px).most_common(1)[0][0]
        text = max(px, key=lambda p: abs(luminance(p) - luminance(background)))
        print(f"{name}\t{ratio(text, background):.2f}\ttext={text}\tbackground={background}")


if __name__ == "__main__":
    main(sys.argv)
