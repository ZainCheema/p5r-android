# Launcher icons from the P5R logo picture (white/gold/black on red): the logo is keyed out of its red background
# and put on a clean square red with a soft radial glow. Writes mipmap-*/ic_launcher.png, ic_launcher_layer.png,
# the adaptive xml, and icon.png (1024 px) next to res/.
# Usage: python3 games/p5r/tools/make_nova_icon.py <picture> [<out res dir>]      (needs Pillow: pip install pillow)
# The default output is private/p5r/icon/res, which games/p5r/tools/build_android.sh uses before the project's own icon.
# It stays in private/ (not committed): the logo is ATLUS's artwork.
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_OUT = os.path.join(HERE, "..", "..", "..", "private", "p5r", "icon", "res")

from PIL import Image, ImageChops, ImageFilter


def smooth(v, lo, hi):
    if v <= lo:
        return 0.0
    if v >= hi:
        return 1.0
    t = (v - lo) / (hi - lo)
    return t * t * (3 - 2 * t)


def key_logo(path):
    im = Image.open(path).convert("RGB")
    im = im.crop((6, 6, im.width - 6, im.height - 6))  # the picture's edge rows are not clean
    im = im.resize((im.width * 4, im.height * 4), Image.LANCZOS)
    r, g, b = im.split()
    gb = ImageChops.lighter(g, b)
    # background: green/blue near 0 and red bright; anything else (white, gold, black shadow) is the logo
    lut_gb = [round(255 * (1 - smooth(v, 18, 60))) for v in range(256)]
    lut_r = [round(255 * smooth(v, 70, 130)) for v in range(256)]
    bg = ImageChops.multiply(gb.point(lut_gb), r.point(lut_r))
    alpha = ImageChops.invert(bg).filter(ImageFilter.MedianFilter(5))
    alpha = alpha.point(lambda v: 0 if v < 24 else v)
    logo = im.convert("RGBA")
    logo.putalpha(alpha)
    return logo.crop(alpha.getbbox())


def background(size):
    # radial red: bright centre (251,1,2) to darker edge (140,0,2), like the original picture
    grad = Image.radial_gradient("L").resize((size, size), Image.LANCZOS)  # 0 centre .. 255 edge
    lut = [round(251 - (251 - 140) * min(1.0, v / 255 * 1.15) ** 1.6) for v in range(256)]
    red = grad.point(lut)
    zero = Image.new("L", (size, size), 1)
    return Image.merge("RGB", (red, zero, zero))


def compose(logo, size, share):
    bg = background(size).convert("RGBA")
    w = round(size * share)
    h = round(logo.height * w / logo.width)
    pic = logo.resize((w, h), Image.LANCZOS)
    bg.alpha_composite(pic, ((size - w) // 2, (size - h) // 2))
    return bg.convert("RGB")


def main():
    logo = key_logo(sys.argv[1])
    res = os.path.normpath(sys.argv[2] if len(sys.argv) > 2 else DEFAULT_OUT)
    # legacy square icon: logo 86% wide; adaptive layer (108 dp, launchers show about the middle 66%): 60%
    for folder, px in (("mdpi", 48), ("hdpi", 72), ("xhdpi", 96), ("xxhdpi", 144), ("xxxhdpi", 192)):
        d = os.path.join(res, "mipmap-" + folder)
        os.makedirs(d, exist_ok=True)
        compose(logo, px * 4, 0.86).resize((px, px), Image.LANCZOS).save(os.path.join(d, "ic_launcher.png"))
        lp = px * 108 // 48
        compose(logo, lp * 4, 0.60).resize((lp, lp), Image.LANCZOS).save(os.path.join(d, "ic_launcher_layer.png"))
    d = os.path.join(res, "mipmap-anydpi-v26")
    os.makedirs(d, exist_ok=True)
    with open(os.path.join(d, "ic_launcher.xml"), "w") as f:
        f.write('<?xml version="1.0" encoding="utf-8"?>\n'
                '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
                '    <background android:drawable="@mipmap/ic_launcher_layer" />\n'
                '    <foreground android:drawable="@android:color/transparent" />\n'
                '</adaptive-icon>\n')
    compose(logo, 1024, 0.60).save(os.path.join(res, "..", "icon.png"))
    print("icons:", res)


main()
