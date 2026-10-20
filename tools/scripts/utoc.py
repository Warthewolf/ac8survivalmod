import struct
class Utoc:
    def __init__(self, path):
        d = open(path,'rb').read(); self.raw = d
        assert d[:16] == b'-==--==--==--==-'
        (self.version, _, _, self.hsize, self.n, self.nblk, self.blksz, self.ncm, self.cmlen, self.cbs,
         self.dirsize, self.partcount) = struct.unpack_from('<BBHIIIIIIIII', d, 16)
        o = 0x38
        self.cid, = struct.unpack_from('<Q', d, o); o+=8
        self.guid = d[o:o+16]; o+=16
        self.flags = d[o]; o+=4
        self.nseeds, = struct.unpack_from('<I', d, o); o+=4
        self.partsize, = struct.unpack_from('<Q', d, o); o+=8
        self.nnoperf, = struct.unpack_from('<I', d, o); o+=4
        o = self.hsize
        self.ids = [d[o+12*i:o+12*i+12] for i in range(self.n)]; o += 12*self.n
        self.offlen_off = o
        self.offlen = []
        for i in range(self.n):
            b = d[o+10*i:o+10*i+10]
            self.offlen.append((int.from_bytes(b[:5],'big'), int.from_bytes(b[5:],'big')))
        o += 10*self.n
        self.seeds_off = o; o += 4*self.nseeds; o += 4*self.nnoperf
        self.blk_off = o
        self.blocks = []
        for i in range(self.nblk):
            b = d[o+12*i:o+12*i+12]
            off = int.from_bytes(b[0:5],'little'); csz = int.from_bytes(b[5:8],'little'); usz = int.from_bytes(b[8:11],'little'); m = b[11]
            self.blocks.append([off,csz,usz,m])
        o += 12*self.nblk
        self.cm_off = o
        self.cms = [d[o+self.cmlen*i:o+self.cmlen*(i+1)].rstrip(b'\0').decode() for i in range(self.ncm)]; o += self.cmlen*self.ncm
        self.sig_off = o
        if self.flags & 0x4:  # signed
            raise Exception('signed toc')
        self.dir_off = o; o += self.dirsize
        self.meta_off = o
        self.metasize = (len(d)-o)//self.n if self.n else 0
        self.metas = [d[o+self.metasize*i:o+self.metasize*(i+1)] for i in range(self.n)]
        self.tail = o + self.metasize*self.n
