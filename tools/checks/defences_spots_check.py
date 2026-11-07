"""defences_spots_check.py : the STORE's CIWS spots (survival_events.DEFENCE_CIWS, 0.72.1), without the game
(tools/checks/defences_test.sh runs it): each one >= 150 m from every one of Mission 22's airport objects Survival spawns or
keeps (its AA guns, SAM sites, target dummies, the parked F/A-18s and their scramble taxi: WD_Mission022_global, km on the
map), off the runway (>= 150 m from its axis, the approach box 98 m wide), >= 60 m from the amphibious troops' drives
(survival_events.lcac_craft), within 1.5 km of the airfield, at the airport objects' 5 m, the units and objects named as
the Lua runtime sells them (Scripts/sv_config.lua CFG.shop.items.Airfield.defences.ciws.units) and without a numeric
tail (hard rule 17).
"""
import math
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..'))
import survival_events as se  # noqa: E402

AIRPORT = {  # Mission 22's airport objects (x, y) km, z 5 m (7.5 m the jets)
    'AA gun 0': (16.0836, -4.2721), 'AA gun 1': (15.0612, -3.9711), 'AA gun 2': (16.9721, -4.7926),
    'AA gun 3': (17.0500, -4.6484), 'AA gun 4': (16.2310, -4.3287), 'SAM site 0': (15.1668, -3.8307),
    'SAM site 1': (15.8063, -4.1199), 'dummy 0': (15.6204, -4.1971), 'dummy 1': (15.8935, -4.1639),
    'dummy 2': (16.4605, -4.4474), 'dummy 3': (16.1913, -4.4608), 'dummy (Ground1)': (16.1085, -4.3470),
    'F/A-18 0': (16.7600, -4.5719), 'F/A-18 1': (16.7266, -4.5577),
}
AIRFIELD = (16.09639, -4.36414)
(RX, RY), RYAW = se.LCAC_RUNWAY
UX, UY = math.cos(math.radians(RYAW)), math.sin(math.radians(RYAW))
TAXI = [(0.715, 0.062), (0.729, 0.060), (0.742, 0.051), (0.748, 0.030), (0.743, 0.015), (0.732, 0.005), (0.714, 0.001)]


def axis(x_km, y_km):
    """(along, across) km on the runway's axis from its centre."""
    dx, dy = x_km - RX / 1e5, y_km - RY / 1e5
    return dx * UX + dy * UY, -dx * UY + dy * UX


def seg(p, a, b):
    vx, vy = b[0] - a[0], b[1] - a[1]
    t = max(0.0, min(1.0, ((p[0] - a[0]) * vx + (p[1] - a[1]) * vy) / (vx * vx + vy * vy)))
    return math.hypot(p[0] - a[0] - t * vx, p[1] - a[1] - t * vy)


fails = 0


def check(ok, what):
    global fails
    print(('  ok   ' if ok else '  FAIL ') + what)
    if not ok: fails += 1


print('the CIWS spots (survival_events.DEFENCE_CIWS)')
spots = se.defence_ciws()
check(len(spots) == 4 and len({u for u, _, _, _ in spots}) == 4 and len({o for _, o, _, _ in spots}) == 4, '4 units, 4 objects')
drives = [(axis(*[v / 1e5 for v in c['beach'][:2]]), axis(*[v / 1e5 for v in c['runway'][:2]])) for c in se.lcac_craft()]
for unit, obj, (x, y, z), yaw in spots:
    xk, yk = x / 1e5, y / 1e5
    near = min((math.dist((xk, yk), q), n) for n, q in AIRPORT.items())
    p = axis(xk, yk)
    taxi = min(math.dist(p, q) for q in TAXI)
    drive = min(seg(p, a, b) for a, b in drives)
    check(near[0] >= 0.150 and taxi >= 0.150, f'{obj} ({xk:.3f}, {yk:.3f}) km: {near[0] * 1000:.0f} m from the nearest airport '
          f'object ({near[1]}), {taxi * 1000:.0f} m from the scramble taxi')
    check(abs(p[1]) >= 0.150, f'{obj}: {abs(p[1]) * 1000:.0f} m off the runway axis')
    check(drive >= 0.060, f'{obj}: {drive * 1000:.0f} m from the nearest amphibious troops\' drive')
    check(math.dist((xk, yk), AIRFIELD) <= 1.5 and z == 500.0 and yaw == RYAW,
          f'{obj}: {math.dist((xk, yk), AIRFIELD):.2f} km from the airfield, z {z / 100:.0f} m, facing along the runway')
    check(not unit[-1].isdigit() and not obj[-1].isdigit() and unit.startswith('SV_Unit_') and obj.startswith('SV_Obj_'),
          f'{unit} / {obj}: Survival\'s names, no numeric tail')
lua = se.runtime_lua()
m = re.search(r'ciws = \{[^}]*units = \{([^}]*)\}', lua)
check(m is not None and re.findall(r'"(\w+)"', m.group(1)) == [u for u, _, _, _ in spots],
      'Scripts/sv_config.lua sells the build\'s CIWS units, in order')
check(se.DEFENCE_CIWS_ROW == ('sv_def_ciws', 'SV_Def_Ciws') and 'CIWS_ROW = "SV_Def_Ciws"' in lua,
      'the CIWS\'s rows: sv_def_ciws -> SV_Def_Ciws, the runtime\'s CIWS_ROW')
check(se.DEFENCE_AREA_M >= 10000 and se.DEFENCE_ALT_M[0] == 0.0, f'the defences\' area {se.DEFENCE_AREA_M:.0f} m from the ground up')
print('defences spots: all passed' if not fails else f'defences spots: {fails} FAILED')
sys.exit(1 if fails else 0)
