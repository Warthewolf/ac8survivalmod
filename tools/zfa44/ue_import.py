"""ue_import.py : run inside UE 5.4 (tools/zfa44/build.sh: UnrealEditor-Cmd ue/Live/Live.uproject -run=pythonscript).

Builds the ZFA-44EL (tools/re/ZFA44.md; the user's own model, AGENTS.md's exception of 2026-11-06) under
/Game/Mods/SurvivalMode/ZFA44 from build/zfa44/prep (tools/zfa44/prepare.py):
  Textures/T_ZFA44_C, _N, _LM, _LM_MREC, _Pod_C, _Pod_N, _Fair_C, _Fair_N   ordinary textures (never virtual: hard
                               rule 44); colour sRGB, normals BC5, the Livemaps linear
  Materials/MI_ZFA44_Body, _Pod, _Fairing   instances of the x40a's GEAR instance MI_PP0016_x40a_Gear (-> MP_Gear ->
                               M_Live_Vehicle_Base: ordinary samplers and GPU-skin shaders; tools/re/FALKEN_MATERIALS.md,
                               the route VALKA's paint 16 and SOLG T0b drew with). No static switch is set, so each draws
                               with that instance's own shaders (none of ours ship). Basecolor / Normalmap / Livemap
                               ours; Detail_Normal and Blend_Dameged_Normalmap the engine's DefaultNormal; Ctrl_All_Emissive,
                               Turbine_speed, DNormal_Strength, DamegedNormal_Intencity, PlayerPlane_Damage 0 (the
                               Falken's set, NormalIntencity left as the parent has it: ours is a real normal map)
  Model/SK_ZFA44 (+ SKEL_ZFA44, PA_ZFA44)   the skinned ZFA-44, life size (24 m), slots Body / Canopy / Pod / Fairing,
                               the canopy on AC8's M_NPC_Canopy (as VALKA's X-02S); its socket bones (burner_01 / _02 ...)
AC8's materials are stood in for by stubs at their own paths (MP_Gear a Material with the parameters, MI_PP0016_x40a_Gear
an instance of it, M_NPC_Canopy): the cooked instances and mesh import them by path, the game loads its own. build.sh
packs only /Game/Mods/SurvivalMode/ZFA44, never a stub.
"""
import json, os
import unreal

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.normpath(os.path.join(HERE, '..', '..', 'build', 'zfa44', 'prep'))
LOG = os.path.normpath(os.path.join(SRC, '..', 'ue_import.log'))
DEST = '/Game/Mods/SurvivalMode/ZFA44'
GEAR = '/Game/Vehicles/Aircraft/PP/PP0016_x40a/Materials/Common/MI_PP0016_x40a_Gear'
MP_GEAR = '/Game/Vehicles/Aircraft/Common/Material/MP/MP_Gear'
CANOPY = '/Game/Vehicles/Aircraft/Common/Material/MP/M_NPC_Canopy'
DEFAULT_NORMAL = '/Engine/EngineMaterials/DefaultNormal'
GEAR_TEX = ['Basecolor', 'Livemap', 'Normalmap', 'Detail_Normal', 'Blend_Dameged_Normalmap']
GEAR_SCALARS = ['Ctrl_All_Emissive', 'Turbine_speed', 'NormalIntencity', 'DNormal_Strength', 'DamegedNormal_Intencity',
                'PlayerPlane_Damage']
SCALARS = {'Ctrl_All_Emissive': 0.0, 'Turbine_speed': 0.0, 'DNormal_Strength': 0.0, 'DamegedNormal_Intencity': 0.0,
           'PlayerPlane_Damage': 0.0}
# slot -> (instance, Basecolor, Normalmap, Livemap); the Canopy slot takes AC8's M_NPC_Canopy
PAINT = {'Body': ('MI_ZFA44_Body', 'T_ZFA44_C', 'T_ZFA44_N', 'T_ZFA44_LM'),
         'Pod': ('MI_ZFA44_Pod', 'T_ZFA44_Pod_C', 'T_ZFA44_Pod_N', 'T_ZFA44_LM'),
         'Fairing': ('MI_ZFA44_Fairing', 'T_ZFA44_Fair_C', 'T_ZFA44_Fair_N', 'T_ZFA44_LM')}
CHECK_BONES = ('Root', 'Body', 'burner_01', 'burner_02', 'burner_03', 'vapor01', 'vapor02', 'gun', 'laser', 'cam_nose',
               'SOC_EF_Burner_01', 'core02')

AT = unreal.AssetToolsHelpers.get_asset_tools()
MEL = unreal.MaterialEditingLibrary
EAL = unreal.EditorAssetLibrary
TCS = unreal.TextureCompressionSettings
lines = []


def say(msg):
    lines.append(msg)
    unreal.log('[zfa44] ' + msg)
    with open(LOG, 'w', encoding='utf-8') as f:
        f.write('\n'.join(lines) + '\n')


def fresh(path):
    if EAL.does_asset_exist(path):
        EAL.delete_asset(path)


def stub_material(path, params, scalars=()):
    """A Material at an AC8 material's path with texture parameters `params` (all wired, so they're kept) and scalar
    parameters (summed into its roughness, so they're kept too); usable on skeletal meshes (tools/x02s/ue_import.py)."""
    fresh(path)
    pkg, name = path.rsplit('/', 1)
    m = AT.create_asset(name, pkg, unreal.Material, unreal.MaterialFactoryNew())
    m.set_editor_property('used_with_skeletal_mesh', True)
    default = unreal.load_asset('/Engine/EngineResources/DefaultTexture')
    normal = unreal.load_asset(DEFAULT_NORMAL)
    outputs = [unreal.MaterialProperty.MP_BASE_COLOR, unreal.MaterialProperty.MP_EMISSIVE_COLOR,
               unreal.MaterialProperty.MP_SPECULAR, unreal.MaterialProperty.MP_METALLIC,
               unreal.MaterialProperty.MP_AMBIENT_OCCLUSION]
    for k, pn in enumerate(params):
        e = MEL.create_material_expression(m, unreal.MaterialExpressionTextureSampleParameter2D, -400, 250 * k)
        e.set_editor_property('parameter_name', pn)
        if 'Normal' in pn:                           # (normal samplers, so the instances' BC5 maps fit them)
            e.set_editor_property('sampler_type', unreal.MaterialSamplerType.SAMPLERTYPE_NORMAL)
            e.set_editor_property('texture', normal)
        else:
            e.set_editor_property('texture', default)
        MEL.connect_material_property(e, 'RGB' if k < 2 else 'R', outputs[k])
    extra = []
    for k, pn in enumerate(scalars):
        e = MEL.create_material_expression(m, unreal.MaterialExpressionScalarParameter, -400, 250 * (len(params) + k))
        e.set_editor_property('parameter_name', pn)
        extra.append(e)
    if extra:
        acc = extra[0]
        for k, e in enumerate(extra[1:]):
            add = MEL.create_material_expression(m, unreal.MaterialExpressionAdd, -200, 250 * k)
            MEL.connect_material_expressions(acc, '', add, 'A')
            MEL.connect_material_expressions(e, '', add, 'B')
            acc = add
        MEL.connect_material_property(acc, '', unreal.MaterialProperty.MP_ROUGHNESS)
    MEL.recompile_material(m)
    EAL.save_loaded_asset(m)
    say(f'stub {path} ({", ".join(list(params) + list(scalars)) or "no parameters"})')
    return m


def stub_instance(path, parent):
    """A MaterialInstanceConstant at an AC8 instance's path on `parent`, no overrides (the game loads its own)."""
    fresh(path)
    pkg, name = path.rsplit('/', 1)
    mi = AT.create_asset(name, pkg, unreal.MaterialInstanceConstant, unreal.MaterialInstanceConstantFactoryNew())
    MEL.set_material_instance_parent(mi, parent)
    EAL.save_loaded_asset(mi)
    say(f'stub {path} (an instance of {parent.get_path_name()})')
    return mi


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


def texture(name, srgb, compression, max_size=0, flat=False):
    """An ordinary texture (never virtual: hard rule 44). flat: the 4 x 4 constant (no mips, never streamed, uncompressed
    BGRA8, as the Falken's body Livemap)."""
    import_file(os.path.join(SRC, name + '.png'), DEST + '/Textures', name)
    tex = unreal.load_asset(f'{DEST}/Textures/{name}')
    assert tex is not None, f'{name} not imported'
    tex.set_editor_property('srgb', srgb)
    tex.set_editor_property('compression_settings', compression)
    tex.set_editor_property('virtual_texture_streaming', False)
    if compression == TCS.TC_DEFAULT:
        tex.set_editor_property('compression_no_alpha', True)
    if compression == TCS.TC_NORMALMAP:
        tex.set_editor_property('lod_group', unreal.TextureGroup.TEXTUREGROUP_WORLD_NORMAL_MAP)
    if max_size:
        tex.set_editor_property('max_texture_size', max_size)
    if flat:
        tex.set_editor_property('mip_gen_settings', unreal.TextureMipGenSettings.TMGS_NO_MIPMAPS)
        tex.set_editor_property('never_stream', True)
        tex.set_editor_property('filter', unreal.TextureFilter.TF_NEAREST)
    EAL.save_loaded_asset(tex)
    say(f'texture {name}: {tex.blueprint_get_size_x()}x{tex.blueprint_get_size_y()}, srgb {srgb}, {compression}'
        f'{", max " + str(max_size) if max_size else ""}{", flat (no mips, never streamed)" if flat else ""}, '
        f'virtual {tex.get_editor_property("virtual_texture_streaming")}')
    return tex


def instance(name, parent, tex, scalars):
    """MI_ZFA44_* on the gear instance: its texture and scalar values as AC8's own instances store them
    ({ Name, GlobalParameter, INDEX_NONE }, value), no static parameter."""
    path = f'{DEST}/Materials/{name}'
    fresh(path)
    mi = AT.create_asset(name, DEST + '/Materials', unreal.MaterialInstanceConstant,
                         unreal.MaterialInstanceConstantFactoryNew())
    MEL.set_material_instance_parent(mi, parent)
    tv = []
    for pn, t in tex:
        v = unreal.TextureParameterValue()
        v.set_editor_property('parameter_info', unreal.MaterialParameterInfo(pn, unreal.MaterialParameterAssociation.GLOBAL_PARAMETER, -1))
        v.set_editor_property('parameter_value', t)
        tv.append(v)
    mi.set_editor_property('texture_parameter_values', tv)
    sv = []
    for pn, x in scalars.items():
        v = unreal.ScalarParameterValue()
        v.set_editor_property('parameter_info', unreal.MaterialParameterInfo(pn, unreal.MaterialParameterAssociation.GLOBAL_PARAMETER, -1))
        v.set_editor_property('parameter_value', x)
        sv.append(v)
    mi.set_editor_property('scalar_parameter_values', sv)
    MEL.update_material_instance(mi)
    got_t = {str(v.get_editor_property('parameter_info').get_editor_property('name')): v.get_editor_property('parameter_value').get_name()
             for v in mi.get_editor_property('texture_parameter_values')}
    got_s = {str(v.get_editor_property('parameter_info').get_editor_property('name')): v.get_editor_property('parameter_value')
             for v in mi.get_editor_property('scalar_parameter_values')}
    assert got_t == {pn: t.get_name() for pn, t in tex}, got_t
    assert set(got_s) == set(scalars), got_s
    try:
        statics = mi.get_editor_property('static_parameters')
        sw = len(statics.get_editor_property('static_switch_parameters'))
    except Exception as ex:                          # (not exposed in every build: the cooked check in build.sh decides)
        sw = f'? ({type(ex).__name__})'
    EAL.save_loaded_asset(mi)
    say(f'{name} on {parent.get_name()}: textures {got_t}, scalars {got_s}, static switches overridden {sw}')
    return mi


def import_skeletal(layout, mats_by_slot):
    before = set(EAL.list_assets(DEST, recursive=True))
    import_file(os.path.join(SRC, layout['mesh'] + '.gltf'), DEST + '/Model')
    made = sorted(set(EAL.list_assets(DEST, recursive=True)) - before)
    kinds = {}
    for p in made:
        a = p.split('.')[0]
        if EAL.does_asset_exist(a):
            kinds.setdefault(unreal.load_asset(a).get_class().get_name(), []).append(a)
    say(f'glTF import: { {k: len(v) for k, v in kinds.items()} }')
    assert len(kinds.get('SkeletalMesh', [])) == 1, kinds
    for cls, nm in (('SkeletalMesh', 'SK_ZFA44'), ('Skeleton', 'SKEL_ZFA44'), ('PhysicsAsset', 'PA_ZFA44')):
        for p in kinds.get(cls, [])[:1]:
            if p != f'{DEST}/Model/{nm}':
                EAL.rename_asset(p, f'{DEST}/Model/{nm}')
    for a in kinds.get('Material', []) + kinds.get('MaterialInstanceConstant', []) + kinds.get('Texture2D', []):
        if EAL.does_asset_exist(a):                  # (the importer's own: not ours to ship)
            EAL.delete_asset(a)
            say(f"deleted the importer's {a}")
    sk = unreal.load_asset(f'{DEST}/Model/SK_ZFA44')
    skel = sk.get_editor_property('skeleton')
    mats = list(sk.get_editor_property('materials'))
    names = []
    for k, s in enumerate(mats):
        slot = str(s.get_editor_property('material_slot_name'))
        key = next((x for x in mats_by_slot if x.lower() in slot.lower()), None)
        assert key, f'slot {k} {slot}: not one of {list(mats_by_slot)}'
        s.set_editor_property('material_interface', mats_by_slot[key])
        names.append(f'{k} {slot}: {mats_by_slot[key].get_name()}')
    sk.set_editor_property('materials', mats)
    assert len(mats) == len(layout['slots']), names
    say(f'SK_ZFA44 slots: {names}')
    b = sk.get_bounds()
    say(f'SK_ZFA44 bounds origin {b.origin} extent {b.box_extent} sphere {b.sphere_radius:.0f} cm '
        f'(prepare.py: {layout["bounds_cm"]}, {layout["size_m"]})')
    EAL.save_loaded_asset(sk)
    EAL.save_loaded_asset(skel)
    pose = unreal.AnimPoseExtensions.get_reference_pose(skel)
    bn = [str(n) for n in unreal.AnimPoseExtensions.get_bone_names(pose)]
    want = ['Root', 'Body'] + list(layout['bones'])
    missing, extra = sorted(set(want) - set(bn)), sorted(set(bn) - set(want))
    say(f'SKEL_ZFA44: {len(bn)} bones (prepare.py made {len(want)}); missing {missing}, extra {extra}')
    assert not missing, missing
    worst = 0.0
    for n in bn:
        t = unreal.AnimPoseExtensions.get_bone_pose(pose, n, unreal.AnimPoseSpaces.WORLD)
        p = t.translation
        exp = layout['bones'].get(n, {}).get('ue_cm')
        if exp:
            worst = max(worst, abs(p.x - exp[0]), abs(p.y - exp[1]), abs(p.z - exp[2]))
        if n in CHECK_BONES:
            try:
                ax = t.rotation.rotate_vector(unreal.Vector(1, 0, 0))
                axis = f'({ax.x:.2f}, {ax.y:.2f}, {ax.z:.2f})'
            except Exception as ex:
                axis = f'? ({type(ex).__name__})'
            say(f'  bone {n} at ({p.x:.1f}, {p.y:.1f}, {p.z:.1f}) cm, its X axis {axis}'
                + (f' (prepare.py {exp})' if exp else ''))
    say(f'SKEL_ZFA44: every socket bone within {worst:.2f} cm of prepare.py\'s place')
    assert worst < 1.0, worst


def main():
    layout = json.load(open(os.path.join(SRC, 'layout.json')))
    if EAL.does_directory_exist(DEST):
        EAL.delete_directory(DEST)
    mp_gear = stub_material(MP_GEAR, GEAR_TEX, GEAR_SCALARS)
    gear = stub_instance(GEAR, mp_gear)
    canopy = stub_material(CANOPY, [])
    T = {}
    T['T_ZFA44_C'] = texture('T_ZFA44_C', True, TCS.TC_DEFAULT)
    T['T_ZFA44_N'] = texture('T_ZFA44_N', False, TCS.TC_NORMALMAP, max_size=2048)
    T['T_ZFA44_LM'] = texture('T_ZFA44_LM', False, TCS.TC_VECTOR_DISPLACEMENTMAP, flat=True)
    T['T_ZFA44_LM_MREC'] = texture('T_ZFA44_LM_MREC', False, TCS.TC_MASKS, max_size=2048)
    T['T_ZFA44_Pod_C'] = texture('T_ZFA44_Pod_C', True, TCS.TC_DEFAULT)
    T['T_ZFA44_Pod_N'] = texture('T_ZFA44_Pod_N', False, TCS.TC_NORMALMAP)
    T['T_ZFA44_Fair_C'] = texture('T_ZFA44_Fair_C', True, TCS.TC_DEFAULT)
    T['T_ZFA44_Fair_N'] = texture('T_ZFA44_Fair_N', False, TCS.TC_NORMALMAP)
    dn = unreal.load_asset(DEFAULT_NORMAL)
    assert dn is not None, DEFAULT_NORMAL
    mats = {'Canopy': canopy}
    for slot, (mi, c, n, lm) in PAINT.items():
        mats[slot] = instance(mi, gear, [('Basecolor', T[c]), ('Normalmap', T[n]), ('Livemap', T[lm]),
                                         ('Detail_Normal', dn), ('Blend_Dameged_Normalmap', dn)], SCALARS)
    import_skeletal(layout, mats)
    for a in sorted(x.split('.')[0] for x in EAL.list_assets(DEST, recursive=True)):
        say(f'  {a}: {unreal.load_asset(a).get_class().get_name()}')
    say('done')


try:
    main()
except Exception as ex:
    say(f'FAILED: {type(ex).__name__}: {ex}')
    raise
