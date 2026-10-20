"""Lossless unversioned-property tree reader/writer (UE5.4), driven by usmap. For copying/editing data between packages."""
import struct, sys, os
sys.path.insert(0, os.path.dirname(__file__))
import ue
U = ue.U
NATIVE_SIZE = {'Vector':24,'Vector2D':16,'Vector4':32,'Rotator':24,'Quat':32,'Guid':16,'Color':4,'LinearColor':16,
               'IntPoint':8,'IntVector':12,'DateTime':8,'Timespan':8,'FrameNumber':4,'Box2D':33,'Box':49}
PRIM = {'Bool':1,'Byte':1,'Int8':1,'Int16':2,'UInt16':2,'Int':4,'UInt32':4,'Int64':8,'UInt64':8,'Float':4,'Double':8,
        'Object':4,'WeakObject':4,'LazyObject':4,'Interface':4}

class Ctx:
    """names: list of str (read side). soft_list: legacy soft object path table (list of (pkg,asset,sub)) or None for zen."""
    def __init__(self, data, names, soft_list=None):
        self.d=data; self.names=names; self.soft=soft_list

def _hdr_read(c, o):
    frags=[]
    while True:
        h=struct.unpack_from('<H',c.d,o)[0]; o+=2; frags.append((h&0x7f, bool(h&0x80), h>>9))
        if h&0x100: break
    nz=sum(f[2] for f in frags if f[1]); zm=[]
    if nz:
        if nz<=8: w=c.d[o]; o+=1; zm=[(w>>i)&1 for i in range(nz)]
        elif nz<=16: w=struct.unpack_from('<H',c.d,o)[0]; o+=2; zm=[(w>>i)&1 for i in range(nz)]
        else:
            for k in range((nz+31)//32):
                w=struct.unpack_from('<I',c.d,o)[0]; o+=4; zm+=[(w>>i)&1 for i in range(32)]
            zm=zm[:nz]
    out=[]; p=0; zi=0
    for sk,hz,vn in frags:
        p+=sk
        for k in range(vn):
            z=zm[zi] if hz else 0
            if hz: zi+=1
            out.append((p,bool(z))); p+=1
    return out,o

def _hdr_write(items):
    """items: sorted list of (index, zero). Rebuild fragments like UE (max 127 skip / 127 values)."""
    frags=[]; prev=0; cur=None
    for idx,z in items:
        gap=idx-prev
        if cur is None or gap>0 or cur[2]>=127:
            while gap>127:
                frags.append([127,False,0]); gap-=127
            cur=[gap,False,0,[]]; frags.append(cur)
        cur[2]+=1; cur[3].append(z); cur[1]=cur[1] or z
        prev=idx+1
    if not frags: frags=[[0,False,0,[]]]
    out=b''; bits=[]
    for i,f in enumerate(frags):
        h=f[0] | (0x80 if f[1] else 0) | (0x100 if i==len(frags)-1 else 0) | (f[2]<<9)
        out+=struct.pack('<H',h)
        if f[1]: bits+= [1 if z else 0 for z in f[3]]
    n=len(bits)
    if n:
        if n<=8: out+=bytes([sum(b<<i for i,b in enumerate(bits))])
        elif n<=16: out+=struct.pack('<H',sum(b<<i for i,b in enumerate(bits)))
        else:
            for k in range(0,n,32):
                chunk=bits[k:k+32]; out+=struct.pack('<I',sum(b<<i for i,b in enumerate(chunk)))
    return out

def read_struct(c, o, sname):
    if sname in NATIVE_SIZE: n=NATIVE_SIZE[sname]; return ('native',sname,c.d[o:o+n]), o+n
    if sname in ('SoftObjectPath','SoftClassPath'): return _read_soft(c,o)
    if sname=='GameplayTagContainer':
        n=struct.unpack_from('<i',c.d,o)[0]; o+=4; vals=[]
        for i in range(n): v,o=_read_name(c,o); vals.append(v)
        return ('tags',vals), o
    sc=U.schema(sname); items,o=_hdr_read(c,o); props=[]
    for idx,z in items:
        nm,t=sc[idx]
        if z: props.append((idx,nm,True,None)); continue
        v,o=read_value(c,o,t); props.append((idx,nm,False,v))
    return ('struct',sname,props), o

def _read_name(c,o):
    i,n=struct.unpack_from('<II',c.d,o); return ('name',c.names[i],n), o+8
def _read_fstr(c,o):
    L=struct.unpack_from('<i',c.d,o)[0]; o+=4
    if L==0: return ('str',''),o
    if L<0: s=c.d[o:o-2*L].decode('utf-16-le')[:-1]; return ('str',s),o-2*L
    return ('str',c.d[o:o+L-1].decode('latin1')),o+L
def _read_soft(c,o):
    if c.soft is not None:
        i=struct.unpack_from('<i',c.d,o)[0]; return ('soft',)+tuple(c.soft[i]), o+4
    a,o=_read_name(c,o); b,o=_read_name(c,o); s,o=_read_fstr(c,o)
    return ('soft',a,b,s[1]), o

def read_value(c,o,t,mode='normal'):
    k=t[0]
    if k in PRIM:
        n=PRIM[k]
        if k in ('Object','WeakObject','LazyObject','Interface'): return ('obj',struct.unpack_from('<i',c.d,o)[0]),o+4
        return ('raw',k,c.d[o:o+n]),o+n
    if k=='Name': return _read_name(c,o)
    if k=='Str': return _read_fstr(c,o)
    if k in ('SoftObject','AssetObject'): return _read_soft(c,o)
    if k=='Enum':
        if mode=='normal': v,o=read_value(c,o,t[1]); return ('enum',t[2],v),o
        v,o=_read_name(c,o); return ('enumname',t[2],v),o
    if k=='Struct': return read_struct(c,o,t[1])
    if k=='Array':
        n=struct.unpack_from('<i',c.d,o)[0]; o+=4; vals=[]
        for i in range(n): v,o=read_value(c,o,t[1],'array'); vals.append(v)
        return ('arr',vals),o
    if k=='Set':
        rm,n=struct.unpack_from('<ii',c.d,o); o+=8; vals=[]
        for i in range(n): v,o=read_value(c,o,t[1],'array'); vals.append(v)
        return ('set',rm,vals),o
    if k=='Map':
        rm,n=struct.unpack_from('<ii',c.d,o); o+=8; vals=[]
        for i in range(n):
            a,o=read_value(c,o,t[1],'array'); b,o=read_value(c,o,t[2],'array'); vals.append((a,b))
        return ('map',rm,vals),o
    if k=='Text':
        st=o; r=ue.Reader(c.d,c.names,o); r.ftext(); return ('textraw',c.d[st:r.o]),r.o
    raise Exception(f'unhandled {t} @ {o}')

class W:
    """names: NameMap with .index(str)->int ; objmap(int)->int ; zen_soft: write soft paths inline"""
    def __init__(self, names, objmap=lambda x:x):
        self.names=names; self.objmap=objmap
def write_struct(w, v):
    kind=v[0]
    if kind=='native': return v[2]
    if kind=='soft': return write_value(w,v)
    if kind=='tags': return struct.pack('<i',len(v[1]))+b''.join(write_value(w,x) for x in v[1])
    assert kind=='struct'
    props=sorted(v[2],key=lambda p:p[0])
    out=_hdr_write([(p[0],p[2]) for p in props])
    for idx,nm,z,val in props:
        if not z: out+=write_value(w,val)
    return out
def _wstr(s):
    if s=='': return struct.pack('<i',0)
    try: b=s.encode('latin1'); return struct.pack('<i',len(b)+1)+b+b'\0'
    except UnicodeEncodeError:
        b=s.encode('utf-16-le')+b'\0\0'; return struct.pack('<i',-(len(b)//2))+b
def write_value(w,v):
    k=v[0]
    if k=='raw': return v[2]
    if k=='obj': return struct.pack('<i',w.objmap(v[1]))
    if k=='name': return struct.pack('<II',w.names.index(v[1]),v[2])
    if k=='str': return _wstr(v[1])
    if k=='soft': return write_value(w,v[1])+write_value(w,v[2])+_wstr(v[3])
    if k=='enum': return write_value(w,v[2])
    if k=='enumname': return write_value(w,v[2])
    if k in ('struct','native','tags'): return write_struct(w,v)
    if k=='arr': return struct.pack('<i',len(v[1]))+b''.join(write_value(w,x) for x in v[1])
    if k=='set': return struct.pack('<ii',v[1],len(v[2]))+b''.join(write_value(w,x) for x in v[2])
    if k=='map': return struct.pack('<ii',v[1],len(v[2]))+b''.join(write_value(w,a)+write_value(w,b) for a,b in v[2])
    if k=='textraw': return v[1]
    raise Exception(k)

class NameMap:
    def __init__(self, names): self.names=list(names); self.idx={n:i for i,n in enumerate(self.names)}; self.added=[]
    def index(self, s):
        if s not in self.idx: self.idx[s]=len(self.names); self.names.append(s); self.added.append(s)
        return self.idx[s]

# helpers
def get(v,name):
    for p in v[2]:
        if p[1]==name: return p
    return None
def setp(v,name,val,zero=False):
    sc=U.schema(v[1]); idx=[i for i,(n,t) in sc.items() if n==name][0]
    v[2][:]=[p for p in v[2] if p[1]!=name]+[(idx,name,zero,val)]
