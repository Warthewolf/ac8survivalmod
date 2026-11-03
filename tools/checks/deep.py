"""deep.py : the whole faulting thread's stack of a crash report's minidump, and the code bytes round addresses (plan F3,
from the cloud session of 2026-11-03, testing/2026-11-03/tools/deep.py; uses mdmp.py beside it).

  python -X utf8 -I tools/checks/deep.py <UEMinidump.dmp> <N> [<hex address> ...] [--map <main_<v>_<ts>.map>]

Lists the first N values inside a module from rsp to the stack's top (antivirus hook modules left out), then the 48 bytes
round rip and each address given (32 before, 16 after), when the dump holds them. As mdmp.py: a stack value is a
candidate, not a frame; --map names main.dll's from the runtime's linker map.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from mdmp import Dump, u64  # noqa: E402


def main():
    args = list(sys.argv[1:])
    mp = None
    if '--map' in args:
        k = args.index('--map')
        mp = args[k + 1]
        del args[k:k + 2]
    if len(args) < 2:
        print(__doc__)
        return
    d = Dump(args[0])
    if mp:
        print('map %s: %d main.dll symbols' % (mp, d.load_map(mp)))
    n = int(args[1])
    tid, code, addr, params, ctx = d.exception()
    regs = d.context(ctx)
    st_start, st_size, st_rva, _ = d.threads()[tid]
    rsp = regs['rsp']
    off = rsp - st_start
    data = d.b[st_rva + off: st_rva + st_size]
    print('thread stack %x..%x, rsp at +%x, %d bytes above' % (st_start, st_start + st_size, off, len(data)))
    seen = 0
    for i in range(0, len(data) - 7, 8):
        v = u64(data, i)
        m = d.mod_of(v)
        if m and not m[0].lower().startswith(('atcuf', 'bdhkm', 'antimalware')):
            print('  [rsp+0x%04x] %s' % (i, d.where(v)))
            seen += 1
            if seen >= n:
                break
    for a in [regs['rip']] + [int(x, 16) for x in args[2:]]:
        b = d.read(a - 32, 48)
        print('code at %x: %s' % (a, b.hex() if b else 'not in dump'))


if __name__ == '__main__':
    main()
