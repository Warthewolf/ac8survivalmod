"""bosses_build_check.py : the boss phases' build half (behaviour roadmap P7, docs/re/BEHAVIOUR_DIRECTOR.md unit 9), without
the game (tools/checks/bosses_test.sh runs it; tools/build_all.sh builds and checks it again on the stock files):
  - (0.73.73) the Ladons' circuit (survival_events.ladon_circuit): every new path (the route's end -> arc A, each arc's
    end -> the other) starts 1-4 km ahead of the plane within 15 deg of its way, its own end 10 km or more off (hard rule
    2: the old circuit's start lay 74-88 deg off the Ladon's way at its end and was never flown, A19 2026-11-01);
    KOT's circle over the airfield, MISHKA's within Lua's 2.5 km pass radius, its far side past Lua's 5 km and inside
    leash_km less 3; every point inside the Ladons' area x 0.9 (build_survival.ladon_units asserts it too) and the zone,
    1.2 km up or more; the enraged lap (the same circle at LADON_RAGE_SPEED) long enough that each pass still bombs
    (Lua counts one pass in 30 s at most), its speed in Mission 16's range and above LADON_SPEED; names in letters
    (hard rule 17); its flags in INT_FLAGS; the Lua names (leash, rearm, legs, seen, done);
  - AB.L..IN's LastTGT (RE_SV_GlitchTurn) among GLITCH_POST_STALL but never one of Lua's random post_stall_moves;
  - the two new radio lines in TELL_LINES (AWACS lines, letters only, named by the Lua catalog);
  - the Lua names the build checks for: RE_SV_AnomalyPackSpring / Hold fired, ^RE_SV_AnomalyPack kept in co-op,
    RE_SV_LadonRage fired, RE_SV_GlitchTurn fired;
  - (2026-11-11) the Alicorn's legs for a co-op rejoiner's copy (survival_events.alcn_legs, Scripts/sv_alicorn.lua
    SPC.alicornLegOf): Lua's LANE_KM / LANE_LETTERS the build's ALCN_ROUTE / ALCN_LEG_LETTERS, each RE_SV_AlcnLeg*'s path
    from its waypoint on along the lane its way, a part leg's end onto the other way's whole leg, letters only.
"""
import math
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..'))
import survival_events as se  # noqa: E402

bad = []
lua = se.runtime_lua()

def handover(name, prev, end, after, nxt, max_deg=15.0):
    """A new path started at a path's end: its first point 1-4 km ahead of `end` (cm), within max_deg of the way the
    plane goes there (make_path's end tangent: `prev` -> `after`), its own last point 10 km or more off."""
    tx, ty = after[0] - prev[0], after[1] - prev[1]
    vx, vy = nxt[0][0] - end[0], nxt[0][1] - end[1]
    d, off = math.hypot(vx, vy) / 100000.0, math.degrees(math.acos(max(-1.0, min(1.0, (tx * vx + ty * vy) / (math.hypot(tx, ty) * math.hypot(vx, vy))))))
    far = math.dist(end[:2], nxt[-1][:2]) / 100000.0
    if not 1.0 <= d <= 4.0 or off > max_deg or far < 10.0:
        bad.append(f'{name}: the next path starts {d:.2f} km ahead, {off:.1f} deg off its way, ends {far:.1f} km off')
    return d, off


# (0.73.73) the Ladons' circuit
(ax, ay), radius = se.LADON_AREA
(zx, zy), half = se.ZONE_KM
afx, afy = se.AIRFIELD_KM
m = re.search(r'leash_km = (\d+)', lua)
leash = float(m.group(1)) if m else 0.0
if not m: bad.append('CFG.specials.ladon has no leash_km')
cc = se.ladon_circuit()
hand = []
for L in se.ladons():
    route, arc_a, arc_b = L['route'], L['arc_a_pts'], L['arc_b_pts']
    hand.append(handover(f'{L["key"]}: route -> arc A', route[-2], route[-1], arc_a[0], arc_a))
    hand.append(handover(f'{L["key"]}: arc A -> arc B', arc_a[-2], arc_a[-1], L['a_after'], arc_b))
    hand.append(handover(f'{L["key"]}: arc B -> arc A', arc_b[-2], arc_b[-1], L['b_after'], arc_a))
    pts = arc_a + arc_b
    far = max(math.dist((ax * 100000.0, ay * 100000.0), p[:2]) for p in route + pts) / 100.0
    if far >= radius * 0.9: bad.append(f'{L["unit"]}: its track {far:.0f} m from the area centre (radius {radius})')
    if any(abs(p[0] / 100000.0 - zx) >= half - 1.0 or abs(p[1] / 100000.0 - zy) >= half - 1.0 for p in pts):
        bad.append(f'{L["unit"]}: its circuit leaves the zone')
    if min(p[2] for p in pts) < 120000.0: bad.append(f'{L["unit"]}: its circuit under 1.2 km')
    shift = (route[0][1] / 100000.0 - se.LADON_ROUTE[0][1])                   # (MISHKA's whole track: km north)
    near = min(math.hypot(cc['pt'](a / 4.0)[0] - afx, cc['pt'](a / 4.0)[1] + shift - afy) for a in range(1440))
    out = max(math.hypot(cc['pt'](a / 4.0)[0] - afx, cc['pt'](a / 4.0)[1] + shift - afy) for a in range(1440))
    if near > (0.5 if L['key'] == 'Kot' else 2.4): bad.append(f'{L["unit"]}: its circuit {near:.2f} km from the airfield at closest')
    if out < 6.0 or (leash and out > leash - 3.0): bad.append(f'{L["unit"]}: its circuit out to {out:.1f} km (Lua: 5 km, leash_km {leash})')
    for k in ('arc_a', 'arc_b', 'leg_a', 'leg_b', 'leg', 'done', 'seen', 'rearm', 'leash', 'rage_flag', 'rage_ev'):
        if not se.survival_fname_plain(L[k]): bad.append(f'{L[k]}: a numeric tail (hard rule 17)')
    for k in ('leg', 'done', 'seen', 'rage_flag'):
        if L[k] not in se.INT_FLAGS: bad.append(f'{L[k]} not in INT_FLAGS')
lap = 2.0 * math.pi * se.LADON_CIRCUIT_KM                                  # km
speed = float(se.LADON_RAGE_SPEED)
lap_s = lap * 1000.0 / (speed / 3.6)
if lap_s < 30.0: bad.append(f'the enraged lap is {lap_s:.0f} s at {speed:.0f} km/h: under the 30 s a bombing pass needs')
if not float(se.LADON_SPEED) < speed <= 3200.0: bad.append(f'LADON_RAGE_SPEED {speed}: not above LADON_SPEED within Mission 16 range')
for name in ('"RE_SV_LadonLeash"', '"RE_SV_LadonRearm"', '"SV_LadonLeg"', '"SV_LadonSeen"', '"SV_LadonDone"'):
    if name not in lua: bad.append(f'Scripts/sv_ladon.lua never names {name}')
# AB.L..IN's LastTGT
if ('Turn', 'LastTGT') not in se.GLITCH_POST_STALL: bad.append('GLITCH_POST_STALL has no (Turn, LastTGT)')
m = re.search(r'post_stall_moves = \{ ([^}]*) \},', lua)
if not m or 'Turn' in re.findall(r'"(\w+)"', m.group(1)): bad.append('CFG.specials.glitch.post_stall_moves: never "Turn"')
# the radio lines
lines = {g: (t, s) for g, t, s, _ in se.TELL_LINES}
for g, tid in (('SV_Radio_GlitchEcm', 'v0001_2693'), ('SV_Radio_LadonRage', 'v0001_3110')):
    if lines.get(g, (None, None))[0] != tid or lines[g][1] != 'LIVE_AWACS': bad.append(f'{g}: not {tid} (LIVE_AWACS)')
    if f'"{se.tell_event(g)}"' not in lua: bad.append(f'{se.tell_event(g)}: no Lua tell names it')
# the Lua names
for name in ('"RE_SV_AnomalyPackSpring"', '"RE_SV_AnomalyPackHold"', '"^RE_SV_AnomalyPack"', '"RE_SV_LadonRage"',
             '"RE_SV_GlitchTurn"'):
    if name not in lua: bad.append(f'the runtime never names {name}')
# ((2026-11-11) the Alicorn's legs for a co-op rejoiner's copy: Lua's lane and letters the build's (ALCN_ROUTE,
# ALCN_LEG_LETTERS), each leg's path from the waypoint its name says (Out / Back: the lane's ends), on along the lane its
# way (east / west), its end handing over to the other way's whole leg; letters only (hard rule 17); the whole legs named
# by Lua (SPC.alicornLegOf)
m = re.search(r'local LANE_KM = \{ (.*?) \}\n', lua)
lane = [tuple(float(v) for v in p) for p in re.findall(r'\{ (-?[\d.]+), (-?[\d.]+) \}', m.group(1))] if m else []
if lane != [tuple(p) for p in se.ALCN_ROUTE]: bad.append(f'Scripts/sv_alicorn.lua LANE_KM {lane} != ALCN_ROUTE {se.ALCN_ROUTE}')
m = re.search(r'local LANE_LETTERS = "(\w+)"', lua)
if not m or m.group(1) != se.ALCN_LEG_LETTERS: bad.append('Scripts/sv_alicorn.lua LANE_LETTERS != ALCN_LEG_LETTERS')
paths = dict(se.alcn_paths())
legs = se.alcn_legs()
want = {'RE_SV_AlcnLegOut', 'RE_SV_AlcnLegBack'} | {f'RE_SV_AlcnLeg{d}{L}' for d in ('Out', 'Back') for L in se.ALCN_LEG_LETTERS[1:-1]}
if set(legs) != want: bad.append(f'alcn_legs: {sorted(legs)} != {sorted(want)}')
wp = {L: (x * 100000.0, y * 100000.0) for L, (x, y) in zip(se.ALCN_LEG_LETTERS, se.ALCN_ROUTE)}
for ev, (path, then) in legs.items():
    tail = ev[len('RE_SV_AlcnLeg'):]
    way, L = ('Out', tail[3:]) if tail.startswith('Out') else ('Back', tail[4:])
    first = wp[L or (se.ALCN_LEG_LETTERS[0] if way == 'Out' else se.ALCN_LEG_LETTERS[-1])]
    pts = paths.get(path)
    if not pts or tuple(pts[0][:2]) != first: bad.append(f'{ev}: its path {path} doesn\'t start at its waypoint')
    elif any((b[0] - a[0]) * (1 if way == 'Out' else -1) <= 0 for a, b in zip(pts, pts[1:])) or len(pts) < 2:
        bad.append(f'{ev}: {path} doesn\'t run on {way.lower()} along the lane')
    if not se.survival_fname_plain(ev) or not se.survival_fname_plain(path): bad.append(f'{ev} / {path}: a numeric tail')
    other = list(paths)[1] if way == 'Out' else list(paths)[0]          # (the other way's whole leg)
    if L and then != other: bad.append(f'{ev}: its end hands over to {then}, not {other}')
    if not L and then is not None: bad.append(f'{ev}: a whole leg with a handover of its own ({then})')
for name in ('"RE_SV_AlcnLegOut"', '"RE_SV_AlcnLegBack"'):
    if name not in lua: bad.append(f'Scripts/sv_alicorn.lua never names {name}')
if bad:
    print('bosses build: FAILED\n  ' + '\n  '.join(bad))
    sys.exit(1)
print(f'bosses build: all passed (the Ladons\' circuit {lap:.1f} km, each new path {min(h[0] for h in hand):.1f}-'
      f'{max(h[0] for h in hand):.1f} km ahead within {max(h[1] for h in hand):.0f} deg; enraged {lap_s:.0f} s a lap at '
      f'{speed:.0f} km/h; {len(se.GLITCH_POST_STALL)} AB.L..IN unique actions; {len(se.TELL_LINES)} radio lines)')
