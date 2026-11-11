"""build_survival_fleet.py : THE INVINCIBLE FLEET's fleet (round 30, WP7: docs/design/INVINCIBLE_FLEET.md,
docs/design/INVINCIBLE_FLEET_WP7.md): its units and lanes in the world data, its rows, and their read-back check.

  fleet_units        (build_wd_global) every ship of survival_events.if_fleet(): a one-ship unit of its own, made as the
                     Spaceport's ships are (spaceport_units: Faction 2, no tags, a TGT mark and a box, its parts renamed and
                     on Survival's rows), new units even where the Spaceport has the class (its units stay as they are),
                     at its spawn spot facing the course, and its lane (fleet_path)
  fleet_npc_rows     (build_npc_rows) DT_SV_NpcRows: each named ship's hull row (its class's stock hull row on its own model
                     row, its ChildNPCId on the fleet's turret rows) and Mission 22's ships' turret rows (IF_TURRETS)
  fleet_mission_rows (build_npc_table) DT_SV_NpcMission: their mission rows
  fleet_model_rows   (build_model_rows) DT_SV_ModelRows: each named ship's model row, its name key on the box
  check_fleet_build  (main) all of it read back from the packages this build saved

A part of tools/build_survival.py (its docstring has the layout): every name build_survival defines is here through the
import below, and build_survival imports this part back whole, so each name here is build_survival.<name> too. The parts
imported before this one (build_survival_rows, build_survival_world) call these through the main module (import
build_survival): a part sees only the names above its own import. Import build_survival (or run it), not this file.
"""
from build_survival import *  # noqa: F401,F403 (build_survival's names; it imports this part at its end)
import hashlib  # noqa: E402 (fleet_units' guard)


def fleet_path(z, used_ids, template, name, pts, before=None, after=None):
    """A ship's lane: make_path's smooth shape (each tangent along the line through its neighbours, as long as its shorter
    leg: wide curves through the densely set points of the turns) with the ship kept level: every point's Up straight up
    (smooth=True banks an aircraft into its turns, up to 50 deg: a ship would heel) and no pitch or roll."""
    p = make_path(z, used_ids, template, name, pts, smooth=True, before=before, after=after)
    f = {q[1]: q for q in p[2]}
    for el in [f['BeginPointDesc'][3]] + list(f['PathPointDescList'][3][1]):
        rot = [q for q in el[2] if q[1] == 'PathPointRotation']
        yaw = struct.unpack('<3d', rot[0][3][2])[1] if rot and rot[0][3] else 0.0
        el[2][:] = [(q[0], q[1], False, vec(0.0, 0.0, 1.0)) if q[1] == 'Up' and q[3] is not None else
                    (q[0], q[1], False, vec(0.0, yaw, 0.0, 'Rotator')) if q[1] == 'PathPointRotation' and q[3] is not None
                    else q for q in el[2]]
    return p


def fleet_parts(ch_list, prefix, rows, used_ids, z, places):
    """Mission 22's ship parts (ChildAIObjectDescs / GrandChildrens) renamed by place (places: component -> place,
    se.IF_M22_PLACES: their components end in digits), new UniqueIDs, their mission rows Survival's (rows: Mission 22's
    mission row -> Survival's), no tags (hard rule 31: Mission 22's artillery mounts carry TAG_Enemy_Ship_Obj in their
    Data; the review of 8ca3195, finding 3). Their classes are imports of this package already (the world data is
    Mission 22's)."""
    for ch in ch_list:
        data = [p for p in ch[2] if p[1] == 'Data'][0][3][2]
        comp = comp_of(ch)
        assert comp in places, (prefix, comp)
        was = [q for q in data if q[1] == 'MissionNpcID'][0][3][1]
        assert was in rows, (prefix, comp, was)
        data[:] = [(q[0], q[1], False, ('name', rows[was], 0)) if q[1] == 'MissionNpcID' else
                   (q[0], q[1], False, ('arr', [])) if q[1] == 'Tags' and q[3] is not None else q for q in data]
        name = f'{prefix}_{places[comp]}'
        assert survival_events.fname(name)[2] == 0, name                  # (no number tail: hard rule 17)
        uid = new_unique_id(used_ids, 'AC8SurvivalMode:' + name)
        ch[2][:] = [(q[0], q[1], False, ('name', name, 0)) if q[1] == 'Name' else
                    (q[0], q[1], False, ('raw', 'UInt32', uid)) if q[1] == 'UniqueID' else
                    (q[0], q[1], False, ('arr', [])) if q[1] == 'Tags' and q[3] is not None else q for q in ch[2]]
        for n in (name, rows[was]): z.nb.add(n)
        gc = [p for p in ch[2] if p[1] == 'GrandChildrens']
        if gc and gc[0][3]: fleet_parts(gc[0][3][1], name, rows, used_ids, z, places)


def fleet_copy_object(units, used_ids, z, src_unit, src_obj, new_unit, obj_name, npc_row, top_number):
    """A one-ship unit `new_unit` of Survival's own world data's unit `src_unit` holding only its object `src_obj` (copy_unit
    keeps a unit's first objects; Mission 22's enemy units hold two or three ships each), named obj_name, on npc_row.
    Mission 22's identity left behind (the review of 8ca3195, finding 3): its object's callsign GameObjectDisplayNameID02
    (the Kirov's, the Udaloy's and the Gorshkov's carry Mission 22's ContainerEnemyCallsign_Name_*, which could show on
    the box beside or instead of its name) and the unit's bShowDebugArea (on in Mission 22) written as explicit zeros, as
    the Spaceport's ports have them."""
    unit_name = lambda u: [p for p in u[2] if p[1] == 'Name'][0][3][1]
    dn = lambda n: n[1] if n[2] == 0 else f'{n[1]}_{n[2] - 1}'
    src = [u for u in units if unit_name(u) == src_unit]
    assert len(src) == 1, src_unit
    assert new_unit not in {unit_name(u) for u in units} and not new_unit[-1].isdigit(), new_unit
    assert obj_name not in top_number and not obj_name[-1].isdigit(), obj_name
    new = copy.deepcopy(src[0])
    objs = [p for p in new[2] if p[1] == 'AIObjectDescList'][0][3][1]
    hit = [ob for ob in objs if dn([q for q in ob[2] if q[1] == 'Name'][0][3]) == src_obj]
    assert len(hit) == 1, (src_unit, src_obj)
    objs[:] = hit
    uid = new_unique_id(used_ids, f'AC8SurvivalMode:{new_unit}:0')
    hit[0][2][:] = [(q[0], q[1], False, ('name', obj_name, 0)) if q[1] == 'Name' else
                    (q[0], q[1], False, ('name', npc_row, 0)) if q[1] == 'MissionNpcID' else
                    (q[0], q[1], False, ('raw', 'UInt32', uid)) if q[1] == 'UniqueID' else
                    (q[0], q[1], True, None) if q[1] == 'GameObjectDisplayNameID02' else q for q in hit[0][2]]
    top_number[obj_name] = 1
    assert npc_row in NPC_ROWS, npc_row
    uu = new_unique_id(used_ids, f'AC8SurvivalMode:{new_unit}')
    new[2][:] = [(q[0], q[1], False, ('name', new_unit, 0)) if q[1] == 'Name' else
                 (q[0], q[1], False, ('raw', q[3][1], uu)) if q[1] == 'UniqueID' else
                 (q[0], q[1], True, None) if q[1] == 'bShowDebugArea' else q for q in new[2]]
    for n in (new_unit, obj_name, npc_row): z.nb.add(n)
    units.append(new)
    return [obj_name]


def fleet_units(units, used_ids, z, top_number, v):
    """THE INVINCIBLE FLEET's ships (survival_events.if_fleet): each a one-ship unit at its spawn spot (IF_LEAD_M behind its
    lane's start: hard rule 2), facing the course in, an enemy's (Faction 2, no tags, a TGT mark and a box), its area
    IF_AREA_M round it, never at the level's start; its parts named as build_fleet's records name them, on Survival's rows;
    its lane SV_Path_IF<Key> (fleet_path on Mission 22's ship lane, the Spaceport boats' template: ControlType 1).
    Only additions: every unit and path desc in the world data before it (the Spaceport's too) is asserted the same after."""
    se = survival_events
    paths = [p for p in v[2] if p[1] == 'AIPathDescList'][0][3][1]
    # ((the review of 8ca3195, finding 6) the fleet only adds: every unit and path already in the world data, the Spaceport's
    # among them, is the same desc after it, property for property: checked at its end, every build)
    sig = lambda d: hashlib.sha1(repr(d).encode('utf-8')).hexdigest()
    was_units, was_paths, was_imports = [sig(u) for u in units], [sig(p) for p in paths], len(z.imports)
    lane_t = desc_named(v, 'AIPathDescList', se.SP_BOAT_PATH_TEMPLATE)
    def load(pkg):
        zs = ZenPkg(stock(pkg))
        w, _ = props_of(zs, zs.export_index(pkg.rsplit('/', 1)[1]), 'LiveWorldData')
        return zs, w
    fz, fw = load(se.SP_FORD_SOURCE[0])
    bz_, bw = load(se.SP_BOAT_SOURCE[0])
    src_ford = desc_named(fw, 'UnitDescList', se.IF_KINDS['ford']['src'][1])
    src_boat = desc_named(bw, 'UnitDescList', se.IF_KINDS['boat']['src'][1])
    turret = {src: mrow for src, mrow, _, _ in se.SP_TURRETS}            # (the Spaceport's turret rows: the Aegis's, the Ford's)
    aegis_rows = dict((r, turret[r]) for r in se.ALLY_TURRETS['Aegis'])
    ford_rows = {f'VE004_grfd_mk15_{p}_Ally_01': (turret[f'VE004_grfd_mk15_{p}_Ally_01'], f'Mk15{p}') for p in ('LB', 'RF', 'LF', 'RB')}
    m22_rows = {src: mrow for src, mrow, _, _ in se.IF_TURRETS}           # (Mission 22's ships' parts: the fleet's own rows)
    assert all(r in NPC_ROWS for r in list(turret.values()) + list(m22_rows.values())), 'a fleet turret row not in DT_SV_NpcMission'
    count, n_parts = {}, 0
    for s in se.if_fleet():
        kind, unit, obj = s['kind'], s['unit'], s['obj']
        K = se.IF_KINDS[kind]
        row = s['row'] or 'sv_sp_boat'                                    # (an unnamed ship: its class's rows, the Spaceport's)
        count[kind] = count.get(kind, 0) + 1
        if kind == 'ford':                     # Mission 16's allied Grindylow, made an enemy, its four Mk 15s by place
            names = port_unit(units, used_ids, z, src_ford, unit, obj, row, [s['point']], s['yaw'], top_number, tgt=True)
            u = unit_named(units, unit)
            clear_flags(u, ('bIsLanding', 'bShowCallSignForAlly'))
            u[2][:] = [(q[0], q[1], True, None) if q[1] == 'bIsEscortedUnit' else q for q in u[2]]
            kids = field_of(objects_of(u)[0], 'ChildAIObjectDescs')[1]
            assert len(kids) == 4, unit
            for ch in kids:
                data = [p for p in ch[2] if p[1] == 'Data'][0][3][2]
                was = [q for q in data if q[1] == 'MissionNpcID'][0][3][1]
                new_row, place_ = ford_rows[was]
                data[:] = [(q[0], q[1], False, ('name', new_row, 0)) if q[1] == 'MissionNpcID' else
                           (q[0], q[1], False, import_from(z, fz, q[3])) if q[1] == 'Class' and q[3] is not None else q
                           for q in data]
                name = f'{obj}_{place_}'
                uid = new_unique_id(used_ids, 'AC8SurvivalMode:' + name)
                ch[2][:] = [(q[0], q[1], False, ('name', name, 0)) if q[1] == 'Name' else
                            (q[0], q[1], False, ('raw', 'UInt32', uid)) if q[1] == 'UniqueID' else
                            (q[0], q[1], False, ('name', 'WD_SurvivalMode_global', 0)) if q[1] == 'WorldDataName' and q[3] is not None
                            else q for q in ch[2]]
                for n in names_in(ch): z.nb.add(n)
        elif kind == 'aegis':                  # Survival's copy of Mission 22's allied Aegis, made an enemy
            names = copy_unit(units, used_ids, z, K['src'][1], unit, 1, top_number, obj, row)
            u = unit_named(units, unit)
            clear_flags(u, ('bIsAttackTargetsException',))
            retag_turrets(field_of(objects_of(u)[0], 'ChildAIObjectDescs')[1], obj, aegis_rows, used_ids, z)
        elif kind == 'boat':                   # Training006's (an enemy already), its SAM launcher on the Spaceport's row
            names = port_unit(units, used_ids, z, src_boat, unit, obj, row, [s['point']], s['yaw'], top_number, tgt=True)
            u = unit_named(units, unit)
            kids = field_of(objects_of(u)[0], 'ChildAIObjectDescs')[1]
            assert len(kids) == 1, unit
            retag_parts(kids, obj, used_ids, z, bz_)
            for ch in kids:
                data = [p for p in ch[2] if p[1] == 'Data'][0][3][2]
                was = [q for q in data if q[1] == 'MissionNpcID'][0][3][1]
                data[:] = [(q[0], q[1], False, ('name', turret[was], 0)) if q[1] == 'MissionNpcID' else q for q in data]
                z.nb.add(turret[was])
        else:                                  # Mission 22's enemy fleet (EA_Unit_01_Ship0..3): one of its ships alone
            names = fleet_copy_object(units, used_ids, z, K['src'][1], K['src'][2], unit, obj, row, top_number)
            u = unit_named(units, unit)
            fleet_parts(field_of(objects_of(u)[0], 'ChildAIObjectDescs')[1], obj, m22_rows, used_ids, z, se.IF_M22_PLACES)
        assert names == [obj], (unit, names)

        def part_names(children):              # (as event args write them: build_fleet orders each one)
            out = []
            for ch in children:
                n = [q for q in ch[2] if q[1] == 'Name'][0][3]
                out.append(n[1] if n[2] == 0 else f'{n[1]}_{n[2] - 1}')
                gc = [q for q in ch[2] if q[1] == 'GrandChildrens']
                if gc and gc[0][3]: out += part_names(gc[0][3][1])
            return out
        got = part_names((field_of(objects_of(u)[0], 'ChildAIObjectDescs') or ('arr', []))[1])
        assert sorted(got) == sorted(s['parts']), (unit, got, s['parts'])
        n_parts += len(got)
        enemy_unit(u)
        place(u, s['point'], s['yaw'], [s['point']])
        unit_area(u, se.IF_AREA_M, se.IF_ALT_M)
        lane = s['lane']
        ahead = (2 * lane[-1][0] - lane[-2][0], 2 * lane[-1][1] - lane[-2][1], lane[-1][2])
        paths.append(fleet_path(z, used_ids, lane_t, s['path'], lane, before=s['point'], after=ahead))
    course = se.if_course()
    km = sum(math.dist(a, b) for a, b in zip(course, course[1:])) / 1e5
    changed = [field_of(u, 'Name') for u, s in zip(units, was_units) if sig(u) != s]
    changed += [field_of(p, 'Name') for p, s in zip(paths, was_paths) if sig(p) != s]
    assert not changed, f'the fleet changed descs that were there before it (it may only add): {changed[:5]}'
    assert len(units) == len(was_units) + len(se.if_fleet()) and len(paths) == len(was_paths) + len(se.if_fleet())
    print(f'  invincible fleet: {len(se.if_fleet())} ships (' + ', '.join(f'{n} {k}' for k, n in count.items())
          + f'), {n_parts} parts; lanes of {len(course)} points, {km:.1f} km (in from {se.IF_START_KM:.0f} km, the station '
          f'{se.IF_HOLD_KM:.0f}-{se.IF_SHELL_KM:.0f} km out, {se.IF_LAPS} laps) at {se.IF_SPEED} km/h; the '
          f'{len(was_units)} units and {len(was_paths)} paths there before it unchanged; '
          + (f'no import added ({was_imports})' if len(z.imports) == was_imports else
             f'{len(z.imports) - was_imports} imports added ({was_imports} -> {len(z.imports)})'))


def fleet_npc_rows(rows, m22):
    """DT_SV_NpcRows' fleet rows: Mission 22's ships' turrets (IF_TURRETS: copies of their stock rows, a child (the Kirov's
    gun mount's artillery) on the fleet's copy) and each named ship's hull (its class's stock hull row on its own model row,
    its class key as its second line, every ChildNPCId the fleet's copy: the Spaceport's turret rows for the Ford and the
    Aegis, IF_TURRETS' for Mission 22's: a ship's parts spawn on the rows its hull's row names, hard rule 38).
    rows: DT_NPC's rows; m22: Mission 22's mission rows -> their NpcIds (mission_npc_ids)."""
    se = survival_events
    schema = uprop.U.schema('LiveNpcDataTable')
    idx = {n: k for k, (n, t) in schema.items()}
    shown = lambda n: n[1] if n[2] == 0 else f'{n[1]}_{n[2] - 1}'
    kid_of = {(stock_npc or m22[src]): npc for src, _, npc, stock_npc in se.SP_TURRETS}
    kid_of.update({stock_npc: npc for _, _, npc, stock_npc in se.IF_TURRETS})
    out, remapped = [], 0

    def copy_row(src):
        nonlocal remapped
        f = se.fname(src)
        row = copy.deepcopy(rows[(f[1], f[2])])
        for i, q in enumerate(row[2]):
            if q[1] == 'ChildNPCId' and q[3]:
                kids = []
                for k in q[3][1]:
                    assert shown(k) in kid_of, f'{src}: its child {shown(k)} has no fleet row (IF_TURRETS / SP_TURRETS)'
                    kids.append(('name', kid_of[shown(k)], 0))
                    remapped += 1
                row[2][i] = (q[0], q[1], q[2], ('arr', kids))
        return row
    for _, _, npc, stock_npc in se.IF_TURRETS:
        assert se.fname(npc)[2] == 0, npc
        out.append(((npc, 0), copy_row(stock_npc)))
    for sh in se.if_fleet():
        if not sh['npc']: continue
        row = copy_row(se.IF_KINDS[sh['kind']]['hull'])
        set_prop(row[2], idx['ModelId'], 'ModelId', ('name', sh['model'], 0))
        set_prop(row[2], idx['GameObjectDisplayName02'], 'GameObjectDisplayName02', s(se.IF_CLASS_KEY + sh['kind'].title()))
        assert se.fname(sh['npc'])[2] == 0, sh['npc']
        out.append(((sh['npc'], 0), row))
    print(f'  invincible fleet: {len(out)} DT_SV_NpcRows rows ({len(se.IF_TURRETS)} turrets of Mission 22\'s ships, '
          f'{len(out) - len(se.IF_TURRETS)} named hulls on their own model rows; {remapped} children on the fleet\'s rows)')
    return out


def fleet_mission_rows():
    """DT_SV_NpcMission's fleet rows (build_npc_table's `extra`: (new row, the Mission 22 row it's shaped as, its NpcId)):
    each named ship's hull and Mission 22's ships' turrets (each shaped as its own Mission 22 mission row)."""
    se = survival_events
    out = [(s['row'], se.IF_KINDS[s['kind']]['shape'], s['npc']) for s in se.if_fleet() if s['row']]
    out += [(mrow, src, npc) for src, mrow, npc, _ in se.IF_TURRETS]
    return out


def fleet_model_rows(crow, idx):
    """DT_SV_ModelRows' fleet rows: each named ship's model row, its class's stock model row (crow: DT_NPC_Model's rows by
    key) with only its name changed (GameObjectDisplayName01: the box's first line) to its name key."""
    se = survival_events
    out = []
    for sh in se.if_fleet():
        if not sh['model']: continue
        f = se.fname(se.IF_KINDS[sh['kind']]['model'])
        assert (f[1], f[2]) in crow, sh['kind']
        row = copy.deepcopy(crow[(f[1], f[2])])
        set_prop(row[2], idx['GameObjectDisplayName01'], 'GameObjectDisplayName01', s(sh['name_key']))
        assert se.fname(sh['model'])[2] == 0, sh['model']
        out.append(((sh['model'], 0), row))
    return out


def check_fleet_build():
    """THE INVINCIBLE FLEET read back from the packages this build saved: every ship's unit by its name (an enemy, not at the
    level's start, no debug area, its one object on its row with a box and the TGT mark, no other mission's callsign
    (GameObjectDisplayNameID02) and no tags, facing the course, at its spawn spot), its parts by the names the records give
    them on the rows their hull's DT_NPC row names, none tagged; its lane (ControlType 1, its points where if_fleet put them,
    every Up straight up); every record (each ship's two events once, RE_SV_IFFleetRemove once, every exec's object / unit /
    path there); the rows (mission -> DT_NPC -> model, the hulls' children all fleet rows, the names' keys; no row twice in
    any of the three tables)."""
    se = survival_events
    plain = lambda n: n[1] if n[2] == 0 else f'{n[1]}_{n[2] - 1}'
    load = lambda path: ZenPkg(data=open(os.path.join(OUT, path[len('/Game/'):]) + '.uasset', 'rb').read())
    zw = load(MI + 'WD_SurvivalMode_global')
    w, _ = props_of(zw, zw.export_index('WD_SurvivalMode_global'), 'LiveWorldData')
    units = {plain(field_of(u, 'Name')): u for u in field_of(w, 'UnitDescList')[1]}
    paths = {plain(field_of(el, 'Name')): el for el in field_of(w, 'AIPathDescList')[1]}

    def table(path, st):
        z = load(path)
        dt, _ = dtx.parse(uprop.Ctx(bytes(z.payloads[0]), z.names), 0, st)
        keys = [plain(('name',) + k) for k, _ in dt['rows']]
        assert len(keys) == len(set(keys)), (path, 'a row twice', sorted({k for k in keys if keys.count(k) > 1})[:5])
        return {plain(('name',) + k): dict((q[1], q[3]) for q in r[2]) for k, r in dt['rows']}
    mission = table(NPC_TABLE, 'LiveNpcMissionDataTable')
    npc = table(DATA + 'DT_SV_NpcRows', 'LiveNpcDataTable')
    model = table(DATA + 'DT_SV_ModelRows', 'LiveModelDataTable')
    objs = {}
    fleet = se.if_fleet()
    for s in fleet:
        u = units.get(s['unit'])
        assert u is not None, f"{s['unit']} not in the world data"
        assert field_of(u, 'Faction')[2][2] == b'\x02' and not field_of(u, 'bIsSpawnFromStart') \
            and not (field_of(u, 'Tags') or ('arr', []))[1], s['unit']
        assert field_of(u, 'bShowDebugArea') in (None, ('raw', 'Bool', b'\x00')), (s['unit'], 'bShowDebugArea on')
        assert math.dist(spot_of(u), s['point']) < 1.0, (s['unit'], spot_of(u))
        obs = objects_of(u)
        assert [plain(field_of(ob, 'Name')) for ob in obs] == [s['obj']], s['unit']
        ob = obs[0]
        # (the review of 8ca3195, finding 3) no other mission's callsign, no tags on the ship or its parts
        assert field_of(ob, 'GameObjectDisplayNameID02') is None, (s['obj'], field_of(ob, 'GameObjectDisplayNameID02'))
        assert not (field_of(ob, 'Tags') or ('arr', []))[1], (s['obj'], field_of(ob, 'Tags'))
        row = plain(field_of(ob, 'MissionNpcID'))
        assert row == (s['row'] or 'sv_sp_boat'), (s['unit'], row)
        assert field_of(ob, 'TargetMarkType')[2][2] == b'\x01' and field_of(ob, 'bShowHUDBox') == ('raw', 'Bool', b'\x01'), s['unit']
        assert abs(struct.unpack('<3d', field_of(ob, 'Rotation')[2])[1] - s['yaw']) < 0.01, s['unit']
        assert math.dist(spot_of(ob), s['point']) < 1.0 and not field_of(ob, 'bIsAttackTargetsException'), s['unit']
        objs[s['obj']] = s['unit']
        # its rows: mission -> DT_NPC (a named ship's own, its model's name key; a picket the Spaceport's boat) -> children
        nid = plain(mission[row]['NpcId'])
        if s['npc']:
            assert nid == s['npc'] and plain(npc[nid]['ModelId']) == s['model'], (s['unit'], nid)
            assert model[s['model']]['GameObjectDisplayName01'] == ('str', s['name_key']), (s['model'], model[s['model']]['GameObjectDisplayName01'])
            assert npc[nid]['GameObjectDisplayName02'] == ('str', se.IF_CLASS_KEY + s['kind'].title()), nid
        kids_rows = {plain(k) for k in (npc[nid]['ChildNPCId'] or ('arr', []))[1]}
        got = []

        def walk(chs):
            for ch in chs:
                n = plain(field_of(ch, 'Name'))
                got.append(n)
                objs[n] = s['unit']
                prow = plain(field_of(field_of(ch, 'Data'), 'MissionNpcID'))
                assert prow in mission, (n, prow)
                for tags in (field_of(ch, 'Tags'), field_of(field_of(ch, 'Data'), 'Tags')):
                    assert not (tags or ('arr', []))[1], (n, 'tagged', tags)
                gc = field_of(ch, 'GrandChildrens')
                if gc: walk(gc[1])
        walk((field_of(ob, 'ChildAIObjectDescs') or ('arr', []))[1])
        assert sorted(got) == sorted(s['parts']), (s['unit'], got)
        assert kids_rows and all(k in npc for k in kids_rows), (s['unit'], nid, kids_rows)   # (every child a row of Survival's)
        # its lane
        el = paths.get(s['path'])
        assert el is not None and field_of(el, 'ControlType')[2][2] != b'\x02', s['path']
        pts = [field_of(el, 'BeginPointDesc')] + list(field_of(el, 'PathPointDescList')[1])
        assert len(pts) == len(s['lane']), (s['path'], len(pts))
        for p, want in zip(pts, s['lane']):
            assert math.dist(struct.unpack('<3d', field_of(p, 'Pos')[2]), want) < 1.0, s['path']
            assert struct.unpack('<3d', field_of(p, 'Up')[2]) == (0.0, 0.0, 1.0), (s['path'], 'not level')
    for _, mrow, nrow, _ in se.IF_TURRETS:
        assert plain(mission[mrow]['NpcId']) == nrow and nrow in npc, mrow
    # the records
    ze = load(MI + 'EP_SurvivalMode_global')
    _, _, _, T, E, _ = ep_dump.load_bytes(ze)
    show = lambda v: ep_dump.show(v, ze)
    trig = [show(ep_dump.fields(t)['EventName']) for t in T]
    events = [ev for s in fleet for ev in (s['up'], s['go'])] + ['RE_SV_IFFleetRemove']
    for ev in events:
        assert trig.count(ev) == 1, (ev, trig.count(ev))
    n_ex, kinds = 0, {}
    for e in E:
        f = ep_dump.fields(e)
        ev = show(f['ConnectionEventName'])
        if ev not in events: continue
        n_ex += 1
        args = [show(ep_dump.fields(a)['Value']) for a in f['ArgsInfo'][1]]
        cls = show(f['ExecutionClass'])
        kinds[cls] = kinds.get(cls, 0) + 1
        if cls == 'LiveAIPathExecution':
            assert args[2] in paths and (args[0] in objs or args[1] in units) and float(args[4]) == float(se.IF_SPEED), (ev, args[:5])
        else:
            assert cls in ('LiveAIEngagementOrder', 'LiveDestroyUnitExecution') and any(a in objs or a in units for a in args[:3]), (ev, cls, args[:3])
    want_ex = sum(2 * (2 + 1 + len(s['parts'])) for s in fleet) + len(fleet)
    assert n_ex == want_ex, (n_ex, want_ex)
    print(f'  invincible fleet: {len(fleet)} units, {sum(len(s["parts"]) for s in fleet)} parts, {len(fleet)} lanes, '
          f'{len(events)} events ({n_ex} execs: ' + ', '.join(f'{k} {n}' for k, n in sorted(kinds.items()))
          + ') and their rows read back from the packages: all there')
