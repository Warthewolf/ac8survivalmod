"""Editable UE5.4 zen package, like scripts/zenw.py but safe on packages with wide (UTF-16) names.

Name hashes of unchanged names are kept as read; renamed or added names get a fresh hash.
Exports are written back-to-back in export-map order (true for every stock and Stonehenge package so far).

    z = ZenPkg('in.uasset')
    z.rename('PL_Mission022', 'PL_SurvivalMode')            # name-table entry
    z.set_imported_package('/Game/.../MC_Mission022', '/Game/Mods/SurvivalMode/Mission/MC_SurvivalMode')
    z.payloads[i] = new_bytes                             # export data
    open('out.uasset', 'wb').write(z.write())
"""
import struct, sys, os
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), 'scripts'))
from cityhash import city64


def name_hash(s):
    return city64(s.lower().encode('latin1'))


def export_hash(obj_path):
    """Public export hash: city64 of the lower-case UTF-16 path inside the package, e.g. 'mc_survival'."""
    return city64(obj_path.lower().encode('utf-16-le'))


def package_id(path):
    return city64(path.lower().encode('utf-16-le'))


class NameBatch:
    def __init__(self, names, hashes, hv):
        self.names, self.hashes, self.hv = names, hashes, hv

    @staticmethod
    def read(d, off):
        n = struct.unpack_from('<I', d, off)[0]
        if n == 0:
            return NameBatch([], [], b''), off + 4
        off += 8
        hv = d[off:off + 8]; off += 8
        hashes = [d[off + 8 * i:off + 8 * i + 8] for i in range(n)]; off += 8 * n
        lens = [struct.unpack_from('>H', d, off + 2 * i)[0] for i in range(n)]; off += 2 * n
        names = []
        for L in lens:
            if L & 0x8000:
                L &= 0x7fff; names.append(d[off:off + 2 * L].decode('utf-16-le')); off += 2 * L
            else:
                names.append(d[off:off + L].decode('latin1')); off += L
        return NameBatch(names, hashes, hv), off

    def write(self):
        if not self.names:
            return struct.pack('<I', 0)
        lens, strs = [], []
        for s in self.names:
            try:
                b = s.encode('latin1'); lens.append(len(s))
            except UnicodeEncodeError:
                b = s.encode('utf-16-le'); lens.append(len(s) | 0x8000)
            strs.append(b)
        body = b''.join(self.hashes) + b''.join(struct.pack('>H', L) for L in lens) + b''.join(strs)
        return struct.pack('<II', len(self.names), sum(len(s) for s in strs)) + self.hv + body

    def set(self, i, new):
        self.names[i] = new; self.hashes[i] = struct.pack('<Q', name_hash(new))

    def add(self, new):
        if new not in self.names:
            self.names.append(new); self.hashes.append(struct.pack('<Q', name_hash(new)))
        return self.names.index(new)


class ZenPkg:
    def __init__(self, path=None, data=None):
        d = data if data is not None else open(path, 'rb').read()
        self.raw = d
        (self.hasver, self.header_size, self.name_idx, self.name_num, self.flags, self.cooked_header_size,
         ih, im, ex, bu, dh, de, ipn) = struct.unpack_from('<IIIIIIiiiiiii', d, 0)
        assert not self.hasver, 'versioned zen packages are not handled'
        self.nb, o = NameBatch.read(d, 0x34)
        pad = struct.unpack_from('<Q', d, o)[0]; o += 8 + pad
        self.bulkmap = d[o:ih]
        self.imp_hashes = [struct.unpack_from('<Q', d, x)[0] for x in range(ih, im, 8)]
        self.imports = [struct.unpack_from('<Q', d, x)[0] for x in range(im, ex, 8)]
        self.exports = [bytearray(d[x:x + 72]) for x in range(ex, bu, 72)]
        self.bundles = d[bu:dh]
        self.dep_hdr = d[dh:de]
        self.dep_ent = d[de:ipn]
        self.ipn, o2 = NameBatch.read(d, ipn)
        self.imp_pkg_nums = [struct.unpack_from('<I', d, o2 + 4 * i)[0] for i in range(len(self.ipn.names))]
        o2 += 4 * len(self.ipn.names)
        self.ipn_tail = d[o2:self.header_size]
        self.payloads = []
        pos = self.header_size
        for e in self.exports:
            off, size = struct.unpack_from('<QQ', e, 0)
            assert self.header_size + off == pos, 'exports not back-to-back'
            self.payloads.append(bytearray(d[pos:pos + size])); pos += size
        self.tail = d[pos:]

    # names ---------------------------------------------------------------
    @property
    def names(self):
        return self.nb.names

    @property
    def imp_pkgs(self):
        return self.ipn.names

    def rename(self, old, new):
        i = self.nb.names.index(old); self.nb.set(i, new)

    def set_imported_package(self, old, new):
        i = self.ipn.names.index(old); self.ipn.set(i, new)

    def export_name(self, i):
        idx, num = struct.unpack_from('<II', self.exports[i], 16)
        return self.names[idx] + (f'_{num - 1}' if num else '')

    def set_export_public_hash(self, i, obj_path):
        struct.pack_into('<Q', self.exports[i], 56, export_hash(obj_path))

    def export_index(self, name):
        hits = [i for i in range(len(self.exports)) if self.export_name(i) == name]
        assert len(hits) == 1, (name, hits)
        return hits[0]

    def imported_hash_index(self, pkg_path):
        """Indices into imp_hashes used by imports of the given imported package."""
        k = self.ipn.names.index(pkg_path)
        return sorted({x & 0xffffffff for x in self.imports if x >> 62 == 2 and (x >> 32) & 0x3fffffff == k})

    # write ---------------------------------------------------------------
    def write(self):
        nb = self.nb.write()
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
        de = len(h); h += self.dep_ent
        ipn = len(h)
        h += self.ipn.write() + b''.join(struct.pack('<I', x) for x in self.imp_pkg_nums) + self.ipn_tail
        hs = len(h)
        # cooked_header_size is the editor-side header size; keep the original delta so loaders that look at it are happy
        struct.pack_into('<IIIIIIiiiiiii', h, 0, self.hasver, hs, self.name_idx, self.name_num, self.flags,
                         self.cooked_header_size, ih, im, ex, bu, dh, de, ipn)
        return bytes(h) + b''.join(bytes(p) for p in self.payloads) + self.tail


if __name__ == '__main__':
    ok = True
    for p in sys.argv[1:]:
        z = ZenPkg(p); w = z.write(); same = w == z.raw; ok &= same
        print(os.path.basename(p), 'roundtrip', same, len(w), len(z.raw))
    sys.exit(0 if ok else 1)
