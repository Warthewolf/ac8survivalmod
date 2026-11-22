"""AC:I KFM1 clip decoder (MOP2 clips), worked out 2026-11-22 from the SOLG's `auta` (ring spin) and the SOLG cutscenes'
Tdemo__* tracks.

KFM1: 'KFM1', ...; u32 @0x18 records start, u32 @0x1C records end. Records are 32 bytes: u32 hash, u16 ?, u16 bone,
u16 type (0x0503 vec3 position, 0x0704 quaternion xyzw, 0x0001 one value), u16 ?, u16 slot, u16 width.
After the records: u32 frames, then (u32 size, u32 offset) of the CONSTANT block and of the ANIMATED block.
A block: 'cdab', u16 header size (8 + 8 a track), u16 ?, u16 block size, then a track entry each:
u16 key count, u16 0, u16 first frame-number index, u16 values offset (from the block); then the u16 frame numbers;
the values (3 / 4 / 1 big-endian floats a key) at each track's offset.
The records list the constant tracks first, then the animated ones, in the blocks' entry order.
"""
import struct


def comps(typ):
    return {0x0503: 3, 0x0704: 4, 0x0001: 1}.get(typ, 4)


def block(kb, o, size):
    if size == 0 or kb[o:o + 2] != b'\xcd\xab':
        return []
    hs = struct.unpack_from('>H', kb, o + 2)[0]
    n = (hs - 8) // 8
    ents = [struct.unpack_from('>HHHH', kb, o + 8 + 8 * i) for i in range(n)]
    total = sum(e[0] for e in ents)
    times = struct.unpack_from('>%dH' % total, kb, o + hs) if total else ()
    out = []
    for nk, _, ti, vo in ents:
        out.append((list(times[ti:ti + nk]), o + vo, nk))
    return out


def decode(kb):
    assert kb[:4] == b'KFM1', kb[:4]
    rs, re_ = struct.unpack_from('>II', kb, 0x18)
    frames, asz, aoff, bsz, boff = struct.unpack_from('>IIIII', kb, re_)
    recs = []
    for r in range(rs, re_, 32):
        h, u0, bone, typ, u1, slot, width = struct.unpack_from('>IHHHHHH', kb, r)
        recs.append((bone, typ))
    A, B = block(kb, aoff, asz), block(kb, boff, bsz)
    ents = A + B
    tracks = []
    for (bone, typ), ent in zip(recs, ents):
        times, vo, nk = ent
        c = comps(typ)
        vals = [struct.unpack_from('>%df' % c, kb, vo + k * 4 * c) for k in range(nk)]
        tracks.append(dict(bone=bone, type=typ, times=times, vals=vals, animated=ent in B))
    return frames, tracks


def clips_of(d, kit_skel, flat_chunks, prefix=''):
    """every KFM1 clip in a package, in its order: [(name, kb)]"""
    out = []
    for c in flat_chunks:
        if c[1] != b'MOP2' or c[3] < 32:
            continue
        for name, kb in kit_skel.clips(d[c[2]:c[2] + c[3]]).items():
            if name.startswith(prefix):
                out.append((name, kb))
    return out


if __name__ == '__main__':
    import sys
    sys.path.insert(0, sys.argv[1])
    from fhm import fhm_tree, flat
    import skel
    d = open(sys.argv[2], 'rb').read()
    want = sys.argv[3]
    for name, kb in clips_of(d, skel, list(flat(fhm_tree(d)))):
        if want not in name:
            continue
        frames, tracks = decode(kb)
        print(name, 'frames', frames)
        for t in tracks:
            v = t['vals']
            if not v:
                continue
            pick = sorted(set([0, len(v) - 1]))
            print('  bone %d %04x %s keys %d: %s' % (t['bone'], t['type'], 'anim' if t['animated'] else 'const', len(v),
                  ' -> '.join('f%d (%s)' % (t['times'][k], ', '.join('%.2f' % x for x in v[k])) for k in pick)))
