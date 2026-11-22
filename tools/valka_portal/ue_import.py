"""ue_import.py : VALKA's portal meshes (tools/valka_portal/make_portal.py's glTFs) into the AC8 template project, UE 5.4.

Run by tools/valka_portal/build.sh: UnrealEditor-Cmd <Live.uproject> -run=pythonscript -script=<this>. Reads SV_PORTAL_SRC
(the glTFs) and SV_PORTAL_LOG; makes /Game/Mods/SurvivalMode/ValkaPortal/Model/SM_SV_Portal* static meshes, each slot on
the engine's /Engine/BasicShapes/BasicShapeMaterial (in AC8's own files: Survival colours them in game with AC8's glow
materials, hard rule 58: no material of ours), no collision, no Nanite, no lightmap UVs needed (never lit from a map).
The log ends with `done` when every mesh is in and saved.
"""
import os

import unreal

SRC = os.environ.get('SV_PORTAL_SRC', '')
LOG = os.environ.get('SV_PORTAL_LOG', os.path.join(SRC, '..', 'ue_import.log'))
DEST = '/Game/Mods/SurvivalMode/ValkaPortal/Model'
NAMES = ['SM_SV_BHShadow', 'SM_SV_BHPhotonRing', 'SM_SV_BHHaloInner', 'SM_SV_BHHaloOuter', 'SM_SV_BHDiskHot',
         'SM_SV_BHDiskWarm', 'SM_SV_BHDiskCool', 'SM_SV_BHDiskBright']
EAL = unreal.EditorAssetLibrary
AT = unreal.AssetToolsHelpers.get_asset_tools()
lines = []


def say(msg):
    lines.append(msg)
    unreal.log('[valka_portal] ' + msg)
    with open(LOG, 'w', encoding='utf-8') as f:
        f.write('\n'.join(lines) + '\n')


def import_glb(name):
    before = set(EAL.list_assets(DEST, recursive=True)) if EAL.does_directory_exist(DEST) else set()
    t = unreal.AssetImportTask()
    t.set_editor_property('filename', os.path.join(SRC, name + '.glb'))
    t.set_editor_property('destination_path', DEST)
    t.set_editor_property('automated', True)
    t.set_editor_property('replace_existing', True)
    t.set_editor_property('save', True)
    AT.import_asset_tasks([t])
    made = sorted(set(EAL.list_assets(DEST, recursive=True)) - before)
    meshes = []
    for p in made:
        a = p.split('.')[0]
        if not EAL.does_asset_exist(a):
            continue
        cls = unreal.load_asset(a).get_class().get_name()
        if cls == 'StaticMesh':
            meshes.append(a)
        elif cls in ('Material', 'MaterialInstanceConstant', 'Texture2D'):
            EAL.delete_asset(a)                      # (the importer's own: never ours in the game)
    return meshes


def main():
    say(f'source {SRC}')
    mat = unreal.load_asset('/Engine/BasicShapes/BasicShapeMaterial')
    assert mat is not None, 'no /Engine/BasicShapes/BasicShapeMaterial'
    if EAL.does_directory_exist(DEST):
        for a in EAL.list_assets(DEST, recursive=True):
            EAL.delete_asset(a.split('.')[0])
    for name in NAMES:
        meshes = import_glb(name)
        assert meshes, f'{name}: nothing imported'
        path = f'{DEST}/{name}'
        if meshes[0] != path:
            if EAL.does_asset_exist(path):
                EAL.delete_asset(path)
            EAL.rename_asset(meshes[0], path)
        sm = unreal.load_asset(path)
        slots = list(sm.get_editor_property('static_materials'))
        for s in slots:
            s.set_editor_property('material_interface', mat)
        sm.set_editor_property('static_materials', slots)
        try:
            body = sm.get_editor_property('body_setup')
            if body:
                body.set_editor_property('collision_trace_flag', unreal.CollisionTraceFlag.CTF_USE_SIMPLE_AS_COMPLEX)
        except Exception as e:                       # (only for the log: the game never collides with it)
            say(f'{name}: body setup left ({e})')
        try:
            nan = sm.get_editor_property('nanite_settings')
            nan.set_editor_property('enabled', False)
            sm.set_editor_property('nanite_settings', nan)
        except Exception as e:
            say(f'{name}: nanite setting left ({e})')
        EAL.save_loaded_asset(sm)
        b = sm.get_bounds()
        say(f'{name}: {len(slots)} slot(s) on BasicShapeMaterial, bounds radius {b.sphere_radius:.1f} cm, '
            f'{sm.get_num_triangles(0) if hasattr(sm, "get_num_triangles") else "?"} tris')
    say('done')


try:
    main()
except Exception as e:
    say(f'FAILED: {e}')
    raise
