# VALKA (AC7 Mission 18's Mihaly, ported): research, 2026-10-24

User's spec: memory `valka-boss`; config `Scripts/main.lua` CFG.specials.valka; records `tools/survival_events.py`
VALKA_* / build_valka; world data `tools/build_survival.py` valka_unit.
Tags: **[V]** verified from data, **[I]** inferred, **[T]** needs an in-game test.

## 1. Reading AC7 files
- AC7 assets carry a per-file XOR layer ("ACE7" header). `tools/ac7_decrypt.py <export root> <out> [regex]` removes it
  (UAssetAPI's AC7Decrypt scheme; key table `build/ac7/AC7Key.bin`, 217 x 1024 bytes, never committed or shipped). [V]
- Decrypted packages are UE 4.18 (`VER_UE4_18`): `UAssetGUI.exe tojson <in> <out> VER_UE4_18` (<UAssetGUI folder>)
  dumps them, Kismet bytecode included. `build/ac7/kdec.py` prints the bytecode with script offsets (UE 4.18 sizes:
  pointer 8, FName 12), `build/ac7/trace.py` follows a flow from an offset. [V]
- Sounds: `tools/ac7_sfx.py` (AC7 `game_se.bnk` / `.pck` + the wwiser xml, $AC7_BNK_DIR) writes
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
  UE4SS.log). A source build of 5.4.4 is at $UE (Windows-only dependencies). [V]

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
- Paint: docs/re/AIRCRAFT_MATERIALS.md (AC8's aircraft master samples virtual textures only).

## 6. Mission 18's lens flash (ms18_LensEffect1, decrypted) [V]
`ms18_LensEffect_VFX` spawns `ms18_LensEffect1` (LensEffectActorClass, life from the event). That actor: a
MaterialBillboardComponent (one MaterialSpriteElement: M_LensBokeh1, BaseSizeX / Y 0.4, bSizeIsInScreenSpace,
DistanceToOpacity / DistanceToSize curves) and three planes (Plane_Flare1 M_LensFlare1 with Ace_SunGlareVR, Plane_Flare2
M_LensFlare2 with T_EML_shine01, Plane_Ring M_LensRing1 with T_EML_LensFlare01; RelativeLocation X 79.24) that it moves
each tick along the camera-to-`light_dummy` line (ScreenSpaceOffsetX / Y), all additive; EffectLifeTime 5 s; alpha by
the curve Ms18_lensAlpha (keys (0.1, 1.0), (0.831, 0.84), (1.0, 0.0) over its life) into each material's `Alpha`.
Survival's rebuild (0.68): AC7's textures on instances of AC8's Mission 23 flare, all as screen-space billboard elements
on one spawned actor (no ghost planes yet). [T]

## 6. Her end in a STORE (2026-11-11; untested in game)
RE_SV_ValkaEnd (the WARNING and noise off, ATTACK_BASE, SV_ValkaUp 0), RE_SV_ValkaChargeOff and RE_SV_ValkaAlertOff fired
while a game's landing STORE is open run nothing there (hard rule 64): the host fires them again once its STORE is shut
(SV_ValkaUp read back; an Off dropped when its On came after it; the band's newer preset fired again after a late end,
which puts ATTACK_BASE back), a joiner holds the forwarded ones until its own is shut: docs/re/COOP.md section 13.

## 7. Why she fought in one spot, and what she flies now (2026-11-22; the valka autotest suite)
The user: "she seems to fight in one place, she doesn't seem to take the fight anywhere and just flies around in one
spot", "She needs to be more active". Measured with tools/ac8-autotest's `valka` suite (her disguise off; your plane on
the DOWN autopilot round the airfield, then a 30 km leg west, then round there; `valka-track:` every 0.5 s,
tools/autotest/valka_track.py: numbers and a top-down SVG). Baseline 0.74.201 (run 20261122_130001_claude) [V]:
- she flew NLID_SV_Fighter (every row searchSetup touches, hers too) at the x40a row's PilotRank 2 and stock speeds;
- her orders were given again every 5 s (64 in 5 minutes) and LastTGT every 6 s (54); LastTGT is a 20 s
  PursuerTarget 200 m behind you whose close-range mode, inside ~3 km and nose-on, copies your heading
  (docs/re/BEHAVIOUR_NATIVE_MOVE.md section 2, a5 / a6) and whose closure drops her to min speed when the aim point is
  behind her: re-asked every 6 s she never left it;
- result: from 15 km she closed at your speed (12.5 km mean over the first 80 s); then, wherever you flew, she sat
  3.1 km behind you (median 3.1, max 3.4 km round the second circle), at your speed, nose on you 79 % of the time,
  firing her railgun every ~17 s and a post-stall every ~20 s: she mirrored your circle at 3 km. Her fight's centre moved
  54 % as far as yours (she trails, she never leads or passes).
0.74.202 (CFG.specials.valka): her row flies `luaset` NLID_SV_Lancer (slashing passes, zoom climbs) at `pilot_rank` 5,
speed / cruise / acceleration x `speed_x` / `cruise_x` / `accel_x`, turn rates + `turn_add` (sv_rows.lua, at the main
menu: hard rule 20); LastTGT only when you sit behind her (turn_every_s 0, behind_gap_s 12); her orders every 20 s;
post-stalls a 50 % chance every 25 s within 1.5 km; farther than chase_km 6 for 4 s she blinks onto your six (ring E,
2.5 km; chase_gap_s 15); hit, 2 blinks onto your six or across your nose (rings D 1.5 km / E 2.5 km, attack_ahead 0.4).
Her portal (section 8). [T] each in the next runs.

## 8. Her portal (2026-11-22; sv_anomalies_valka.lua SPC.V.portal*, CFG.specials.valka.portal)
The user: "try to build a 3D Portal, an event horizon that she spawns out of". Built at run time from the game's own
pieces (no container): one actor of ours with StaticMeshComponents (AddComponentByClass) and dynamic material
instances, plus Niagara systems at moments. It opens where her opener fires from as the railgun charges (facing you,
each mesh grown from nothing over open_s), her shot comes out of it, she spawns exit_back_m behind its face and flies
out (a burst), and it closes hold_s later. Co-op: the host's "vp" (open / she's through), each joiner draws its own.
The portalprobe pieces (autotest run 20261122_131212_claude, each 220 m across 9 km north of the runway) [V]:
- draw against the sky: the engine's /Engine/BasicShapes Cylinder / Sphere with BasicShapeMaterial (its `Color`
  vector: a solid black disc); /Game/VFX/Mission/Traning/MI_TrainingRing (M_TrainingRing: a solid glow, `Color`,
  `Opacity`) on a ring mesh; MI_TrainingRingGlow (M_TrainingRingGlow: see-through, brightest at its edges; `Color`,
  `EmissiveIntensity` 2, `Opacity` 0.05, `EmissiveFresnelFalloff`, `EmissiveFresnelInverseHardness`) faint as stock;
  the ring meshes SM_MGF_MagneticControlRingParts001_I07 (finned) and SM_UNI_OrbitElevatorRing002_I22 (plain) lie flat
  (their axis Z); Mission 27's NS_MGF_CoreDest1st_CoreElectricPlasma draws a column of light;
- draw nothing against the sky: MI_CoreDest_ShockDomeRefraction001, MI_CoreDest_AfterExitBlackSmokeMesh,
  /Game/VFX/Vehicles/Weapon/UAV/Barrier/MI_Distortion (refraction / depth materials), NS_ElectricDischargeM001 at x20,
  Mission 10's main-gun charge systems; MI_TrainingRingGlow on SM_MGF_MagneticControlRing002_I07 drew it black;
- the IGC "ShockWave" systems (Ms25, Ms29) are huge dust / smoke clouds, not rings.
- The autotest's own camera (ST.look) showed every picture level, whatever its pitch [T: the read-back added].
The black hole (0.74.207+; the user: "I want the portal to look like an event horizon from a black hole", "Needs to be a
3D model, not a png floating in the air"): tools/valka_portal/build.sh makes eight pieces in Blender 3.3 from numbers
(make_portal.py: the shadow sphere, the photon ring, the lensed arcs inner / outer, the disk's hot / warm / cool streak
layers, its brighter approaching side; preview.py renders them as the game holds them), imports them into the AC8
template project (ue_import.py: each slot on /Engine/BasicShapes/BasicShapeMaterial, AC8 has it), cooks VERSIONED and
packs /Game/Mods/SurvivalMode/ValkaPortal into SurvivalMode_ValkaPortal_P (build_all.sh stages it with her X-02S; the
builds without her drop it). In game each piece is coloured by a dynamic instance of AC8's MI_TrainingRing (its Color;
BasicShapeMaterial's Color 0 for the shadow, MI_TrainingRingGlow for the haze), sized as one model (`abs`: 1 unit =
the shadow's diameter = size_m), the arcs and the shadow facing you, the disk tipped 5 degrees towards you, the whole
hole turned to you each tick (`face_you`), the disk's layers turning (inner faster). [V] in game, runs
20261122_140649 / 141607 / 142542: it draws at full scale (250 m shadow, 1.6 km disk) from your own view at her reveal
14 km out and from off its axis; hard rule 74 for its rolls. Her blinks open small ones (28 m) where she goes and comes
back. Her opener's lens flash is dimmed (flare.portal_x 0.3) and halved while the hole is up (its beam covered it).
