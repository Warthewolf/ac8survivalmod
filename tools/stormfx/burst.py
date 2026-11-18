"""burst.py : NS_SV_CloudBurst, AC8's own Mission 12 cloud lightning (NS_CloudLightning) copied under Survival's path with its
emitters' spawn literals raised, so it flashes the moment it's switched on (tools/stormfx/README.md; the user, 2026-11-17:
"extract or reverse engineer how ace combat 8 gets it to work").

Why: the stock system is three looping spawn-rate emitters (FarLightning001 / 002, NearLightning001); in the cooked build
their rapid-iteration inputs are baked into the system update script's literal table (export 34 of the stock package:
0.08, 0.22, 0.5, 0.15, 0.1, 0.4, 0.05 between the table's ints), so one switched on at a bolt flashes when its rate next
comes round: at a random moment. Raised to BURST each emitter spawns in its first frame; the storm switches it off a
moment later (sv_fleet_storm.lua bolt_glow.burst_life_s), the particles already up finish their own flicker.
Unlike NS_SV_CloudFlash (tools/stormfx/ue_flash.py, cooked in our own 5.4) this is Bandai's own compiled system: only
its name and seven floats change, so AC8 runs its own bytecode and shaders.

    python -I tools/stormfx/burst.py      -> build/stormfx/out/SurvivalMode_StormBurst_P.utoc / .ucas
"""
import os
import shutil
import struct
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
TOOLS = os.path.dirname(HERE)
ROOT = os.path.dirname(TOOLS)
sys.path.insert(0, TOOLS)
from zenpkg import ZenPkg   # noqa: E402

MAIN = subprocess.run(['git', 'rev-parse', '--path-format=absolute', '--git-common-dir'], capture_output=True, text=True,
                      cwd=ROOT).stdout.strip()
MAIN = os.path.dirname(MAIN) if MAIN else ROOT
STOCK = os.path.join(ROOT, 'build', 'stock')
if not os.path.isdir(STOCK):
    STOCK = os.path.join(MAIN, 'build', 'stock')
OLD = '/Game/VFX/Environment/Common/Lightning/CloudLightning/NS_CloudLightning'
NEW = '/Game/Mods/SurvivalMode/StormFx/NS_SV_CloudBurst'
SCRIPT_EXPORT = 34                     # (the system update script: its literal table holds the emitters' spawn inputs)
LITERALS = {4440: 0.08, 4444: 0.22, 4448: 0.5, 4460: 0.15, 4464: 0.1, 4472: 0.4, 4480: 0.05}
BURST = 4.0                            # (0.74.130: 20 in 0.74.115-0.74.129 whited the night sky out even at DIM 300: autotest whiteout runs 20261117_161131-163054; 5 in 0.74.111-0.74.114: 2-3 flickering sprites, the pictures mostly dark)
# ((0.74.114) AC8's near lightning instance fades its sprites out 0.5-3.5 km from the camera (MI_NearCloudLightning001's
# FarFade_Start 50000, FarFade_Distance 300000, emissive 5000; the far one, MI_CloudLightning001, has no fade): nothing
# showed at 7-10 km in 0.74.113's burstwatch. A copy with the fade pushed out and half the light, which the burst's
# sprites use: only scalar values change, so AC8's own material and shaders draw it
MI_OLD = '/Game/VFX/Environment/Common/Lightning/CloudLightning/MI_NearCloudLightning001'
MI_NEW = '/Game/Mods/SurvivalMode/StormFx/MI_SV_CloudFlashNear'
MI_VALUES = {42: (5000.0, 150.0),   # (2500 in 0.74.114-0.74.115, 800 in 0.74.116: saturated white)
              79: (300000.0, 1000000.0), 116: (50000.0, 3000000.0)}   # (emissive, fade length, fade start)
# ((0.74.118) the user, 2026-11-17: "I think the cloud burst is too big, i liked the vanilla look": AC8's own instances as
# they are (its brightness and its fade), only the timing patched; the copies above stay for a later choice
VANILLA = True
# ((0.74.129) the user flying 0.74.128's night storm, a picture of the sky blown out white: "we'll need to tone down the
# cloud burst brightness": VANILLA's look (AC8's fades and sizes) with only the emissive of both instances lowered, on
# copies (MI_SV_CloudFlashNear / Far, as the non-VANILLA route); None: AC8's own instances untouched
DIM = 40.0                             # (AC8's 5000; 300 in 0.74.129)
# ((2026-11-17) the user: "need to increase the brightness of the lightning bolt") the bolts' own copy of the near instance
# (sv_fleet.lua bolts.material_bright), built whatever VANILLA says: brighter, its fade pushed out to 30 km
BOLT_MI = '/Game/Mods/SurvivalMode/StormFx/MI_SV_StormBolt'
BOLT_VALUES = {42: (5000.0, 15000.0), 79: (300000.0, 1000000.0), 116: (50000.0, 3000000.0)}
WORK = os.path.join(MAIN, 'build', 'stormfx', 'burst')
OUT = os.path.join(MAIN, 'build', 'stormfx', 'out')


# ((0.74.116) the far emitters' instance too (MI_CloudLightning001: emissive 5000, no fade): 0.74.115's flash at 10 km was
# saturated white
MIF_OLD = '/Game/VFX/Environment/Common/Lightning/CloudLightning/MI_CloudLightning001'
MIF_NEW = '/Game/Mods/SurvivalMode/StormFx/MI_SV_CloudFlashFar'
MIF_VALUES = {42: (5000.0, 150.0)}    # (800 in 0.74.116: saturated white)


def instance(MI_OLD=MI_OLD, MI_NEW=MI_NEW, MI_VALUES=MI_VALUES):
    """A copy of a stock lightning instance with scalar values changed -> its bytes (near: its fade pushed out)."""
    src = os.path.join(STOCK, MI_OLD[len('/Game/'):] + '.uasset')
    if not os.path.exists(src):
        sys.exit(f'burst: no stock {src} (sh tools/get_stock.sh {MI_OLD[len("/Game/"):]}.uasset)')
    m = ZenPkg(src)
    p = m.payloads[0]
    for off, (want, new) in MI_VALUES.items():
        got = struct.unpack_from('<f', p, off)[0]
        if got != want:
            sys.exit(f'burst: {MI_OLD} at {off} is {got}, not {want}: the stock package changed')
        struct.pack_into('<f', p, off, new)
    old_short, new_short = MI_OLD.rsplit('/', 1)[1], MI_NEW.rsplit('/', 1)[1]
    i = m.export_index(old_short)
    m.rename(MI_OLD, MI_NEW)
    m.rename(old_short, new_short)
    m.set_export_public_hash(i, new_short)
    data = m.write()
    ZenPkg(data=data)
    print(f'burst: {MI_NEW}: ' + ', '.join(f'{a:g} -> {b:g}' for a, b in MI_VALUES.values()))
    return data


def main():
    src = os.path.join(STOCK, OLD[len('/Game/'):] + '.uasset')
    if not os.path.exists(src):
        sys.exit(f'burst: no stock {src} (tools/get_stock.sh)')
    z = ZenPkg(src)
    p = z.payloads[SCRIPT_EXPORT]
    for off, want in LITERALS.items():
        got = struct.unpack_from('<f', p, off)[0]
        if abs(got - want) > 1e-4:
            sys.exit(f'burst: export {SCRIPT_EXPORT} at {off} is {got}, not {want}: the stock package changed (re-find the table)')
        struct.pack_into('<f', p, off, BURST)
    old_short, new_short = OLD.rsplit('/', 1)[1], NEW.rsplit('/', 1)[1]
    i = z.export_index(old_short)
    z.rename(OLD, NEW)
    z.rename(old_short, new_short)
    z.set_export_public_hash(i, new_short)
    mi = mif = None
    if not VANILLA or DIM:
        near_values = MI_VALUES if not VANILLA else {42: (5000.0, DIM)}
        far_values = MIF_VALUES if not VANILLA else {42: (5000.0, DIM)}
        # the near emitter's sprites on our instance (the import's package and its object's public hash)
        from zenpkg import export_hash
        hs = z.imported_hash_index(MI_OLD)
        assert len(hs) == 1 and z.imp_hashes[hs[0]] == export_hash(MI_OLD.rsplit('/', 1)[1]), (MI_OLD, hs)
        z.imp_hashes[hs[0]] = export_hash(MI_NEW.rsplit('/', 1)[1])
        z.set_imported_package(MI_OLD, MI_NEW)
        mi = instance(MI_OLD, MI_NEW, near_values)
        hs = z.imported_hash_index(MIF_OLD)
        assert len(hs) == 1 and z.imp_hashes[hs[0]] == export_hash(MIF_OLD.rsplit('/', 1)[1]), (MIF_OLD, hs)
        z.imp_hashes[hs[0]] = export_hash(MIF_NEW.rsplit('/', 1)[1])
        z.set_imported_package(MIF_OLD, MIF_NEW)
        mif = instance(MIF_OLD, MIF_NEW, far_values)
        if VANILLA:
            print(f"burst: AC8's own look (VANILLA), only its emissive 5000 -> {DIM:g} (DIM)")
    else:
        print('burst: AC8\'s own lightning instances as they are (VANILLA: the user, "i liked the vanilla look")')
    data = z.write()
    ZenPkg(data=data)                  # (must parse back)
    content = os.path.join(WORK, 'Content')
    shutil.rmtree(WORK, ignore_errors=True)
    dst = os.path.join(content, NEW[len('/Game/'):] + '.uasset')
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    open(dst, 'wb').write(data)
    if mi is not None:
        open(os.path.join(content, MI_NEW[len('/Game/'):] + '.uasset'), 'wb').write(mi)
        open(os.path.join(content, MIF_NEW[len('/Game/'):] + '.uasset'), 'wb').write(mif)
    open(os.path.join(content, BOLT_MI[len('/Game/'):] + '.uasset'), 'wb').write(instance(MI_OLD, BOLT_MI, BOLT_VALUES))
    print(f'burst: {NEW} ({len(data)} bytes): {len(LITERALS)} spawn literals {sorted(set(LITERALS.values()))} -> {BURST}')
    os.makedirs(OUT, exist_ok=True)
    r = subprocess.run([sys.executable, '-I', os.path.join(TOOLS, 'pack.py'), '--name', 'SurvivalMode_StormBurst_P',
                        '--content', content, '--out', OUT])
    if r.returncode:
        sys.exit('burst: pack.py failed')
    print(f'burst: built {OUT}/SurvivalMode_StormBurst_P (staged with TANI=1 by tools/build_all.sh; dev installs only)')


if __name__ == '__main__':
    main()
