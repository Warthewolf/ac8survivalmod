"""build_survival_world.py : the world data's units, part two, and the world data, flag and event packages.

The units of the Spaceport Assault (spaceport_units), the STORE's CIWS (ciws_units), the airfield's split
(split_units: the shuttle's and the pad dummies' own units, the airport's AA guns and SAM sites as the
STORE's defences), GONE FISHIN' and THE FESTIVAL
(fishing_units, festival_units and their helpers unit_named, objects_of, place, ...), THE ESCORT, its cargo
ships and THE DECOY (escort_units, cargo_units, decoy_units); then the global world data (build_wd_global,
which builds every unit above and build_survival_units' in), its flag asset (build_ef) and the event
packages (build_ep: survival_events' graph).

A part of tools/build_survival.py (its docstring has the layout): every name build_survival defines is here
through the import below, and build_survival imports this part back whole, so each name here is
build_survival.<name> too. Import build_survival (or run it), not this file.
"""
from build_survival import *  # noqa: F401,F403 (build_survival's names; it imports this part at its end)


def spaceport_units(units, used_ids, z, top_number, v):
    """The Spaceport Assault (survival_events.SP_*): the enemy fleet (14 Aegis, 4 Wasps, 8 missile boats and the Ford,
    each a one-ship unit at its spot), each lane's waves of landing craft and their paths, each craft's troops
    (invincible, no box) and their drive to the troops' spot, and the retake's garrison (targetable)."""
    import math
    unit_by = lambda n: [u for u in units if [p for p in u[2] if p[1] == 'Name'][0][3][1] == n][0]
    objects = lambda u: [p for p in u[2] if p[1] == 'AIObjectDescList'][0][3][1]
    kids = lambda ob: ([p for p in ob[2] if p[1] == 'ChildAIObjectDescs'] or [(0, 0, 0, None)])[0][3]
    def face(u, yaw):
        for ob in objects(u):
            ob[2][:] = [(q[0], q[1], False, vec(0.0, yaw, 0.0, 'Rotator')) if q[1] == 'Rotation' else q for q in ob[2]]
    def load(pkg):
        zs = ZenPkg(stock(pkg))
        w, _ = props_of(zs, zs.export_index(pkg.rsplit('/', 1)[1]), 'LiveWorldData')
        return zs, w
    wz, ww = load(survival_events.SP_WASP_SOURCE[0])
    bz_, bw = load(survival_events.SP_BOAT_SOURCE[0])
    fz, fw = load(survival_events.SP_FORD_SOURCE[0])
    src_wasp = desc_named(ww, 'UnitDescList', survival_events.SP_WASP_SOURCE[1])
    src_boat = desc_named(bw, 'UnitDescList', survival_events.SP_BOAT_SOURCE[1])
    src_ford = desc_named(fw, 'UnitDescList', survival_events.SP_FORD_SOURCE[1])
    turret = {src: mrow for src, mrow, _, _ in survival_events.SP_TURRETS}   # each turret on its own row (SP_TURRETS)
    assert all(m in NPC_ROWS for m in turret.values()), [m for m in turret.values() if m not in NPC_ROWS]
    rows = dict((r, turret[r]) for r in survival_events.ALLY_TURRETS['Aegis'])
    ford_rows = {f'VE004_grfd_mk15_{p}_Ally_01': (turret[f'VE004_grfd_mk15_{p}_Ally_01'], f'Mk15{p}') for p in ('LB', 'RF', 'LF', 'RB')}
    count = {}
    for s in survival_events.sp_fleet():
        kind, unit, obj = s['kind'], s['unit'], s['obj']
        count[kind] = count.get(kind, 0) + 1
        if kind == 'aegis':                    # Survival's own copy of Mission 22's allied Aegis, made an enemy
            names = copy_unit(units, used_ids, z, survival_events.SP_AEGIS_SOURCE, unit, 1, top_number, obj,
                              survival_events.SP_AEGIS_ROW)
            u = unit_by(unit)
            clear_flags(u, ('bIsAttackTargetsException',))
            retag_turrets(kids(objects(u)[0])[1], obj, rows, used_ids, z)
            set_unit_point(u, s['point'])
        elif kind == 'wasp':                   # Mission 28's (allied, invincible, an attack-target exception)
            names = port_unit(units, used_ids, z, src_wasp, unit, obj, 'sv_sp_wasp', [s['point']], s['yaw'], top_number, tgt=True)
            u = unit_by(unit)
            clear_flags(u, ('bIsInvincible', 'bIsAttackTargetsException', 'bShowCallSignForAlly'))
        elif kind == 'boat':                   # Training006's (enemy already): its first boat, its SAM launcher
            names = port_unit(units, used_ids, z, src_boat, unit, obj, 'sv_sp_boat', [s['point']], s['yaw'], top_number, tgt=True)
            u = unit_by(unit)
            ks = kids(objects(u)[0])
            assert ks and len(ks[1]) == 1, unit
            retag_parts(ks[1], obj, used_ids, z, bz_)
            for ch in ks[1]:
                data = [p for p in ch[2] if p[1] == 'Data'][0][3][2]
                was = [q for q in data if q[1] == 'MissionNpcID'][0][3][1]
                data[:] = [(q[0], q[1], False, ('name', turret[was], 0)) if q[1] == 'MissionNpcID' else q for q in data]
                z.nb.add(turret[was])
        else:                                  # the Ford: Mission 16's (allied Grindylow), its four Mk 15s
            names = port_unit(units, used_ids, z, src_ford, unit, obj, 'sv_sp_ford', [s['point']], s['yaw'], top_number, tgt=True)
            u = unit_by(unit)
            clear_flags(u, ('bIsLanding', 'bShowCallSignForAlly'))
            u[2][:] = [(q[0], q[1], True, None) if q[1] == 'bIsEscortedUnit' else q for q in u[2]]
            ks = kids(objects(u)[0])
            assert ks and len(ks[1]) == 4, unit
            for ch in ks[1]:                   # (their components end in digits, _01.._04: named by their place instead)
                data = [p for p in ch[2] if p[1] == 'Data'][0][3][2]
                row = [q for q in data if q[1] == 'MissionNpcID'][0][3][1]
                new_row, place = ford_rows[row]
                data[:] = [(q[0], q[1], False, ('name', new_row, 0)) if q[1] == 'MissionNpcID' else
                           (q[0], q[1], False, import_from(z, fz, q[3])) if q[1] == 'Class' and q[3] is not None else q
                           for q in data]
                name = f'{obj}_{place}'
                uid = new_unique_id(used_ids, 'AC8SurvivalMode:' + name)
                ch[2][:] = [(q[0], q[1], False, ('name', name, 0)) if q[1] == 'Name' else
                            (q[0], q[1], False, ('raw', 'UInt32', uid)) if q[1] == 'UniqueID' else
                            (q[0], q[1], False, ('name', 'WD_SurvivalMode_global', 0)) if q[1] == 'WorldDataName' and q[3] is not None
                            else q for q in ch[2]]
                for n in names_in(ch): z.nb.add(n)
        assert names == [obj], (unit, names)
        def part_names(children):              # (its turrets as event args write them: survival_events.sp_parts orders them)
            out = []
            for ch in children:
                n = [q for q in ch[2] if q[1] == 'Name'][0][3]
                out.append(n[1] if n[2] == 0 else f'{n[1]}_{n[2] - 1}')
                gc = [q for q in ch[2] if q[1] == 'GrandChildrens']
                if gc and gc[0][3]: out += part_names(gc[0][3][1])
            return out
        got = part_names((kids(objects(u)[0]) or (0, []))[1])
        assert sorted(got) == sorted(survival_events.sp_parts(s)), (unit, got, survival_events.sp_parts(s))
        enemy_unit(u)
        face(u, s['yaw'])
        unit_area(u, survival_events.SP_SHIP_AREA_M, survival_events.SP_SHIP_ALT_M)
    # the landing craft (Mission 13's, as lcac_units) and their troops
    m13 = stock_wd(M13 + 'WD_Mission013_global')
    src_craft = desc_named(m13, 'UnitDescList', survival_events.LCAC_SOURCE_UNIT)
    src_troop = desc_named(m13, 'UnitDescList', survival_events.LCAC_TROOP_SOURCE)
    src_path = desc_named(m13, 'AIPathDescList', survival_events.LCAC_SOURCE_PATH)
    src_drive = desc_named(m13, 'AIPathDescList', survival_events.LCAC_TROOP_SOURCE_PATH)
    paths = [p for p in v[2] if p[1] == 'AIPathDescList'][0][3][1]
    craft = survival_events.sp_craft()
    waves = []
    for c in craft:
        if c['unit'] not in waves: waves.append(c['unit'])
    for wu in waves:
        cs = [c for c in craft if c['unit'] == wu]
        names = port_unit(units, used_ids, z, src_craft, wu, cs[0]['obj_base'], survival_events.LCAC_ROW,
                          [c['start'] for c in cs], cs[0]['yaw'], top_number, tgt=True)
        assert names == [c['obj'] for c in cs], names
    for c in craft:
        (sx, sy, sz), (bx, by, bz) = c['start'], c['beach']
        at = lambda t, zz: (sx + (bx - sx) * t, sy + (by - sy) * t, zz)
        shore = 1.0 - min(0.08, 60000.0 / c['length'])           # the last point at sea, up to 600 m off the beach
        paths.append(make_path(z, used_ids, src_path, c['path'], [at(0.0, 0.0), at(0.35, sz), at(0.7, sz), at(shore, sz), at(1.0, bz)]))
        paths.append(make_path(z, used_ids, src_path, c['back'], [at(1.0, bz), at(shore, sz), at(0.6, sz), at(0.2, sz), at(-0.05, sz)]))
        (gx, gy, gz) = c['spot']
        gnd = survival_events.LCAC_GROUND_Z
        drive = [(bx, by, bz)] + [(bx + (gx - bx) * t, by + (gy - by) * t, gnd) for t in (0.25, 0.5, 0.75)] + [(gx, gy, gz)]
        paths.append(make_path(z, used_ids, src_drive, c['drive'], drive))
        port_unit(units, used_ids, z, src_troop, c['troops'], c['troop_obj'], survival_events.LCAC_TROOP_ROW,
                  [c['beach']], c['yaw'], top_number)
        set_bools(unit_by(c['troops']), ('bIsInvincible', 'bIsAttackTargetsException'))   # (this round: can't be shot)
    lane = desc_named(v, 'AIPathDescList', survival_events.SP_BOAT_PATH_TEMPLATE)   # the boats' patrols (a ship lane's shape)
    boats = [s for s in survival_events.sp_fleet() if s['kind'] == 'boat']
    for s in boats:
        paths.append(make_path(z, used_ids, lane, s['out_path'], s['out_pts']))
        paths.append(make_path(z, used_ids, lane, s['back_path'], s['back_pts']))
    for unit, obj, pts in survival_events.sp_garrison():          # the retake's: on the spot, targets
        port_unit(units, used_ids, z, src_troop, unit, obj, survival_events.LCAC_TROOP_ROW, pts, 180.0, top_number, tgt=True)
    # the retake's rockets and their debris (survival_events.SP_ROCKET_* / SP_DEBRIS): Mission 19's, where it has them
    m19 = stock_wd(survival_events.SP_ROCKET_SOURCE[0])
    spot = lambda ob: struct.unpack('<3d', [q for q in ob[2] if q[1] == 'SpawnPoint'][0][3][2])
    src_r = desc_named(m19, 'UnitDescList', survival_events.SP_ROCKET_SOURCE[1])
    obj_r = survival_events.SP_ROCKET_OBJ
    names = port_unit(units, used_ids, z, src_r, survival_events.SP_ROCKET_UNIT, obj_r, survival_events.SP_ROCKET_ROW,
                      [spot(ob) for ob in objects(src_r)], 0.0, top_number, keep_rotation=True)
    assert names == [f'{obj_r}_0', f'{obj_r}_1'], names
    unit_area(unit_by(survival_events.SP_ROCKET_UNIT), survival_events.SP_ROCKET_AREA_M, survival_events.SP_ROCKET_ALT_M)
    for src_p, new_p in survival_events.SP_ROCKET_PATHS:
        paths.append(copy_path(z, used_ids, desc_named(m19, 'AIPathDescList', src_p), new_p))
    for src_u, unit, obj, rws in survival_events.SP_DEBRIS:
        su = desc_named(m19, 'UnitDescList', src_u)
        names = port_unit(units, used_ids, z, su, unit, obj, rws[0][0], [spot(ob) for ob in objects(su)], 0.0, top_number,
                          rows=[r[0] for r in rws], keep_rotation=True, digit_ok=True)
        assert names == [f'{obj}_0', f'{obj}_1'], names   # (as Mission 19 stores them: its rocket's blueprint looks them up)
    # the retake's island enemies (survival_events.sp_island: their spots past tools/spaceport_spots.py's building check)
    for u in survival_events.sp_island():
        su = desc_named(stock_wd(u['src'][0]), 'UnitDescList', u['src'][1])
        if not u['clone_first']:                             # (the EXSAM site: its objects as Mission 6 has them)
            got = [nm for nm in [[q for q in ob[2] if q[1] == 'MissionNpcID'][0][3][1] for ob in objects(su)]]
            assert got[:1] == ['exsamsr_common'] and got[1:5] == ['exsam_MS06'] * 4, got
        names = port_unit(units, used_ids, z, su, u['unit'], u['obj'], u['rows'][0], u['points'], u['yaw'], top_number,
                          tgt=True, rows=u['rows'], clone_first=u['clone_first'])
        assert len(names) == len(u['points']), (u['unit'], names)
        unit_area(unit_by(u['unit']), survival_events.SP_ISLAND_AREA_M, survival_events.SP_ISLAND_ALT_M)
    print(f'  spaceport assault: ' + ', '.join(f'{n} {k}' for k, n in count.items()) + f'; {len(waves)} landing waves '
          f'({len(craft)} craft, {len(craft) * 3} paths, {len(craft)} troop units), {len(boats)} boat patrols, '
          f'{len(survival_events.sp_garrison())} garrison units; the retake: 2 rockets on 2 climbs, '
          f'{len(survival_events.SP_DEBRIS)} debris units, '
          + ', '.join(f'{u["unit"][len("SV_Unit_SpIsl"):]} {len(u["points"])}' for u in survival_events.sp_island()))


def ciws_units(units, used_ids, z, top_number):
    """The STORE's CIWS (survival_events.DEFENCE_CIWS*): one-object units copied from Survival's first AA gun unit
    (Mission 22's allied airport unit: faction 1, its tags, its ground objects' flags, the defences' area), each at its
    spot by the runway, facing along it, on the CIWS's mission row. Allied as the AA guns are: by the unit's faction
    (Mission 22's own allied AA guns, SAM sites and Aegis turrets fly the plain blueprints, no _Ally ones)."""
    unit_by = lambda n: [u for u in units if [p for p in u[2] if p[1] == 'Name'][0][3][1] == n][0]
    src = unit_by(survival_events.DEFENCE_CIWS_SOURCE_UNIT)
    assert [p for p in src[2] if p[1] == 'Faction'][0][3] == ('enum', 'ELiveFaction', ('raw', 'Byte', b'\x01')), 'not allied'
    for unit, obj, point, yaw in survival_events.defence_ciws():
        names = copy_unit(units, used_ids, z, survival_events.DEFENCE_CIWS_SOURCE_UNIT, unit, 1, top_number, obj,
                          survival_events.DEFENCE_CIWS_ROW[0])
        assert names == [obj], names
        u = unit_by(unit)
        set_unit_point(u, point)
        for ob in [p for p in u[2] if p[1] == 'AIObjectDescList'][0][3][1]:
            assert any(q[1] == 'Rotation' and q[3] for q in ob[2]), unit
            ob[2][:] = [(q[0], q[1], False, vec(0.0, yaw, 0.0, 'Rotator')) if q[1] == 'Rotation' else q for q in ob[2]]
    print(f'  CIWS: {len(survival_events.DEFENCE_CIWS)} units from {survival_events.DEFENCE_CIWS_SOURCE_UNIT} on '
          f'{survival_events.DEFENCE_CIWS_ROW[0]}: ' + ', '.join(f'{o} ({p[0] / 1e5:.3f}, {p[1] / 1e5:.3f}) km'
                                                                   for _, o, p, _ in survival_events.defence_ciws()))


def split_units(units, used_ids, z, top_number):
    """Comona Defense (survival_events.SHUTTLE_*): the shuttle gets a unit of its own, spawned every special, and the
    pad's invincible dummies one of theirs (PAD_DUMMY_UNIT, spawned once a run: a unit with anything alive can't be
    spawned again), so Mission 22's pad unit keeps only what can be destroyed (AA guns, SAMs, tower: removed after
    each special). Airfield defences (survival_events.DEFENCES): each of Mission 22's airport AA guns and SAM sites
    becomes a one-object unit the shop can build."""
    move_object(units, used_ids, z, survival_events.PAD_UNIT, survival_events.SHUTTLE, survival_events.SHUTTLE_UNIT,
                survival_events.SHUTTLE_NPC_ROW)
    # Mission 22's shuttle is an attack-target exception (bIsAttackTargetsException): no AI ever aims at it (its
    # "attacks" are scripted near misses), so Survival's strike flights circled it without a shot (test of 2026-10-23:
    # 0 hits in 150 s, 1.4-3.3 km out). Survival's copy can be attacked.
    clear_flags([u for u in units if [p for p in u[2] if p[1] == 'Name'][0][3][1] == survival_events.SHUTTLE_UNIT][0],
                ('bIsAttackTargetsException',))
    left = move_object(units, used_ids, z, survival_events.PAD_UNIT, survival_events.PAD_DUMMIES, survival_events.PAD_DUMMY_UNIT)
    print(f'  shuttle: {survival_events.SHUTTLE} in {survival_events.SHUTTLE_UNIT} (NPC row {survival_events.SHUTTLE_NPC_ROW}), '
          f'{len(survival_events.PAD_DUMMIES)} dummies in {survival_events.PAD_DUMMY_UNIT}; {survival_events.PAD_UNIT} keeps {left} objects')
    unit_by = lambda n: [u for u in units if [p for p in u[2] if p[1] == 'Name'][0][3][1] == n][0]
    for new_unit, obj, mrow in survival_events.DEFENCES:
        move_object(units, used_ids, z, survival_events.DEFENCE_SOURCE, obj, new_unit, survival_events.DEFENCE_ROWS[mrow][0])
        # (0.72.1: an area their longer lock-on and search fit in, survival_events.DEFENCE_AREA_M)
        unit_area(unit_by(new_unit), survival_events.DEFENCE_AREA_M, survival_events.DEFENCE_ALT_M)
    print(f'  airfield defences: {len(survival_events.DEFENCES)} units from {survival_events.DEFENCE_SOURCE}, area '
          f'{survival_events.DEFENCE_AREA_M:.0f} m, {survival_events.DEFENCE_ALT_M[0]:.0f}-{survival_events.DEFENCE_ALT_M[1]:.0f} m up')
    ciws_units(units, used_ids, z, top_number)
    # The Anomaly (survival_events.ANOMALY_*): MINDRIPPER alone, and its guards
    # (user, 2026-10-22: "make mindripper an F-4": its NPC row is the F-4E one in the world data too, not only at spawn)
    (lead, _, _), (wing, _, _) = ace_rows('anomaly', 'f04e')
    ace = copy_unit(units, used_ids, z, survival_events.ANOMALY_SOURCE, survival_events.ANOMALY_UNIT, 1, top_number,
                    'SV_Obj_Mindripper', lead + '_sv')
    guards = copy_unit(units, used_ids, z, survival_events.ANOMALY_SOURCE, survival_events.ANOMALY_GUARD_UNIT,
                       survival_events.ANOMALY_GUARDS, top_number, 'SV_Obj_AnomalyGuard', wing + '_sv')
    survival_events.ANOMALY_OBJ = ace[0]
    print(f'  anomaly: {ace[0]} in {survival_events.ANOMALY_UNIT}, guards {guards} in {survival_events.ANOMALY_GUARD_UNIT}')
    # AB.L..IN (survival_events.GLITCH_*): the EA-18G alone, on its ace row (its airframe in the world data too)
    (glead, _, _), _ = ace_rows('glitch', 'e18g')
    gl = copy_unit(units, used_ids, z, survival_events.ANOMALY_SOURCE, survival_events.GLITCH_UNIT, 1, top_number,
                   'SV_Obj_Glitch', glead + '_sv')
    survival_events.GLITCH_OBJ = gl[0]
    print(f'  glitch: {gl[0]} in {survival_events.GLITCH_UNIT}')


# ---------------------------------------------------------------- GONE FISHIN' and THE FESTIVAL (2026-11-06)
def unit_named(units, name):
    """Unit desc `name`, the string SV_Spawn names it by (a digit tail split as the engine splits it: survival_events.fname)."""
    want = survival_events.fname(name)[1:]
    hit = [u for u in units if tuple([p for p in u[2] if p[1] == 'Name'][0][3][1:3]) == want]
    assert len(hit) == 1, (name, len(hit))
    return hit[0]


def objects_of(u):
    return [p for p in u[2] if p[1] == 'AIObjectDescList'][0][3][1]


def put(props, schema, name, value):
    """Property `name` of a desc (struct `schema`) set to `value`: replaced where it's there (None too: an explicit zero) or
    added at its schema index (unversioned properties are written in index order)."""
    idx = [k for k, (n, t) in uprop.U.schema(schema).items() if n == name]
    assert len(idx) == 1, (schema, name)
    props[:] = sorted([q for q in props if q[1] != name] + [(idx[0], name, False, value)], key=lambda q: q[0])


def place(u, point, yaw, obj_points=None):
    """Unit desc `u` at `point` facing `yaw`, and its AI objects at obj_points facing yaw: every SpawnPoint and Rotation
    written, also where the source has none (Mission 30's missile unit: spawned by its mission at a moved unit). SV_Spawn's
    SetPose (runtime/survival_rt.c) keeps each object's offset from the unit point, z too, and turns it by the yaw given
    less the unit's: so the objects' z here is the unit's (offset z 0), and the unit's yaw the one Lua spawns it with."""
    put(u[2], 'LiveUnitDesc', 'SpawnPoint', vec(*point))
    put(u[2], 'LiveUnitDesc', 'Rotation', vec(0.0, yaw, 0.0, 'Rotator'))
    if obj_points is not None:
        objs = objects_of(u)
        assert len(obj_points) == len(objs), (len(obj_points), len(objs))
        for ob, pt in zip(objs, obj_points):
            put(ob[2], 'LiveAIObjectDesc', 'SpawnPoint', vec(*pt))
            put(ob[2], 'LiveAIObjectDesc', 'Rotation', vec(0.0, yaw, 0.0, 'Rotator'))


def spot_of(d):
    return struct.unpack('<3d', [q for q in d[2] if q[1] == 'SpawnPoint'][0][3][2])


def field_of(d, name):
    q = [q for q in d[2] if q[1] == name]
    return q[0][3] if q else None


def fishing_units(units, used_ids, z, top_number):
    """GONE FISHIN' (survival_events.FISH_* / SAL_BOAT_*): units of FISH_PER_GROUND shoals round SAL's boat (one on it),
    from Mission 13's scored dummy unit (faction 2, a box and the TGT mark: hard rules 31, 32), each unit's origin on its
    ground 7 m up and its shoals round it at that height (bIsLanding cleared: placed, not set down on the sea), on
    sv_shoal; and SAL's boat, Mission 28's allied Wasp desc on the stock fishing boat, its callsign as VOID WATCHER's."""
    se = survival_events
    src = desc_named(stock_wd(se.FISH_SOURCE[0]), 'UnitDescList', se.FISH_SOURCE[1])
    assert [field_of(ob, 'MissionNpcID')[1] for ob in objects_of(src)] == ['Dummy_btr9_common'], 'Mission 13 score unit changed'
    assert field_of(src, 'Faction') == ('enum', 'ELiveFaction', ('raw', 'Byte', b'\x02')), field_of(src, 'Faction')
    for key, unit, obj, (gx, gy), pts in se.fish_units():
        names = port_unit(units, used_ids, z, src, unit, obj, se.FISH_ROW, pts, 0.0, top_number, tgt=True)
        assert names == [f'{obj}_{k}' for k in range(se.FISH_PER_GROUND)], names
        u = unit_named(units, unit)
        clear_flags(u, ('bIsLanding',))
        place(u, (gx, gy, se.FISH_Z_CM), 0.0)
        at = [spot_of(ob) for ob in objects_of(u)]
        assert all(abs(p[2] - se.FISH_Z_CM) < 0.5 and math.hypot(p[0] - gx, p[1] - gy) <= se.FISH_SPREAD_M * 100.0 for p in at), at
        gap = min(math.dist(a[:2], b[:2]) for i, a in enumerate(at) for b in at[i + 1:])
        assert gap >= se.FISH_GAP_M * 100.0, (unit, gap)
        if key == se.FISH_KEYS[0]:                            # (on SAL's boat: its shoals clear of it at any yaw)
            assert all(math.hypot(p[0] - gx, p[1] - gy) >= se.FISH_INNER_MIN_M * 100.0 - 1 for p in at), (unit, at)
        assert all(field_of(ob, 'TargetMarkType') and field_of(ob, 'bShowHUDBox') == ('raw', 'Bool', b'\x01')
                   and not field_of(ob, 'bIsLanding') for ob in objects_of(u)), unit
        far = max(math.hypot(p[0] - gx, p[1] - gy) for p in at) / 100.0
        print(f'  fishing: {unit} ({len(names)} {obj}_N on {se.FISH_ROW}) at ({gx:.0f}, {gy:.0f}, {se.FISH_Z_CM:.0f}), '
              f'out to {far:.0f} m, {gap / 100.0:.0f} m apart at least')
    ww = stock_wd(se.SP_WASP_SOURCE[0])
    src = desc_named(ww, 'UnitDescList', se.SP_WASP_SOURCE[1])
    assert field_of(src, 'Faction') == ('enum', 'ELiveFaction', ('raw', 'Byte', b'\x01')), 'Mission 28 Wasp not allied'
    names = port_unit(units, used_ids, z, src, se.SAL_BOAT_UNIT, se.SAL_BOAT_OBJ, se.SAL_BOAT_ROW, [se.SAL_BOAT_SPOT],
                      se.SAL_BOAT_YAW, top_number)
    assert names == [se.SAL_BOAT_OBJ], names
    u = unit_named(units, se.SAL_BOAT_UNIT)
    clear_flags(u, ('bIsInvincible',))
    set_bools(u, ('bIsInvincibleFromAI', 'bIsInvincibleFromWingman', 'bShowHUDBox', 'bShowCallSignForAlly'))
    ob = objects_of(u)[0]
    put(ob[2], 'LiveAIObjectDesc', 'GameObjectDisplayNameID02', ('name', se.SAL_BOAT_NAME_KEY, 0))
    z.nb.add(se.SAL_BOAT_NAME_KEY)
    place(u, se.SAL_BOAT_SPOT, se.SAL_BOAT_YAW)
    kids = (field_of(ob, 'ChildAIObjectDescs') or ('arr', []))[1]
    assert spot_of(ob) == se.SAL_BOAT_SPOT and not field_of(ob, 'bIsInvincible') and not kids, se.SAL_BOAT_UNIT
    print(f'  fishing: SAL\'s boat {se.SAL_BOAT_UNIT} ({se.SAL_BOAT_OBJ} on {se.SAL_BOAT_ROW} -> {se.SAL_BOAT_NPC}, callsign '
          f'{se.SAL_BOAT_NAME_KEY}, allied, invincible from AI and wingmen) at {se.SAL_BOAT_SPOT}')


def festival_units(units, used_ids, z, top_number, v):
    """THE FESTIVAL (survival_events.FEST_*): three 4-ship Tu-160 formations (copies of Survival's heavy flight), each at
    its entry facing the runway, a lane per aircraft (its path and one outside it) of its run in and FEST_LAPS racetrack
    laps (smooth aircraft paths: hard rules 35, 54); the salvo units of Mission 30's path-flown cruise missile at their
    launch points, side by side, a box and the TGT mark each, and their lanes to the runway; and the four searchlights,
    C_011's searchlight vehicle with its light (its class imported from C_011's world data), allied, by the runway."""
    se = survival_events
    tpl = desc_named(stock_wd(M16 + 'WD_Mission016_global'), 'AIPathDescList', se.LADON_SOURCE_PATH)
    paths = [p for p in v[2] if p[1] == 'AIPathDescList'][0][3][1]
    (zx, zy), half = se.FEST_ZONE
    lim = half - se.FEST_ZONE_MARGIN_KM * 1e5
    for F in se.fest_bombers():
        names = copy_unit(units, used_ids, z, se.FEST_SOURCE_UNIT, F['unit'], se.FEST_BOMBERS_N, top_number, F['obj'],
                          se.FEST_BOMBER_ROW)
        assert names == F['objs'], names
        u = unit_named(units, F['unit'])
        assert field_of(u, 'Faction') == ('enum', 'ELiveFaction', ('raw', 'Byte', b'\x02')), F['unit']
        assert field_of(objects_of(u)[0], 'bGroupLead') == ('raw', 'Bool', b'\x01'), F['unit']
        place(u, F['entry'], F['yaw'], F['points'])
        unit_area(u, se.FEST_AREA_M, se.FEST_ALT_M)
        launch = se.fest_launch(F['g'])
        for name, side in ((F['path'], 0.0), (F['side_path'], se.FEST_FORMATION_CM / 1e5)):
            pts, after = se.fest_track(F['g'], side)
            near = min(math.hypot(p[0] - se.FISH_RWY[0], p[1] - se.FISH_RWY[1]) for p in pts) / 1e5
            assert near >= se.FEST_NEAR_KM, (name, near)
            assert all(abs(p[0] - zx) <= lim and abs(p[1] - zy) <= lim for p in pts), (name, 'outside the zone')
            if not side:
                passes = sum(1 for p in pts if math.hypot(p[0] - launch[0], p[1] - launch[1]) < 1.0)
                assert passes == se.FEST_LAPS + 1, (name, passes)
                assert math.dist(pts[0], F['points'][0]) < 1.0, name
            else:
                assert math.dist(pts[0], F['points'][1]) < 1.0, name
            paths.append(make_path(z, used_ids, tpl, name, pts, smooth=True, after=after))
            print(f'  festival: {name}: {len(pts)} points, {se.FEST_LAPS} laps, nearest the runway {near:.1f} km')
    m30 = stock_wd(se.FEST_CM_SOURCE[0])
    src = desc_named(m30, 'UnitDescList', se.FEST_CM_SOURCE[1])
    sob = objects_of(src)
    assert len(sob) == 1 and field_of(sob[0], 'MissionNpcID')[1] == se.FEST_CM_SOURCE_ROW, 'Mission 30 missile unit changed'
    assert not (field_of(sob[0], 'ChildAIObjectDescs') or ('arr', []))[1], 'Mission 30 missile has parts (hard rule 31)'
    lanes = {}
    for M in se.fest_missiles():
        names = port_unit(units, used_ids, z, src, M['unit'], M['obj'], se.FEST_CM_ROW, M['points'], M['yaw'], top_number,
                          tgt=True, digit_ok=True, unit_digits=True)
        assert names == M['objs'], names
        u = unit_named(units, M['unit'])
        place(u, M['launch'], M['yaw'], M['points'])
        assert all(abs(spot_of(ob)[2] - M['launch'][2]) < 0.5 for ob in objects_of(u)), M['unit']
        for lane, pts in M['lanes']: lanes[lane] = pts
    for lane, pts in lanes.items():
        end = min(math.hypot(p[0] - se.FISH_RWY[0], p[1] - se.FISH_RWY[1]) for p in pts)
        assert end < 15000.0, (lane, end)                 # (the lane crosses the runway, its last point 1.5 km past it)
        paths.append(make_path(z, used_ids, tpl, lane, pts, smooth=True))
    print(f'  festival: {len(se.fest_missiles())} cruise missile salvo units of {se.FEST_CM_PER} ({se.FEST_CM_ROW}), '
          f'{len(lanes)} lanes ({", ".join(sorted(lanes))})')
    lz = ZenPkg(stock(se.FEST_LIGHT_SOURCE[0]))
    lw, _ = props_of(lz, lz.export_index(se.FEST_LIGHT_SOURCE[0].rsplit('/', 1)[1]), 'LiveWorldData')
    src = copy.deepcopy(desc_named(lw, 'UnitDescList', se.FEST_LIGHT_SOURCE[1]))
    seli = [ob for ob in objects_of(src) if field_of(ob, 'MissionNpcID')[1] == se.FEST_LIGHT_SOURCE[2]]
    assert seli, 'C_011 searchlight not found'
    objects_of(src)[:] = seli[:1]
    import festival_lights_check as fl
    bad = fl.failures(se.fest_lights())
    assert not bad, 'festival searchlight spots: ' + '; '.join(bad)
    for unit, obj, pt, yaw in se.fest_lights():
        names = port_unit(units, used_ids, z, src, unit, obj, se.FEST_LIGHT_ROW, [pt], yaw, top_number, unit_digits=True)
        assert names == [obj], names
        u = unit_named(units, unit)
        u[2][:] = [(q[0], q[1], False, ('enum', 'ELiveFaction', ('raw', 'Byte', b'\x01'))) if q[1] == 'Faction' else
                   (q[0], q[1], True, None) if q[1] == 'bRequireRankS' else q for q in u[2]]
        place(u, pt, yaw)
        kids = field_of(objects_of(u)[0], 'ChildAIObjectDescs')[1]
        assert retag_parts(kids, obj, used_ids, z, lz) == 1, unit
        data = [p for p in kids[0][2] if p[1] == 'Data'][0][3][2]
        assert [q for q in data if q[1] == 'ComponentFieldName'][0][3][1] == se.FEST_LIGHT_PART
        assert [q for q in data if q[1] == 'MissionNpcID'][0][3][1] == se.FEST_LIGHT_ROWS[1][1]
        data[:] = [(q[0], q[1], False, ('name', se.FEST_BEAM_ROW, 0)) if q[1] == 'MissionNpcID' else q for q in data]
        assert se.FEST_BEAM_ROW in NPC_ROWS
        z.nb.add(se.FEST_BEAM_ROW)
    print(f'  festival: {len(se.FEST_LIGHTS)} searchlights ({se.FEST_LIGHT_ROW} + its {se.FEST_LIGHT_PART} on '
          f'{se.FEST_BEAM_ROW}), allied: ' + ', '.join(f'{u} ({p[0]:.0f}, {p[1]:.0f})' for u, _, p, _ in se.fest_lights()))
    festival_town(units, used_ids, z, top_number)


FEST_TOWN_SAFE = ('bIsInvincible', 'bIsInvincibleFromAI', 'bIsInvincibleFromWingman', 'bIsAttackTargetsException')


def festival_town(units, used_ids, z, top_number):
    """(2026-11-07) THE FESTIVAL in the town (survival_events.FEST_TOWN_*): Mission 22's invisible dummy (Unit_dummyN0 on
    dummy_common, THE DECOY's marks' source) ported with an object per box, allied, invincible (from AI and wingmen too)
    and out of every attack, each object its own target box and callsign key shown for an ally, 8 m up (bIsLanding
    cleared: placed, not set down)."""
    se = survival_events
    msrc = unit_named(units, se.DECOY_MARK_SOURCE)
    assert [field_of(ob, 'MissionNpcID')[1] for ob in objects_of(msrc)] == [se.DECOY_MARK_ROW], 'Unit_dummyN0 changed'
    spots = se.fest_town()
    names = port_unit(units, used_ids, z, msrc, se.FEST_TOWN_UNIT, se.FEST_TOWN_OBJ, se.DECOY_MARK_ROW, [p for _, p in spots],
                      0.0, top_number, clone_first=True)
    assert names == [f'{se.FEST_TOWN_OBJ}_{k}' for k in range(len(spots))], names
    u = unit_named(units, se.FEST_TOWN_UNIT)
    put(u[2], 'LiveUnitDesc', 'Faction', ('enum', 'ELiveFaction', ('raw', 'Byte', b'\x01')))   # (written where the dummy has none)
    set_bools(u, FEST_TOWN_SAFE)
    clear_flags(u, ('bIsLanding',))
    cx, cy = sum(p[0] for _, p in spots) / len(spots), sum(p[1] for _, p in spots) / len(spots)
    place(u, (round(cx, 1), round(cy, 1), se.FEST_TOWN_Z_CM), 0.0, [p for _, p in spots])
    for ob, (key, _) in zip(objects_of(u), spots):
        put(ob[2], 'LiveAIObjectDesc', 'bShowHUDBox', ('raw', 'Bool', b'\x01'))
        put(ob[2], 'LiveAIObjectDesc', 'bShowCallSignForAlly', ('raw', 'Bool', b'\x01'))
        put(ob[2], 'LiveAIObjectDesc', 'GameObjectDisplayNameID02', ('name', key, 0))
        z.nb.add(key)
    assert not field_of(objects_of(u)[0], 'TargetMarkType'), 'a festival box with a TGT mark'
    gap = min(math.dist(a[:2], b[:2]) for i, (_, a) in enumerate(spots) for _, b in spots[i + 1:]) / 100.0
    print(f'  festival: the town ({se.FEST_TOWN_UNIT}: {len(spots)} invisible, invincible allied boxes on {se.DECOY_MARK_ROW}, '
          f'{len(se.FEST_TOWN_KEYS)} names) round ({cx:.0f}, {cy:.0f}), {gap:.0f} m apart at least')


# ---------------------------------------------------------------- THE ESCORT and THE DECOY (2026-11-06)
def callsign(u, key, z):
    """Every AI object of unit desc `u` with its target box and the callsign `key` shown for an ally (the desc's
    GameObjectDisplayNameID02 with bShowCallSignForAlly: VOID WATCHER 1's and the co-op stand-ins' way); Lua sets the key's
    text (SV_SetText)."""
    for ob in objects_of(u):
        put(ob[2], 'LiveAIObjectDesc', 'bShowHUDBox', ('raw', 'Bool', b'\x01'))
        put(ob[2], 'LiveAIObjectDesc', 'bShowCallSignForAlly', ('raw', 'Bool', b'\x01'))
        put(ob[2], 'LiveAIObjectDesc', 'GameObjectDisplayNameID02', ('name', key, 0))
    z.nb.add(key)


def set_faction(u, faction):
    """Unit desc `u` on side `faction` (1 allied, 2 enemy: ELiveFaction)."""
    assert field_of(u, 'Faction') is not None, 'no Faction on the unit'
    put(u[2], 'LiveUnitDesc', 'Faction', ('enum', 'ELiveFaction', ('raw', 'Byte', bytes([faction]))))


def comp_of(ch):
    data = [p for p in ch[2] if p[1] == 'Data'][0][3][2]
    return [q for q in data if q[1] == 'ComponentFieldName'][0][3][1]


def runway_clear_m(pt):
    """The nearest building or prop box (m, 2D) round the runway (tools/checks/festival_lights_data.json's boxes)."""
    import festival_lights_check as fl
    d = json.load(open(fl.DATA))
    boxes = [dict(zip(('x', 'y', 'yaw', 'hx', 'hy', 'zmax'), b)) for b in d['boxes']]
    return min(fl.dist_to_box(pt[:2], e) for e in boxes) / 100.0


ESC_PARK_CLEAR_M = 30.0        # each parking slot (and its stop path's end) this far from every building or prop box


def escort_units(units, used_ids, z, top_number, v):
    """THE ESCORT (survival_events.ESC_*): CHARLENE (Mission 14's escorted C-130 desc, its wing parts left out, on her row
    sv_charlene, the Attention mark and her callsign), her four escorts (MOONCHILD's lead's desc on their rows, their
    callsigns), every path: her route and each escort's (smooth, one path to the IAF: hard rules 35, 54), the final (the
    3 deg glide slope from the IAF to touchdown), the rollout and the parking slots' taxi and stop paths on the runway's
    7.5 m (MOONCHILD's runway paths' shape: its roll path the template, its taxi path run backwards), each escort's orbit."""
    se = survival_events
    paths = [p for p in v[2] if p[1] == 'AIPathDescList'][0][3][1]
    tpl_air = desc_named(stock_wd(M16 + 'WD_Mission016_global'), 'AIPathDescList', se.LADON_SOURCE_PATH)
    tpl_taxi = desc_named(v, 'AIPathDescList', se.TAKEOFF_LEAD[0])
    route, route_after = se.esc_route_pts()
    yaw = math.degrees(math.atan2(route[1][1] - route[0][1], route[1][0] - route[0][0]))
    # CHARLENE
    src = desc_named(stock_wd(se.ESC_CHAR_SOURCE[0]), 'UnitDescList', se.ESC_CHAR_SOURCE[1])
    assert field_of(src, 'bIsEscortedUnit') == ('raw', 'Bool', b'\x01') and \
        field_of(objects_of(src)[0], 'TargetMarkType') == ('enum', 'ELiveTargetMarkType', ('raw', 'Byte', b'\x03')), 'Mission 14 C-130 changed'
    names = port_unit(units, used_ids, z, src, se.ESC_CHAR_UNIT, se.ESC_CHAR_OBJ, se.ESC_CHAR_ROW, [route[0]], yaw, top_number)
    assert names == [se.ESC_CHAR_OBJ], names
    u = unit_named(units, se.ESC_CHAR_UNIT)
    ob = objects_of(u)[0]
    ob[2][:] = [(q[0], q[1], q[2], ('arr', [])) if q[1] == 'ChildAIObjectDescs' else q for q in ob[2]]   # (the C-130's wings)
    callsign(u, se.ESC_CHAR_NAME_KEY, z)
    unit_area(u, se.ESC_AREA_M, se.ESC_ALT_M)
    place(u, route[0], yaw)
    # her escorts
    msrc = unit_named(units, se.ALLY_AIR_SOURCE)
    for a in se.esc_aircraft()[1:]:
        pts, after = se.esc_route_pts(a['right_km'], a['up_km'])
        names = port_unit(units, used_ids, z, msrc, a['unit'], a['obj'], a['row'], [pts[0]], yaw, top_number)
        assert names == [a['obj']], names
        eu = unit_named(units, a['unit'])
        clear_flags(eu, ('bIsInvincible',))
        callsign(eu, a['name_key'], z)
        unit_area(eu, se.ESC_AREA_M, se.ESC_ALT_M)
        place(eu, pts[0], yaw)
        paths.append(make_path(z, used_ids, tpl_air, a['route'], pts, smooth=True, after=after))
    # the shared paths (2026-11-07): her route on into the final and the rollout, one path (Mission 14's C-130 lands on
    # the path it flew in on); T0's final and rollout alone; the escorts' landing circuit
    final, roll = se.esc_final_pts(), se.esc_roll_pts()
    char, char_after = se.esc_char_pts()
    paths.append(make_path(z, used_ids, tpl_air, se.ESC_PATH_ROUTE, char, smooth=True, after=char_after))
    t0, t0_before, t0_after = se.esc_t0_pts()
    paths.append(make_path(z, used_ids, tpl_air, se.ESC_PATH_FINAL, t0, smooth=True, before=t0_before, after=t0_after))
    circ, circ_before, circ_after = se.esc_circuit_pts()
    paths.append(make_path(z, used_ids, tpl_air, se.ESC_PATH_CIRCUIT, circ, smooth=True, before=circ_before, after=circ_after))
    assert char[len(route) - 1] == route[-1] and char[len(route)] == final[0] and math.dist(char[-1][:2], roll[-1][:2]) < 1.0
    assert all(abs(p[2] - se.ESC_GROUND_Z) < 0.5 for p in char[-len(roll) + 1:])
    # ((2026-11-07) the circuit cut to ~14 km: its downwind at ESC_CIRC_Z_M, then the base turn down onto the 3 deg slope,
    # never below it, ending over 200 m; was "its first 14 points over 450 m", the old 26 km circuit's shape)
    n_dw = int(math.ceil((se.ESC_CIRC_START_T - se.ESC_CIRC_TURN_T - 1.0) / se.ESC_CIRC_STEP_M))
    z_turn_end = se.esc_glide_cm((se.ESC_TOUCH_T - se.ESC_CIRC_TURN_T) / 1000.0)
    turn = circ[n_dw:n_dw + 7]
    assert all(abs(p[2] - se.ESC_CIRC_Z_M * 100.0) < 0.5 for p in circ[:n_dw]) and len(turn) == 7 \
        and all(a[2] >= b[2] for a, b in zip(turn, turn[1:])) and abs(turn[-1][2] - z_turn_end) < 1.0 and z_turn_end > 20000.0, \
        ('the escorts circuit: its downwind at its height, its base turn down onto the 3 deg slope', [p[2] for p in circ[:n_dw + 7]])
    slope = math.degrees(math.atan2(final[0][2] - final[-1][2], math.dist(final[0][:2], final[-1][:2])))
    assert abs(slope - se.ESC_GLIDE_DEG) < 0.05 and abs(final[0][2] - 84602.0) < 100.0, ('the glide slope', slope, final[0])
    assert math.dist(final[-1][:2], se.esc_rwy(se.ESC_TOUCH_T)[:2]) < 1.0 and math.dist(se.esc_rwy(-742.0)[:2], (1541439, -406838)) < 100.0
    # the taxi: from 22 m past the rollout's end, MOONCHILD's taxi path backwards (its U-turn off the east end onto the
    # parallel taxiway), then west along the taxiway to the slot; a slot's stop path 18 m on from it
    f = {p[1]: p[3] for p in tpl_taxi[2]}
    mc = [struct.unpack('<3d', {q[1]: q[3] for q in f['BeginPointDesc'][2]}['Pos'][2])] + \
         [struct.unpack('<3d', {q[1]: q[3] for q in p[2]}['Pos'][2]) for p in f['PathPointDescList'][1]]
    back = list(reversed(mc))
    rt = lambda p: ((p[0] - se.ESC_RWY_O[0]) * se.ESC_RWY_U[0] + (p[1] - se.ESC_RWY_O[1]) * se.ESC_RWY_U[1]) / 100.0
    rs = lambda p: ((p[0] - se.ESC_RWY_O[0]) * se.ESC_RWY_S[0] + (p[1] - se.ESC_RWY_O[1]) * se.ESC_RWY_S[1]) / 100.0
    assert abs(rs(back[0])) < 3.0 and rt(back[0]) > se.ESC_TAXI_FIRST_T + 20.0, ('MOONCHILD taxi start', rt(back[0]), rs(back[0]))
    assert abs(rs(back[-1]) - se.ESC_TAXI_S) < 1.0, ('MOONCHILD hold spot', rt(back[-1]), rs(back[-1]))
    hold_t = rt(back[-1])
    clear = {}
    for S, t in se.ESC_SLOTS:
        line, d = [], hold_t - se.ESC_TAXI_STEP_M
        while d > t + 1.0:
            line.append(se.esc_rwy(d, se.ESC_TAXI_S))
            d -= se.ESC_TAXI_STEP_M
        pts = [se.esc_rwy(se.ESC_TAXI_FIRST_T)] + back + line + [se.esc_rwy(t, se.ESC_TAXI_S)]
        stop = [se.esc_rwy(t - m, se.ESC_TAXI_S) for m in se.ESC_STOP_M]
        clear[S] = min(runway_clear_m(p) for p in [pts[-1]] + stop)
        assert clear[S] >= ESC_PARK_CLEAR_M, ('a parking slot near a building', S, clear[S])
        paths.append(make_path(z, used_ids, tpl_taxi, f'SV_Path_TaxiSlot{S}', pts))
        paths.append(make_path(z, used_ids, tpl_taxi, f'SV_Path_StopSlot{S}', stop))
    print(f'  escort: {se.ESC_CHAR_UNIT} ({se.ESC_CHAR_OBJ}, {se.ESC_CHAR_ROW} -> {se.ESC_CHAR_NPC}) at {tuple(round(c) for c in route[0])} '
          f'yaw {yaw:.1f}; her path {len(char)} points: the route ({len(route)}), the final at {slope:.2f} deg from the IAF '
          f'{tuple(round(c) for c in final[0])} to touchdown {tuple(round(c) for c in final[-1])}, the rollout ({len(roll)}); '
          f'T0\'s final {len(t0)} points; the escorts\' circuit {len(circ)} points from {tuple(round(c) for c in circ[0])}; '
          f'escorts {", ".join(a["unit"] for a in se.esc_aircraft()[1:])} hold over her ({se.ESC_HOLD_RADIUS_M / 1000:.0f} km); '
          f'parking slots (t m: clear of buildings m) ' + ', '.join(f'{S} {t:.0f}: {clear[S]:.0f}' for S, t in se.ESC_SLOTS))


def cargo_arms(component):
    """[(n, unit)]: the container launcher class `component`'s spawner arms in its fire control's AllArms order (WN_WEAPON_n:
    hard rule 40) and the world-data unit each one names (LiveFCSModule_ProjectileSpawnerFromWorldData Units[0].Name_WD,
    as the engine stores it), read from the stock blueprint (build/stock)."""
    zb = ZenPkg(stock(survival_events.CARGO_LAUNCHER_DIR + component))

    def parse(i, st):
        p = bytes(zb.payloads[i])
        assert p[:4] == b'\0\0\0\0', (component, i)
        val, _ = uprop.read_struct(uprop.Ctx(p, zb.names), 4, st)
        return {q[1]: q[3] for q in val[2]}
    fcs = [i for i in range(len(zb.payloads)) if zb.export_name(i).startswith('LiveAIFireControlSystemComponent')]
    assert len(fcs) == 1, (component, fcs)
    arms = parse(fcs[0], 'LiveAIFireControlSystemComponent')['AllArms'][1]
    out = []
    for n, ref in enumerate(arms, 1):
        assert ref[0] == 'obj' and ref[1] > 0, ref
        mod = parse(ref[1] - 1, 'LiveFireControlSystemSpawner')['ProjectileModule']
        units = parse(mod[1] - 1, 'LiveFCSModule_ProjectileSpawnerFromWorldData')['Units'][1]
        assert len(units) == 1, (component, n, units)
        nm = [q for q in units[0][2] if q[1] == 'Name_WD'][0][3]
        out.append((n, nm[1] if nm[2] == 0 else f'{nm[1]}_{nm[2] - 1}'))
    return out


def cargo_units(units, used_ids, z, top_number, v):
    """The ZFA-44 cargo ships (survival_events.CARGO_* / ZFA_*): Mission 17's container ship, hull, its two container
    launchers and its Stinger mount (their classes imported: retag_parts, hard rule 7), allied, its callsign; for each arm of
    the launcher the ship fires, a unit of exactly the name the arm spawns (Mission 17's drone unit desc, allied, its
    ZFA_PER_ARM objects on the ZFA-44 drone host's row ZFA_DRONE_ROW, parked under the sea as Mission 17's drones are),
    each object index's climb-out path off each ship (zfa_climb_points: Mission 16's Ladon path's shape, smooth); and
    the pose-spawn fallback 4-ships (MOONCHILD's desc, the Su-47 host) above each ship."""
    se = survival_events
    m17z = ZenPkg(stock(se.CARGO_SOURCE_WD))
    m17, _ = props_of(m17z, m17z.export_index(se.CARGO_SOURCE_WD.rsplit('/', 1)[1]), 'LiveWorldData')
    drone = desc_named(m17, 'UnitDescList', se.ZFA_DRONE_SOURCE)
    assert field_of(drone, 'bIsSpawnFromStart') is None and [field_of(ob, 'MissionNpcID')[1] for ob in objects_of(drone)][:1] == \
        ['OP0019_uavcs_01'], 'Mission 17 drone unit changed'
    se.CARGO_ARMS.clear()
    fired = set()
    for s, unit, obj, row, srow, src_unit, spot, yaw, launcher in se.CARGO_SHIPS:
        src = desc_named(m17, 'UnitDescList', src_unit)
        assert [field_of(ob, 'MissionNpcID')[1] for ob in objects_of(src)] == [srow], (src_unit, 'Mission 17 ship unit changed')
        names = port_unit(units, used_ids, z, src, unit, obj, row, [spot], yaw, top_number, digit_ok=True, unit_digits=True)
        assert names == [obj], names
        u = unit_named(units, unit)
        set_faction(u, 1)
        put(u[2], 'LiveUnitDesc', 'RandomGroupIndex', ('raw', 'Int', struct.pack('<i', -1)))   # (Mission 17's random group 102)
        callsign(u, se.CARGO_NAME_KEY, z)
        unit_area(u, se.CARGO_AREA_M, se.CARGO_ALT_M)
        place(u, spot, yaw)
        kids = field_of(objects_of(u)[0], 'ChildAIObjectDescs')[1]
        comps = [comp_of(ch) for ch in kids]
        assert launcher in comps and 'BP_VE021_stgr_Base' in comps and len(comps) == 3, (unit, comps)
        assert retag_parts(kids, obj, used_ids, z, m17z) == 3, unit
        arms = cargo_arms(launcher)
        assert [x for _, x in arms] == se.CARGO_ARMS_EXPECTED[launcher], (launcher, arms)
        assert not fired & {x for _, x in arms}, ('two ships fire the same arm units', fired & {x for _, x in arms})
        fired |= {x for _, x in arms}
        se.CARGO_ARMS[s] = []
        for n, dunit in arms:
            base = f'SV_Obj_ZfaShip{s}Arm{chr(64 + n)}'
            park = (spot[0], spot[1], se.ZFA_PARK_Z)
            pts = [(spot[0] + (k - (se.ZFA_PER_ARM - 1) / 2.0) * se.ZFA_GAP_CM, spot[1], se.ZFA_PARK_Z) for k in range(se.ZFA_PER_ARM)]
            dn = port_unit(units, used_ids, z, drone, dunit, base, se.ZFA_DRONE_ROW, pts, yaw, top_number, unit_digits=True)
            assert dn == [f'{base}_{k}' for k in range(se.ZFA_PER_ARM)], dn
            du = unit_named(units, dunit)
            set_faction(du, 1)
            callsign(du, se.ZFA_SUB_KEY, z)      # ((2026-11-07) "the drones say ZFA-44 Twice, where is VAMPIRE?": line 2)
            unit_area(du, se.ZFA_AREA_M, se.ZFA_ALT_M)
            place(du, park, yaw, pts)
            se.CARGO_ARMS[s].append((n, dunit, dn))
    paths = [p for p in v[2] if p[1] == 'AIPathDescList'][0][3][1]
    tpl_air = desc_named(stock_wd(M16 + 'WD_Mission016_global'), 'AIPathDescList', se.LADON_SOURCE_PATH)
    for c in se.CARGO_SHIPS:
        for k in range(se.ZFA_PER_ARM):
            paths.append(make_path(z, used_ids, tpl_air, se.zfa_climb_path(c[0], k), se.zfa_climb_points(c[0], k), smooth=True))
    msrc = unit_named(units, se.ALLY_AIR_SOURCE)
    for L, unit, obj, s in se.ZFA_FALLBACK:
        spot = se.cargo_ship(s)[6]
        top = (spot[0], spot[1], spot[2] + se.ZFA_FALLBACK_UP_CM)
        pts = [(top[0] - (k // 2) * se.ZFA_GAP_CM, top[1] + (k % 2) * se.ZFA_GAP_CM, top[2]) for k in range(se.ZFA_FALLBACK_N)]
        names = port_unit(units, used_ids, z, msrc, unit, obj, se.ZFA_ROW, pts, se.cargo_ship(s)[7], top_number)
        assert names == [f'{obj}_{k}' for k in range(se.ZFA_FALLBACK_N)], names
        u = unit_named(units, unit)
        clear_flags(u, ('bIsInvincible',))
        callsign(u, se.ZFA_SUB_KEY, z)
        unit_area(u, se.ZFA_AREA_M, se.ZFA_ALT_M)
        place(u, top, se.cargo_ship(s)[7], pts)
        assert [field_of(ob, 'bGroupLead') == ('raw', 'Bool', b'\x01') for ob in objects_of(u)] == [True] + [False] * (se.ZFA_FALLBACK_N - 1)
    print(f'  cargo ships: ' + '; '.join(f'{c[1]} ({c[3]} -> {c[4]}) at ({c[6][0]:.0f}, {c[6][1]:.0f}), fires {c[8]}: '
          + ', '.join(f'WN_WEAPON_{n} {u_}' for n, u_, _ in se.CARGO_ARMS[c[0]]) for c in se.CARGO_SHIPS)
          + f'; {se.ZFA_PER_ARM} ZFA-44s ({se.ZFA_DRONE_ROW}) an arm, a climb-out path each off each ship; fallback '
          + f'{", ".join(f[1] for f in se.ZFA_FALLBACK)} of {se.ZFA_FALLBACK_N} ({se.ZFA_ROW})')


def decoy_units(units, used_ids, z, top_number):
    """THE DECOY (survival_events.DECOY_*): the bait and the DECOY_N trap UAVs (Mission 30's Marker UAV desc with its laser pod,
    its class imported: retag_parts; a box and the TGT mark), the bait's mark and the DECOY_N marks (Mission 22's dummy desc,
    invincible, attack-target exceptions, no box), the four Spear shooters (Mission 19's God desc with its targeting dummy,
    invincible, attack-target exceptions, 30 km up)."""
    se = survival_events
    m30z = ZenPkg(stock(se.DECOY_UAV_SOURCE[0]))
    m30, _ = props_of(m30z, m30z.export_index(se.DECOY_UAV_SOURCE[0].rsplit('/', 1)[1]), 'LiveWorldData')
    src = desc_named(m30, 'UnitDescList', se.DECOY_UAV_SOURCE[1])
    assert field_of(objects_of(src)[0], 'MissionNpcID')[1] == se.DECOY_MISSION_SOURCE, 'Mission 30 UAV unit changed'
    (ax, ay), safe = (se.AIRFIELD_KM[0] * 1e5, se.AIRFIELD_KM[1] * 1e5), ('bIsInvincible', 'bIsInvincibleFromAI', 'bIsAttackTargetsException')

    def uav(unit, obj, row, spot, yaw, area, digits):
        names = port_unit(units, used_ids, z, src, unit, obj, row, [spot], yaw, top_number, tgt=True, digit_ok=digits,
                          unit_digits=digits)
        assert names == [obj], names
        u = unit_named(units, unit)
        kids = field_of(objects_of(u)[0], 'ChildAIObjectDescs')[1]
        assert [comp_of(ch) for ch in kids] == [se.DECOY_POD] and retag_parts(kids, obj, used_ids, z, m30z) == 1, unit
        unit_area(u, area, se.DECOY_UAV_ALT_M)
        place(u, spot, yaw)
    uav(se.DECOY_BAIT_UNIT, se.DECOY_BAIT_OBJ, se.DECOY_BAIT_ROW, se.DECOY_BAIT_SPOT, se.DECOY_BAIT_YAW, se.DECOY_BAIT_AREA_M, False)
    msrc = unit_named(units, se.DECOY_MARK_SOURCE)
    assert [field_of(ob, 'MissionNpcID')[1] for ob in objects_of(msrc)] == [se.DECOY_MARK_ROW], 'Unit_dummyN0 changed'

    def mark(unit, obj, spot, digits):
        names = port_unit(units, used_ids, z, msrc, unit, obj, se.DECOY_MARK_ROW, [spot], 0.0, top_number, digit_ok=digits,
                          unit_digits=digits)
        assert names == [obj], names
        u = unit_named(units, unit)
        set_bools(u, safe)
        place(u, spot, 0.0)
        assert not field_of(objects_of(u)[0], 'bShowHUDBox') and not field_of(objects_of(u)[0], 'TargetMarkType'), unit
    mark(se.DECOY_BAIT_MARK_UNIT, se.DECOY_BAIT_MARK_OBJ, se.DECOY_BAIT_MARK_SPOT, False)
    for k, unit, obj, munit, mobj in se.decoy_uavs():
        a = math.radians(10.0 * k)
        uav(unit, obj, se.DECOY_UAV_ROW, (ax + 600000.0 * math.cos(a), ay + 600000.0 * math.sin(a), 200000.0), 10.0 * k + 90.0,
            se.DECOY_UAV_AREA_M, True)
        mark(munit, mobj, (ax, ay, -10000.0), True)
    m19z = ZenPkg(stock(se.DECOY_SPEAR_SOURCE[0]))
    m19, _ = props_of(m19z, m19z.export_index(se.DECOY_SPEAR_SOURCE[0].rsplit('/', 1)[1]), 'LiveWorldData')
    gsrc = desc_named(m19, 'UnitDescList', se.DECOY_SPEAR_SOURCE[1])
    assert field_of(objects_of(gsrc)[0], 'MissionNpcID')[1] == se.DECOY_SPEAR_SOURCE_ROW, 'Mission 19 God unit changed'
    for k, (unit, obj) in enumerate(se.DECOY_SPEARS):
        spot = (ax + (k - 1.5) * se.DECOY_SPEAR_GAP_CM, ay, se.DECOY_SPEAR_Z)
        names = port_unit(units, used_ids, z, gsrc, unit, obj, se.DECOY_SPEAR_ROW, [spot], 0.0, top_number, unit_digits=True)
        assert names == [obj], names
        u = unit_named(units, unit)
        kids = field_of(objects_of(u)[0], 'ChildAIObjectDescs')[1]
        assert [comp_of(ch) for ch in kids] == ['TargetingDummy'] and retag_parts(kids, obj, used_ids, z, m19z) == 1, unit
        set_bools(u, safe)
        place(u, spot, 0.0)
    print(f'  decoy: {se.DECOY_BAIT_UNIT} ({se.DECOY_BAIT_ROW}) at {se.DECOY_BAIT_SPOT}, its mark {se.DECOY_BAIT_MARK_UNIT}; '
          f'{se.DECOY_N} trap UAVs SV_Unit_DecoyUav_01-{se.DECOY_N} ({se.DECOY_UAV_ROW} -> {se.DECOY_UAV_NPC}) and marks '
          f'SV_Unit_DecoyMark_01-{se.DECOY_N}; {len(se.DECOY_SPEARS)} Spear shooters ({se.DECOY_SPEAR_ROW}) 30 km up')


def build_wd_global():
    """Mission 22's global world data (its units, AI paths, marks, volumes and the combat zone the minimap frames
    itself on - test 6), with no unit spawning at mission start: Survival's events spawn every unit they use."""
    old, new = M22 + 'WD_Mission022_global', MI + 'WD_SurvivalMode_global'
    z = ZenPkg(stock(old))
    rename_package(z, old, new)               # also renames every WorldDataName value (same FName)
    i = z.export_index(new.rsplit('/', 1)[1])
    v, rest = props_of(z, i, 'LiveWorldData')
    units = [p for p in v[2] if p[1] == 'UnitDescList'][0][3][1]
    # An absent property means the class default, and bIsSpawnFromStart defaults to true (test M2-1: removing it
    # spawned all 71 units, 135 aircraft). Mission 22's own reinforcements carry it as an explicit zero: do the same.
    idx = [k for k, (n, t) in uprop.U.schema('LiveUnitDesc').items() if n == 'bIsSpawnFromStart'][0]
    sp_idx = [k for k, (n, t) in uprop.U.schema('LiveUnitDesc').items() if n == 'SpawnPoint'][0]
    r_idx = [k for k, (n, t) in uprop.U.schema('LiveUnitDesc').items() if n == 'RadiusInMeter'][0]
    top_idx = [k for k, (n, t) in uprop.U.schema('LiveUnitDesc').items() if n == 'MaxAltitudeInMeter'][0]
    dn = lambda n: n[1] if n[2] == 0 else f'{n[1]}_{n[2] - 1}'
    POOL_UNITS = set(survival_events.POOL)
    survival_events.POOL_OBJS.clear()
    turned_off, lancers = 0, 0
    behaviours, sized = {}, {}
    used_ids = {q[3][2] for u in units for p in u[2] if p[1] == 'AIObjectDescList' and p[3]
                for ob in p[3][1] for q in ob[2] if q[1] == 'UniqueID' and q[3]}
    top_number = {}                            # AI object name -> highest number used anywhere in the world data
    for u in units:
        for p in u[2]:
            if p[1] == 'AIObjectDescList' and p[3]:
                for ob in p[3][1]:
                    for q in ob[2]:
                        if q[1] == 'Name' and q[3]: top_number[q[3][1]] = max(top_number.get(q[3][1], 0), q[3][2])
    for u in units:
        name = [p for p in u[2] if p[1] == 'Name'][0][3][1]
        keep = name in survival_events.KEEP_AT_START
        point = survival_events.KEEP_AT_START.get(name)
        cur = [p for p in u[2] if p[1] == 'bIsSpawnFromStart']
        if not keep and not (cur and cur[0][2]): turned_off += 1
        on = (idx, 'bIsSpawnFromStart', False, ('raw', 'Bool', b'\x01')) if keep else (idx, 'bIsSpawnFromStart', True, None)
        rest_props = [p for p in u[2] if p[1] != 'bIsSpawnFromStart' and not (point and p[1] == 'SpawnPoint')]
        if point:
            # the unit's SpawnPoint alone left the anchor at the map origin (probe test 7): its AI object has a
            # SpawnPoint of its own, which is where it actually stands, so both get the point
            rest_props.append((sp_idx, 'SpawnPoint', False, ('native', 'Vector', struct.pack('<3d', *point))))
            for k, p in enumerate(rest_props):
                if p[1] == 'AIObjectDescList':
                    for obj in p[3][1]:
                        obj[2][:] = [(q[0], q[1], False, ('native', 'Vector', struct.pack('<3d', *point)))
                                     if q[1] == 'SpawnPoint' else q for q in obj[2]]
        radius = (survival_events.AREA_RADIUS_M if name in POOL_UNITS else       # the pool: an area over the whole zone
                  survival_events.HEAVY_AREA_RADIUS_M if name in survival_events.HEAVY_BOMBERS else None)
        if radius:
            rest_props = [p for p in rest_props if p[1] != 'RadiusInMeter'] + [
                (r_idx, 'RadiusInMeter', False, ('raw', 'Float', struct.pack('<f', radius)))]
        if survival_events.POOL_ROLE.get(name) == 'lancer':     # the Lancers' band higher (P1: they spawn 2 km up)
            rest_props = [p for p in rest_props if p[1] != 'MaxAltitudeInMeter'] + [
                (top_idx, 'MaxAltitudeInMeter', False, ('raw', 'Float', struct.pack('<f', survival_events.LANCER_MAX_ALT_M)))]
            lancers += 1
        size = survival_events.flight_size(name)
        if size:                               # Survival's flights: 2, 4 or 6 aircraft in a standard formation
            for p in rest_props:
                if p[1] == 'AIObjectDescList':
                    objs = p[3][1]
                    assert any(q[1] == 'bGroupLead' and q[3] == ('raw', 'Bool', b'\x01') for q in objs[0][2]), name
                    set_flight_size(objs, size, name, unit_point(u), used_ids, top_number)
                    sized[size] = sized.get(size, 0) + 1
        # the flight's behaviour (survival_events: built at level load), each object's after sizing: a Wolf flight's bait
        # and trap objects name different rows (survival_events.behaviour_rows; set_flight_size copies objects 0 / 1)
        if survival_events.behaviour_row(name):
            for p in rest_props:
                if p[1] == 'AIObjectDescList':
                    rows = []
                    for k, obj in enumerate(p[3][1]):
                        row = survival_events.behaviour_rows(name, k)
                        assert row in NPC_ROWS, (name, k, row)
                        assert any(q[1] == 'MissionNpcID' for q in obj[2]), name
                        z.nb.add(row)
                        obj[2][:] = [(q[0], q[1], False, ('name', row, 0)) if q[1] == 'MissionNpcID' else q for q in obj[2]]
                        rows.append(row)
                    key = '+'.join(sorted(set(rows)))
                    behaviours[key] = behaviours.get(key, 0) + 1
                    if name in POOL_UNITS:     # the objects' names as event args write them (the Wolf trap's events)
                        survival_events.POOL_OBJS[name] = [dn([q for q in ob[2] if q[1] == 'Name'][0][3]) for ob in p[3][1]]
        u[2][:] = sorted(rest_props + [on], key=lambda p: p[0])
    split_units(units, used_ids, z, top_number)
    ally_units(units, used_ids, z, top_number, v)
    lcac_units(units, used_ids, z, top_number, v)
    spaceport_units(units, used_ids, z, top_number, v)
    ladon_units(units, used_ids, z, top_number, v)
    heavy_paths(used_ids, z, v)
    alcn_units(units, used_ids, z, top_number, v)
    valka_unit(units, used_ids, z, top_number)
    valka_eml_unit(units, used_ids, z, top_number)
    fishing_units(units, used_ids, z, top_number)          # GONE FISHIN' (survival_events.FISH_* / SAL_BOAT_*)
    festival_units(units, used_ids, z, top_number, v)      # THE FESTIVAL (survival_events.FEST_*)
    escort_units(units, used_ids, z, top_number, v)        # THE ESCORT (survival_events.ESC_*)
    cargo_units(units, used_ids, z, top_number, v)         # its unlock: the ZFA-44 cargo ships (CARGO_* / ZFA_*)
    decoy_units(units, used_ids, z, top_number)            # THE DECOY (survival_events.DECOY_*)
    names = {[p for p in u[2] if p[1] == 'Name'][0][3][1] for u in units}
    assert set(survival_events.KEEP_AT_START) <= names, set(survival_events.KEEP_AT_START) - names
    assert set(survival_events.BOMBERS) <= names, set(survival_events.BOMBERS) - names
    assert any(p[1] == 'CombatZoneDescList' for p in v[2])
    # every object reference in the world data inside this package (an export index from another mission's desc crashes
    # the game's loader when the level loads: "Bad export index")
    def refs(x, out):
        if isinstance(x, tuple):
            if x and x[0] == 'obj' and isinstance(x[1], int) and x[1] > len(z.exports): out.append(x)
            for y in x: refs(y, out)
        elif isinstance(x, list):
            for y in x: refs(y, out)
        return out
    bad = refs(v, [])
    assert not bad, f'object references past the {len(z.exports)} exports: {bad[:5]}'
    z.payloads[i] = bytearray(write_props(z, v) + rest)
    chk, _ = props_of(z, i, 'LiveWorldData'); assert chk == v
    print(f'  {len(units)} units, spawn-at-start turned off on {turned_off}; behaviour rows (flights): {behaviours}; '
          f'flight sizes: {sized}; {lancers} Lancer flights up to {survival_events.LANCER_MAX_ALT_M:.0f} m')
    assert lancers == sum(1 for u in survival_events.POOL if survival_events.POOL_ROLE[u] == 'lancer'), lancers
    assert len(survival_events.POOL_OBJS) == len(survival_events.POOL), sorted(set(survival_events.POOL) - set(survival_events.POOL_OBJS))
    retarget_import(z, NPC_TABLE_STOCK, NPC_TABLE)        # Survival's own NPC mission table (build_npc_table)
    save(z, new)


def build_ef():
    """Mission 22's event flag asset with every flag removed, then Survival's int flags (value 0) added."""
    old = M22 + 'EF_Mission022_global'
    z = ZenPkg(stock(old))
    rename_package(z, old, MI + 'EF_SurvivalMode_global')
    v, rest = props_of(z, 0, 'LiveEventFlagAsset')
    def clear(s):
        for k, (pi, pn, zero, val) in enumerate(s[2]):
            if val and val[0] == 'map': s[2][k] = (pi, pn, False, ('map', 0, []))
            elif val and val[0] == 'struct': clear(val)
    clear(v)
    fd = [p for p in v[2] if p[1] == 'FlagData'][0][3]
    ints = [p for p in fd[2] if p[1] == 'IntegerFiled'][0][3]
    for name in survival_events.INT_FLAGS:
        # The event records name flags by string, which the game turns into an FName that splits a numeric tail
        # ("SV_Up_19" -> SV_Up, number 20). Keys must be stored the same way or the flag never matches: test of
        # 2026-10-21 05:07, flights 10-24 were never flagged up, so they were never chased.
        key = survival_events.fname(name)
        z.nb.add(key[1])
        ints[2].append((key, ('struct', 'LiveEventFlagType_Integer', [(0, 'Value', True, None)])))
    z.payloads[0] = bytearray(write_props(z, v) + rest)
    chk, _ = props_of(z, 0, 'LiveEventFlagAsset'); assert chk == v
    save(z, MI + 'EF_SurvivalMode_global')


def empty_ep(z, new_path):
    """Keep the EP's properties (world data, flag asset, package hash), remove every trigger and exec."""
    p = bytes(z.payloads[0])
    v, rest = props_of(z, 0, 'LiveEventPackage')
    props = v[2]
    for k, (pi, pn, zero, val) in enumerate(props):
        if pn == 'PackageHash': props[k] = (pi, pn, False, ('raw', 'Int', struct.pack('<I', package_hash(new_path))))
    head = write_props(z, v)
    # after the properties: u32 (always 0 so far), u32 trigger count, triggers, u32 exec count, execs
    assert rest[:4] == b'\0\0\0\0', rest[:4]
    z.payloads[0] = bytearray(head + b'\0\0\0\0' + struct.pack('<II', 0, 0))


def build_ep(part, ef=False):
    """Mission 22's event package for `part` (global / phase01 / phase02) with every trigger and exec removed;
    the global one then gets Survival's event graph (tools/survival_events.py)."""
    old, new = M22 + 'EP_Mission022_' + part, MI + 'EP_SurvivalMode_' + part
    z = ZenPkg(stock(old))
    rename_package(z, old, new)
    retarget_import(z, M22 + 'WD_Mission022_' + part, MI + 'WD_SurvivalMode_' + part)
    if ef:
        retarget_import(z, M22 + 'EF_Mission022_global', MI + 'EF_SurvivalMode_global')
    empty_ep(z, new)
    if part == 'global':
        g = survival_events.build_events(stock(old))
        # exec classes Mission 22's package doesn't import (Graph.foreign_template): the same imports, in the same order
        assert len(z.imports) + len(g.added_imports) == len(g.z.imports), (len(z.imports), len(g.added_imports))
        z.imports += g.added_imports
        head = bytes(z.payloads[0])[:-12]         # empty_ep left: properties + u32 0 + u32 0 + u32 0
        z.payloads[0] = bytearray(survival_events.write_records(g, z, head))
        _, _, _, T, E, offs = ep_dump.load_bytes(z)
        assert len(T) == len(g.trig) and len(E) == len(g.ex) and offs[3] == offs[4], (len(T), len(E), offs)
        declared = {survival_events.fname(n) for n in survival_events.INT_FLAGS}   # build_ef's keys
        assert {survival_events.fname(n) for n in g.flags} <= declared, g.flags - set(survival_events.INT_FLAGS)
        print(f'  events: {len(T)} triggers, {len(E)} execs')
    save(z, new)


# ---------------------------------------------------------------- the ZFA-44s' anti-missile laser (2026-11-07)
# (survival_events.ZFA_TLS_*; tools/re/LASER_INTERCEPTOR.md "Built") The CIWS arm's weapon imports onto BP_SwingTLS_ForMSL's
# public exports by role (each export's name in its own package). None: the CIWS weapon's ParticleUpdateHandler, which the
# laser hasn't and nothing in the arm's package references (no dependency, no property value: build_zfa_laser checks),
# made a null import (as stock packages carry) and its hash dropped, so the arm imports exactly the laser's 7 public
# exports, as the Nightmare UAV's blueprint does.
ZFA_TLS_ROLES = {'BP_wp_ciws_vessel_C': 'BP_SwingTLS_ForMSL_C', 'Default__BP_wp_ciws_vessel_C': 'Default__BP_SwingTLS_ForMSL_C',
                 'WeaponCollisionEffectModule': 'WeaponCollisionEffectModule', 'BulletVFX NS': 'MainLaser Niagara',
                 'BulletVFX CS': 'EndLaser Niagara', 'DefaultSceneRoot_GEN_VARIABLE': 'DefaultSceneRoot_GEN_VARIABLE',
                 'Static Mesh': 'Static Mesh', 'ParticleUpdateHandler': None}
ZFA_TLS_MESH = 'PlaneBodyMesh'          # the host's body: the Su-47's own gun arm's (slot sockets GUN: its SOC_Gun_01)
# the Nightmare UAV's TLSforMSL launcher's numbers (BP_OP0024_uavn_CP), all round (no turret here: 180 deg, not 30)
ZFA_TLS_PERFORMANCE = {'FireRate': 8, 'MagazineCapacity': 1, 'ReloadTime': 1.0}
ZFA_TLS_FIRE_CONTROL = {'CaptureDistance': 300000.0, 'CaptureAngleRange': 180.0, 'ActivationTime': 0.1,
                        'TriggeringTime': 8.0, 'TriggerCount': 1, 'ShotIntervalTime': 8.0, 'RestingTime': 1.0}
ZFA_TLS_SEARCH_CM = (300000.0, 330000.0)   # its AIControlCIWS's lock / loss radius (cm): the laser's 3 km reach
# its fire-control row (DT_SV_NpcFCS, metres / seconds / degrees): NPC_FCS_VesselCIWS000's with these values; no weapon row
# (the laser has none: Online Mode's NFID_Vessel_CIWS_00 names none either) and no AI module row (the arm's own search)
ZFA_TLS_ROW_VALUES = {'FireRate': 8, 'MagazineCapacity': 1, 'ReloadTime': 1.0, 'SlotNum': 1, 'CaptureDistance': 3000.0,
                      'CaptureAngleRange': 180.0, 'ActivationTime': 0.1, 'TriggeringTime': 8.0, 'TriggerCount': 1,
                      'ShotIntervalTime': 8.0, 'RestingTime': 1.0, 'YawSpeed': 360.0, 'YawAngleMin': -180.0,
                      'YawAngleMax': 180.0, 'PitchSpeed': 360.0, 'PitchAngleMin': -90.0, 'PitchAngleMax': 90.0}
ZFA_TLS_ROW_CLEAR = ('NpcAIModuleId', 'NpcWeaponId', 'PredictionOffsetTime', 'ActivationRandomTimeMin', 'ActivationRandomTimeMax')
NULL_IMPORT = 0xFFFFFFFFFFFFFFFF


def zfa_tls_u64(e, at):
    return struct.unpack_from('<Q', e, at)[0]


def zfa_tls_value(sname, field, x):
    """A value for `sname`'s property `field`, typed as the usmap has it (Int / Float / Double / Bool)."""
    t = {n: tt for k, (n, tt) in uprop.U.schema(sname).items()}[field][0]
    if t == 'Int': return ('raw', 'Int', struct.pack('<i', int(x)))
    if t == 'Float': return ('raw', 'Float', struct.pack('<f', float(x)))
    if t == 'Double': return ('raw', 'Double', struct.pack('<d', float(x)))
    if t == 'Bool': return ('raw', 'Bool', b'\x01' if x else b'\x00')
    raise TypeError((sname, field, t))


def zfa_tls_set(props, sname, field, value=None, zero=False):
    """props (a struct's or row's (idx, name, zero, value) list): `field` set (value) or zeroed (zero), in index order."""
    idx = {n: k for k, (n, t) in uprop.U.schema(sname).items()}[field]
    props[:] = sorted([q for q in props if q[0] != idx] + [(idx, field, zero, None if zero else value)], key=lambda q: q[0])


def build_zfa_laser():
    """The ZFA-44s' anti-missile laser (survival_events.ZFA_TLS_*): its fire-control arm BP_FCS_SV_ZfaTLS, a copy of the
    ships' CIWS arm BP_FCS_Vessel_CIWS_00 under Survival's path (its objects keep their names: a zen package's export
    hashes are package-relative, as the menu pages' copies), its weapon AC8's BP_SwingTLS_ForMSL (stock, unchanged), its
    launcher a LauncherCommon on the host's body at its gun socket (the bone control the CIWS turns its turret with needs
    bones a fighter hasn't), its AIControlCIWS missiles only within 3 km; and its fire-control row SV_FCS_ZfaTLS in
    DT_SV_NpcFCS, which Lua adds to DT_NPC_FCS at the main menu (Scripts/sv_escort_laser.lua). DT_SV_NpcRows' laser twin
    of the ZFA-44 host (build_npc_rows) names that row in its gun's slot (ZFA_TLS_SLOT)."""
    se = survival_events
    z = ZenPkg(stock(se.ZFA_TLS_FCS_SOURCE))
    old_w, new_w, ecm = (ZenPkg(stock(p)) for p in (se.ZFA_TLS_OLD_WEAPON, se.ZFA_TLS_WEAPON, se.ZFA_TLS_LAUNCHER_SOURCE))
    pub = lambda zz: {zfa_tls_u64(e, 56): zz.export_name(i) for i, e in enumerate(zz.exports) if zfa_tls_u64(e, 56)}
    old_pub, new_pub = pub(old_w), {n: h for h, n in pub(new_w).items()}
    assert sorted(old_pub.values()) == sorted(ZFA_TLS_ROLES), ('the CIWS weapon changed', sorted(old_pub.values()))
    assert sorted(new_pub) == sorted(r for r in ZFA_TLS_ROLES.values() if r), ('the laser changed', sorted(new_pub))
    assert z.imp_pkgs == [se.ZFA_TLS_OLD_WEAPON], z.imp_pkgs
    # 1. the weapon: each import of the CIWS's onto the laser's export of its role; the one with none a null import
    k = z.imp_pkgs.index(se.ZFA_TLS_OLD_WEAPON)
    mine = [i for i, x in enumerate(z.imports) if x >> 62 == 2 and (x >> 32) & 0x3fffffff == k]
    role = {i: old_pub[z.imp_hashes[z.imports[i] & 0xffffffff]] for i in mine}
    assert sorted(role.values()) == sorted(ZFA_TLS_ROLES), role
    drop = [i for i in mine if ZFA_TLS_ROLES[role[i]] is None]
    deps = {struct.unpack_from('<i', z.dep_ent, o)[0] for o in range(0, len(z.dep_ent), 4)}
    for i in drop:          # referenced nowhere: no dependency, no property value (its index, -(i+1), in no payload)
        assert -(i + 1) not in deps and all(struct.pack('<i', -(i + 1)) not in bytes(p) for p in z.payloads), (i, role[i])
    for i in mine:
        if i not in drop: z.imp_hashes[z.imports[i] & 0xffffffff] = new_pub[ZFA_TLS_ROLES[role[i]]]
    for i in sorted(drop, key=lambda i: z.imports[i] & 0xffffffff, reverse=True):
        h = z.imports[i] & 0xffffffff
        assert sum(1 for x in z.imports if x >> 62 == 2 and x & 0xffffffff == h) == 1, (i, h)
        z.imports[i] = NULL_IMPORT
        del z.imp_hashes[h]
        z.imports = [x - 1 if x >> 62 == 2 and x & 0xffffffff > h else x for x in z.imports]
    z.set_imported_package(se.ZFA_TLS_OLD_WEAPON, se.ZFA_TLS_WEAPON)
    # 2. the launcher: LauncherBoneControl -> LauncherCommon (BP_FCS_ECM_00's class and template ids, in the import map in
    #    place of the bone control's), on the host's body at its gun socket, the Nightmare UAV's numbers
    li = z.export_index('LiveFCSModule_LauncherBoneControl_0')
    el = ecm.export_index('LiveFCSModule_LauncherCommon_0')
    c0, t0 = zfa_tls_u64(z.exports[li], 32), zfa_tls_u64(z.exports[li], 48)
    c1, t1 = zfa_tls_u64(ecm.exports[el], 32), zfa_tls_u64(ecm.exports[el], 48)
    assert c1 in ecm.imports and t1 in ecm.imports and z.imports.count(c0) == 1 and z.imports.count(t0) == 1, 'launcher ids'
    assert [i for i, e in enumerate(z.exports) if zfa_tls_u64(e, 32) == c0] == [li], 'one bone control'
    z.imports = [c1 if x == c0 else t1 if x == t0 else x for x in z.imports]
    struct.pack_into('<Q', z.exports[li], 32, c1)
    struct.pack_into('<Q', z.exports[li], 48, t1)
    bone, rest = props_of(z, li, 'LiveFCSModule_LauncherBoneControl')
    have = {q[1]: q[3] for q in bone[2] if not q[2]}
    perf, fc = copy.deepcopy(have['Performance']), copy.deepcopy(have['FireControl'])
    for f, x in ZFA_TLS_PERFORMANCE.items():
        zfa_tls_set(perf[2], perf[1], f, zfa_tls_value(perf[1], f, x))
    for f, x in ZFA_TLS_FIRE_CONTROL.items():
        zfa_tls_set(fc[2], fc[1], f, zfa_tls_value(fc[1], f, x))
    z.nb.add(ZFA_TLS_MESH)
    lc = ('struct', 'LiveFCSModule_LauncherCommon', [])
    zfa_tls_set(lc[2], lc[1], 'MeshComponentName', ('name', ZFA_TLS_MESH, 0))
    zfa_tls_set(lc[2], lc[1], 'Performance', perf)
    zfa_tls_set(lc[2], lc[1], 'FireControl', fc)
    z.payloads[li] = bytearray(write_props(z, lc) + rest)
    # 3. its AI: missiles only, within the laser's reach
    ai = z.export_index('LiveFCSModule_AIControlCIWS_0')
    v, rest = props_of(z, ai, 'LiveFCSModule_AIControlCIWS')
    zfa_tls_set(v[2], v[1], 'bSearchMissileOnly', ('raw', 'Bool', b'\x01'))
    for f, r in zip(('EnemySearchLockAreaBounds', 'EnemySearchLossAreaBounds'), ZFA_TLS_SEARCH_CM):
        b = copy.deepcopy([q[3] for q in v[2] if q[1] == f][0])
        zfa_tls_set(b[2], b[1], 'Radius', zfa_tls_value(b[1], 'Radius', r))
        zfa_tls_set(v[2], v[1], f, b)
    z.payloads[ai] = bytearray(write_props(z, v) + rest)
    # 4. under Survival's path
    z.rename(se.ZFA_TLS_FCS_SOURCE, se.ZFA_TLS_FCS_PKG)
    assert se.ZFA_TLS_FCS_PKG in z.names and se.ZFA_TLS_FCS_SOURCE not in z.names
    for i, sn in ((li, 'LiveFCSModule_LauncherCommon'), (ai, 'LiveFCSModule_AIControlCIWS')):
        props_of(z, i, sn)                                  # (each reads back and round-trips)
    save(z, se.ZFA_TLS_FCS_PKG)
    cls = z.export_name(0)
    assert cls == se.ZFA_TLS_FCS_SOURCE.rsplit('/', 1)[1] + '_C', cls

    # its fire-control row
    def edit(props):
        zfa_tls_set(props, 'LiveNpcFCSDataTable', 'FCSBlueprintClass',
                    ('soft', ('name', se.ZFA_TLS_FCS_PKG, 0), ('name', cls, 0), ''))
        for f in ZFA_TLS_ROW_CLEAR:
            zfa_tls_set(props, 'LiveNpcFCSDataTable', f, zero=True)
        for f, x in ZFA_TLS_ROW_VALUES.items():
            zfa_tls_set(props, 'LiveNpcFCSDataTable', f, zfa_tls_value('LiveNpcFCSDataTable', f, x))
    build_rows_table('/Game/Datatables/AI/NPC/FCS/DT_NPC_FCS', se.ZFA_TLS_FCS_TABLE, 'LiveNpcFCSDataTable',
                     se.ZFA_TLS_FCS_ROW_SOURCE, se.ZFA_TLS_FCS_ROW, edit)
    print(f'  zfa laser: {se.ZFA_TLS_FCS_PKG} ({cls}: {se.ZFA_TLS_FCS_SOURCE.rsplit("/", 1)[1]} with '
          f'{se.ZFA_TLS_WEAPON.rsplit("/", 1)[1]}, LauncherCommon on {ZFA_TLS_MESH} GUN, missiles only within '
          f'{ZFA_TLS_SEARCH_CM[0] / 100000:g} km; {len(drop)} import made null), its row {se.ZFA_TLS_FCS_ROW} in '
          f'{se.ZFA_TLS_FCS_TABLE.rsplit("/", 1)[1]}; {se.ZFA_TLS_NPC} carries it in slot {se.ZFA_TLS_SLOT}')
