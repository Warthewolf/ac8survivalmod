"""sounds.py : the SOLG's sounds (AC:I's own SOLG bank, the user's exception of 2026-11-23: "start with the SOLG";
docs/rules/sources_and_toolchain.md) -> build/solg/sounds/*.wav, staged by tools/build_all.sh into
AC8SurvivalMode/Sounds/solg (Scripts/sv_solg.lua SOLG.C.sounds).

    python tools/solg/sounds.py      (plain python: the AC:I kit needs numpy from the user's site-packages)

From the user's AC:I install ($ACI in .env, its USRDIR) through the AC:I kit's DPL reader and vgmstream ($VGMSTREAM),
as tools/ulysses/sounds.py: the bank (ACB + AWB) cut out of its DPL entry at its @UTF, each stream decoded whole (-i: no
loop) to 16-bit PCM. Nothing from AC:I is committed: the WAVs stay in build/ (git-ignored). The bank (DATA92 #528) has
six streams and no engine or laser of its own (2026-11-28, vgmstream -m):
  break_small_1.wav  stream 1: SOLG_BREAK_BIG_01; SOLG_BREAK_SML_01 (5.7 s)
  break_small_2.wav  stream 2: SOLG_BREAK_SML_02 (7.8 s)
  break_small_3.wav  stream 3: SOLG_BREAK_BIG_02; SOLG_BREAK_SML_03 (4.7 s)
  break_small_4.wav  stream 4: SOLG_BREAK_SML_04 (7.6 s)
  break_big_1.wav    stream 5: SOLG_BREAK_BIG_01 (8.3 s)
  break_big_2.wav    stream 6: SOLG_BREAK_BIG_02 (8.5 s)
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

OUT = os.path.join(REPO, 'build', 'solg', 'sounds')
# (bank: pac, entry, the @UTF offset in its entry (acbscan.py's), {stream: out name})
BANKS = [('DATA92', 528, 31071470, {1: 'break_small_1.wav', 2: 'break_small_2.wav', 3: 'break_small_3.wav',
                                    4: 'break_small_4.wav', 5: 'break_big_1.wav', 6: 'break_big_2.wav'})]


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
            print('solg sound: %-17s %s #%d stream %d (%s), %d bytes' % (name, pac, ent, s, cue[:70], os.path.getsize(out)))
            n += 1
    os.remove(tmp)
    print('solg sounds: %d written to %s' % (n, OUT))


if __name__ == '__main__':
    main()
