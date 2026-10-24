"""ue_import.py : run inside UE 5.4 (tools/x02s/build.sh: UnrealEditor-Cmd ue/Live/Live.uproject -run=pythonscript).

Builds VALKA's X-02S under /Game/Mods/SurvivalMode/Valka from build/x02s (tools/x02s/prepare.py):
  T_X02S_Valka_C / _NO / _LM   textures (colour sRGB; normal BC7 linear; Livemap linear)
  MI_X02S_Valka                material instance on AC8's own aircraft material MP_PP0032_f18e_Decal (the F/A-18E's
                               skin parent: Basecolor / Livemap / Normalmap), no static switches of its own, so in game
                               it uses the parent's shaders (none of ours ship)
  SK_X02S_Valka (+ skeleton, physics asset)  the skinned X-02S, life-size: body and cockpit slots MI_X02S_Valka,
                               canopy and glass AC8's M_NPC_Canopy; AC7's sockets (burner_01 / _02 at the nozzles, as
                               AC8's aircraft name theirs) and the x40a's other effect sockets at the X-02S's own spots
  A_X02S_Valka_Sweep           the swing wings alone, unswept (0 s) to swept (1 s): AC7's x02s_Anim frames 50-100 on
                               the VariableWing bones, every other bone at rest (main.lua plays it by her speed)
AC8's materials are stood in for here by stubs at their own paths (same names, the parameters the instance sets):
the cooked instance and mesh import them by path, and the game loads its real ones. build.sh never packs the stubs.
"""
import json, math, os
import unreal

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.normpath(os.path.join(HERE, '..', '..', 'build', 'x02s'))
DEST = '/Game/Mods/SurvivalMode/Valka'
BODY_PARENT = '/Game/Vehicles/Aircraft/PP/PP0032_f18e/Materials/Common/MP_PP0032_f18e_Decal'
CANOPY = '/Game/Vehicles/Aircraft/Common/Material/MP/M_NPC_Canopy'
GLASS_SLOTS = ('canopy', 'glass')                 # glTF material names holding these go on CANOPY
SCALE = None                                      # set from prepare's scale (sockets are in AC7's units)
# AC7's x02s_Skeleton sockets (build/ac7/json/x02s_Skeleton.json): name -> (bone, location in AC7 units, rotation P/Y/R)
AC7_SOCKETS = {
    'burner_01': ('L_Nozzle', (13.263, 0, 0), (0, 180, 0)), 'burner_02': ('R_Nozzle', (13.263, 0, 0), (-180, 0, 0)),
    'vapor01': ('VariableWing_19', (0, 0, 0), (0, 41.12, 0)), 'vapor02': ('VariableWing_20', (0, 0, 0), (0, -41.12, 0)),
    'pitchup_body_01': ('Body', (86.446, -7.567, 0.867), (0, 0, 0)), 'pitchup_body_02': ('Body', (86.446, 8.738, 0.867), (0, 0, 0)),
    'pitchup_frtFlap_01': ('Body', (24.858, -22.195, 0.867), (0, 0, 0)), 'pitchup_frtFlap_02': ('Body', (24.858, 22.195, 0.867), (0, 0, 0)),
    'VFX_Dmg_Engine': ('Body', (-34.359, 8.312, 10.777), (0, 0, 0)), 'VFX_Dmg_Body': ('Body', (6.174, -23.359, 3.219), (0, 0, 0)),
    'VFX_Dmg_WingL': ('Body', (-13.441, -31.167, 1.531), (0, 0, 0)), 'VFX_Dmg_WingR': ('Body', (3.429, 33.545, 1.632), (0, 0, 0)),
    'gun': ('Body', (75.521, -7.714, 0.471), (1.243, -0.485, -158.701)),
    'TEMP_muzzleFlash': ('Body', (75.521, -7.714, 0.471), (1.243, -0.485, -158.701)),
    'cam_pilot': ('Body', (97.646, 0, 6.809), (0, 0, 0)), 'cam_nose': ('Body', (144.24, 0, -5.971), (0, 0, 0)),
}
# the x40a's effect sockets (AC8 DT_OP0016_x40a_FX_MapTable) -> the AC7 socket at the same kind of spot
X40A_ALIASES = {
    'core01': 'burner_01', 'cone01': 'burner_01', 'fakeLight01': 'burner_01', 'SOC_EF_Burner_01': 'burner_01',
    'core02': 'burner_02', 'cone02': 'burner_02', 'fakeLight02': 'burner_02', 'SOC_EF_Burner_02': 'burner_02',
    'SOC_R_EF_Burner': 'burner_02', 'ShoulderVaporL': 'pitchup_body_01', 'ShoulderVaporR': 'pitchup_body_02',
    'WingOverVaporL': 'vapor01', 'WingOverVaporR': 'vapor02', 'BN_Body': 'pitchup_body_01',
}
LOG = os.path.join(SRC, 'ue_import.log')

AT = unreal.AssetToolsHelpers.get_asset_tools()
MEL = unreal.MaterialEditingLibrary
EAL = unreal.EditorAssetLibrary
lines = []


def say(msg):
    lines.append(msg)
    unreal.log('[x02s] ' + msg)
    with open(LOG, 'w', encoding='utf-8') as f:
        f.write('\n'.join(lines) + '\n')


def fresh(path):
    if EAL.does_asset_exist(path):
        EAL.delete_asset(path)


def stub_material(path, params):
    """A Material at an AC8 material's path with texture parameters `params` (all wired, so they're kept)."""
    fresh(path)
    pkg, name = path.rsplit('/', 1)
    m = AT.create_asset(name, pkg, unreal.Material, unreal.MaterialFactoryNew())
    m.set_editor_property('used_with_skeletal_mesh', True)
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
    say(f'stub {path} ({", ".join(params) or "no parameters"})')
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
    import_file(os.path.join(SRC, name + '.tga'), DEST + '/Textures', name)
    tex = unreal.load_asset(f'{DEST}/Textures/{name}')
    tex.set_editor_property('srgb', srgb)
    tex.set_editor_property('compression_settings', compression)
    EAL.save_loaded_asset(tex)
    say(f'texture {name}: srgb {srgb}, {compression}')
    return tex


def material(parent, C, NO, LM):
    mi = AT.create_asset('MI_X02S_Valka', DEST + '/Materials', unreal.MaterialInstanceConstant,
                         unreal.MaterialInstanceConstantFactoryNew())
    MEL.set_material_instance_parent(mi, parent)
    want = (('Basecolor', C), ('Normalmap', NO), ('Livemap', LM))
    oks = [MEL.set_material_instance_texture_parameter_value(mi, pn, tex) for pn, tex in want]
    if not all(oks):
        # (the helper refuses a parameter it doesn't find on the parent; AC8's own instances store exactly this:
        # TextureParameterValues of { ParameterInfo { Name, GlobalParameter, INDEX_NONE }, ParameterValue })
        vals = []
        for pn, tex in want:
            v = unreal.TextureParameterValue()
            v.set_editor_property('parameter_info', unreal.MaterialParameterInfo(pn, unreal.MaterialParameterAssociation.GLOBAL_PARAMETER, -1))
            v.set_editor_property('parameter_value', tex)
            vals.append(v)
        mi.set_editor_property('texture_parameter_values', vals)
        MEL.update_material_instance(mi)
    got = {str(v.get_editor_property('parameter_info').get_editor_property('name')): v.get_editor_property('parameter_value').get_name()
           for v in mi.get_editor_property('texture_parameter_values')}
    say(f'MI_X02S_Valka textures (helper {oks}): {got}')
    assert got == {pn: tex.get_name() for pn, tex in want}, got
    EAL.save_loaded_asset(mi)
    return mi


def sockets(sk, scale):
    """AC7's sockets and the x40a's effect sockets as leaf bones (a bone is found wherever a socket name is asked
    for; Python can't set a SkeletalMeshSocket's name or bone in 5.4): USkeletonModifier.AddBone, its transform in the
    parent bone's space, as AC7's socket offsets are."""
    mod = unreal.SkeletonModifier()
    assert mod.set_skeletal_mesh(sk), 'SkeletonModifier.set_skeletal_mesh'
    names, parents, xforms = [], [], []
    def add(name, bone, loc, rot):
        names.append(name)
        parents.append(bone)
        xforms.append(unreal.Transform(unreal.Vector(loc[0] * scale, loc[1] * scale, loc[2] * scale),
                                       unreal.Rotator(rot[2], rot[0], rot[1]), unreal.Vector(1, 1, 1)))
    for name, (bone, loc, rot) in AC7_SOCKETS.items():
        add(name, bone, loc, rot)
    for name, src in X40A_ALIASES.items():
        bone, loc, rot = AC7_SOCKETS[src]
        add(name, bone, loc, rot)
    assert mod.add_bones(names, parents, xforms), 'SkeletonModifier.add_bones'
    assert mod.commit_skeleton_to_skeletal_mesh(), 'SkeletonModifier.commit_skeleton_to_skeletal_mesh'
    ref = unreal.AnimPoseExtensions.get_reference_pose(sk.get_editor_property('skeleton'))
    for n in ('burner_01', 'burner_02', 'vapor01', 'vapor02', 'gun'):
        t = unreal.AnimPoseExtensions.get_bone_pose(ref, n, unreal.AnimPoseSpaces.WORLD)
        say(f'  {n} at {t.translation} (component space, cm)')
    say(f'{len(names)} socket bones on SK_X02S_Valka: {", ".join(sorted(names))}')


def qmul(a, b):
    ax, ay, az, aw = a
    bx, by, bz, bw = b
    return (aw * bx + ax * bw + ay * bz - az * by, aw * by - ax * bz + ay * bw + az * bx,
            aw * bz + ax * by - ay * bx + az * bw, aw * bw - ax * bx - ay * by - az * bz)


FPS = 30


def resample(keys, n):
    """`keys` (quaternions, evenly spaced) at n evenly spaced points, normalised lerp between neighbours."""
    out = []
    for k in range(n):
        x = k * (len(keys) - 1) / (n - 1)
        i = min(int(x), len(keys) - 2)
        f = x - i
        a, b = keys[i], keys[i + 1]
        if sum(p * q for p, q in zip(a, b)) < 0:
            b = [-c for c in b]
        q = [p * (1 - f) + r * f for p, r in zip(a, b)]
        m = math.sqrt(sum(c * c for c in q)) or 1.0
        out.append([c / m for c in q])
    return out


def sweep_anim(skel):
    data = json.load(open(os.path.join(SRC, 'sweep.json')))
    ref = unreal.AnimPoseExtensions.get_reference_pose(skel)
    f = unreal.AnimSequenceFactory()
    f.set_editor_property('target_skeleton', skel)
    seq = AT.create_asset('A_X02S_Valka_Sweep', DEST + '/Model', unreal.AnimSequence, f)
    ctrl = seq.get_editor_property('controller')
    src_n = len(next(iter(data['bones'].values())))                 # AC7's keys (frames 50..100)
    n = FPS + 1                                                      # ours: 1 s at the project's 30 fps
    ctrl.open_bracket(unreal.Text('X-02S sweep'), True)
    ctrl.set_frame_rate(unreal.FrameRate(FPS, 1), True)             # 0 s unswept, 1 s swept
    ctrl.set_number_of_frames(unreal.FrameNumber(FPS), True)
    # AC7 plays x02s_Anim rotation-only (its .config: bAnimRotationOnly): an animated bone's local rotation IS the key
    # (its rest rotation never shows), translations stay the skeleton's. The .psa's quaternions are already in the
    # imported bones' local frames (bones whose rest pose is frame 0 match it to 0.999+; the sockets land where AC7
    # put them), so they go in as they are. (A delta on the rest pose swung the tips forward: build/x02s/ue_check.log.)
    how = {}
    for bone, keys in data['bones'].items():
        t = unreal.AnimPoseExtensions.get_bone_pose(ref, bone, unreal.AnimPoseSpaces.LOCAL)
        r = t.rotation
        q0 = data['frame0'][bone]
        how[bone] = round(abs(sum(a * b for a, b in zip(q0, (r.x, r.y, r.z, r.w)))), 3)
        rots = [unreal.Quat(q[0], q[1], q[2], q[3]) for q in resample(keys, n)]
        ctrl.add_bone_curve(bone, True)
        ctrl.set_bone_track_keys(bone, [t.translation] * n, rots, [t.scale3d] * n, True)
    ctrl.close_bracket(True)
    EAL.save_loaded_asset(seq)
    say(f"A_X02S_Valka_Sweep: {len(data['bones'])} wing bones, {n} keys over 1 s (from AC7's {src_n}); frame 0 vs rest |dot| {how}")
    return seq


def main():
    global SCALE
    if EAL.does_directory_exist(DEST):
        EAL.delete_directory(DEST)
    parent = stub_material(BODY_PARENT, ['Basecolor', 'Normalmap', 'Livemap'])
    canopy = stub_material(CANOPY, [])
    C = texture('T_X02S_Valka_C', True, unreal.TextureCompressionSettings.TC_DEFAULT)
    NO = texture('T_X02S_Valka_NO', False, unreal.TextureCompressionSettings.TC_BC7)
    LM = texture('T_X02S_Valka_LM', False, unreal.TextureCompressionSettings.TC_DEFAULT)
    mi = material(parent, C, NO, LM)

    before = set(EAL.list_assets(DEST, recursive=True))
    paths = import_file(os.path.join(SRC, 'x02s_skel.gltf'), DEST + '/Model')
    made = sorted(set(EAL.list_assets(DEST, recursive=True)) - before)
    say(f'glTF import: {paths}; new assets {made}')
    kinds = {}
    for p in made:
        a = unreal.load_asset(p)
        kinds.setdefault(a.get_class().get_name(), []).append(p.split('.')[0])
    say(f'imported kinds: { {k: len(v) for k, v in kinds.items()} }')
    assert len(kinds.get('SkeletalMesh', [])) == 1, kinds
    want_names = {'SkeletalMesh': 'SK_X02S_Valka', 'Skeleton': 'SKEL_X02S_Valka', 'PhysicsAsset': 'PA_X02S_Valka'}
    for cls, nm in want_names.items():
        for p in kinds.get(cls, [])[:1]:
            if p != f'{DEST}/Model/{nm}':
                EAL.rename_asset(p, f'{DEST}/Model/{nm}')
    sk = unreal.load_asset(DEST + '/Model/SK_X02S_Valka')
    skel = sk.get_editor_property('skeleton')
    mats = list(sk.get_editor_property('materials'))
    for k, m in enumerate(mats):
        n = str(m.get_editor_property('material_slot_name'))
        glass = any(w in n.lower() for w in GLASS_SLOTS)
        m.set_editor_property('material_interface', canopy if glass else mi)
        say(f'slot {k} {n}: {"M_NPC_Canopy" if glass else "MI_X02S_Valka"}')
    sk.set_editor_property('materials', mats)
    b = sk.get_bounds()
    say(f'SK_X02S_Valka bounds origin {b.origin} extent {b.box_extent} (cm)')
    scale = json.load(open(os.path.join(SRC, 'scale.json')))['scale']
    sockets(sk, scale)
    EAL.save_loaded_asset(sk)
    EAL.save_loaded_asset(skel)                     # (the commit rebuilt its bone tree: the socket bones too)
    sweep_anim(skel)
    for p in made:                                  # the importer's own materials / textures: not ours to ship
        a = p.split('.')[0]
        if EAL.does_asset_exist(a):
            cls = unreal.load_asset(a).get_class().get_name()
            if cls in ('Material', 'MaterialInstanceConstant', 'Texture2D'):
                EAL.delete_asset(a)
                say(f"deleted the importer's {cls} {a}")
    for a in sorted(x.split('.')[0] for x in EAL.list_assets(DEST, recursive=True)):
        say(f'  {a}: {unreal.load_asset(a).get_class().get_name()}')
    say('done')


try:
    main()
except Exception as ex:
    say(f'FAILED: {type(ex).__name__}: {ex}')
    raise
