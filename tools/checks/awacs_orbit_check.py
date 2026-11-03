"""awacs_orbit_check.py : VOID WATCHER 1's orbit, the build's half (0.73.73; tools/survival_events.py awacs_orbit,
build_awacs), without the game (tools/checks/defences_test.sh runs it):
  - the lead-in's first point 0.5-2 km ahead of the climb-out's end (AWACS_CLIMB_END), within 15 deg of its way out
    (AWACS_CLIMB_DIR): every new path starts a little ahead of the plane along its way (hard rule 2; the orbit paths of
    0.73.33-0.73.61 began off to its side and were never flown);
  - each later new path (the lead-in's end -> arc B, each arc's end -> the other) 1-3 km ahead within 15 deg of the way
    the plane goes there (make_path's end tangent), its own end 8 km or more off;
  - the arcs round the airfield at AWACS_ORBIT_KM (5-7 km: the tester's "a circle with a 5-7 kilometer radius") and
    AWACS_ALT_KM, in its unit area's height band; the lead-in climbing no steeper than 25 deg, its turn no tighter than
    2.5 km; ~bank on the circle at AWACS_SPEED under 30 deg, on the lead-in at AWACS_IN_SPEED under 35;
  - every point inside the zone and inside its unit area (AWACS_AREA_M) less 2 km; the backstop's lost_km
    (Scripts/sv_config.lua CFG.allies.awacs.orbit) past the orbit by 2 km or more and inside the area;
  - names in letters (hard rule 17), SV_AwacsLeg in INT_FLAGS;
  - (0.73.78, plan G5) its ways home (AWACS_OUT_A / _B): from each arc's end 1-3 km ahead within 15 deg of its way, a
    straight leg (no point more than 2 deg off its first heading) at the orbit's height, ending 15 km or more from the
    airfield, inside the zone and inside AWACS_HOME_AREA_M less 2 km; SV_AwacsHome / SV_AwacsOut in INT_FLAGS; the
    runtime's RE_SV_AwacsHome / RE_SV_AwacsRemove and its gone_km (Scripts/sv_config.lua CFG.allies.awacs.home) short of
    the exits' end.
"""
import math
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..'))
import survival_events as se  # noqa: E402

bad = []
o = se.awacs_orbit()
c = se.AIRFIELD_KM
km = lambda p: (p[0] / 100000.0, p[1] / 100000.0, p[2] / 100000.0)


def ang(a, b):
    return math.degrees(math.acos(max(-1.0, min(1.0, (a[0] * b[0] + a[1] * b[1]) / (math.hypot(*a) * math.hypot(*b))))))


# the lead-in's start, from the climb-out's end
e = se.AWACS_CLIMB_END
p0 = km(o['in'][0])
d0, off0 = math.hypot(p0[0] - e[0], p0[1] - e[1]), ang((p0[0] - e[0], p0[1] - e[1]), se.AWACS_CLIMB_DIR)
if not 0.5 <= d0 <= 2.0 or off0 > 15.0:
    bad.append(f'the lead-in starts {d0:.2f} km from the climb-out\'s end, {off0:.1f} deg off its way')
# each handover
hand = []
for name, a, after, b in (('lead-in -> arc B', o['in'], o['in_after'], o['arc_b']), ('arc B -> arc A', o['arc_b'], o['b_after'], o['arc_a']),
                          ('arc A -> arc B', o['arc_a'], o['a_after'], o['arc_b'])):
    end, prev, nxt = km(a[-1]), km(a[-2]), km(b[0])
    t = (after[0] / 100000.0 - prev[0], after[1] / 100000.0 - prev[1])
    v = (nxt[0] - end[0], nxt[1] - end[1])
    d, off, far = math.hypot(*v), ang(v, t), math.hypot(km(b[-1])[0] - end[0], km(b[-1])[1] - end[1])
    hand.append((d, off))
    if not 1.0 <= d <= 3.0 or off > 15.0 or far < 8.0:
        bad.append(f'{name}: the next path starts {d:.2f} km ahead, {off:.1f} deg off its way, ends {far:.1f} km off')
# the circle
if not 5.0 <= se.AWACS_ORBIT_KM <= 7.0: bad.append(f'AWACS_ORBIT_KM {se.AWACS_ORBIT_KM}: not the tester\'s 5-7 km')
lo, hi = se.AWACS_ALT_BAND_M
for p in o['arc_a'] + o['arc_b']:
    x, y, z = km(p)
    if abs(math.hypot(x - c[0], y - c[1]) - se.AWACS_ORBIT_KM) > 0.01: bad.append(f'an arc point {math.hypot(x - c[0], y - c[1]):.2f} km out')
    if not lo / 1000.0 <= z <= hi / 1000.0: bad.append(f'an arc point {z:.2f} km up, outside its band')
pts = [km(p) for p in o['in']]
climb = max(math.degrees(math.atan2(b[2] - a[2], math.hypot(b[0] - a[0], b[1] - a[1]))) for a, b in zip([km(o['in_before'])] + pts, pts))
if climb > 25.0: bad.append(f'the lead-in climbs {climb:.1f} deg at its steepest')
if o['rho'] < 2.5: bad.append(f'the lead-in turns at {o["rho"]:.2f} km')
bank = lambda v_kmh, r_km: math.degrees(math.atan2((v_kmh / 3.6) ** 2 / (r_km * 1000.0), 9.81))
b_orbit, b_in = bank(float(se.AWACS_SPEED), se.AWACS_ORBIT_KM), bank(float(se.AWACS_IN_SPEED), o['rho'])
if b_orbit > 30.0: bad.append(f'{b_orbit:.0f} deg of bank round the orbit at {se.AWACS_SPEED} km/h')
if b_in > 35.0: bad.append(f'{b_in:.0f} deg of bank on the lead-in at {se.AWACS_IN_SPEED} km/h')
# the zone, its area, the backstop
(zx, zy), half = se.ZONE_KM
reach = max(math.hypot(x - c[0], y - c[1]) for x, y, _ in pts + [km(p) for p in o['arc_a'] + o['arc_b']])
if any(abs(x - zx) >= half - 1.0 or abs(y - zy) >= half - 1.0 for x, y, _ in pts): bad.append('the lead-in leaves the zone')
if reach > se.AWACS_AREA_M / 1000.0 - 2.0: bad.append(f'the orbit reaches {reach:.1f} km, its area {se.AWACS_AREA_M:.0f} m')
cfg = open(os.path.join(HERE, '..', '..', 'mod', 'UE4SS', 'AC8SurvivalMode', 'Scripts', 'sv_config.lua'), encoding='utf-8').read()
m = re.search(r'orbit = \{ event = "RE_SV_AwacsOrbit", climb_s = \d+, lost_km = (\d+)', cfg)
if not m: bad.append('CFG.allies.awacs.orbit: no lost_km')
elif not reach + 2.0 <= float(m.group(1)) <= se.AWACS_AREA_M / 1000.0 + 3.0:
    bad.append(f'CFG.allies.awacs.orbit.lost_km {m.group(1)}: not 2 km past the orbit ({reach:.1f} km) or well past its area')
for n in (se.AWACS_PATH_IN, se.AWACS_ARC_A, se.AWACS_ARC_B, 'SV_AwacsLeg', 'SV_AwacsLegIn', 'SV_AwacsLegA', 'SV_AwacsLegB'):
    if not se.survival_fname_plain(n): bad.append(f'{n}: a numeric tail (hard rule 17)')
if 'SV_AwacsLeg' not in se.INT_FLAGS: bad.append('SV_AwacsLeg not in INT_FLAGS')
# (0.73.78, plan G5) its ways home
outs = []
for name, arc, out, before in (('arc B -> exit B', o['arc_b'], o['out_b'], o['out_b_before']), ('arc A -> exit A', o['arc_a'], o['out_a'], o['out_a_before'])):
    end, prev, first = km(arc[-1]), km(arc[-2]), km(out[0])
    if math.dist(km(before)[:2], end[:2]) > 1e-6: bad.append(f'{name}: its tangent\'s point before isn\'t the arc\'s end')
    t = (end[0] - prev[0], end[1] - prev[1])                     # (the arc's way at its end, a half step back)
    a = math.atan2(end[1] - c[1], end[0] - c[0])
    tt = (-o['sense'] * math.sin(a), o['sense'] * math.cos(a))    # (the circle's tangent there)
    v = (first[0] - end[0], first[1] - end[1])
    d, off = math.hypot(*v), ang(v, tt)
    if not 1.0 <= d <= 3.0 or off > 15.0 or ang(t, tt) > 15.0:
        bad.append(f'{name}: the exit starts {d:.2f} km ahead, {off:.1f} deg off its way')
    pts_o = [km(p) for p in out]
    head = (pts_o[1][0] - pts_o[0][0], pts_o[1][1] - pts_o[0][1])
    bend = max(ang((b[0] - a2[0], b[1] - a2[1]), head) for a2, b in zip(pts_o, pts_o[1:]))
    far = math.hypot(pts_o[-1][0] - c[0], pts_o[-1][1] - c[1])
    if bend > 2.0: bad.append(f'{name}: the exit bends {bend:.1f} deg')
    if far < 15.0: bad.append(f'{name}: the exit ends {far:.1f} km from the airfield')
    if any(not lo / 1000.0 <= z <= hi / 1000.0 for _, _, z in pts_o): bad.append(f'{name}: the exit leaves its height band')
    if any(abs(x - zx) >= half - 1.0 or abs(y - zy) >= half - 1.0 for x, y, _ in pts_o): bad.append(f'{name}: the exit leaves the zone')
    if far > se.AWACS_HOME_AREA_M / 1000.0 - 2.0: bad.append(f'{name}: the exit reaches {far:.1f} km, its area {se.AWACS_HOME_AREA_M:.0f} m')
    outs.append((d, off, far))
for n in (se.AWACS_OUT_A, se.AWACS_OUT_B, 'SV_AwacsHome', 'SV_AwacsOut', 'SV_AwacsOutDoneA', 'SV_AwacsOutDoneB'):
    if not se.survival_fname_plain(n): bad.append(f'{n}: a numeric tail (hard rule 17)')
for n in ('SV_AwacsHome', 'SV_AwacsOut'):
    if n not in se.INT_FLAGS: bad.append(f'{n} not in INT_FLAGS')
mh = re.search(r'home = \{ event = "RE_SV_AwacsHome", remove = "RE_SV_AwacsRemove", gone_km = (\d+)', cfg)
if not mh: bad.append('CFG.allies.awacs.home: not RE_SV_AwacsHome / RE_SV_AwacsRemove with a gone_km')
elif not reach + 4.0 <= float(mh.group(1)) <= min(f for _, _, f in outs) - 2.0:
    bad.append(f'CFG.allies.awacs.home.gone_km {mh.group(1)}: not past the orbit ({reach:.1f} km) and short of the exits\' ends')
if bad:
    print('awacs orbit: FAILED\n  ' + '\n  '.join(bad))
    sys.exit(1)
print(f'awacs orbit: all passed ({se.AWACS_ORBIT_KM:.1f} km round, ~{b_orbit:.0f} deg of bank at {se.AWACS_SPEED} km/h; the '
      f'lead-in {d0:.2f} km ahead, {off0:.0f} deg off, a {o["turn"]:.0f} deg turn of {o["rho"]:.2f} km (~{b_in:.0f} deg at '
      f'{se.AWACS_IN_SPEED}), climbing {climb:.0f} deg at most; each new arc {min(h[0] for h in hand):.2f} km ahead within '
      f'{max(h[1] for h in hand):.0f} deg; reach {reach:.1f} km in a {se.AWACS_AREA_M:.0f} m area; its exits '
      f'{min(x[0] for x in outs):.2f} km ahead within {max(x[1] for x in outs):.0f} deg, out to {min(x[2] for x in outs):.1f} km)')
