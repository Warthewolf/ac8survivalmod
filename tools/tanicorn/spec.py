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

THE TANACORN's parts (tools/tanicorn/export_tanacorn.py; docs/design/INVINCIBLE_FLEET.md WP0 -> WP1): every part's
sockets with their rotations (SOC_Gun_NN on turret_pitch, SOC_Vls_NN on Body along each cell's launch line), the hull's
36 Mount_* sockets on its static mesh (mesh_sockets), and a blueprint for each gun mount on the 5-inch's layout
(BP_SV_Tani_T5 / _T16 / _CIWS / _LASER; FCS below; the 16-inch's with its fire mode's two meshes, FIRE_MODE). The VLS
blocks and the hull get their blueprints in WP1 / WP2.
"""
import json, os

HERE = os.path.dirname(os.path.abspath(__file__))
BUILD = os.environ.get('TANI_BUILD') or os.path.normpath(os.path.join(HERE, '..', '..', 'build', 'tanicorn'))
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


# The 16-inch's FIRE MODE (firemode.py; export_tanacorn.py's deploy parts): two skeletal meshes riding the turret's own
# bones, each with its Deploy loaded and held at its start (shut); the game plays it forward to open and backwards to
# shut (PlayAnimation / SetPlayRate on the component: docs/re/TANICORN.md 7). They draw only: the hit sphere stays the
# turret's, and the destroy system hides them with the turret.
FIRE_MODE = {'T16': [('FireModeArmor', 'T16_ARMOR', 'turret_yaw'), ('FireModeGuns', 'T16_GUNS', 'turret_pitch')]}


def fire_mode_scs(part):
    out = []
    for comp, sub, bone in FIRE_MODE.get(part, []):
        anim = obj(f'{DEST}/Model/AS_SV_Tani_{sub}_Deploy')
        out.append({'name': comp, 'class': 'SkeletalMeshComponent', 'parent': 'TurretPoseableMesh', 'socket': bone,
                    'props': {'SkinnedAsset': obj(f'{DEST}/Model/SK_SV_Tani_{sub}'),
                              'AnimationMode': 'AnimationSingleNode',
                              'AnimationData': (f'(AnimToPlay="{anim}",bSavedLooping=False,bSavedPlaying=False,'
                                                f'SavedPosition=0,SavedPlayRate=1)'),
                              'BodyInstance': '(CollisionEnabled=NoCollision)'}})
    return out


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
        ] + fire_mode_scs(part),
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
                    'DestroyHideMeshNameList': '(' + ','.join(
                        f'(ChangeTime=0,TargetMeshName="{m}",bHideToFinalExplosion=True,bReflectChildMesh=False)'
                        for m in ['TurretPoseableMesh'] + [c for c, _, _ in FIRE_MODE.get(part, [])]) + ')',
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
# The other gun mounts, until WP1 gives each its own weapon (docs/design/INVINCIBLE_FLEET.md WP1: the 16-inch its
# railgun shells, the CIWS and the laser their anti-missile arms): the SAME fire control as the 5-inch, the stock
# vessel AA shell, only the speeds, the lift and the hit sphere each mount's own. So every mount's rig can be seen
# to aim and fire from the test key before its real weapon is built; none of these values is a design decision.
FCS = {
    'T5': T5_FCS,
    'T16': {**T5_FCS, 'yaw': (12, -150, 150), 'pitch': (8, -2, 45), 'activation': 3, 'interval': 2, 'resting': 6,
            'fire_rate': 3,
            'magazine': 3, 'reload': 8, 'hit_radius_cm': 1800, 'hit_z_cm': 400},
    'CIWS': {**T5_FCS, 'yaw': (120, -180, 180), 'pitch': (100, -10, 85), 'activation': 1, 'triggering': 2,
             'interval': 0.1, 'resting': 1, 'fire_rate': 30, 'magazine': 60, 'hit_radius_cm': 350, 'hit_z_cm': 300},
    'LASER': {**T5_FCS, 'yaw': (120, -180, 180), 'pitch': (100, -10, 85), 'activation': 1, 'triggering': 2,
              'hit_radius_cm': 350, 'hit_z_cm': 250},
}


def main():
    parts = json.load(open(os.path.join(BUILD, 'parts.json')))
    only = [x for x in os.environ.get('TANI_PARTS', '').split(',') if x]
    spec = {'sockets': [], 'mesh_sockets': [], 'stubs': [{'path': AA_SHELL, 'parent': 'LiveBulletEmitter'}],
            'blueprints': []}
    for p in parts:
        if only and p not in only:
            continue
        info = json.load(open(os.path.join(BUILD, 'src_' + p, f'Tani_{p}.json')))
        kind = info.get('kind', 'turret')
        if kind == 'hull':
            # the hull's sockets: a Mount_<name> for every part, +X the part's forward (TaniBuild: UStaticMeshSocket)
            for s in info['sockets']:
                spec['mesh_sockets'].append({'mesh': obj(f'{DEST}/Model/SM_SV_Tani_{p}'), 'name': s['name'],
                                             'loc': s['loc'], 'rot': s.get('rot', [0, 0, 0])})
            continue
        for s in info['sockets']:
            spec['sockets'].append({'skeleton': obj(f'{DEST}/Model/SKEL_SV_Tani_{p}'), 'name': s['name'],
                                    'bone': s['bone'], 'loc': s['loc'], 'rot': s.get('rot', [0, 0, 0])})
        if kind == 'turret' and p in FCS:
            spec['blueprints'].append(mount(p, info, FCS[p]))
    out = os.path.join(BUILD, 'tani.spec.json')
    json.dump(spec, open(out, 'w'), indent=1)
    print(f'spec.py: {out}: {len(spec["sockets"])} sockets, {len(spec["mesh_sockets"])} hull sockets, '
          f'{len(spec["stubs"])} stubs, {len(spec["blueprints"])} blueprints '
          f'({", ".join(b["path"].rsplit("/", 1)[1] for b in spec["blueprints"])})')


if __name__ == '__main__':
    main()
