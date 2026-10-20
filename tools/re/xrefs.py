# xrefs.py <dll> <regex> : find strings (ASCII/UTF-16) matching regex and the code (RIP-relative LEA/MOV) that uses them.
import re, struct, sys
d = open(sys.argv[1], 'rb').read(); pat = re.compile(sys.argv[2], re.I)
pe = struct.unpack_from('<I', d, 0x3c)[0]; nsec = struct.unpack_from('<H', d, pe + 6)[0]
optsz = struct.unpack_from('<H', d, pe + 20)[0]; opt = pe + 24
secs = []
for i in range(nsec):
    o = opt + optsz + 40 * i
    secs.append((d[o:o + 8].rstrip(b'\0').decode(),) + struct.unpack_from('<IIII', d, o + 8))
def rva(off):
    for n, vs, va, rs, ra in secs:
        if ra <= off < ra + rs: return va + off - ra
def off(r):
    for n, vs, va, rs, ra in secs:
        if va <= r < va + rs: return r - va + ra
text = [s for s in secs if s[0] == '.text'][0]; t0, tl, tva = text[4], text[3], text[2]
strs = []
for m in re.finditer(rb'[\x20-\x7e]{4,}\x00', d):
    s = m.group()[:-1].decode()
    if pat.search(s): strs.append((rva(m.start()), s))
for m in re.finditer(rb'(?:[\x20-\x7e]\x00){4,}\x00\x00', d):
    s = m.group()[:-2].decode('utf-16-le')
    if pat.search(s): strs.append((rva(m.start()), 'W:' + s))
targets = {r: s for r, s in strs if r is not None}
code = d[t0:t0 + tl]
hits = {}
for i in range(len(code) - 7):
    if code[i] in (0x48, 0x4c) and code[i + 1] in (0x8d, 0x8b) and (code[i + 2] & 0xc7) == 0x05:
        disp = struct.unpack_from('<i', code, i + 3)[0]; tgt = tva + i + 7 + disp
        if tgt in targets: hits.setdefault(tgt, []).append(tva + i)
for r, s in sorted(targets.items()):
    print(f'{r:#07x} {s[:90]!r}  used at', ' '.join(f'{x:#x}' for x in hits.get(r, [])))
