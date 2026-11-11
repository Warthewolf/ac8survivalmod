"""build_survival_units.py : the level and its world data's units, part one.

The level, its MC and phase world data (build_pl, build_mc, build_wd_phase); the world data's unit and path
helpers (set_flight_size, move_object, copy_unit, port_unit, copy_path, make_path, import_from, ...); the
units of the STORE's allies (ally_units), the Ladons, the heavies' paths, VALKA, the Alicorn (and its rows)
and the amphibious assault.

A part of tools/build_survival.py (its docstring has the layout): every name build_survival defines is here
through the import below, and build_survival imports this part back whole, so each name here is
build_survival.<name> too. Import build_survival (or run it), not this file.
"""
from build_survival import *  # noqa: F401,F403 (build_survival's names; it imports this part at its end)


# ---------------------------------------------------------------- packages
def build_pl():
    z = ZenPkg(stock(M22 + 'PL_Mission022'))
    rename_package(z, M22 + 'PL_Mission022', PL)
    # Lighting: Mission 4's sky/cloud level instead of Mission 22's.
    z.rename(LIT_OLD, LIT_NEW); z.rename(LIT_OLD.rsplit('/', 1)[1], LIT_NEW.rsplit('/', 1)[1])
    # Mission files
    for n in ('MC_Mission022', 'WD_Mission022_global', 'WD_Mission022_phase01', 'WD_Mission022_phase02',
              'EP_Mission022_global', 'EP_Mission022_phase01', 'EP_Mission022_phase02'):
        retarget_import(z, M22 + n, MI + n.replace('Mission022', 'SurvivalMode'))
    retarget_import(z, RADIO_STOCK, RADIO)                 # Survival's copy of Mission 22's radio lines (build_radio)
    # World settings: Mission 4's clock and cloud values; drop Mission 22's shuttle-launch cloud light.
    i = z.export_index('ChronicleWorldSettings')
    v, rest = props_of(z, i, 'LiveWorldSettings')
    props = v[2]
    sc = uprop.U.schema('LiveWorldSettings')
    idx = {nm: k for k, (nm, t) in sc.items()}
    set_prop(props, idx['ClockHour'], 'ClockHour', ('raw', 'Int', struct.pack('<i', CLOCK[0])))
    set_prop(props, idx['ClockMin'], 'ClockMin', ('raw', 'Int', struct.pack('<i', CLOCK[1])))
    drop_prop(props, idx['CloudDensityScale'])
    set_prop(props, idx['CloudDensityScaleBySound'], 'CloudDensityScaleBySound',
             ('raw', 'Float', struct.pack('<f', CLOUD_DENSITY_BY_SOUND)))
    drop_prop(props, idx['CloudLightSettings'])
    z.payloads[i] = bytearray(write_props(z, v) + rest)
    chk, _ = props_of(z, i, 'LiveWorldSettings'); assert chk == v
    save(z, PL, '.umap')


def build_mc():
    z = ZenPkg(stock(M22 + 'MC_Mission022'))
    rename_package(z, M22 + 'MC_Mission022', MI + 'MC_SurvivalMode')
    v, rest = props_of(z, 0, 'LiveCampaignMissionConfig')
    set_prop(v[2], 7, 'MissionLimitTime', ('raw', 'Float', struct.pack('<f', MISSION_TIME_LIMIT)))
    z.payloads[0] = bytearray(write_props(z, v) + rest)
    save(z, MI + 'MC_SurvivalMode')


def build_wd_phase(n):
    old, new = M22 + f'WD_Mission022_phase0{n}', MI + f'WD_SurvivalMode_phase0{n}'
    z = ZenPkg(stock(old))
    rename_package(z, old, new)   # also renames the WorldDataName value (same FName)
    v, rest = props_of(z, 0, 'LiveWorldData')
    starts = [p for p in v[2] if p[1] == 'PlayerStartDescList'][0][3][1]
    assert len(starts) == 1
    ps = starts[0][2]
    for k, (pi, pn, zero, val) in enumerate(ps):
        if pn == 'SpawnPoint': ps[k] = (pi, pn, False, ('native', 'Vector', struct.pack('<3d', *START)))
        if pn == 'Rotation': ps[k] = (pi, pn, False, ('native', 'Rotator', struct.pack('<3d', *START_ROT)))
    z.payloads[0] = bytearray(write_props(z, v) + rest)
    save(z, new)


FORMATION_CM = 30000.0     # 300 m: pairs side by side, each pair this far behind the one ahead


def unit_point(u):
    sp = [p for p in u[2] if p[1] == 'SpawnPoint']
    return struct.unpack('<3d', sp[0][3][2]) if sp and sp[0][3] else (0.0, 0.0, 0.0)


def set_flight_size(objs, size, unit, point, used_ids, top_number):
    """Cut or grow a flight's AI object list to `size` (copies of the lead / wingman pair with new UniqueIDs and the next
    free number of their name: Mission 22 numbers one name across several flights, so top_number is world-wide), and
    lay it out: lead on the unit point, wingman beside it, each further pair FORMATION_CM back."""
    del objs[size:]
    while len(objs) < size:
        k = len(objs)
        ob = copy.deepcopy(objs[k % 2])
        name = [q for q in ob[2] if q[1] == 'Name'][0][3]
        top_number[name[1]] += 1
        top = top_number[name[1]] - 1
        h = zlib.crc32(f'AC8SurvivalMode:{unit}:{k}'.encode())
        while struct.pack('<I', h) in used_ids: h = (h + 1) & 0xffffffff
        used_ids.add(struct.pack('<I', h))
        ob[2][:] = [(q[0], q[1], False, ('name', name[1], top + 1)) if q[1] == 'Name' else
                    (q[0], q[1], False, ('raw', 'UInt32', struct.pack('<I', h))) if q[1] == 'UniqueID' else q for q in ob[2]]
        objs.append(ob)
    for k, ob in enumerate(objs):
        at = (point[0] - FORMATION_CM * (k // 2), point[1] + (FORMATION_CM if k % 2 else 0.0), point[2])
        assert any(q[1] == 'SpawnPoint' for q in ob[2]), unit
        ob[2][:] = [(q[0], q[1], False, ('native', 'Vector', struct.pack('<3d', *at))) if q[1] == 'SpawnPoint' else q
                    for q in ob[2]]


def move_object(units, used_ids, z, src_unit, obj, new_unit, npc_row=None):
    """Moves AI object `obj` (a name, or a list of names) out of world-data unit `src_unit` into a new unit `new_unit`:
    a copy of the source's desc (same faction, point, area and tags) with a new UniqueID, holding only those objects
    (optionally on NPC row `npc_row`). SV_Spawn(new_unit) without a position then puts them where the stock mission
    placed them. No ground object of Mission 22's leads its unit (bGroupLead 0), so such a unit needs no leader."""
    dn = lambda n: n[1] if n[2] == 0 else f'{n[1]}_{n[2] - 1}'
    unit_name = lambda u: [p for p in u[2] if p[1] == 'Name'][0][3][1]
    src = [u for u in units if unit_name(u) == src_unit][0]
    assert new_unit not in {unit_name(u) for u in units} and not new_unit[-1].isdigit(), new_unit   # hard rule 17
    objs = [p for p in src[2] if p[1] == 'AIObjectDescList'][0][3][1]
    wanted = [obj] if isinstance(obj, str) else list(obj)
    moved = []
    for name in wanted:
        hit = [ob for ob in objs if dn([q for q in ob[2] if q[1] == 'Name'][0][3]) == name]
        assert len(hit) == 1, name
        objs.remove(hit[0])
        moved.append(hit[0])
    new = copy.deepcopy(src)
    if npc_row:
        for ob in moved:
            assert any(q[1] == 'MissionNpcID' for q in ob[2]), obj
            ob[2][:] = [(q[0], q[1], False, ('name', npc_row, 0)) if q[1] == 'MissionNpcID' else q for q in ob[2]]
        z.nb.add(npc_row)
    z.nb.add(new_unit)
    ids = used_ids | {q[3][2] for u in units for q in u[2] if q[1] == 'UniqueID' and q[3]}
    h = zlib.crc32(b'AC8SurvivalMode:' + new_unit.encode())
    while struct.pack('<I', h) in ids: h = (h + 1) & 0xffffffff
    assert any(q[1] == 'UniqueID' for q in new[2]), 'unit desc without UniqueID'
    new[2][:] = [(q[0], q[1], False, ('name', new_unit, 0)) if q[1] == 'Name' else
                 (q[0], q[1], False, ('raw', q[3][1], struct.pack('<I', h))) if q[1] == 'UniqueID' else q for q in new[2]]
    [p for p in new[2] if p[1] == 'AIObjectDescList'][0][3][1][:] = moved
    units.append(new)
    return len(objs)


def new_unique_id(used_ids, seed):
    h = zlib.crc32(seed.encode())
    while struct.pack('<I', h) in used_ids: h = (h + 1) & 0xffffffff
    used_ids.add(struct.pack('<I', h))
    return struct.pack('<I', h)


def path_start(v, path):
    """The world position (cm) of AI path `path`'s first point."""
    paths = [p for p in v[2] if p[1] == 'AIPathDescList'][0][3][1]
    for el in paths:
        f = {p[1]: p[3] for p in el[2]}
        if f['Name'][1:3] == (path, 0):
            pos = {p[1]: p[3] for p in f['BeginPointDesc'][2]}['Pos']
            return struct.unpack('<3d', pos[2])
    raise LookupError(path)


def set_unit_point(u, point):
    """Unit desc `u` and its AI objects (and so their turrets) at `point` (cm)."""
    vec = ('native', 'Vector', struct.pack('<3d', *point))
    u[2][:] = [(q[0], q[1], False, vec) if q[1] == 'SpawnPoint' else q for q in u[2]]
    for ob in [p for p in u[2] if p[1] == 'AIObjectDescList'][0][3][1]:
        ob[2][:] = [(q[0], q[1], False, vec) if q[1] == 'SpawnPoint' else q for q in ob[2]]


def clear_flags(u, flags):
    """Every AI object of unit desc `u` with these bool properties written as an explicit false."""
    for ob in [p for p in u[2] if p[1] == 'AIObjectDescList'][0][3][1]:
        ob[2][:] = [(q[0], q[1], True, None) if q[1] in flags else q for q in ob[2]]


def unit_area(u, radius_m, alt_m):
    """Unit desc `u`'s area: radius_m around its point, alt_m (min, max) high (its turrets engage only inside it)."""
    area = {'RadiusInMeter': radius_m, 'MinAltitudeInMeter': alt_m[0], 'MaxAltitudeInMeter': alt_m[1]}
    idx = {n: k for k, (n, t) in uprop.U.schema('LiveUnitDesc').items() if n in area}
    assert len(idx) == 3, idx
    u[2][:] = sorted([p for p in u[2] if p[1] not in area] + [(idx[n], n, False, ('raw', 'Float', struct.pack('<f', v)))
                     for n, v in area.items()], key=lambda p: p[0])


def retag_turrets(children, owner, rows, used_ids, z):
    """A copied ship's turret descs (ChildAIObjectDescs / GrandChildrens): named after their new owner as Mission 22
    names them (<owner>_<component>), new UniqueIDs, and Survival's mission rows (`rows`: stock row -> Survival's)."""
    for ch in children:
        d = {p[1]: p for p in ch[2]}
        data = d['Data'][3][2]
        comp = [q for q in data if q[1] == 'ComponentFieldName'][0][3][1]
        stock_row = [q for q in data if q[1] == 'MissionNpcID'][0][3][1]
        assert stock_row in rows, (owner, stock_row)
        data[:] = [(q[0], q[1], False, ('name', rows[stock_row], 0)) if q[1] == 'MissionNpcID' else q for q in data]
        name = f'{owner}_{comp}'
        assert not name.rpartition('_')[2].isdigit(), name                  # no _<digits> tail: hard rule 17
        uid = new_unique_id(used_ids, 'AC8SurvivalMode:' + name)
        ch[2][:] = [(q[0], q[1], False, ('name', name, 0)) if q[1] == 'Name' else
                    (q[0], q[1], False, ('raw', 'UInt32', uid)) if q[1] == 'UniqueID' else q for q in ch[2]]
        for n in (name, rows[stock_row]): z.nb.add(n)
        grand = d.get('GrandChildrens')
        if grand and grand[3]: retag_turrets(grand[3][1], name, rows, used_ids, z)


def copy_unit(units, used_ids, z, src_unit, new_unit, size, top_number, obj_name, npc_row):
    """A new unit `new_unit`: a copy of `src_unit`'s desc (faction, point, area, tags) holding its first `size` AI
    objects, named obj_name (numbered _0, _1, ... when more than one) with new UniqueIDs, on NPC row `npc_row` (their
    airframe and, built at level load, their behaviour: hard rule 20). Returns the objects' names as event args write them."""
    unit_name = lambda u: [p for p in u[2] if p[1] == 'Name'][0][3][1]
    src = [u for u in units if unit_name(u) == src_unit][0]
    assert new_unit not in {unit_name(u) for u in units} and not new_unit[-1].isdigit(), new_unit   # hard rule 17
    new = copy.deepcopy(src)
    objs = [p for p in new[2] if p[1] == 'AIObjectDescList'][0][3][1]
    assert len(objs) >= size, (src_unit, len(objs), size)
    del objs[size:]
    assert obj_name not in top_number and not obj_name[-1].isdigit(), obj_name
    names = []
    for k, ob in enumerate(objs):
        num = 0 if size == 1 else k + 1                       # FName number: 0 = no suffix, n = "_<n-1>"
        h = zlib.crc32(f'AC8SurvivalMode:{new_unit}:{k}'.encode())
        while struct.pack('<I', h) in used_ids: h = (h + 1) & 0xffffffff
        used_ids.add(struct.pack('<I', h))
        assert any(q[1] == 'MissionNpcID' for q in ob[2]), new_unit
        ob[2][:] = [(q[0], q[1], False, ('name', obj_name, num)) if q[1] == 'Name' else
                    (q[0], q[1], False, ('name', npc_row, 0)) if q[1] == 'MissionNpcID' else
                    (q[0], q[1], False, ('raw', 'UInt32', struct.pack('<I', h))) if q[1] == 'UniqueID' else q for q in ob[2]]
        names.append(obj_name if num == 0 else f'{obj_name}_{num - 1}')
    top_number[obj_name] = len(objs)
    assert npc_row in NPC_ROWS, npc_row
    for n in (new_unit, obj_name, npc_row): z.nb.add(n)
    ids = used_ids | {q[3][2] for u in units for q in u[2] if q[1] == 'UniqueID' and q[3]}
    h = zlib.crc32(b'AC8SurvivalMode:' + new_unit.encode())
    while struct.pack('<I', h) in ids: h = (h + 1) & 0xffffffff
    new[2][:] = [(q[0], q[1], False, ('name', new_unit, 0)) if q[1] == 'Name' else
                 (q[0], q[1], False, ('raw', q[3][1], struct.pack('<I', h))) if q[1] == 'UniqueID' else q for q in new[2]]
    units.append(new)
    return names


COOP_NAME_KEYS = [f'SV_CoopName_{c}' for c in survival_events.COOP_PEER_SLOTS]   # sv_coop.lua NAME_KEYS


def ally_units(units, used_ids, z, top_number, v):
    """The STORE's allies (survival_events.ALLY_*): MOONCHILD's two-ships, parked where Mission 22 parks its scramble
    jets, and the ships, each at the start of its lane. Both may be targeted and killed (Mission 22's jets are
    invincible and its allied ships attack-target exceptions)."""
    unit_by = lambda n: [u for u in units if [p for p in u[2] if p[1] == 'Name'][0][3][1] == n][0]
    r_idx = [k for k, (n, t) in uprop.U.schema('LiveUnitDesc').items() if n == 'RadiusInMeter'][0]
    for unit in survival_events.ALLY_AIR_UNITS:
        names = copy_unit(units, used_ids, z, survival_events.ALLY_AIR_SOURCE, unit, 2, top_number,
                          'SV_Obj_' + unit[len('SV_Unit_'):], survival_events.ALLY_AIR_ROW)
        survival_events.ALLY_AIR_OBJS[unit] = names
        u = unit_by(unit)
        clear_flags(u, ('bIsInvincible',))
        u[2][:] = sorted([p for p in u[2] if p[1] != 'RadiusInMeter'] + [(r_idx, 'RadiusInMeter', False,
                         ('raw', 'Float', struct.pack('<f', survival_events.AREA_RADIUS_M)))], key=lambda p: p[0])
    hulls = {key: (src, hull) for key, src, hull, _ in survival_events.ALLY_SHIPS}
    for key, n, unit, obj, lane in survival_events.ally_ships():
        src, hull = hulls[key]
        rows = {t: survival_events.ally_turret_rows(t)[0] for t in survival_events.ALLY_TURRETS[key]}
        names = copy_unit(units, used_ids, z, src, unit, 1, top_number, obj, survival_events.ally_ship_rows(key)[0])
        assert names == [obj], names
        u = unit_by(unit)
        clear_flags(u, ('bIsAttackTargetsException',))
        ob = [p for p in u[2] if p[1] == 'AIObjectDescList'][0][3][1][0]
        retag_turrets([p for p in ob[2] if p[1] == 'ChildAIObjectDescs'][0][3][1], obj, rows, used_ids, z)
        x, y, _ = path_start(v, lane)
        set_unit_point(u, (x, y, 300.0))
        area = {'RadiusInMeter': survival_events.ALLY_SHIP_AREA_M, 'MinAltitudeInMeter': survival_events.ALLY_SHIP_ALT_M[0],
                'MaxAltitudeInMeter': survival_events.ALLY_SHIP_ALT_M[1]}
        sc = uprop.U.schema('LiveUnitDesc')
        aidx = {n: k for k, (n, t) in sc.items() if n in area}
        assert len(aidx) == 3, aidx
        u[2][:] = sorted([p for p in u[2] if p[1] not in area] + [(aidx[n], n, False, ('raw', 'Float', struct.pack('<f', val)))
                         for n, val in area.items()], key=lambda p: p[0])
    # Survival COOP: the other players' planes, one per player slot, each one aircraft of MOONCHILD's source
    # (invincible kept: they only show the players). Each shows its player's name on its target box (user, 2026-10-26:
    # "we need to get player names working on the HUD always"): the callsign is the desc's GameObjectDisplayNameID02
    # (docs/re/MINIMAP_MARKERS.md 1d, 1g), shown for an ally with bShowCallSignForAlly; Survival's key SV_CoopName_<A-X>
    # is set to the player's name at run time (sv_coop.lua, SV_SetText).
    sc = uprop.U.schema('LiveAIObjectDesc')
    ix = {n: k for k, (n, t) in sc.items() if n in ('bShowHUDBox', 'bShowCallSignForAlly', 'GameObjectDisplayNameID02')}
    assert len(ix) == 3, ix
    for unit, obj, key in zip(survival_events.COOP_PEER_UNITS, survival_events.COOP_PEER_OBJS, COOP_NAME_KEYS):
        names = copy_unit(units, used_ids, z, survival_events.ALLY_AIR_SOURCE, unit, 1, top_number, obj,
                          survival_events.ALLY_AIR_ROW)
        assert names == [obj], names
        ob = [p for p in unit_by(unit)[2] if p[1] == 'AIObjectDescList'][0][3][1][0]
        ob[2][:] = sorted([q for q in ob[2] if q[1] not in ix] + [
            (ix['bShowHUDBox'], 'bShowHUDBox', False, ('raw', 'Bool', b'\x01')),
            (ix['bShowCallSignForAlly'], 'bShowCallSignForAlly', False, ('raw', 'Bool', b'\x01')),
            (ix['GameObjectDisplayNameID02'], 'GameObjectDisplayNameID02', False, ('name', key, 0))], key=lambda q: q[0])
        z.nb.add(key)
    # VOID WATCHER 1 (survival_events.AWACS_*): one aircraft of MOONCHILD's source, parked where its lead is, on the
    # E-767's row (its behaviour built at level load: hard rule 20), killable, its name on its target box as the co-op
    # stand-ins' (the desc's GameObjectDisplayNameID02, shown for an ally with bShowCallSignForAlly)
    names = copy_unit(units, used_ids, z, survival_events.ALLY_AIR_SOURCE, survival_events.AWACS_UNIT, 1, top_number,
                      survival_events.AWACS_OBJ, survival_events.AWACS_ROW)
    assert names == [survival_events.AWACS_OBJ], names
    u = unit_by(survival_events.AWACS_UNIT)
    clear_flags(u, ('bIsInvincible',))
    # (0.73.68) its area's height band too: with the area alone it circled the airfield but climbed on and on (the
    # test of 2026-11-01 23:41: 0.4 -> 2.2 -> 3.5 km in 60 s, "continues climbing but doesn't level out")
    unit_area(u, survival_events.AWACS_AREA_M, survival_events.AWACS_ALT_BAND_M)
    ob = [p for p in u[2] if p[1] == 'AIObjectDescList'][0][3][1][0]
    ob[2][:] = sorted([q for q in ob[2] if q[1] not in ix] + [
        (ix['bShowHUDBox'], 'bShowHUDBox', False, ('raw', 'Bool', b'\x01')),
        (ix['bShowCallSignForAlly'], 'bShowCallSignForAlly', False, ('raw', 'Bool', b'\x01')),
        (ix['GameObjectDisplayNameID02'], 'GameObjectDisplayNameID02', False, ('name', survival_events.AWACS_NAME_KEY, 0))],
        key=lambda q: q[0])
    z.nb.add(survival_events.AWACS_NAME_KEY)
    print(f'  allies: {len(survival_events.ALLY_AIR_UNITS)} MOONCHILD flights {survival_events.ALLY_AIR_OBJS}, '
          f'{len(survival_events.ally_ships())} ships, VOID WATCHER 1 ({survival_events.AWACS_UNIT})')


M13 = '/Game/Maps/Ingame/Mission013/'


def stock_wd(path):
    """A stock world data's LiveWorldData properties (for descs copied from another mission)."""
    zs = ZenPkg(stock(path))
    i = zs.export_index(path.rsplit('/', 1)[1])
    v, _ = props_of(zs, i, 'LiveWorldData')
    return v


def desc_named(v, lst, name):
    for el in [p for p in v[2] if p[1] == lst][0][3][1]:
        if [p for p in el[2] if p[1] == 'Name'][0][3][1:3] == survival_events.fname(name)[1:]:   # ('Boss_0' = ('Boss', 1))
            return el
    raise LookupError((lst, name))


def vec(x, y, zz, kind='Vector'):
    return ('native', kind, struct.pack('<3d', x, y, zz))


def port_unit(units, used_ids, z, src, new_unit, obj_name, npc_row, points, yaw, top_number, tgt=False, rows=None,
              keep_rotation=False, digit_ok=False, clone_first=False, unit_digits=False):
    """A new unit `new_unit` from another mission's unit desc `src`: its first len(points) AI objects at `points`
    (cm), facing `yaw`, named obj_name (numbered _0, _1 ... when more than one) on NPC row `npc_row`; no tags (they're
    the other mission's), our world data's name, new UniqueIDs; tgt: a target box and a TGT mark on each (user,
    2026-10-23: "assault ships and troops did not come with target boxes"). rows: each object's own row (in order);
    keep_rotation: the source objects' rotation (Mission 19's rockets stand on their tails); digit_ok: an obj_name
    ending in a digit with no underscore before it (FName splits a tail only after one: Mission 19's debris names, which
    its rocket's blueprint looks up exactly); clone_first: every object a copy of the source's first (a unit of mixed
    vehicles: Mission 7's T-90 is one of three kinds); unit_digits: a unit name ending in a digit (the build contract's
    SV_Unit_FestLight_1 / SV_Unit_FestCM_N1), stored as the engine turns the string into an FName (survival_events.fname:
    'X_1' = ('X', 2), as stock stores B_Unit_00_MainMissile_PathMove0_0; hard rule 17), so SV_Spawn's name finds it.
    Returns the objects' names as event args write them."""
    new = copy.deepcopy(src)
    uname = survival_events.fname(new_unit) if unit_digits else ('name', new_unit, 0)
    assert uname[1:] not in {tuple([p for p in u[2] if p[1] == 'Name'][0][3][1:3]) for u in units}, new_unit
    assert (unit_digits or not new_unit[-1].isdigit()) and (digit_ok or not obj_name[-1].isdigit()) \
        and obj_name not in top_number, obj_name
    assert not digit_ok or obj_name.rpartition('_')[2][:1].isalpha(), obj_name    # (its tail is a word, not _<digits>)
    assert rows is None or len(rows) == len(points), (new_unit, rows)
    wd = ('name', 'WD_SurvivalMode_global', 0)
    objs = [p for p in new[2] if p[1] == 'AIObjectDescList'][0][3][1]
    if clone_first: objs[:] = [copy.deepcopy(objs[0])]
    while len(objs) < len(points): objs.append(copy.deepcopy(objs[-1]))   # more than the source has: copies of its last
    del objs[len(points):]
    names = []
    for k, (ob, pt) in enumerate(zip(objs, points)):
        num = 0 if len(points) == 1 else k + 1
        uid = new_unique_id(used_ids, f'AC8SurvivalMode:{new_unit}:{k}')
        repl = {'Name': ('name', obj_name, num), 'MissionNpcID': ('name', rows[k] if rows else npc_row, 0),
                'UniqueID': ('raw', 'UInt32', uid), 'SpawnPoint': vec(*pt), 'Rotation': vec(0.0, yaw, 0.0, 'Rotator'),
                'WorldDataName': wd, 'Tags': ('arr', [])}
        if keep_rotation: del repl['Rotation']
        assert all(any(q[1] == n for q in ob[2]) for n in ('Name', 'MissionNpcID', 'UniqueID', 'SpawnPoint')), new_unit
        ob[2][:] = [(q[0], q[1], False, repl[q[1]]) if q[1] in repl and q[3] is not None else q for q in ob[2]]
        if tgt:                    # the HUD's target box and the red TGT mark (ELiveTargetMarkType 1), as a mission target
            sc = uprop.U.schema('LiveAIObjectDesc')
            ix = {n: k for k, (n, t) in sc.items() if n in ('TargetMarkType', 'bShowHUDBox')}
            ob[2][:] = sorted([q for q in ob[2] if q[1] not in ix] + [
                (ix['TargetMarkType'], 'TargetMarkType', False, ('enum', 'ELiveTargetMarkType', ('raw', 'Byte', b'\x01'))),
                (ix['bShowHUDBox'], 'bShowHUDBox', False, ('raw', 'Bool', b'\x01'))], key=lambda q: q[0])
        names.append(obj_name if num == 0 else f'{obj_name}_{num - 1}')
    top_number[obj_name] = len(points)
    uid = new_unique_id(used_ids, f'AC8SurvivalMode:{new_unit}')
    cx, cy = sum(p[0] for p in points) / len(points), sum(p[1] for p in points) / len(points)
    repl = {'Name': uname, 'UniqueID': ('raw', 'UInt32', uid), 'SpawnPoint': vec(cx, cy, 0.0),
            'Rotation': vec(0.0, yaw, 0.0, 'Rotator'), 'WorldDataName': wd, 'Tags': ('arr', [])}
    new[2][:] = [(q[0], q[1], False, repl[q[1]]) if q[1] in repl and q[3] is not None else q for q in new[2]]
    # never at the level's start (the source may say so: Mission 16's Ladons and EB_002's Alicorn did, and build_wd_global's
    # switch-off has run by now; code review of 2026-10-23): an explicit zero, as Mission 22's reinforcements carry it
    sp_idx = [k for k, (n, t) in uprop.U.schema('LiveUnitDesc').items() if n == 'bIsSpawnFromStart'][0]
    new[2][:] = sorted([q for q in new[2] if q[1] != 'bIsSpawnFromStart'] + [(sp_idx, 'bIsSpawnFromStart', True, None)],
                       key=lambda q: q[0])
    assert npc_row in NPC_ROWS and all(r in NPC_ROWS for r in rows or []), (npc_row, rows)
    for n in names_in(new) + [uname[1], obj_name, npc_row, 'WD_SurvivalMode_global'] + list(rows or []): z.nb.add(n)
    units.append(new)
    return names


def copy_path(z, used_ids, src, name):
    """Another mission's AI path desc `src` whole as Survival's `name`: its points where they are (their tangents, up and
    rotation: Mission 19's rocket climbs, straight up, need its own; make_path's level tangents can't), renamed as the
    engine names a path's points (name_0, name_1 ...), new UniqueIDs, our world data's name, no tube data (hard rule 34)
    and ControlType 1 (hard rule 35)."""
    new = copy.deepcopy(src)
    f = {p[1]: p for p in new[2]}
    assert not name[-1].isdigit(), name
    els = []
    for k, el in enumerate(f['PathPointDescList'][3][1]):
        el = copy.deepcopy(el)
        uid = ('raw', 'UInt32', new_unique_id(used_ids, f'AC8SurvivalMode:{name}:{k + 1}'))
        el[2][:] = [(q[0], q[1], False, ('name', name, k + 1)) if q[1] == 'Name' else
                    (q[0], q[1], False, uid) if q[1] == 'UniqueID' else q for q in el[2]]
        els.append(el)
    b = copy.deepcopy(f['BeginPointDesc'][3])
    b[2][:] = [(q[0], q[1], False, ('raw', 'UInt32', new_unique_id(used_ids, f'AC8SurvivalMode:{name}:0'))) if q[1] == 'UniqueID'
               else q for q in b[2]]
    tube = ('struct', 'LiveAIPathTubeData', [(0, 'TubeData', False, ('arr', [])), (1, 'MoveData', False, ('arr', []))])
    ctl = ('enum', 'ELiveAIPathControlType', ('raw', 'Byte', b'\x01'))
    assert f['ControlType'][3] is not None and f['ControlType'][3][2][2] == b'\x01', (name, f['ControlType'][3])
    repl = {'BeginPointDesc': b, 'PathPointDescList': ('arr', els), 'PathTubeData': tube, 'ControlType': ctl,
            'UniqueID': ('raw', 'UInt32', new_unique_id(used_ids, f'AC8SurvivalMode:{name}')),
            'Name': ('name', name, 0), 'WorldDataName': ('name', 'WD_SurvivalMode_global', 0)}
    new[2][:] = [(q[0], q[1], False, repl[q[1]]) if q[1] in repl else q for q in new[2]]
    for n in names_in(new) + [name, 'DefaultPathPoint']: z.nb.add(n)
    return new


def make_path(z, used_ids, template, name, pts, smooth=False, before=None, after=None):
    """An AI path desc `name` through `pts` (cm), shaped like `template` (Mission 13's LCAC path: begin point, points
    with tangents, ControlType 1). Default: short level tangents (at most 1.2 km), up straight up, no pitch: fine for
    craft and vehicles. smooth=True (aircraft: the Ladons): Mission 16's Ladon path's shape, each tangent along the
    line through its neighbours (3D) and as long as its shorter leg, so the spline turns in wide curves; up banked into
    the turn (up to 50 degrees, with the turn's angle) and the rotation's pitch the climb. `before` / `after`: the
    points just outside `pts` (a circuit's other end, the next path's second point), so the tangent runs on smoothly."""
    import math
    # ((2026-11-07) a record names a path by string, which the engine splits at a number tail (hard rule 17): a desc named
    # "..._1_0" is never found. Never one)
    assert survival_events.fname(name)[2] == 0, f'path {name}: a number tail (records would never find it: hard rule 17)'
    new = copy.deepcopy(template)
    f = {p[1]: p for p in new[2]}
    begin = f['BeginPointDesc'][3]
    point_t = f['PathPointDescList'][3][1][0]

    def unit(v):
        n = math.sqrt(sum(c * c for c in v)) or 1.0
        return [c / n for c in v]

    def shape(k, pos):
        prv = pts[k - 1] if k > 0 else (before or pos)
        nxt = pts[k + 1] if k + 1 < len(pts) else (after or pos)
        if not smooth:
            dx, dy = (nxt[0] - prv[0]), (nxt[1] - prv[1])
            seg = math.hypot(dx, dy) or 1.0
            tan = (dx / seg * min(seg, 120000.0), dy / seg * min(seg, 120000.0), 0.0)
            return tan, (0.0, 0.0, 1.0), (0.0, math.degrees(math.atan2(dy, dx)), 0.0)
        legs = [math.dist(a, b) for a, b in ((prv, pos), (pos, nxt)) if math.dist(a, b) > 1.0]
        d = unit([nxt[i] - prv[i] for i in range(3)])
        tan = tuple(c * min(legs or [1.0]) for c in d)
        din = unit([pos[0] - prv[0], pos[1] - prv[1], 0.0]) if math.dist(prv, pos) > 1.0 else None
        dout = unit([nxt[0] - pos[0], nxt[1] - pos[1], 0.0]) if math.dist(pos, nxt) > 1.0 else None
        up = (0.0, 0.0, 1.0)
        if din and dout:
            turn = math.acos(max(-1.0, min(1.0, din[0] * dout[0] + din[1] * dout[1])))
            inside = unit([dout[0] - din[0], dout[1] - din[1], 0.0])
            bank = min(math.radians(50.0), turn * 0.6)
            if turn > 0.02:
                up = (inside[0] * math.sin(bank), inside[1] * math.sin(bank), math.cos(bank))
        pitch = math.degrees(math.atan2(d[2], math.hypot(d[0], d[1])))
        return tan, up, (pitch, math.degrees(math.atan2(d[1], d[0])), 0.0)

    def point(el, k, pos, pname):
        tan, up, rot = shape(k, pos)
        repl = {'Pos': vec(*pos), 'tan': vec(*tan), 'Up': vec(*up), 'PathPointRotation': vec(*rot, 'Rotator'),
                'UniqueID': ('raw', 'UInt32', new_unique_id(used_ids, f'AC8SurvivalMode:{name}:{k}')), 'Name': pname}
        el = copy.deepcopy(el)
        el[2][:] = [(q[0], q[1], False, repl[q[1]]) if q[1] in repl and q[3] is not None else q for q in el[2]]
        return el
    els, b = [], None
    for k, pos in enumerate(pts):
        if k == 0:
            b = point(begin, k, pos, ('name', 'DefaultPathPoint', 0))
        else:
            els.append(point(point_t, k, pos, ('name', name, k)))
    # no tube data: a template's (Mission 16's Ladon path) names a tube object in its own package, an export index past
    # ours ("Bad export index 74/19": the game's loader stopped at the hangar, 2026-10-23)
    tube = ('struct', 'LiveAIPathTubeData', [(0, 'TubeData', False, ('arr', [])), (1, 'MoveData', False, ('arr', []))])
    # and so no tube control (ControlType 2): a tube path without its tube "finishes" at once, every frame (the Ladons'
    # PathFinish fired ~30 times a second and restarted their circuit: no route, a bombing run a second, 2026-10-23)
    ctl = ('enum', 'ELiveAIPathControlType', ('raw', 'Byte', b'\x01'))
    repl = {'BeginPointDesc': b, 'PathPointDescList': ('arr', els), 'PathTubeData': tube,
            'UniqueID': ('raw', 'UInt32', new_unique_id(used_ids, f'AC8SurvivalMode:{name}')),
            'Name': ('name', name, 0), 'WorldDataName': ('name', 'WD_SurvivalMode_global', 0)}
    ct = [q for q in new[2] if q[1] == 'ControlType']
    if ct and ct[0][3] is not None and ct[0][3][2][2] == b'\x02': repl['ControlType'] = ctl
    new[2][:] = [(q[0], q[1], False, repl[q[1]]) if q[1] in repl else q for q in new[2]]
    for n in names_in(new) + [name, 'DefaultPathPoint']: z.nb.add(n)
    return new


M16 = '/Game/Maps/Ingame/Mission016/'


def import_from(z, zs, ref):
    """Our import index for another package's import `ref` (('obj', -n) in `zs`): the same imported package and public
    export hash, added to `z`'s import map (and its imported packages) when it isn't there yet. Hard rule 7: pack.py
    puts the package into the container header from this list."""
    assert ref[0] == 'obj' and ref[1] < 0, ref
    x = zs.imports[-ref[1] - 1]
    if x >> 62 == 1:              # (2026-11-06) a script (native) class: the same global id in every package, no package
        if x not in z.imports:    # to import (Mission 19's Spear shooter's TargetingDummy child names one)
            z.imports.append(x)
        return ('obj', -(z.imports.index(x) + 1))
    assert x >> 62 == 2, hex(x)                               # a package import
    pkg = zs.imp_pkgs[(x >> 32) & 0x3fffffff]
    h = zs.imp_hashes[x & 0xffffffff]
    if pkg not in z.imp_pkgs:
        z.ipn.add(pkg)
        z.imp_pkg_nums.append(0)
    k = z.imp_pkgs.index(pkg)
    if h not in z.imp_hashes:
        z.imp_hashes.append(h)
    new = (2 << 62) | (k << 32) | z.imp_hashes.index(h)
    if new not in z.imports:
        z.imports.append(new)
    return ('obj', -(z.imports.index(new) + 1))


def import_class(z, pkg, cls):
    """(2026-11-11, WP2 step 2) Our import index for class `cls` (its short name, e.g. 'BP_SV_Tani_T5_C') of package `pkg`,
    a package no stock package imports (import_from's sibling: Survival's own cooked blueprints, the Tanicorn container's):
    the package into z's imported packages (pack.py puts it in the container header from them: hard rule 7), the class's
    public export hash (zenpkg.export_hash of its name, as each cooked BP_SV_Tani_* package stores it) into its hashes."""
    assert pkg.startswith('/Game/') and '.' not in pkg and cls.endswith('_C'), (pkg, cls)
    if pkg not in z.imp_pkgs:
        z.ipn.add(pkg)
        z.imp_pkg_nums.append(0)
    k = z.imp_pkgs.index(pkg)
    h = export_hash(cls)
    if h not in z.imp_hashes:
        z.imp_hashes.append(h)
    new = (2 << 62) | (k << 32) | z.imp_hashes.index(h)
    if new not in z.imports:
        z.imports.append(new)
    return ('obj', -(z.imports.index(new) + 1))


def retag_parts(children, owner, used_ids, z, zs):
    """A ported aircraft's parts (ChildAIObjectDescs / GrandChildrens): named after their new owner (<owner>_<component>,
    keeping the component's FName number), new UniqueIDs, our world data's name, and their classes imported from the
    source package `zs`. Their mission rows stay the source mission's (NPC_IMPORT brings them)."""
    n = 0
    for ch in children:
        d = {p[1]: p for p in ch[2]}
        data = d['Data'][3][2]
        comp = [q for q in data if q[1] == 'ComponentFieldName'][0][3]
        data[:] = [(q[0], q[1], False, import_from(z, zs, q[3])) if q[1] == 'Class' and q[3] is not None else q for q in data]
        name = (f'{owner}_{comp[1]}', comp[2])
        assert not name[0].rpartition('_')[2].isdigit(), name                 # hard rule 17
        uid = new_unique_id(used_ids, f'AC8SurvivalMode:{name[0]}:{name[1]}')
        ch[2][:] = [(q[0], q[1], False, ('name',) + name) if q[1] == 'Name' else
                    (q[0], q[1], False, ('raw', 'UInt32', uid)) if q[1] == 'UniqueID' else
                    (q[0], q[1], False, ('name', 'WD_SurvivalMode_global', 0)) if q[1] == 'WorldDataName' and q[3] is not None else q
                    for q in ch[2]]
        for nm in names_in(ch): z.nb.add(nm)
        n += 1
        grand = d.get('GrandChildrens')       # (after the whole name: EB_002's WP_L #2..#7 each hold a ram / aagun / ciws)
        sub = f'{owner}_{comp[1]}' + (f'_{comp[2] - 1}' if comp[2] else '')
        if grand and grand[3]: n += retag_parts(grand[3][1], sub, used_ids, z, zs)
    return n


def zone_area(u):
    """Unit desc `u`'s area over the whole combat zone (as the pool's: a 6-10 km area keeps an AI from what's outside)."""
    r_idx = [k for k, (n, t) in uprop.U.schema('LiveUnitDesc').items() if n == 'RadiusInMeter'][0]
    u[2][:] = sorted([p for p in u[2] if p[1] != 'RadiusInMeter'] + [(r_idx, 'RadiusInMeter', False,
                     ('raw', 'Float', struct.pack('<f', survival_events.AREA_RADIUS_M)))], key=lambda p: p[0])


def ladon_units(units, used_ids, z, top_number, v):
    """The Ladons (survival_events.LADON*): Mission 16's Ladon desc with its parts, once per Ladon, at the start of
    its route, on its own mission row; its route and its circuit round the airfield."""
    m16z = ZenPkg(stock(M16 + 'WD_Mission016_global'))
    i = m16z.export_index('WD_Mission016_global')
    m16, _ = props_of(m16z, i, 'LiveWorldData')
    src = desc_named(m16, 'UnitDescList', survival_events.LADON_SOURCE_UNIT)
    src_path = desc_named(m16, 'AIPathDescList', survival_events.LADON_SOURCE_PATH)
    paths = [p for p in v[2] if p[1] == 'AIPathDescList'][0][3][1]
    import math
    pz = ZenPkg(stock(survival_events.LADON_PULSE_WD))       # the pulse cannon pod's class (survival_events.LADON_PULSE_*)
    pw, _ = props_of(pz, pz.export_index(survival_events.LADON_PULSE_WD.rsplit('/', 1)[1]), 'LiveWorldData')
    pref = None
    for pu in [q for q in pw[2] if q[1] == 'UnitDescList'][0][3][1]:
        for pob in [q for q in pu[2] if q[1] == 'AIObjectDescList'][0][3][1]:
            pk = [q for q in pob[2] if q[1] == 'ChildAIObjectDescs']
            for ch in (pk[0][3][1] if pk and pk[0][3] else []):
                data = [p for p in ch[2] if p[1] == 'Data'][0][3][2]
                if [q for q in data if q[1] == 'ComponentFieldName'][0][3][1] == survival_events.LADON_PULSE_PART:
                    pref = [q for q in data if q[1] == 'Class'][0][3]
    assert pref and pref[0] == 'obj' and pref[1] < 0, pref
    for L in survival_events.ladons():
        (x0, y0, z0), (x1, y1, _) = L['route'][0], L['route'][1]
        yaw = math.degrees(math.atan2(y1 - y0, x1 - x0))
        names = port_unit(units, used_ids, z, src, L['unit'], L['obj'], L['row'], [L['route'][0]], yaw, top_number)
        assert names == [L['obj']], names
        u = [u for u in units if [p for p in u[2] if p[1] == 'Name'][0][3][1] == L['unit']][0]
        ob = [p for p in u[2] if p[1] == 'AIObjectDescList'][0][3][1][0]
        kids = [p for p in ob[2] if p[1] == 'ChildAIObjectDescs'][0][3][1]
        parts = retag_parts(kids, L['obj'], used_ids, z, m16z)
        pulse = 0                                          # the CIWS slots: the Arsenal Bird's pulse cannon pods
        for ch in kids:
            data = [p for p in ch[2] if p[1] == 'Data'][0][3][2]
            comp = [q for q in data if q[1] == 'ComponentFieldName'][0][3][1]
            if comp in survival_events.LADON_CIWS:
                data[:] = [(q[0], q[1], False, import_from(z, pz, pref)) if q[1] == 'Class' and q[3] is not None else q for q in data]
                pulse += 1
        assert pulse == len(survival_events.LADON_CIWS), pulse
        # its area over the whole job (survival_events.LADON_AREA), not 40 km round the far-west spawn
        (ax, ay), radius = survival_events.LADON_AREA
        r_idx = [k for k, (n, t) in uprop.U.schema('LiveUnitDesc').items() if n == 'RadiusInMeter'][0]
        u[2][:] = sorted([q for q in u[2] if q[1] != 'RadiusInMeter'] + [(r_idx, 'RadiusInMeter', False,
                         ('raw', 'Float', struct.pack('<f', radius)))], key=lambda q: q[0])
        u[2][:] = [(q[0], q[1], False, vec(ax * 100000.0, ay * 100000.0, 0.0)) if q[1] == 'SpawnPoint' else q for q in u[2]]
        arc_a, arc_b = L['arc_a_pts'], L['arc_b_pts']
        far = max(math.dist((ax * 100000.0, ay * 100000.0), pt[:2]) for pt in L['route'] + arc_a + arc_b) / 100.0
        assert far < radius * 0.9, (L['unit'], far, radius)
        # smooth: wide banked turns (players saw sharp flat turns with 1.2 km tangents, 2026-10-23); the route runs on
        # into its circuit's arc A, and each arc (survival_events.ladon_circuit, 0.73.73) into the other along the circle
        # (0.73.74) the route runs on into LADON_LAPS laps of its circuit in the same path (no handover: see
        # survival_events.LADON_LAPS); its PathFinish (pass flag, then arc A) comes only when the laps run out
        laps = (arc_a + arc_b) * survival_events.LADON_LAPS
        paths.append(make_path(z, used_ids, src_path, L['path'], L['route'] + laps, smooth=True, after=arc_a[0]))
        paths.append(make_path(z, used_ids, src_path, L['arc_a'], arc_a, smooth=True, before=L['a_before'], after=L['a_after']))
        paths.append(make_path(z, used_ids, src_path, L['arc_b'], arc_b, smooth=True, before=L['b_before'], after=L['b_after']))
        print(f'  ladon: {L["unit"]} ({L["row"]}), {parts} parts, route {len(L["route"])} points + {survival_events.LADON_LAPS} laps in its path + circuit arcs '
              f'{len(arc_a)} + {len(arc_b)}')


def heavy_paths(used_ids, z, v):
    """The heavy bombers' routes in and their figure-8s over the runway (survival_events.heavy_routes): smooth aircraft
    paths on Mission 16's Ladon path, as the Ladons'; the route runs on into its loop, the loop (it ends over the runway
    and starts 2 km past the route's end) into itself."""
    m16z = ZenPkg(stock(M16 + 'WD_Mission016_global'))
    m16, _ = props_of(m16z, m16z.export_index('WD_Mission016_global'), 'LiveWorldData')
    src_path = desc_named(m16, 'AIPathDescList', survival_events.LADON_SOURCE_PATH)
    paths = [p for p in v[2] if p[1] == 'AIPathDescList'][0][3][1]
    hs = survival_events.heavy_routes()
    for H in hs:
        loop = H['circuit']
        paths.append(make_path(z, used_ids, src_path, H['path'], H['route'], smooth=True, after=loop[0]))
        paths.append(make_path(z, used_ids, src_path, H['loop'], loop, smooth=True, before=loop[-1], after=loop[0]))
    # VOID WATCHER 1's orbit (survival_events.awacs_orbit, 0.73.73): the lead-in from the climb-out's end, then its arcs,
    # each into the other; the climb-out's end and way out as survival_events has them
    se = survival_events
    for el in paths:
        f = {p[1]: p[3] for p in el[2]}
        if f['Name'][1:3] == (se.TAKEOFF_LEAD[2], 0):
            last = {p[1]: p[3] for p in f['PathPointDescList'][1][-1][2]}
            pos, tan = struct.unpack('<3d', last['Pos'][2]), struct.unpack('<3d', last['tan'][2])
            break
    else:
        raise LookupError(se.TAKEOFF_LEAD[2])
    assert math.dist(pos, [c * 100000.0 for c in se.AWACS_CLIMB_END]) < 5000.0, ('AWACS_CLIMB_END', pos)
    want = math.atan2(se.AWACS_CLIMB_DIR[1], se.AWACS_CLIMB_DIR[0])
    assert abs(math.remainder(math.atan2(tan[1], tan[0]) - want, 2 * math.pi)) < math.radians(2.0), ('AWACS_CLIMB_DIR', tan)
    o = se.awacs_orbit()
    paths.append(make_path(z, used_ids, src_path, se.AWACS_PATH_IN, o['in'], smooth=True, before=o['in_before'],
                           after=o['in_after']))
    paths.append(make_path(z, used_ids, src_path, se.AWACS_ARC_B, o['arc_b'], smooth=True, before=o['b_before'],
                           after=o['b_after']))
    paths.append(make_path(z, used_ids, src_path, se.AWACS_ARC_A, o['arc_a'], smooth=True, before=o['a_before'],
                           after=o['a_after']))
    # ((0.73.78, G5) its ways home: from each arc's end straight out along its tangent, se.AWACS_OUT_*)
    paths.append(make_path(z, used_ids, src_path, se.AWACS_OUT_B, o['out_b'], smooth=True, before=o['out_b_before'],
                           after=o['out_b_after']))
    paths.append(make_path(z, used_ids, src_path, se.AWACS_OUT_A, o['out_a'], smooth=True, before=o['out_a_before'],
                           after=o['out_a_after']))
    near = sorted({(H['sector'], H['route_km']) for H in hs if H['route_km'] < survival_events.HEAVY_ROUTE_KM})
    print(f'  heavies: {2 * len(hs)} paths ({len(hs)} routes + loops); routes begun nearer: '
          + (', '.join(f'{s} {d:.1f} km' for s, d in near) or 'none'))


M26 = '/Game/Maps/Ingame/Mission026/'


def valka_unit(units, used_ids, z, top_number):
    """VALKA (survival_events.VALKA_*): Mission 26's x40a desc with its parts (laser pod, three railguns), as the Ladons
    are ported, on her ace row (her airframe in the world data too: hard rule 20), her area over the whole zone."""
    m26z = ZenPkg(stock(M26 + 'WD_Mission026_global'))
    m26, _ = props_of(m26z, m26z.export_index('WD_Mission026_global'), 'LiveWorldData')
    src = desc_named(m26, 'UnitDescList', survival_events.VALKA_SOURCE_UNIT)
    (lead, _, _), _ = ace_rows('valka', 'x40a')
    # tgt: a target box and TGT mark (Mission 26's x40a desc has none; test of 2026-10-24: no box on her once she
    # stopped coming hidden, setGone's un-hide had been what gave her one; hard rule 32)
    names = port_unit(units, used_ids, z, src, survival_events.VALKA_UNIT, 'SV_Obj_Valka', lead + '_sv',
                      [(0.0, 0.0, 300000.0)], 0.0, top_number, tgt=True)
    u = [u for u in units if [p for p in u[2] if p[1] == 'Name'][0][3][1] == survival_events.VALKA_UNIT][0]
    ob = [p for p in u[2] if p[1] == 'AIObjectDescList'][0][3][1][0]
    kids = [p for p in ob[2] if p[1] == 'ChildAIObjectDescs'][0][3][1]
    parts = retag_parts(kids, names[0], used_ids, z, m26z)
    for ch in kids:
        data = [p for p in ch[2] if p[1] == 'Data'][0][3][2]
        comp = [q for q in data if q[1] == 'ComponentFieldName'][0][3][1]
        survival_events.VALKA_PARTS[comp] = [q for q in ch[2] if q[1] == 'Name'][0][3][1]
    assert set(survival_events.VALKA_PARTS) >= {survival_events.VALKA_RAILGUN, *survival_events.VALKA_IDLE_PARTS}, survival_events.VALKA_PARTS
    zone_area(u)
    survival_events.VALKA_OBJ = names[0]
    print(f'  valka: {names[0]} in {survival_events.VALKA_UNIT} ({lead}_sv), {parts} parts: {survival_events.VALKA_PARTS}')


def valka_eml_unit(units, used_ids, z, top_number):
    """VALKA's opener railgun (survival_events.VALKA_EML_*): AC7 Mission 18 fires its opener from a hidden dummy
    railgun of its own (ms18_dummy_eml_p1, an AITurret_Pawn), not from Mihaly. Ours: the x40a's RailGun part alone
    (its DT_NPC row OP1016_x40a_RG, on mission row VALKA_EML_ROW), on Mission 26's x40a unit desc without its parts
    (an air unit: main.lua spawns it in the sky, 9 km along the player's aim)."""
    m26z = ZenPkg(stock(M26 + 'WD_Mission026_global'))
    m26, _ = props_of(m26z, m26z.export_index('WD_Mission026_global'), 'LiveWorldData')
    src = desc_named(m26, 'UnitDescList', survival_events.VALKA_SOURCE_UNIT)
    names = port_unit(units, used_ids, z, src, survival_events.VALKA_EML_UNIT, survival_events.VALKA_EML_OBJ,
                      survival_events.VALKA_EML_ROW, [(0.0, 0.0, 300000.0)], 0.0, top_number)
    u = [u for u in units if [p for p in u[2] if p[1] == 'Name'][0][3][1] == survival_events.VALKA_EML_UNIT][0]
    ob = [p for p in u[2] if p[1] == 'AIObjectDescList'][0][3][1][0]
    ob[2][:] = [(q[0], q[1], q[2], ('arr', [])) if q[1] == 'ChildAIObjectDescs' else q for q in ob[2]]
    zone_area(u)
    assert names == [survival_events.VALKA_EML_OBJ], names
    print(f'  valka: opener railgun {names[0]} in {survival_events.VALKA_EML_UNIT} ({survival_events.VALKA_EML_ROW} -> {survival_events.VALKA_EML_NPC}), no parts')


EB002 = '/Game/OnlineMode/Maps/EmergencyCall/EB_002/'


def alcn_units(units, used_ids, z, top_number, v):
    """The Alicorn (survival_events.ALCN_*): EB_002's Boss_0 at the start of its lane, without the pools it launches,
    its parts' classes imported (import_from); its ways out and back."""
    import math
    ebz = ZenPkg(stock(EB002 + 'WD_EB_002'))
    i = ebz.export_index('WD_EB_002')
    eb, _ = props_of(ebz, i, 'LiveWorldData')
    src = copy.deepcopy(desc_named(eb, 'UnitDescList', survival_events.ALCN_SOURCE_UNIT))
    ob = [p for p in src[2] if p[1] == 'AIObjectDescList'][0][3][1][0]
    kids = [p for p in ob[2] if p[1] == 'ChildAIObjectDescs'][0][3][1]
    def comp(ch):
        data = [p for p in ch[2] if p[1] == 'Data'][0][3][2]
        return [q for q in data if q[1] == 'ComponentFieldName'][0][3][1]
    dropped = [comp(ch) for ch in kids if comp(ch) in survival_events.ALCN_DROP]
    kids[:] = [ch for ch in kids if comp(ch) not in survival_events.ALCN_DROP]
    paths_def = survival_events.alcn_paths()
    (x0, y0, z0), (x1, y1, _) = paths_def[0][1][0], paths_def[0][1][1]
    names = port_unit(units, used_ids, z, src, survival_events.ALCN_UNIT, survival_events.ALCN_OBJ,
                      survival_events.ALCN_ROW, [(x0, y0, z0)], math.degrees(math.atan2(y1 - y0, x1 - x0)), top_number)
    assert names == [survival_events.ALCN_OBJ], names
    u = [u for u in units if [p for p in u[2] if p[1] == 'Name'][0][3][1] == survival_events.ALCN_UNIT][0]
    ob = [p for p in u[2] if p[1] == 'AIObjectDescList'][0][3][1][0]
    parts = retag_parts([p for p in ob[2] if p[1] == 'ChildAIObjectDescs'][0][3][1], survival_events.ALCN_OBJ, used_ids, z, ebz)
    zone_area(u)
    src_path = desc_named(eb, 'AIPathDescList', survival_events.ALCN_SOURCE_PATH)
    paths = [p for p in v[2] if p[1] == 'AIPathDescList'][0][3][1]
    for name, pts in paths_def:
        paths.append(make_path(z, used_ids, src_path, name, pts))
    print(f'  alicorn: {survival_events.ALCN_UNIT}, {parts} parts ({len(dropped)} pools left out: {", ".join(dropped)})')


# The Alicorn's rows, all Online Mode's (docs/re/ALICORN.md 3, 5): copies of the rows it needs, into Survival tables
# that Scripts/main.lua adds to the campaign tables at the main menu (CFG.specials.alicorn.tables).
ON_NPC = '/Game/OnlineMode/DataTables/AI/NPC/'
ALCN_TABLES = [   # (Online table, row struct, Survival's copy, the campaign table main.lua adds the rows to)
    (ON_NPC + 'DT_NPC_ON', 'LiveNpcDataTable', 'DT_SV_AlcnNpc', '/Game/Datatables/AI/NPC/DT_NPC'),
    (ON_NPC + 'DT_NPC_Model_ON', 'LiveModelDataTable', 'DT_SV_AlcnModel', '/Game/Datatables/AI/NPC/Model/DT_NPC_Model'),
    (ON_NPC + 'DT_NPC_WeaponDurability_ON', 'LiveWeaponDurabilityDataTable', 'DT_SV_AlcnWpDur',
     '/Game/Datatables/AI/NPC/WeaponDurability/DT_NPC_WeaponDurability'),
    (ON_NPC + 'DT_NPC_ExplosionDurability_ON', 'LiveExplosionDurabilityDataTable', 'DT_SV_AlcnExDur',
     '/Game/Datatables/AI/NPC/ExplosionDurability/DT_NPC_ExplosionDurability'),
]


def build_alicorn_rows():
    """DT_SV_Alcn*: the Alicorn's NPC rows (alcn_01 with its pools left out of its children, and every kept part's,
    down the tree), their model rows and the durability rows they name."""
    def load(path, st):
        z = ZenPkg(stock(path))
        dt, o = dtx.parse(uprop.Ctx(bytes(z.payloads[0]), z.names), 0, st)
        assert o == len(z.payloads[0]), path
        return z, dt
    def key(k): return k[0] if k[1] == 0 else f'{k[0]}_{k[1] - 1}'
    def field(row, n):
        q = [q for q in row[2] if q[1] == n]
        return q[0][3] if q else None
    def nm(v): return None if v is None else (v[1] if v[2] == 0 else f'{v[1]}_{v[2] - 1}')
    zn, dn = load(ALCN_TABLES[0][0], ALCN_TABLES[0][1])
    npc = {key(k): (k, row) for k, row in dn['rows']}
    # (and the Arsenal Bird's pulse cannon pod, on the Ladons' CIWS slots: survival_events.LADON_PULSE_NPC)
    # (and THE FESTIVAL's searchlight, C_011's GR053_seli_01 and its light: survival_events.FEST_LIGHT_NPC)
    want, seen, refs = [survival_events.ALCN_ROW, survival_events.LADON_PULSE_NPC, survival_events.FEST_LIGHT_NPC], [], {'ModelId': set(), 'WeaponDurabilityId': set(), 'ExplosionDurabilityId': set()}
    while want:
        r = want.pop(0)
        if r in seen or r in ('None', ''): continue
        seen.append(r)
        row = npc[r][1]
        kids, comps = field(row, 'ChildNPCId'), field(row, 'ChildNPCComponentNames')
        if r == survival_events.ALCN_ROW:        # its pools out
            keep = [i for i, c in enumerate(comps[1]) if nm(c) not in survival_events.ALCN_DROP]
            row[2][:] = [(q[0], q[1], q[2], ('arr', [q[3][1][i] for i in keep])) if q[1] in ('ChildNPCId', 'ChildNPCComponentNames')
                         else q for q in row[2]]
            kids = field(row, 'ChildNPCId')
        for k in (kids[1] if kids else []): want.append(nm(k))
        for f in refs:
            v = field(row, f)
            if v is not None and nm(v) not in ('None', ''): refs[f].add(nm(v))
    keepsets = {0: set(seen), 1: refs['ModelId'], 2: refs['WeaponDurabilityId'], 3: refs['ExplosionDurabilityId']}
    for i, (src, st, out, _) in enumerate(ALCN_TABLES):
        z, dt = (zn, dn) if i == 0 else load(src, st)
        rename_package(z, src, DATA + out)
        rows = [(k, row) for k, row in dt['rows'] if key(k) in keepsets[i]]
        assert {key(k) for k, _ in rows} == keepsets[i], (out, keepsets[i] - {key(k) for k, _ in rows})
        if i == 0:                  # the submarine's parts: Survival's damage table (survival_events.ALCN_PART_* / DURABLE_*)
            n_parts = 0
            for k, row in rows:
                d = nm(field(row, 'WeaponDurabilityId'))
                if key(k) != survival_events.ALCN_ROW and d and d.startswith(survival_events.ALCN_DURABLE_FROM):
                    row[2][:] = [(q[0], q[1], q[2], ('name', survival_events.ALCN_PART_DURABILITY, 0))
                                 if q[1] == 'WeaponDurabilityId' else q for q in row[2]]
                    n_parts += 1
            assert n_parts >= survival_events.ALCN_DURABLE_MIN, n_parts
            print(f'  alicorn: {n_parts} part rows take full damage ({survival_events.ALCN_PART_DURABILITY})')
        if i == 2:                  # ... a copy of NWDID_SubMarine taking full damage from every weapon category
            src_row = [row for k, row in rows if key(k) == survival_events.ALCN_PART_DURABILITY_SOURCE][0]
            new = copy.deepcopy(src_row)
            full = ('raw', 'Float', struct.pack('<f', 100.0))
            new[2][:] = [(q[0], q[1], q[2], full) if q[1].startswith('Category') and q[3] is not None
                         and struct.unpack('<f', q[3][2])[0] < 100.0 else q for q in new[2]]
            rows.append(((survival_events.ALCN_PART_DURABILITY, 0), new))
        for k, row in rows:
            for n in names_in(row) + [k[0]]: z.nb.add(n)
        dt['rows'] = rows
        z.payloads[0] = bytearray(dtx.write(uprop.W(z.names), dt))
        chk, _ = dtx.parse(uprop.Ctx(bytes(z.payloads[0]), z.names), 0, st)
        assert chk['rows'] == dt['rows']
        save(z, DATA + out)
        print(f'  {out}: {len(rows)} rows')


def lcac_units(units, used_ids, z, top_number, v):
    """The amphibious assault (survival_events.LCAC_*): per lane a unit of four landing craft (LCAC_CRAFT) at its start, each
    craft's path in and back out, and per craft a troop unit (one BTR-90) on the beach where it lands."""
    m13 = stock_wd(M13 + 'WD_Mission013_global')
    src_craft = desc_named(m13, 'UnitDescList', survival_events.LCAC_SOURCE_UNIT)
    src_troop = desc_named(m13, 'UnitDescList', survival_events.LCAC_TROOP_SOURCE)
    src_path = desc_named(m13, 'AIPathDescList', survival_events.LCAC_SOURCE_PATH)
    src_drive = desc_named(m13, 'AIPathDescList', survival_events.LCAC_TROOP_SOURCE_PATH)
    paths = [p for p in v[2] if p[1] == 'AIPathDescList'][0][3][1]
    craft = survival_events.lcac_craft()
    for lane in survival_events.lcac_lane_names():
        cs = [c for c in craft if c['lane'] == lane]
        names = port_unit(units, used_ids, z, src_craft, cs[0]['unit'], cs[0]['obj_base'], survival_events.LCAC_ROW,
                          [c['start'] for c in cs], cs[0]['yaw'], top_number, tgt=True)
        assert names == [c['obj'] for c in cs], names
    for c in craft:
        (sx, sy, sz), (bx, by, bz) = c['start'], c['beach']
        at = lambda t, zz: (sx + (bx - sx) * t, sy + (by - sy) * t, zz)
        shore = 1.0 - min(0.08, 60000.0 / c['length'])           # the last point at sea, up to 600 m off the beach
        inbound = [at(0.0, 0.0), at(0.35, sz), at(0.7, sz), at(shore, sz), at(1.0, bz)]
        back = [at(1.0, bz), at(shore, sz), at(0.6, sz), at(0.2, sz), at(-0.3, sz)]   # out past the start
        paths.append(make_path(z, used_ids, src_path, c['path'], inbound))
        paths.append(make_path(z, used_ids, src_path, c['back'], back))
        (gx, gy, gz) = c['runway']                                  # the troops' drive: beach to their runway spot
        gnd = survival_events.LCAC_GROUND_Z
        drive = [(bx, by, bz)] + [(bx + (gx - bx) * t, by + (gy - by) * t, gnd) for t in (0.15, 0.4, 0.65, 0.9)] + [(gx, gy, gz)]
        paths.append(make_path(z, used_ids, src_drive, c['drive'], drive))
        port_unit(units, used_ids, z, src_troop, c['troops'], c['troop_obj'], survival_events.LCAC_TROOP_ROW,
                  [c['beach']], c['yaw'], top_number, tgt=True)
    print(f'  amphibious assault: {len(survival_events.LCAC_LANES)} lanes of {len(survival_events.LCAC_CRAFT)} landing craft, {len(craft) * 3} paths, '
          f'{len(craft)} troop units')


def enemy_unit(u, tgt=True):
    """Unit desc `u` and its AI objects an enemy's (Faction 2, as Training006's missile boats and every stock enemy):
    no tags (they're another mission's or the allies'), and with tgt a target box and the TGT mark on each object."""
    assert any(q[1] == 'Faction' for q in u[2]), 'no Faction on the unit'
    u[2][:] = [(q[0], q[1], False, ('enum', 'ELiveFaction', ('raw', 'Byte', b'\x02'))) if q[1] == 'Faction' else
               (q[0], q[1], False, ('arr', [])) if q[1] == 'Tags' and q[3] is not None else q for q in u[2]]
    sc = uprop.U.schema('LiveAIObjectDesc')
    ix = {n: k for k, (n, t) in sc.items() if n in ('TargetMarkType', 'bShowHUDBox')}
    for ob in [p for p in u[2] if p[1] == 'AIObjectDescList'][0][3][1]:
        ob[2][:] = [(q[0], q[1], False, ('arr', [])) if q[1] == 'Tags' and q[3] is not None else q for q in ob[2]]
        if tgt:
            ob[2][:] = sorted([q for q in ob[2] if q[1] not in ix] + [
                (ix['TargetMarkType'], 'TargetMarkType', False, ('enum', 'ELiveTargetMarkType', ('raw', 'Byte', b'\x01'))),
                (ix['bShowHUDBox'], 'bShowHUDBox', False, ('raw', 'Bool', b'\x01'))], key=lambda q: q[0])


def set_bools(u, names):
    """Every AI object of unit desc `u` with these bool properties true."""
    sc = uprop.U.schema('LiveAIObjectDesc')
    ix = {n: k for k, (n, t) in sc.items() if n in names}
    assert len(ix) == len(names), (names, ix)
    for ob in [p for p in u[2] if p[1] == 'AIObjectDescList'][0][3][1]:
        ob[2][:] = sorted([q for q in ob[2] if q[1] not in ix] + [(ix[n], n, False, ('raw', 'Bool', b'\x01')) for n in names],
                          key=lambda q: q[0])
