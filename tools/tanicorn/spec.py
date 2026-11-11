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
(BP_SV_Tani_T5 / _T16 / _CIWS / _LASER; FCS below). The VLS blocks and the hull get their blueprints in WP1 / WP2.
The deploying Alicorn parts (kinds railcannon and railgun: RAILCANNON, RAILGUN_L, RAILGUN_R, each with its Deploy
animation) get their SOC_Gun_01 like the others and no blueprint of their own yet (no fire control: WP11); the hull's
blueprint draws them, stowed, on Mount_RAILCANNON / Mount_RAILGUN_L / _R as it draws every part.
(2026-11-11, WP2 step 2, route (a)) BP_SV_Tani_HULLLIVE: the same hull with the gun mounts LIVE (LIVE: each T16 / T5 / CIWS /
LASER socket a LiveChildActorComponent whose child is that mount's own blueprint), the rest drawn; BP_SV_Tani_HULL unchanged.
(2026-11-12, WP1's VLS route: docs/re/TANICORN.md "VLS") the VLS blocks' blueprints (vls_mount: BP_SV_Tani_VLSD, the deck
block on its 8 sockets, and BP_SV_Tani_VLSS_L1..R4, each side block its own mesh): their mesh a SkeletalMeshComponent
TurretMesh (the Mk 41's component name; its cells SOC_Vls_01..08, the lids' AS_SV_Tani_<part>_Open in single-node mode,
shut), a LauncherCommon arm on it with the VLS prefix and the Mk 41's missile (the row's arm replaces it), the gun mounts'
wreck and damage state; on BP_SV_Tani_HULLLIVE all 16 VLS sockets live too (32 parts).
"""
import json, os

HERE = os.path.dirname(os.path.abspath(__file__))
BUILD = os.environ.get('TANI_BUILD') or os.path.normpath(os.path.join(HERE, '..', '..', 'build', 'tanicorn'))
DEST = '/Game/Mods/SurvivalMode/Tanicorn'
AA_SHELL = '/Game/Blueprints/Weapons/AAGUN/BP_wp_aagun_vessel'          # LiveBulletEmitter (its emitter base's class)
# the ground flak gun's shell (BP_FCS_FlakGun_00's weapon; BP_flakgun_BaseClass on the native LiveFlakGun): one shell a
# shot from the launcher, not an attached emitter
FLAK_SHELL = '/Game/Blueprints/Weapons/FlakGun/NPC/BP_wp_flakgun'
# (2026-11-12) the Aegis Mk 41's missile (BP_FCS_Vessel_VLS_VE002_mk41's weapon; BP_wp_vls_BaseClass on the native
# LiveVLSMissile: its script imports, build/stock): the VLS blocks' own arm names it (a stub here, never packed)
VLS_MISSILE = '/Game/Blueprints/Weapons/MSL/NPC/Vls/BP_wp_vls_a0'


def obj(path):
    return f'{path}.{path.rsplit("/", 1)[1]}'


def bones(yaw, pitch):
    """ControlBones as text (FLiveFCSLauncherBoneSettings; the pitch field is lower-case 'pitch' in AC8's struct)."""
    def one(axis, bone, y, p):
        return (f'(BoneName="{bone}",bUseBasisBone=False,Axis={axis},'
                f'Yaw=(Speed={y[0]},AngleMin={y[1]},AngleMax={y[2]}),pitch=(Speed={p[0]},AngleMin={p[1]},AngleMax={p[2]}),'
                f'bUseRotationAccel=False,RotationSpeedThreshold=10,bRotationSound=False)')
    return '(' + one(1, 'BN_turret_yaw', yaw, (45, -45, 45)) + ',' + one(2, 'BN_turret_pitch', (45, -45, 45), pitch) + ')'   # (0.74.59: the stock names)


def mount(part, info, fcs):
    name = f'Tani_{part}'
    bp = f'{DEST}/BP_SV_{name}'
    me = obj(bp).replace(f'.BP_SV_{name}', f'.Default__BP_SV_{name}_C')
    slots = len(info['sockets'])
    return {
        'path': bp,
        'parent': 'LiveAIGroundVehicleObject',
        'scs': [
            # both mesh fields, as the stock Mk45's template has them: UE 5.4 draws and poses from SkinnedAsset, but with
            # SkeletalMesh (deprecated, still a property) empty AC8's fire control found no muzzle socket and fired from
            # the mesh's origin along its forward (0.74.50-0.74.51: the turret tracked, the shells left its foot southward)
            {'name': 'TurretPoseableMesh', 'class': 'PoseableMeshComponent', 'parent': 'RootComponent',
             'props': {'SkeletalMesh': obj(f'{DEST}/Model/SK_SV_{name}'), 'SkinnedAsset': obj(f'{DEST}/Model/SK_SV_{name}')}},
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
                        **({'AimingMethod': fcs['aiming']} if fcs.get('aiming') else {}),
                        'FireControl': (f'(LauncherDirection=SlotSocket,CaptureDistance={fcs["capture_cm"]},'
                                        f'CaptureMinDistance={fcs.get("min_cm", 0)},'
                                        + (f'PredictionOffsetTime={fcs["lead_s"]},' if fcs.get('lead_s') else '')
                                        + f'CaptureAngleRange={fcs["cone"]},ActivationTime={fcs["activation"]},'
                                        f'TriggeringTime={fcs["triggering"]},ShotIntervalTime={fcs["interval"]},'
                                        f'RestingTime={fcs["resting"]},TriggerCount={fcs["trigger_count"]})'),
                        # (bDirectEdit left off, as every stock arm: 0.74.57's bDirectEdit + SlotNum didn't give the arm
                        # its muzzle; the stock arms get it from their NPC row's fire control row, NpcFCSId0, which
                        # supplies Performance with bDirectEdit off: 0.74.58 gives the T5's row one, the stock flak gun's)
                        'Performance': (f'(FireRate={fcs["fire_rate"]},MagazineCapacity={fcs["magazine"]},'
                                        f'ReloadTime={fcs["reload"]},SlotNum={fcs.get("slot_num") or slots},'
                                        'SlotSocketPrefix=GUN)'),
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


VLS_CELLS = 8                                          # (SOC_Vls_01..08: the export's, every block's)


def vls_mount(part, info, fcs):
    """(2026-11-12, WP1's VLS route: docs/re/TANICORN.md "VLS", the Mk 41's way) a VLS block's blueprint BP_SV_Tani_<part> on the
    gun mounts' native ALiveAIGroundVehicleObject and layout (mount), but:
      TurretMesh  a SkeletalMeshComponent under the Mk 41's component name (its TurretMesh is a static mesh; a LauncherCommon
                  reading its sockets off a skinned one is the Ladon's HatchAnimSK), both mesh fields as every mount since
                  0.74.52, its cells SOC_Vls_01..08 on Body (the Mk 41's spelling), in single-node mode on
                  AS_SV_Tani_<part>_Open held at 0 (the lids shut), not playing: Scripts/sv_tanicorn.lua plays it open when the
                  block fires and back shut after (its lids watch)
      the arm     AIControlCommon + LauncherCommon (no bones: MeshComponentName TurretMesh, SlotSocket, the VLS prefix, SlotNum
                  8) + ProjectileCommon (the Mk 41's missile): in game the row's arm (SV_FCS_TaniVLS, from NPC_FCS_VesselVLSmk41:
                  BP_FCS_Vessel_VLS_VE002_mk41, the same launcher on the same component name) replaces it, as on every mount
      the wreck   as the mounts': TurretMesh hidden, DamagedStaticMesh (SM_SV_Tani_<part>_DAM) shown
      the hit     a sphere round its cells: their middle, the farthest cell's reach + hit_pad_cm (EnemyPawn)"""
    name = f'Tani_{part}'
    cells = sorted(s['name'] for s in info['sockets'])
    assert cells == [f'SOC_Vls_{i:02d}' for i in range(1, VLS_CELLS + 1)], (part, cells)
    assert info.get('kind') == 'vls' and (info.get('anim') or {}).get('name') == 'Open', (part, info.get('kind'), info.get('anim'))
    mid = [sum(s['loc'][i] for s in info['sockets']) / len(info['sockets']) for i in range(3)]
    reach = max(sum((s['loc'][i] - mid[i]) ** 2 for i in range(3)) ** 0.5 for s in info['sockets'])
    sk, anim = obj(f'{DEST}/Model/SK_SV_{name}'), obj(f'{DEST}/Model/AS_SV_{name}_Open')
    return {
        'path': f'{DEST}/BP_SV_{name}',
        'parent': 'LiveAIGroundVehicleObject',
        'scs': [
            {'name': 'TurretMesh', 'class': 'SkeletalMeshComponent', 'parent': 'RootComponent',
             'props': {'SkeletalMesh': sk, 'SkinnedAsset': sk, 'AnimationMode': 'AnimationSingleNode',
                       'AnimationData': (f'(AnimToPlay="{anim}",bSavedLooping=False,bSavedPlaying=False,'
                                         'SavedPosition=0.000000,SavedPlayRate=1.000000)')}},
            {'name': 'DamagedStaticMesh', 'class': 'StaticMeshComponent', 'parent': 'RootComponent',
             'props': {'StaticMesh': obj(f'{DEST}/Model/SM_SV_{name}_DAM'), 'bVisible': 'False'}},
            {'name': 'DamagedCollision', 'class': 'SphereComponent', 'parent': 'RootComponent',
             'props': {'SphereRadius': str(round(reach + fcs['hit_pad_cm'])),
                       'RelativeLocation': f'(X={int(round(mid[0]))},Y={int(round(mid[1]))},Z={int(round(mid[2]))})',
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
                    'LauncherModule': {'$new': 'LiveFCSModule_LauncherCommon', 'props': {
                        'MeshComponentName': 'TurretMesh',
                        'FireControl': (f'(LauncherDirection=SlotSocket,CaptureDistance={fcs["capture_cm"]},'
                                        f'CaptureMinDistance={fcs["min_cm"]},CaptureAngleRange={fcs["cone"]},'
                                        f'ActivationTime={fcs["activation"]},TriggeringTime={fcs["triggering"]},'
                                        f'ShotIntervalTime={fcs["interval"]},RestingTime={fcs["resting"]},'
                                        f'TriggerCount={fcs["trigger_count"]})'),
                        'Performance': (f'(FireRate={fcs["fire_rate"]},MagazineCapacity={fcs["magazine"]},'
                                        f'ReloadTime={fcs["reload"]},SlotNum={VLS_CELLS},SlotSocketPrefix=VLS)'),
                    }},
                    'ProjectileModule': {'$new': 'LiveFCSModule_ProjectileCommon', 'props': {
                        'WeaponClass': f'{obj(fcs["weapon"])}_C'}},
                }}],
            },
            'DamagedStateComponent': {
                'DefaultDestroySystemList': [{'$new': 'LiveDefaultDestroySystemChangeMesh', 'props': {
                    'DestroyHideMeshNameList': '((ChangeTime=0,TargetMeshName="TurretMesh",bHideToFinalExplosion=True,bReflectChildMesh=False))',
                    'DestroyVisibleMeshNameList': '((ChangeTime=0,TargetMeshName="DamagedStaticMesh",bHideToFinalExplosion=False,bReflectChildMesh=False))',
                    'bChangeMeshes': 'True', 'bHideMeshes': 'True'}}],
            },
        },
    }


def hull_bp(parts_on, rig=None, live=None, name='HULL'):
    """(0.74.60) THE TANACORN whole, its parts drawn on their sockets (docs/design/INVINCIBLE_FLEET.md WP2, the first step:
    the ship on the sea; the parts become live AI parts in the next): BP_SV_Tani_HULL on the native
    ALiveAIGroundVehicleObject (as the test mount: its spawn route through the model row is proven), the hull's static mesh
    (its 36 Mount_* sockets) and, on each part's socket, that part's skeletal mesh as a PoseableMeshComponent at its rest
    pose (the VLS hatches shut, the guns level, the railcannon down in its bay and the sub-railguns 6 m down under their
    shut hatches: the stowed ship). parts_on: [(part, [socket name, ...])].
    (2026-11-11, WP4's route B2: docs/design/INVINCIBLE_FLEET_RISE_FORD.md 2.3, 4.1) rig: the rise rig's json (part RIG).
    Then RiseRig (our SK_SV_Tani_RIG: bones only and one hidden triangle) comes first on the RootComponent, and HullMesh hangs
    on its SOC_Hull, so the whole ship rides the rig's animated bone: AS_SV_Tani_RIG_Rise in single-node mode, not playing,
    its saved position at the animation's END (the rest pose: the hull on the water, Ctrl+Y as before). Lua scrubs it to 0
    and plays it (sv_tanicorn.lua Ctrl+R). An undrawn skinned mesh refreshes its bones (and what hangs on them) only with
    AlwaysTickPoseAndRefreshBones, and update-rate optimisations off so distance never slows it. No collision of its own.
    (2026-11-11, WP2 step 2, route (a): docs/design/INVINCIBLE_FLEET.md "WP2 step 2") live: the parts (LIVE) whose sockets
    carry a LiveChildActorComponent in place of their drawn mesh, never both: Part_<socket> on HullMesh's Mount_<socket>,
    child_class the mount's own blueprint (made earlier in the same spec: the hull's come last), which TaniBuild sets with
    UChildActorComponent::SetChildActorClass (it makes the <comp>_<class>_CAT template every stock part has). Each child is a
    live AI part through the world data's child desc (tools/build_survival_world.py tanicorn_units, TANI=1 builds only).
    name: the blueprint's (BP_SV_Tani_<name>): HULL drawn whole (live None: byte for byte the 0.74.60-0.74.64 spec), HULLLIVE."""
    def sk(p):
        return obj(f'{DEST}/Model/SK_SV_Tani_{p}')
    hull = {'name': 'HullMesh', 'class': 'StaticMeshComponent', 'parent': 'RootComponent',
            'props': {'StaticMesh': obj(f'{DEST}/Model/SM_SV_Tani_HULL'),
                      'BodyInstance': '(CollisionEnabled=QueryOnly,ObjectType=ECC_GameTraceChannel3,'
                                      'CollisionProfileName="EnemyPawn")'}}
    scs = [hull]
    if rig:
        end = rig['anim']['length_s']
        scs = [{'name': 'RiseRig', 'class': 'SkeletalMeshComponent', 'parent': 'RootComponent',
                'props': {'SkeletalMesh': sk('RIG'), 'SkinnedAsset': sk('RIG'),
                          'AnimationMode': 'AnimationSingleNode',
                          'AnimationData': (f'(AnimToPlay="{obj(f"{DEST}/Model/AS_SV_Tani_RIG_Rise")}",bSavedLooping=False,'
                                            f'bSavedPlaying=False,SavedPosition={end:.6f},SavedPlayRate=1.000000)'),
                          'VisibilityBasedAnimTickOption': 'AlwaysTickPoseAndRefreshBones',
                          'bEnableUpdateRateOptimizations': 'False',
                          'BodyInstance': '(CollisionEnabled=NoCollision,CollisionProfileName="NoCollision")'}},
               dict(hull, parent='RiseRig', socket='SOC_Hull')]
    for part, sockets in parts_on:
        for s in sockets:
            if live and part in live:                  # (a live part: the mount's own blueprint as a child actor)
                scs.append({'name': f'Part_{s}', 'class': 'LiveChildActorComponent', 'parent': 'HullMesh',
                            'socket': f'Mount_{s}', 'child_class': f'{obj(f"{DEST}/BP_SV_Tani_{part}")}_C'})
                continue
            scs.append({'name': f'Part_{s}', 'class': 'PoseableMeshComponent', 'parent': 'HullMesh', 'socket': f'Mount_{s}',
                        'props': {'SkeletalMesh': sk(part), 'SkinnedAsset': sk(part)}})
    return {'path': f'{DEST}/BP_SV_Tani_{name}', 'parent': 'LiveAIGroundVehicleObject', 'scs': scs,
            'cdo': {'AutoPossessAI': 'PlacedInWorldOrSpawned', 'GameObjectId': '1000', 'GameObjectCategory': 'Category_Ship',
                    'PursuitPointOffset': '(X=0,Y=0,Z=45000)', 'bKeepOnGround': 'False', 'bIsSea': 'True',
                    'bShowHUDBox': 'True', 'BriDebriIconType': 'Weapons',
                    # (2026-11-11) never skipped far off (the Alicorn's desc has both: docs/re/ALICORN.md; its world-data
                    # desc too, tools/build_survival_world.py): the rise's transforms must update at any range
                    'bIgnoreMeshOptimize': 'True', 'bIgnoreSetAutoSkipUpdateTransform': 'True'}}


# milestone 0's mount: the Mk45's fire control, but searching the air (it's to track and fire at the player)
T5_FCS = {'search': 'AIR_ONLY', 'yaw': (40, -180, 180), 'pitch': (40, 0, 80), 'capture_cm': 600000, 'cone': 180,
          'activation': 2, 'triggering': 4, 'interval': 1, 'resting': 2, 'trigger_count': 1,
          'fire_rate': 10, 'magazine': 20, 'reload': 3, 'weapon': AA_SHELL,
          'hit_radius_cm': 600, 'hit_z_cm': 300}
# The other gun mounts, until WP1 gives each its own weapon (docs/design/INVINCIBLE_FLEET.md WP1: the 16-inch its
# railgun shells, the CIWS and the laser their anti-missile arms): the SAME fire control as the 5-inch, the stock
# vessel AA shell, only the speeds, the lift and the hit sphere each mount's own. So every mount's rig can be seen
# to aim and fire from the test key before its real weapon is built; none of these values is a design decision.
# (0.74.53) the 5-inch's arm as the stock ground flak gun's (BP_FCS_FlakGun_00, dumped from the game: the same
# TurretPoseableMesh, yaw / pitch bones, SlotSocket and GUN prefix as ours) but our bones' arcs and speeds: its flak shell,
# its aiming (not while firing), its lead (5 s), its reach (250 m - 15 km), its timings, no SlotNum. On the vessel AA
# emitter the shells left the mount's foot along its forward, never its barrels (the user's runs of 0.74.50-0.74.52).
T5_FLAK = {**T5_FCS, 'weapon': FLAK_SHELL, 'aiming': 'DoNotWhileFiring', 'lead_s': 5, 'min_cm': 25000,
           'capture_cm': 1500000, 'activation': 0.2, 'triggering': 5, 'interval': 5, 'resting': 1, 'trigger_count': 1,
           'fire_rate': 12, 'magazine': 2, 'reload': 1}         # (0.74.57: a shell a barrel, SlotNum 2 with bDirectEdit)
FCS = {
    'T5': T5_FLAK,
    'T16': {**T5_FCS, 'yaw': (12, -150, 150), 'pitch': (8, -2, 45), 'interval': 2, 'resting': 6, 'fire_rate': 3,
            'magazine': 3, 'reload': 8, 'hit_radius_cm': 1800, 'hit_z_cm': 400},
    'CIWS': {**T5_FCS, 'yaw': (120, -180, 180), 'pitch': (100, -10, 85), 'activation': 1, 'triggering': 2,
             'interval': 0.1, 'resting': 1, 'fire_rate': 30, 'magazine': 60, 'hit_radius_cm': 350, 'hit_z_cm': 300},
    'LASER': {**T5_FCS, 'yaw': (120, -180, 180), 'pitch': (100, -10, 85), 'activation': 1, 'triggering': 2,
              'hit_radius_cm': 350, 'hit_z_cm': 250},
}


# (2026-11-11, WP2 step 2, route (a)) the parts live on BP_SV_Tani_HULLLIVE: every socket of these (the gun mounts, each with
# its blueprint and fire control row: T16_FWD / _AFT, T5_1-6, CIWS_1-4, LASER_FWD_L / _R, LASER_AFT_L / _R); every other
# socket drawn as on BP_SV_Tani_HULL (the VLS blocks too until 2026-11-12). tools/survival_events_festival.py
# TANI_LIVE names the same sockets for the world data (build_survival.py check_tanicorn_build compares them with this spec)
# (2026-11-12) and the VLS blocks (VLS_PARTS: the deck block's 8 sockets VLSD_1..8 on BP_SV_Tani_VLSD, each side block's
# own on its BP_SV_Tani_VLSS_<side>): 32 live parts, only the railcannon and the sub-railguns drawn
VLS_PARTS = ('VLSD',) + tuple(f'VLSS_{s}{n}' for s in 'LR' for n in range(1, 5))
LIVE = ('T16', 'T5', 'CIWS', 'LASER') + VLS_PARTS
# (2026-11-12) the VLS blocks' own arm (vls_mount), as the row Scripts/sv_tanicorn.lua makes (TANI.vls_fcs: SV_FCS_TaniVLS from
# the Mk 41's NPC_FCS_VesselVLSmk41, which replaces it in game): 7 km down to 600 m, all round, a ripple of 4 missiles 0.4 s
# apart, 10 s rest, 8 cells then a 15 s reload; the Mk 41's missile (9 s, 3000 km/h: about 7.5 km). Not a design decision:
# the boss's tuning comes with WP3
VLS_FCS = {'search': 'AIR_ONLY', 'capture_cm': 700000, 'min_cm': 60000, 'cone': 180, 'activation': 2, 'triggering': 1.6,
           'interval': 0.4, 'resting': 10, 'trigger_count': 4, 'fire_rate': 12, 'magazine': VLS_CELLS, 'reload': 15,
           'weapon': VLS_MISSILE, 'hit_pad_cm': 200}


def main():
    parts = json.load(open(os.path.join(BUILD, 'parts.json')))
    only = [x for x in os.environ.get('TANI_PARTS', '').split(',') if x]
    spec = {'sockets': [], 'mesh_sockets': [], 'stubs': [{'path': AA_SHELL, 'parent': 'LiveBulletEmitter'},
                                                         {'path': FLAK_SHELL, 'parent': 'LiveFlakGun'},
                                                         {'path': VLS_MISSILE, 'parent': 'LiveVLSMissile'}],
            'blueprints': []}
    parts_on, hull, rig = [], False, None
    for p in parts:
        if only and p not in only:
            continue
        info = json.load(open(os.path.join(BUILD, 'src_' + p, f'Tani_{p}.json')))
        kind = info.get('kind', 'turret')
        if kind == 'rig':                              # (2026-11-11) the rise rig: its sockets, and the hull's RiseRig
            rig = info
            for s in info['sockets']:
                spec['sockets'].append({'skeleton': obj(f'{DEST}/Model/SKEL_SV_Tani_{p}'),
                                        'mesh': obj(f'{DEST}/Model/SK_SV_Tani_{p}'), 'name': s['name'],
                                        'bone': s['bone'], 'loc': s['loc'], 'rot': s.get('rot', [0, 0, 0])})
            continue
        if kind == 'hull':
            # the hull's sockets: a Mount_<name> for every part, +X the part's forward (TaniBuild: UStaticMeshSocket)
            for s in info['sockets']:
                spec['mesh_sockets'].append({'mesh': obj(f'{DEST}/Model/SM_SV_Tani_{p}'), 'name': s['name'],
                                             'loc': s['loc'], 'rot': s.get('rot', [0, 0, 0])})
            hull = True
            continue
        parts_on.append((p, info.get('on', [])))
        for s in info['sockets']:
            # (0.74.54) on the skeleton and on the mesh itself: the cooked socket map reads the mesh's own first, and the
            # T5's muzzles on the skeleton alone were never found (its shells left the mesh's origin)
            spec['sockets'].append({'skeleton': obj(f'{DEST}/Model/SKEL_SV_Tani_{p}'),
                                    'mesh': obj(f'{DEST}/Model/SK_SV_Tani_{p}'), 'name': s['name'],
                                    'bone': s['bone'], 'loc': s['loc'], 'rot': s.get('rot', [0, 0, 0])})
        if kind == 'turret' and p in FCS:              # (the railcannon and the sub-railguns: none yet)
            spec['blueprints'].append(mount(p, info, FCS[p]))
        elif kind == 'vls' and p in VLS_PARTS:         # ((2026-11-12) the VLS blocks: WP1's VLS route)
            spec['blueprints'].append(vls_mount(p, info, VLS_FCS))
    live_said = ''
    if hull:
        spec['blueprints'].append(hull_bp(parts_on, rig))
        # (2026-11-11) and THE TANACORN with her gun mounts ((2026-11-12) and VLS blocks) live: the same hull, the LIVE
        # parts' sockets child actors
        made = {b['path'] for b in spec['blueprints']}
        lb = hull_bp(parts_on, rig, live=LIVE, name='HULLLIVE')
        kids = [n for n in lb['scs'] if 'child_class' in n]
        for n in kids:                                 # (each child's blueprint built before the hull's, in this spec)
            assert n['child_class'].rsplit('.', 1)[0] in made, (n['name'], n['child_class'])
        spec['blueprints'].append(lb)
        live_said = (f'; BP_SV_Tani_HULLLIVE: {len(kids)} live parts ({", ".join(n["name"] for n in kids)}), '
                     f'{len(lb["scs"]) - len(kids) - (2 if rig else 1)} drawn')
    out = os.path.join(BUILD, 'tani.spec.json')
    json.dump(spec, open(out, 'w'), indent=1)
    print(f'spec.py: {out}: {len(spec["sockets"])} sockets, {len(spec["mesh_sockets"])} hull sockets, '
          f'{len(spec["stubs"])} stubs, {len(spec["blueprints"])} blueprints '
          f'({", ".join(b["path"].rsplit("/", 1)[1] for b in spec["blueprints"])}){live_said}')


if __name__ == '__main__':
    main()
