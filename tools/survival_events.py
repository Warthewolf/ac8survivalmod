"""survival_events.py : Survival Mode's event graph (EP_SurvivalMode_global), built from Mission 22's own records.

Every trigger / exec here is a deep copy of a stock Mission 22 record of the same node class, with only its names,
unit/flag arguments, delays and conditions changed, so the node classes, argument layouts and TipsHashes are the
game's own. EP_SurvivalMode_global is a copy of EP_Mission022_global, so its import and name tables already hold every
node class and most names these records use. Record format: tools/re/EVENT_NOTES.md.

Milestone 2: rounds are run by Survival's own spawner (Scripts/main.lua + the native runtime, tools/re/SPAWN_SYSTEM.md),
not by events. The probe graph that spawned with LiveReinforcement* (tests 2-10) showed why: the game never spawns a
desc again while its shot-down flight is still on the phase's unit list. The events left here:
  MissionStart        (no music: MUSIC is None) the mission clock paused and hidden (Mission 22's own pair, run when its
                      battle ends): Survival is endless, so no 60-minute countdown and no time-up
  SV_FlightUp_NN      (one per pool flight, "reinforcement appeared", fires for any spawn of it) SV_Alive += 1,
                      SV_Up_NN = 1; 2 s later: air-only enemy search + engage the player (Mission 22's own orders)
  SV_FlightDown_NN    (one per pool flight, destroyed) SV_Alive -= 1, SV_Kills += 1 (for the Lua log), SV_Up_NN = 0
  RE_SV_Chase         every 6 s: teleport the chase dummy onto the player; for each flight that is up call
                      RE_SV_Chase_NN, which moves that flight's area onto the dummy
  SV_BomberUp_NN      (one per bomber flight, BOMBERS) Mission 22's Comona Airport strike: unit area onto the airport,
                      ground-only search, engagement order on the airfield unit (AIRFIELD_UNIT)
  SV_AirfieldHit_N    (one per airfield dummy) a weapon an enemy fired at it ended there: SV_AirHits += 1 and
                      Mission 22's explosion VFX on that dummy; Scripts/main.lua turns SV_AirHits into airfield health
  RE_SV_AirfieldClose / RE_SV_AirfieldOpen   landing off / on (fired by Scripts/main.lua with SV_Event)
  RE_SV_BombRun_NN    (one per bomber flight) both aircraft drop BOMB_COUNT bombs (weapon slot 4); Scripts/main.lua
                      fires it when a Tu-95 / Tu-160 of that flight is over the airfield
"""
import copy, os, struct, sys, zlib
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, 'checks'))
import ep_dump

# The flights Survival's spawner draws from: Mission 22's 24 "kokatu" reinforcement flights, 2 aircraft each.
# Scripts/main.lua has the same list (CFG.pool); a flight outside it would spawn without its orders.
POOL = [f'ERA_Unit_{n:02d}_Dep_Air{k}' for n in range(1, 9) for k in range(3)]
# A flight only works inside its unit area (Mission 22's: 6000 m, 0.5 patrol ratio): it loitered near its spawn until
# the player came within ~3 km, and an 80 km area (probe test 9) didn't make it come either. Chase (user request,
# 2026-10-21: "enemies didn't go after the player until they were close" without it): every CHASE_S seconds Mission 22's
# dummy Unit_dummyN0 is teleported onto the player and every flight that is up gets its area moved onto it
# (LiveUnitMoveActor, as Mission 22 moves its waves; the player dummy is Missions 006/023's pattern). Probe tests 7-8
# blamed the moves for flights not respawning; the real cause was the phase's unit list (re/SPAWN_SYSTEM.md).
# Chase OFF (user, 2026-10-22): flights seemed to break off fights to fly to the moved area. Instead every flight gets
# a 40 km area and (Scripts/main.lua CFG.search) a 40 km AI search radius that doesn't lose the player in cloud; the
# 80 km area alone (test 9) failed because the stock search radius was only 6 km.
CHASE = False
CHASE_UNIT = 'Unit_dummyN0'
CHASE_OBJECT = 'A_Obj_01_dummyN0'
CHASE_S = 6.0
AREA_RADIUS_M = None if CHASE else 40000.0   # pool flights' RadiusInMeter (None: Mission 22's own 6000)
# Milestone 3 (user, 2026-10-22: bombers that only attack the airfield). Mission 22's own Comona Airport strike
# (tools/re/AIRFIELD_SUPPLY.md 2b): its Su-34s get the airport unit as their engagement target with a ground-only search
# and fire at its invincible dummies; a MissedWeapon trigger on each dummy counts what reaches it. The target is
# AB_Unit_01_Ground2 (the 4 dummies alone, Mission 22's landing-time target), spawned at mission start. The bomber
# flights are Mission 22's strike desc and its three idle enemy fighter descs, cut to BOMBER_FLIGHT aircraft by
# build_survival.py; Scripts/main.lua (CFG.airfield) picks their aircraft: Su-34, F-15E, Tu-95, Tu-160.
AIRFIELD_UNIT = 'AB_Unit_01_Ground2'
AIRFIELD_DUMMIES = [f'AB_Obj_01_Dummy{k}' for k in range(4, 8)]      # Mission 22's MissedWeapon_AreaB_0..3 dummies' twins
AIRFIELD_MARK = 'AreaB_MarkActor0'
BOMBERS = ['ERB_Unit_01_Air2', 'EA_Unit_01_Air0', 'EA_Unit_01_Air1', 'EA_Unit_01_Air2']
BOMBER_FLIGHT = 2
# Heavy bombers never bomb on their own: in every stock mission (M003/004/009/013/028) a Tu-95 / Tu-160 drop is a
# scripted LiveFireOneShotWeapon on weapon slot 4 (WN_WEAPON_4: PlaneBomb002, unguided, no AI capture distance), and
# the damage is counted by script too (build/research/bombers, 2026-10-22). Survival does the same: Lua watches the
# heavies and fires the flight's bomb run over the airfield, then applies the damage itself.
BOMB_COUNT = 6
BOMB_GAP_S = 0.4
# Behaviour rows (test of 2026-10-22): the game builds every AI aircraft's behaviour trees when the level loads, one
# set per world-data AI object desc, from the NPC row the desc names at that moment (127 aircraft x 15 slots = the
# 1915 behaviours the census counted before anything spawned; each stock script was built once, ours never).
# SV_SetAircraft at spawn changes the airframe and the AI module (search radius), not the behaviour, so every flight
# Survival flies gets its behaviour row here, in the world data (tools/build_survival.py):
POOL_BEHAVIOUR_ROW = 'f16c_common_sv'      # its DT_NPC row is made by Scripts/main.lua at the main menu, with the
                                           # behaviour set CFG.search.luaset (NLID_0400_CP: keeps pursuing)
PROBE_UNITS = {'Pkg': 'ERA_Unit_08_Dep_Air2', 'Rt': 'ERA_Unit_08_Dep_Air1'}   # main.lua CFG.probe.units
PROBE_ROWS = {'Pkg': 'sv_probe_pkg', 'Rt': 'sv_probe_rt'}                     # build_survival.py NPC_EXTRA
HEAVY_BOMBERS = ['EA_Unit_01_Air1', 'EA_Unit_01_Air2']   # main.lua CFG.airfield.bombers.heavy_units
STRIKE_BEHAVIOUR_ROW = 'su34_common'       # Mission 22's strike Su-34s (0021_CP)
HEAVY_BEHAVIOUR_ROW = 't160_common'        # Mission 4's Tu-160 (NLID_1000: large aircraft, no dogfighting)


def behaviour_row(unit):
    """The NPC row a flight's AI objects name in the world data (its behaviour), or None to leave Mission 22's."""
    for v, u in PROBE_UNITS.items():
        if u == unit: return PROBE_ROWS[v]
    if unit in BOMBERS: return HEAVY_BEHAVIOUR_ROW if unit in HEAVY_BOMBERS else STRIKE_BEHAVIOUR_ROW
    if unit in POOL: return POOL_BEHAVIOUR_ROW
    return None
KEEP_AT_START = {AIRFIELD_UNIT: None}                 # units spawned at mission start (name -> spawn point or None)
if CHASE: KEEP_AT_START[CHASE_UNIT] = None
# Music at mission start: none (user, 2026-10-22: it played over the pause menu's Music Player; the player picks the
# music there). Was Mission 8's 'AKE_Bgm_Ms08A_Play' (the shared campaign BGM bank, DA_SoundDB_AKB_BGM_Campaign).
MUSIC = None
# SV_Alive / SV_Kills: diagnostics, logged by Scripts/main.lua. SV_Up_NN: 1 while pool flight NN is up (chase).
INT_FLAGS = ['SV_Alive', 'SV_Kills', 'SV_AirHits'] + [f'SV_Up_{k + 1:02d}' for k in range(len(POOL))]


# ---------------------------------------------------------------- record helpers (uprop struct tuples)
def fields(rec):
    return {p[1]: p for p in rec[2]}


def setf(rec, name, value):
    """Set field `name` (must exist in the record) to a non-default value."""
    for k, p in enumerate(rec[2]):
        if p[1] == name:
            rec[2][k] = (p[0], name, False, value)
            return
    raise KeyError(name)


def clearf(rec, name):
    for k, p in enumerate(rec[2]):
        if p[1] == name:
            rec[2][k] = (p[0], name, True, None)
            return
    raise KeyError(name)


def args(rec):
    return fields(rec)['ArgsInfo'][3][1]


def set_arg(rec, i, value):
    a = args(rec)[i]
    a[2][:] = [(q[0], q[1], q[2], ('str', str(value)) if q[1] == 'Value' else q[3]) for q in a[2]]


def arg_values(rec):
    return [fields(a)['Value'][3][1] for a in args(rec)]


def fname(s):
    """FName value: 'Name_3' is stored as ('Name', 4) like the engine does; plain names as number 0."""
    base, _, tail = s.rpartition('_')
    if base and tail.isdigit() and not (len(tail) > 1 and tail[0] == '0'):
        return ('name', base, int(tail) + 1)
    return ('name', s, 0)


class Graph:
    def __init__(self, stock_ep):
        self.z, self.i, self.props, self.T, self.E, self.offs = ep_dump.load(stock_ep)
        self.trig, self.ex = [], []
        self.names = set()
        self.used_hashes = {struct.unpack('<i', fields(t)['EventHash'][3][2])[0] for t in self.T}
        self.next_shared = 900000
        self.next_exec = 1
        self.flags = set()      # int flags the records read or write (must all be in INT_FLAGS)

    # templates --------------------------------------------------------
    def exec_template(self, cls, event=None, pred=None):
        for e in self.E:
            f = fields(e)
            if ep_dump.show(f['ExecutionClass'][3], self.z) != cls: continue
            if event and ep_dump.show(f['ConnectionEventName'][3], self.z) != event: continue
            if pred and not pred(arg_values(e), e): continue
            return copy.deepcopy(e)
        raise LookupError((cls, event))

    def trig_template(self, event):
        for t in self.T:
            if ep_dump.show(fields(t)['EventName'][3], self.z) == event:
                return copy.deepcopy(t)
        raise LookupError(event)

    def cond_template(self):
        for e in self.E:
            for c in fields(e)['ConditionalStatementTables'][3][1]:
                if ep_dump.show(fields(c)['StatementClass'][3], self.z) == 'LiveInequality_FlagIntStatement':
                    return copy.deepcopy(c)
        raise LookupError('LiveInequality_FlagIntStatement')

    # builders ---------------------------------------------------------
    def _hash(self, name):
        h = zlib.crc32(b'AC8SurvivalMode:' + name.encode())
        h = h - (1 << 32) if h >= 1 << 31 else h
        while h in self.used_hashes: h += 1
        self.used_hashes.add(h)
        return h

    def trigger(self, template_event, name, life=None, arg_changes=None):
        t = self.trig_template(template_event)
        setf(t, 'EventName', fname(name)); self.names.add(fname(name)[1])
        setf(t, 'EventHash', ('raw', 'Int', struct.pack('<i', self._hash(name))))
        if life: setf(t, 'LifeCount', ('raw', 'Int', struct.pack('<i', life)))
        else: clearf(t, 'LifeCount')
        for i, v in (arg_changes or {}).items(): set_arg(t, i, v)
        self.trig.append(t)
        return t

    def cond(self, flag, op, value):
        c = self.cond_template()
        setf(c, 'SharedID', ('raw', 'Int', struct.pack('<i', self.next_shared))); self.next_shared += 1
        for i, v in enumerate((flag, op, value)): set_arg(c, i, v)
        self.flags.add(flag)
        return c

    def execute(self, template, event, arg_changes=None, delay=None, conds=(), loop=None):
        e = copy.deepcopy(template)
        setf(e, 'ConnectionEventName', fname(event)); self.names.add(fname(event)[1])
        for i, v in (arg_changes or {}).items(): set_arg(e, i, v)
        if delay: setf(e, 'Delay', ('raw', 'Float', struct.pack('<f', delay)))
        else: clearf(e, 'Delay')
        if loop: setf(e, 'LoopCount', ('raw', 'Int', struct.pack('<i', loop)))
        setf(e, 'ConditionalStatementTables', ('arr', list(conds)))
        eid = f'SV_Exec_{self.next_exec}'
        setf(e, 'ExecutionID', fname(eid)); self.names.add(fname(eid)[1])
        setf(e, 'ExecutionNumber', ('raw', 'Int', struct.pack('<i', self.next_exec))); self.next_exec += 1
        self.ex.append(e)
        return e


def unit_objects(stock_ep, units):
    """{unit: [AI object names]} from the stock world data next to the EP (as event args write them: 'X_0')."""
    import uprop
    from zenpkg import ZenPkg
    wd = os.path.join(os.path.dirname(stock_ep), os.path.basename(stock_ep).replace('EP_', 'WD_'))
    z = ZenPkg(wd)
    i = max(range(len(z.payloads)), key=lambda k: len(z.payloads[k]))
    v, _ = uprop.read_struct(uprop.Ctx(bytes(z.payloads[i]), z.names), 4, 'LiveWorldData')
    out = {}
    for u in [p for p in v[2] if p[1] == 'UnitDescList'][0][3][1]:
        f = {p[1]: p[3] for p in u[2]}
        if f['Name'][1] not in units: continue
        names = []
        for ob in f['AIObjectDescList'][1]:
            n = {p[1]: p[3] for p in ob[2]}['Name']
            names.append(n[1] if n[2] == 0 else f'{n[1]}_{n[2] - 1}')
        out[f['Name'][1]] = names
    return out


def build_events(stock_ep):
    g = Graph(stock_ep)
    # templates, all from Mission 22
    t_flag = g.exec_template('LiveFlagOperation_IntExecution', pred=lambda a, e: a[1] == 'Set')
    t_bgm = g.exec_template('LivePlayBGMExecution', 'MissionStart')
    t_search = g.exec_template('LiveAIChangeEnemySearchType', '01_E_AreaA_ReinforcementAppearance_0')
    t_engage = g.exec_template('LiveAIEngagementOrder', '01_E_Wave03_ReinforcementAppearance_0')
    t_call = g.exec_template('LiveCallRemoteEventExecution', 'MissionStart')
    t_tp_unit = g.exec_template('LiveActorTeleportExecution', '01_Wave05_YesEvent02', lambda a, e: a[8] == 'Unit_dummyN0')
    t_tp_obj = g.exec_template('LiveActorTeleportExecution', '01_Wave05_YesEvent02', lambda a, e: a[1] == 'A_Obj_01_dummyN0')
    t_move = g.exec_template('LiveUnitMoveActor', '01_E_AreaA_ReinforcementAppearance_0')
    # Mission 22's airport strike (records 1686, 1694, 2037) and its landing switch (2099)
    t_bmove = g.exec_template('LiveUnitMoveActor', 'Default_CompositeEvent_19')       # unit area onto AreaB_MarkActor0
    t_bsearch = g.exec_template('LiveAIChangeEnemySearchType', 'Default_CompositeEvent_98')   # GROUND_ONLY
    t_bengage = g.exec_template('LiveAIEngagementOrder', 'Default_CompositeEvent_98')         # Normal, target unit, AIOnly
    t_landing = g.exec_template('LiveSetTakeoffAndLandingEventExecution', 'Default_Campaign_ExterminationBattleSuccess')
    t_fire = g.exec_template('LiveFireOneShotWeapon', '01_A_Wave03_ReinforcementAppearance_0')   # WN_WEAPON_4, no target
    t_pause = g.exec_template('LiveSetPauseTimerExecution', 'Default_CompositeEvent_106')   # pause: true
    t_hide = g.exec_template('LiveHideRemainingTimerExecution', 'Default_CompositeEvent_106')

    def flag(event, name, op, value, **kw):
        g.flags.add(name)
        return g.execute(t_flag, event, {0: name, 1: op, 2: value}, **kw)

    def call(event, target, **kw):
        return g.execute(t_call, event, {0: target}, **kw)

    g.trigger('MissionStart', 'MissionStart')
    if MUSIC: g.execute(t_bgm, 'MissionStart', {0: MUSIC})
    g.execute(t_pause, 'MissionStart')
    g.execute(t_hide, 'MissionStart')
    g.execute(t_hide, 'MissionStart', delay=3.0)   # again once the HUD is up (Mission 8 hides 3 s late)
    if CHASE:
        call('MissionStart', 'RE_SV_Chase', delay=3.0)
        g.trigger('RE_SpawnEnemy_kokatu_1st', 'RE_SV_Chase')
        g.execute(t_tp_unit, 'RE_SV_Chase', {5: 0, 8: CHASE_UNIT})          # onto the player, no offset
        g.execute(t_tp_obj, 'RE_SV_Chase', {1: CHASE_OBJECT, 5: 0})
        for k, unit in enumerate(POOL):
            ev = f'RE_SV_Chase_{k + 1:02d}'
            g.trigger('RE_SpawnEnemy_kokatu_1st', ev)
            call('RE_SV_Chase', ev, delay=0.5, conds=[g.cond(f'SV_Up_{k + 1:02d}', 'Geq', 1)])
            g.execute(t_move, ev, {0: unit, 1: CHASE_OBJECT, 3: 'NoneSelect'})
        call('RE_SV_Chase', 'RE_SV_Chase', delay=CHASE_S)
    for k, unit in enumerate(POOL):
        up, down = f'SV_FlightUp_{k + 1:02d}', f'SV_FlightDown_{k + 1:02d}'
        g.trigger('01_E_AreaA_ReinforcementAppearance_0', up, arg_changes={0: unit})
        flag(up, 'SV_Alive', 'Add', 1)
        flag(up, f'SV_Up_{k + 1:02d}', 'Set', 1)
        g.execute(t_search, up, {1: unit}, delay=2.0)
        g.execute(t_engage, up, {1: unit}, delay=2.0)
        g.trigger('UnitDamage_Ship_Destroy_0', down, arg_changes={0: unit})
        flag(down, 'SV_Alive', 'Sub', 1)
        flag(down, 'SV_Kills', 'Add', 1)
        flag(down, f'SV_Up_{k + 1:02d}', 'Set', 0)
    assert arg_values(t_bmove)[3] == AIRFIELD_MARK and arg_values(t_bsearch)[3] == 'GROUND_ONLY'
    assert arg_values(t_bengage)[3] == 'Normal' and arg_values(t_bengage)[5] == 'AB_Unit_01_Ground0'
    for k, unit in enumerate(BOMBERS):
        up = f'SV_BomberUp_{k + 1:02d}'
        g.trigger('01_E_AreaA_ReinforcementAppearance_0', up, arg_changes={0: unit})
        g.execute(t_bmove, up, {0: unit}, delay=1.0)
        g.execute(t_bsearch, up, {1: unit}, delay=2.0)
        g.execute(t_bengage, up, {1: unit, 5: AIRFIELD_UNIT}, delay=2.0)
    for k, dummy in enumerate(AIRFIELD_DUMMIES):
        hit = f'SV_AirfieldHit_{k + 1}'
        t = g.trigger(f'MissedWeapon_AreaB_{k}', hit, arg_changes={4: dummy})      # LifeCount cleared: every hit
        assert arg_values(t)[0] == 'EnemyNPC'
        flag(hit, 'SV_AirHits', 'Add', 1)
        g.execute(g.exec_template('LiveSetActiveVFXExecution', f'MissedWeapon_AreaB_{k}'), hit)
    assert arg_values(t_fire)[0] == 'WN_WEAPON_4' and arg_values(t_fire)[2] == arg_values(t_fire)[3] == 'NoneSelect'
    objs = unit_objects(stock_ep, BOMBERS)
    for k, unit in enumerate(BOMBERS):
        run = f'RE_SV_BombRun_{k + 1:02d}'
        g.trigger('RE_Wave2_AreaB_PathSet', run)
        for obj in objs[unit][:BOMBER_FLIGHT]:      # build_survival.py keeps these first BOMBER_FLIGHT aircraft
            g.execute(t_fire, run, {1: obj}, delay=BOMB_GAP_S, loop=BOMB_COUNT)
    assert arg_values(t_landing)[0] == 'false'
    for ev, on in (('RE_SV_AirfieldClose', 'false'), ('RE_SV_AirfieldOpen', 'true')):
        g.trigger('RE_Wave2_AreaB_PathSet', ev)                                    # a remote-event trigger
        g.execute(t_landing, ev, {0: on})
    return g


def write_records(g, z, prefix_props_bytes):
    """Payload for z (the renamed EP copy): properties + u32 0 + triggers + execs."""
    import uprop
    for n in sorted(g.names): z.nb.add(n)       # sorted: the same build twice gives the same bytes
    w = uprop.W(z.names)
    out = bytearray(prefix_props_bytes) + b'\0\0\0\0' + struct.pack('<I', len(g.trig))
    for t in g.trig: out += uprop.write_struct(w, t)
    out += struct.pack('<I', len(g.ex))
    for e in g.ex: out += uprop.write_struct(w, e)
    return bytes(out)
