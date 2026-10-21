"""survival_events.py : Survival Mode's event graph (EP_SurvivalMode_global), built from Mission 22's own records.

Every trigger / exec here is a deep copy of a stock Mission 22 record of the same node class, with only its names,
unit/flag arguments, delays and conditions changed, so the node classes, argument layouts and TipsHashes are the
game's own. EP_SurvivalMode_global is a copy of EP_Mission022_global, so its import and name tables already hold every
node class and most names these records use. Record format: tools/re/EVENT_NOTES.md.

Milestone 2: rounds are run by Survival's own spawner (Scripts/main.lua + the native runtime, tools/re/SPAWN_SYSTEM.md),
not by events. The probe graph that spawned with LiveReinforcement* (tests 2-10) showed why: the game never spawns a
desc again while its shot-down flight is still on the phase's unit list. The events left here:
  MissionStart        Mission 8's music
  SV_FlightUp_NN      (one per pool flight, "reinforcement appeared", fires for any spawn of it) SV_Alive += 1,
                      SV_Up_NN = 1; 2 s later: air-only enemy search + engage the player (Mission 22's own orders)
  SV_FlightDown_NN    (one per pool flight, destroyed) SV_Alive -= 1, SV_Kills += 1 (for the Lua log), SV_Up_NN = 0
  RE_SV_Chase         every 6 s: teleport the chase dummy onto the player; for each flight that is up call
                      RE_SV_Chase_NN, which moves that flight's area onto the dummy
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
KEEP_AT_START = {CHASE_UNIT: None} if CHASE else {}   # units spawned at mission start (name -> spawn point or None)
# Mission 8's music; it sits in the shared campaign BGM bank (DA_SoundDB_AKB_BGM_Campaign) with Mission 22's.
MUSIC = 'AKE_Bgm_Ms08A_Play'
# SV_Alive / SV_Kills: diagnostics, logged by Scripts/main.lua. SV_Up_NN: 1 while pool flight NN is up (chase).
INT_FLAGS = ['SV_Alive', 'SV_Kills'] + [f'SV_Up_{k + 1:02d}' for k in range(len(POOL))]


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

    def execute(self, template, event, arg_changes=None, delay=None, conds=()):
        e = copy.deepcopy(template)
        setf(e, 'ConnectionEventName', fname(event)); self.names.add(fname(event)[1])
        for i, v in (arg_changes or {}).items(): set_arg(e, i, v)
        if delay: setf(e, 'Delay', ('raw', 'Float', struct.pack('<f', delay)))
        else: clearf(e, 'Delay')
        setf(e, 'ConditionalStatementTables', ('arr', list(conds)))
        eid = f'SV_Exec_{self.next_exec}'
        setf(e, 'ExecutionID', fname(eid)); self.names.add(fname(eid)[1])
        setf(e, 'ExecutionNumber', ('raw', 'Int', struct.pack('<i', self.next_exec))); self.next_exec += 1
        self.ex.append(e)
        return e


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

    def flag(event, name, op, value, **kw):
        g.flags.add(name)
        return g.execute(t_flag, event, {0: name, 1: op, 2: value}, **kw)

    def call(event, target, **kw):
        return g.execute(t_call, event, {0: target}, **kw)

    g.trigger('MissionStart', 'MissionStart')
    g.execute(t_bgm, 'MissionStart', {0: MUSIC})
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
