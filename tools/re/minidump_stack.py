# minidump_stack.py <file.dmp> [words] : the exception, and the return-address-looking values on the faulting
# thread's stack, each mapped to its module (+offset). Enough to see which modules were on the stack in a crash.
import struct, sys

d = open(sys.argv[1], 'rb').read()
WORDS = int(sys.argv[2]) if len(sys.argv) > 2 else 3000
assert d[:4] == b'MDMP'
nstreams, dir_rva = struct.unpack_from('<II', d, 8)
streams = {}
for i in range(nstreams):
    t, size, rva = struct.unpack_from('<III', d, dir_rva + 12 * i)
    streams[t] = (rva, size)


def utf16(rva):
    n = struct.unpack_from('<I', d, rva)[0]
    return d[rva + 4:rva + 4 + n].decode('utf-16-le')


mods = []
rva, _ = streams[4]                                           # ModuleListStream
n = struct.unpack_from('<I', d, rva)[0]
for i in range(n):
    o = rva + 4 + 108 * i
    base, size = struct.unpack_from('<QI', d, o)
    name = utf16(struct.unpack_from('<I', d, o + 20)[0])
    mods.append((base, size, name))


def where(a):
    for base, size, name in mods:
        if base <= a < base + size:
            return f'{name.split(chr(92))[-1]}+{a - base:#x}'
    return None


mem = []                                                       # (start, size, file offset)
if 9 in streams:                                               # Memory64ListStream
    rva, _ = streams[9]
    n, base_rva = struct.unpack_from('<QQ', d, rva)
    off = base_rva
    for i in range(n):
        start, size = struct.unpack_from('<QQ', d, rva + 16 + 16 * i)
        mem.append((start, size, off)); off += size
if 5 in streams:                                               # MemoryListStream
    rva, _ = streams[5]
    n = struct.unpack_from('<I', d, rva)[0]
    for i in range(n):
        start, size, mrva = struct.unpack_from('<QII', d, rva + 4 + 16 * i)
        mem.append((start, size, mrva))


def read(addr, n):
    for start, size, off in mem:
        if start <= addr and addr + n <= start + size:
            return d[off + addr - start: off + addr - start + n]
    return None


rva, _ = streams[6]                                            # ExceptionStream
tid = struct.unpack_from('<I', d, rva)[0]
code, flags, rec, addr = struct.unpack_from('<IIQQ', d, rva + 8)
ctx_size, ctx_rva = struct.unpack_from('<II', d, rva + 8 + 152 + 8 - 8)
print(f'exception {code:#x} at {addr:#x} ({where(addr)}) thread {tid}')
ctx = d[ctx_rva:ctx_rva + ctx_size]
rsp = struct.unpack_from('<Q', ctx, 0x98)[0]; rip = struct.unpack_from('<Q', ctx, 0xF8)[0]
print(f'rip {rip:#x} ({where(rip)})  rsp {rsp:#x}')
seen = 0
for k in range(WORDS):
    b = read(rsp + 8 * k, 8)
    if b is None: break
    v = struct.unpack('<Q', b)[0]
    w = where(v)
    if w and not w.startswith('ntdll') and not w.startswith('KERNELBASE'):
        print(f'  [rsp+{8 * k:#06x}] {v:#x} {w}'); seen += 1
        if seen > 80: break
print('modules of interest:', [m[2].split(chr(92))[-1] for m in mods if any(x in m[2] for x in ('main.dll', 'UE4SS', 'lua', 'SkinSlot'))])
