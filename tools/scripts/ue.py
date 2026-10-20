"""Minimal UE5.4 unversioned-property reader for legacy (.uasset/.uexp) and zen packages, driven by a usmap."""
import struct, pickle, sys, os
sys.path.insert(0, os.path.dirname(__file__))
from usmap import Usmap
U = pickle.load(open(os.path.join(os.path.dirname(__file__), '..', 'usmap.pkl'), 'rb'))

NATIVE = {
 'Vector': lambda r: (r.f64(), r.f64(), r.f64()), 'Vector2D': lambda r: (r.f64(), r.f64()),
 'Vector4': lambda r: tuple(r.f64() for _ in range(4)), 'Rotator': lambda r: (r.f64(), r.f64(), r.f64()),
 'Quat': lambda r: tuple(r.f64() for _ in range(4)), 'Guid': lambda r: r.raw(16).hex(),
 'Color': lambda r: r.raw(4).hex(), 'LinearColor': lambda r: (r.f32(), r.f32(), r.f32(), r.f32()),
 'IntPoint': lambda r: (r.i32(), r.i32()), 'IntVector': lambda r: (r.i32(), r.i32(), r.i32()),
 'DateTime': lambda r: r.i64(), 'Timespan': lambda r: r.i64(), 'FrameNumber': lambda r: r.i32(),
 'SoftObjectPath': lambda r: r.softpath(), 'SoftClassPath': lambda r: r.softpath(),
 'GameplayTagContainer': lambda r: [r.fname() for _ in range(r.i32())],
 'Box2D': lambda r: (r.f64(), r.f64(), r.f64(), r.f64(), r.u8()),
 'Box': lambda r: (tuple(r.f64() for _ in range(6)), r.u8()),
}

class Reader:
    def __init__(self, data, names, o=0, soft_list=None, zen=False):
        self.d = data; self.o = o; self.names = names; self.soft_list = soft_list; self.zen = zen
    def raw(self, n): v = self.d[self.o:self.o+n]; self.o += n; return v
    def u8(self): v = self.d[self.o]; self.o += 1; return v
    def i8(self): return struct.unpack('<b', self.raw(1))[0]
    def u16(self): return struct.unpack('<H', self.raw(2))[0]
    def i16(self): return struct.unpack('<h', self.raw(2))[0]
    def i32(self): return struct.unpack('<i', self.raw(4))[0]
    def u32(self): return struct.unpack('<I', self.raw(4))[0]
    def i64(self): return struct.unpack('<q', self.raw(8))[0]
    def u64(self): return struct.unpack('<Q', self.raw(8))[0]
    def f32(self): return struct.unpack('<f', self.raw(4))[0]
    def f64(self): return struct.unpack('<d', self.raw(8))[0]
    def fname(self):
        i, n = struct.unpack('<II', self.raw(8))
        s = self.names[i] if i < len(self.names) else f'?{i}'
        return s if n == 0 else f'{s}_{n-1}'
    def fstr(self):
        L = self.i32()
        if L == 0: return ''
        if L < 0: s = self.raw(-2*L).decode('utf-16-le'); return s[:-1]
        return self.raw(L)[:-1].decode('latin1')
    def softpath(self):
        if self.soft_list is not None and not self.zen:
            idx = self.i32(); return self.soft_list[idx]
        a = self.fname(); b = self.fname(); c = self.fstr()
        return f'{a}.{b}' + (f':{c}' if c else '')
    def ftext(self):
        flags = self.u32(); ht = self.i8()
        if ht == -1:
            has = self.u32()
            return {'invariant': self.fstr()} if has else ''
        if ht == 0:
            return {'ns': self.fstr(), 'key': self.fstr(), 'src': self.fstr()}
        if ht == 11:
            return {'table': self.fname(), 'key': self.fstr()}
        raise Exception(f'text history {ht} @ {self.o}')
    def header(self):
        frags = []
        while True:
            h = self.u16(); frags.append((h & 0x7f, bool(h & 0x80), h >> 9))
            if h & 0x100: break
        nz = sum(f[2] for f in frags if f[1]); zm = []
        if nz:
            if nz <= 8: w = self.u8(); zm = [(w>>i)&1 for i in range(nz)]
            elif nz <= 16: w = self.u16(); zm = [(w>>i)&1 for i in range(nz)]
            else:
                for k in range((nz+31)//32):
                    w = self.u32(); zm += [(w>>i)&1 for i in range(32)]
                zm = zm[:nz]
        out = []; p = 0; zi = 0
        for sk, hz, vn in frags:
            p += sk
            for k in range(vn):
                zz = zm[zi] if hz else 0
                if hz: zi += 1
                out.append((p, bool(zz))); p += 1
        return out

def read_value(r, t, mode='normal'):
    k = t[0]
    if k == 'Bool': return bool(r.u8())
    if k == 'Byte': return r.u8()
    if k == 'Int8': return r.i8()
    if k == 'Int16': return r.i16()
    if k == 'UInt16': return r.u16()
    if k == 'Int': return r.i32()
    if k == 'UInt32': return r.u32()
    if k == 'Int64': return r.i64()
    if k == 'UInt64': return r.u64()
    if k == 'Float': return r.f32()
    if k == 'Double': return r.f64()
    if k == 'Name': return r.fname()
    if k == 'Str': return r.fstr()
    if k == 'Text': return r.ftext()
    if k in ('Object', 'WeakObject', 'LazyObject', 'Interface'): return ('obj', r.i32())
    if k in ('SoftObject', 'AssetObject'): return r.softpath()
    if k == 'Enum':
        en = U.enums.get(t[2], {})
        if mode == 'normal':
            v = read_value(r, t[1])
            return f'{t[2]}::{en.get(v, v)}' if False else (en.get(v, v) if not isinstance(v, int) or v in en else v)
        return r.fname()
    if k == 'Struct': return read_struct(r, t[1])
    if k == 'Array':
        n = r.i32(); return [read_value(r, t[1], 'array') for _ in range(n)]
    if k == 'Set':
        rm = r.i32(); n = r.i32(); return [read_value(r, t[1], 'array') for _ in range(n)]
    if k == 'Map':
        rm = r.i32(); n = r.i32(); return [(read_value(r, t[1], 'array'), read_value(r, t[2], 'array')) for _ in range(n)]
    raise Exception(f'unhandled type {t} @ {r.o}')

def read_struct(r, sname):
    if sname in NATIVE: return NATIVE[sname](r)
    return read_props(r, sname)

def read_props(r, sname):
    sc = U.schema(sname)
    out = {}
    for p, zero in r.header():
        if p not in sc: raise Exception(f'{sname}: prop {p} not in schema @ {r.o}')
        nm, t = sc[p]
        if zero: out[nm] = ('ZERO',); continue
        st = r.o
        try:
            out[nm] = read_value(r, t)
        except Exception as e:
            raise Exception(f'{sname}.{nm} @ {st}: {e}') from None
    return out

class Legacy:
    def __init__(self, path):
        d = open(path, 'rb').read(); self.d = d
        self.uexp = open(path[:-6] + 'uexp', 'rb').read() if os.path.exists(path[:-6] + 'uexp') else b''
        r = Reader(d, [])
        tag = r.u32(); lfv = r.i32()
        if lfv != -4: r.i32()
        ue4 = r.i32(); ue5 = r.i32() if lfv <= -8 else 0; lic = r.i32()
        if ue5 == 0: ue5 = 1012
        self.ue5 = ue5
        if ue5 >= 1016: r.raw(20); 
        ncv = r.i32(); r.raw(ncv * 20)
        self.total_header = r.i32()
        self.pkgname = r.fstr()
        self.flags = r.u32()
        self.name_count = r.i32(); self.name_off = r.i32()
        self.soft_count = 0
        if ue5 >= 1008:
            self.soft_count = r.i32(); self.soft_off = r.i32()
        if not (self.flags & 0x80000000):
            r.fstr()
        self.gtd = (r.i32(), r.i32())
        self.export_count = r.i32(); self.export_off = r.i32()
        self.import_count = r.i32(); self.import_off = r.i32()
        # names
        nr = Reader(d, [], self.name_off)
        names = []
        for i in range(self.name_count):
            names.append(nr.fstr()); nr.u32()
        self.names = names
        self.soft_list = None
        if self.soft_count:
            sr = Reader(d, names, self.soft_off, zen=True)
            self.soft_list = [sr.softpath() for _ in range(self.soft_count)]
    def data_reader(self):
        # single-export assets: export data is all of uexp minus the trailing tag
        return Reader(self.uexp, self.names, 0, self.soft_list)

def dump_datatable_legacy(path, rowstruct):
    a = Legacy(path); r = a.data_reader()
    return read_datatable(a, r, rowstruct)

def read_datatable(a, r, rowstruct):
    r.u32()  # leading 4 bytes (serialization control / extension)
    top = r.header()
    vals = {}
    sc = U.schema('DataTable')
    for p, zero in top:
        nm, t = sc[p]
        vals[nm] = ('ZERO',) if zero else read_value(r, t)
    vals['_guidflag'] = r.u32()
    n = r.i32(); rows = {}
    for i in range(n):
        rn = r.fname()
        try:
            rows[rn] = read_props(r, rowstruct)
        except Exception as e:
            raise Exception(f'row {rn}: {e}') from None
    r.u32() if False else None
    return a, vals, rows, r.o, len(r.d)

class ZenAsset:
    def __init__(self, path):
        sys.path.insert(0, os.path.dirname(__file__))
        from zen import Zen
        self.z = Zen(path); self.names = self.z.names
    def data_reader(self):
        return Reader(self.z.d, self.names, self.z.header_size, None, zen=True)
