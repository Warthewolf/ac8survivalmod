"""build_survival.py's part for VALKA's SOLG's lasers (survival_events.SOLG_TLS_*; docs/re/SOLG.md section 11).

The user (2026-11-22): "The Lasers will have to be a custom blueprint as to not affect all the other lasers we are
using, the lasers on the solg will target aircraft but damage them for 5 health every hit". AC:I's SOLG carries 28
laser turrets (f_111t, CONT_LASER UNIT: tools/solg/lasers.py); ours, each a target unit on AC8's land Phalanx
(GR033_ciws_01, enemy) held on its laser bone by Lua, its own meshes hidden (the SOLG's turret dome shows), firing:

- the weapon, BP_SV_SolgTLS: a copy of AC8's anti-aircraft swing laser BP_SwingTLS_ForPlane (its objects keep their
  names, as every copy of ours) with damage and SlipDamage SOLG_TLS_DAMAGE (5: stock 3 and 1). Nothing else uses it.
- the arm, BP_FCS_SV_SolgTLS: a copy of the ships' CIWS arm BP_FCS_Vessel_CIWS_00 (the one the airfield's land Phalanx
  fires through: its turret bones are the Phalanx's) with its weapon imports onto BP_SV_SolgTLS's exports (role by
  role, as build_zfa_laser), its AIControlCIWS after aircraft (bSearchMissileOnly off) within SOLG_TLS_SEARCH_CM.
- its fire-control row SV_FCS_SolgTLS in DT_SV_SolgFCS (its own table): NPC_FCS_VesselCIWS000's on the arm, no weapon
  row (the laser has none), SOLG_TLS_ROW_VALUES (AC:I's laser block: one shot about every 10 s within ~10 km).
Lua (Scripts/sv_solg.lua SOLG.rowsIn) adds the row to DT_NPC_FCS at the main menu; the turret rows (DT_SV_NpcRows
SV_SOLG_LSRA / _LSRB) name it in NpcFCSId0 (build_survival.py build_npc_rows)."""
import copy
import struct

from build_survival import *  # noqa: F401,F403 (build_survival's names; it imports this part at its end)
from build_survival_world import (ZFA_TLS_ROLES, NULL_IMPORT, zfa_tls_u64, zfa_tls_value, zfa_tls_set)  # noqa: E402

# (SOLG -Gould-'s laser handlers, docs/re/SOLG.md 13: 10 s at players within 1200 m, then 5 s)
SOLG_TLS_ROW_VALUES = {'CaptureDistance': 1200.0, 'CaptureAngleRange': 180.0, 'ActivationTime': 1.0,
                       'TriggeringTime': 10.0, 'TriggerCount': 1, 'ShotIntervalTime': 15.0, 'RestingTime': 5.0,
                       'FireRate': 4, 'MagazineCapacity': 1, 'ReloadTime': 5.0,
                       'YawSpeed': 120.0, 'YawAngleMin': -180.0, 'YawAngleMax': 180.0,
                       'PitchSpeed': 120.0, 'PitchAngleMin': -90.0, 'PitchAngleMax': 90.0}
SOLG_TLS_ROW_CLEAR = ('NpcWeaponId', 'PredictionOffsetTime', 'ActivationRandomTimeMin', 'ActivationRandomTimeMax')
SOLG_TLS_SEARCH_CM = (120000.0, 132000.0)
SOLG_TLS_LIFE_S = 10.0                                 # (its beam: Gould's 10 s burst; stock 7)


def build_solg_laser():
    se = survival_events
    # 1. the weapon: BP_SwingTLS_ForPlane with its damage
    w = ZenPkg(stock(se.SOLG_TLS_WEAPON_SOURCE))
    cdo = w.export_index('Default__' + se.SOLG_TLS_WEAPON_SOURCE.rsplit('/', 1)[1] + '_C')
    p = bytes(w.payloads[cdo])
    v, o = uprop.read_struct(uprop.Ctx(p, w.names), 0, 'LiveTLSSwingforPlane')
    assert uprop.write_struct(uprop.W(w.names), v) == p[:o], 'the laser CDO does not round-trip'
    have = {q[1]: q[3] for q in v[2]}
    assert struct.unpack('<f', have['damage'][2])[0] == 3.0 and struct.unpack('<f', have['SlipDamage'][2])[0] == 1.0, \
        ('BP_SwingTLS_ForPlane changed', have['damage'], have['SlipDamage'])
    for f in ('damage', 'SlipDamage'):
        zfa_tls_set(v[2], 'LiveTLSSwingforPlane', f, ('raw', 'Float', struct.pack('<f', se.SOLG_TLS_DAMAGE)))
    zfa_tls_set(v[2], 'LiveTLSSwingforPlane', 'LifeTime', ('raw', 'Float', struct.pack('<f', SOLG_TLS_LIFE_S)))
    w.payloads[cdo] = bytearray(uprop.write_struct(uprop.W(w.names), v) + p[o:])
    w.rename(se.SOLG_TLS_WEAPON_SOURCE, se.SOLG_TLS_WEAPON)
    assert se.SOLG_TLS_WEAPON in w.names and se.SOLG_TLS_WEAPON_SOURCE not in w.names
    chk, _ = uprop.read_struct(uprop.Ctx(bytes(w.payloads[cdo]), w.names), 0, 'LiveTLSSwingforPlane')
    assert struct.unpack('<f', dict((q[1], q[3]) for q in chk[2])['damage'][2])[0] == se.SOLG_TLS_DAMAGE
    save(w, se.SOLG_TLS_WEAPON)
    # 2. the arm: the ships' CIWS arm, its weapon imports onto the laser's exports by role
    roles = {k: (r.replace('ForMSL', 'ForPlane') if r else r) for k, r in ZFA_TLS_ROLES.items()}
    z = ZenPkg(stock(se.ZFA_TLS_FCS_SOURCE))
    old_w, new_w = ZenPkg(stock(se.ZFA_TLS_OLD_WEAPON)), ZenPkg(stock(se.SOLG_TLS_WEAPON_SOURCE))
    pub = lambda zz: {zfa_tls_u64(e, 56): zz.export_name(i) for i, e in enumerate(zz.exports) if zfa_tls_u64(e, 56)}
    old_pub, new_pub = pub(old_w), {n: h for h, n in pub(new_w).items()}
    assert sorted(old_pub.values()) == sorted(roles), ('the CIWS weapon changed', sorted(old_pub.values()))
    assert sorted(new_pub) == sorted(r for r in roles.values() if r), ('the laser changed', sorted(new_pub))
    k = z.imp_pkgs.index(se.ZFA_TLS_OLD_WEAPON)
    mine = [i for i, x in enumerate(z.imports) if x >> 62 == 2 and (x >> 32) & 0x3fffffff == k]
    role = {i: old_pub[z.imp_hashes[z.imports[i] & 0xffffffff]] for i in mine}
    drop = [i for i in mine if roles[role[i]] is None]
    deps = {struct.unpack_from('<i', z.dep_ent, o_)[0] for o_ in range(0, len(z.dep_ent), 4)}
    for i in drop:
        assert -(i + 1) not in deps and all(struct.pack('<i', -(i + 1)) not in bytes(q) for q in z.payloads), (i, role[i])
    for i in mine:
        if i not in drop: z.imp_hashes[z.imports[i] & 0xffffffff] = new_pub[roles[role[i]]]
    for i in sorted(drop, key=lambda i: z.imports[i] & 0xffffffff, reverse=True):
        h = z.imports[i] & 0xffffffff
        z.imports[i] = NULL_IMPORT
        del z.imp_hashes[h]
        z.imports = [x - 1 if x >> 62 == 2 and x & 0xffffffff > h else x for x in z.imports]
    z.set_imported_package(se.ZFA_TLS_OLD_WEAPON, se.SOLG_TLS_WEAPON)
    # its AI: aircraft, within reach
    ai = z.export_index('LiveFCSModule_AIControlCIWS_0')
    v, rest = props_of(z, ai, 'LiveFCSModule_AIControlCIWS')
    zfa_tls_set(v[2], v[1], 'bSearchMissileOnly', ('raw', 'Bool', b'\x00'))
    for f, r in zip(('EnemySearchLockAreaBounds', 'EnemySearchLossAreaBounds'), SOLG_TLS_SEARCH_CM):
        b = copy.deepcopy([q[3] for q in v[2] if q[1] == f][0])
        zfa_tls_set(b[2], b[1], 'Radius', zfa_tls_value(b[1], 'Radius', r))
        zfa_tls_set(v[2], v[1], f, b)
    z.payloads[ai] = bytearray(write_props(z, v) + rest)
    z.rename(se.ZFA_TLS_FCS_SOURCE, se.SOLG_TLS_FCS_PKG)
    assert se.SOLG_TLS_FCS_PKG in z.names and se.ZFA_TLS_FCS_SOURCE not in z.names
    props_of(z, ai, 'LiveFCSModule_AIControlCIWS')
    save(z, se.SOLG_TLS_FCS_PKG)
    cls = z.export_name(0)

    def edit(props):
        zfa_tls_set(props, 'LiveNpcFCSDataTable', 'FCSBlueprintClass', ('soft', ('name', se.SOLG_TLS_FCS_PKG, 0), ('name', cls, 0), ''))
        for f in SOLG_TLS_ROW_CLEAR:
            zfa_tls_set(props, 'LiveNpcFCSDataTable', f, zero=True)
        for f, x in SOLG_TLS_ROW_VALUES.items():
            zfa_tls_set(props, 'LiveNpcFCSDataTable', f, zfa_tls_value('LiveNpcFCSDataTable', f, x))
    build_rows_table('/Game/Datatables/AI/NPC/FCS/DT_NPC_FCS', se.SOLG_TLS_FCS_TABLE, 'LiveNpcFCSDataTable',
                     se.ZFA_TLS_FCS_ROW_SOURCE, se.SOLG_TLS_FCS_ROW, edit)
    print(f'  solg laser: {se.SOLG_TLS_WEAPON} (BP_SwingTLS_ForPlane, {se.SOLG_TLS_DAMAGE:g} a hit), its arm '
          f'{se.SOLG_TLS_FCS_PKG} ({cls}, aircraft within {SOLG_TLS_SEARCH_CM[0] / 100000:g} km; {len(drop)} import '
          f'made null), its row {se.SOLG_TLS_FCS_ROW} in {se.SOLG_TLS_FCS_TABLE.rsplit("/", 1)[1]}')


def check_solg_laser_build():
    se = survival_events
    def table(path, st):
        z = ZenPkg(data=open(os.path.join(OUT, path[len('/Game/'):]) + '.uasset', 'rb').read())
        dt, _ = dtx.parse(uprop.Ctx(bytes(z.payloads[0]), z.names), 0, st)
        return {k[0]: dict((q[1], q[3]) for q in r[2]) for k, r in dt['rows']}
    assert os.path.exists(os.path.join(OUT, se.SOLG_TLS_WEAPON[len('/Game/'):]) + '.uasset'), 'no laser weapon package'
    fcs = table(se.SOLG_TLS_FCS_TABLE, 'LiveNpcFCSDataTable')
    assert se.SOLG_TLS_FCS_ROW in fcs, fcs.keys()
    assert fcs[se.SOLG_TLS_FCS_ROW]['FCSBlueprintClass'][1] == ('name', se.SOLG_TLS_FCS_PKG, 0)
    npc = table(DATA + 'DT_SV_NpcRows', 'LiveNpcDataTable')
    for t in se.SOLG_LASER_TYPES:
        r = npc[se.SOLG_NPC[t]]
        assert r['NpcFCSId0'] == ('name', se.SOLG_TLS_FCS_ROW, 0), (t, r.get('NpcFCSId0'))
    print(f'  solg laser: read back: {se.SOLG_TLS_FCS_ROW} on its arm, {len(se.SOLG_LASER_TYPES)} turret rows fire it')
