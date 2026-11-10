"""ue_import.py : run inside UE 5.4 in the AC8 template project (E:/AC8LiveProject, which has AC8's classes compiled):
  UnrealEditor-Cmd E:/AC8LiveProject/Live.uproject -run=pythonscript -script=tools/tanicorn/ue_import.py

THE TANACORN's parts under /Game/Mods/SurvivalMode/Tanicorn from build/tanicorn/src_<part>
(tools/tanicorn/export_tanacorn.py; the first 5-inch mount came from prepare_part.py), for every part in
build/tanicorn/parts.json (TANI_PARTS=T5,HULL picks some), by its json's kind:
  Textures/T_SV_<part>_<n>_D, _N, _L   ordinary textures (never virtual: hard rule 44)
  Materials/MI_SV_<part>_<n>           instances of the x40a's gear instance MI_PP0016_x40a_Gear (-> MP_Gear), the route
                                       the ZFA-44 and VALKA drew with in game: AC8's own shaders, no static switch set
                                       (hard rules 42, 58: no master material of ours)
  turret   Model/SK_SV_<part> (+ SKEL_SV_<part>, PA_SV_<part>): bones Body > turret_yaw > turret_pitch
  vls      Model/SK_SV_<part> (+ SKEL, PA): bones Body > Hatch_01..08, and AS_SV_<part>_Open (the lids' swing, 0.5 s)
  railcannon, railgun (the Alicorn's deploying parts: RAILCANNON, RAILGUN_L / _R)
           Model/SK_SV_<part> (+ SKEL, PA): the json's bones (railcannon: Body > railcannon_pitch > barrel_n / barrel_p;
           railgun: Body > lift > BN_turret_yaw > BN_turret_pitch, Body > Hatch_n / Hatch_p), and AS_SV_<part>_Deploy
           (the design's deploy, rotations and the lift's translation; 3.333 s / 4.0 s)
  hull     Model/SM_SV_Tani_HULL: one static mesh (its 36 Mount_* sockets come from TaniBuild), collision its triangles
  each but the hull: Model/SM_SV_<part>_DAM, the wreck (a static mesh the destroy system shows)
AC8's materials are stubs at their own paths here; the game loads its own. tools/tanicorn/build.sh packs only
/Game/Mods/SurvivalMode/Tanicorn. The sockets (SOC_Gun_NN, SOC_Vls_NN, Mount_*) are added by the TaniBuild commandlet
(C++: real sockets). The log ends with its warnings counted, then `done`.
"""
import json, os
import unreal

HERE = os.path.dirname(os.path.abspath(__file__))
BUILD = os.environ.get('TANI_BUILD') or os.path.normpath(os.path.join(HERE, '..', '..', 'build', 'tanicorn'))
LOG = os.path.join(BUILD, 'ue_import.log')
DEST = '/Game/Mods/SurvivalMode/Tanicorn'
GEAR = '/Game/Vehicles/Aircraft/PP/PP0016_x40a/Materials/Common/MI_PP0016_x40a_Gear'
MP_GEAR = '/Game/Vehicles/Aircraft/Common/Material/MP/MP_Gear'
DEFAULT_NORMAL = '/Engine/EngineMaterials/DefaultNormal'
GEAR_TEX = ['Basecolor', 'Livemap', 'Normalmap', 'Detail_Normal', 'Blend_Dameged_Normalmap']
GEAR_SCALARS = ['Ctrl_All_Emissive', 'Turbine_speed', 'NormalIntencity', 'DNormal_Strength', 'DamegedNormal_Intencity',
                'PlayerPlane_Damage']
SCALARS = {'Ctrl_All_Emissive': 0.0, 'Turbine_speed': 0.0, 'DNormal_Strength': 0.0, 'DamegedNormal_Intencity': 0.0,
           'PlayerPlane_Damage': 0.0}

AT = unreal.AssetToolsHelpers.get_asset_tools()
MEL = unreal.MaterialEditingLibrary
EAL = unreal.EditorAssetLibrary
TCS = unreal.TextureCompressionSettings
lines = []


def say(msg):
    lines.append(msg)
    unreal.log('[tanicorn] ' + msg)
    with open(LOG, 'w', encoding='utf-8') as f:
        f.write('\n'.join(lines) + '\n')


def fresh(path):
    if EAL.does_asset_exist(path):
        EAL.delete_asset(path)


def stub_material(path, params, scalars=()):
    """A Material at an AC8 material's path with its parameters (as tools/zfa44/ue_import.py)."""
    if EAL.does_asset_exist(path):
        return unreal.load_asset(path)
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
        if 'Normal' in pn:
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
    say(f'stub {path}')
    return m


def stub_instance(path, parent):
    if EAL.does_asset_exist(path):
        return unreal.load_asset(path)
    pkg, name = path.rsplit('/', 1)
    mi = AT.create_asset(name, pkg, unreal.MaterialInstanceConstant, unreal.MaterialInstanceConstantFactoryNew())
    MEL.set_material_instance_parent(mi, parent)
    EAL.save_loaded_asset(mi)
    say(f'stub {path}')
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


def texture(src_dir, name, srgb, compression, flat=False):
    import_file(os.path.join(src_dir, name + '.png'), DEST + '/Textures', name)
    tex = unreal.load_asset(f'{DEST}/Textures/{name}')
    assert tex is not None, f'{name} not imported'
    tex.set_editor_property('srgb', srgb)
    tex.set_editor_property('compression_settings', compression)
    tex.set_editor_property('virtual_texture_streaming', False)
    if compression == TCS.TC_DEFAULT:
        tex.set_editor_property('compression_no_alpha', True)
    if compression == TCS.TC_NORMALMAP:
        tex.set_editor_property('lod_group', unreal.TextureGroup.TEXTUREGROUP_WORLD_NORMAL_MAP)
    if flat:
        tex.set_editor_property('mip_gen_settings', unreal.TextureMipGenSettings.TMGS_NO_MIPMAPS)
        tex.set_editor_property('never_stream', True)
        tex.set_editor_property('filter', unreal.TextureFilter.TF_NEAREST)
    EAL.save_loaded_asset(tex)
    say(f'texture {name}: {tex.blueprint_get_size_x()}x{tex.blueprint_get_size_y()}, srgb {srgb}, {compression}')
    return tex


def instance(name, parent, tex):
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
    for pn, x in SCALARS.items():
        v = unreal.ScalarParameterValue()
        v.set_editor_property('parameter_info', unreal.MaterialParameterInfo(pn, unreal.MaterialParameterAssociation.GLOBAL_PARAMETER, -1))
        v.set_editor_property('parameter_value', x)
        sv.append(v)
    mi.set_editor_property('scalar_parameter_values', sv)
    MEL.update_material_instance(mi)
    EAL.save_loaded_asset(mi)
    say(f'{name} on {parent.get_name()}: {[t.get_name() for _, t in tex]}')
    return mi


def imported(src, folder):
    """Import a glTF; return {class name: [asset paths]} of what it made, the importer's own materials deleted."""
    before = set(EAL.list_assets(DEST, recursive=True))
    import_file(src, DEST + '/' + folder)
    made = sorted(set(EAL.list_assets(DEST, recursive=True)) - before)
    kinds = {}
    for p in made:
        a = p.split('.')[0]
        if EAL.does_asset_exist(a):
            kinds.setdefault(unreal.load_asset(a).get_class().get_name(), []).append(a)
    for a in kinds.get('Material', []) + kinds.get('MaterialInstanceConstant', []) + kinds.get('Texture2D', []):
        if EAL.does_asset_exist(a):
            EAL.delete_asset(a)
    return kinds


def set_slots(mesh, mats, prop='materials', field='material_interface'):
    slots = list(mesh.get_editor_property(prop))
    assert len(slots) == len(mats), (len(slots), len(mats))
    for s, m in zip(slots, mats):
        s.set_editor_property(field, m)
    mesh.set_editor_property(prop, slots)


def soft(fn):
    """a value only for the log (this script can't be run outside the editor: an API name that differs must not stop
    the import)"""
    try:
        return fn()
    except Exception as ex:
        return f'? ({type(ex).__name__})'


TEX = {}                                # textures imported in this run, by name (the side VLS blocks share one set,
                                        # the two sub-railguns another)
DEPLOY = ('railcannon', 'railgun')      # export_tanacorn.py deploying(): a rig and its Deploy


def tex_once(src, name, *args, **kw):
    if name not in TEX:
        TEX[name] = texture(src, name, *args, **kw)
    return TEX[name]


def materials(name, info, src, gear, dn):
    """an instance a slot: its base colour, its own normal map where the export has one (the Alicorn's sheets)"""
    n = tex_once(src, info.get('flat_normal', f'T_SV_{name}_N'), False, TCS.TC_NORMALMAP)
    lm = tex_once(src, info.get('livemap', f'T_SV_{name}_L'), False, TCS.TC_VECTOR_DISPLACEMENTMAP, flat=True)
    mats = []
    for s in info['slots']:
        c = tex_once(src, s['basecolor'], True, TCS.TC_DEFAULT)
        sn = tex_once(src, s['normal'], False, TCS.TC_NORMALMAP) if s.get('normal') else n
        mats.append(instance(f'MI_SV_{name}_{s["slot"]}', gear, [('Basecolor', c), ('Normalmap', sn), ('Livemap', lm),
                                                                   ('Detail_Normal', dn), ('Blend_Dameged_Normalmap', dn)]))
        if s.get('cutout'):
            say(f'  NOTE MI_SV_{name}_{s["slot"]}: its source has a cut-out ({s["cutout"]}: a lattice); AC8\'s gear '
                f'material has no opacity, so it draws solid')
    return mats


def renamed(kinds, cls, path):
    """the first asset of that class the import made, at `path`; None if it made none"""
    got = kinds.get(cls, [])
    if not got:
        return None
    if got[0] != path:
        fresh(path)
        EAL.rename_asset(got[0], path)
    return unreal.load_asset(path)


def static(src_file, path, mats):
    kinds = imported(src_file, 'Model')
    say(f'{os.path.basename(src_file)}: { {k: len(v) for k, v in kinds.items()} }')
    assert len(kinds.get('StaticMesh', [])) == 1, kinds
    sm = renamed(kinds, 'StaticMesh', path)
    set_slots(sm, mats, 'static_materials', 'material_interface')
    EAL.save_loaded_asset(sm)
    return sm


def skinned(name, info, src, mats, need):
    """the rigged mesh SK_SV_<name> with its skeleton and physics asset; its bones logged against the export's"""
    kinds = imported(os.path.join(src, name + '.gltf'), 'Model')
    say(f'{name}.gltf: { {k: len(v) for k, v in kinds.items()} }')
    assert len(kinds.get('SkeletalMesh', [])) == 1, kinds
    for cls, nm in (('SkeletalMesh', f'SK_SV_{name}'), ('Skeleton', f'SKEL_SV_{name}'), ('PhysicsAsset', f'PA_SV_{name}')):
        renamed(kinds, cls, f'{DEST}/Model/{nm}')
    sk = unreal.load_asset(f'{DEST}/Model/SK_SV_{name}')
    set_slots(sk, mats)
    EAL.save_loaded_asset(sk)
    skel = sk.get_editor_property('skeleton')
    EAL.save_loaded_asset(skel)
    pose = unreal.AnimPoseExtensions.get_reference_pose(skel)
    bones = [str(b) for b in unreal.AnimPoseExtensions.get_bone_names(pose)]
    say(f'SK_SV_{name}: bones {bones}')
    worst = 0.0
    for b in bones:
        t = unreal.AnimPoseExtensions.get_bone_pose(pose, b, unreal.AnimPoseSpaces.WORLD)
        q = t.rotation
        want = info['bones'].get(b)
        if want:
            worst = max(worst, abs(t.translation.x - want[0]), abs(t.translation.y - want[1]), abs(t.translation.z - want[2]))
        say(f'  bone {b} at ({t.translation.x:.1f}, {t.translation.y:.1f}, {t.translation.z:.1f}) cm, '
            f'rotation ({q.x:.3f}, {q.y:.3f}, {q.z:.3f}, {q.w:.3f})' + (f' (export: {want})' if want else ''))
    for b in need:
        assert b in bones, f'bone {b} missing from {bones}'
    say(f'SK_SV_{name}: every bone within {worst:.2f} cm of the export' + ('' if worst < 1.0 else '  WARNING: bones off'))
    bb = sk.get_bounds()
    say(f'SK_SV_{name} bounds origin {bb.origin} extent {bb.box_extent}')
    return sk, kinds


def part(p, gear, dn):
    src = os.path.join(BUILD, 'src_' + p)
    info = json.load(open(os.path.join(src, f'Tani_{p}.json')))
    name = f'Tani_{p}'
    kind = info.get('kind', 'turret')
    mats = materials(name, info, src, gear, dn)
    if kind == 'hull':
        # the hull: one static mesh, its sockets added by TaniBuild (mesh_sockets); every triangle its own collision
        sm = static(os.path.join(src, name + '.gltf'), f'{DEST}/Model/SM_SV_{name}', mats)
        try:
            sm.get_editor_property('body_setup').set_editor_property(
                'collision_trace_flag', unreal.CollisionTraceFlag.CTF_USE_COMPLEX_AS_SIMPLE)
            EAL.save_loaded_asset(sm)
            say(f'SM_SV_{name}: collision = its own triangles')
        except Exception as ex:
            say(f'  WARNING SM_SV_{name}: collision flag not set ({ex})')
        bb = sm.get_bounds()
        say(f'SM_SV_{name}: {soft(lambda: sm.get_num_triangles(0))} triangles (export {info["triangles"]}), bounds '
            f'origin {bb.origin} extent {bb.box_extent}')
        return
    if kind == 'vls':
        need = ['Body'] + [f'Hatch_{k:02d}' for k in range(1, 9)]
        sk, kinds = skinned(name, info, src, mats, need)
        anim = renamed(kinds, 'AnimSequence', f'{DEST}/Model/AS_SV_{name}_Open')
        if anim:
            EAL.save_loaded_asset(anim)
            say(f'AS_SV_{name}_Open: {soft(lambda: round(anim.get_play_length(), 3))} s (export {info["anim"]["length_s"]} s)')
        else:
            say(f'  WARNING {name}: the import made no animation (the lids\' Open): {kinds}')
    elif kind in DEPLOY:
        sk, kinds = skinned(name, info, src, mats, tuple(info['bones']))
        anim = renamed(kinds, 'AnimSequence', f'{DEST}/Model/AS_SV_{name}_Deploy')
        if anim:
            EAL.save_loaded_asset(anim)
            say(f'AS_SV_{name}_Deploy: {soft(lambda: round(anim.get_play_length(), 3))} s (export {info["anim"]["length_s"]} s, '
                f'the design frames {info["anim"]["design_frames"]})')
        else:
            say(f'  WARNING {name}: the import made no animation (its Deploy): {kinds}')
    else:
        skinned(name, info, src, mats, tuple(info['bones']))          # (0.74.59: BN_Body > BN_turret_yaw > BN_turret_pitch)
    if info.get('wreck', True):
        static(os.path.join(src, name + '_DAM.gltf'), f'{DEST}/Model/SM_SV_{name}_DAM', mats)


def main():
    parts = json.load(open(os.path.join(BUILD, 'parts.json')))
    if EAL.does_directory_exist(DEST):
        EAL.delete_directory(DEST)
    gear = stub_instance(GEAR, stub_material(MP_GEAR, GEAR_TEX, GEAR_SCALARS))
    dn = unreal.load_asset(DEFAULT_NORMAL)
    only = [x for x in os.environ.get('TANI_PARTS', '').split(',') if x]
    for p in parts:
        if only and p not in only:
            continue
        part(p, gear, dn)
        say(f'part {p} done')
    for a in sorted(x.split('.')[0] for x in EAL.list_assets(DEST, recursive=True)):
        say(f'  {a}: {unreal.load_asset(a).get_class().get_name()}')
    warn = [l for l in lines if 'WARNING' in l]
    say(f'{len(warn)} warnings' + ''.join('\n' + w for w in warn))
    say('done')


try:
    main()
except Exception as ex:
    say(f'FAILED: {type(ex).__name__}: {ex}')
    raise
