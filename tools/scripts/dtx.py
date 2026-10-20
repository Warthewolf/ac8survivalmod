import struct,sys,os; sys.path.insert(0,os.path.dirname(__file__))
import uprop
def parse(c,o,rowstruct):
    pre=c.d[o:o+4]; o+=4
    top,o=uprop.read_struct(c,o,'DataTable')
    gf=struct.unpack_from('<I',c.d,o)[0]; o+=4
    n=struct.unpack_from('<i',c.d,o)[0]; o+=4
    rows=[]
    for i in range(n):
        idx,num=struct.unpack_from('<II',c.d,o); o+=8
        v,o=uprop.read_struct(c,o,rowstruct); rows.append(((c.names[idx],num),v))
    return dict(pre=pre,top=top,gf=gf,rows=rows),o
def write(w,dt):
    out=dt['pre']+uprop.write_struct(w,dt['top'])+struct.pack('<Ii',dt['gf'],len(dt['rows']))
    for (n,num),v in dt['rows']:
        out+=struct.pack('<II',w.names.index(n),num)+uprop.write_struct(w,v)
    return out
