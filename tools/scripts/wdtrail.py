import struct
def parse(t, names):
    o=0
    z0,n=struct.unpack_from('<II',t,o); o+=8
    idxs=list(struct.unpack_from('<%dI'%n,t,o)); o+=4*n
    def node(o):
        i,num=struct.unpack_from('<II',t,o); o+=8
        f=t[o]; o+=1
        a,b=struct.unpack_from('<II',t,o); o+=8
        kids=[]
        if b:
            c=struct.unpack_from('<I',t,o)[0]; o+=4
            assert b==c,(a,b,c,o)
            for k in range(c):
                ch,o=node(o); kids.append(ch)
        return dict(name=(i,num),flag=f,a=a,kids=kids),o
    x,m=struct.unpack_from('<II',t,o); o+=8
    nodes=[]
    for k in range(m):
        nd,o=node(o); nodes.append(nd)
    return dict(z0=z0,idxs=idxs,x=x,nodes=nodes,rest=t[o:]),o
def write(tr):
    out=struct.pack('<II',tr['z0'],len(tr['idxs']))+struct.pack('<%dI'%len(tr['idxs']),*tr['idxs'])
    def node(nd):
        b=struct.pack('<II',*nd['name'])+bytes([nd['flag']])
        k=len(nd['kids'])
        b+=struct.pack('<II',nd['a'],k)
        if k: b+=struct.pack('<I',k)+b''.join(node(c) for c in nd['kids'])
        return b
    out+=struct.pack('<II',tr['x'],len(tr['nodes']))+b''.join(node(n) for n in tr['nodes'])
    return out+tr['rest']
