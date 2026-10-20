import struct
TYPES = ['Byte','Bool','Int','Float','Object','Name','Delegate','Double','Array','Struct','Str','Text','Interface',
 'MulticastDelegate','WeakObject','LazyObject','AssetObject','SoftObject','UInt64','UInt32','UInt16','Int64','Int16','Int8',
 'Map','Set','Enum','FieldPath','Optional','Utf8Str','AnsiStr']
class Usmap:
    def __init__(self, path):
        d = open(path,'rb').read()
        magic, ver = struct.unpack_from('<HB', d, 0); o = 3
        assert magic == 0x30C4
        self.ver = ver
        if ver >= 1:
            hv = struct.unpack_from('<i', d, o)[0]; o += 4
            if hv:
                o += 4 + 4  # FileVersionUE4/UE5
                n = struct.unpack_from('<i', d, o)[0]; o += 4 + n*20
                o += 4
        comp, csz, dsz = struct.unpack_from('<BII', d, o); o += 9
        assert comp == 0, comp
        self.d = d[o:o+dsz]; d = self.d; o = 0
        n = struct.unpack_from('<I', d, o)[0]; o += 4
        names = []
        for i in range(n):
            if ver >= 2: L = struct.unpack_from('<H', d, o)[0]; o += 2
            else: L = d[o]; o += 1
            names.append(d[o:o+L].decode('utf-8','replace')); o += L
        self.names = names
        ne = struct.unpack_from('<I', d, o)[0]; o += 4
        self.enums = {}
        for i in range(ne):
            nm = names[struct.unpack_from('<I', d, o)[0]]; o += 4
            if ver >= 3: c = struct.unpack_from('<H', d, o)[0]; o += 2
            else: c = d[o]; o += 1
            ents = {}
            for k in range(c):
                if ver >= 4: v = struct.unpack_from('<q', d, o)[0]; o += 8
                else: v = k
                en = names[struct.unpack_from('<I', d, o)[0]]; o += 4
                ents[v] = en
            self.enums[nm] = ents
        ns = struct.unpack_from('<I', d, o)[0]; o += 4
        self.structs = {}
        self._o = o
        for i in range(ns):
            nm = names[struct.unpack_from('<I', d, self._o)[0]]; self._o += 4
            sup = struct.unpack_from('<I', d, self._o)[0]; self._o += 4
            sup = names[sup] if sup != 0xffffffff else None
            pc, spc = struct.unpack_from('<HH', d, self._o); self._o += 4
            props = []
            for k in range(spc):
                idx, asz, pn = struct.unpack_from('<HBI', d, self._o); self._o += 7
                t = self._ptype()
                props.append((idx, asz, names[pn], t))
            self.structs[nm] = dict(super=sup, count=pc, props=props)
    def _ptype(self):
        d = self.d
        t = d[self._o]; self._o += 1
        tn = TYPES[t] if t < len(TYPES) else f'?{t}'
        if tn == 'Enum':
            inner = self._ptype(); en = self.names[struct.unpack_from('<I', d, self._o)[0]]; self._o += 4
            return ('Enum', inner, en)
        if tn == 'Struct':
            sn = self.names[struct.unpack_from('<I', d, self._o)[0]]; self._o += 4
            return ('Struct', sn)
        if tn in ('Array','Set','Optional'):
            return (tn, self._ptype())
        if tn == 'Map':
            k = self._ptype(); v = self._ptype(); return ('Map', k, v)
        return (tn,)
    def schema(self, sname):
        """flat list index->(name,type) incl. supers"""
        chain = []
        s = sname
        while s:
            st = self.structs.get(s)
            if st is None: break
            chain.append(st); s = st['super']
        out = {}; base = 0  # derived struct's own props first, then super's (CUE4Parse ordering)
        for st in chain:
            for idx, asz, pn, t in st['props']:
                for a in range(asz):
                    out[base + idx + a] = (pn if asz == 1 else f'{pn}[{a}]', t)
            base += st['count']
        return out
