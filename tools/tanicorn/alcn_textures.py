"""alcn_textures.py : the Alicorn's six skin textures at the game's own size (4096 px) for THE TANACORN's hull.

    python -I tools/tanicorn/alcn_textures.py [--legacy <dir>] [--tex <dir>] [--extract]

The hull's Alicorn surfaces (materials ALC_a / ALC_b of the Leviathan design) used 2048 px copies of AC8's
/Game/OnlineMode/Vehicles/Boss/BA002_alcn/Textures/T_BA002_alcn_{a,b}_{D,N,MREC}: their mip 1. The game's own are
4096 px ordinary (not virtual) textures. This makes the 4096 copies:
  1. `retoc to-legacy` of the six from the game's paks (AC8_PAKS, the AES key from .env through tools/env.py; the key is
     never printed) into --legacy (default <TANI_BUILD>/alcn/legacy), when they aren't there yet or with --extract;
  2. mip 0 of each: the .ubulk's first data resource (the .uasset's data resource table says where and how big), decoded
     with Pillow's own BCn decoder (PF_DXT1 / PF_DXT5 as RGBA, PF_BC5 as RGB with blue 0), the same decode the 2048 px
     copies were made with (their pixels are this decode's mip 1 exactly);
  3. written as <tex>/T_BA002_alcn_<x>.png (default <TANI_BUILD>/alcn/tex), a 2048 px file there kept once as
     T_BA002_alcn_<x>_2048.png;
  4. checked: mip 1 against the _2048 copy (must be identical: same layout, orientation and channels) and mip 0 box-
     filtered to 2048 against it (mean |difference| a channel, 0..255; the game's mips are filtered its own way, so
     about 0.5-3.5 there is expected).
model_tanacorn.py then puts them into the design's ALC image datablocks (which the design file holds packed at 2048)
before it saves Tanacorn_model.blend: its log line `model: ALC images at full size: ...`; export_tanacorn.py writes them
on as they are (src_HULL's T_SV_Tani_HULL_<n>_D / _N at 4096).
Formats (2026-11-10): a_D PF_DXT5, b_D PF_DXT1, a_MREC / b_MREC PF_DXT1, a_N / b_N PF_BC5, all 4096 x 4096.
TANI_BUILD defaults to the repo's build/tanicorn, as build.sh, spec.py and ue_import.py take it.
"""
import os
import re
import shutil
import struct
import subprocess
import sys

from PIL import Image, ImageChops, ImageStat

HERE = os.path.dirname(os.path.abspath(__file__))
TOOLS = os.path.dirname(HERE)
ROOT = os.path.dirname(TOOLS)
BUILD = os.environ.get('TANI_BUILD') or os.path.join(ROOT, 'build', 'tanicorn')
GAME_DIR = 'OnlineMode/Vehicles/Boss/BA002_alcn/Textures'
NAMES = ['a_D', 'a_N', 'a_MREC', 'b_D', 'b_N', 'b_MREC']
# pixel format -> (Pillow's bcn decoder number, mode, bytes a texel)
FORMATS = {'PF_DXT1': (1, 'RGBA', 0.5), 'PF_DXT5': (3, 'RGBA', 1.0), 'PF_BC5': (5, 'RGB', 1.0)}
PF = re.compile(rb'(?P<len>[\x05-\x20])\x00\x00\x00(?P<name>PF_[A-Za-z0-9_]+)\x00')
ENTRY = struct.Struct('<IqqqqiI')     # a data resource: flags, serial offset, duplicate offset, serial size, raw size,
                                      # outer index, legacy bulk data flags (UE 5.2+ packages)


def extract(legacy):
    sys.path.insert(0, TOOLS)
    import env                                          # (tools/env.py: the game's paks and key from .env)
    retoc = os.path.join(TOOLS, 'bin', 'retoc.exe')
    r = subprocess.run([retoc, '-a', env.aes_key(), 'to-legacy', '--no-shaders', '--version', 'UE5_4',
                        '-f', 'T_BA002_alcn_', env.paks(), legacy], capture_output=True, text=True)
    said = [l for l in (r.stdout + r.stderr).splitlines() if 'Extracted' in l or 'rror' in l]
    print('alcn: retoc to-legacy: ' + ('; '.join(s.strip() for s in said) or 'exit %d' % r.returncode))
    if r.returncode:
        raise SystemExit('alcn: retoc failed (exit %d)' % r.returncode)


def platform(uexp):
    """(width, height, pixel format) of the package's cooked platform data"""
    for m in PF.finditer(uexp):
        if len(m.group('name')) + 1 == m.group('len')[0] and m.start() >= 12:
            sx, sy = struct.unpack_from('<ii', uexp, m.start() - 12)   # (SizeX, SizeY, PackedData, the FString)
            if 0 < sx <= 16384 and 0 < sy <= 16384:
                return sx, sy, m.group('name').decode()
    raise SystemExit('alcn: no platform data in the .uexp')


def resource(uasset, size):
    """(offset, size) in the .ubulk of the data resource holding `size` bytes (mip 0 or mip 1)"""
    for o in range(len(uasset) - ENTRY.size + 1):
        flags, off, dup, ssize, raw, outer, legacy = ENTRY.unpack_from(uasset, o)
        if ssize == size and raw == size and dup == -1 and 0 <= off and legacy & 0x100:   # (payload in the .ubulk)
            return off, ssize
    raise SystemExit('alcn: no data resource of %d bytes in the .uasset' % size)


def mip(base, k):
    """mip k (0 or 1) of a legacy texture package: a PIL image"""
    uexp = open(base + '.uexp', 'rb').read()
    uasset = open(base + '.uasset', 'rb').read()
    w, h, pf = platform(uexp)
    if pf not in FORMATS:
        raise SystemExit('alcn: %s is %s, not one this decodes' % (os.path.basename(base), pf))
    n, mode, bpt = FORMATS[pf]
    w, h = w >> k, h >> k
    off, size = resource(uasset, int(w * h * bpt))
    with open(base + '.ubulk', 'rb') as f:
        f.seek(off)
        data = f.read(size)
    return Image.frombytes(mode, (w, h), data, 'bcn', (n, pf[3:])), pf


def mean_diff(a, b):
    return [round(v, 3) for v in ImageStat.Stat(ImageChops.difference(a, b)).mean]


def main(argv):
    legacy = os.path.join(BUILD, 'alcn', 'legacy')
    tex = os.path.join(BUILD, 'alcn', 'tex')
    force = '--extract' in argv
    for i, a in enumerate(argv):
        if a == '--legacy':
            legacy = os.path.abspath(argv[i + 1])
        elif a == '--tex':
            tex = os.path.abspath(argv[i + 1])
    pkg = os.path.join(legacy, 'Live', 'Content', GAME_DIR)
    if force or not all(os.path.isfile(os.path.join(pkg, 'T_BA002_alcn_%s.ubulk' % x)) for x in NAMES):
        extract(legacy)
    os.makedirs(tex, exist_ok=True)
    bad = []
    for x in NAMES:
        base = os.path.join(pkg, 'T_BA002_alcn_' + x)
        dst = os.path.join(tex, 'T_BA002_alcn_%s.png' % x)
        old = os.path.join(tex, 'T_BA002_alcn_%s_2048.png' % x)
        if os.path.isfile(dst) and not os.path.isfile(old):
            with Image.open(dst) as im:
                small = im.size == (2048, 2048)
            if small:
                shutil.copy2(dst, old)
                print('alcn: kept the 2048 px copy as %s' % os.path.basename(old))
        im0, pf = mip(base, 0)
        im0.save(dst)
        line = 'alcn: %-6s %-7s %s %dx%d -> %s' % (x, pf, im0.mode, im0.size[0], im0.size[1], dst)
        if os.path.isfile(old):
            ref = Image.open(old)
            im1, _ = mip(base, 1)
            if ref.mode != im0.mode or ref.size != im1.size:
                bad.append(x)
                line += '; the 2048 copy is %s %s, not %s %s' % (ref.mode, ref.size, im0.mode, im1.size)
            else:
                d1 = mean_diff(im1, ref)
                d0 = mean_diff(im0.resize(ref.size, Image.BOX), ref)
                if max(d1) > 0.01:
                    bad.append(x)
                line += '; vs the 2048 copy: mip 1 |d| %s, mip 0 box-filtered |d| %s' % (d1, d0)
        print(line)
    print('alcn: %d textures at full size%s' % (len(NAMES), ', MISMATCHED: ' + ', '.join(bad) if bad else ', every one '
          'the same layout as its 2048 copy'))
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
