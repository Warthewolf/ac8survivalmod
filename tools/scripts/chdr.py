"""IoStore container header (UE5.4) store-entry editor."""
import struct

class CHdr:
    def __init__(self, ch):
        self.head = ch[:16]
        n, = struct.unpack_from('<i', ch, 16)
        self.ids = [struct.unpack_from('<Q', ch, 20+8*i)[0] for i in range(n)]
        eo = 20 + 8*n
        blen, = struct.unpack_from('<i', ch, eo)
        ent = ch[eo+4:eo+4+blen]
        self.tail = ch[eo+4+blen:]
        self.imports = []; self.shaders = []; self.layout = []
        for i in range(n):
            arrs = []
            for f, sz in ((0, 8), (8, 20)):
                num, off = struct.unpack_from('<II', ent, 16*i+f)
                base = 16*i+f+off
                arrs.append([ent[base+sz*k:base+sz*(k+1)] for k in range(num)])
                self.layout.append((i, f, base if num else None))
            self.imports.append([struct.unpack('<Q', x)[0] for x in arrs[0]])
            self.shaders.append(arrs[1])
        self._orig = ch

    def write(self):
        n = len(self.ids)
        ent = bytearray(16*n)
        # data laid out entry by entry: imports then shader hashes (matches cooker order)
        for i in range(n):
            for f, items in ((0, [struct.pack('<Q', x) for x in self.imports[i]]), (8, self.shaders[i])):
                if items:
                    base = len(ent); ent += b''.join(items)
                    struct.pack_into('<II', ent, 16*i+f, len(items), base-(16*i+f))
                else:
                    struct.pack_into('<II', ent, 16*i+f, 0, 0)
        return (self.head + struct.pack('<i', n) + b''.join(struct.pack('<Q', x) for x in self.ids)
                + struct.pack('<i', len(ent)) + bytes(ent) + self.tail)
