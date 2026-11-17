"""Decode Ace Combat 7 / 8 localization .dat files (Cmn.dat + a language file each) into a TSV: id, key, text per language.

    python -I tools/acloc.py <Cmn.dat> <A.dat> [<B.dat> ...] > out.tsv

A port of Ace8LocEd's Loc.cs (the XOR + zlib layer, the Cmn key tree, the language string tables). AC7's A.dat is
English (its voice lines keyed by voice ID: v6157_6001_alt1 "Salvation is nigh--"). Reads only.
"""
# AC7/AC8 localization .dat decoder (port of Ace8LocEd Loc.cs)
import sys, zlib, struct
def xor(data, seed):
    a=0; b=seed; out=bytearray(data)
    for i in range(len(out)):
        bit=((~(((a<<3)^a)&0xff))>>7)&1
        a=((a<<1)|bit)&0xff
        b=(b*5+1)&0xff
        out[i]^=(a+b)&0xff
    return bytes(out)
def decode(f):
    for s in range(256):
        h=xor(f[:2],s)
        if (h[0]&0xf)!=8 or ((h[0]<<8)|h[1])%31 or (h[1]&0x20): continue
        try:
            p=zlib.decompress(xor(f,s))
        except Exception: continue
        return p,(s-len(f))&0xff
    raise ValueError('not loc')
def cmn(buf):
    res={}; pos=[0]
    def ri():
        v=struct.unpack_from('<i',buf,pos[0])[0]; pos[0]+=4; return v
    def walk(key):
        n=ri()
        for _ in range(n):
            ln=ri(); nm=buf[pos[0]:pos[0]+ln]; pos[0]+=ln
            num=ri()
            k=key+nm
            if num>=0: res[k.decode('utf8','replace')]=num
            walk(k)
    walk(b'')
    return res
def strings(buf):
    if buf.endswith(b'\0'): buf=buf[:-1]
    return [x.decode('utf8','replace') for x in buf.split(b'\0')]
if __name__=="__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    import os
    cm=sys.argv[1]; langs=sys.argv[2:]
    p,d=decode(open(cm,'rb').read()); keys=cmn(p)
    L=[]
    for l in langs:
        q,dd=decode(open(l,'rb').read()); L.append(strings(q)); print('#',l,'delta',dd,len(L[-1]),file=sys.stderr)
    print('#cmn delta',d,len(keys),file=sys.stderr)
    for k,n in sorted(keys.items(),key=lambda x:x[1]):
        row=[str(n),k]+[ (s[n] if n<len(s) else '').replace('\r','\r').replace('\n','\n') for s in L]
        print('\t'.join(row))
