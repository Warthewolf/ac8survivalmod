"""mksig.py : masked byte signatures for functions in AceCombat8.exe, checked for uniqueness.

  python mksig.py <hex va> [min bytes] [name]

Disassembles from the address, wildcards every rel32 (call/jmp/jcc) and RIP-relative displacement, and grows the
pattern instruction by instruction until it matches exactly once in the executable sections. Prints a C array pair
(bytes + mask) for runtime/sigs.h, the match count, and the disassembly it covers.
"""
import re, struct, subprocess, sys
from exe import Exe, OBJDUMP


def insns(x, va, n=160):
    out = subprocess.run([OBJDUMP, '-d', '-M', 'intel', '--start-address=%#x' % va, '--stop-address=%#x' % (va + n),
                          x.path], capture_output=True, text=True).stdout
    res = []
    for line in out.splitlines():
        m = re.match(r'\s*([0-9a-f]+):\s+((?:[0-9a-f]{2} )+)\s*(.*)', line)
        if m:
            res.append((int(m.group(1), 16), bytes.fromhex(m.group(2).replace(' ', '')), m.group(3)))
    return res


def mask_for(addr, raw, text):
    """1 = fixed byte, 0 = wildcard."""
    mask = [1] * len(raw)
    end = addr + len(raw)
    targets = [int(t, 16) for t in re.findall(r'0x([0-9a-f]{6,})', text)]
    for t in targets:
        disp = struct.pack('<i', (t - end + (1 << 31)) % (1 << 32) - (1 << 31))
        k = raw.rfind(disp)
        if k < 0:   # RIP-relative with an immediate after the displacement
            for imm in (1, 2, 4):
                d2 = struct.pack('<i', (t - end + imm + (1 << 31)) % (1 << 32) - (1 << 31))
                k = raw.rfind(d2, 0, len(raw) - imm)
                if k >= 0: break
        if k >= 0:
            for i in range(k, k + 4): mask[i] = 0
    if raw[0] in (0xe8, 0xe9) and len(raw) == 5:
        mask[1:5] = [0] * 4
    return mask


def count(x, pat, mask):
    rx = b''.join(re.escape(bytes([b])) if m else b'.' for b, m in zip(pat, mask))
    rx = re.compile(rx, re.S)
    n, first = 0, None
    for name, sva, vs, ra, rs, ch in x.code_sections():
        for mt in rx.finditer(x.d, ra, ra + rs):
            n += 1
            if first is None: first = x.base + sva + mt.start() - ra
            if n > 1: return n, first
    return n, first


def main():
    x = Exe()
    va = int(sys.argv[1], 16)
    minb = int(sys.argv[2]) if len(sys.argv) > 2 else 16
    name = sys.argv[3] if len(sys.argv) > 3 else 'kSig'
    pat, mask, lines = b'', [], []
    for addr, raw, text in insns(x, va):
        pat += raw; mask += mask_for(addr, raw, text); lines.append('%x: %s' % (addr, text))
        if len(pat) < minb: continue
        n, first = count(x, pat, mask)
        if n == 1 and first == va: break
    else:
        print('no unique signature within the window'); return
    def carr(bs):
        rows = [', '.join('0x%02X' % b for b in bs[i:i + 12]) for i in range(0, len(bs), 12)]
        return '{\n    ' + ',\n    '.join(rows) + ',\n}'
    print('/* %s */' % ' | '.join(l.split(': ', 1)[1] for l in lines[:6]))
    print('static const uint8_t %s[%d] = %s;' % (name, len(pat), carr(pat)))
    if 0 in mask:
        print('static const uint8_t %sMask[%d] = %s;' % (name, len(mask), carr(mask)))
    print('// unique: %d match at %#x, %d bytes, %d wildcards' % (n, first, len(pat), mask.count(0)))


if __name__ == '__main__':
    main()
