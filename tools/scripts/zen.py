import struct, sys

class Zen:
    def __init__(self, path):
        self.path = path
        self.d = open(path,'rb').read()
        d = self.d
        (self.hasver, self.header_size, nidx, nnum, self.flags, self.cooked_header_size,
         self.imp_hashes_off, self.import_off, self.export_off, self.bundle_off,
         self.dep_hdr_off, self.dep_ent_off, self.imp_pkg_names_off) = struct.unpack_from('<IIIIIIiiiiiii', d, 0)
        off = 0x34
        if self.hasver:
            raise Exception('versioned')
        self.names, off = self.read_namebatch(off)
        self.name_end = off
        self.pkgname = self.names[nidx]
        # import map: uint64 each
        self.imports = [struct.unpack_from('<Q', d, o)[0] for o in range(self.import_off, self.export_off, 8)]
        # export map entries: 72 bytes
        self.exports = []
        for o in range(self.export_off, self.bundle_off, 72):
            (cooked_off, cooked_size, on_idx, on_num, outer, cls, sup, tmpl, pub_hash, oflags, filter_flags) = struct.unpack_from('<QQIIQQQQQIB', d, o)
            self.exports.append(dict(off=cooked_off, size=cooked_size, name=self.names[on_idx] + (f'_{on_num-1}' if on_num else ''), outer=outer, cls=cls, sup=sup, tmpl=tmpl, pubhash=pub_hash, oflags=oflags, entry_off=o))
        self.imp_hashes = [struct.unpack_from('<Q', d, o)[0] for o in range(self.imp_hashes_off, self.import_off, 8)]

    def read_namebatch(self, off):
        d = self.d
        n, nbytes = struct.unpack_from('<II', d, off); off += 8
        if n == 0:
            return [], off
        hashver = struct.unpack_from('<Q', d, off)[0]; off += 8
        off += 8*n
        lens = [struct.unpack_from('>H', d, off+2*i)[0] for i in range(n)]; off += 2*n
        names = []
        for L in lens:
            if L & 0x8000:
                L &= 0x7fff
                s = d[off:off+2*L].decode('utf-16-le', 'replace'); off += 2*L
            else:
                s = d[off:off+L].decode('latin1'); off += L
            names.append(s)
        return names, off

    def export_data(self, i):
        e = self.exports[i]
        # cooked serial offset is relative to cooked header; data begins at header_size
        start = self.header_size + (e['off'] - self.cooked_header_size)
        return start, self.d[start:start+e['size']]

if __name__ == '__main__':
    z = Zen(sys.argv[1])
    print('pkg', z.pkgname, 'header', hex(z.header_size), 'cookedhdr', hex(z.cooked_header_size), 'size', hex(len(z.d)))
    print('names', len(z.names))
    for i,n in enumerate(z.names):
        print(i, n)
    print('imports', [hex(x) for x in z.imports])
    for i,e in enumerate(z.exports):
        print('export', i, e['name'], hex(e['off']), hex(e['size']), 'cls', hex(e['cls']))
