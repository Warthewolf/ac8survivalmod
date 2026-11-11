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


EXTRA = (("5_inside", "inside, past the back quarter"), ("6_inside_front", "inside, past the front quarter"))
done = sorted(n for n in NAMES if all(os.path.exists(os.path.join(SRC, "style%d_%s.png" % (n, v))) for v, _ in VIEWS))
W, H = 960, 540
for n in done:
    views = list(VIEWS) + [e for e in EXTRA if os.path.exists(os.path.join(SRC, "style%d_%s.png" % (n, e[0])))]
    cols = 3 if len(views) > 4 else 2
    row = Image.new("RGB", (W * cols, H * 2 + 70), (12, 14, 18))
    label(row, "STYLE %d   %s" % (n, NAMES[n]), 40)
    seq = [os.path.join(SRC, "style%d_seq_%d.png" % (n, k)) for k in range(1, 6)]
    if all(os.path.exists(f) for f in seq):                 # its transform in five steps, under it
        strip = Image.new("RGB", (W * 5, H + 60), (12, 14, 18))
        label(strip, "STYLE %d   the transform, step by step" % n, 34)
        for k, f in enumerate(seq):
            strip.paste(label(Image.open(f).convert("RGB").resize((W, H)), "%d" % (k + 1), 26), (k * W, 60))
        strip.save(os.path.join(OUT, "style_%d_sequence.png" % n))
    for k, (v, cap) in enumerate(views):
        im = Image.open(os.path.join(SRC, "style%d_%s.png" % (n, v))).convert("RGB").resize((W, H))
        row.paste(label(im, cap, 22), ((k % cols) * W, 70 + (k // cols) * H))
    row.save(os.path.join(OUT, "style_%d.png" % n))
for v, cap in VIEWS:
    grid = Image.new("RGB", (W * 4, H * 2), (0, 0, 0))
    for i, n in enumerate(done):
        im = Image.open(os.path.join(SRC, "style%d_%s.png" % (n, v))).convert("RGB").resize((W, H))
        grid.paste(label(im, "%d  %s" % (n, NAMES[n]), 30), ((i % 4) * W, (i // 4) * H))
    grid.save(os.path.join(OUT, "styles_%s.png" % v.split("_", 1)[1]))
print("style_sheet: %d styles: %s" % (len(done), done))
