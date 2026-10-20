import re,struct,sys; sys.path.insert(0,'.')
import ue
def load(p):
    a=ue.Legacy(p+'.uasset'); d=a.d
    size=(a.export_off-a.import_off)//a.import_count
    imps=[a.names[struct.unpack_from('<i',d,a.import_off+i*size+20)[0]] for i in range(a.import_count)]
    u=open(p+'.uexp','rb').read()
    hs=[m.start() for m in re.finditer(rb'\x01\x80\x13',u)]
    nodes=[]
    for k,o in enumerate(hs):
        c=struct.unpack_from('<i',u,o+13)[0]; end=hs[k+1] if k+1<len(hs) else len(u)
        cname=imps[-c-1] if c<0 and -c-1<len(imps) else ('trig:%08x'%(c&0xffffffff))
        strs=[s.decode() for s in re.findall(rb'[\x20-\x7e]{2,}',u[o+17:end])]
        nodes.append(dict(off=o,fl=u[o+3],grp=struct.unpack_from('<I',u,o+5)[0],idx=struct.unpack_from('<I',u,o+9)[0],cls=cname,strs=strs,raw=u[o:end]))
    return nodes
if __name__=='__main__':
    ns=load(sys.argv[1]); pat=sys.argv[2] if len(sys.argv)>2 else None
    for n in ns:
        if pat is None or any(re.search(pat,s) for s in n['strs']):
            print(hex(n['off']),'fl=%02x'%n['fl'],'grp=%d'%n['grp'],'idx=%d'%n['idx'],n['cls'],n['strs'][:12])
