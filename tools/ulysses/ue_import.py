"""ue_import.py : run inside UE 5.4 (tools/ulysses/build.sh: UnrealEditor-Cmd ue/Live/Live.uproject -run=pythonscript).

Builds AC:I's meteors under /Game/Mods/SurvivalMode/Ulysses from build/ulysses (tools/ulysses/prepare.py):
  Textures/T_SV_Ulysses_Rock_D / _N / _L   colour (sRGB), normal (TC_NORMALMAP), Livemap (linear); ordinary textures,
                                           never virtual (hard rule 44)
  Materials/MI_SV_Ulysses_Rock             an instance on AC8's M_Live_Base (T_Basecolor / T_Normalmap / T_Livemap),
                                           as the SOLG's MI_SV_SOLG_<id>: M_Live_Base is stood in for by a stub at its
                                           own path, which build.sh never packs (hard rules 42 / 58: no master of ours)
  Textures/T_SV_Ulysses_Tail_D, _FlatN     the streak's gradient (sRGB, alpha) and a flat normal
  Materials/MI_SV_Ulysses_Tail             the streak's instance on the same stub (the game repaints it at run time)
  Model/SM_SV_Ulysses_A / _C / _D / _Tail  static meshes, no collision (_Tail: the streak, ours, prepare.py)
  Model/SK_SV_Ulysses_A / _C / _D / _Tail  the same as one-bone skeletal meshes (+ SKEL_SV_Ulysses_<K>), no
                                           physics asset: the route AC8 is proven to draw (docs/re/SOLG.md 8)
"""
import json, os
import unreal

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.normpath(os.path.join(HERE, '..', '..', 'build', 'ulysses'))
DEST = '/Game/Mods/SurvivalMode/Ulysses'
BASE = '/Game/Base/Material/M_Live_Base'
LOG = os.path.join(SRC, 'ue_import.log')

AT = unreal.AssetToolsHelpers.get_asset_tools()
MEL = unreal.MaterialEditingLibrary
EAL = unreal.EditorAssetLibrary
lines = []


def say(msg):
    lines.append(msg)
    unreal.log('[ulysses] ' + msg)
    with open(LOG, 'w', encoding='utf-8') as f:
        f.write('\n'.join(lines) + '\n')


def base_stub(params):
    """AC8's M_Live_Base: the stub already in the project (tools/solg makes it) or a new one with `params` wired."""
    if EAL.does_asset_exist(BASE):
        say(f'stub {BASE}: the one in the project')
        return unreal.load_asset(BASE)
    pkg, name = BASE.rsplit('/', 1)
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
    say(f'stub {BASE} made ({", ".join(params)})')
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
    for pn, tex in want:
        v = unreal.TextureParameterValue()
        v.set_editor_property('parameter_info', unreal.MaterialParameterInfo(pn, unreal.MaterialParameterAssociation.GLOBAL_PARAMETER, -1))
        v.set_editor_property('parameter_value', tex)
        vals.append(v)
    mi.set_editor_property('texture_parameter_values', vals)
    MEL.update_material_instance(mi)
    EAL.save_loaded_asset(mi)
    say(f'instance {name} on {parent.get_path_name()}: {", ".join(pn + "=" + t.get_name() for pn, t in want)}')
    return mi


def imported(gltf):
    """Import one glTF into DEST/Model -> {class name: [asset paths]} of what it made."""
    before = set(EAL.list_assets(DEST, recursive=True))
    import_file(os.path.join(SRC, gltf), DEST + '/Model')
    kinds = {}
    for p in sorted(set(EAL.list_assets(DEST, recursive=True)) - before):
        a = p.split('.')[0]
        if EAL.does_asset_exist(a):
            kinds.setdefault(unreal.load_asset(a).get_class().get_name(), []).append(a)
    for a in kinds.get('Material', []) + kinds.get('MaterialInstanceConstant', []) + kinds.get('Texture2D', []):
        EAL.delete_asset(a)                  # (the importer's own materials and textures)
    return kinds


def named(path, name):
    want = f'{DEST}/Model/{name}'
    if path != want:
        EAL.rename_asset(path, want)
    return unreal.load_asset(want)


def no_collision(m):
    for get in (lambda: unreal.get_editor_subsystem(unreal.StaticMeshEditorSubsystem),
                lambda: unreal.EditorStaticMeshLibrary):
        try:
            get().remove_collisions(m)
            return 'removed'
        except Exception:
            continue
    return 'not removed (no helper)'


def static(name, info, mi):
    kinds = imported(name + '.gltf')
    assert len(kinds.get('StaticMesh', [])) == 1, kinds
    m = named(kinds['StaticMesh'][0], name)
    mats = list(m.get_editor_property('static_materials'))
    for s in mats:
        s.set_editor_property('material_interface', mi)
    m.set_editor_property('static_materials', mats)
    col = no_collision(m)
    EAL.save_loaded_asset(m)
    b = m.get_bounding_box()
    say(f'{name}: {len(mats)} slot(s), collision {col}, bounds {[round(b.min.x), round(b.min.y), round(b.min.z)]} .. '
        f'{[round(b.max.x), round(b.max.y), round(b.max.z)]} cm (prepare.py: {info["size_m"]} m)')


def skeletal(name, mi):
    kinds = imported(name + '.gltf')
    assert len(kinds.get('SkeletalMesh', [])) == 1, kinds
    sk = named(kinds['SkeletalMesh'][0], name)
    skel = named(kinds['Skeleton'][0], 'SKEL' + name[2:])
    try:
        sk.set_editor_property('physics_asset', None)
    except Exception as ex:
        say(f'physics asset not cleared: {ex}')
    for a in kinds.get('PhysicsAsset', []):
        if EAL.does_asset_exist(a):
            EAL.delete_asset(a)
    mats = list(sk.get_editor_property('materials'))
    for s in mats:
        s.set_editor_property('material_interface', mi)
    sk.set_editor_property('materials', mats)
    EAL.save_loaded_asset(sk)
    EAL.save_loaded_asset(skel)
    b = sk.get_bounds()
    say(f'{name}: {len(mats)} slot(s), bounds origin {b.origin} extent {b.box_extent} cm')


def main():
    layout = json.load(open(os.path.join(SRC, 'layout.json')))
    if EAL.does_directory_exist(DEST):
        EAL.delete_directory(DEST)
    base = base_stub(['T_Basecolor', 'T_Normalmap', 'T_Livemap'])
    d = texture('T_SV_Ulysses_Rock_D', True, unreal.TextureCompressionSettings.TC_DEFAULT)
    n = texture('T_SV_Ulysses_Rock_N', False, unreal.TextureCompressionSettings.TC_NORMALMAP)
    lm = texture('T_SV_Ulysses_Rock_L', False, unreal.TextureCompressionSettings.TC_DEFAULT)
    mis = {'Rock': instance('MI_SV_Ulysses_Rock', base, (('T_Basecolor', d), ('T_Normalmap', n), ('T_Livemap', lm)))}
    # ((2026-11-23) the streak, ours: its gradient on the same stub; the game paints it at run time)
    td = texture('T_SV_Ulysses_Tail_D', True, unreal.TextureCompressionSettings.TC_DEFAULT)
    fn = texture('T_SV_Ulysses_FlatN', False, unreal.TextureCompressionSettings.TC_NORMALMAP)
    mis['Tail'] = instance('MI_SV_Ulysses_Tail', base, (('T_Basecolor', td), ('T_Normalmap', fn), ('T_Livemap', lm)))
    for name, info in sorted(layout['meshes'].items()):
        mi = mis[info.get('mi', 'Rock')]
        static(name, info, mi)
        skeletal(info['skeletal'], mi)
    for a in sorted(x.split('.')[0] for x in EAL.list_assets(DEST, recursive=True)):
        say(f'  {a}: {unreal.load_asset(a).get_class().get_name()}')
    say('done')


try:
    main()
except Exception as ex:
    say(f'FAILED: {type(ex).__name__}: {ex}')
    raise
