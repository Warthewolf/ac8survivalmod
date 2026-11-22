"""ue_import.py : VALKA's portal meshes (tools/valka_portal/make_portal.py's glTFs) into the AC8 template project, UE 5.4.

Run by tools/valka_portal/build.sh: UnrealEditor-Cmd <Live.uproject> -run=pythonscript -script=<this>. Reads SV_PORTAL_SRC
(one design's glTFs and its manifest.json: the pieces) and SV_PORTAL_LOG; makes /Game/Mods/SurvivalMode/ValkaPortal/Model/SM_SV_Portal* static meshes, each slot on
the engine's /Engine/BasicShapes/BasicShapeMaterial (in AC8's own files: Survival colours them in game with AC8's glow
materials, hard rule 58: no material of ours), no collision, no Nanite, no lightmap UVs needed (never lit from a map).
The log ends with `done` when every mesh is in and saved.
"""
import json
import os

import unreal

SRC = os.environ.get('SV_PORTAL_SRC', '')
LOG = os.environ.get('SV_PORTAL_LOG', os.path.join(SRC, '..', 'ue_import.log'))
DEST = '/Game/Mods/SurvivalMode/ValkaPortal/Model'
with open(os.path.join(SRC, 'manifest.json'), encoding='utf-8') as _fh:
    NAMES = [p['name'] for p in json.load(_fh)['pieces']]
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


# ((2026-11-22) the user: "the portal opening and closing is so laggy") its scaler (tools/valka_portal/scaler.py): a
# skeletal mesh of one bone and three scale animations the engine plays every frame, each piece hung on one in game
SCALER, SCALER_ANIMS = 'SK_SV_PortalScaler', ['A_SV_PortalGrow']   # (one: the importer gives only a file's first its skeleton)


def import_scaler(mat):
    src = os.path.join(SRC, SCALER + '.gltf')
    assert os.path.exists(src), 'no ' + src + ' (scaler.py)'
    before = set(EAL.list_assets(DEST, recursive=True))
    t = unreal.AssetImportTask()
    t.set_editor_property('filename', src)
    t.set_editor_property('destination_path', DEST)
    t.set_editor_property('automated', True)
    t.set_editor_property('replace_existing', True)
    t.set_editor_property('save', True)
    AT.import_asset_tasks([t])
    kinds = {}
    for q in sorted(set(EAL.list_assets(DEST, recursive=True)) - before):
        a = q.split('.')[0]
        if EAL.does_asset_exist(a):
            kinds.setdefault(unreal.load_asset(a).get_class().get_name(), []).append(a)
    say(f'scaler import: { {k: len(v) for k, v in kinds.items()} }')
    assert len(kinds.get('SkeletalMesh', [])) == 1 and len(kinds.get('AnimSequence', [])) == len(SCALER_ANIMS), kinds
    for cls in ('Material', 'MaterialInstanceConstant', 'Texture2D'):
        for a in kinds.get(cls, []):
            EAL.delete_asset(a)                      # (the importer's own: never ours in the game)
    # ((2026-11-22) nothing renamed: each rename (the animation's, the skeleton's) left the animation with no skeleton
    # ("Unable to retrieve target USkeleton"; None in the editor; frozen in game). The importer's own names, as
    # Scripts/sv_anomalies_valka.lua names them: the mesh, <mesh>_Skeleton, <mesh>_Anim
    assert kinds['SkeletalMesh'][0] == f'{DEST}/{SCALER}', kinds['SkeletalMesh']
    an_path = kinds['AnimSequence'][0]
    assert an_path == f'{DEST}/{SCALER}_Anim', kinds['AnimSequence']
    an = unreal.load_asset(an_path)
    skel = an.get_editor_property('skeleton')
    msk = unreal.load_asset(f'{DEST}/{SCALER}').get_editor_property('skeleton')
    assert skel is not None and msk is not None and skel.get_path_name() == msk.get_path_name(), (an_path, skel, msk)
    EAL.save_loaded_asset(an)
    say(f'{SCALER}_Anim: an animation of {an.get_editor_property("sequence_length"):.2f} s on {skel.get_name()}')
    sk = unreal.load_asset(f'{DEST}/{SCALER}')
    mats = list(sk.get_editor_property('materials'))
    for m in mats:
        m.set_editor_property('material_interface', mat)
    sk.set_editor_property('materials', mats)
    try:
        sk.set_editor_property('physics_asset', None)
    except Exception as e:
        say(f'scaler: physics asset left ({e})')
    EAL.save_loaded_asset(sk)
    EAL.save_loaded_asset(sk.get_editor_property('skeleton'))
    say(f'{SCALER}: {len(mats)} slot(s) on BasicShapeMaterial, its skeleton {sk.get_editor_property("skeleton").get_name()}')


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
        # ((2026-11-22) the detailed design is ~630k triangles: three LODs, so it costs little 14 km out or as her blinks'
        # small holes; the commandlet has no StaticMeshEditorSubsystem (the cook of 14:47): EditorStaticMeshLibrary then)
        opts = unreal.StaticMeshReductionOptions()
        opts.set_editor_property('auto_compute_lod_screen_size', False)
        opts.set_editor_property('reduction_settings', [
            unreal.StaticMeshReductionSettings(1.0, 1.0), unreal.StaticMeshReductionSettings(0.35, 0.3),
            unreal.StaticMeshReductionSettings(0.1, 0.1)])
        how = []
        for what in ('StaticMeshEditorSubsystem', 'EditorStaticMeshLibrary'):
            try:
                if what == 'StaticMeshEditorSubsystem':
                    lods = unreal.get_editor_subsystem(unreal.StaticMeshEditorSubsystem).set_lods_with_notification(sm, opts, True)
                else:
                    lods = unreal.EditorStaticMeshLibrary.set_lods(sm, opts)
                how.append(f'{what}: {lods}')
                break
            except Exception as e:
                how.append(f'{what}: {e}')
        say(f'{name}: LODs: ' + '; '.join(how))
        EAL.save_loaded_asset(sm)
        b = sm.get_bounds()
        say(f'{name}: {len(slots)} slot(s) on BasicShapeMaterial, bounds radius {b.sphere_radius:.1f} cm, '
            f'{sm.get_num_triangles(0) if hasattr(sm, "get_num_triangles") else "?"} tris')
    import_scaler(mat)
    say('done')


try:
    main()
except Exception as e:
    say(f'FAILED: {e}')
    raise
