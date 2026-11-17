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
BURST = 5.0                            # (20 in 0.74.109-0.74.110: too many sprites stacked in its 0.5 s on)
WORK = os.path.join(MAIN, 'build', 'stormfx', 'burst')
OUT = os.path.join(MAIN, 'build', 'stormfx', 'out')


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
    data = z.write()
    ZenPkg(data=data)                  # (must parse back)
    content = os.path.join(WORK, 'Content')
    shutil.rmtree(WORK, ignore_errors=True)
    dst = os.path.join(content, NEW[len('/Game/'):] + '.uasset')
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    open(dst, 'wb').write(data)
    print(f'burst: {NEW} ({len(data)} bytes): {len(LITERALS)} spawn literals {sorted(set(LITERALS.values()))} -> {BURST}')
    os.makedirs(OUT, exist_ok=True)
    r = subprocess.run([sys.executable, '-I', os.path.join(TOOLS, 'pack.py'), '--name', 'SurvivalMode_StormBurst_P',
                        '--content', content, '--out', OUT])
    if r.returncode:
        sys.exit('burst: pack.py failed')
    print(f'burst: built {OUT}/SurvivalMode_StormBurst_P (staged with TANI=1 by tools/build_all.sh; dev installs only)')


if __name__ == '__main__':
    main()
