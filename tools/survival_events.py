"""survival_events.py : Survival Mode's event graph (EP_SurvivalMode_global), built from Mission 22's own records.

Every trigger / exec here is a deep copy of a stock Mission 22 record of the same node class, with only its names,
unit/flag arguments, delays and conditions changed, so the node classes, argument layouts and TipsHashes are the
game's own. EP_SurvivalMode_global is a copy of EP_Mission022_global, so its import and name tables already hold every
node class and most names these records use. Record format: tools/re/EVENT_NOTES.md.

Rounds are run by Survival's own spawner (Scripts/main.lua + the native runtime, tools/re/SPAWN_SYSTEM.md), not
by events: the game never spawns a desc again while its shot-down flight is still on the phase's unit list. The events:
  MissionStart        the mission clock paused and hidden (Mission 22's own pair): Survival is endless (no music: the
                      pause menu's Music Player is the only music)
  SV_FlightUp_NN      (one per pool flight, "reinforcement appeared", fires for any spawn of it) SV_Alive += 1,
                      SV_Up_NN = 1; 2 s later: air-only enemy search + engage the player only (PlayerOnlyNoLimit)
  RE_SV_FlightOrders_NN  the same, fired by Scripts/main.lua for a flight whose appearance didn't fire (landing menu)
  SV_FlightDown_NN    (one per pool flight, destroyed) SV_Alive -= 1, SV_Kills += 1 (for the Lua log), SV_Up_NN = 0
  SV_BomberUp_NN      (one per bomber flight, BOMBERS) Mission 22's Comona Airport strike: unit area onto the airport,
                      ground-only search, engagement order on the airfield unit (AIRFIELD_UNIT); on the shuttle while
                      SV_ShuttleRound is 1
  SV_AirfieldHit_N    (one per airfield dummy) a weapon an enemy fired at it ended there: SV_AirHits += 1 and
                      Mission 22's explosion VFX on that dummy; Scripts/main.lua turns SV_AirHits into airfield health
  RE_SV_AirfieldClose / RE_SV_AirfieldOpen   landing off / on (fired by Scripts/main.lua with SV_Event)
  RE_SV_BombRun_NN    (one per bomber flight) both aircraft drop BOMB_COUNT bombs (weapon slot 4); Scripts/main.lua
                      fires it when a Tu-95 / Tu-160 of that flight is over the airfield
  SV_Shuttle*         Comona Defense (build_shuttle, SHUTTLE_*): countdown, liftoff, hits, loss
"""
import copy, os, struct, sys, zlib
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, 'checks'))
import ep_dump

# The flights Survival's spawner draws from: Mission 22's 24 "kokatu" reinforcement flights, 2 aircraft each.
# Scripts/main.lua has the same list (CFG.pool); a flight outside it would spawn without its orders.
POOL = [f'ERA_Unit_{n:02d}_Dep_Air{k}' for n in range(1, 9) for k in range(3)]
# A flight only works inside its unit area (Mission 22's: 6000 m, 0.5 patrol ratio): it loitered near its spawn until
# the player came within ~3 km. Every pool flight gets a 40 km area and (Scripts/main.lua CFG.search) a 40 km AI search
# radius that doesn't lose the player in cloud, so it comes for the player from anywhere in the zone. (The 2026-10-21
# chase, which moved each flight's area onto the player every 6 s, was turned off on 2026-10-22: flights broke off
# fights to fly to the moved area; it is in git history.)
AREA_RADIUS_M = 40000.0                      # pool flights' RadiusInMeter (None: Mission 22's own 6000)
# Milestone 3 (user, 2026-10-22: bombers that only attack the airfield). Mission 22's own Comona Airport strike
# (tools/re/AIRFIELD_SUPPLY.md 2b): its Su-34s get the airport unit as their engagement target with a ground-only search
# and fire at its invincible dummies; a MissedWeapon trigger on each dummy counts what reaches it. The target is
# AB_Unit_01_Ground2 (the 4 dummies alone, Mission 22's landing-time target), spawned at mission start. The bomber
# flights are Mission 22's strike desc and its four idle enemy fighter descs, sized by BOMBER_SIZES in
# build_survival.py; Scripts/main.lua (CFG.airfield) picks their aircraft: Su-34, F-15E, Tu-95, Tu-160.
AIRFIELD_UNIT = 'AB_Unit_01_Ground2'
AIRFIELD_DUMMIES = [f'AB_Obj_01_Dummy{k}' for k in range(4, 8)]      # Mission 22's MissedWeapon_AreaB_0..3 dummies' twins
AIRFIELD_MARK = 'AreaB_MarkActor0'
# Bomber flights and their sizes (user, 2026-10-22: squadrons of 2, 4 and 6). The order is RE_SV_BombRun_NN's and
# Scripts/main.lua CFG.airfield.bombers.pool's.
BOMBER_SIZES = {'ERB_Unit_01_Air2': 4, 'EA_Unit_01_Air0': 2, 'EA_Unit_01_Air1': 2, 'EA_Unit_01_Air2': 4,
                'EB_Unit_01_Air0': 6}
BOMBERS = list(BOMBER_SIZES)
# Heavy bombers never bomb on their own: in every stock mission (M003/004/009/013/028) a Tu-95 / Tu-160 drop is a
# scripted LiveFireOneShotWeapon on weapon slot 4 (WN_WEAPON_4: PlaneBomb002, unguided, no AI capture distance), and
# the damage is counted by script too (build/research/bombers, 2026-10-22). Survival does the same: Lua watches the
# heavies and fires the flight's bomb run over the airfield, then applies the damage itself.
BOMB_COUNT = 6
BOMB_GAP_S = 0.4
# Special round "Comona Defense" (Milestone 6, tools/re/SPECIAL_ROUNDS.md 12a): Mission 22's shuttle on its pad, a
# countdown, liftoff. Mission 22's pad stays as it is (PAD_UNIT: near-miss dummies, 6 AA guns, 4 SAMs, the control
# tower; user, 2026-10-22: "you can leave the AA guns in", "SAMs too and tower"), spawned at the first special and kept;
# build_survival.py moves the shuttle into a unit of its own (SHUTTLE_UNIT, spawned every special: a unit with
# anything still alive can't be spawned again) and gives it Survival's NPC row, for its name SV_Shuttle_Name.
# Scripts/main.lua spawns both in place (SV_Spawn without a position); the shuttle's appearance runs the chain on
# exec delays: SHUTTLE_COUNTDOWN_S after it appears the shuttle lifts off (main.lua CFG.specials.shuttle.countdown_s
# must be the same), SHUTTLE_REMOVE_S after liftoff it is taken off (LiveDestroyUnitExecution) so the next special can
# spawn it again. Flags for Lua: SV_ShuttleRound 1 while it's on the pad (strike flights go for it instead of the
# airfield), SV_ShuttleLaunched / SV_ShuttleLost, SV_ShuttleHits.
PAD_UNIT = 'AA_Unit_01_Ground0'
SHUTTLE_UNIT = 'SV_Unit_Shuttle'
# the pad's invincible near-miss / tower dummies: a unit of their own, spawned once a run and kept, so the pad's guns,
# SAMs and tower can be removed after each special (user, 2026-10-22: "we have to despawn the allies that spawned with
# the shuttle") and spawned again for the next (a unit with anything still alive can't be)
PAD_DUMMY_UNIT = 'SV_Unit_PadDummies'
PAD_DUMMIES = (['AA_Obj_01_Ground0_Shuttle_Dummy_Point0'] + [f'AA_Obj_01_Ground0_Shuttle_Dummy_{k}' for k in range(5)]
               + [f'AA_Obj_01_Ground0_Tower_Dummy{k}' for k in range(3)])
PAD_REMOVE_LOST_S = 30.0                    # the pad's allies go this long after the shuttle is lost (after liftoff:
                                            # SHUTTLE_REMOVE_S, with the shuttle)
SHUTTLE = 'AA_Obj_01_Ground0_Shuttle_0'
SHUTTLE_NPC_ROW = 'sstb_common_sv'          # DT_SV_NpcMission row (NpcId SHUTTLE_NPC)
SHUTTLE_NPC = 'OP0057_sstb_01_SV'           # DT_SV_NpcRows row, added to DT_NPC by main.lua
SHUTTLE_PATH = '01_Ground0_shuttle_0_Path0'
SHUTTLE_HP = 175.0                          # Mission 22's
SHUTTLE_COUNTDOWN_S = 150.0
SHUTTLE_REMOVE_S = 180.0                    # = Scripts/main.lua CFG.specials.shuttle.remove_s
# Mission 22's countdown radio, as seconds before liftoff (its lines count down in seconds), and its countdown sound
# flags; Mission 22 drives them off its mission timer, Survival off delays from the shuttle's appearance.
SHUTTLE_RADIO = [(SHUTTLE_COUNTDOWN_S - 3, '01_Wave5_Countdown_Start'), (33, '01_Countdown_Shuttle33'),
                 (32, '01_Countdown_Shuttle32'), (31, '01_Countdown_Shuttle31'), (28, '01_Countdown_intermission_1st'),
                 (23, '01_Countdown_Shuttle23'), (22, '01_Countdown_Shuttle22'), (21, '01_Countdown_Shuttle21'),
                 (20, '01_Countdown_Shuttle20'), (19, '01_Countdown_Shuttle19'), (15, '01_Countdown_intermission_2nd'),
                 (11, '01_Countdown_Ignistion'), (10, '01_Countdown_mainEngine'), (8, '01_Countdown_Shuttle8'),
                 (7, '01_Countdown_Shuttle7'), (2, '01_Countdown_Shuttle2and1')]
SHUTTLE_SOUND_FLAGS = [(33, 'AKE_FLAG_Ms22_ARMS_SKY_OP0057_sstb_Countdown_33sec_Set'),
                       (23, 'AKE_FLAG_Ms22_ARMS_SKY_OP0057_sstb_Countdown_23sec_Set'),
                       (8, 'AKE_FLAG_Ms22_ARMS_SKY_OP0057_sstb_Countdown_08sec_Set'),
                       (2, 'AKE_FLAG_Ms22_ARMS_SKY_OP0057_sstb_Countdown_02sec_Set')]
SHUTTLE_SOUND = 'AKE_Ms22_ARMS_SKY_OP0057_sstb_Body_'
# Special round "The Anomaly" (tools/re/SPECIAL_ROUNDS.md 13; user, 2026-10-22: the ace flies an F-4 and is named
# MINDRIPPER; its own HUD warning; the mission-update beep when its round starts; the shuttle's zoom-in camera on it).
# build_survival.py copies pool flight ANOMALY_SOURCE (Survival's fighter behaviour, 40 km area) into MINDRIPPER's own
# one-aircraft unit and a guard unit; Scripts/main.lua spawns both, gives MINDRIPPER its NPC row and flies the field
# (inside 3 km the player's pitch and roll invert: dlls/main.dll SV_Invert). The records here are the stock
# presentation: Mission 22's MISSION UPDATE message (its beep) and focus camera, and Mission 15's forced WARNING
# message, radar noise and glasses effect (Graph.foreign_template: classes Mission 22's package doesn't import).
ANOMALY_SOURCE = 'ERA_Unit_01_Dep_Air1'     # a 4-ship of the pool
ANOMALY_UNIT = 'SV_Unit_Anomaly'
ANOMALY_GUARD_UNIT = 'SV_Unit_AnomalyGuards'
ANOMALY_GUARDS = 4
ANOMALY_GUARD_RADIUS_M = 2000.0             # its guards' unit area, on it: they circle inside it
# The game's throttle on how hard enemies may press the player (Mission 22 sets it per wave): how many missiles may be
# aimed at the player at once, how many enemies may attack at once, and its attack cooldowns. Survival never set it, so
# it ran on the game's defaults; ATTACK_BASE (Mission 22's wave 3) from the mission start and after the Anomaly, and
# while MINDRIPPER is up ANOMALY_ATTACK (user, 2026-10-22: "mindripper still wasn't aggressive enough").
ATTACK_BASE = {'missiles': 4, 'attackers': 6, 'cooldown': (4.0, 8.0, 15.0, 20.0)}
ANOMALY_ATTACK = {'missiles': 8, 'attackers': 10, 'cooldown': (0.5, 1.0, 3.0, 5.0)}
ANOMALY_OBJ = None                          # MINDRIPPER's AI object name, set by build_survival.py copy_unit
# The arrival (user, 2026-10-22: "the zoom in camera appears, then the portal, then MINDRIPPER"): it spawns hidden
# (Scripts/main.lua CFG.specials.anomaly.portal) and the focus camera swings onto it at once; Lua opens the portal on it
# and shows it ~3 s in, so the camera holds on through the burst.
ANOMALY_CAMERA_S = 9.0                      # (Mission 22's shuttle camera: 9 s)
# Its camera settings (BP_InGameCameraParameter names): RE_SV_AnomalyCam_<n> focuses on it with the nth, then lets go;
# Scripts/main.lua fires the one CFG.specials.anomaly.camera names (user, 2026-10-22: ms22-01, the shuttle's, was
# "far too zoomed in"; the game zooms harder the farther the target is). Keep in step with main.lua ANOMALY_CAMERAS.
ANOMALY_CAMERAS = ['LookAt_Event_Camera', 'LookAt_Event_Camera_ms08-01', 'LookAt_Event_Camera_ms04-01',
                   'LookAt_Event_Camera_ms23-01', 'LookAt_Event_Camera_ms22-01']
ANOMALY_HUM = 'AKE_Ms23_ARMS_SKY_OP0049_cleo_ControlUnit_Electricity_'   # + Play / Stop: the Celaeno core's crackle
# its death plays the Celaeno's (Mission 23; user, 2026-10-22: "the celaeno has this special sound when its destroyed,
# add that when MINDRIPPER is destroyed"): the airship's three-part body explosion, on its wreck, seconds after the
# kill. Mission 23's sound events: Scripts/main.lua loads their assets when the level starts (CFG.specials.anomaly).
ANOMALY_DOWN_SOUNDS = [(0.0, 'AKE_Ms23_EXP_SKY_OP0049_cleo_Body_Killed_seq01_Play'),
                       (1.5, 'AKE_Ms23_EXP_SKY_OP0049_cleo_Body_Killed_seq02_Play'),
                       (3.0, 'AKE_Ms23_EXP_SKY_OP0049_cleo_Body_Killed_seq03_Play'),
                       (0.5, 'AKE_Ms23_ARMS_SKY_OP0049_cleo_ControlUnit_Collapse_Play')]
# Airfield defences the shop builds (user, 2026-10-22: "purchase AA guns that sit around the airfield or SAM sites, make
# them expensive"): Mission 22's own airport AA guns and SAM sites (AB_Unit_01_Ground0, never spawned by Survival), each
# moved into a unit of its own by build_survival.py, so Scripts/main.lua (CFG.shop.items.Airfield.defences) spawns them
# one at a time where Mission 22 placed them. Allied, so they fire at enemies by themselves; no event records.
DEFENCE_SOURCE = 'AB_Unit_01_Ground0'
DEFENCES = ([(f'SV_Unit_AAGun_{c}', f'AB_Obj_01_Ground0_AAGUN_{k}') for k, c in enumerate('ABCDE')] +
            [(f'SV_Unit_SAM_{c}', f'AB_Obj_01_Ground0_SAM{k}') for k, c in enumerate('AB')])
# Behaviour rows (test of 2026-10-22): the game builds every AI aircraft's behaviour trees when the level loads, one
# set per world-data AI object desc, from the NPC row the desc names at that moment (127 aircraft x 15 slots = the
# 1915 behaviours the census counted before anything spawned; each stock script was built once, ours never).
# SV_SetAircraft at spawn changes the airframe and the AI module (search radius), not the behaviour, so every flight
# Survival flies gets its behaviour row here, in the world data (tools/build_survival.py):
POOL_BEHAVIOUR_ROW = 'f16c_common_sv'      # its DT_NPC row is made by Scripts/main.lua at the main menu, with the
                                           # behaviour set CFG.search.luaset (NLID_SV_Fighter; hard rule 22)
PROBE_UNITS = {'Pkg': 'ERA_Unit_08_Dep_Air2', 'Rt': 'ERA_Unit_08_Dep_Air1'}   # main.lua CFG.probe.units
PROBE_ROWS = {'Pkg': 'sv_probe_pkg', 'Rt': 'sv_probe_rt'}                     # build_survival.py NPC_EXTRA
HEAVY_BOMBERS = ['EA_Unit_01_Air1', 'EA_Unit_01_Air2']   # main.lua CFG.airfield.bombers.heavy_units
# Their unit area (RadiusInMeter, moved onto the airfield by SV_BomberUp_NN): Tu-95s / Tu-160s circle inside it, and
# with Mission 22's 6 km they circled 8-12 km out and never crossed the runway, so the scripted bomb run never fired
# (test of 2026-10-22: "TU160's didn't do anything when reaching the airfield"). 1.5 km keeps their orbit over it.
HEAVY_AREA_RADIUS_M = 1500.0
STRIKE_BEHAVIOUR_ROW = 'su34_common'       # Mission 22's strike Su-34s (0021_CP)
HEAVY_BEHAVIOUR_ROW = 't160_common'        # Mission 4's Tu-160 (NLID_1000: large aircraft, no dogfighting)


def flight_size(unit):
    """Aircraft in a flight Survival flies (build_survival.py adds or removes AI objects), or None to leave it.
    Fighter pool: ERA_Unit_NN_Dep_Air0 2, _Air1 4, _Air2 6 (Scripts/main.lua flightSize, same rule)."""
    if unit in BOMBER_SIZES: return BOMBER_SIZES[unit]
    if unit in POOL: return {'0': 2, '1': 4, '2': 6}[unit[-1]]
    return None


def behaviour_row(unit):
    """The NPC row a flight's AI objects name in the world data (its behaviour), or None to leave Mission 22's."""
    for v, u in PROBE_UNITS.items():
        if u == unit: return PROBE_ROWS[v]
    if unit in BOMBERS: return HEAVY_BEHAVIOUR_ROW if unit in HEAVY_BOMBERS else STRIKE_BEHAVIOUR_ROW
    if unit in POOL: return POOL_BEHAVIOUR_ROW
    return None
KEEP_AT_START = {AIRFIELD_UNIT: None}                 # units spawned at mission start (name -> spawn point or None)
# SV_Alive / SV_Kills: diagnostics, logged by Scripts/main.lua. SV_Up_NN: 1 while pool flight NN is up (its orders
# came; main.lua's ordersTick checks it). SV_Shuttle*: Comona Defense (build_shuttle).
INT_FLAGS = (['SV_Alive', 'SV_Kills', 'SV_AirHits'] + [f'SV_Up_{k + 1:02d}' for k in range(len(POOL))]
             + ['SV_ShuttleRound', 'SV_ShuttleLaunched', 'SV_ShuttleLost', 'SV_ShuttleHits', 'SV_ShuttleNearSaid']
             + [f'SV_ShuttleDmg{c}' for c in 'ABC'] + ['SV_AnomalyUp'])


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
        self.foreign = {}       # other stock EPs read for templates
        self.added_imports = [] # script imports (exec classes) appended to the EP's import map, in order

    # templates --------------------------------------------------------
    def exec_template(self, cls, event=None, pred=None):
        for e in self.E:
            f = fields(e)
            if ep_dump.show(f['ExecutionClass'][3], self.z) != cls: continue
            if event and ep_dump.show(f['ConnectionEventName'][3], self.z) != event: continue
            if pred and not pred(arg_values(e), e): continue
            return copy.deepcopy(e)
        raise LookupError((cls, event))

    def foreign_template(self, stock_ep, cls, event=None, pred=None):
        """An exec record of another stock EP, for a class Mission 22's package doesn't import (Mission 15's HUD
        warning, radar noise, glasses). Its class is a script import: it's appended to this EP's import map (build_ep
        appends the same to the package it writes) and the record points at it."""
        if stock_ep not in self.foreign: self.foreign[stock_ep] = ep_dump.load(stock_ep)
        fz, _, _, _, fE, _ = self.foreign[stock_ep]
        for e in fE:
            f = fields(e)
            if ep_dump.show(f['ExecutionClass'][3], fz) != cls: continue
            if event and ep_dump.show(f['ConnectionEventName'][3], fz) != event: continue
            if pred and not pred(arg_values(e), e): continue
            e = copy.deepcopy(e)
            ref = f['ExecutionClass'][3]
            assert ref[0] == 'obj' and ref[1] < 0, ref
            x = fz.imports[-ref[1] - 1]
            assert x >> 62 == 1, (cls, hex(x))                       # a script import: no package to add
            if x not in self.z.imports:
                self.z.imports.append(x)
                self.added_imports.append(x)
            setf(e, 'ExecutionClass', ('obj', -(self.z.imports.index(x) + 1)))
            setf(e, 'ConditionalStatementTables', ('arr', []))
            return e
        raise LookupError((stock_ep, cls, event))

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
    t_search = g.exec_template('LiveAIChangeEnemySearchType', '01_E_AreaA_ReinforcementAppearance_0')
    t_engage = g.exec_template('LiveAIEngagementOrder', '01_E_Wave03_ReinforcementAppearance_0')
    # Mission 22's order says PlayerFirst, which let fighters pick the airfield's target points once those existed (AI
    # watch, 2026-10-22: an F-15E pursued BP_GR000_dummy at the runway). PlayerOnlyNoLimit, as Mission 24 orders its
    # pursuers (RE_SilverProtect602_0): the player only, at any range.
    assert arg_values(t_engage)[4] == 'Player' and arg_values(t_engage)[6] == 'PlayerFirst'
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

    g.trigger('MissionStart', 'MissionStart')
    g.execute(t_pause, 'MissionStart')
    g.execute(t_hide, 'MissionStart')
    g.execute(t_hide, 'MissionStart', delay=3.0)   # again once the HUD is up (Mission 8 hides 3 s late)
    # RE_SV_FlightOrders_NN gives a flight the same orders as its appearance: a flight that appears while the player
    # is in the landing menu never gets its appearance trigger (test of 2026-10-22: two F-16 flights spawned during a
    # rearm kept Mission 22's PlayerFirst and attacked the airfield), so Scripts/main.lua fires it for an unflagged flight.
    for k, unit in enumerate(POOL):
        up, down = f'SV_FlightUp_{k + 1:02d}', f'SV_FlightDown_{k + 1:02d}'
        orders = f'RE_SV_FlightOrders_{k + 1:02d}'
        g.trigger('01_E_AreaA_ReinforcementAppearance_0', up, arg_changes={0: unit})
        g.trigger('RE_SpawnEnemy_kokatu_1st', orders)                  # a remote-event trigger (the 2026-10-21 chase's)
        for ev in (up, orders):
            flag(ev, 'SV_Alive', 'Add', 1)
            flag(ev, f'SV_Up_{k + 1:02d}', 'Set', 1)
            g.execute(t_search, ev, {1: unit}, delay=2.0)
            g.execute(t_engage, ev, {1: unit, 6: 'PlayerOnlyNoLimit'}, delay=2.0)
        g.trigger('UnitDamage_Ship_Destroy_0', down, arg_changes={0: unit})
        flag(down, 'SV_Alive', 'Sub', 1)
        flag(down, 'SV_Kills', 'Add', 1)
        flag(down, f'SV_Up_{k + 1:02d}', 'Set', 0)
    assert arg_values(t_bmove)[3] == AIRFIELD_MARK and arg_values(t_bsearch)[3] == 'GROUND_ONLY'
    assert arg_values(t_bengage)[3] == 'Normal' and arg_values(t_bengage)[5] == 'AB_Unit_01_Ground0'
    on_airfield = lambda: [g.cond('SV_ShuttleRound', 'Leq', 0)]
    on_shuttle = lambda: [g.cond('SV_ShuttleRound', 'Geq', 1)]
    for k, unit in enumerate(BOMBERS):
        up = f'SV_BomberUp_{k + 1:02d}'
        g.trigger('01_E_AreaA_ReinforcementAppearance_0', up, arg_changes={0: unit})
        g.execute(t_bmove, up, {0: unit}, delay=1.0, conds=on_airfield())
        g.execute(t_bsearch, up, {1: unit}, delay=2.0)
        g.execute(t_bengage, up, {1: unit, 5: AIRFIELD_UNIT}, delay=2.0, conds=on_airfield())
        # Comona Defense: while the shuttle is on its pad the strike flights go for it (Mission 22's waves' order)
        g.execute(t_move, up, {0: unit, 1: SHUTTLE, 3: 'NoneSelect'}, delay=1.0, conds=on_shuttle())
        g.execute(t_bengage, up, {1: unit, 5: SHUTTLE_UNIT}, delay=2.0, conds=on_shuttle())
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
        for obj in objs[unit][:BOMBER_SIZES[unit]]:   # build_survival.py keeps these first aircraft
            g.execute(t_fire, run, {1: obj}, delay=BOMB_GAP_S, loop=BOMB_COUNT)
    assert arg_values(t_landing)[0] == 'false'
    for ev, on in (('RE_SV_AirfieldClose', 'false'), ('RE_SV_AirfieldOpen', 'true')):
        g.trigger('RE_Wave2_AreaB_PathSet', ev)                                    # a remote-event trigger
        g.execute(t_landing, ev, {0: on})
    build_shuttle(g, flag)
    build_anomaly(g, flag, stock_ep, t_search, t_engage, t_move)
    build_repair(g, stock_ep)
    return g


def build_repair(g, stock_ep):
    """RE_SV_RepairAircraft: the player's aircraft back to full health (LiveRestorePlayerPlaneExecution, Training001's
    node: SetHealth(Max) and the armour pool refilled; tools/re/KILLS_HEALTH_DEATH.md). The airfield shop fires it."""
    tr = os.path.join(os.path.dirname(os.path.dirname(stock_ep)), 'Training001', 'EP_Training001_global.uasset')
    t_restore = g.foreign_template(tr, 'LiveRestorePlayerPlaneExecution')
    g.trigger('RE_SpawnEnemy_kokatu_1st', 'RE_SV_RepairAircraft')
    g.execute(t_restore, 'RE_SV_RepairAircraft')


def build_anomaly(g, flag, stock_ep, t_search, t_engage, t_move):
    """The Anomaly (see ANOMALY_*): MINDRIPPER's appearance, its guards' orders, its death, and the field's effects
    Scripts/main.lua switches with RE_SV_AnomalyFieldOn / RE_SV_AnomalyFieldOff (RE_SV_AnomalyEnd: everything off)."""
    assert ANOMALY_OBJ, 'build_survival.py build_wd_global sets ANOMALY_OBJ first'
    m15 = os.path.join(os.path.dirname(os.path.dirname(stock_ep)), 'Mission015', 'EP_Mission015_global.uasset')
    t_msg = g.exec_template('LiveMessageExecution', 'RE_FinishMessage')                  # {0e MISSION_ACCOMPLISHED}
    t_cam_on = g.exec_template('LiveEventFocusCameraExecution', 'RE_ShuttleFocusCamera', lambda a, e: a[0] == SHUTTLE)
    t_cam_off = g.exec_template('LiveEventFocusCameraExecution', 'RE_ShuttleFocusCamera', lambda a, e: a[0] == 'NoneSelect')
    t_warn_on = g.foreign_template(m15, 'LiveSetForceWarinigMessageExecution', '01_Start_Enemy_Attack')
    t_warn_off = g.foreign_template(m15, 'LiveSetForceWarinigMessageExecution', 'Green_SpeedUp_0')
    t_noise = g.foreign_template(m15, 'LiveStartHUDRaderMapNoiseExecution', 'RadarNoise_01')       # 4 / 3 / 6
    t_noise_hard = g.foreign_template(m15, 'LiveStartHUDRaderMapNoiseExecution', 'RadarNoise_02')  # 5 / 5 / 8
    t_noise_off = g.foreign_template(m15, 'LiveStopHUDRaderMapNoiseExecution', 'NoiseCancel03')
    t_glass_on = g.foreign_template(m15, 'LiveActivateGlassesEffectExecution')
    t_glass_off = g.foreign_template(m15, 'LiveDeactivateGlassesEffectExecution')
    # its health bar on the HUD (Mission 6's LCAC records: tools/re/MINIMAP_MARKERS.md), from the portal's burst on
    m06 = os.path.join(os.path.dirname(os.path.dirname(stock_ep)), 'MIssion006', 'EP_Mission006_global.uasset')
    t_hp = g.foreign_template(m06, 'LiveUnitHealthDisplaySwitch', pred=lambda a, e: a[1] == 'All' and a[2] == 'true')
    t_sound = g.exec_template('LiveSoundGeneralPostEventExecution', 'RE_Shuttle_Launch', lambda a, e: a[0].endswith('LiftOff_Play'))
    t_mm = g.exec_template('LiveSetPlayerMaxAttackerMissiles', '01_Wave03_RemainingTime_0')     # [BOTH_MISSILE, n, false]
    t_cd = g.exec_template('LivePlayerAttackCooldownOverrideExecution', '01_Wave03_RemainingTime_0')   # 4 floats
    t_ma = g.exec_template('LiveChangePlayerMaxAttackersNumExecution', '01_Wave03_RemainingTime_0')    # [n]
    assert arg_values(t_mm)[0] == 'BOTH_MISSILE' and len(arg_values(t_cd)) == 4 and len(arg_values(t_ma)) == 1
    def attack(ev, a, delay=None):
        g.execute(t_mm, ev, {1: a['missiles']}, delay=delay)
        g.execute(t_ma, ev, {0: a['attackers']}, delay=delay)
        g.execute(t_cd, ev, {i: f'{v}' for i, v in enumerate(a['cooldown'])}, delay=delay)
    attack('MissionStart', ATTACK_BASE)
    assert arg_values(t_warn_on) == ['true'] and arg_values(t_warn_off) == ['false'], (arg_values(t_warn_on), arg_values(t_warn_off))
    up, guards, down = 'SV_AnomalyUp', 'SV_AnomalyGuardsUp', 'SV_AnomalyDown'
    g.trigger('01_E_AreaA_ReinforcementAppearance_0', up, arg_changes={0: ANOMALY_UNIT})
    g.trigger('01_E_AreaA_ReinforcementAppearance_0', guards, arg_changes={0: ANOMALY_GUARD_UNIT})
    g.execute(t_search, up, {1: ANOMALY_UNIT}, delay=2.0)                    # MINDRIPPER: the pool's orders
    g.execute(t_engage, up, {1: ANOMALY_UNIT, 6: 'PlayerOnlyNoLimit'}, delay=2.0)
    # Its guards circle it (user, 2026-10-22: "they need to circle MINDRIPPER, currently they leave mindripper alone
    # after they sight the player"): Mission 26's escort pattern, their unit area on it (ANOMALY_GUARD_RADIUS_M,
    # following it: arg 10 true, as Start_WaveI_UAV_Setting keeps the UAVs on the x40a), and PlayerOnly instead of the
    # pool's PlayerOnlyNoLimit, so they attack the player near it and go back to it. Once it's down they hunt the player.
    assert arg_values(t_move)[1] == 'NoneSelect' and arg_values(t_move)[10] == 'false', arg_values(t_move)
    g.execute(t_search, guards, {1: ANOMALY_GUARD_UNIT}, delay=2.0)
    g.execute(t_engage, guards, {1: ANOMALY_GUARD_UNIT, 6: 'PlayerOnly'}, delay=2.0)
    g.execute(t_move, guards, {0: ANOMALY_GUARD_UNIT, 1: ANOMALY_OBJ, 3: 'NoneSelect', 5: f'{ANOMALY_GUARD_RADIUS_M}',
                               10: 'true'}, delay=2.5)
    flag(up, 'SV_AnomalyUp', 'Set', 1)
    attack(up, ANOMALY_ATTACK)
    g.execute(t_hp, up, {0: ANOMALY_UNIT, 1: 'All', 2: 'true'}, delay=3.0)        # (Lua shows it at ~2.8 s)
    g.execute(t_msg, up, {0: 'MISSION_UPDATE'})                               # the stock banner and its beep
    g.execute(t_warn_on, up, delay=1.0)                                       # WARNING until it's down
    g.execute(t_noise, up, delay=1.0)
    assert arg_values(t_cam_on)[4] == 'LookAt_Event_Camera_ms22-01', arg_values(t_cam_on)
    for k, cam in enumerate(ANOMALY_CAMERAS):
        ev = f'RE_SV_AnomalyCam_{chr(65 + k)}'                                  # letters: hard rule 17
        g.trigger('RE_SpawnEnemy_kokatu_1st', ev)
        g.execute(t_cam_on, ev, {0: ANOMALY_OBJ, 4: cam})
        g.execute(t_cam_off, ev, delay=ANOMALY_CAMERA_S)
    g.execute(t_sound, up, {0: ANOMALY_HUM + 'Play', 1: ANOMALY_OBJ}, delay=1.0)   # crackles from the portal on
    for name in ('RE_SV_AnomalyFieldOn', 'RE_SV_AnomalyFieldOff', 'RE_SV_AnomalyEnd'):
        g.trigger('RE_SpawnEnemy_kokatu_1st', name)                           # remote events Lua fires (SV_Event)
    g.execute(t_glass_on, 'RE_SV_AnomalyFieldOn')
    g.execute(t_noise_hard, 'RE_SV_AnomalyFieldOn')
    g.execute(t_glass_off, 'RE_SV_AnomalyFieldOff')
    g.execute(t_noise, 'RE_SV_AnomalyFieldOff')
    g.trigger('UnitDamage_Ship_Destroy_0', down, arg_changes={0: ANOMALY_UNIT})
    g.execute(t_sound, down, {0: ANOMALY_HUM + 'Stop', 1: ANOMALY_OBJ})
    for delay, key in ANOMALY_DOWN_SOUNDS:
        g.execute(t_sound, down, {0: key, 1: ANOMALY_OBJ}, delay=delay)
    for ev in (down, 'RE_SV_AnomalyEnd'):
        attack(ev, ATTACK_BASE)
        g.execute(t_hp, ev, {0: ANOMALY_UNIT, 1: 'All', 2: 'false'})
        g.execute(t_engage, ev, {1: ANOMALY_GUARD_UNIT, 6: 'PlayerOnlyNoLimit'})     # the guards, loose
        g.execute(t_move, ev, {0: ANOMALY_GUARD_UNIT, 5: f'{AREA_RADIUS_M}'})        # (Mission 22's mark, the whole zone)
        flag(ev, 'SV_AnomalyUp', 'Set', 0)
        g.execute(t_warn_off, ev)
        g.execute(t_noise_off, ev)
        g.execute(t_glass_off, ev)


def build_shuttle(g, flag):
    """Comona Defense (see SHUTTLE_*): Mission 22's shuttle records, copied with their exact arguments, on delays
    from the shuttle's appearance instead of Mission 22's mission timer."""
    T = SHUTTLE_COUNTDOWN_S
    tpl = lambda cls, ev, pred=None: g.exec_template(cls, ev, pred)
    t_maxhp = tpl('LiveSetMaxHealthExecution', 'MissionStart')
    t_minhp = tpl('LiveSetMinHealthExecution', 'RE_SetGroundObjMinHP1')
    t_sound = tpl('LiveSoundGeneralPostEventExecution', 'RE_Shuttle_Launch', lambda a, e: a[0].endswith('LiftOff_Play'))
    t_sflag = tpl('LiveSoundGeneralPostEventExecution', 'CompositeEvent_CountDown_1')
    t_radio = tpl('LiveRadioPlayExecution', 'CompositeEvent_CountDown_1')
    t_vfx_on = tpl('LiveSetActiveVFXExecution', 'RE_Shuttle_Boost_On')
    t_vfx_off = tpl('LiveSetActiveVFXExecution', 'RE_Shuttle_Boost_Off')
    t_fire = tpl('LiveAIPathExecution', 'RE_Shuttle_Fire_On')
    t_climb = tpl('LiveAIPathExecution', 'RE_Shuttle_Launch', lambda a, e: a[4] == '4000.0')
    t_climb2 = tpl('LiveAIPathExecution', 'RE_Shuttle_Launch', lambda a, e: a[4] == '5000.0')
    t_cam_on = tpl('LiveEventFocusCameraExecution', 'RE_ShuttleFocusCamera', lambda a, e: a[0] == SHUTTLE)
    t_cam_off = tpl('LiveEventFocusCameraExecution', 'RE_ShuttleFocusCamera', lambda a, e: a[0] == 'NoneSelect')
    t_remove = tpl('LiveDestroyUnitExecution', 'Debug_Destroy_Shuttle')
    for t in (t_fire, t_climb, t_climb2):
        assert arg_values(t)[0] == SHUTTLE and arg_values(t)[2] == SHUTTLE_PATH
    assert arg_values(t_remove)[2] == SHUTTLE and arg_values(t_maxhp)[0] == SHUTTLE
    standing = lambda: [g.cond('SV_ShuttleLost', 'Leq', 0)]          # nothing more once it's been shot down
    up = 'SV_ShuttleUp'
    g.trigger('01_E_AreaA_ReinforcementAppearance_0', up, arg_changes={0: SHUTTLE_UNIT})
    resets = ['SV_ShuttleLost', 'SV_ShuttleLaunched', 'SV_ShuttleHits', 'SV_ShuttleNearSaid'] + [f'SV_ShuttleDmg{c}' for c in 'ABC']
    for name in resets:
        flag(up, name, 'Set', 0)
    flag(up, 'SV_ShuttleRound', 'Set', 1)
    g.execute(t_maxhp, up, {3: f'{SHUTTLE_HP}'})
    g.execute(t_sound, up, {0: SHUTTLE_SOUND + 'Ignition_Stop', 1: SHUTTLE})
    for before, key in SHUTTLE_RADIO:
        g.execute(t_radio, up, {0: key}, delay=T - before, conds=standing())
    for before, key in SHUTTLE_SOUND_FLAGS:
        g.execute(t_sflag, up, {0: key}, delay=T - before, conds=standing())
    g.execute(t_minhp, up, {0: SHUTTLE, 3: '1.0'}, delay=T - 20, conds=standing())   # the last 20 s it can't die
    g.execute(t_vfx_on, up, delay=T - 14, conds=standing())                         # ignition (RE_Shuttle_Boost_On)
    g.execute(t_sound, up, {0: SHUTTLE_SOUND + 'Ignition_Play', 1: SHUTTLE}, delay=T - 14, conds=standing())
    g.execute(t_fire, up, delay=T - 4, conds=standing())                            # on its path, engines lit
    g.execute(t_cam_on, up, delay=T - 2, conds=standing())
    # liftoff (RE_Shuttle_Launch, without Mission 22's wave cleanup)
    g.execute(t_climb, up, delay=T, conds=standing())
    g.execute(t_sound, up, {0: SHUTTLE_SOUND + 'Ignition_Stop', 1: SHUTTLE}, delay=T, conds=standing())
    g.execute(t_sound, up, {0: SHUTTLE_SOUND + 'LiftOff_Play', 1: SHUTTLE}, delay=T, conds=standing())
    flag(up, 'SV_ShuttleLaunched', 'Set', 1, delay=T, conds=standing())
    flag(up, 'SV_ShuttleRound', 'Set', 0, delay=T, conds=standing())
    g.execute(t_climb2, up, delay=T + 13, conds=standing())
    g.execute(t_cam_off, up, delay=T + 7)
    g.execute(t_vfx_off, up, delay=T + 30)
    # Taking it and the pad's allies off after liftoff: Scripts/main.lua fires RE_SV_ShuttleRemove SHUTTLE_REMOVE_S after
    # it (test of 2026-10-22: records here on a delay gated on SV_ShuttleLaunched never ran, both units stayed up to
    # round 9: a delayed record's conditions are checked when its event fires, at the shuttle's appearance).
    # LiveDestroyUnitExecution kills through TakeDamage(FLT_MAX), which is clamped at the object's MinHealth: the 1.0
    # set before liftoff has to go back to 0 first (as M019/M021/M026 do), or the shuttle stays up with 1 HP.
    g.trigger('RE_SpawnEnemy_kokatu_1st', 'RE_SV_ShuttleRemove')
    g.execute(t_minhp, 'RE_SV_ShuttleRemove', {0: SHUTTLE, 3: '0.0'})
    g.execute(t_remove, 'RE_SV_ShuttleRemove', delay=1.0)
    g.execute(t_remove, 'RE_SV_ShuttleRemove', {0: 'NoneSelect', 1: PAD_UNIT, 2: 'NoneSelect'})
    # the pad's allies (guns, SAMs, tower) go with it: the whole unit, not one object
    # the flags back to 0 once this special's records are all done, in case the game checks a delayed record's conditions
    # when the event fires, not when it runs: then a loss left in SV_ShuttleLost would silence the next special
    after = T + SHUTTLE_REMOVE_S + 30                # (well after Lua's removal: it counts from when it sees liftoff)
    for name in resets:
        flag(up, name, 'Set', 0, delay=after)
    # hits: Mission 22's ObjectDamage_Shuttle; its low-health radio (61 / 31 / 16 %) keeps the stock health conditions.
    # Mission 22 also gates each stage on a bool flag of its own (Bool_Shuttle_Damage_Phase0N), which Survival's flag
    # asset doesn't have: that check is replaced by an int flag of Survival's, set when the line plays and reset when the
    # shuttle appears, so the callouts come again every special (a life-1 trigger would fire once a level).
    hit = 'SV_ShuttleHit'
    g.trigger('ObjectDamage_Shuttle', hit)
    g.execute(t_radio, hit, {0: '01_All_Wave_Hit_Shuttle_First'}, conds=[g.cond('SV_ShuttleHits', 'Leq', 0)])
    flag(hit, 'SV_ShuttleHits', 'Add', 1)
    for c, stage, line in (('A', 1, 'Durability50'), ('B', 2, 'Durability30'), ('C', 3, 'Durability_Limit')):
        t = tpl('LiveCallRemoteEventExecution', 'ObjectDamage_Shuttle', lambda a, e, n=stage: a[0] == f'RE_Shuttle_Damage_Phase{n}')
        stock = fields(t)['ConditionalStatementTables'][3][1]
        cls = [ep_dump.show(fields(x)['StatementClass'][3], g.z) for x in stock]
        health = [x for x, c in zip(stock, cls) if c == 'LiveIsLowHealthStatement']     # its band, e.g. < 61 and >= 31 %
        assert health and set(cls) == {'LiveIsLowHealthStatement', 'LiveCheck_FlagBoolStatement'}, (stage, cls)
        said = f'SV_ShuttleDmg{c}'
        ev = f'RE_SV_ShuttleDamage{c}'                               # no numeric tail (hard rule 17)
        g.execute(t, hit, {0: ev}, conds=health + [g.cond(said, 'Leq', 0)])
        g.trigger('RE_Shuttle_Damage_Phase1', ev)
        g.execute(t_radio, ev, {0: f'01_All_Wave_{line}_Shuttle'})
        flag(ev, said, 'Set', 1)
    near = 'SV_ShuttleNear'
    g.trigger('VolumeEvent_Shuttle_Near_1st', near)
    g.execute(t_radio, near, {0: '01_All_Wave_Close_Shuttle_First'},
              conds=standing() + [g.cond('SV_ShuttleNearSaid', 'Leq', 0), g.cond('SV_ShuttleRound', 'Geq', 1)])
    flag(near, 'SV_ShuttleNearSaid', 'Set', 1, conds=[g.cond('SV_ShuttleRound', 'Geq', 1)])
    # shot down on the pad (Mission 22's ObjectDestroy / ObjectDestroy_1, any attacker or a system kill)
    on_pad = lambda: [g.cond('SV_ShuttleLaunched', 'Leq', 0)]
    for src, ev in (('ObjectDestroy', 'SV_ShuttleDown'), ('ObjectDestroy_1', 'SV_ShuttleDownSys')):
        assert arg_values(g.trig_template(src))[16] == SHUTTLE
        g.trigger(src, ev)
        flag(ev, 'SV_ShuttleLost', 'Set', 1, conds=on_pad())
        flag(ev, 'SV_ShuttleRound', 'Set', 0, conds=on_pad())
    g.execute(t_radio, 'SV_ShuttleDown', {0: '01_Mission_Failure_Destroy_Shuttle'},
              conds=[g.cond('SV_ShuttleLaunched', 'Leq', 0)])
    g.execute(t_sflag, 'SV_ShuttleDown', {0: 'AKE_FLAG_Ms22_ARMS_SKY_OP0057_sstb_Countdown_Interrupted_Set'},
              conds=[g.cond('SV_ShuttleLaunched', 'Leq', 0)])
    for k in range(3):
        g.execute(t_vfx_on, 'SV_ShuttleDown', {0: f'VFX_ShuttleDummy{k}'}, conds=[g.cond('SV_ShuttleLaunched', 'Leq', 0)])
    g.execute(t_remove, 'SV_ShuttleDown', {0: 'NoneSelect', 1: PAD_UNIT, 2: 'NoneSelect'}, delay=PAD_REMOVE_LOST_S,
              conds=[g.cond('SV_ShuttleLaunched', 'Leq', 0)])


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
