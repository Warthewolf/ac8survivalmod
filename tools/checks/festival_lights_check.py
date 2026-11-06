"""festival_lights_check.py : THE FESTIVAL's searchlight spots (survival_events.FEST_LIGHTS, 2026-11-06), without the game.

    python -X utf8 -I tools/checks/festival_lights_check.py           check the spots (tools/build_survival.py does too)
    python -X utf8 -I tools/checks/festival_lights_check.py --scan    rebuild festival_lights_data.json from the stock level

Each spot: >= BUILDING_M from every building or prop box round the runway (tools/scan_spaceport_buildings.py's oriented
boxes from the stock level packages, here round the runway: festival_lights_data.json; compound meshes such as the airport's
paved ground and boxes no taller than the ground plates left out), >= PLANT_M from every plant (Map17_Env_Foliage_Baked's
and the airport level's instances: the mangroves north of the runway), >= 150 m from Mission 22's airport objects and the
STORE's CIWS spots (as tools/checks/defences_spots_check.py), >= 150 m off the runway's axis (170 m on the apron's side),
>= 60 m from the amphibious troops' drives, on the ground (z 5 m), inside the data's radius, named as the build contract
names them (SV_Unit_FestLight_1 .. _4).
"""
import json
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..'))
import survival_events as se  # noqa: E402

DATA = os.path.join(HERE, 'festival_lights_data.json')
RADIUS_CM = 140000.0          # the data's reach round the runway centre
BUILDING_M, PLANT_M, OBJECT_M, AXIS_M, APRON_AXIS_M, DRIVE_M = 30.0, 12.0, 150.0, 150.0, 170.0, 60.0
GROUND_TOP_CM = 600.0         # a box whose top is no higher is a ground plate (paint, the paved ground's lines)
AIRPORT = {  # Mission 22's airport objects (x, y) km (tools/checks/defences_spots_check.py)
    'AA gun 0': (16.0836, -4.2721), 'AA gun 1': (15.0612, -3.9711), 'AA gun 2': (16.9721, -4.7926),
    'AA gun 3': (17.0500, -4.6484), 'AA gun 4': (16.2310, -4.3287), 'SAM site 0': (15.1668, -3.8307),
    'SAM site 1': (15.8063, -4.1199), 'dummy 0': (15.6204, -4.1971), 'dummy 1': (15.8935, -4.1639),
    'dummy 2': (16.4605, -4.4474), 'dummy 3': (16.1913, -4.4608), 'dummy (Ground1)': (16.1085, -4.3470),
    'F/A-18 0': (16.7600, -4.5719), 'F/A-18 1': (16.7266, -4.5577),
}
(RX, RY), RYAW = se.LCAC_RUNWAY
UX, UY = math.cos(math.radians(RYAW)), math.sin(math.radians(RYAW))


def axis(x, y):
    """(along, across) cm on the runway's axis from its centre (+ across: SSE, the apron's side)."""
    dx, dy = x - RX, y - RY
    return dx * UX + dy * UY, -dx * UY + dy * UX


def seg(p, a, b):
    vx, vy = b[0] - a[0], b[1] - a[1]
    t = max(0.0, min(1.0, ((p[0] - a[0]) * vx + (p[1] - a[1]) * vy) / (vx * vx + vy * vy)))
    return math.hypot(p[0] - a[0] - t * vx, p[1] - a[1] - t * vy)


def dist_to_box(pt, e):
    """2D distance (cm) from pt to box e's footprint (0 inside): scan_spaceport_buildings.dist_to_box."""
    a = math.radians(e['yaw'])
    dx, dy = pt[0] - e['x'], pt[1] - e['y']
    lx, ly = dx * math.cos(a) + dy * math.sin(a), -dx * math.sin(a) + dy * math.cos(a)
    return math.hypot(max(abs(lx) - e['hx'], 0.0), max(abs(ly) - e['hy'], 0.0))


def clearances(spots):
    """[(unit, object, {what: metres})] for each spot."""
    d = json.load(open(DATA))
    boxes = [dict(zip(('x', 'y', 'yaw', 'hx', 'hy', 'zmax'), b)) for b in d['boxes']]
    plants = d['plants']
    objs = [(x * 1e5, y * 1e5) for x, y in AIRPORT.values()] + [p[:2] for _, _, p, _ in se.defence_ciws()]
    drives = [(c['beach'][:2], c['runway'][:2]) for c in se.lcac_craft()]
    out = []
    for unit, obj, (x, y, z), yaw in spots:
        p = (x, y)
        al, ac = axis(x, y)
        out.append((unit, obj, {
            'building': min(dist_to_box(p, e) for e in boxes) / 100.0,
            'plant': min(math.hypot(q[0] - x, q[1] - y) for q in plants) / 100.0,
            'object': min(math.dist(p, o) for o in objs) / 100.0,
            'axis': abs(ac) / 100.0, 'side': ac,
            'drive': min(seg(p, a, b) for a, b in drives) / 100.0,
            'centre': math.hypot(x - d['centre'][0], y - d['centre'][1]) / 100.0,
            'z': z / 100.0}))
    return out, d


def failures(spots):
    """What's wrong with these spots (survival_events.fest_lights()), as text; [] when they're fine."""
    bad = []
    got, d = clearances(spots)
    want = [f'SV_Unit_FestLight_{k}' for k in range(1, 5)]
    if [u for u, _, _ in got] != want: bad.append(f'units {[u for u, _, _ in got]}, the contract names {want}')
    if len({o for _, o, _ in got}) != len(got): bad.append('objects not unique')
    for unit, obj, c in got:
        if c['centre'] > d['radius_cm'] / 100.0 - 60.0: bad.append(f'{unit}: past the data ({c["centre"]:.0f} m out)')
        if c['building'] < BUILDING_M: bad.append(f'{unit}: {c["building"]:.0f} m from a building')
        if c['plant'] < PLANT_M: bad.append(f'{unit}: {c["plant"]:.0f} m from a plant')
        if c['object'] < OBJECT_M: bad.append(f'{unit}: {c["object"]:.0f} m from an airport object or CIWS spot')
        if c['axis'] < (APRON_AXIS_M if c['side'] > 0 else AXIS_M): bad.append(f'{unit}: {c["axis"]:.0f} m off the runway axis')
        if c['drive'] < DRIVE_M: bad.append(f'{unit}: {c["drive"]:.0f} m from the troops\' drive')
        if c['z'] != 5.0: bad.append(f'{unit}: z {c["z"]} m (the ground: 5 m)')
    return bad


def scan():
    """festival_lights_data.json from the stock level: tools/scan_spaceport_buildings.py's reading, round the runway."""
    sys.path.insert(0, os.path.join(HERE, '..'))
    import scan_spaceport_buildings as sb
    c = (float(RX), float(RY))
    R = RADIUS_CM
    placed, plants = [], []
    for lv in sb.sublevels():
        if not sb.pkg_file(lv): print('missing level', lv); continue
        for name, actor, mesh, M in sb.level_placements(lv):
            x, y = M[3][0], M[3][1]
            if math.hypot(x - c[0], y - c[1]) > R + 50000: continue
            k = sb.kind_of(mesh)
            if k == 'foliage':
                if math.hypot(x - c[0], y - c[1]) <= R + 5000: plants.append([round(x), round(y)])
            elif k in ('building', 'prop'):
                placed.append((mesh, M, k))
    bounds = sb.mesh_bounds([m for m, _, _ in placed], True)
    boxes = []
    for mesh, M, k in placed:
        b = bounds.get(mesh.split('.')[0])
        if not b or 'err' in b: continue
        cc, yaw, h, z0, z1 = sb.obb(M, b)
        if math.hypot(cc[0] - c[0], cc[1] - c[1]) - math.hypot(h[0], h[1]) > R: continue
        if max(h[0], h[1]) * 2 > sb.COMPOUND_CM or z1 <= GROUND_TOP_CM: continue    # (a whole complex / a ground plate)
        boxes.append([round(cc[0]), round(cc[1]), round(yaw, 1), round(h[0]), round(h[1]), round(z1)])
    json.dump({'about': 'tools/checks/festival_lights_check.py --scan: building / prop boxes [x, y, yaw, half x, half y, '
                        'top] cm and plants [x, y] round the runway (stock level packages, tools/scan_spaceport_buildings.py)',
               'centre': c, 'radius_cm': R, 'boxes': boxes, 'plants': plants}, open(DATA, 'w'), separators=(',', ':'))
    print(f'{len(boxes)} boxes, {len(plants)} plants within {R / 100:.0f} m of the runway -> {DATA}')


if __name__ == '__main__':
    if '--scan' in sys.argv: scan()
    got, _ = clearances(se.fest_lights())
    for unit, obj, c in got:
        print(f'  {unit} ({obj}): building {c["building"]:.0f} m, plant {c["plant"]:.0f} m, airport object {c["object"]:.0f} m, '
              f'axis {c["axis"]:.0f} m, troops\' drive {c["drive"]:.0f} m')
    bad = failures(se.fest_lights())
    print('festival lights: all passed' if not bad else 'festival lights FAILED: ' + '; '.join(bad))
    sys.exit(1 if bad else 0)
