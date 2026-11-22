"""ue_import.py : run inside UE 5.4 (tools/solg/build.sh: UnrealEditor-Cmd ue/Live/Live.uproject -run=pythonscript).

Builds AC:I's SOLG under /Game/Mods/SurvivalMode/SOLG from build/solg (tools/solg/prepare.py):
  T_SV_SOLG_<id>          its AC:I textures (colour, sRGB), T_SV_SOLG_FlatN / _FlatL (a neutral normal and Livemap)
  MI_SV_SOLG_<id>         one instance per texture on AC8's general material M_Live_Base (T_Basecolor / T_Normalmap /
                          T_Livemap, as Stonehenge Returns' MI_SH_tex<id>: ordinary textures draw on it; the aircraft
                          paint master needs virtual textures, hard rule 44), no static switches, so the game uses
                          M_Live_Base's own shaders
  SM_SV_SOLG_Body (+_Wreck), SM_SV_SOLG_SG01 .. SG09 (+_Wreck)   static meshes, no collision (visuals only)
  sockets on SM_SV_SOLG_Body: one per part mount (<MODEL>_<nn>: SG04_01 ...; CORE_01 for f_sgc1), and RING_1 / RING_2
AC8's M_Live_Base is stood in for here by a stub at its own path (the parameters the instances set); build.sh never
packs it. AC:I -> UE axes: measured on a probe mesh imported first (glTF's +X left / +Y up / +Z forward, metres), not
assumed; build/solg/ue_import.log has it.
"""
import json, math, os
import unreal

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.normpath(os.path.join(HERE, '..', '..', 'build', 'solg'))
DEST = '/Game/Mods/SurvivalMode/SOLG'
BASE = '/Game/Base/Material/M_Live_Base'
LOG = os.path.join(SRC, 'ue_import.log')

AT = unreal.AssetToolsHelpers.get_asset_tools()
MEL = unreal.MaterialEditingLibrary
EAL = unreal.EditorAssetLibrary
lines = []


def say(msg):
    lines.append(msg)
    unreal.log('[solg] ' + msg)
    with open(LOG, 'w', encoding='utf-8') as f:
        f.write('\n'.join(lines) + '\n')


def fresh(path):
    if EAL.does_asset_exist(path):
        EAL.delete_asset(path)


def stub_material(path, params):
    """A Material at an AC8 material's path with texture parameters `params`, all wired so they're kept."""
    fresh(path)
    pkg, name = path.rsplit('/', 1)
    m = AT.create_asset(name, pkg, unreal.Material, unreal.MaterialFactoryNew())
    default = unreal.load_asset('/Engine/EngineResources/DefaultTexture')
    outputs = [unreal.MaterialProperty.MP_BASE_COLOR, unreal.MaterialProperty.MP_EMISSIVE_COLOR,
               unreal.MaterialProperty.MP_SPECULAR]
    for k, pn in enumerate(params):
        e = MEL.create_material_expression(m, unreal.MaterialExpressionTextureSampleParameter2D, -400, 250 * k)
        e.set_editor_property('parameter_name', pn)
        e.set_editor_property('texture', default)
        MEL.connect_material_property(e, 'RGB' if k < 2 else 'R', outputs[k])
    MEL.recompile_material(m)
    EAL.save_loaded_asset(m)
    say(f'stub {path} ({", ".join(params)})')
    return m


def import_file(src, dest, name=None):
    t = unreal.AssetImportTask()
    t.set_editor_property('filename', src)
    t.set_editor_property('destination_path', dest)
    if name:
        t.set_editor_property('destination_name', name)
    t.set_editor_property('automated', True)
    t.set_editor_property('replace_existing', True)
    t.set_editor_property('save', True)
    AT.import_asset_tasks([t])
    return list(t.get_editor_property('imported_object_paths') or [])


def texture(name, srgb, compression):
    import_file(os.path.join(SRC, name + '.png'), DEST + '/Textures', name)
    tex = unreal.load_asset(f'{DEST}/Textures/{name}')
    tex.set_editor_property('srgb', srgb)
    tex.set_editor_property('compression_settings', compression)
    tex.set_editor_property('virtual_texture_streaming', False)
    EAL.save_loaded_asset(tex)
    say(f'texture {name}: {tex.blueprint_get_size_x()}x{tex.blueprint_get_size_y()}, srgb {srgb}, {compression}')
    return tex


def instance(name, parent, want):
    mi = AT.create_asset(name, DEST + '/Materials', unreal.MaterialInstanceConstant,
                         unreal.MaterialInstanceConstantFactoryNew())
    MEL.set_material_instance_parent(mi, parent)
    vals = []
    for pn, tex in want:          # (as AC8's own instances store them: { Name, GlobalParameter, INDEX_NONE }, value)
        v = unreal.TextureParameterValue()
        v.set_editor_property('parameter_info', unreal.MaterialParameterInfo(pn, unreal.MaterialParameterAssociation.GLOBAL_PARAMETER, -1))
        v.set_editor_property('parameter_value', tex)
        vals.append(v)
    mi.set_editor_property('texture_parameter_values', vals)
    MEL.update_material_instance(mi)
    got = {str(v.get_editor_property('parameter_info').get_editor_property('name')): v.get_editor_property('parameter_value').get_name()
           for v in mi.get_editor_property('texture_parameter_values')}
    assert got == {pn: tex.get_name() for pn, tex in want}, got
    EAL.save_loaded_asset(mi)
    return mi


def import_mesh(gltf, name):
    """One glTF -> one StaticMesh named `name` in DEST/Model; the importer's own materials and textures deleted."""
    before = set(EAL.list_assets(DEST, recursive=True))
    import_file(os.path.join(SRC, gltf), DEST + '/Model')
    made = sorted(set(EAL.list_assets(DEST, recursive=True)) - before)
    meshes = [p.split('.')[0] for p in made if unreal.load_asset(p.split('.')[0]).get_class().get_name() == 'StaticMesh']
    assert len(meshes) == 1, (gltf, made)
    for p in made:
        a = p.split('.')[0]
        if a != meshes[0] and EAL.does_asset_exist(a) and unreal.load_asset(a).get_class().get_name() in (
                'Material', 'MaterialInstanceConstant', 'Texture2D'):
            EAL.delete_asset(a)
    if meshes[0] != f'{DEST}/Model/{name}':
        EAL.rename_asset(meshes[0], f'{DEST}/Model/{name}')
    return unreal.load_asset(f'{DEST}/Model/{name}')


def probe_axes():
    """A one-triangle glTF at AC:I (1, 0, 0), (0, 2, 0), (0, 0, 3) m (+ the origin) -> UE: each AC:I axis's UE axis and
    sign, from the imported bounds (an AC:I axis k lands where the bounds reach 100 x (k + 1) cm)."""
    import struct
    pts = [(0, 0, 0), (1, 0, 0), (0, 2, 0), (0, 0, 3)]
    blob = b''.join(struct.pack('<3f', *p) for p in pts) + struct.pack('<6I', 0, 1, 2, 0, 2, 3)
    g = {'asset': {'version': '2.0'}, 'scene': 0, 'scenes': [{'nodes': [0]}], 'nodes': [{'name': 'probe', 'mesh': 0}],
         'meshes': [{'name': 'probe', 'primitives': [{'attributes': {'POSITION': 0}, 'indices': 1, 'mode': 4}]}],
         'buffers': [{'uri': 'axis_probe.bin', 'byteLength': len(blob)}],
         'bufferViews': [{'buffer': 0, 'byteOffset': 0, 'byteLength': 48}, {'buffer': 0, 'byteOffset': 48, 'byteLength': 24}],
         'accessors': [{'bufferView': 0, 'componentType': 5126, 'count': 4, 'type': 'VEC3', 'min': [0, 0, 0], 'max': [1, 2, 3]},
                       {'bufferView': 1, 'componentType': 5125, 'count': 6, 'type': 'SCALAR'}]}
    open(os.path.join(SRC, 'axis_probe.bin'), 'wb').write(blob)
    json.dump(g, open(os.path.join(SRC, 'axis_probe.gltf'), 'w'))
    m = import_mesh('axis_probe.gltf', 'SM_SV_SOLG_AxisProbe')
    b = m.get_bounding_box()
    lo, hi = b.min, b.max
    lo, hi = (lo.x, lo.y, lo.z), (hi.x, hi.y, hi.z)
    M = [[0, 0, 0] for _ in range(3)]          # UE = M . AC:I (metres -> cm included)
    for k in range(3):                         # AC:I axis k reached 100 * (k + 1) cm on one UE axis
        want = 100.0 * (k + 1)
        for j in range(3):
            if abs(hi[j] - want) < 1:
                M[j][k] = 100.0
            elif abs(lo[j] + want) < 1:
                M[j][k] = -100.0
    say(f'axis probe bounds lo {lo} hi {hi} -> UE = M . AC:I m: {M}')
    for k in range(3):
        assert sum(1 for j in range(3) if M[j][k]) == 1, M
    EAL.delete_asset(f'{DEST}/Model/SM_SV_SOLG_AxisProbe')
    return M


def mul(M, v):
    return [sum(M[j][k] * v[k] for k in range(3)) for j in range(3)]


IDENTITY = [[1, 0, 0], [0, 1, 0], [0, 0, 1]]


def sockets(body, mounts, rings, M):
    """The part mounts as sockets on the body mesh, in UE's frame: location M . p, rotation M R M^T (a proper rotation
    even when M mirrors), as a Rotator from its X / Z axes. p and R are in prepare.py's turned glTF frame."""
    S = [[M[j][k] / 100.0 for k in range(3)] for j in range(3)]      # unit-scale axis map
    St = [[S[k][j] for k in range(3)] for j in range(3)]
    def rotator(R):
        A = [[sum(S[i][a] * R[a][b] for a in range(3)) for b in range(3)] for i in range(3)]
        U = [[sum(A[i][b] * St[b][j] for b in range(3)) for j in range(3)] for i in range(3)]
        x = unreal.Vector(U[0][0], U[1][0], U[2][0]); z = unreal.Vector(U[0][2], U[1][2], U[2][2])
        return unreal.MathLibrary.make_rot_from_xz(x, z)
    made = []
    def add(name, pos_m, R):
        s = unreal.StaticMeshSocket(outer=body)
        s.set_editor_property('socket_name', name)
        p = mul(M, pos_m)
        s.set_editor_property('relative_location', unreal.Vector(p[0], p[1], p[2]))
        s.set_editor_property('relative_rotation', rotator(R))
        body.add_socket(s)
        made.append(name)
        return p
    for mt in mounts:
        key = 'CORE' if mt['model'] == 'f_sgc1' else mt['model'][2:].upper()
        p = add('%s_%02d' % (key, mt['index']), mt['pos_m'], mt['rot_m'])
        if mt['index'] == 1:
            say(f"socket {key}_01 at {[round(v) for v in p]} cm (AC:I {mt['aci_pos_m']} m)")
    for n, pos in sorted(rings.items()):
        add('RING_' + n[-1], pos, IDENTITY)
    say(f'{len(made)} sockets on {body.get_name()}')


# (test T0, 2026-11-03) a static mesh of ours, added on an AI plane at run time, crashed AC8 in its render-proxy setup
# (access violation reading -1; AC8 cooks with ray tracing, Lumen and mesh distance fields on, this project with none):
# the SOLG ships as one skeletal mesh instead, the route VALKA's X-02S proved (hard rule 46). STATIC = True imports the
# static meshes too (for a later test of that path only).
STATIC = False


def import_skeletal(layout, mis, sk_name=None, skel_name=None, anim_names=None):
    """SK_SV_SOLG (+ SKEL_SV_SOLG): the whole SOLG, a bone per piece (prepare.py write_skinned); its slots our
    instances (by slot name: t<texture id>); no physics asset (no collision: the carrier's parts take the hits).
    The reference pose's bones logged against layout.json (the UE frame: (AC.z, -AC.x, AC.y) x 100)."""
    sk_name = sk_name or layout['skeletal']['mesh']
    skel_name = skel_name or 'SKEL_SV_SOLG'
    before = set(EAL.list_assets(DEST, recursive=True))
    import_file(os.path.join(SRC, sk_name + '.gltf'), DEST + '/Model')
    made = sorted(set(EAL.list_assets(DEST, recursive=True)) - before)
    kinds = {}
    for p in made:
        a = p.split('.')[0]
        if EAL.does_asset_exist(a):
            kinds.setdefault(unreal.load_asset(a).get_class().get_name(), []).append(a)
    say(f'skeletal glTF import: { {k: len(v) for k, v in kinds.items()} }')
    assert len(kinds.get('SkeletalMesh', [])) == 1, kinds
    for cls, nm in (('SkeletalMesh', sk_name), ('Skeleton', skel_name)):
        p = kinds[cls][0]
        if p != f'{DEST}/Model/{nm}':
            EAL.rename_asset(p, f'{DEST}/Model/{nm}')
    # ((2026-11-22) its animations (prepare.py: AC:I's own ring spin, A_SV_SOLG_Spin), named as the glTF names them)
    for k, p in enumerate(sorted(kinds.get('AnimSequence', []))):
        want = (anim_names or [])[k] if anim_names and k < len(anim_names) else None
        if want and p != f'{DEST}/Model/{want}':
            EAL.rename_asset(p, f'{DEST}/Model/{want}')
            p = f'{DEST}/Model/{want}'
        a = unreal.load_asset(p)
        try:
            say(f'{p.rsplit("/", 1)[-1]}: an animation of {a.get_editor_property("sequence_length"):.1f} s')
        except Exception as ex:
            say(f'{p.rsplit("/", 1)[-1]}: an animation ({ex})')
        EAL.save_loaded_asset(a)
    sk = unreal.load_asset(f'{DEST}/Model/{sk_name}')
    skel = sk.get_editor_property('skeleton')
    try:
        sk.set_editor_property('physics_asset', None)
    except Exception as ex:
        say(f'physics asset not cleared: {ex}')
    for a in kinds.get('PhysicsAsset', []) + kinds.get('Material', []) + kinds.get('MaterialInstanceConstant', []) + kinds.get('Texture2D', []):
        if EAL.does_asset_exist(a):
            EAL.delete_asset(a)
    mats = list(sk.get_editor_property('materials'))
    names = []
    for s in mats:
        slot = str(s.get_editor_property('material_slot_name'))
        key = next((x for x in mis if x in slot), None)
        if key:
            s.set_editor_property('material_interface', mis[key])
        names.append(slot + ('' if key else ' (NO INSTANCE)'))
    sk.set_editor_property('materials', mats)
    b = sk.get_bounds()
    say(f'{sk_name}: {len(mats)} slots {names}, bounds origin {b.origin} extent {b.box_extent} cm')
    EAL.save_loaded_asset(sk)
    EAL.save_loaded_asset(skel)
    try:
        pose = unreal.AnimPoseExtensions.get_reference_pose(skel)
        bn = [str(n) for n in unreal.AnimPoseExtensions.get_bone_names(pose)]
        want = layout['skeletal']['bones']
        say(f'SKEL_SV_SOLG: {len(bn)} bones (prepare.py made {len(want)}); missing {sorted(set(want) - set(bn))[:10]}, '
            f'extra {sorted(set(bn) - set(want))[:10]}')
        for n in ('SOLG', 'SG08_01', 'CORE_01', 'SG04_01', 'SG05_12', 'SG07_32', 'SG01_04', 'RING_1'):
            if n in bn:
                t = unreal.AnimPoseExtensions.get_bone_pose(pose, n, unreal.AnimPoseSpaces.WORLD).translation
                say(f'  bone {n} at {[round(t.x), round(t.y), round(t.z)]} cm')
    except Exception as ex:
        say(f'bones not read: {type(ex).__name__}: {ex}')


def main():
    layout = json.load(open(os.path.join(SRC, 'layout.json')))
    if EAL.does_directory_exist(DEST):
        EAL.delete_directory(DEST)
    M = probe_axes()
    base = stub_material(BASE, ['T_Basecolor', 'T_Normalmap', 'T_Livemap'])
    flat_n = texture('T_SV_SOLG_FlatN', False, unreal.TextureCompressionSettings.TC_NORMALMAP)
    flat_l = texture('T_SV_SOLG_FlatL', False, unreal.TextureCompressionSettings.TC_DEFAULT)
    mis = {}
    for key, t in sorted(layout['textures'].items()):
        tex = texture(t['file'][:-4], True, unreal.TextureCompressionSettings.TC_DEFAULT)
        mis[key] = instance('MI_SV_SOLG_' + key[1:], base, (('T_Basecolor', tex), ('T_Normalmap', flat_n), ('T_Livemap', flat_l)))
    def no_collision(m):
        """Its simple collision taken off (visuals only); 5.4 builds differ in which helper they have."""
        for get in (lambda: unreal.get_editor_subsystem(unreal.StaticMeshEditorSubsystem),
                    lambda: unreal.EditorStaticMeshLibrary):
            try:
                get().remove_collisions(m)
                return 'removed'
            except Exception:
                continue
        bs = m.get_editor_property('body_setup')
        if bs:
            bs.set_editor_property('collision_trace_flag', unreal.CollisionTraceFlag.CTF_USE_SIMPLE_AS_COMPLEX)
            return 'body setup simple-as-complex (no helper)'
        return 'none to remove'
    import_skeletal(layout, mis, anim_names=['A_SV_SOLG_Spin'])
    for nm in layout.get('panels', []):              # ((2026-11-22) the solar array wings on their own: they fall)
        import_skeletal(layout, mis, nm, 'SKEL_' + nm[3:])
    for name, info in sorted(layout['meshes'].items()):
        if not STATIC:
            break
        m = import_mesh(name + '.gltf', name)
        mats = list(m.get_editor_property('static_materials'))
        for k, s in enumerate(mats):
            slot = str(s.get_editor_property('material_slot_name'))
            key = next((x for x in mis if x in slot), info['materials'][min(k, len(info['materials']) - 1)])
            s.set_editor_property('material_interface', mis[key])
        m.set_editor_property('static_materials', mats)
        col = no_collision(m)
        b = m.get_bounding_box()
        say(f'{name}: {len(mats)} slots {[str(s.get_editor_property("material_slot_name")) for s in mats]}, collision {col}, '
            f'bounds {[round(b.min.x), round(b.min.y), round(b.min.z)]} .. {[round(b.max.x), round(b.max.y), round(b.max.z)]} cm '
            f'(AC:I {info["min_m"]} .. {info["max_m"]} m)')
        if name == 'SM_SV_SOLG_Body':
            sockets(m, layout['mounts'], layout['rings'], M)
        EAL.save_loaded_asset(m)
    for a in sorted(x.split('.')[0] for x in EAL.list_assets(DEST, recursive=True)):
        say(f'  {a}: {unreal.load_asset(a).get_class().get_name()}')
    say('done')


try:
    main()
except Exception as ex:
    say(f'FAILED: {type(ex).__name__}: {ex}')
    raise
