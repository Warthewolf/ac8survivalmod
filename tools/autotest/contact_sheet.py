"""contact_sheet.py : a run's pictures on one sheet, each labelled, centre-cropped (the HUD's edges off).

  python -X utf8 -I tools/autotest/contact_sheet.py <run folder> <out.jpg> [--match TEXT] [--cols N] [--crop 0.6] [--w 640]

Reads <run>/shots/NN_<name>.png (job.py's window grabs), the ones whose name has TEXT; each scaled to w pixels wide
after keeping the central `crop` share of it (1 = whole), its name written under it.
"""
import os
import sys

from PIL import Image, ImageDraw


def main():
    a = sys.argv[1:]
    if len(a) < 2:
        print(__doc__)
        return 2
    run, out = a[0], a[1]
    opt = lambda k, d: a[a.index(k) + 1] if k in a else d
    match, cols, crop, w = opt('--match', ''), int(opt('--cols', '3')), float(opt('--crop', '0.6')), int(opt('--w', '640'))
    d = os.path.join(run, 'shots')
    names = sorted(f for f in os.listdir(d) if f.endswith('.png') and not f.startswith('game_') and match in f)
    if not names:
        print('no pictures')
        return 1
    tiles = []
    for n in names:
        im = Image.open(os.path.join(d, n)).convert('RGB')
        W, H = im.size
        cw, ch = int(W * crop), int(H * crop)
        im = im.crop(((W - cw) // 2, (H - ch) // 2, (W + cw) // 2, (H + ch) // 2))
        h = int(w * ch / cw)
        tiles.append((n[:-4], im.resize((w, h))))
    th = tiles[0][1].size[1] + 22
    rows = (len(tiles) + cols - 1) // cols
    sheet = Image.new('RGB', (cols * w, rows * th), (16, 20, 24))
    dr = ImageDraw.Draw(sheet)
    for i, (n, im) in enumerate(tiles):
        x, y = (i % cols) * w, (i // cols) * th
        sheet.paste(im, (x, y))
        dr.text((x + 6, y + im.size[1] + 4), n, fill=(230, 230, 230))
    sheet.save(out, quality=85)
    print('sheet:', out, len(tiles), 'pictures')
    return 0


if __name__ == '__main__':
    sys.exit(main())
