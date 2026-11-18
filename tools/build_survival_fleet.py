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
            kids = field_of(objects_of(u)[0], 'ChildAIObjectDescs')[1]
            retag_turrets(kids, obj, aegis_rows, used_ids, z)
            if se.TANI_WD:                     # ((2026-11-17) its two lasers, bow and aft: TANI=1 only)
                kids += aegis_lasers(z, used_ids, obj, kids)
            if se.TANI_WD and s['name'] == se.IF_RAVEN_ECM['ship']:   # ((2026-11-18) RAVEN's EW mast: the Alicorn's ECM
                kids += raven_ecm(z, used_ids, obj, kids)
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


def raven_ecm(z, used_ids, obj, kids):
    """((2026-11-18) the user: "Have the Raven use ECM too") RAVEN's ECM part on BP_SV_IF_Raven's ECM_MAST component, made as
    the Aegis's lasers are (aegis_lasers): a deep copy of its own Mk 15 child (no grandchildren), named <obj>_ECM_MAST, a new
    UniqueID, our world data's name, the Alicorn's ECM mission row (alcn_ecm_01: NPC_IMPORT), a TGT mark, no tags, its Class
    EB_002's `ecm` child's hard import (import_from), the template's dropped (hard rule 34)."""
    se = survival_events
    E = se.IF_RAVEN_ECM
    ebz = ZenPkg(stock(E['wd']))
    eb, _ = props_of(ebz, ebz.export_index(E['wd'].rsplit('/', 1)[1]), 'LiveWorldData')
    src = desc_named(eb, 'UnitDescList', E['src_unit'])
    ref = None
    for ch in field_of(objects_of(src)[0], 'ChildAIObjectDescs')[1]:
        data = field_of(ch, 'Data')[2]
        if field_of_list(data, 'ComponentFieldName')[1] == E['part']:
            ref = field_of_list(data, 'Class')
    assert ref and ref[0] == 'obj' and ref[1] < 0, ('the Alicorn ECM part\'s class import not found', ref)
    cls = import_from(z, ebz, ref)
    tmpl = [ch for ch in kids if field_of(field_of(ch, 'Data'), 'ComponentFieldName') == ('name', 'BP_VE002_aegs_mk15_Base', 0)]
    assert len(tmpl) == 1 and field_of(tmpl[0], 'GrandChildrens') == ('arr', []), (obj, 'its Mk 15 child changed')
    ch = copy.deepcopy(tmpl[0])
    data = field_of(ch, 'Data')[2]
    put(data, 'LiveChildAIObjectData', 'MissionNpcID', ('name', E['row'], 0))
    put(data, 'LiveChildAIObjectData', 'ComponentFieldName', se.fname(E['comp']))
    put(data, 'LiveChildAIObjectData', 'Class', cls)
    put(data, 'LiveChildAIObjectData', 'TargetMarkType', ('enum', 'ELiveTargetMarkType', ('raw', 'Byte', b'\x01')))
    put(data, 'LiveChildAIObjectData', 'Tags', ('arr', []))
    name = f'{obj}_{E["comp"]}'
    put(ch[2], 'LiveChildAIObjectDesc', 'Name', se.fname(name))
    put(ch[2], 'LiveChildAIObjectDesc', 'UniqueID', ('raw', 'UInt32', new_unique_id(used_ids, 'AC8SurvivalMode:' + name)))
    put(ch[2], 'LiveChildAIObjectDesc', 'WorldDataName', ('name', 'WD_SurvivalMode_global', 0))
    put(ch[2], 'LiveChildAIObjectDesc', 'GrandChildrens', ('arr', []))
    bad = [x for x in obj_refs(ch) if x != cls]
    assert not bad, (name, 'a foreign object reference kept (hard rule 34)', bad)
    for nm in names_in(ch) + [E['row'], E['comp']]: z.nb.add(nm)
    print(f'  invincible fleet: RAVEN\'s ECM_MAST carries the Alicorn\'s ECM ({E["npc"]}, its class from {E["wd"].rsplit("/", 1)[1]})')
    return [ch]


def field_of_list(data, name):                           # (a property list's value by name, or None)
    for q in data:
        if q[1] == name: return q[3]
    return None


def aegis_lasers(z, used_ids, obj, kids):
    """((2026-11-17) the user: two LaserInterceptors on each Aegis, bow and aft, targetable) An Aegis's two laser parts
    (survival_events.IF_AEGIS_LASERS on BP_SV_IF_Aegis's components), as THE TANACORN's live parts are made
    (build_survival_world.tanicorn_live_unit): a deep copy of its own Mk 15 child (no grandchildren), named <obj>_<component>,
    a new UniqueID, our world data's name, the LASER mount's mission row, a TGT mark, no tags, its Class a hard import of the
    mount's blueprint in the Tanicorn container (hard rule 7), the template's class import dropped (hard rule 34)."""
    se = survival_events
    L = se.IF_AEGIS_LASER
    tmpl = [ch for ch in kids if field_of(field_of(ch, 'Data'), 'ComponentFieldName') == ('name', 'BP_VE002_aegs_mk15_Base', 0)]
    assert len(tmpl) == 1 and field_of(tmpl[0], 'GrandChildrens') == ('arr', []), (obj, 'its Mk 15 child changed')
    cls = import_class(z, L['bp'], L['bp_class'])
    out = []
    for comp in se.IF_AEGIS_LASERS:
        ch = copy.deepcopy(tmpl[0])
        data = field_of(ch, 'Data')[2]
        put(data, 'LiveChildAIObjectData', 'MissionNpcID', ('name', L['row'], 0))
        put(data, 'LiveChildAIObjectData', 'ComponentFieldName', se.fname(comp))
        put(data, 'LiveChildAIObjectData', 'Class', cls)
        put(data, 'LiveChildAIObjectData', 'TargetMarkType', ('enum', 'ELiveTargetMarkType', ('raw', 'Byte', b'\x01')))
        put(data, 'LiveChildAIObjectData', 'Tags', ('arr', []))
        name = f'{obj}_{comp}'
        assert not name.rpartition('_')[2].isdigit(), name                  # (hard rule 17)
        put(ch[2], 'LiveChildAIObjectDesc', 'Name', se.fname(name))
        put(ch[2], 'LiveChildAIObjectDesc', 'UniqueID', ('raw', 'UInt32', new_unique_id(used_ids, 'AC8SurvivalMode:' + name)))
        put(ch[2], 'LiveChildAIObjectDesc', 'WorldDataName', ('name', 'WD_SurvivalMode_global', 0))
        put(ch[2], 'LiveChildAIObjectDesc', 'GrandChildrens', ('arr', []))
        bad = [x for x in obj_refs(ch) if x != cls]
        assert not bad, (name, 'a foreign object reference kept (hard rule 34)', bad)
        for n in names_in(ch) + [L['bp'], L['bp_class'], L['row'], comp]: z.nb.add(n)
        out.append(ch)
    return out


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
        if sh['kind'] == 'aegis' and se.TANI_WD:   # ((2026-11-17) its lasers' rows by their components, as a stock ship's)
            ecm = sh['name'] == se.IF_RAVEN_ECM['ship']   # ((2026-11-18) and RAVEN's ECM mast's)
            for name, add in (('ChildNPCId', [('name', se.IF_AEGIS_LASER['npc'], 0)] * len(se.IF_AEGIS_LASERS)
                               + ([('name', se.IF_RAVEN_ECM['npc'], 0)] if ecm else [])),
                              ('ChildNPCComponentNames', [se.fname(c) for c in se.IF_AEGIS_LASERS]
                               + ([se.fname(se.IF_RAVEN_ECM['comp'])] if ecm else []))):
                i = [k for k, q in enumerate(row[2]) if q[1] == name][0]
                q = row[2][i]
                row[2][i] = (q[0], q[1], q[2], ('arr', list(q[3][1] if q[3] else []) + add))
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
        if sh['kind'] == 'aegis' and se.TANI_WD:   # ((2026-11-17) on BP_SV_IF_Aegis: its two lasers' components)
            bp, bpc = se.IF_AEGIS_BP, se.IF_AEGIS_BP_CLASS
            if sh['name'] == se.IF_RAVEN_ECM['ship']:   # ((2026-11-18) RAVEN's own: the Aegis's + its ECM mast)
                bp, bpc = se.IF_RAVEN_ECM['bp'], se.IF_RAVEN_ECM['bp_class']
            row[2][:] = [(q[0], q[1], q[2], ('soft', ('name', bp, 0), ('name', bpc, 0), ''))
                         if q[1] == 'BlueprintClass' else q for q in row[2]]
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
        # (every child a row of Survival's; RAVEN's ECM the Alicorn's row, which main.lua adds at the main menu: survival_events
        # IF_RAVEN_ECM, build_alicorn_rows' DT_SV_AlcnNpc)
        alcn = {se.IF_RAVEN_ECM['npc']} if s['name'] == se.IF_RAVEN_ECM['ship'] else set()
        assert kids_rows and all(k in npc or k in alcn for k in kids_rows), (s['unit'], nid, kids_rows)
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
        elif cls == 'LiveAIChangeEnemySearchType':                    # ((2026-11-16) each unit air-only: its guns on you)
            assert args[1] in units and args[3] == 'AIR_ONLY', (ev, args[:4])
        else:
            assert cls in ('LiveAIEngagementOrder', 'LiveDestroyUnitExecution') and any(a in objs or a in units for a in args[:3]), (ev, cls, args[:3])
    want_ex = sum(2 * (2 + 1 + 1 + len(s['parts'])) for s in fleet) + len(fleet)   # (paths 2, order 1, search 1, parts)
    assert n_ex == want_ex, (n_ex, want_ex)
    print(f'  invincible fleet: {len(fleet)} units, {sum(len(s["parts"]) for s in fleet)} parts, {len(fleet)} lanes, '
          f'{len(events)} events ({n_ex} execs: ' + ', '.join(f'{k} {n}' for k, n in sorted(kinds.items()))
          + ') and their rows read back from the packages: all there')


# ---------------------------------------------------------------- THE TANACORN's railguns: their arm and row (stage 4)
# (2026-11-12, docs/re/TANICORN.md "Railguns and railcannon"; the route chosen by the stage-4 research's weapon topic, two
# dry runs) the sub-railguns RAILGUN_L / _R fire the Alicorn's own round BP_wp_emls_alcn from an arm of ours: the T16's
# proven BP_FCS_Vessel_Artillery_00 (BoneControl on TurretPoseableMesh, BN_turret_yaw / BN_turret_pitch, the GUN prefix)
# copied as survival_events.TANI_RAIL_ARM, its 7 imports of the artillery shell put on the round's 7 public exports by
# role (1:1: no null import, unlike the ZFA's laser), its launcher a LauncherTripleRailCannon (the x40a RailGun's class
# and template ids: the TripleRailCannon VALKA fired on our exact bones) for hard rule 45's minimap line and RAILGUN
# WARNING, its properties rewritten BY NAME (an unversioned subclass gives its own fields the low indexes: copied by
# index, BoneControl's first fields read back as HUDControl ...); its arm's search 18 km, its fire 18 km (CaptureDistance).
# (The generator review of 2026-11-12: the row's AI module Turret500, kept, sets a turret's search in game (30 km:
# docs/re/AIRFIELD_SUPPLY.md 4a), so they likely track from 30 km and fire inside 18 km; the ZFA's row clears its module
# for the arm's own, untried on a turret.) Its row TANI_RAIL_FCS (the T16's
# NPC_FCS_VesselArtillery000 copied: its AI module Turret500 kept, its NpcWeaponId (Artillery_Vessel_000: damage 40,
# 4000 km/h) cleared so the round keeps its own values) in a table of its own (DT_SV_NpcFCS holds the ZFA's row only:
# check_zfa_laser_build), which Scripts/sv_tanicorn.lua copies whole into DT_NPC_FCS at the main menu. Imports only
# stock packages: in every build. TANI_RAIL_LAUNCHER 'bone' keeps the T16's BoneControl (only the round changed): the
# fallback if a row-named TripleRailCannon misbehaves (it has never fired with its own AI: VALKA's fired on command).
TANI_RAIL_ROLES = {'BP_wp_artillery_vesselgun_C': 'BP_wp_emls_alcn_C',
                   'Default__BP_wp_artillery_vesselgun_C': 'Default__BP_wp_emls_alcn_C',
                   'WeaponCollisionEffectModule': 'WeaponCollisionEffectModule', 'Artillery Movement': 'Bullet Movement',
                   'Fire Particles NS': 'Fire Particles NS', 'DefaultSceneRoot_GEN_VARIABLE': 'DefaultSceneRoot_GEN_VARIABLE',
                   'Static Mesh': 'Static Mesh'}
# (2026-11-16, the autotest's first runs of route (iv): the TripleRailCannon fired the round (11 km/s) but its barrels never
# turned: yaw and pitch at rest through 4 orders, the rounds leaving ~180 deg off them. It's the x40a's plane-fixed railgun
# (FixAngleYaw / FixAnglePitch): the plane aims, the launcher doesn't. The stock Alicorn's own sub-railguns fly
# LauncherAlicornRailgun, a bare LauncherBoneControl subclass, with no railgun HUD fields either. So 'bone': the T16's
# proven BoneControl tracks and fires the Alicorn's round; no minimap line or RAILGUN WARNING from these two)
TANI_RAIL_LAUNCHER = 'bone'
TANI_RAIL_PERFORMANCE = {'FireRate': 6, 'MagazineCapacity': 1, 'ReloadTime': 10.0, 'bEnableSpinUp': True, 'SpinUpTime': 3.0}
TANI_RAIL_FIRE_CONTROL = {'CaptureDistance': 1800000.0, 'CaptureMinDistance': 10000.0, 'CaptureAngleRange': 10.0,
                          'ActivationTime': 0.6, 'TriggeringTime': 10.0, 'TriggerCount': 1, 'ShotIntervalTime': 10.0,
                          'RestingTime': 10.0, 'PredictionOffsetTime': 0.5}
TANI_RAIL_SEARCH_CM = (1800000.0, 1900000.0)        # its AIControlCommon's lock / loss radius (cm): the round's 18 km (the
                                                    # row's Turret500 module likely searches 30 km over it: above)
TANI_RAIL_ROW_VALUES = {'FireRate': 6, 'MagazineCapacity': 1, 'ReloadTime': 10.0, 'SlotNum': 1, 'bEnableSpinUp': True,
                        'SpinUpTime': 3.0, 'PredictionOffsetTime': 0.5, 'CaptureDistance': 18000.0, 'CaptureMinDistance': 100.0,
                        'CaptureAngleRange': 10.0, 'ActivationTime': 0.6, 'TriggeringTime': 10.0, 'TriggerCount': 1,
                        'ShotIntervalTime': 10.0, 'RestingTime': 10.0, 'YawSpeed': 90.0, 'YawAngleMin': -180.0,
                        'YawAngleMax': 180.0, 'PitchSpeed': 90.0, 'PitchAngleMin': 0.0, 'PitchAngleMax': 90.0}
TANI_RAIL_ROW_CLEAR = ('NpcWeaponId', 'ActivationRandomTimeMin', 'ActivationRandomTimeMax')
# ((2026-11-18) the display arm's: never a shot (one round, a reload longer than any fight), its line and HUD only)
TANI_RAIL_DISP_PERFORMANCE = {'FireRate': 1, 'MagazineCapacity': 1, 'ReloadTime': 9999.0, 'bEnableSpinUp': True, 'SpinUpTime': 9999.0}
TANI_RAIL_DISP_ROW_VALUES = {'FireRate': 1, 'MagazineCapacity': 1, 'ReloadTime': 9999.0, 'SlotNum': 1, 'bEnableSpinUp': True,
                             'SpinUpTime': 9999.0}
TANI_RAIL_ARM_CLASS = 'BP_FCS_Vessel_Artillery_00_C'  # (its class export keeps its name: a zen package's export hashes are
                                                       # package-relative, as the ZFA's BP_FCS_Vessel_CIWS_00_C)


def build_tani_rail():
    """THE TANACORN's railguns' arm survival_events.TANI_RAIL_ARM and its row TANI_RAIL_FCS in TANI_RAIL_FCS_TABLE (above);
    ((2026-11-18) the user: her railguns' red lines on the minimap) and their display arm TANI_RAIL_DISP_ARM (a TripleRailCannon
    that never fires: its minimap line and RAILGUN HUD on) on its row TANI_RAIL_DISP_FCS, the same table."""
    se = survival_events
    cls = rail_arm(se.TANI_RAIL_ARM, TANI_RAIL_LAUNCHER, TANI_RAIL_PERFORMANCE)
    dcls = rail_arm(se.TANI_RAIL_DISP_ARM, 'triple', TANI_RAIL_DISP_PERFORMANCE)

    def row_edit(arm, acls, values):
        def edit(props):
            zfa_tls_set(props, 'LiveNpcFCSDataTable', 'FCSBlueprintClass', ('soft', ('name', arm, 0), ('name', acls, 0), ''))
            for f in TANI_RAIL_ROW_CLEAR:
                zfa_tls_set(props, 'LiveNpcFCSDataTable', f, zero=True)
            for f, x in values.items():
                zfa_tls_set(props, 'LiveNpcFCSDataTable', f, zfa_tls_value('LiveNpcFCSDataTable', f, x))
        return edit
    build_rows_table('/Game/Datatables/AI/NPC/FCS/DT_NPC_FCS', se.TANI_RAIL_FCS_TABLE, 'LiveNpcFCSDataTable',
                     se.TANI_RAIL_FCS_ROW_SOURCE, se.TANI_RAIL_FCS, row_edit(se.TANI_RAIL_ARM, cls, TANI_RAIL_ROW_VALUES),
                     more=[(se.TANI_RAIL_DISP_FCS, row_edit(se.TANI_RAIL_DISP_ARM, dcls, TANI_RAIL_DISP_ROW_VALUES))])
    print(f'  tanicorn rail: its rows {se.TANI_RAIL_FCS} (firing) and {se.TANI_RAIL_DISP_FCS} (the minimap line\'s, never firing) '
          f'in {se.TANI_RAIL_FCS_TABLE.rsplit("/", 1)[1]} (from {se.TANI_RAIL_FCS_ROW_SOURCE}, their NpcWeaponId cleared)')


def rail_arm(arm_path, launcher, performance):
    """One of THE TANACORN's railgun arms at arm_path: the vessel artillery's arm firing the Alicorn's round from a `launcher`
    ('bone': BoneControl, which turns her barrels; 'triple': TripleRailCannon, its minimap line and RAILGUN HUD cooked on)
    with `performance`, its AI the round's 18 km -> its class's name."""
    import copy
    se = survival_events
    u64 = zfa_tls_u64
    z = ZenPkg(stock(se.TANI_RAIL_ARM_SOURCE))
    TANI_RAIL_LAUNCHER_ = launcher
    old_w, new_w, trc = (ZenPkg(stock(p)) for p in (se.TANI_RAIL_OLD_WEAPON, se.TANI_RAIL_ROUND, se.TANI_RAIL_LAUNCHER_SOURCE))
    pub = lambda zz: {u64(e, 56): zz.export_name(i) for i, e in enumerate(zz.exports) if u64(e, 56)}
    old_pub, new_pub = pub(old_w), {n: h for h, n in pub(new_w).items()}
    assert sorted(old_pub.values()) == sorted(TANI_RAIL_ROLES), ('the artillery shell changed', sorted(old_pub.values()))
    assert sorted(new_pub) == sorted(TANI_RAIL_ROLES.values()), ('the railgun round changed', sorted(new_pub))
    assert z.imp_pkgs == [se.TANI_RAIL_OLD_WEAPON], z.imp_pkgs
    # 1. the round: each import of the shell's onto the round's export of its role
    k = z.imp_pkgs.index(se.TANI_RAIL_OLD_WEAPON)
    mine = [i for i, x in enumerate(z.imports) if x >> 62 == 2 and (x >> 32) & 0x3fffffff == k]
    role = {i: old_pub[z.imp_hashes[z.imports[i] & 0xffffffff]] for i in mine}
    assert sorted(set(role.values())) == sorted(TANI_RAIL_ROLES), role
    for i in mine:
        z.imp_hashes[z.imports[i] & 0xffffffff] = new_pub[TANI_RAIL_ROLES[role[i]]]
    z.set_imported_package(se.TANI_RAIL_OLD_WEAPON, se.TANI_RAIL_ROUND)
    # 2. the launcher: its numbers, and (triple) TripleRailCannon's class and template ids, its properties by name
    li = z.export_index('LiveFCSModule_LauncherBoneControl_0')
    v, rest = props_of(z, li, 'LiveFCSModule_LauncherBoneControl')
    have = {q[1]: q[3] for q in v[2] if not q[2]}
    perf, fc = copy.deepcopy(have['Performance']), copy.deepcopy(have['FireControl'])
    for f, x in performance.items():
        zfa_tls_set(perf[2], perf[1], f, zfa_tls_value(perf[1], f, x))
    for f, x in TANI_RAIL_FIRE_CONTROL.items():
        zfa_tls_set(fc[2], fc[1], f, zfa_tls_value(fc[1], f, x))
    assert TANI_RAIL_LAUNCHER_ in ('triple', 'bone'), TANI_RAIL_LAUNCHER_
    if TANI_RAIL_LAUNCHER_ == 'triple':
        el = trc.export_index('LiveFCSModule_LauncherTripleRailCannon_0')
        c0, t0 = u64(z.exports[li], 32), u64(z.exports[li], 48)
        c1, t1 = u64(trc.exports[el], 32), u64(trc.exports[el], 48)
        assert c1 >> 62 == 1 and t1 >> 62 == 1, 'script imports'
        assert z.imports.count(c0) == 1 and z.imports.count(t0) == 1, 'launcher ids'
        z.imports = [c1 if x == c0 else t1 if x == t0 else x for x in z.imports]
        struct.pack_into('<Q', z.exports[li], 32, c1)
        struct.pack_into('<Q', z.exports[li], 48, t1)
        sn = 'LiveFCSModule_LauncherTripleRailCannon'
        tv = ('struct', sn, [])
        for q in v[2]:
            if q[1] not in ('Performance', 'FireControl'):
                zfa_tls_set(tv[2], sn, q[1], copy.deepcopy(q[3]), zero=q[2])
        zfa_tls_set(tv[2], sn, 'ForceAlertDisp', ('raw', 'Bool', b'\x01'))
        zfa_tls_set(tv[2], sn, 'IsDispRadarMap', ('raw', 'Bool', b'\x01'))
        zfa_tls_set(tv[2], sn, 'HUDControl', ('enum', 'ELiveFCSRailGunHUDControl', ('raw', 'Byte', b'\x01')))
    else:
        sn, tv = 'LiveFCSModule_LauncherBoneControl', copy.deepcopy(v)
    zfa_tls_set(tv[2], sn, 'Performance', perf)
    zfa_tls_set(tv[2], sn, 'FireControl', fc)
    z.payloads[li] = bytearray(write_props(z, tv) + rest)
    # 3. its AI: the round's 18 km
    ai = z.export_index('LiveFCSModule_AIControlCommon_0')
    av, arest = props_of(z, ai, 'LiveFCSModule_AIControlCommon')
    for f, r in zip(('EnemySearchLockAreaBounds', 'EnemySearchLossAreaBounds'), TANI_RAIL_SEARCH_CM):
        b = copy.deepcopy([q[3] for q in av[2] if q[1] == f][0])
        zfa_tls_set(b[2], b[1], 'Radius', zfa_tls_value(b[1], 'Radius', r))
        zfa_tls_set(av[2], av[1], f, b)
    z.payloads[ai] = bytearray(write_props(z, av) + arest)
    # 4. under Survival's path
    z.rename(se.TANI_RAIL_ARM_SOURCE, arm_path)
    assert arm_path in z.names and se.TANI_RAIL_ARM_SOURCE not in z.names
    for i, s_ in ((li, sn), (ai, 'LiveFCSModule_AIControlCommon')):
        props_of(z, i, s_)                                  # (each reads back and round-trips)
    save(z, arm_path)
    cls = z.export_name(0)
    assert cls == TANI_RAIL_ARM_CLASS, cls
    print(f'  tanicorn rail: {arm_path} ({cls}: {se.TANI_RAIL_ARM_SOURCE.rsplit("/", 1)[1]} firing '
          f'{se.TANI_RAIL_ROUND.rsplit("/", 1)[1]} from a {sn[len("LiveFCSModule_"):]}, {len(mine)} imports moved, search '
          f'{TANI_RAIL_SEARCH_CM[0] / 100000:g} km)')
    return cls


def check_tani_rail_build():
    """(2026-11-12) The railguns' arm, its row and the rail parts' rows read back from the packages this build saved, and
    the names Lua uses for them (Scripts/sv_tanicorn.lua: TANI.rail_fcs, TANI.rail; the live parts' text is
    check_tanicorn_build's)."""
    se = survival_events
    plain = lambda n: n[1] if n[2] == 0 else f'{n[1]}_{n[2] - 1}'
    load = lambda path: ZenPkg(data=open(os.path.join(OUT, path[len('/Game/'):]) + '.uasset', 'rb').read())
    u64 = zfa_tls_u64
    z = load(se.TANI_RAIL_ARM)
    rnd, trc = ZenPkg(stock(se.TANI_RAIL_ROUND)), ZenPkg(stock(se.TANI_RAIL_LAUNCHER_SOURCE))
    rnd_pub = sorted(u64(e, 56) for e in rnd.exports if u64(e, 56))
    assert z.names[z.name_idx] == se.TANI_RAIL_ARM and z.imp_pkgs == [se.TANI_RAIL_ROUND], (z.names[z.name_idx], z.imp_pkgs)
    got = sorted(set(z.imp_hashes[x & 0xffffffff] for x in z.imports if x >> 62 == 2))
    assert got == rnd_pub, ('the round imports', [hex(h) for h in got])
    wc = dict((q[1], q[3]) for q in props_of(z, z.export_index('LiveFCSModule_ProjectileCommon_0'), 'LiveFCSModule_ProjectileCommon')[0][2])
    w = z.imports[-wc['WeaponClass'][1] - 1]
    assert w >> 62 == 2 and z.imp_hashes[w & 0xffffffff] == export_hash(se.TANI_RAIL_ROUND.rsplit('/', 1)[1] + '_C'), wc
    li = z.export_index('LiveFCSModule_LauncherBoneControl_0')
    if TANI_RAIL_LAUNCHER == 'triple':
        el = trc.export_index('LiveFCSModule_LauncherTripleRailCannon_0')
        assert (u64(z.exports[li], 32), u64(z.exports[li], 48)) == (u64(trc.exports[el], 32), u64(trc.exports[el], 48)), 'launcher'
        sn = 'LiveFCSModule_LauncherTripleRailCannon'
    else:
        sn = 'LiveFCSModule_LauncherBoneControl'
    lc = dict((q[1], q[3]) for q in props_of(z, li, sn)[0][2] if not q[2])
    assert lc['MeshComponentName'] == ('name', 'TurretPoseableMesh', 0), lc.get('MeshComponentName')
    bones = [[b[3] for b in cb[2] if b[1] == 'BoneName'][0] for cb in lc['ControlBones'][1]]
    assert bones == [('name', 'BN_turret_yaw', 0), ('name', 'BN_turret_pitch', 0)], bones
    if sn.endswith('TripleRailCannon'):
        assert lc['HUDControl'][2] == ('raw', 'Byte', b'\x01') and lc['IsDispRadarMap'] == ('raw', 'Bool', b'\x01') \
            and lc['ForceAlertDisp'] == ('raw', 'Bool', b'\x01'), 'hard rule 45 fields'
    fc = dict((q[1], q) for q in lc['FireControl'][2])
    assert fc['LauncherDirection'][3][2] == ('raw', 'Byte', b'\x01'), fc['LauncherDirection']       # SlotSocket
    cls = z.export_name(0)

    def table(path, st):
        zt = load(path)
        dt, _ = dtx.parse(uprop.Ctx(bytes(zt.payloads[0]), zt.names), 0, st)
        return {plain(('name',) + k): dict((q[1], q[3]) for q in r[2]) for k, r in dt['rows']}
    fcs = table(se.TANI_RAIL_FCS_TABLE, 'LiveNpcFCSDataTable')
    assert list(fcs) == [se.TANI_RAIL_FCS, se.TANI_RAIL_DISP_FCS], list(fcs)
    # ((2026-11-18) the display arm: a TripleRailCannon, hard rule 45's fields on, never a shot, on its own row)
    zd = load(se.TANI_RAIL_DISP_ARM)
    ld = dict((q[1], q[3]) for q in props_of(zd, zd.export_index('LiveFCSModule_LauncherBoneControl_0'),
                                              'LiveFCSModule_LauncherTripleRailCannon')[0][2] if not q[2])
    assert ld['HUDControl'][2] == ('raw', 'Byte', b'') and ld['IsDispRadarMap'] == ('raw', 'Bool', b'')         and ld['ForceAlertDisp'] == ('raw', 'Bool', b''), 'the display arm: hard rule 45 fields'
    rd = fcs[se.TANI_RAIL_DISP_FCS]
    assert rd['FCSBlueprintClass'][1] == ('name', se.TANI_RAIL_DISP_ARM, 0), rd['FCSBlueprintClass']
    assert struct.unpack('<f', rd['ReloadTime'][2])[0] >= 9999.0, rd['ReloadTime']
    r = fcs[se.TANI_RAIL_FCS]
    assert r['FCSBlueprintClass'] == ('soft', ('name', se.TANI_RAIL_ARM, 0), ('name', cls, 0), ''), r['FCSBlueprintClass']
    assert r['NpcWeaponId'] is None and r['NpcAIModuleId'] is not None, (r['NpcWeaponId'], r['NpcAIModuleId'])
    assert struct.unpack('<f', r['CaptureDistance'][2])[0] == TANI_RAIL_ROW_VALUES['CaptureDistance'], r['CaptureDistance']
    npc = table(DATA + 'DT_SV_NpcRows', 'LiveNpcDataTable')
    model = table(DATA + 'DT_SV_ModelRows', 'LiveModelDataTable')
    for m in se.TANI_RAIL:
        n = npc[m['npc']]
        assert plain(n['ModelId']) == m['model'], (m['npc'], n['ModelId'])
        assert (n.get('NpcFCSId0') == ('name', m['fcs'], 0)) if m['fcs'] else not n.get('NpcFCSId0'), (m['npc'], n.get('NpcFCSId0'))
        assert (n.get('NpcFCSId1') == ('name', m['fcs1'], 0)) if m.get('fcs1') else not n.get('NpcFCSId1'), (m['npc'], n.get('NpcFCSId1'))
        mo = model[m['model']]
        assert mo['BlueprintClass'][1][1] == m['bp'] and mo['BlueprintClass'][2][1] == m['bp_class'], mo['BlueprintClass']
        assert abs(struct.unpack('<f', mo['MaxHealth'][2])[0] - m['health']) < 1e-3, (m['model'], mo['MaxHealth'])
    lua = open(os.path.join(ROOT, 'mod', 'UE4SS', 'AC8SurvivalMode', 'Scripts', 'sv_tanicorn.lua'), encoding='utf-8').read()
    for want in (f'fcs = "{se.TANI_RAIL_FCS}"', f'table = "{se.TANI_RAIL_FCS_TABLE}.{se.TANI_RAIL_FCS_TABLE.rsplit("/", 1)[1]}"',
                 f'disp = "{se.TANI_RAIL_DISP_FCS}"'):
        assert want in lua, f'Scripts/sv_tanicorn.lua TANI.rail_fcs: no {want}'
    got_l = re.findall(r'\{ rail = "([A-Z_]+)", tag = "([A-Za-z]+)"', lua)
    assert got_l == [(m['part'], m['tag']) for m in se.TANI_RAIL], ('Scripts/sv_tanicorn.lua TANI.rail', got_l)
    # ((the generator review of 2026-11-12, finding 5) what Lua fires and sizes, the world data's: a railgun's event named
    # otherwise in either never orders it (SV_Event on a name with no trigger), a health otherwise rows Lua's live watch wrong)
    hl = re.search(r'health = p\.cannon and ([0-9.]+) or ([0-9.]+)', lua)
    assert hl, 'Scripts/sv_tanicorn.lua TANI.rail: no `health = p.cannon and <railcannon> or <railgun>`'
    for m in se.TANI_RAIL:
        assert abs(float(hl.group(1 if m['part'] == 'RAILCANNON' else 2)) - m['health']) < 1e-3, (m['part'], m['health'], hl.group(0))
    rl = open(os.path.join(ROOT, 'mod', 'UE4SS', 'AC8SurvivalMode', 'Scripts', 'sv_tanicorn_rail.lua'), encoding='utf-8').read()
    om = re.search(r'local ORDER = \{([^}]*)\}', rl)
    assert om, 'Scripts/sv_tanicorn_rail.lua: no `local ORDER = { ... }`'
    got_o = dict(re.findall(r'([A-Z_]+) = "([A-Za-z_]+)"', om.group(1)))
    assert got_o == se.TANI_RAIL_ORDER_EVENTS, ('Scripts/sv_tanicorn_rail.lua ORDER', got_o, se.TANI_RAIL_ORDER_EVENTS)
    print(f'  tanicorn rail: {cls} in {se.TANI_RAIL_ARM} read back ({sn[len("LiveFCSModule_"):]} on TurretPoseableMesh '
          f'BN_turret_yaw / BN_turret_pitch, the round {se.TANI_RAIL_ROUND.rsplit("/", 1)[1]}, its {len(rnd_pub)} exports'
          + (', HUDControl 1, minimap line and alert' if sn.endswith('TripleRailCannon') else '')
          + f'); {se.TANI_RAIL_FCS} names it, no NpcWeaponId; {len(se.TANI_RAIL)} rail parts\' rows and Lua\'s names, health and railgun events read back')
