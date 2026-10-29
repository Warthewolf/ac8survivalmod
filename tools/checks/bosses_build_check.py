"""bosses_build_check.py : the boss phases' build half (behaviour roadmap P7, tools/re/BEHAVIOUR_DIRECTOR.md unit 9), without
the game (tools/checks/bosses_test.sh runs it; tools/build_all.sh builds and checks it again on the stock files):
  - the enraged Ladon's circuit (survival_events.LADON_RAGE): starts and ends where the old circuit does (hard rule 2),
    every point inside the Ladons' area x 0.9 (build_survival.ladon_units asserts it too), a lap long enough that each
    pass still bombs (Lua counts one pass in 30 s at most: sv_ladon.lua), a speed in Mission 16's range, names in letters
    (hard rule 17), its flags in INT_FLAGS;
  - AB.L..IN's LastTGT (RE_SV_GlitchTurn) among GLITCH_POST_STALL but never one of Lua's random post_stall_moves;
  - the two new radio lines in TELL_LINES (AWACS lines, letters only, named by the Lua catalog);
  - the Lua names the build checks for: RE_SV_AnomalyPackSpring / Hold fired, ^RE_SV_AnomalyPack kept in co-op,
    RE_SV_LadonRage fired, RE_SV_GlitchTurn fired.
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
# the rage circuit
rage, loop = se.LADON_RAGE, se.LADON_LOOP
if rage[0] != loop[0] or rage[-1] != loop[-1] or rage[-1] != se.LADON_AIRFIELD:
    bad.append('LADON_RAGE must start just past the airfield (LADON_LOOP[0]) and end over it (LADON_AIRFIELD)')
lap = sum(math.dist(a[:2], b[:2]) for a, b in zip(rage, rage[1:]))       # km
speed = float(se.LADON_RAGE_SPEED)
lap_s = lap * 1000.0 / (speed / 3.6)
if lap_s < 30.0: bad.append(f'the rage lap is {lap_s:.0f} s at {speed:.0f} km/h: under the 30 s a bombing pass needs')
if not 1200.0 <= speed <= 3200.0: bad.append(f'LADON_RAGE_SPEED {speed}: outside Mission 16 range 1200-3200')
if lap >= sum(math.dist(a[:2], b[:2]) for a, b in zip(loop, loop[1:])): bad.append('the rage circuit is no tighter than the old one')
(ax, ay), radius = se.LADON_AREA
for L in se.ladons():
    far = max(math.dist((ax * 100000.0, ay * 100000.0), p[:2]) for p in L['rage_route']) / 100.0
    if far >= radius * 0.9: bad.append(f'{L["unit"]}: its rage circuit {far:.0f} m from the area centre (radius {radius})')
    for k in ('rage', 'rage_lap', 'rage_flag', 'rage_ev'):
        if not se.survival_fname_plain(L[k]): bad.append(f'{L[k]}: a numeric tail (hard rule 17)')
    if L['rage_flag'] not in se.INT_FLAGS: bad.append(f'{L["rage_flag"]} not in INT_FLAGS')
    if min(p[2] for p in L['rage_route']) < 120000.0: bad.append(f'{L["unit"]}: its rage circuit under 1.2 km')
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
if bad:
    print('bosses build: FAILED\n  ' + '\n  '.join(bad))
    sys.exit(1)
print(f'bosses build: all passed (the rage circuit {lap:.1f} km, {lap_s:.0f} s a lap at {speed:.0f} km/h; '
      f'{len(se.GLITCH_POST_STALL)} AB.L..IN unique actions; {len(se.TELL_LINES)} radio lines)')
