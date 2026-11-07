"""ue_import.py : AC7's LaserInterceptor beam parts into the AC8 template project (UE 5.4, E:/AC8LiveProject), under
/Game/Mods/SurvivalMode/Laser7 (tools/laser7/README.md). Run by tools/laser7/build.sh:

  UnrealEditor-Cmd.exe E:/AC8LiveProject/Live.uproject -run=pythonscript -script=tools/laser7/ue_import.py

- the beam's meshes from AC7's UModel glTF: SM_SV_TLS_01 (the flash), SM_SV_TLS_projectile_root / _tip (the beam), at
  AC7's own size (the effect's components are scaled x10 into AC8's world, so its emitters keep AC7's numbers)
- T_SV_rain_drop (m_TLS_03's sparks)
- the four materials, rebuilt (AC7's cooked materials keep no graph, only: unlit, two-sided, sprite and mesh particles,
  the particle colour into emissive through AC7's sky plugin's transparency function, which AC8 hasn't):
  M_SV_TLS_01 (the beam), M_SV_TLS_01_wire (its wire layer), M_SV_TLS_02 (the flash), M_SV_TLS_03 (the sparks):
  emissive = particle colour x its alpha (x T_SV_rain_drop for the sparks), additive
Writes build/laser7/ue_import.log; its last line "done" when it all went in.
"""
import os
import unreal

ROOT = os.environ.get('SV_ROOT', r'E:\ACE8 Survival Mode')
SRC = os.path.join(ROOT, 'build', 'ac7', 'laser', 'umodel', 'Game')
OUT = os.path.join(ROOT, 'build', 'laser7')
DEST = '/Game/Mods/SurvivalMode/Laser7'
LOG = os.path.join(OUT, 'ue_import.log')
AT = unreal.AssetToolsHelpers.get_asset_tools()
MEL = unreal.MaterialEditingLibrary
EAL = unreal.EditorAssetLibrary
lines = []


def say(msg):
    lines.append(msg)
    unreal.log('[laser7] ' + msg)
    os.makedirs(OUT, exist_ok=True)
    with open(LOG, 'w', encoding='utf-8') as f:
        f.write('\n'.join(lines) + '\n')


def fresh(path):
    if EAL.does_asset_exist(path):
        EAL.delete_asset(path)


def import_file(src, dest, name):
    t = unreal.AssetImportTask()
    t.set_editor_property('filename', src)
    t.set_editor_property('destination_path', dest)
    t.set_editor_property('destination_name', name)
    t.set_editor_property('automated', True)
    t.set_editor_property('replace_existing', True)
    t.set_editor_property('save', True)
    AT.import_asset_tasks([t])
    return list(t.get_editor_property('imported_object_paths') or [])


def mesh(src_name, name):
    src = os.path.join(SRC, 'VFX', 'Vehicles', 'Weapon', 'TLS', 'mesh', src_name + '.gltf')
    path = DEST + '/' + name
    fresh(path)
    got = import_file(src, DEST, name)
    sm = [p for p in got if EAL.does_asset_exist(p) and isinstance(unreal.load_asset(p), unreal.StaticMesh)]
    if not sm:
        say(f'mesh {name}: NOT imported (got {got})')
        return None
    m = unreal.load_asset(sm[0])
    if sm[0].split('.')[0] != path:                   # (the importer's own name: renamed to ours)
        EAL.rename_asset(sm[0].split('.')[0], path)
        m = unreal.load_asset(path)
    for p in got:                                     # (its materials and textures: never used, the effect sets ours)
        if p.split('.')[0] != path and EAL.does_asset_exist(p.split('.')[0]):
            EAL.delete_asset(p.split('.')[0])
    b = m.get_bounding_box()
    say(f'mesh {name}: {src_name}.gltf, bounds {b.min} .. {b.max}')
    EAL.save_asset(path)
    return m


def material(name, texture=None, wire=False):
    path = DEST + '/' + name
    fresh(path)
    m = AT.create_asset(name, DEST, unreal.Material, unreal.MaterialFactoryNew())
    m.set_editor_property('blend_mode', unreal.BlendMode.BLEND_ADDITIVE)
    m.set_editor_property('shading_model', unreal.MaterialShadingModel.MSM_UNLIT)
    m.set_editor_property('two_sided', True)
    m.set_editor_property('used_with_particle_sprites', True)
    m.set_editor_property('used_with_mesh_particles', True)
    if wire:
        m.set_editor_property('wireframe', True)
    pc = MEL.create_material_expression(m, unreal.MaterialExpressionParticleColor, -700, 0)
    mul = MEL.create_material_expression(m, unreal.MaterialExpressionMultiply, -400, 0)
    MEL.connect_material_expressions(pc, 'RGB', mul, 'A')
    MEL.connect_material_expressions(pc, 'A', mul, 'B')
    last = mul
    if texture is not None:
        ts = MEL.create_material_expression(m, unreal.MaterialExpressionTextureSample, -700, 250)
        ts.set_editor_property('texture', texture)
        mul2 = MEL.create_material_expression(m, unreal.MaterialExpressionMultiply, -200, 100)
        MEL.connect_material_expressions(mul, '', mul2, 'A')
        MEL.connect_material_expressions(ts, 'R', mul2, 'B')
        last = mul2
    MEL.connect_material_property(last, '', unreal.MaterialProperty.MP_EMISSIVE_COLOR)
    MEL.recompile_material(m)
    EAL.save_asset(path)
    say(f'material {name}: unlit, additive, two-sided, sprite + mesh particles, emissive = particle colour x alpha'
        + (f' x {texture.get_name()}' if texture else '') + (', wireframe' if wire else ''))
    return m


def main():
    say(f'from {SRC} into {DEST}')
    for src_name, name in (('SM_TLS_01', 'SM_SV_TLS_01'), ('SM_TLS_projectile_root', 'SM_SV_TLS_projectile_root'),
                           ('SM_TLS_projectile_tip', 'SM_SV_TLS_projectile_tip')):
        if mesh(src_name, name) is None:
            say('failed')
            return
    tex_src = os.path.join(SRC, 'VFX', 'Environment', 'Common', 'rain', 'textrure', 'T_rain_drop.png')
    fresh(DEST + '/T_SV_rain_drop')
    got = import_file(tex_src, DEST, 'T_SV_rain_drop')
    tex = unreal.load_asset(DEST + '/T_SV_rain_drop')
    if tex is None:
        say(f'texture T_SV_rain_drop: NOT imported ({got})')
        say('failed')
        return
    say(f'texture T_SV_rain_drop: {tex.blueprint_get_size_x()} x {tex.blueprint_get_size_y()}')
    material('M_SV_TLS_01')
    material('M_SV_TLS_01_wire', wire=True)
    material('M_SV_TLS_02')
    material('M_SV_TLS_03', texture=tex)
    say('done')


main()
