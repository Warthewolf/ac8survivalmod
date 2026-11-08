"""music_lengths.py : how long one pass of each looping track Survival adds to the music player is (2026-11-08).

    python -I tools/music_lengths.py show     print each track's media, length, loop and pass
    python -I tools/music_lengths.py write    write the lengths into Scripts/sv_music.lua (its SONG LENGTHS block)
    python -I tools/music_lengths.py check    fail if the block differs from the game's files

Saint Alessia's run of 0.74.32: "hush still ended abruptly". Online Mode's versions of the songs (AKE_Bgm_Online_*,
AKB_BGM_Online) are one looping Sound each (DurationType 2: the music player gives them 60 s, runtime MusicLoopCap),
and the loop is in the .wem itself (its smpl chunk): Hush plays 0 - 312.6 s, then from 38.3 s again. 0.74.32 moved on
after the lobby jukebox's recording of the same song (332 s), 19 s into Hush's second pass. One pass is the media's
loop end (or its whole length without a loop), and that's what the music player is given now (SV_MusicLen).

Reads the game's classic paks (tools/pak_read.py: the .env key, research only, nothing written into the game): the
bank's HIRC (event -> play action -> Sound -> its media id) from pakchunk0 and only the first block of each .wem.
Rerun `write` after a game update that changes the music; build_music_rows fails on a looping track with no length.
"""
import os
import re
import struct
import sys
import warnings

warnings.filterwarnings('ignore')                       # (the cryptography package's notice on this Python)
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
LUA = os.path.join(HERE, '..', 'mod', 'UE4SS', 'AC8SurvivalMode', 'Scripts', 'sv_music.lua')
BEGIN = '-- BEGIN SONG LENGTHS'
END = '-- END SONG LENGTHS'
VORBIS, PCM, OPUS = 0xFFFF, 0xFFFE, (0x3040, 0x3041)


def fnv(s):                                             # Wwise's id of a name: FNV-1 32 of its lower case
    h = 2166136261
    for c in s.lower().encode():
        h = (h * 16777619) & 0xffffffff
        h ^= c
    return h


def hirc(d):
    o, objs = 0, {}
    while o < len(d):
        tag, n = d[o:o + 4], struct.unpack_from('<I', d, o + 4)[0]
        if tag == b'HIRC':
            p = o + 12
            for _ in range(struct.unpack_from('<I', d, o + 8)[0]):
                t, sz, oid = struct.unpack_from('<BII', d, p)
                objs[oid] = (t, d[p + 9:p + 5 + sz])
                p += 5 + sz
        o += 8 + n
    return objs


def media_of(objs, event):
    """the media id the event's play action's Sound streams, or why not"""
    eid = fnv(event)
    if eid not in objs:
        return None, 'no event in the bank'
    b = objs[eid][1]
    acts = [a for a in (struct.unpack_from('<I', b, i)[0] for i in range(len(b) - 3)) if a in objs and objs[a][0] == 3]
    for a in acts:
        ab = objs[a][1]
        kind, tgt = struct.unpack_from('<HI', ab, 0)
        if kind != 0x0403 or tgt not in objs:
            continue
        t, sb = objs[tgt]
        if t != 0x02:
            return None, f'plays a type {t:#x} object, not a Sound'
        return struct.unpack_from('<I', sb, 5)[0], None   # (AkBankSourceData: plugin u32, stream type u8, source id)
    return None, 'no play action'


def wem_info(h):
    """(sample rate, samples, loop end or None) from a .wem's first bytes"""
    assert h[:4] == b'RIFF' and h[8:12] == b'WAVE', h[:12]
    o, rate, total, loop, fmt, data = 12, None, None, None, None, None
    while o + 8 <= len(h):
        tag, n = h[o:o + 4], struct.unpack_from('<I', h, o + 4)[0]
        b = h[o + 8:o + 8 + n]
        if tag == b'fmt ':
            fmt, ch, rate = struct.unpack_from('<HHI', b, 0)
            align = struct.unpack_from('<H', b, 12)[0]
            if fmt == VORBIS or fmt in OPUS:
                total = struct.unpack_from('<I', b, 0x18)[0]
        elif tag == b'smpl' and len(b) >= 36 and struct.unpack_from('<I', b, 28)[0] >= 1:
            loop = struct.unpack_from('<I', b, 36 + 12)[0] + 1   # (dwEnd: the loop's last sample)
        elif tag == b'data':
            data = n
            break
        o += 8 + n + (n & 1)
    if total is None and fmt in (PCM, 1) and data is not None:
        total = data // align
    assert rate and total, f'codec {fmt:#x}: its length unread'
    return rate, total, loop


def paks():
    import pak_read
    root = pak_read.env.paks()
    out = []
    for f in sorted(os.listdir(root)):
        if re.match(r'pakchunk\d+-Windows\.pak$', f):
            out.append(pak_read.Pak(os.path.join(root, f)))
    return out


def lengths():
    """{event: (pass ms, media, seconds, loop end s or None)} for every Online Mode track Survival adds; and what's not"""
    import build_survival                               # (its parts' names; the stock packages in build/stock)
    tracks = build_survival.music_track_list()
    ps = paks()
    def find(path):
        for p in ps:
            if path in p.files:
                return p
        raise SystemExit(f'{path} is in none of the paks')
    bnk = 'Live/Content/WwiseAudio/AKB_BGM_Online.bnk'
    objs = hirc(find(bnk).read(bnk))
    out, skipped = {}, []
    for t in tracks:
        ev = t[0]
        if not ev.startswith('AKE_Bgm_Online_'):        # (the runtime gives only these their length: MusicIsOnline)
            continue
        mid, why = media_of(objs, ev)
        if mid is None:
            skipped.append((ev, why))
            continue
        path = f'Live/Content/WwiseAudio/Media/{mid}.wem'
        rate, total, loop = wem_info(find(path).read(path, head=1 << 16))
        end = loop if loop and loop <= total else total
        out[ev] = (round(end * 1000 / rate), mid, total / rate, loop / rate if loop else None)
    return out, skipped


def block(L):
    keys = sorted(L)
    lines = [BEGIN + ' (tools/music_lengths.py write: one pass of each looping Online Mode track, its .wem\'s loop end; ms)',
             'MUSIC.passMs = {']
    row = []
    for k in keys:
        row.append(f'{k} = {L[k][0]},')
        if len(' '.join(row)) > 100:
            lines.append('    ' + ' '.join(row[:-1]))
            row = row[-1:]
    if row:
        lines.append('    ' + ' '.join(row))
    lines += ['}', END]
    return '\n'.join(lines)


def current():
    s = open(LUA, encoding='utf-8').read()
    i, j = s.find(BEGIN), s.find(END)
    assert i >= 0 and j > i, f'no {BEGIN} ... {END} block in {LUA}'
    j = s.index('\n', j) if '\n' in s[j:] else len(s)
    return s, i, j


def main(a):
    mode = a[0] if a else 'show'
    if mode not in ('show', 'write', 'check'):
        sys.exit(__doc__)
    L, skipped = lengths()
    if mode == 'show':
        for ev in sorted(L):
            ms, mid, sec, loop = L[ev]
            print(f'{ev:58s} {mid:>10d}.wem {sec:7.1f} s  loop end {loop and f"{loop:7.1f} s" or "   none  "}  pass {ms / 1000:7.1f} s')
    for ev, why in skipped:
        print(f'  not timed: {ev} ({why})')
    if mode == 'show':
        return
    new = block(L)
    s, i, j = current()
    if mode == 'write':
        s = s[:i] + new + s[j:]
        open(LUA, 'w', encoding='utf-8', newline='\n').write(s)
        print(f'sv_music.lua: {len(L)} track lengths written')
    elif mode == 'check':
        if s[i:j] != new:
            sys.exit('sv_music.lua\'s SONG LENGTHS differ from the game\'s files: run tools/music_lengths.py write')
        print(f'sv_music.lua: {len(L)} track lengths match the game\'s files')


if __name__ == '__main__':
    main(sys.argv[1:])
