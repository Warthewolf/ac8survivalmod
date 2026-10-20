"""Editable UE5.4 zen package (single or multi export). Parse -> modify lists -> write.
Only handles packages whose exports are laid out back-to-back in export-map order."""
import struct, sys, os
sys.path.insert(0, os.path.dirname(__file__))
from cityhash import city64

def _namebatch(names, hv):
    hashes = b''.join(struct.pack('<Q', city64(n.lower().encode('latin1'))) for n in names)
    lens = b''.join(struct.pack('>H', len(n)) for n in names)
    strs = b''.join(n.encode('latin1') for n in names)
    if not names: return struct.pack('<I', 0)
    return struct.pack('<II', len(names), len(strs)) + hv + hashes + lens + strs

def _read_namebatch(d, off):
    n = struct.unpack_from('<I', d, off)[0]
    if n == 0: return [], b'', off + 4
    off += 8
    hv = d[off:off+8]; off += 8 + 8*n
    lens = [struct.unpack_from('>H', d, off+2*i)[0] for i in range(n)]; off += 2*n
    out = []
    for L in lens:
        assert not L & 0x8000, 'wide names unsupported'
        out.append(d[off:off+L].decode('latin1')); off += L
    return out, hv, off

class ZenPkg:
    def __init__(self, path=None, data=None):
        d = data if data is not None else open(path, 'rb').read()
        self.raw = d
        f = struct.unpack_from('<IIIIIIiiiiiii', d, 0)
        (self.hasver, self.header_size, self.name_idx, self.name_num, self.flags, self.cooked_header_size,
         ih, im, ex, bu, dh, de, ipn) = f
        self.names, self.hv, o = _read_namebatch(d, 0x34)
        pad = struct.unpack_from('<Q', d, o)[0]; o += 8 + pad
        self.bulkmap = d[o:ih]                       # i64 size + entries
        self.imp_hashes = [struct.unpack_from('<Q', d, x)[0] for x in range(ih, im, 8)]
        self.imports = [struct.unpack_from('<Q', d, x)[0] for x in range(im, ex, 8)]
        self.exports = [bytearray(d[x:x+72]) for x in range(ex, bu, 72)]
        self.bundles = d[bu:dh]
        self.dep_hdr = d[dh:de]
        self.dep_ent = [struct.unpack_from('<i', d, x)[0] for x in range(de, ipn, 4)]
        # imported package names: name batch + u32 numbers
        self.imp_pkgs, self.ipn_hv, o2 = _read_namebatch(d, ipn)
        self.imp_pkg_nums = [struct.unpack_from('<I', d, o2+4*i)[0] for i in range(len(self.imp_pkgs))]
        o2 += 4*len(self.imp_pkgs)
        self.ipn_tail = d[o2:self.header_size]
        # export payloads
        self.payloads = []
        for e in self.exports:
            off, size = struct.unpack_from('<QQ', e, 0)
            s = self.header_size + off
            self.payloads.append(bytearray(d[s:s+size]))
        end = self.header_size + sum(len(p) for p in self.payloads)
        self.tail = d[end:]

    def write(self):
        nb = _namebatch(self.names, self.hv)
        o = 0x34 + len(nb)
        pad = (8 - (o + 8) % 8) % 8
        h = bytearray(0x34) + nb + struct.pack('<Q', pad) + bytes(pad) + self.bulkmap
        ih = len(h); h += b''.join(struct.pack('<Q', x) for x in self.imp_hashes)
        im = len(h); h += b''.join(struct.pack('<Q', x) for x in self.imports)
        ex = len(h)
        off = 0
        for e, p in zip(self.exports, self.payloads):
            struct.pack_into('<QQ', e, 0, off, len(p)); off += len(p)
            h += e
        bu = len(h); h += self.bundles
        dh = len(h); h += self.dep_hdr
        de = len(h); h += b''.join(struct.pack('<i', x) for x in self.dep_ent)
        ipn = len(h)
        h += _namebatch(self.imp_pkgs, self.ipn_hv) + b''.join(struct.pack('<I', x) for x in self.imp_pkg_nums) + self.ipn_tail
        hs = len(h)
        struct.pack_into('<IIIIIIiiiiiii', h, 0, self.hasver, hs, self.name_idx, self.name_num, self.flags,
                         self.cooked_header_size, ih, im, ex, bu, dh, de, ipn)
        return bytes(h) + b''.join(bytes(p) for p in self.payloads) + self.tail

    def name(self, s):
        if s not in self.names: self.names.append(s)
        return self.names.index(s)

if __name__ == '__main__':
    for p in sys.argv[1:]:
        z = ZenPkg(p); w = z.write()
        print(p.split('/')[-1], 'roundtrip', w == z.raw, len(w), len(z.raw))
