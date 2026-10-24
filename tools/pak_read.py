"""pak_read.py : read AC8's classic .pak (pakchunk0-Windows.pak: the config .ini files and whatever IoStore can't hold),
for research only. Reads, never writes the game's files.

    python -I tools/pak_read.py list  [regex]               list the files (path, size, compressed size)
    python -I tools/pak_read.py get   <regex> [out dir]     extract matching files (default build/pak)

Pak version 11 (UE 5.4): an AES-256 encrypted index (the key from ACE8AircraftBuilder's settings.json, as
tools/get_stock.sh uses it: never in this repo), the full directory index, the encoded entries; file data compressed
with Oodle (tools/bin/oo2core_9_win64.dll) in blocks, encrypted where the entry says.

CAUTION: AC8's shipped config holds third-party credentials (Live/Config/DefaultGame.ini: Bandai Namco's internal Slack
webhook and bot token). Extract only into build/ (git-ignored) or scratch; never commit, quote or share what comes out.
"""
import ctypes
import json
import os
import re
import struct
import sys

from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes

HERE = os.path.dirname(os.path.abspath(__file__))
PAK = 'E:/SteamLibrary/steamapps/common/ACE COMBAT 8/Game/Content/Paks/pakchunk0-Windows.pak'
KEY = bytes.fromhex(json.load(open('E:/ACE8AircraftBuilder/settings.json'))['aesKey'][2:])
MAGIC = 0x5A6F12E1


def aes(data):
    d = Cipher(algorithms.AES(KEY), modes.ECB()).decryptor()
    return d.update(data) + d.finalize()


class R:
    def __init__(self, b, o=0):
        self.b, self.o = b, o

    def u(self, f):
        v = struct.unpack_from('<' + f, self.b, self.o)
        self.o += struct.calcsize('<' + f)
        return v[0] if len(v) == 1 else v

    def fstr(self):
        n = self.u('i')
        if n == 0:
            return ''
        if n > 0:
            s = self.b[self.o:self.o + n - 1].decode('latin-1')
            self.o += n
        else:
            s = self.b[self.o:self.o - 2 * n - 2].decode('utf-16-le')
            self.o += -2 * n
        return s

    def raw(self, n):
        v = self.b[self.o:self.o + n]
        self.o += n
        return v


class Pak:
    def __init__(self, path=PAK):
        self.f = open(path, 'rb')
        self.f.seek(0, 2)
        size = self.f.tell()
        self.f.seek(size - 512)
        tail = self.f.read(512)
        i = tail.rfind(struct.pack('<I', MAGIC))
        self.encrypted_index = tail[i - 1]
        _, self.version, ioff, isz = struct.unpack_from('<IiQQ', tail, i)
        self.methods = [tail[i + 44 + k * 32:i + 44 + (k + 1) * 32].split(b'\0')[0].decode() for k in range(5)]
        assert self.version == 11, self.version
        idx = self.read_at(ioff, isz, self.encrypted_index)
        r = R(idx)
        self.mount = r.fstr()
        self.num = r.u('i')
        r.u('Q')                                            # path hash seed
        if r.u('i'):
            r.u('Q'); r.u('Q'); r.raw(20)                   # path hash index (not needed)
        assert r.u('i'), 'no full directory index'
        doff, dsz = r.u('Q'), r.u('Q')
        r.raw(20)
        n = r.u('i')
        self.encoded = r.raw(n)
        self.files = {}
        d = R(self.read_at(doff, dsz, self.encrypted_index))
        for _ in range(d.u('i')):
            dirname = d.fstr()
            for _ in range(d.u('i')):
                name = d.fstr()
                self.files[(self.mount + dirname + name).replace('../../../', '')] = d.u('i')

    def read_at(self, off, size, encrypted):
        self.f.seek(off)
        data = self.f.read((size + 15) & ~15 if encrypted else size)
        return aes(data)[:size] if encrypted else data

    def entry(self, enc_off):
        r = R(self.encoded, enc_off)
        v = r.u('I')
        bs = (v & 0x3f) << 11
        if (v & 0x3f) == 0x3f:
            bs = r.u('I')
        nblocks = (v >> 6) & 0xffff
        enc = (v >> 22) & 1
        method = (v >> 23) & 0x3f
        off = r.u('I') if (v >> 31) & 1 else r.u('Q')
        usize = r.u('I') if (v >> 30) & 1 else r.u('Q')
        csize = (r.u('I') if (v >> 29) & 1 else r.u('Q')) if method else usize
        sizes = []
        if nblocks == 1 and not enc:
            sizes = [csize]
        elif nblocks:
            sizes = [r.u('I') for _ in range(nblocks)]
        return dict(offset=off, usize=usize, csize=csize, method=method, encrypted=enc, block=bs, blocks=sizes)

    def header_size(self, e):
        n = 8 + 8 + 8 + 4 + 20 + 1 + 4                      # offset, size, usize, method, hash, flags, block size
        if e['method']:
            n += 4 + 16 * len(e['blocks'])
        return n

    def read(self, path):
        e = self.entry(self.files[path])
        pos = e['offset'] + self.header_size(e)
        if not e['method']:
            return self.read_at(pos, e['usize'], e['encrypted'])
        out = bytearray()
        for k, cs in enumerate(e['blocks']):
            span = (cs + 15) & ~15 if e['encrypted'] else cs
            self.f.seek(pos)
            blk = self.f.read(span)
            if e['encrypted']:
                blk = aes(blk)
            blk = blk[:cs]
            want = min(e['block'] or e['usize'], e['usize'] - len(out))   # (block 0: one block, the whole file)
            out += oodle(blk, want) if self.methods[e['method'] - 1].lower() == 'oodle' else blk
            pos += span
        return bytes(out)


_oo = None


def oodle(src, n):
    global _oo
    if _oo is None:
        _oo = ctypes.WinDLL(os.path.join(HERE, 'bin', 'oo2core_9_win64.dll'))
        _oo.OodleLZ_Decompress.restype = ctypes.c_int64
    dst = ctypes.create_string_buffer(n)
    got = _oo.OodleLZ_Decompress(src, ctypes.c_int64(len(src)), dst, ctypes.c_int64(n), 1, 0, 0, None, 0, None, None, None, 0, 3)
    if got != n:
        raise ValueError(f'Oodle gave {got} of {n} bytes')
    return dst.raw


def main(a):
    if not a or a[0] not in ('list', 'get'):
        sys.exit(__doc__)
    pak = Pak()
    rx = re.compile(a[1] if len(a) > 1 else '.', re.I)
    hits = sorted(p for p in pak.files if rx.search(p))
    if a[0] == 'list':
        print(f'{pak.num} entries, mount {pak.mount!r}, compression {pak.methods}; {len(hits)} match')
        for p in hits:
            e = pak.entry(pak.files[p])
            print(f'{e["usize"]:10d} {e["csize"]:10d} {"E" if e["encrypted"] else " "} {p}')
        return
    out = a[2] if len(a) > 2 else os.path.join(HERE, '..', 'build', 'pak')
    for p in hits:
        dst = os.path.join(out, p)
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        data = pak.read(p)
        e = pak.entry(pak.files[p])
        if len(data) != e['usize']:
            raise ValueError(f'{p}: {len(data)} of {e["usize"]} bytes')
        open(dst, 'wb').write(data)
        print('got', p)


if __name__ == '__main__':
    main(sys.argv[1:])
