"""pad.py <container.utoc> : hard rule 8 for a container retoc made (as tools/pack.py does for SurvivalMode_P): the
game reads every compression block rounded up to 16 bytes, so the .ucas is padded until every such read fits, then
every block is checked."""
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'scripts'))
from utoc import Utoc

utoc = sys.argv[1]
ucas = utoc[:-5] + '.ucas'
toc = Utoc(utoc)
need = max(off + ((csz + 15) & ~15) for off, csz, usz, m in toc.blocks)
have = os.path.getsize(ucas)
if need > have:
    with open(ucas, 'ab') as f:
        f.write(b'\0' * (need - have))
    print(f'padded {os.path.basename(ucas)} by {need - have} bytes so the last block can be read whole')
size = os.path.getsize(ucas)
for i, (off, csz, usz, m) in enumerate(toc.blocks):
    assert off + ((csz + 15) & ~15) <= size, f'block {i} at {off} (+{csz}) reads past the end of the .ucas ({size})'
print(f'checked {len(toc.blocks)} blocks: every 16-byte-aligned read fits in the {size}-byte .ucas')
