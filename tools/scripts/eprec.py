"""Event package (EP) record lists: split, parse exec/trigger records, rebuild."""
import struct, re

def _fstr(b, o):
    n = struct.unpack_from('<i', b, o)[0]; o += 4
    assert 0 <= n < 4096, n
    s = b[o:o+n]; o += n
    assert n == 0 or s[-1] == 0
    return s[:-1].decode('latin1') if n else None, o

def _wfstr(s):
    if s is None: return struct.pack('<i', 0)
    e = s.encode('latin1') + b'\0'
    return struct.pack('<i', len(e)) + e

def parse_params(b, o, n):
    ps = []
    for _ in range(n):
        flag, seven, typ = b[o], b[o+1], b[o+2]
        assert seven == 7 and flag in (0, 0x80), (hex(o), flag, seven)
        h = struct.unpack_from('<I', b, o+3)[0]
        s, o = _fstr(b, o+7)
        ps.append([flag, typ, h, s])
    return ps, o

def write_params(ps):
    return b''.join(bytes([f, 7, t]) + struct.pack('<I', h) + _wfstr(s) for f, t, h, s in ps)

class Exec:
    """mask u16; p0 FName grp; p1 class i32; p2 u32; [p3 f32 delay]; p4 u32; p5 params; [p7 u32 order]; p8 u8"""
    @staticmethod
    def parse(b):
        assert b[:2] == b'\x80\x13'
        m = struct.unpack_from('<H', b, 2)[0]
        o = 4
        e = Exec()
        e.grp = struct.unpack_from('<II', b, o); o += 8
        e.cls = struct.unpack_from('<i', b, o)[0]; o += 4
        e.p2 = struct.unpack_from('<I', b, o)[0]; o += 4
        e.delay = None
        if not m & 0x08: e.delay = struct.unpack_from('<f', b, o)[0]; o += 4
        e.p4 = struct.unpack_from('<I', b, o)[0]; o += 4
        n = struct.unpack_from('<I', b, o)[0]; o += 4
        e.params, o = parse_params(b, o, n)
        assert m & 0x40
        e.order = 0
        if not m & 0x80: e.order = struct.unpack_from('<I', b, o)[0]; o += 4
        e.p8 = b[o]; o += 1
        assert o == len(b), (o, len(b))
        e.mask_rest = m & ~0xc8
        return e
    def write(self):
        m = self.mask_rest | 0x40
        if not self.delay: m |= 0x08
        if not self.order: m |= 0x80
        out = b'\x80\x13' + struct.pack('<H', m) + struct.pack('<II', *self.grp) + struct.pack('<iI', self.cls, self.p2)
        if self.delay: out += struct.pack('<f', self.delay)
        out += struct.pack('<II', self.p4, len(self.params)) + write_params(self.params)
        if self.order: out += struct.pack('<I', self.order)
        return out + bytes([self.p8])

class Trig:
    """mask; p0 FName grp; p1 id u32; p2 u32; [p3 u32]; 02 kind; u32 n; params; p8"""
    @staticmethod
    def parse(b):
        assert b[:2] == b'\x80\x13'
        m = struct.unpack_from('<H', b, 2)[0]; o = 4
        t = Trig(); t.mask = m
        t.grp = struct.unpack_from('<II', b, o); o += 8
        t.id, t.p2 = struct.unpack_from('<II', b, o); o += 8
        t.p3 = None
        if not m & 0x08: t.p3 = struct.unpack_from('<I', b, o)[0]; o += 4
        assert b[o] == 2, hex(b[o]); t.kind = b[o+1]; o += 2
        n = struct.unpack_from('<I', b, o)[0]; o += 4
        t.params, o = parse_params(b, o, n)
        t.rest = b[o:]
        assert t.rest == b'\x01', t.rest
        return t
    def write(self):
        out = b'\x80\x13' + struct.pack('<H', self.mask) + struct.pack('<II', *self.grp) + struct.pack('<II', self.id, self.p2)
        if not self.mask & 0x08: out += struct.pack('<I', self.p3)
        return out + bytes([2, self.kind]) + struct.pack('<I', len(self.params)) + write_params(self.params) + self.rest

def split_lists(p, nnames):
    """payload -> (prefix, trig_bytes_list, mid(count bytes), exec_list, trailer). Each record includes trailing p8."""
    first = p.find(b'\x80\x13')
    ntrig = struct.unpack_from('<I', p, first-4)[0]
    starts = [first] + [m.start()+1 for m in re.finditer(b'\x01\x80\x13', p) if m.start()+1 > first]
    # locate exec start: '01 <u32 nexec> 80 13' after trigger ntrig-1
    recs = []
    # triggers: ntrig consecutive starts
    trig = []
    pos = first
    for i in range(ntrig):
        nxt = [s for s in starts if s > pos]
        # last trigger ends before 'u32 nexec'
        if i < ntrig-1:
            end = nxt[0]
        else:
            # find "01 xx xx xx xx 80 13"
            m = re.compile(b'\x01(.{4})\x80\x13', re.S).search(p, pos)
            end = m.start()+1
        trig.append(p[pos:end]); pos = end
    nexec = struct.unpack_from('<I', p, pos)[0]; mid = p[pos:pos+4]; pos += 4
    ex = []
    for i in range(nexec):
        nxt = [s for s in starts if s > pos]
        end = nxt[0] if i < nexec-1 else None
        if end is None:
            # last exec: parse to find its end
            e = None
            for cut in range(pos+20, len(p)+1):
                try:
                    Exec.parse(p[pos:cut]); end = cut; break
                except Exception:
                    continue
        ex.append(p[pos:end]); pos = end
    return p[:first-4], ntrig, trig, nexec, ex, p[pos:]

def join_lists(prefix, trig, ex, trailer):
    return prefix + struct.pack('<I', len(trig)) + b''.join(trig) + struct.pack('<I', len(ex)) + b''.join(ex) + trailer
