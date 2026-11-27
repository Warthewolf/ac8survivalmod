"""sounds.py : ULYSSES' sounds (AC:I's Stardust set, the user's exception of 2026-11-23) -> build/ulysses/sounds/*.wav,
staged by tools/build_all.sh into AC8SurvivalMode/Sounds/ulysses (Scripts/sv_ulysses.lua CFG.specials.ulysses.sounds).

    python tools/ulysses/sounds.py      (plain python: the AC:I kit needs numpy from the user's site-packages)

From the user's AC:I install ($ACI in .env, its USRDIR) through the AC:I kit's DPL reader and vgmstream ($VGMSTREAM):
the CRI banks (ACB + AWB) cut out of their DPL entries at their @UTF, each stream decoded whole (-i: no loop) to
16-bit PCM. Nothing from AC:I is committed: the WAVs stay in build/ (git-ignored).
  fall_small.wav  the shared SFX bank (DATA94 #18) stream 71: OBJ_FALL_STARTDUST_SMALL (with the ICBM burner's)
  fall_big.wav    stream 72: OBJ_FALL_STARTDUST_LARGE / _MID (with the Aigaion's fall)
  explosion.wav   the Stardust mission's bank (DATA01 #24) stream 5: Stardust_EXPL_CLOSE_0 / _MID / _FAR
  encounter.wav   its stream 1: Stardust_Encounter
  ambient.wav     its stream 4: Stardust_Ambient (38.5 s; the user, 2026-11-24: under the whole round)
"""
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, os.path.join(REPO, 'tools'))
import env                                                     # (tools/env.py: ACI and VGMSTREAM from .env)

env.load()
ACI = env.need('ACI', "the user's AC:I folder (holds aci_kit and NPUB31347)")
VGM = env.need('VGMSTREAM', "vgmstream-cli.exe")
USR = os.path.join(ACI, 'NPUB31347', 'USRDIR')
os.environ.setdefault('ACI_USRDIR', USR)
sys.path.insert(0, os.path.join(ACI, 'aci_kit', 'tools'))
from fhm import DPL                                            # noqa: E402 (the AC:I kit)

OUT = os.path.join(REPO, 'build', 'ulysses', 'sounds')
# (bank: pac, entry, the @UTF offset in its entry (acbscan.py's), {stream: out name})
BANKS = [('DATA94', 18, 76, {71: 'fall_small.wav', 72: 'fall_big.wav'}),
         ('DATA01', 24, 30961145, {5: 'explosion.wav', 1: 'encounter.wav', 4: 'ambient.wav'})]


def main():
    os.makedirs(OUT, exist_ok=True)
    tmp = os.path.join(OUT, '_bank.acb')
    n = 0
    for pac, ent, off, want in BANKS:
        d = DPL(os.path.join(USR, pac + '.PAC')).read(ent)
        if d[off:off + 4] != b'@UTF':
            sys.exit('%s #%d: no @UTF at %d (the install differs from the scan)' % (pac, ent, off))
        with open(tmp, 'wb') as f:
            f.write(d[off:])
        for s, name in want.items():
            out = os.path.join(OUT, name)
            r = subprocess.run([VGM, '-i', '-s', str(s), '-o', out, tmp], capture_output=True, text=True)
            meta = subprocess.run([VGM, '-m', '-s', str(s), tmp], capture_output=True, text=True).stdout
            cue = (re.search(r'stream name: (.+)', meta) or re.search('(.+)', '?')).group(1).strip()
            if r.returncode != 0 or not os.path.exists(out):
                sys.exit('%s #%d stream %d: vgmstream failed: %s' % (pac, ent, s, r.stderr[-300:]))
            print('ulysses sound: %-15s %s #%d stream %d (%s), %d bytes' % (name, pac, ent, s, cue[:70], os.path.getsize(out)))
            n += 1
    os.remove(tmp)
    print('ulysses sounds: %d written to %s' % (n, OUT))


if __name__ == '__main__':
    main()
