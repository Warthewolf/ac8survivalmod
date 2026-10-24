# VALKA (AC7 Mission 18's Mihaly, ported): research, 2026-10-24

User's spec: memory `valka-boss`; config `Scripts/main.lua` CFG.specials.valka; records `tools/survival_events.py`
VALKA_* / build_valka; world data `tools/build_survival.py` valka_unit.
Tags: **[V]** verified from data, **[I]** inferred, **[T]** needs an in-game test.

## 1. Reading AC7 files
- AC7 assets carry a per-file XOR layer ("ACE7" header). `tools/ac7_decrypt.py <export root> <out> [regex]` removes it
  (UAssetAPI's AC7Decrypt scheme; key table `build/ac7/AC7Key.bin`, 217 x 1024 bytes, never committed or shipped). [V]
- Decrypted packages are UE 4.18 (`VER_UE4_18`): `UAssetGUI.exe tojson <in> <out> VER_UE4_18` (E:\DOWNLOADS\uassetgui)
  dumps them, Kismet bytecode included. `build/ac7/kdec.py` prints the bytecode with script offsets (UE 4.18 sizes:
  pointer 8, FName 12), `build/ac7/trace.py` follows a flow from an offset. [V]
- Sounds: `tools/ac7_sfx.py` (AC7 `game_se.bnk` / `.pck` + the wwiser xml, D:\Ace Combat PAKS\bnk's\Windows) writes
  WAVs, per-event trees and `build/ac7/sfx/NOTES.md` (layers, loops, volumes, attenuation). [V]

## 2. Mission 18's opener (ms18_Phase_01, ExecuteUbergraph) [V]
1. MissionVariableEvent_34: `01_dummy_playertarget` is activated on the player ("railgun target") and follows them at
   (player_speed, 0, 30) units, player_speed = km/h x 10 x 1.2.
2. 2 s later `01_shoot_eml_event`: `01_dummy_eml_1` (ms18_dummy_eml_p1: a hidden AITurret_Pawn of its own, wp_eml_p1,
   an AIMihaiComponent; not Mihaly's plane) activated once, 0.5 s on, at (70000, 0, 50) relative to the player (mode 2,
   along where they're aiming), yaw 180: facing them, then fixed there (it never follows). [V]
   AC7's units are NOT AC8's centimetres: 70000 is not 700 m. In game the light is about 9 km out (user, 2026-10-24:
   "she's supposed to be 9km from me in a fixed position in the sky that the player was currently aiming at, she
   can't be attached to the aircraft at all"; "70000 does not translate to 700m"). Never convert AC7 distances as cm.
   (The lens flash, ms18_LensEffect1, is a screen-space billboard that follows its tagged `light_dummy` actor.)
3. On its activation: StopUnit 6 s ("railgun shot preparation"), attack-target exception, EngagementOrder at the
   target dummy, HUD warning 6 s, BeginHUDDistortion(0.04, 0, 0, 60), `01_dummy_light` (the lens flash,
   ms18_LensEffect_VFX: LensEffectActorClass ms18_LensEffect1, life 2 s) at the same spot, AIMihai.StartRailgunAiming(6).
4. After the 6 s: FireOneShotWeapon(0, target dummy) on the dummy railgun; StopUnit "railgun firing end".
Mihaly's weapon `wp_eml`: 111111 cm/s (4000 km/h), raycast radius 80, life 5 s; FX_EML_Muzzleflash02,
FX_EML_Projectile03 (trail), impacts FX_MachineGunHit_*; sounds OBJ_M18_MIHAI_SHOT, _BULLET (loop) / _BULLET_Stop,
_BULLET_PASS; camera shake EMLBulletDamage.

## 3. Mihaly's invincibility (ms18_Phase_02) [V]
`SetMinHealth(100)`, then 80 / 20 / 0 as radio lines play ("02_mihai_damage_*"): a health floor, nothing else.
VALKA never gets one.

## 4. AC8 side
- No X-02S in AC8 (only ADFX-02). AC8's aircraft EML: Mission 26's x40a ("Nightmare", unit EI_Unit_01_Air0) with four
  parts (WD ChildAIObjectDescs): LaserPod, RailGun, RailGunCK (scripted sure kill), RailGunPF. Each railgun is a
  BP_AITurret_Pawn with LiveFCSModule_LauncherTripleRailCannon; RG_CP: TriggerCount 3, MagazineCapacity 3,
  ShotIntervalTime 0.33, PredictionOffsetTime 0.5, SpinUpTime 3; charge sounds AKE_Ms29_..._x40a_Railgun_Charge_*;
  rounds BP_wp_eml_Nightmare_*. Mission 26 fires them with LiveFireOneShotWeapon {WN_WEAPON_1, <part>, target} and
  holds the CK one with LiveAIEngagementOrder EvadeOnly. [V]
- VALKA: that unit ported with its parts (as the Ladon), on ace row sv_ace_valka_x40a_l (OP1016_x40a_MS26), the
  launcher modules made single-shot at run time (FindAllOf; only hers and the dummy's are in Survival). [T]
- The opener's dummy (survival_events.VALKA_EML_*): the x40a's RailGun part alone, as AC7's ms18_dummy_eml_p1 is a
  turret of its own. A part desc has no NPC row (its row comes through the parent's DT_NPC ChildNPCId); the RailGun's
  DT_NPC row is OP1016_x40a_RG, so mission row sv_valka_eml (a copy of Mission 22's gepa_common) points at it, on the
  x40a's unit desc with ChildAIObjectDescs emptied. main.lua spawns it once 9 km along the player's nose, hides it,
  charges, fires RE_SV_ValkaEmlShot, then spawns VALKA there and removes it. [T] (does a turret stay put in the
  sky; does the EML round reach 9 km; is its actor a LiveAIGameObject)
- First build (0.63.x) got this wrong: VALKA herself was the dummy, kept 700 m ahead and re-teleported every tick;
  her attached parts showed and she fired QAAMs / missiles / gun from ~470 m (test of 2026-10-24).
- The editor work (X-02S model, AC7's EML effects) needs UE 5.4: AC8's engine ("Using engine version: 5.4",
  UE4SS.log). A source build of 5.4.4 is at E:\UE_5.4 (Windows-only dependencies). [V]

## 5. The X-02S in AC8 (tools/x02s)
- AC7 builds the X-02S from more than `x02s.gltf`: `x02s_GearOff_SM` (closed gear doors), `x02s_RefuelOff_SM` (closed
  refuel panel) and a special-weapon mesh `x02s_SWP1..3` (bay covers; SWP3 the long centre piece between the engines)
  are separate meshes. Without them she had holes (user, 2026-10-24: "told you it was missing a mesh"). prepare.py
  merges GearOff, RefuelOff and SWP3 into her skinned mesh on the Body bone (SWP3 posed through its own bones). [V] (a
  software render of the merged mesh closes the holes) [T] in game.
- AC7's EML pod for the X-02S is `Vehicles/Weapons/w_eml_x0` (its export pulls in the X-02S's own x02s_00 textures);
  the racks `WeaponRack_w_eml_x0..2` place it. Not used yet. [V]
- Bone rotations: AC7 .psa key (x, y, z, w) -> UModel glTF (-x, -z, y, w) -> UE 5.4's glTF import mirrors y/z
  (positions UE = (x, z, y) x 100), so a key goes into UE's bone frame as (x, -y, z, w). Unconverted keys were right
  only where both agree (VariableWing_19) and wrong on VariableWing_03/05/07/09: her wings came apart in game (0.67.1).
  With the conversion every wing bone's frame 0 matches its rest (|dot| 1.0), and a render of the swept glTF pose is
  the proper delta. [V] [T] in game.
- Paint: tools/re/AIRCRAFT_MATERIALS.md (AC8's aircraft master samples virtual textures only).

## 6. Mission 18's lens flash (ms18_LensEffect1, decrypted) [V]
`ms18_LensEffect_VFX` spawns `ms18_LensEffect1` (LensEffectActorClass, life from the event). That actor: a
MaterialBillboardComponent (one MaterialSpriteElement: M_LensBokeh1, BaseSizeX / Y 0.4, bSizeIsInScreenSpace,
DistanceToOpacity / DistanceToSize curves) and three planes (Plane_Flare1 M_LensFlare1 with Ace_SunGlareVR, Plane_Flare2
M_LensFlare2 with T_EML_shine01, Plane_Ring M_LensRing1 with T_EML_LensFlare01; RelativeLocation X 79.24) that it moves
each tick along the camera-to-`light_dummy` line (ScreenSpaceOffsetX / Y), all additive; EffectLifeTime 5 s; alpha by
the curve Ms18_lensAlpha (keys (0.1, 1.0), (0.831, 0.84), (1.0, 0.0) over its life) into each material's `Alpha`.
Survival's rebuild (0.68): AC7's textures on instances of AC8's Mission 23 flare, all as screen-space billboard elements
on one spawned actor (no ghost planes yet). [T]
