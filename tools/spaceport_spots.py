"""spaceport_spots.py : where the Spaceport Retake's island enemies stand (user, 2026-10-31: "on the spaceport retake, add
more enemies around the island", "do a building check so that no enemies spawn in buildings").

The building check: every building and prop round the spaceport as an oriented box (tools/data/spaceport_buildings.json,
made by tools/scan_spaceport_buildings.py from the stock level packages: each StaticMeshActor and mesh instance, the
mesh's own bounds). A spot is
  - clear: CLEAR_CM or more from every box, the launch complexes' big boxes too (so nothing stands on the pads' aprons;
    Mission 22's own AA guns stand 19-57 m from the nearest box),
  - on the island's built-up land: buildings within LAND_R_CM in all four quadrants round it (the map's land can't be
    traced from afar, hard rule 27, so the buildings stand in for it: never a shore, a harbour basin or the sea),
  - AWAY_CM from the pads and the garrison's spots, and its group's spacing from every other spot.
Everything is on a fixed grid in a fixed order: the same spots every build. pick_* answer (x, y, z) in cm.
"""
import json, math, os

HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.join(HERE, 'data', 'spaceport_buildings.json')
CLEAR_CM = 2000.0
LAND_R_CM, LAND_QUADRANTS = 30000.0, 4
AWAY_CM = 25000.0
GRID_CM = 4000.0
GROUND_Z = 500.0                     # the island's ground (Mission 22's and 19's ground units stand at z 500)
CELL = 20000.0                       # the boxes' spatial index

_boxes, _index = None, None


def boxes():
    global _boxes, _index
    if _boxes is None:
        d = json.load(open(DATA, encoding='utf-8'))
        _boxes = d['buildings']
        _index = {}
        for i, b in enumerate(_boxes):
            r = math.hypot(b['hx'], b['hy']) + CLEAR_CM + LAND_R_CM
            for cx in range(int((b['x'] - r) // CELL), int((b['x'] + r) // CELL) + 1):
                for cy in range(int((b['y'] - r) // CELL), int((b['y'] + r) // CELL) + 1):
                    _index.setdefault((cx, cy), []).append(i)
    return _boxes


def near(x, y):
    boxes()
    return [_boxes[i] for i in _index.get((int(x // CELL), int(y // CELL)), [])]


def box_dist(x, y, b):
    """Distance (cm, in the ground plane) from (x, y) to box b; 0 inside it."""
    a = math.radians(-b['yaw'])
    dx, dy = x - b['x'], y - b['y']
    lx, ly = dx * math.cos(a) - dy * math.sin(a), dx * math.sin(a) + dy * math.cos(a)
    return math.hypot(max(abs(lx) - b['hx'], 0.0), max(abs(ly) - b['hy'], 0.0))


def clearance(x, y):
    """The nearest box's distance and mesh, of the boxes near (x, y)."""
    best = (1e12, None)
    for b in near(x, y):
        d = box_dist(x, y, b)
        if d < best[0]: best = (d, b['mesh'])
    return best


def on_land(x, y):
    quads = set()
    for b in near(x, y):
        if b['kind'] != 'building': continue
        dx, dy = b['x'] - x, b['y'] - y
        if math.hypot(dx, dy) <= LAND_R_CM: quads.add((dx >= 0, dy >= 0))
    return len(quads) >= LAND_QUADRANTS


def ok(x, y):
    return clearance(x, y)[0] >= CLEAR_CM and on_land(x, y)


def ground_z(x, y):
    zs = sorted(b['zmin'] for b in near(x, y) if math.hypot(b['x'] - x, b['y'] - y) < 15000 and 300 <= b['zmin'] <= 1000)
    return max(GROUND_Z, float(round(zs[len(zs) // 2]))) if zs else GROUND_Z   # (never under the island's 5 m)


def candidates(centre, radius_cm, avoid, footprint=((0.0, 0.0),)):
    """Every grid point within radius_cm of centre whose footprint (offsets, cm) is all clear and on land, AWAY_CM from
    the avoid points, nearest the centre first."""
    out = []
    n = int(radius_cm // GRID_CM)
    for i in range(-n, n + 1):
        for j in range(-n, n + 1):
            x, y = centre[0] + i * GRID_CM, centre[1] + j * GRID_CM
            if math.hypot(x - centre[0], y - centre[1]) > radius_cm: continue
            if any(math.hypot(x - a[0], y - a[1]) < AWAY_CM for a in avoid): continue
            if all(ok(x + ox, y + oy) for ox, oy in footprint):
                out.append((math.hypot(x - centre[0], y - centre[1]), x, y))
    out.sort()
    return [(x, y) for _, x, y in out]


def spread(cands, n, spacing_cm, taken):
    """n of cands, farthest-point first (the first nearest the centre), each spacing_cm from the others and from taken."""
    chosen = []
    for x, y in cands:                          # the first: the nearest the centre that keeps its distance
        if all(math.hypot(x - t[0], y - t[1]) >= spacing_cm for t in taken):
            chosen.append((x, y)); break
    while chosen and len(chosen) < n:
        best, bd = None, -1.0
        for x, y in cands:
            d = min(math.hypot(x - c[0], y - c[1]) for c in chosen + list(taken))
            if d >= spacing_cm and d > bd: best, bd = (x, y), d
        if not best: break
        chosen.append(best)
    assert len(chosen) == n, f'only {len(chosen)} of {n} island spots fit (spacing {spacing_cm / 100:.0f} m)'
    return chosen


def with_z(pts):
    return [(x, y, ground_z(x, y)) for x, y in pts]
