"""Extract Ace Combat 7 voice lines (radio events) into plain WAVs, for reading and listening only.

    python -I tools/ac7_voice.py EVENT [EVENT ...] [--out build/ac7/voice]
    python -I tools/ac7_voice.py --table ex03 [--voice v022] [--out ...]   every event of a decrypted radio table

The user's exception of 2026-11-17 (AGENTS.md, AC7 voice lines): the Alicorn crew's lines from AC7's DLC missions,
distorted, for THE TANACORN in the user's dev install only. Nothing here is committed or shipped but this script.

Reads only (never writes) the AC7 Wwise data, its folder from .env (AC7_VOICE_DIR: the folder of voice_update.bnk /
voice.bnk; AC7_VOICE_PCK: the voice_update_en.pck next to it, by default one level up), and vgmstream (VGMSTREAM).
A radio line's event is its row's voice ID and _Play (ex03_v022_0582 -> v022_0582_Play): its Wwise ID the FNV-1 (32-bit) hash of the lower-cased name;
event -> its Play action -> the sound it plays -> the sound's media ID; the media from the bank's DATA (DIDX) or the
.pck (AKPK). Writes <out>/<event>.wem and <event>.wav. Bank version 125's layouts.
"""
import argparse, os, re, struct, subprocess, sys

sys.stdout.reconfigure(encoding='utf-8')
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import env

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, 'build', 'ac7', 'voice')
RADIO = os.path.join(ROOT, 'build', 'ac7', 'radio')       # (tools/ac7_decrypt.py's radio tables)


def fnv1(name):
    h = 2166136261
    for ch in name.lower().encode('ascii'):
        h = (h * 16777619) & 0xffffffff
        h ^= ch
    return h


def event_name(row):
    """A radio row's Wwise event: ex03_v022_0582 -> v022_0582_Play, ex03_v022_0582_alt1 -> v022_0582_alt1_Play; a name that already ends in _Play or _Play_altN kept."""
    m = re.match(r'^(?:[a-z]+\d+_)?(v\d+_\d+)(?:_Play)?(_alt\d+)?$', row)
    if not m:
        return row
    return m.group(1) + (m.group(2) or '') + '_Play'      # (v022_0582_alt1_Play: hashed against the banks' events)


def sections(b):
    out, i = {}, 0
    while i + 8 <= len(b):
        tag, ln = b[i:i + 4], struct.unpack_from('<I', b, i + 4)[0]
        out[tag] = (i + 8, ln)
        i += 8 + ln
    return out


class Bank:
    def __init__(self, path):
        self.path, self.b = path, open(path, 'rb').read()
        s = sections(self.b)
        self.ver = struct.unpack_from('<I', self.b, s[b'BKHD'][0])[0]
        self.didx, self.data = {}, None
        if b'DIDX' in s:
            o, ln = s[b'DIDX']
            for k in range(ln // 12):
                mid, off, size = struct.unpack_from('<III', self.b, o + 12 * k)
                self.didx[mid] = (off, size)
        if b'DATA' in s:
            self.data = s[b'DATA'][0]
        self.objs = {}
        o, ln = s[b'HIRC']
        n = struct.unpack_from('<I', self.b, o)[0]
        p = o + 4
        for _ in range(n):
            t, size = self.b[p], struct.unpack_from('<I', self.b, p + 1)[0]
            body = self.b[p + 5:p + 5 + size]
            oid = struct.unpack_from('<I', body, 0)[0]
            self.objs[oid] = (t, body)
            p += 5 + size

    def media_of_event(self, eid):
        e = self.objs.get(eid)
        if not e or e[0] != 4:
            return None, 'no event'
        body = e[1]
        # (v125: the action count a u8, then its IDs)
        cnt = body[4]
        acts = [struct.unpack_from('<I', body, 5 + 4 * k)[0] for k in range(cnt)]
        for a in acts:
            ao = self.objs.get(a)
            if not ao or ao[0] != 3:
                continue
            ab = ao[1]
            atype = struct.unpack_from('<H', ab, 4)[0]
            target = struct.unpack_from('<I', ab, 6)[0]
            if atype not in (0x0403, 0x0404):                 # (Play, PlayAndContinue)
                continue
            mid = self.media_of(target, 0)
            if mid:
                return mid, 'ok'
        return None, 'no sound under its play action'

    def media_of(self, oid, depth):
        o = self.objs.get(oid)
        if not o or depth > 4:
            return None
        t, body = o
        if t == 2:                                            # (a Sound: plugin u32, stream type u8, source ID u32)
            stype = body[8]
            sid = struct.unpack_from('<I', body, 9)[0]
            return (sid, stype)
        if t in (5, 6, 7):                                    # (a random / switch / layer container: its first child that has one)
            for m in re.finditer(rb'.', b''):
                pass
            # children list: scan the body's tail for IDs of sounds we know
            for k in range(len(body) - 4, 3, -1):
                cid = struct.unpack_from('<I', body, k)[0]
                if cid in self.objs and self.objs[cid][0] == 2:
                    r = self.media_of(cid, depth + 1)
                    if r:
                        return r
        return None

    def wem(self, mid):
        if mid in self.didx and self.data is not None:
            off, size = self.didx[mid]
            return self.b[self.data + off:self.data + off + size]
        return None


class Pck:
    def __init__(self, path):
        self.path = path
        f = open(path, 'rb')
        head = f.read(8)
        assert head[:4] == b'AKPK', path
        hsize = struct.unpack_from('<I', head, 4)[0]
        h = f.read(hsize)
        self.f = f
        ver, lang_sz, banks_sz, sounds_sz = struct.unpack_from('<IIII', h, 0)
        ext_sz = struct.unpack_from('<I', h, 16)[0] if hsize >= 20 + lang_sz + banks_sz + sounds_sz + 4 else 0
        base = 16 + (4 if ext_sz or hsize > 16 + lang_sz + banks_sz + sounds_sz else 0)
        self.files = {}
        tables = [(base + lang_sz, banks_sz, 4), (base + lang_sz + banks_sz, sounds_sz, 4)]
        if ext_sz:
            tables.append((base + lang_sz + banks_sz + sounds_sz, ext_sz, 8))
        for off, size, idw in tables:
            n = struct.unpack_from('<I', h, off)[0]
            rec = 4 * 4 + idw
            for k in range(n):
                q = off + 4 + rec * k
                if idw == 4:
                    fid, block, sz, start, lang = struct.unpack_from('<IIIII', h, q)
                else:
                    fid, block, sz, start, lang = struct.unpack_from('<QIIII', h, q)
                self.files[fid] = (start * max(1, block), sz)

    def wem(self, mid):
        if mid not in self.files:
            return None
        start, size = self.files[mid]
        self.f.seek(start)
        return self.f.read(size)


def table_events(table, voice=None):
    p = os.path.join(RADIO, 'RadioTable_%s.uasset' % table)
    b = open(p, 'rb').read()
    names = sorted(set(m.decode() for m in re.findall(rb'%s_v\d+_\d+(?:_alt\d+)?' % table.encode(), b)))
    if voice:
        names = [x for x in names if ('_%s_' % voice) in x]
    return names


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('events', nargs='*')
    ap.add_argument('--table')
    ap.add_argument('--voice')
    ap.add_argument('--out', default=OUT)
    a = ap.parse_args()
    vdir = env.need('AC7_VOICE_DIR', "the folder of AC7's voice_update.bnk (English(US))")
    pck_path = env.get('AC7_VOICE_PCK') or os.path.join(os.path.dirname(vdir.rstrip('/\\')), 'voice_update_en.pck')
    vgm = env.need('VGMSTREAM', 'vgmstream-cli.exe')
    banks = [Bank(os.path.join(vdir, n)) for n in ('voice_update.bnk', 'voice.bnk') if os.path.exists(os.path.join(vdir, n))]
    pck = Pck(pck_path)
    evs = list(a.events)
    if a.table:
        evs += table_events(a.table, a.voice)
    os.makedirs(a.out, exist_ok=True)
    got = 0
    for ev in evs:
        eid = fnv1(event_name(ev))
        mid, why = None, 'not in any bank'
        for bk in banks:
            if eid in bk.objs:
                mid, why = bk.media_of_event(eid)
                if mid:
                    src = bk
                    break
        if not mid:
            print('%s: %s' % (ev, why))
            continue
        sid, stype = mid
        data = src.wem(sid) if stype == 0 else None
        if data is None:
            data = pck.wem(sid)
        if not data:
            print('%s: media %d (stream type %d) not found' % (ev, sid, stype))
            continue
        w = os.path.join(a.out, ev + '.wem')
        open(w, 'wb').write(data)
        r = subprocess.run([vgm, '-o', os.path.join(a.out, ev + '.wav'), w], capture_output=True, text=True)
        ok = r.returncode == 0
        got += ok
        print('%s: media %d, %d bytes -> %s' % (ev, sid, len(data), 'wav' if ok else ('vgmstream failed: ' + r.stderr[-200:])))
    print('%d of %d decoded into %s' % (got, len(evs), a.out))


if __name__ == '__main__':
    main()
