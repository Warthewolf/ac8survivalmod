"""parts_lua.py : VALKA's portal parts (CFG.specials.valka.portal.parts and blink_portal.parts in sv_config_specials.lua)
from the cooked design's manifest (tools/valka_portal/make_portal.py; build.sh copies it to build/valka_portal/manifest.json).

  python -I tools/valka_portal/parts_lua.py [--write]

Each piece: its mesh, AC8's material for its kind (ring: MI_TrainingRing with Color and Opacity, see-through as the probe of
2026-11-22 15:36 showed; haze: MI_TrainingRingGlow with its fresnel off (EmissiveFresnelFalloff 0.01): a flat see-through
glow; shadow: the engine's BasicShapeMaterial, black), how it faces (the arch's pieces face you, their top up: tilt -90,
turn 180; the disk's lie tipped DISK_TILT towards you), its spin, its shimmer, and its window of the opening and the closing
(sv_anomalies_valka.lua portalTick: a pinpoint first, the shadow, the disk from the inside out, the arch last; closing, the
outside falls in first and the photon ring snaps shut last). Prints the Lua; --write puts it into sv_config_specials.lua.
"""
import json
import os
import subprocess
import sys

ROOT = subprocess.run(['git', 'rev-parse', '--show-toplevel'], capture_output=True, text=True, check=True).stdout.strip()
MAIN = os.path.dirname(subprocess.run(['git', 'rev-parse', '--path-format=absolute', '--git-common-dir'], capture_output=True,
                                      text=True, check=True).stdout.strip())
MANIFEST = os.path.join(MAIN, 'build', 'valka_portal', 'manifest.json')
CFG = os.path.join(ROOT, 'mod', 'UE4SS', 'AC8SurvivalMode', 'Scripts', 'sv_config_specials.lua')
BH = '/Game/Mods/SurvivalMode/ValkaPortal/Model/'
MAT = {'ring': '/Game/VFX/Mission/Traning/MI_TrainingRing', 'haze': '/Game/VFX/Mission/Traning/MI_TrainingRingGlow',
       'shadow': '/Engine/BasicShapes/BasicShapeMaterial'}
DISK_TILT = -11
SMALL = {'SM_SV_BHShadow', 'SM_SV_BHPhotonRing', 'SM_SV_BHArch3', 'SM_SV_BHArchHaze1', 'SM_SV_BHDisk1', 'SM_SV_BHDisk2',
         'SM_SV_BHInfall'}   # (her blinks' small holes: ~100k triangles, up to 6 at once)


def g(x):
    return ('%.3f' % x).rstrip('0').rstrip('.') if isinstance(x, float) else str(x)


def num_of(name, prefix):
    tail = name[len(prefix):]
    return int(tail) if tail.isdigit() else None


def windows(name):
    """(open from, to), (close from, to), flare"""
    if name == 'SM_SV_BHPhotonRing':
        return (0.0, 0.3), (0.75, 1.0), True
    if name == 'SM_SV_BHShadow':
        return (0.08, 0.4), (0.55, 0.92), False
    for prefix, n_of in (('SM_SV_BHArchLow', 6), ('SM_SV_BHArchHaze', 2), ('SM_SV_BHArch', 6)):
        k = num_of(name, prefix)
        if k is not None:
            late = 0.05 if prefix == 'SM_SV_BHArchLow' else 0.0
            o = (min(0.9, 0.55 + 0.04 * (k - 1) + late), min(1.0, 0.85 + 0.025 * (k - 1) + late))
            c = (0.05 * (n_of - k), 0.35 + 0.05 * (n_of - k))
            return o, c, False
    for prefix in ('SM_SV_BHDiskHaze', 'SM_SV_BHKnots', 'SM_SV_BHDisk'):
        k = num_of(name, prefix)
        if k is not None:
            if prefix == 'SM_SV_BHDiskHaze':
                return (0.3, 0.8), (0.1, 0.5), False
            return (0.15 + 0.06 * (k - 1), 0.45 + 0.06 * (k - 1)), (0.05 * (8 - k), 0.35 + 0.05 * (8 - k)), False
    if name == 'SM_SV_BHInfall':
        return (0.3, 0.7), (0.45, 0.85), False
    return (0.5, 0.9), (0.0, 0.3), False                      # (the sparks, anything else)


def part(p, small=False):
    name, kind = p['name'], p['kind']
    o, c, flare = windows(name)
    bits = [f'mesh = "{BH}{name}"', 'abs = true', f'open = {{ {g(o[0])}, {g(o[1])} }}', f'close = {{ {g(c[0])}, {g(c[1])} }}']
    if flare:
        bits.append('flare = true')
    if p['faces']:
        if name.startswith(('SM_SV_BHArch', 'SM_SV_BHSparksArch')):
            bits += ['tilt = -90', 'turn = 180']
    else:
        bits.append(f'tilt = {DISK_TILT}')
    if p.get('spin'):
        bits.append(f'spin = {g(float(p["spin"]))}')
    if p.get('pulse') and not small:
        bits.append(f'pulse = {{ {g(float(p["pulse"][0]))}, {g(float(p["pulse"][1]))} }}')
    rgb = ', '.join(g(float(v)) for v in p['rgb'])
    if kind == 'shadow':
        params = '{ Color = { 0, 0, 0, 1 } }'
    elif kind == 'haze':
        params = f'{{ Color = {{ {rgb}, 1 }}, EmissiveIntensity = 1.5, Opacity = {g(float(p["opacity"]))}, EmissiveFresnelFalloff = 0.01 }}'
    else:
        params = f'{{ Color = {{ {rgb}, 1 }}, Opacity = {g(float(p["opacity"]))} }}'
    bits += [f'mat = "{MAT[kind]}"', f'params = {params}']
    return '{ ' + ', '.join(bits) + ' }'


SKIP = ('SM_SV_BHDiskHaze',)   # (the run of 15:45: the disk's haze read as a flat pale plate in the wide shots)


# ((2026-11-22) the run of 15:57: the engine's BasicShapeMaterial is lit, so the shadow was a glossy black ball mirroring
# the sea and the sunset. An unlit black over it (MI_TrainingRing, Color 0, Opacity 1, 0.4 % larger), drawn first of the
# see-through pieces (sort -10): the disk's near side over it, the ball beneath still hiding what's behind it)
SHADE = ('{ mesh = "' + BH + 'SM_SV_BHShadow", abs = true, size = 1.004, open = { 0.08, 0.4 }, close = { 0.55, 0.92 }, sort = -10, '
         'mat = "' + MAT['ring'] + '", params = { Color = { 0, 0, 0, 1 }, Opacity = 1 } }')


def block(pieces, indent, small=False):
    lines = []
    for p in pieces:
        if (small and p['name'] not in SMALL) or p['name'].startswith(SKIP):
            continue
        lines.append(' ' * indent + part(p, small) + ',')
        if p['name'] == 'SM_SV_BHShadow':
            lines.append(' ' * indent + SHADE + ',')
    return lines


def main():
    if '--names' in sys.argv:                                   # (build.sh: the pieces it checks were cooked)
        with open(sys.argv[sys.argv.index('--names') + 1], encoding='utf-8') as fh:
            print(' '.join(p['name'] for p in json.load(fh)['pieces']))
        return
    with open(MANIFEST, encoding='utf-8') as fh:
        m = json.load(fh)
    pieces = m['pieces']
    big = block(pieces, 32)
    small = block(pieces, 38, small=True)
    head = f'-- (the {m["design"]} design, {len(pieces)} pieces, {sum(p["tris"] for p in pieces)} triangles: tools/valka_portal/parts_lua.py)'
    if '--write' not in sys.argv:
        print(head)
        print('\n'.join(big))
        print('-- blink_portal:')
        print('\n'.join(small))
        return
    s = open(CFG, encoding='utf-8', newline='').read()
    nl = '\r\n' if '\r\n' in s else '\n'
    a = s.index('                            exit_back_m = 0, face_you = true,')
    b = s.index('parts = {', a) + len('parts = {')
    c = s.index('                            fallback = {', b)
    s = s[:b] + nl + ' ' * 32 + head + nl + nl.join(big) + nl + ' ' * 32 + '},' + nl + s[c:]
    a = s.index('                 blink_portal = { enabled = true')
    b = s.index('parts = {', a) + len('parts = {')
    c = s.index('                                  fallback = {', b)
    s = s[:b] + nl + nl.join(small) + nl + ' ' * 38 + '},' + nl + s[c:]
    open(CFG, 'w', encoding='utf-8', newline='').write(s)
    print(f'parts_lua: {len(big)} parts, {len(small)} for her blinks, written to {os.path.relpath(CFG, ROOT)}')


if __name__ == '__main__':
    main()
