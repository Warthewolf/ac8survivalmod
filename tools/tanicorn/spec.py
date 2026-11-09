"""spec.py : the TaniBuild commandlet's spec for the Tanicorn's parts (build/tanicorn/tani.spec.json).

Milestone 0 (docs/re/TANICORN.md): one 5-inch twin mount of our own, BP_SV_Tani_T5 straight on AC8's native
ALiveAIGroundVehicleObject (not on the stock BP_AITurret_Pawn: the user, 2026-11-09), laid out as the campaign Aegis's
Mk45 (BP_VE002_aegs_mk45_Base over BP_AITurret_Pawn, read with ACE8 Aircraft Builder's dev obj):
  SCS      TurretPoseableMesh (PoseableMesh: our SK_SV_Tani_T5) on the native RootComponent, DamagedStaticMesh (our wreck,
           hidden), DamagedCollision (sphere, EnemyPawn)
  native   LiveAIFireControlSystemComponent: one arm, AIControlCommon + LauncherBoneControl (turret_yaw / turret_pitch,
           SOC_Gun_01..02, prefix GUN) + ProjectileCommon (the vessel AA gun's shell: a stub at its stock path here)
           DamagedStateComponent: ChangeMesh (hide the turret, show the wreck), the native InducedExplosionArrangement
  CDO      AutoPossessAI, GameObjectId 1000 / Category_CarrierBattery (the Mk45's), PursuitPointOffset, bIsSea
Values that aren't set inherit the game's own native defaults (only differences are saved).
"""
import json, os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..'))   # (python -I: tools/env.py)
import env
# build outputs live in the main tree's build/: SV_ROOT (build.sh sets it), else the main git tree, else this checkout
_root, _main = env.roots()
BUILD = os.path.join(os.environ.get('SV_ROOT') or _main or _root, 'build', 'tanicorn')
DEST = '/Game/Mods/SurvivalMode/Tanicorn'
AA_SHELL = '/Game/Blueprints/Weapons/AAGUN/BP_wp_aagun_vessel'          # LiveBulletEmitter (its emitter base's class)


def obj(path):
    return f'{path}.{path.rsplit("/", 1)[1]}'


def bones(yaw, pitch):
    """ControlBones as text (FLiveFCSLauncherBoneSettings; the pitch field is lower-case 'pitch' in AC8's struct)."""
    def one(axis, bone, y, p):
        return (f'(BoneName="{bone}",bUseBasisBone=False,Axis={axis},'
                f'Yaw=(Speed={y[0]},AngleMin={y[1]},AngleMax={y[2]}),pitch=(Speed={p[0]},AngleMin={p[1]},AngleMax={p[2]}),'
                f'bUseRotationAccel=False,RotationSpeedThreshold=10,bRotationSound=False)')
    return '(' + one(1, 'turret_yaw', yaw, (45, -45, 45)) + ',' + one(2, 'turret_pitch', (45, -45, 45), pitch) + ')'


def mount(part, info, fcs):
    name = f'Tani_{part}'
    bp = f'{DEST}/BP_SV_{name}'
    me = obj(bp).replace(f'.BP_SV_{name}', f'.Default__BP_SV_{name}_C')
    slots = len(info['sockets'])
    return {
        'path': bp,
        'parent': 'LiveAIGroundVehicleObject',
        'scs': [
            {'name': 'TurretPoseableMesh', 'class': 'PoseableMeshComponent', 'parent': 'RootComponent',
             'props': {'SkinnedAsset': obj(f'{DEST}/Model/SK_SV_{name}')}},
            {'name': 'DamagedStaticMesh', 'class': 'StaticMeshComponent', 'parent': 'RootComponent',
             'props': {'StaticMesh': obj(f'{DEST}/Model/SM_SV_{name}_DAM'), 'bVisible': 'False'}},
            {'name': 'DamagedCollision', 'class': 'SphereComponent', 'parent': 'RootComponent',
             'props': {'SphereRadius': str(fcs['hit_radius_cm']), 'RelativeLocation': f'(X=0,Y=0,Z={fcs["hit_z_cm"]})',
                       'BodyInstance': '(CollisionEnabled=QueryAndPhysics,ObjectType=ECC_GameTraceChannel3,'
                                       'CollisionProfileName="EnemyPawn")'}},
        ],
        'cdo': {
            'AutoPossessAI': 'PlacedInWorldOrSpawned',
            'GameObjectId': '1000',
            'GameObjectCategory': 'Category_CarrierBattery',
            'PursuitPointOffset': '(X=0,Y=0,Z=45000)',
            'bKeepOnGround': 'False',
            'bIsSea': 'True',
            'bShowHUDBox': 'True',
            'BriDebriIconType': 'Weapons',
            'DamageSound': '(bEnableDamageSound=True)',
        },
        'components': {
            'FireControlSystemComponent': {
                'EnemySearchType': fcs['search'],
                'AllArms': [{'$new': 'LiveFireControlSystemArms', 'props': {
                    'AIModule': {'$new': 'LiveFCSModule_AIControlCommon'},
                    'LauncherModule': {'$new': 'LiveFCSModule_LauncherBoneControl', 'props': {
                        'MeshComponentName': 'TurretPoseableMesh',
                        'ControlBones': bones(fcs['yaw'], fcs['pitch']),
                        'FireControl': (f'(LauncherDirection=SlotSocket,CaptureDistance={fcs["capture_cm"]},CaptureMinDistance=0,'
                                        f'CaptureAngleRange={fcs["cone"]},ActivationTime={fcs["activation"]},'
                                        f'TriggeringTime={fcs["triggering"]},ShotIntervalTime={fcs["interval"]},'
                                        f'RestingTime={fcs["resting"]},TriggerCount={fcs["trigger_count"]})'),
                        'Performance': (f'(FireRate={fcs["fire_rate"]},MagazineCapacity={fcs["magazine"]},'
                                        f'ReloadTime={fcs["reload"]},SlotNum={slots},SlotSocketPrefix=GUN)'),
                    }},
                    'ProjectileModule': {'$new': 'LiveFCSModule_ProjectileCommon', 'props': {
                        'WeaponClass': f'{obj(fcs["weapon"])}_C'}},
                }}],
            },
            'DamagedStateComponent': {
                'DefaultDestroySystemList': [{'$new': 'LiveDefaultDestroySystemChangeMesh', 'props': {
                    'DestroyHideMeshNameList': '((ChangeTime=0,TargetMeshName="TurretPoseableMesh",bHideToFinalExplosion=True,bReflectChildMesh=False))',
                    'DestroyVisibleMeshNameList': '((ChangeTime=0,TargetMeshName="DamagedStaticMesh",bHideToFinalExplosion=False,bReflectChildMesh=False))',
                    'bChangeMeshes': 'True', 'bHideMeshes': 'True'}}],
            },
        },
    }


# milestone 0's mount: the Mk45's fire control, but searching the air (it's to track and fire at the player)
T5_FCS = {'search': 'AIR_ONLY', 'yaw': (40, -180, 180), 'pitch': (40, 0, 80), 'capture_cm': 600000, 'cone': 180,
          'activation': 2, 'triggering': 4, 'interval': 1, 'resting': 2, 'trigger_count': 1,
          'fire_rate': 10, 'magazine': 20, 'reload': 3, 'weapon': AA_SHELL,
          'hit_radius_cm': 600, 'hit_z_cm': 300}


def main():
    parts = json.load(open(os.path.join(BUILD, 'parts.json')))
    spec = {'sockets': [], 'stubs': [{'path': AA_SHELL, 'parent': 'LiveBulletEmitter'}], 'blueprints': []}
    for p in parts:
        info = json.load(open(os.path.join(BUILD, 'src_' + p, f'Tani_{p}.json')))
        for s in info['sockets']:
            spec['sockets'].append({'skeleton': obj(f'{DEST}/Model/SKEL_SV_Tani_{p}'), 'name': s['name'],
                                    'bone': s['bone'], 'loc': s['loc'], 'rot': [0, 0, 0]})
        spec['blueprints'].append(mount(p, info, T5_FCS))
    out = os.path.join(BUILD, 'tani.spec.json')
    json.dump(spec, open(out, 'w'), indent=1)
    print(f'spec.py: {out}: {len(spec["sockets"])} sockets, {len(spec["stubs"])} stubs, {len(spec["blueprints"])} blueprints')


if __name__ == '__main__':
    main()
