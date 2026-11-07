"""survival_events_squads.py : the squads' events: the enemy fighters' orders and the allies'.

The economy review's orders (build_review: escorts, decoys, the allies' Hunt / Cover / Defend), the ace moves
(build_ace_moves), the Wolf trap (build_wolf), the squad director (build_director: its slots are
survival_events.SALVO_SLOT / SPEC_SLOT), the tells' radio (TELL_LINES, build_tells), Wraith's blinks
(WRAITH_BLINK_*, build_wraith), the STORE's allies (build_allies: MOONCHILD, the ships, the co-op stand-ins) and VOID
WATCHER 1's orbit and ESM (build_awacs; its names are survival_events.AWACS_*).

A part of tools/survival_events.py (its docstring has the layout): every name survival_events defines is
here through the import below, and survival_events imports this part back whole, so each name here is
survival_events.<name> too (build_survival.py and tools/checks read them so). Import survival_events, not this file.
"""
from survival_events import *  # noqa: F401,F403 (survival_events' names; it imports this part at its end)


# The tells' radio lines (behaviour roadmap P3; Scripts/sv_config.lua CFG.tells, Scripts/sv_tells.lua,
# tools/re/BEHAVIOUR_DIRECTOR.md unit 4): (group, TextID, SpeakerID, options), all stock AC8 lines (never AC7 voice).
# build_survival.py build_radio adds each as a one-row group of DT_SV_Radio, a clone of Mission 22's AWACS row 382 with
# this line (its voice the global AKB_Voice bank's <TextID>_Play, its subtitle the TextID's text: hard rule 33; the
# build checks every _Play is there), LimitPlayCount 0; build_tells a remote event RE_SV_Radio<Suffix> (tell_event)
# that plays it, the only way Lua plays radio. Group suffixes are letters only (hard rule 17). Options: 'now' = StartDelay
# 0.1 s and Channel InterruptMain (Mission 3's row 233), for the lines an action follows by a short lead. Enemy lines of a
# named unit speak as a Sotoan fighter (Common_Enemy_Fighter_*), so no campaign squadron's name shows. Wingmen's lines
# (Kate, Coster, Baxter) are left out: they aren't flying (the user had Baxter's and Tasha's cut, 2026-10-23).
TELL_LINES = [
    # ace reversal / kulbit (ACE.movesTick)
    ('SV_Radio_TurnA', 'v0001_1928', 'LIVE_AWACS', {'now': True}),        # "That's a sudden turn - coming straight at you!" (ST_ms029 418)
    ('SV_Radio_TurnB', 'v0417_0002', 'Common_Enemy_Fighter_A', {'now': True}),   # "He's mine!" (PByP 3071, Shadow 160th's)
    # a hunting tier's flight closing in (ACE.hunt)
    ('SV_Radio_HuntA', 'v1236_0019', 'ms12_Enemy_Commander', {}),         # "Hunt down the Wings of Theve, and I promise you a war medal!" (ST_ms012 408)
    ('SV_Radio_HuntB', 'v0929_0001', 'Common_Enemy_Fighter_A', {}),       # "I see our prey." (PByP 3397, Shadow 150th's)
    # a raid / strike on the airfield (Mission 22's airfield is "the eastern airfield")
    ('SV_Radio_RaidA', 'v0001_2784', 'LIVE_AWACS', {}),                   # "Joker Flight, enemy aircraft approaching the eastern airfield." (ST_ms022 123)
    ('SV_Radio_RaidB', 'v0001_2240', 'LIVE_AWACS', {}),                   # "Enemy attackers closing on the base." (ST_ms004 499)
    ('SV_Radio_RaidC', 'v0001_2223', 'LIVE_AWACS', {}),                   # "Shoot down the bombers. Protect the base." (ST_ms004 304)
    # the jammer
    ('SV_Radio_Jam', 'v0001_1694', 'LIVE_AWACS', {}),                     # "The enemy's jamming you with a powerful ECM." (ST_ms016 70)
    ('SV_Radio_JamDown', 'v0001_0536', 'LIVE_AWACS', {}),                 # "Hostile EW aircraft destroyed! Jamming has been lifted!" (ST_ms012 91)
    # a late round's next wave
    ('SV_Radio_WaveA', 'v0001_2072', 'LIVE_AWACS', {}),                   # "New enemy aircraft detected. Look sharp!" (ST_ms021 47)
    ('SV_Radio_WaveB', 'v0001_1862', 'LIVE_AWACS', {}),                   # "Enemy reinforcements!" (ST_ms028 235)
    ('SV_Radio_WaveC', 'v0001_4111', 'LIVE_AWACS', {}),                   # "Bandits inbound! More reinforcements!" (ST_ms028 685)
    ('SV_Radio_WaveD', 'v0001_2071', 'LIVE_AWACS', {}),                   # "Enemy reinforcements spotted, closing fast." (ST_ms011 247)
    # the ALICORN
    ('SV_Radio_AlcnRailFirst', 'v0001_2389', 'LIVE_AWACS', {}),           # "Joker Flight, the railgun has been activated." (ST_ms030 713)
    ('SV_Radio_AlcnRailA', 'v0001_2391', 'LIVE_AWACS', {}),               # "Enemy railgun's ready to fire." (ST_ms024 585)
    ('SV_Radio_AlcnRailB', 'v0001_3510', 'LIVE_AWACS', {}),               # "Railguns are getting ready to fire!" (ST_ms027 28)
    ('SV_Radio_AlcnDive', 'v0001_3342', 'LIVE_AWACS', {}),                # "Enemy submarine diving!" (ST_ms030 654)
    ('SV_Radio_AlcnUp', 'v0001_3344', 'LIVE_AWACS', {}),                  # "Submarine has surfaced. Begin attack!" (ST_ms030 671)
    ('SV_Radio_AlcnVls', 'v0001_2895', 'LIVE_AWACS', {}),                 # "Missile launch from VLS!" (ST_ms025_1 74)
    ('SV_Radio_AlcnDeck', 'v0001_3037', 'LIVE_AWACS', {}),                # "Planes launching from the carrier!" (ST_ms026 105; P7)
    # a Ladon's VLS volley
    ('SV_Radio_LadonVlsA', 'v0001_1709', 'LIVE_AWACS', {}),               # "Large aircraft has launched missile." (ST_ms016 378)
    ('SV_Radio_LadonVlsB', 'v0001_1710', 'LIVE_AWACS', {}),               # "The bomber has launched a missile!" (ST_ms016 380)
    # the squad director's (P2; catalogued, not said yet)
    ('SV_Radio_PincerA', 'v0001_2608', 'LIVE_AWACS', {}),                 # "More hostiles from two new bearings!" (ST_ms003 15)
    ('SV_Radio_PincerB', 'v0001_2860', 'LIVE_AWACS', {}),                 # "If we defend one side, the other one'll get us." (ST_ms022 392)
    ('SV_Radio_PincerC', 'v0001_1885', 'LIVE_AWACS', {}),                 # "Coming at us from two directions, with reinforcements!" (ST_ms028 432)
    ('SV_Radio_PincerD', 'v0001_1886', 'LIVE_AWACS', {}),                 # "Make sure they don't surround you! Intercept with full force!" (ST_ms028 450)
    ('SV_Radio_DiveA', 'v0001_1926', 'LIVE_AWACS', {'now': True}),        # "Joker 1, right above you!" (ST_ms029 607)
    ('SV_Radio_DiveB', 'v0001_3067', 'LIVE_AWACS', {'now': True}),        # "Enemy aircraft diving!" (ST_ms026 467)
    ('SV_Radio_DiveC', 'v0001_1703', 'LIVE_AWACS', {'now': True}),        # "The aircraft is diving!" (ST_ms016 122)
    ('SV_Radio_DiveD', 'v0001_3111', 'LIVE_AWACS', {'now': True}),        # "Bandit's coming straight down toward you!" (ST_ms026 769)
] + [(f'SV_Radio_Clock{chr(65 + k)}', f'v0001_{307 + k:04d}', 'LIVE_AWACS', {})   # "Bandit at 1..12 o'clock!" (PByP 7283-7294)
     for k in range(12)] + [
    ('SV_Radio_Drag', 'v0001_1857', 'LIVE_AWACS', {}),                    # "Don't chase them, there's reinforcements inbound!" (ST_ms028 170)
    ('SV_Radio_EnLureA', 'v1900_0009', 'Common_Enemy_Fighter_B', {}),     # "I'll lure him into your sights!" (ST_ms019 646, Shadow 140th's)
    ('SV_Radio_EnLureB', 'v0929_0061', 'Common_Enemy_Fighter_C', {}),     # "I'll fake an opening to lure 'em in." (ST_ms009 1001, Shadow 150th's)
    ('SV_Radio_Trap', 'v0001_4058', 'LIVE_AWACS', {'now': True}),         # "Multiple enemies confirmed! It's an ambush!" (ST_ms021 312)
    ('SV_Radio_EnTrap', 'v1903_0001', 'ms19_Enemy_Fighter_Mob_A', {'now': True}),   # "We'll trap this one between us." (ST_ms019 618)
    ('SV_Radio_EnCoverA', 'v4204_0017', 'Common_Enemy_Fighter_E', {}),    # "Someone cover me!" (PByP 5226)
    ('SV_Radio_EnCoverB', 'v4206_0017', 'Common_Enemy_Fighter_G', {}),    # "Somebody help me!" (PByP 5230)
    ('SV_Radio_EnCoverC', 'v4207_0017', 'Common_Enemy_Fighter_H', {}),    # "Assistance! I need assistance!" (PByP 5232)
    ('SV_Radio_SixA', 'v0001_0026', 'LIVE_AWACS', {'now': True}),         # "Joker 1! Check your six!" (PByP 28)
    ('SV_Radio_SixB', 'v0001_0028', 'LIVE_AWACS', {'now': True}),         # "Enemy on your six!" (PByP 30)
    ('SV_Radio_SixC', 'v0001_0025', 'LIVE_AWACS', {'now': True}),         # "Joker 1, enemy on your tail." (PByP 27)
    ('SV_Radio_SixD', 'v0001_0027', 'LIVE_AWACS', {'now': True}),         # "Enemy behind you!" (PByP 29)
    ('SV_Radio_BracketA', 'v0001_0016', 'LIVE_AWACS', {'now': True}),     # "Missiles! Joker 1, break off!" (PByP 18)
    ('SV_Radio_BracketB', 'v0001_0014', 'LIVE_AWACS', {'now': True}),     # "Missile closing in! Evasive action!" (PByP 16)
    ('SV_Radio_BracketC', 'v0001_4034', 'LIVE_AWACS', {'now': True}),     # "Incoming barrage!" (ST_ms020 434)
    ('SV_Radio_RegroupA', 'v0001_3003', 'LIVE_AWACS', {}),                # "They're trying to regroup." (ST_ms025_1 791)
    ('SV_Radio_RegroupB', 'v0001_1884', 'LIVE_AWACS', {}),                # "They tricked us! The aircraft that retreated regrouped and are back!" (ST_ms028 431)
    # the bosses' phases (P7; MINDRIPPER's pack reuses Trap / EnTrap, AB.L..IN behind you the Six lines)
    ('SV_Radio_GlitchEcm', 'v0001_2693', 'LIVE_AWACS', {}),               # "It's not jamming anymore!" (ST_ms023 02_Jamming_Off)
    ('SV_Radio_LadonRage', 'v0001_3110', 'LIVE_AWACS', {}),               # "The hostile's changed course." (ST_ms026 03_Nightmare_Assault)
]
TELL_START_DELAY_S = 0.1                              # the 'now' lines' StartDelay (the template row's is 0.6 s)
TELL_CHANNEL_INTERRUPT = 6                            # ELiveRadioChannel InterruptMain (Main is 2)


def tell_event(group):
    """The remote event that plays tell group SV_Radio_<Suffix>: RE_SV_Radio<Suffix>."""
    assert group.startswith('SV_Radio_'), group
    return 'RE_SV_Radio' + group[len('SV_Radio_'):]


ESCORT_RADIUS_M = 8000.0          # a raid's escorts hold this close over the airfield (main.lua CFG.escorts)
ALLY_COVER_RADIUS_M = 5000.0      # main.lua CFG.allies.orders cover_radius_m / defend_radius_m (keep in step)
ALLY_DEFEND_RADIUS_M = 8000.0


def build_review(g, stock_ep, t_search, t_engage, t_bmove):
    """The economy review's orders (2026-10-25), all remote events Scripts/sv_*.lua fires:
    RE_SV_Escort_NN      pool flight NN escorts a raid: its area on the airfield (Mission 22's airport strike move,
                         ESCORT_RADIUS_M), air-only search, Normal / PlayerFirst (you first, then the allied aircraft)
    RE_SV_Decoy_NN       pool flight NN breaks off: engagement None (as MOONCHILD's hold on the ground)
    RE_SV_DecoyEnd_NN    ... and back: its appearance's orders (air-only, PlayerOnlyNoLimit)
    RE_SV_Ally<Order><X> MOONCHILD / WINGMEN flight X's orders: Hunt (its area back on the airfield, the pool's 40 km),
                         Cover (its area moved near you, Mission 6's NearPlayer move, ALLY_COVER_RADIUS_M) and Defend (on
                         the airfield, ALLY_DEFEND_RADIUS_M). The radius is Mission 6's LiveChangeUnitRadius."""
    m06 = os.path.join(os.path.dirname(os.path.dirname(stock_ep)), 'MIssion006', 'EP_Mission006_global.uasset')
    t_radius = g.foreign_template(m06, 'LiveChangeUnitRadius', 'PhaseStart_Phase02_2')
    t_near = g.foreign_template(m06, 'LiveUnitMoveActor', 'CE_ReinforceAppear_Phase01_2')
    assert arg_values(t_near)[12] == 'NearPlayer', arg_values(t_near)
    assert len(arg_values(t_radius)) == 3, arg_values(t_radius)
    t_hold = g.exec_template('LiveAIEngagementOrder', 'RE_Wave01_Start', lambda a, e: a[0] == 'AB_Obj_01_Air1_f18e_0')
    assert arg_values(t_hold)[3] == 'None', arg_values(t_hold)
    for k, unit in enumerate(POOL):
        ev = f'RE_SV_Escort_{k + 1:02d}'
        g.trigger('RE_SpawnEnemy_kokatu_1st', ev)
        g.execute(t_bmove, ev, {0: unit})
        g.execute(t_radius, ev, {0: unit, 1: 'NoneSelect', 2: f'{ESCORT_RADIUS_M:.1f}'})
        g.execute(t_search, ev, {1: unit}, delay=1.0)
        g.execute(t_engage, ev, {1: unit, 6: 'PlayerFirst'}, delay=1.0)
        ev = f'RE_SV_Decoy_{k + 1:02d}'
        g.trigger('RE_SpawnEnemy_kokatu_1st', ev)
        g.execute(t_hold, ev, {0: 'NoneSelect', 1: unit})
        ev = f'RE_SV_DecoyEnd_{k + 1:02d}'
        g.trigger('RE_SpawnEnemy_kokatu_1st', ev)
        g.execute(t_search, ev, {1: unit})
        g.execute(t_engage, ev, {1: unit, 6: 'PlayerOnlyNoLimit'})
    for unit in ALLY_AIR_UNITS:
        x = unit[-1]
        ev = f'RE_SV_AllyHunt{x}'
        g.trigger('RE_SpawnEnemy_kokatu_1st', ev)
        g.execute(t_bmove, ev, {0: unit})
        g.execute(t_radius, ev, {0: unit, 1: 'NoneSelect', 2: f'{AREA_RADIUS_M:.1f}'})
        ev = f'RE_SV_AllyCover{x}'
        g.trigger('RE_SpawnEnemy_kokatu_1st', ev)
        g.execute(t_near, ev, {0: unit})
        g.execute(t_radius, ev, {0: unit, 1: 'NoneSelect', 2: f'{ALLY_COVER_RADIUS_M:.1f}'})
        ev = f'RE_SV_AllyDefend{x}'
        g.trigger('RE_SpawnEnemy_kokatu_1st', ev)
        g.execute(t_bmove, ev, {0: unit})
        g.execute(t_radius, ev, {0: unit, 1: 'NoneSelect', 2: f'{ALLY_DEFEND_RADIUS_M:.1f}'})


def build_ace_moves(g, flag, stock_ep):
    """Ace moves (2026-10-23, "a proper fix for the cannon fodder"; tools/re/UNIQUE_ACTIONS.md): remote events that
    Scripts/main.lua fires on a pool flight flying a top tier (CFG.aces.flight <tier>.moves) when the player gets
    behind one of its aircraft: RE_SV_AceTurn_NN = the campaign aces' LastTGT (a hard 600 km/h turn onto the player,
    then 10 s 200 m behind it, twice), RE_SV_AceKulbit_NN = the Shadow squadron's kulbit (0.5 s straight, a kulbit firing
    its special weapon). Both OneShot (they end by themselves), by unit (every plane of the flight), Below_Return
    (they outrank evading, provoke and pursuit). The stock EnemyBehind trigger isn't used: it only fires for the
    player's selected target, matches a callsign, and re-fires every frame (restarting the move)."""
    m06 = os.path.join(os.path.dirname(os.path.dirname(stock_ep)), 'MIssion006', 'EP_Mission006_global.uasset')
    t_req = g.foreign_template(m06, 'LiveAIRequestUniqueAction', 'EnemyBehind_LastTGT')
    assert arg_values(t_req)[3] == 'LastTGT', arg_values(t_req)
    for k, unit in enumerate(POOL):
        for name, action in (('AceTurn', 'LastTGT'), ('AceKulbit', 'Shadow_Kulbit')):
            ev = f'RE_SV_{name}_{k + 1:02d}'
            g.trigger('RE_SpawnEnemy_kokatu_1st', ev)
            g.execute(t_req, ev, {0: 'NoneSelect', 1: unit, 2: '', 3: action, 4: 'OneShot', 5: 'Below_Return', 6: 'NoneSelect', 7: 'false'})


def build_wolf(g, stock_ep, t_search, t_engage):
    """The Wolf trap (behaviour roadmap P1; the critic's gap fill, tools/re/BEHAVIOUR_DIRECTOR.md unit 5): per-object
    remote events on each Wolf flight's trap objects (wolf_held: the odd ones; POOL_OBJS, the names after sizing),
    NN its pool index and L the object's letter (A = object 0; letters, hard rule 17), all fired by Scripts/sv_spawn.lua:
    RE_SV_WolfHold_<NN><L>  engagement None on that object alone (Mission 22's MOONCHILD hold, RE_Wave01_Start, the
                            stock by-object form): it stops attacking and follows its formation [I] (forwarded in co-op,
                            so a joiner's copy holds too)
    RE_SV_WolfFree_<NN><L>  back: air-only search and PlayerOnlyNoLimit on that object (its appearance's orders; forwarded)
    RE_SV_WolfTurn_<NN><L>  the campaign aces' LastTGT on that object alone (Mission 6's EnemyBehind_LastTGT, by object as
                            every stock request is; OneShot, Below_Return): a hard turn onto the player, then 200 m behind
                            it (LocalPlayer: on a co-op host the host, so it's kept there, sv_coop.lua KEEP_EVENTS)."""
    import re
    lua = runtime_lua()
    m = re.search(r'ROLE_BY_FLIGHT\s*=\s*\{([^}]*)\}', lua)
    assert m and re.findall(r'"(\w+)"', m.group(1)) == ROLE_BY_FLIGHT, \
        f'Scripts/sv_config.lua ROLE_BY_FLIGHT is not survival_events.ROLE_BY_FLIGHT {ROLE_BY_FLIGHT}'
    m = re.search(r'LANCER_TOP_M\s*=\s*([\d.]+)', lua)
    assert m and float(m.group(1)) == LANCER_MAX_ALT_M, f'Scripts/sv_config.lua ROLE.LANCER_TOP_M is not {LANCER_MAX_ALT_M}'
    for row in list(ROLE_NPC):                       # (the roles' behaviour rows rolesSetup makes DT_NPC rows for)
        assert f'"{row}"' in lua, f'Scripts/sv_config.lua ROLE.ROWS has no {row}'
    t_hold = g.exec_template('LiveAIEngagementOrder', 'RE_Wave01_Start', lambda a, e: a[0] == 'AB_Obj_01_Air1_f18e_0')
    assert arg_values(t_hold)[3] == 'None' and arg_values(t_hold)[1] == 'NoneSelect', arg_values(t_hold)
    assert arg_values(t_search)[0] == 'NoneSelect' and arg_values(t_engage)[0] == 'NoneSelect'   # (arg 0 the object)
    m06 = os.path.join(os.path.dirname(os.path.dirname(stock_ep)), 'MIssion006', 'EP_Mission006_global.uasset')
    t_req = g.foreign_template(m06, 'LiveAIRequestUniqueAction', 'EnemyBehind_LastTGT')
    assert arg_values(t_req)[3] == 'LastTGT' and arg_values(t_req)[0] != 'NoneSelect', arg_values(t_req)
    n = 0
    for k, unit in enumerate(POOL):
        if POOL_ROLE[unit] != 'wolf' or behaviour_row(unit) != ROLE_ROW['wolf']: continue
        objs = POOL_OBJS.get(unit)
        assert objs and len(objs) == flight_size(unit), (unit, objs)       # (build_wd_global runs first)
        for j, obj in enumerate(objs):
            if not wolf_held(j): continue
            tail = f'{k + 1:02d}{chr(65 + j)}'
            ev = f'RE_SV_WolfHold_{tail}'
            g.trigger('RE_SpawnEnemy_kokatu_1st', ev)
            g.execute(t_hold, ev, {0: obj, 1: 'NoneSelect'})
            ev = f'RE_SV_WolfFree_{tail}'
            g.trigger('RE_SpawnEnemy_kokatu_1st', ev)
            g.execute(t_search, ev, {0: obj, 1: 'NoneSelect'})
            g.execute(t_engage, ev, {0: obj, 1: 'NoneSelect', 6: 'PlayerOnlyNoLimit'})
            ev = f'RE_SV_WolfTurn_{tail}'
            g.trigger('RE_SpawnEnemy_kokatu_1st', ev)
            g.execute(t_req, ev, {0: obj, 1: 'NoneSelect', 2: '', 3: 'LastTGT', 4: 'OneShot', 5: 'Below_Return',
                                  6: 'NoneSelect', 7: 'false'})
            n += 1
    assert n > 0, 'no Wolf trap objects'
    print(f'  wolf trap: {n} held objects in {sum(1 for u in POOL if POOL_ROLE[u] == "wolf")} Wolf flights '
          f'(RE_SV_WolfHold / WolfFree / WolfTurn_<NN><L>)')


def build_director(g, stock_ep, t_search, t_engage):
    """The squad director's events (behaviour roadmap P2; tools/re/BEHAVIOUR_DIRECTOR.md unit 6), all fired by
    Scripts/sv_director.lua:
    RE_SV_Salvo_<NN><L>  one object's missile at the player (SALVO_SLOT; NN its flight's pool index, L the object's
                         letter, A = object 0: hard rule 17), on every usable pool flight's objects (POOL_OBJS, after
                         sizing; not the probe flights'). Kept on the co-op host (sv_coop.lua KEEP_EVENTS: "Player" is each
                         game's own); a joiner gets its own by "dv"
    RE_SV_DirHold_NN     a pool flight's engagement None (Mission 22's MOONCHILD hold, by unit, as RE_SV_Decoy_NN): its
                         top cover held high, its regroup (forwarded: a joiner's copies hold their fire too; Decoy is each
                         player's own, kept, so it can't be reused)
    RE_SV_DirFree_NN     ... and back: its appearance's orders (air-only search, PlayerOnlyNoLimit; forwarded)"""
    import re
    lua = runtime_lua()
    m = re.search(r'SALVO_FCS_SLOT\s*=\s*(\d+)', lua)
    assert m and int(m.group(1)) + 1 == int(SALVO_SLOT.rsplit('_', 1)[1]), \
        f'Scripts/sv_director.lua DIR.SALVO_FCS_SLOT is not {SALVO_SLOT} - 1'
    for fmt in ('"RE_SV_Salvo_%02d%s"', '"RE_SV_DirHold_%02d"', '"RE_SV_DirFree_%02d"'):
        assert fmt in lua, f'Scripts/sv_director.lua never fires {fmt}'
    assert '"^RE_SV_Salvo_"' in lua, 'Scripts/sv_coop.lua KEEP_EVENTS has no ^RE_SV_Salvo_'
    assert '"RE_SV_SpecFire_%02d%s"' in lua and '"^RE_SV_SpecFire_"' in lua, \
        'Scripts/sv_spweapons.lua never fires RE_SV_SpecFire_<NN><L>, or sv_coop.lua KEEP_EVENTS lacks it'
    m = re.search(r'SPW\.FCS_SLOT\s*=\s*(\d+)', lua)
    assert m and int(m.group(1)) + 1 == int(SPEC_SLOT.rsplit('_', 1)[1]), f'Scripts/sv_spweapons.lua SPW.FCS_SLOT is not {SPEC_SLOT} - 1'
    m19 = os.path.join(os.path.dirname(os.path.dirname(stock_ep)), 'Mission019', 'EP_Mission019_global.uasset')
    t_fire = g.foreign_template(m19, 'LiveFireOneShotWeapon', '05_PhaseStart_4', lambda a, e: a[1] == 'E_Obj_00_Air0_rflm_0')
    assert arg_values(t_fire)[0] == 'WN_WEAPON_3' and arg_values(t_fire)[2] == 'Player', arg_values(t_fire)
    t_hold = g.exec_template('LiveAIEngagementOrder', 'RE_Wave01_Start', lambda a, e: a[0] == 'AB_Obj_01_Air1_f18e_0')
    assert arg_values(t_hold)[3] == 'None', arg_values(t_hold)
    n = 0
    probes = set(PROBE_UNITS.values())
    for k, unit in enumerate(POOL):
        ev = f'RE_SV_DirHold_{k + 1:02d}'
        g.trigger('RE_SpawnEnemy_kokatu_1st', ev)
        g.execute(t_hold, ev, {0: 'NoneSelect', 1: unit})
        ev = f'RE_SV_DirFree_{k + 1:02d}'
        g.trigger('RE_SpawnEnemy_kokatu_1st', ev)
        g.execute(t_search, ev, {1: unit})
        g.execute(t_engage, ev, {1: unit, 6: 'PlayerOnlyNoLimit'})
        if unit in probes: continue
        objs = POOL_OBJS.get(unit)
        assert objs and len(objs) == flight_size(unit), (unit, objs)       # (build_wd_global runs first)
        for j, obj in enumerate(objs):
            ev = f'RE_SV_Salvo_{k + 1:02d}{chr(65 + j)}'
            g.trigger('RE_SpawnEnemy_kokatu_1st', ev)
            g.execute(t_fire, ev, {0: SALVO_SLOT, 1: obj})
            ev = f'RE_SV_SpecFire_{k + 1:02d}{chr(65 + j)}'           # (its special weapon: SPEC_SLOT)
            g.trigger('RE_SpawnEnemy_kokatu_1st', ev)
            g.execute(t_fire, ev, {0: SPEC_SLOT, 1: obj})
            n += 1
    print(f'  director: {n} salvo objects in {len(POOL) - len(probes)} flights (RE_SV_Salvo_<NN><L>, {SALVO_SLOT}; '
          f'specials RE_SV_SpecFire_<NN><L>, {SPEC_SLOT}), '
          f'{len(POOL)} flights held / freed (RE_SV_DirHold / DirFree_NN)')


AWACS_EVENTS = {}                              # build_allies' events build_awacs goes on from ('airborne')


def build_awacs(g, stock_ep):
    """VOID WATCHER 1's orbit and ESM (AWACS_*): the climb-out's end -> the lead-in (AWACS_PATH_IN) on Mission 16's Ladon
    path record; its end -> arc B; each arc's end -> the other (awacs_orbit; hard rules 1, 2, 35), SV_AwacsLeg + 1 at
    each; Lua's backstop RE_SV_AwacsOrbit takes it off its path onto the area orbit. RE_SV_AwacsEsm fires AWACS_ESM_SLOT
    on it (Mission 19's LiveFireOneShotWeapon, as the jammer's ECM), which Scripts/sv_allies.lua fires every esm.every_s
    while it's airborne. Forwarded in co-op: each joiner's copy fields its ESM there too."""
    lua = runtime_lua()
    assert 'RE_SV_AwacsEsm' in lua, 'Scripts/sv_config.lua CFG.allies.awacs never names RE_SV_AwacsEsm'
    assert AWACS_UNIT in lua and AWACS_NAME_KEY in lua, 'Scripts/sv_config.lua CFG.allies.awacs != AWACS_UNIT / AWACS_NAME_KEY'
    m16 = os.path.join(os.path.dirname(os.path.dirname(stock_ep)), 'Mission016', 'EP_Mission016_global.uasset')
    t_path = g.foreign_template(m16, 'LiveAIPathExecution', 'PathFinish_Ladon0_0', lambda a, e: a[0] == 'B_Obj_01_Air0_Ladon0')
    m19 = os.path.join(os.path.dirname(os.path.dirname(stock_ep)), 'Mission019', 'EP_Mission019_global.uasset')
    t_fire = g.foreign_template(m19, 'LiveFireOneShotWeapon', '05_PhaseStart_4', lambda a, e: a[1] == 'E_Obj_00_Air0_rflm_0')
    finish = '01_A_Air1_f18e_PathFinish'                   # PathFinish trigger template: {0 object, 2 path}
    # (0.73.62-0.73.72) Its orbit was its unit area, not a path (the path was never flown: it flew straight on, to
    # 163 km on 2026-10-31): it circled 0.9-6.9 km from the airfield, turning tight (2026-11-01). (0.73.73) A path
    # again, started where the plane is going (awacs_orbit): the climb-out's end (its airborne records, build_allies)
    # -> the lead-in, as the Ladons' route's end -> their circuit; then the arcs. Its unit area still onto the airport (the bombers'
    # LiveUnitMoveActor, AIRFIELD_MARK) at AWACS_AREA_M (Mission 6's LiveChangeUnitRadius), round the whole orbit.
    m06 = os.path.join(os.path.dirname(os.path.dirname(stock_ep)), 'MIssion006', 'EP_Mission006_global.uasset')
    t_radius = g.foreign_template(m06, 'LiveChangeUnitRadius', 'PhaseStart_Phase02_2')
    t_bmove = g.exec_template('LiveUnitMoveActor', 'Default_CompositeEvent_19')       # unit area onto AreaB_MarkActor0
    assert arg_values(t_bmove)[3] == AIRFIELD_MARK, arg_values(t_bmove)
    t_exit = g.exec_template('LiveAIPathExitExecution', 'Default_CompositeEvent_19', lambda a, e: a[0] != 'NoneSelect')
    assert arg_values(t_exit)[1] == 'NoneSelect', arg_values(t_exit)
    assert 'RE_SV_AwacsOrbit' in lua, 'Scripts/sv_allies.lua never fires RE_SV_AwacsOrbit'
    for ev, area in ((AWACS_EVENTS['airborne'], AWACS_AREA_M), (AWACS_EVENTS['orbit'], AWACS_FALLBACK_AREA_M)):
        if ev == AWACS_EVENTS['orbit']:
            # (0.73.73) Lua's backstop (its climb-out never ended, or it's off its orbit): off any path first (Mission
            # 22's airport strike leaves its path so), then the area orbit of 0.73.62-0.73.72 round the airport
            g.execute(t_exit, ev, {0: AWACS_OBJ})
        g.execute(t_bmove, ev, {0: AWACS_UNIT}, delay=1.0)
        g.execute(t_radius, ev, {0: AWACS_UNIT, 1: 'NoneSelect', 2: f'{area:.1f}'}, delay=1.5)
    g.flags.add('SV_AwacsLeg')                             # (set 0 by its appearance: build_allies)
    t_flag = g.exec_template('LiveFlagOperation_IntExecution', pred=lambda a, e: a[1] == 'Set')
    g.execute(t_path, AWACS_EVENTS['airborne'], {0: AWACS_OBJ, 2: AWACS_PATH_IN, 4: AWACS_IN_SPEED})
    # ((0.73.78, G5) each arc's end: the other arc while it serves (SV_AwacsHome 0), its exit once it's sent home (1):
    # fresh conditions a record, as the Ladons' rage's; the lead-in's end always onto arc B, whose end then takes it out)
    staying, homing = (lambda: [g.cond('SV_AwacsHome', 'Leq', 0)]), (lambda: [g.cond('SV_AwacsHome', 'Geq', 1)])
    for ev, path, nxt, out in (('SV_AwacsLegIn', AWACS_PATH_IN, AWACS_ARC_B, None), ('SV_AwacsLegB', AWACS_ARC_B, AWACS_ARC_A, AWACS_OUT_B),
                               ('SV_AwacsLegA', AWACS_ARC_A, AWACS_ARC_B, AWACS_OUT_A)):
        g.trigger(finish, ev, arg_changes={0: AWACS_OBJ, 2: path})
        g.execute(t_flag, ev, {0: 'SV_AwacsLeg', 1: 'Add', 2: 1})
        if out is None:
            g.execute(t_path, ev, {0: AWACS_OBJ, 2: nxt, 4: AWACS_SPEED})
            continue
        g.execute(t_path, ev, {0: AWACS_OBJ, 2: nxt, 4: AWACS_SPEED}, conds=staying())
        g.execute(t_path, ev, {0: AWACS_OBJ, 2: out, 4: AWACS_SPEED}, conds=homing())
        g.execute(t_flag, ev, {0: 'SV_AwacsOut', 1: 'Set', 2: 1}, conds=homing())
        g.execute(t_radius, ev, {0: AWACS_UNIT, 1: 'NoneSelect', 2: f'{AWACS_HOME_AREA_M:.1f}'}, delay=0.5, conds=homing())
    # ((0.73.78, G5) the exit's end (SV_AwacsOut 2: Lua takes it off), Lua's RE_SV_AwacsHome (sent home: the flag the arcs'
    # ends read) and RE_SV_AwacsRemove (taken off: Mission 22's own despawn on its unit, LiveSetActiveGameObjectExecution
    # false, as RE_SV_FlightOff_NN; SV_AwacsAir 0). Forwarded in co-op: each joiner's copy goes with it)
    for ev, path in (('SV_AwacsOutDoneA', AWACS_OUT_A), ('SV_AwacsOutDoneB', AWACS_OUT_B)):
        g.trigger(finish, ev, arg_changes={0: AWACS_OBJ, 2: path})
        g.execute(t_flag, ev, {0: 'SV_AwacsOut', 1: 'Set', 2: 2})
    assert '"RE_SV_AwacsHome"' in lua and '"RE_SV_AwacsRemove"' in lua, 'Scripts/sv_config.lua CFG.allies.awacs.home never names RE_SV_AwacsHome / Remove'
    g.trigger('RE_SpawnEnemy_kokatu_1st', 'RE_SV_AwacsHome')
    g.execute(t_flag, 'RE_SV_AwacsHome', {0: 'SV_AwacsHome', 1: 'Set', 2: 1})
    t_off = g.exec_template('LiveSetActiveGameObjectExecution', None, lambda a, e: a[0] != 'NoneSelect' and a[3] == 'false')
    g.trigger('RE_SpawnEnemy_kokatu_1st', 'RE_SV_AwacsRemove')
    g.execute(t_off, 'RE_SV_AwacsRemove', {0: 'NoneSelect', 1: AWACS_UNIT, 2: 'NoneSelect', 3: 'false'})
    g.execute(t_flag, 'RE_SV_AwacsRemove', {0: 'SV_AwacsAir', 1: 'Set', 2: 0})
    g.trigger('RE_SpawnEnemy_kokatu_1st', 'RE_SV_AwacsEsm')
    g.execute(t_fire, 'RE_SV_AwacsEsm', {0: AWACS_ESM_SLOT, 1: AWACS_OBJ})
    o = awacs_orbit()
    print(f'  VOID WATCHER 1: orbit {AWACS_ORBIT_KM:.1f} km round the airfield ({"counter-" if o["sense"] > 0 else ""}clockwise; '
          f'its lead-in a {o["turn"]:.0f} deg turn of {o["rho"]:.2f} km, then {AWACS_IN_CIRCLE_DEG:.0f} deg climbing), its '
          f'area {AWACS_AREA_M:.0f} m ({AWACS_FALLBACK_AREA_M:.0f} m on the backstop), its ESM on RE_SV_AwacsEsm ({AWACS_ESM_SLOT}); '
          f'home: exits of {len(o["out_a"])} + {len(o["out_b"])} points, {AWACS_OUT_KM:.0f} km out from each arc\'s end '
          f'(RE_SV_AwacsHome, RE_SV_AwacsRemove; 0.73.78)')


# The ace squadrons' blinks (behaviour roadmap P9: "Wraith blinks like a lesser AB.L..IN"; tools/re/BEHAVIOUR_DIRECTOR.md
# unit 10): AB.L..IN's teleport (Mission 22's LiveActorTeleportExecution: the object onto the player plus a world offset,
# facing back at them; hard rule 39) for the lead (object 0) of each pool flight of WRAITH_BLINK_ROLE's group (the
# squadrons that blink fly those flights: Scripts/sv_config.lua CFG.aces.flight <tier>.roles), to a spot every
# WRAITH_BLINK_STEP_DEG round, WRAITH_BLINK_RING_M out at the player's height. Scripts/sv_config.lua ACE.BLINK is the same
# (build_wraith checks it); Scripts/sv_ai.lua ACE.squadTick picks the spot.
WRAITH_BLINK_STEP_DEG = 45
WRAITH_BLINK_RING_M = 1000
WRAITH_BLINK_ROLE = 'duelist'


def wraith_blinks():
    """[(unit, event, bearing deg)]: RE_SV_WraithBlink<K><J>, K the flight's pool index as a letter (A = POOL[0]), J the
    bearing's (A = 0 deg); letters only (hard rule 17). The lead of each WRAITH_BLINK_ROLE flight, not the probes'."""
    out = []
    probes = set(PROBE_UNITS.values())
    for k, unit in enumerate(POOL):
        if POOL_ROLE[unit] != WRAITH_BLINK_ROLE or unit in probes: continue
        for j, deg in enumerate(range(0, 360, WRAITH_BLINK_STEP_DEG)):
            out.append((unit, f'RE_SV_WraithBlink{chr(65 + k)}{chr(65 + j)}', deg))
    return out


def build_wraith(g):
    """The ace squadrons' blinks (see WRAITH_BLINK_*): one remote event per lead and spot, fired by Scripts/sv_ai.lua
    ACE.squadTick (kept on a co-op host: "Player" is each game's own, sv_coop.lua KEEP_EVENTS)."""
    import math
    import re
    lua = runtime_lua()
    m = re.search(r'BLINK = \{ STEP_DEG = (\d+), RING_M = (\d+), ROLE = "(\w+)" \}', lua)
    assert m and int(m.group(1)) == WRAITH_BLINK_STEP_DEG and int(m.group(2)) == WRAITH_BLINK_RING_M and (
        m.group(3) == WRAITH_BLINK_ROLE), 'Scripts/sv_config.lua ACE.BLINK != WRAITH_BLINK_*'
    assert '"RE_SV_WraithBlink%s%s"' in lua, 'Scripts/sv_ai.lua never fires RE_SV_WraithBlink<K><J>'
    assert '"^RE_SV_WraithBlink"' in lua, 'Scripts/sv_coop.lua KEEP_EVENTS has no ^RE_SV_WraithBlink'
    t_tp = g.exec_template('LiveActorTeleportExecution', '01_Wave05_YesEvent02', lambda a, e: a[1] == 'A_Obj_01_dummyN0')
    v = arg_values(t_tp)
    assert v[2] == 'Player' and v[13] == 'Absolute' and v[8] == 'NoneSelect', v
    n, units = 0, set()
    for unit, ev, deg in wraith_blinks():
        objs = POOL_OBJS.get(unit)
        assert objs and len(objs) == flight_size(unit), (unit, objs)       # (build_wd_global runs first)
        g.trigger('RE_SpawnEnemy_kokatu_1st', ev)                          # a remote event Lua fires
        r = WRAITH_BLINK_RING_M * 100
        dx, dy = r * math.cos(math.radians(deg)), r * math.sin(math.radians(deg))
        yaw = (deg + 180 + 180) % 360 - 180                                 # facing back at the player
        g.execute(t_tp, ev, {1: objs[0], 4: f'{dx:.1f}', 5: f'{dy:.1f}', 6: '0.0', 9: '0.0', 10: '0.0', 11: f'{yaw:.1f}'})
        n += 1
        units.add(unit)
    assert n > 0, 'no blink events'
    print(f'  wraith blinks: {n} spots for the leads of {len(units)} {WRAITH_BLINK_ROLE} flights (RE_SV_WraithBlink<K><J>, '
          f'{WRAITH_BLINK_RING_M} m every {WRAITH_BLINK_STEP_DEG} deg)')


def build_allies(g, flag, t_search, t_move, t_bsearch):
    """The STORE's allies (ALLY_*): MOONCHILD's scramble, the ships' lanes, and the enemy orders Scripts/main.lua fires
    at them: RE_SV_Hunt_NN (pool flight NN prefers AI targets: allied aircraft over the player) and
    RE_SV_Strike<ship unit>_NN (bomber flight NN attacks that ship only)."""
    tpl = lambda cls, ev, pred=None: g.exec_template(cls, ev, pred)
    lead = lambda i: (lambda a, e: a[i] == 'AB_Obj_01_Air1_f18e_0')
    t_hold = tpl('LiveAIPathExecution', 'RE_Wave01_Start', lead(0))                   # Path0 at speed 0
    t_taxi = tpl('LiveAIPathExecution', '01_Wave01_CheckDistanceEvent', lead(0))      # Path0 at 50
    t_roll = tpl('LiveAIPathExecution', '01_A_Air1_f18e_PathFinish')                  # Path1 at 600
    t_climb = tpl('LiveAIPathExecution', '01_A_Air1_f18e_PathFinish_1')               # Path2 at 800
    t_gear_dn = tpl('LiveEnableLandingGear', 'RE_Wave01_Start', lead(0))
    t_gear_up = tpl('LiveEnableLandingGear', '01_A_Air1_f18e_PathFinish_3')
    t_attr_hold = tpl('LiveSetCommonAttribute', 'RE_Wave01_Start', lead(1))
    t_attr_taxi = tpl('LiveSetCommonAttribute', '01_Wave01_CheckDistanceEvent', lead(1))
    t_attr_air = tpl('LiveSetCommonAttribute', '01_A_Air1_f18e_PathFinish_3')
    t_eng_hold = tpl('LiveAIEngagementOrder', 'RE_Wave01_Start', lead(0))             # None: no fighting on the ground
    t_eng_air = tpl('LiveAIEngagementOrder', '01_A_Air1_f18e_PathFinish_3')           # Normal, Default
    t_radio = tpl('LiveRadioPlayExecution', '01_Wave01_CheckDistanceEvent')           # allies taking off
    assert [arg_values(t)[2] for t in (t_hold, t_taxi, t_roll, t_climb)] == TAKEOFF_LEAD[:1] * 2 + TAKEOFF_LEAD[1:]
    assert arg_values(t_hold)[4] in ('0', '0.0') and arg_values(t_taxi)[4] == '50'
    assert arg_values(t_gear_dn)[3] == 'true' and arg_values(t_gear_up)[3] == 'false'
    assert arg_values(t_attr_hold)[3:5] == ['false', 'true'] and arg_values(t_attr_air)[3:5] == ['true', 'false']
    assert arg_values(t_eng_air)[3] == 'Normal' and arg_values(t_eng_air)[6] == 'Default'
    assert arg_values(t_radio)[0] == '01_Wave1_Ally_Take_Off'
    finish = '01_A_Air1_f18e_PathFinish'                   # PathFinish trigger template: {0 object, 2 path}
    assert arg_values(g.trig_template(finish))[2] == TAKEOFF_LEAD[0]
    for unit in ALLY_AIR_UNITS:
        x = unit[-1]
        o_lead, o_wing = ALLY_AIR_OBJS[unit]
        up, air = f'SV_AllyUp{x}', f'SV_AllyAir{x}'
        g.trigger('01_E_AreaA_ReinforcementAppearance_0', up, arg_changes={0: unit})
        flag(up, air, 'Set', 0)
        for o, path in ((o_lead, TAKEOFF_LEAD[0]), (o_wing, TAKEOFF_WING_FIRST)):
            g.execute(t_hold, up, {0: o, 2: path})
            g.execute(t_gear_dn, up, {0: o})
            g.execute(t_attr_hold, up, {1: o})
            g.execute(t_eng_hold, up, {0: o})
        g.execute(t_taxi, up, {0: o_lead}, delay=3.0)
        g.execute(t_taxi, up, {0: o_wing, 2: TAKEOFF_WING_FIRST}, delay=8.0)
        for o in (o_lead, o_wing):
            g.execute(t_attr_taxi, up, {1: o}, delay=3.0)
        g.execute(t_radio, up, delay=3.0)
        # the chain, one PathFinish trigger per aircraft and path: wing onto the lead's start first
        chain = [(o_lead, TAKEOFF_LEAD[0], t_roll, 'L1'), (o_wing, TAKEOFF_WING_FIRST, t_taxi, 'W0'),
                 (o_wing, TAKEOFF_LEAD[0], t_roll, 'W1'), (o_lead, TAKEOFF_LEAD[1], t_climb, 'L2'),
                 (o_wing, TAKEOFF_LEAD[1], t_climb, 'W2')]
        for o, path, nxt, tag in chain:
            ev = f'SV_AllyTakeoff{x}{tag}'
            g.trigger(finish, ev, arg_changes={0: o, 2: path})
            g.execute(nxt, ev, {0: o})
        for o, tag in ((o_lead, 'L'), (o_wing, 'W')):
            ev = f'SV_AllyAirborne{x}{tag}'                  # the end of the climb out: a fighter now
            g.trigger(finish, ev, arg_changes={0: o, 2: TAKEOFF_LEAD[2]})
            g.execute(t_gear_up, ev, {0: o})
            g.execute(t_attr_air, ev, {1: o})
            g.execute(t_eng_air, ev, {0: o})
            g.execute(t_search, ev, {0: o, 1: 'NoneSelect'})
            flag(ev, air, 'Add', 1)
    # VOID WATCHER 1 (AWACS_*): MOONCHILD's lead's scramble for its one aircraft; airborne: gear up, no longer
    # invincible, no fighting, SV_AwacsAir 1, then the orbit (build_awacs)
    o = AWACS_OBJ
    up = 'SV_AwacsUp'
    g.trigger('01_E_AreaA_ReinforcementAppearance_0', up, arg_changes={0: AWACS_UNIT})
    flag(up, 'SV_AwacsAir', 'Set', 0)
    flag(up, 'SV_AwacsLeg', 'Set', 0)                      # (0.73.73: its orbit's legs flown, build_awacs)
    flag(up, 'SV_AwacsHome', 'Set', 0)                     # ((0.73.78, G5) not sent home yet, no exit flown)
    flag(up, 'SV_AwacsOut', 'Set', 0)
    g.execute(t_hold, up, {0: o, 2: TAKEOFF_LEAD[0]})
    g.execute(t_gear_dn, up, {0: o})
    g.execute(t_attr_hold, up, {1: o})
    g.execute(t_eng_hold, up, {0: o})
    g.execute(t_taxi, up, {0: o}, delay=3.0)
    g.execute(t_attr_taxi, up, {1: o}, delay=3.0)
    for path, nxt, tag in ((TAKEOFF_LEAD[0], t_roll, 'L1'), (TAKEOFF_LEAD[1], t_climb, 'L2')):
        ev = f'SV_AwacsTakeoff{tag}'
        g.trigger(finish, ev, arg_changes={0: o, 2: path})
        g.execute(nxt, ev, {0: o})
    AWACS_EVENTS['airborne'] = ev = 'SV_AwacsAirborne'
    g.trigger(finish, ev, arg_changes={0: o, 2: TAKEOFF_LEAD[2]})
    g.execute(t_gear_up, ev, {0: o})
    g.execute(t_attr_air, ev, {1: o})
    g.execute(t_eng_hold, ev, {0: o})
    flag(ev, 'SV_AwacsAir', 'Set', 1)
    # (the same from Lua, RE_SV_AwacsOrbit: an E-767 that never reaches the fighters' climb-out's end, or wanders off its
    # orbit, is put on it anyway: Scripts/sv_allies.lua ALLY.awacsTick's backstop)
    AWACS_EVENTS['orbit'] = ev = 'RE_SV_AwacsOrbit'
    g.trigger('RE_SpawnEnemy_kokatu_1st', ev)
    g.execute(t_gear_up, ev, {0: o})
    g.execute(t_attr_air, ev, {1: o})
    g.execute(t_eng_hold, ev, {0: o})
    flag(ev, 'SV_AwacsAir', 'Set', 1)
    # Survival COOP: the other players' planes (COOP_PEER_*): gear up and no fighting as soon as each is up
    for c, unit, obj in zip(COOP_PEER_SLOTS, COOP_PEER_UNITS, COOP_PEER_OBJS):
        ev = f'SV_CoopPeerUp{c}'
        g.trigger('01_E_AreaA_ReinforcementAppearance_0', ev, arg_changes={0: unit})
        g.execute(t_gear_up, ev, {0: obj}, delay=0.5)
        g.execute(t_eng_hold, ev, {0: obj}, delay=0.5)
    # ships: on their lane at once, and again from its start whenever they reach its end; turrets fire at will
    t_spath = tpl('LiveAIPathExecution', 'RE_Wave01_Start', lambda a, e: a[0] == 'AC_Obj_01_Ship1_aegs_0')
    t_upath = tpl('LiveAIPathExecution', 'RE_Wave01_Start', lambda a, e: a[1] == 'AC_Unit_01_Ship1')
    t_seng = tpl('LiveAIEngagementOrder', 'UnitDamage_Enemy_Ship_Last1', lambda a, e: a[0].startswith('AC_Obj_01_Ship1'))
    assert arg_values(t_spath)[4] == ALLY_SHIP_SPEED and arg_values(t_seng)[3] == 'Normal'
    for key, n, unit, obj, lane in ally_ships():
        up, lap = f'SV_ShipUp{key}{unit[-1]}', f'SV_ShipLap{key}{unit[-1]}'
        g.trigger('01_E_AreaA_ReinforcementAppearance_0', up, arg_changes={0: unit})
        g.trigger(finish, lap, arg_changes={0: obj, 2: lane})
        for ev, delay in ((up, 1.0), (lap, 2.0)):
            g.execute(t_spath, ev, {0: obj, 2: lane}, delay=delay)
            g.execute(t_upath, ev, {1: unit, 2: lane}, delay=delay)
        g.execute(t_seng, up, {0: 'NoneSelect', 1: unit}, delay=2.0)
    # enemy orders on them: a fighter flight that prefers AI targets (Mission 22's AIFirst order, no target: the allied
    # aircraft first, else the player; still air-only), and a strike flight on one ship (as on the shuttle)
    t_hunt = g.exec_template('LiveAIEngagementOrder', pred=lambda a, e: a[3] == 'Normal' and a[6] == 'AIFirst')
    t_strike = tpl('LiveAIEngagementOrder', 'RE_Wave02_TargetUpdate')
    assert arg_values(t_strike)[3] == 'AttackOnly' and arg_values(t_strike)[6] == 'AIOnly'
    for k, unit in enumerate(POOL):
        ev = f'RE_SV_Hunt_{k + 1:02d}'
        g.trigger('RE_SpawnEnemy_kokatu_1st', ev)
        g.execute(t_hunt, ev, {0: 'NoneSelect', 1: unit, 2: 'NoneSelect', 4: 'NoneSelect', 5: 'NoneSelect'})
    for key, n, ship, obj, lane in ally_ships():
        for k, unit in enumerate(BOMBERS):
            ev = f'RE_SV_Strike{key}{ship[-1]}_{k + 1:02d}'
            g.trigger('RE_SpawnEnemy_kokatu_1st', ev)
            g.execute(t_move, ev, {0: unit, 1: obj, 3: 'NoneSelect'})
            g.execute(t_bsearch, ev, {1: unit, 3: 'AIR_AND_GROUND'})
            g.execute(t_strike, ev, {0: 'NoneSelect', 1: unit, 5: ship})


def build_tells(g):
    """The tells' radio (behaviour roadmap P3): a remote event RE_SV_Radio<Suffix> for each TELL_LINES group, playing it
    (Mission 22's LiveRadioPlayExecution, the shuttle countdown's template; no conditions: hard rule 26). Lua's
    CFG.tells names exactly these events (both ways checked here, so the catalog and the event package can't drift)."""
    import re
    t_radio = g.exec_template('LiveRadioPlayExecution', 'CompositeEvent_CountDown_1')
    groups = [l[0] for l in TELL_LINES]
    assert len(set(groups)) == len(groups), 'TELL_LINES: a group twice'
    for grp in groups:
        suffix = grp[len('SV_Radio_'):]
        assert grp.startswith('SV_Radio_') and suffix.isalpha() and suffix.isascii(), f'{grp}: letters only (hard rule 17)'
        assert survival_fname_plain(grp), grp
        ev = tell_event(grp)
        g.trigger('RE_SpawnEnemy_kokatu_1st', ev)                 # a remote event Lua fires (SV_Event)
        g.execute(t_radio, ev, {0: grp})
    built = {tell_event(x) for x in groups}
    used = set(re.findall(r'RE_SV_Radio\w+', runtime_lua()))
    assert used <= built, f'Lua fires radio tells the build has no line for: {sorted(used - built)}'
    assert built <= used, f'TELL_LINES groups no CFG.tells tell names: {sorted(built - used)}'
