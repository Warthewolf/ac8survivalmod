"""contact_sheet.py : a run's pictures on one sheet, each labelled, centre-cropped (the HUD's edges off).

  python -X utf8 -I tools/autotest/contact_sheet.py <run folder> <out.jpg> [--match TEXT] [--cols N] [--crop 0.6] [--w 640]
                                                    [--hires]

Reads <run>/shots/NN_<name>.png (job.py's window grabs), the ones whose name has TEXT; each scaled to w pixels wide
after keeping the central `crop` share of it (1 = whole), its name written under it.
--hires: the game's own HighResShot of each instead (game_HighresScreenshotNNNNN.png, paired with the NN_ names in
order). (2026-11-22) The window grabs come when job.py reads the SHOT line in the log, which reaches it late (up to 8 s
in the valka runs of 15:13-16:08: grabs after VALKA's cutscene had ended looked like it losing the view); the game's own
pictures are taken as asked.
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
    every = sorted(f for f in os.listdir(d) if f.endswith('.png') and not f.startswith('game_'))
    names = [f for f in every if match in f]
    if not names:
        print('no pictures')
        return 1
    hires = sorted(f for f in os.listdir(d) if f.startswith('game_HighresScreenshot'))
    if '--hires' in a and len(hires) != len(every):
        print(f'--hires: {len(hires)} high-res pictures for {len(every)} asked: the window grabs instead')
    use_hi = '--hires' in a and len(hires) == len(every)
    tiles = []
    for n in names:
        src = hires[every.index(n)] if use_hi else n
        im = Image.open(os.path.join(d, src)).convert('RGB')
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
