"""style_sheet.py : plain Python (PIL), styles_firemode.py's renders laid out for the user's choice.

  python -I tools/tanicorn/style_sheet.py <renders dir> <out dir> [<the clip's frames dir>]

Writes style_<N>.png (its four views, 2 x 2, numbered and named) for each style rendered, and
styles_overhead.png / _front / _firing / _side (one view of every style, 4 x 2, numbered).
With the user's clip's frames (frame_NNN.png, 1-198, extracted at its 24 fps) and a style's `clip` renders:
style_<N>_clip_front.png / _side.png, each step of the clip beside the render posed like it (CLIP_PAIRS).
"""
import os, re, sys
from PIL import Image, ImageDraw, ImageFont

SRC, OUT = sys.argv[1], sys.argv[2]
os.makedirs(OUT, exist_ok=True)
here = os.path.dirname(os.path.abspath(__file__))
NAMES = {int(n): t for n, t in re.findall(r'^\s+(\d+): \{"name": "([^"]+)"', open(os.path.join(here, "firemode.py")).read(), re.M)}
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
# the clip's frames each `clip` render stands beside (styles_firemode.py CLIP_FRONT / CLIP_SIDE, in order)
CLIP_PAIRS = {"front": (32, 50, 54, 57, 59, 63, 66, 70), "side": (165, 176, 177, 178, 181, 190)}
FRAMES = sys.argv[3] if len(sys.argv) > 3 else None
for n in NAMES if FRAMES else ():
    for shot, frames in CLIP_PAIRS.items():
        rend = [os.path.join(SRC, "style%d_clip_%s_%d.png" % (n, shot, k + 1)) for k in range(len(frames))]
        if not all(os.path.exists(f) for f in rend):
            continue
        sheet = Image.new("RGB", (W * 2, H * len(frames) + 70), (12, 14, 18))
        label(sheet, "STYLE %d   the clip (left) and the model (right): %s" % (n, shot), 34)
        for k, (f, r) in enumerate(zip(frames, rend)):
            clip = Image.open(os.path.join(FRAMES, "frame_%03d.png" % f)).convert("RGB").resize((W, H))
            sheet.paste(label(clip, "clip frame %d" % f, 22), (0, 70 + k * H))
            sheet.paste(label(Image.open(r).convert("RGB").resize((W, H)), "step %d" % (k + 1), 22), (W, 70 + k * H))
        sheet.save(os.path.join(OUT, "style_%d_clip_%s.png" % (n, shot)))
print("style_sheet: %d styles: %s" % (len(done), done))
