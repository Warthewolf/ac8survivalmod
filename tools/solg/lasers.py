"""The SOLG's laser turrets in AC:I's mission data (2026-11-22; docs/re/SOLG.md section 11).

AC:I's SOLG mission graph (DATA92 entry 529: its biggest chunk, big-endian) places 28 copies of one turret model,
f_111t (crc 0xef2cd596; HUD name CONT_LASER UNIT, health 850, the only SOLG piece type with weapon blocks: its type
record at graph offset 144736, its type pointer 0x80023560, a direct graph offset). Each placement is a record 56 bytes
before a use of that pointer: +4 position (3 floats, metres), +16 rotation (3 floats, radians, Rz @ Ry @ Rx), +28 its
instance-name crc. The ones before graph offset 700000 follow an arm's record (arm_refs: the four s_sg01 records, taken
as plan nodes 01..04 in order: the arms are alike, so the order changes nothing) and are in that arm's frame (4 an arm:
16, set A, riding ring 1); the rest are in the body's frame (12 round the barrel, set B).

turrets(layout) -> [{'set': 'A' | 'B', 'arm': plan index or None, 'pos': AC:I body-frame metres at rest, 'R': 3x3}]
(layout: prepare.py's, for the arms' plan-node poses). AC:I's frame as prepare.py's (z along the barrel)."""
import os, struct
import numpy as np

TYPE_PTR = 0x80023560
ARM_REFS = [600004, 615220, 626868, 638516]          # the four s_sg01 records' type-pointer uses
SET_A_BEFORE = 700000
TURN = np.array([[0, 0, 1], [0, 1, 0], [-1, 0, 0]], np.float64)


def euler(rx, ry, rz):
    cx, sx, cy, sy, cz, sz = np.cos(rx), np.sin(rx), np.cos(ry), np.sin(ry), np.cos(rz), np.sin(rz)
    Rx = np.array([[1, 0, 0], [0, cx, -sx], [0, sx, cx]])
    Ry = np.array([[cy, 0, sy], [0, 1, 0], [-sy, 0, cy]])
    Rz = np.array([[cz, -sz, 0], [sz, cz, 0], [0, 0, 1]])
    return Rz @ Ry @ Rx


def graph(DPL, fhm_tree, flat):
    d = DPL(os.path.join(os.environ['ACI_USRDIR'], 'DATA92.PAC')).read(529)
    ch = list(flat(fhm_tree(d)))
    big = max(ch, key=lambda c: c[3])
    return d[big[2]:big[2] + big[3]]


def turrets(layout, g):
    w = struct.unpack('>%dI' % (len(g) // 4), g[:len(g) // 4 * 4])
    refs = [i * 4 for i, x in enumerate(w) if x == TYPE_PTR][1:]     # (the first: its type record's own)
    assert len(refs) == 28, ('f_111t placements', len(refs))
    arms = sorted([m for m in layout['mounts'] if m['model'] == 's_sg01'], key=lambda m: m['index'])
    assert len(arms) == 4
    out = []
    for o in refs:
        a = o - 56
        p = np.array(struct.unpack('>3f', g[a + 4:a + 16]), np.float64)
        Rl = euler(*struct.unpack('>3f', g[a + 16:a + 28]))
        if o < SET_A_BEFORE:
            k = max(i for i, x in enumerate(ARM_REFS) if x < o)
            m = arms[k]
            Ra = TURN.T @ np.array(m['rot_m']) @ TURN          # (layout's rot_m is in the glTF frame)
            out.append({'set': 'A', 'arm': m['index'], 'pos': Ra @ p + np.array(m['aci_pos_m']), 'R': Ra @ Rl, 'local': p})
        else:
            out.append({'set': 'B', 'arm': None, 'pos': p, 'R': Rl, 'local': p})
    assert sum(1 for t in out if t['set'] == 'A') == 16, 'set A: 4 on each arm'
    return out
