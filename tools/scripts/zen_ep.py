import re,struct,sys,pickle,os; sys.path.insert(0,os.path.dirname(__file__))
from zen import Zen
SO=pickle.load(open(os.path.join(os.path.dirname(__file__),'..','scriptobjs.pkl'),'rb'))
def load(p):
    z=Zen(p); u=z.d
    imps=[SO.get(x,'pkg:%x'%x).split('/')[-1] for x in z.imports]
    hs=[m.start() for m in re.finditer(rb'\x01\x80\x13',u) if m.start()>z.header_size]
    nodes=[]
    for k,o in enumerate(hs):
        c=struct.unpack_from('<i',u,o+13)[0]; end=hs[k+1] if k+1<len(hs) else len(u)
        cname=imps[-c-1] if c<0 and -c-1<len(imps) else ('trig:%08x'%(c&0xffffffff))
        strs=[s.decode() for s in re.findall(rb'[\x20-\x7e]{2,}',u[o+17:end])]
        g=struct.unpack_from('<I',u,o+5)[0]
        nodes.append(dict(off=o,fl=u[o+3],grp=g,gname=z.names[g] if g<len(z.names) else '?',idx=struct.unpack_from('<I',u,o+9)[0],cls=cname,strs=strs,raw=u[o:end]))
    return z,nodes
if __name__=='__main__':
    z,ns=load(sys.argv[1])
    for n in ns: print(hex(n['off']),len(n['raw']),'fl=%02x'%n['fl'],n['gname'],n['idx'],n['cls'],n['strs'][:10])
