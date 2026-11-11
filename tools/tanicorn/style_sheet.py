"""style_sheet.py : plain Python (PIL), styles_firemode.py's renders laid out for the user's choice.

  python -I tools/tanicorn/style_sheet.py <renders dir> <out dir>

Writes style_<N>.png (its four views, 2 x 2, numbered and named) for each style rendered, and
styles_overhead.png / _front / _firing / _side (one view of every style, 4 x 2, numbered).
"""
import os, re, sys
from PIL import Image, ImageDraw, ImageFont

SRC, OUT = sys.argv[1], sys.argv[2]
os.makedirs(OUT, exist_ok=True)
here = os.path.dirname(os.path.abspath(__file__))
NAMES = {int(n): t for n, t in re.findall(r'^\s+(\d): \{"name": "([^"]+)"', open(os.path.join(here, "firemode.py")).read(), re.M)}
FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
VIEWS = (("1_overhead", "transformed, from above"), ("4_front", "transformed, from ahead"), ("2_firing", "firing"),
         ("3_side", "the side, opened"))


def font(size):
    try:
        return ImageFont.truetype(FONT, size)
    except OSError:
        return ImageFont.load_default()


def label(im, text, size=30):
    d = ImageDraw.Draw(im)
    f = font(size)
    w, h = d.textbbox((0, 0), text, font=f)[2:]
    d.rectangle((0, 0, w + 24, h + 18), fill=(0, 0, 0))
    d.text((12, 8), text, font=f, fill=(255, 255, 255))
    return im


done = sorted(n for n in NAMES if all(os.path.exists(os.path.join(SRC, "style%d_%s.png" % (n, v))) for v, _ in VIEWS))
W, H = 960, 540
for n in done:
    row = Image.new("RGB", (W * 2, H * 2 + 70), (12, 14, 18))
    label(row, "STYLE %d   %s" % (n, NAMES[n]), 40)
    for k, (v, cap) in enumerate(VIEWS):
        im = Image.open(os.path.join(SRC, "style%d_%s.png" % (n, v))).convert("RGB").resize((W, H))
        row.paste(label(im, cap, 22), ((k % 2) * W, 70 + (k // 2) * H))
    row.save(os.path.join(OUT, "style_%d.png" % n))
for v, cap in VIEWS:
    grid = Image.new("RGB", (W * 4, H * 2), (0, 0, 0))
    for i, n in enumerate(done):
        im = Image.open(os.path.join(SRC, "style%d_%s.png" % (n, v))).convert("RGB").resize((W, H))
        grid.paste(label(im, "%d  %s" % (n, NAMES[n]), 30), ((i % 4) * W, (i // 4) * H))
    grid.save(os.path.join(OUT, "styles_%s.png" % v.split("_", 1)[1]))
print("style_sheet: %d styles: %s" % (len(done), done))
