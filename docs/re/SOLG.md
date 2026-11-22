# SOLG special round (user's design of 2026-11-03; research only, nothing built)

The user: "pull the Satellite Interception Mission from ACI and put it into a Survival Mode Special Round". No voice
lines, no map: "just the Satellite and all its targets as they play out in Ace Combat Infinity". The SOLG appears in a
special round; if it isn't destroyed in time it hits the airfield and destroys it. AC:I assets are allowed for this
round at the user's request (a second exception to AGENTS.md's stock-only rule, as VALKA's AC7 assets).
The user also pointed at Stonehenge Returns as the example of an AC:I -> AC8 port (section 4).

## 1. The AC:I data ($ACI (.env), outside the repo)
- `$ACI\pkg\updates`: the user's AceInfinityFiles.7z unpacked: PSN packages for UP0700-NPUB31347_00-ACECOMBATINF0001
  (US): the randomly named 5.47 GB package is the base game (content type 5, v02.00, not a patch), A0200-A0211 the
  updates, a .rap licence (not needed: the DATA files are plain).
- `$ACI\NPUB31347\USRDIR`: installed with `$ACI\tools\pkg_extract.py` (retail PS3 PKG: AES-128-CTR, the public PS3
  package key, counter = IV + block), base then A0200..A0211 in order. No RPCS3 needed.
- `$ACI\aci_kit`: Inveigh's kit (ACI_EXTRACTION_BRIEF.md in the repo root). `set ACI_USRDIR=$ACI\NPUB31347\USRDIR`;
  Python 3.12 (`py -3.12 -I`) has numpy, Pillow, scipy, lz4, pycryptodome. The brief's R-101 smoke test gives its exact
  values on this install.
- `$ACI\tools`: survey.py (chunk types), models.py (an FHM's models), grep_pacs.py (search every entry),
  solg_assemble.py (the whole SOLG as OBJ + previews). Outputs in `$ACI\work\solg` (asm\solg_l1_*.png previews).

## 2. The mission: Special Raid "SOLG"
- AC:I text (DATA94 entry 3): "SOLG -Schroeter-" / "-Oort-" / "-Lexell-": "The predicted impact site of SOLG is inside
  the city. Your mission is to destroy the target in mid-air and minimize damage to the predicted impact site."
  Awards: "the operation to prevent the descent of the SOLG". Raid hints: "Use Forced Sorties when SOLG appears!".
- Packages (each mission = models, data, Lua script): DATA01 213 / 214 / 215, 216-218, 219-221 (likely the three
  versions) and DATA92 528 / 529 / 530 (the latest; its models also carry o_fa45, o_uavb). Enemy aircraft in them:
  o_su47, o_f22a, o_37s1, o_fa45, o_uavb, o_de01-05. DATA01 213 holds every SOLG texture (DATA92 528 only the body's).
- The Lua scripts (215 / 530, Lua 5.1 bytecode) only play music and radio: bgm_micr10_a / bgm_micr12_a,
  `SetMs10StallAltitude` (the ceiling is raised for this mission), talkers Enemy Fighter Squadron A-J. The mission's
  logic isn't in them.
- The data entry (214 / 529): a 1.25 MB chunk (header "1.7.0", "20150820,190555"), an OIF chunk ("OIF\0104", not
  plain zlib: hashed or packed, NOT DECODED YET; most likely the placements, paths and timing), radio tables
  (micr10_0001-0223, micrcloud_*, 6-oncs_*: line ids only, the subtitles are elsewhere).
- DATA01 429 / 431 / 433: the SOLG's arrival cutscene (222 MOP2 tracks: Tdemo__s_solg_t1__01, Tdemo__s_sg08_t1__00,
  Tdemo__s_sg04_t1__00..05, Tdemo__s_sg05_t1__00..11, ...; camera Tcam__cut__03).
- Target names (DATA94 entry 4's name table, beside CONT_SOLG): CONT_MAG PANEL, CONT_KEW SHELL, CONT_CORE UNIT,
  CONT_SP SHELL, CONT_SOLAR PANEL. Which part is which and their health: not found yet (the 800-byte block before
  each model is identical for all of them: render state, not stats).

## 3. The SOLG model (DATA92 528 / DATA01 213)
Each piece is a model with a live (`_l1`..`_l4`, identical copies) and a destroyed (`_d1`..`_d4`) mesh, shadow meshes
(`_shl*` / `_shd*`), a node tree (MNT), base pose (MOP2) and a collision hull (COLH; the body's is 380 KB). Metres,
y up, +z forward, +x left (the kit's convention). The whole thing is about 2 km long (z -1015..+1015) and 1.2 km
across (x / y +-613).
- `s_solg`: the body, 10414 vertices, texture 0x20004dae (1024x2048). A long lattice barrel one way; at the other end a
  cluster with two rotating rings (nodes `auta1` z 714, `auta2` z 791.5; MOP2 clip `auta` animates them).
- Parts, placed by the body's 68-node tree (`plan_node_<model>_<nn>`; positions from skel.py's base pose):
  | model | count | vertices | texture | where |
  |---|---|---|---|---|
  | s_sg01 | 4 | 5153 | 0x20004c40 | on ring auta1, 330 m out: the four ~600 m arms |
  | s_sg02 | 4 | 1103 | 0x20004c3d | on ring auta2, z 802 |
  | s_sg03 | 4 | 360 | 0x20004c42 | z 802, +-58.65 m |
  | s_sg04 | 6 | 278 | 0x20004c3f + 0x20004fa4 | hull, x +-167.7 m, z 465-573 (two rows of 3): solar panels? |
  | s_sg05 | 12 | 280 | 0x20004c3f + 0x20004fa4 | hull, four diagonal rows of 3, z 465-573: solar panels? |
  | s_sg07 | 32 | 106 | 0x20004e4d | small, round ring auta1 (8 per arm): KEW shells? |
  | s_sg08 | 1 | 49 | 0x20004c3e | the nose, z 1011 |
  | s_sg09 | 1 | 40 | 0x20004fa9 | centre of ring auta1, z 714: core unit? |
  | f_sgc1 | 1 | no mesh | | z 785 (an effect or target point; s_sgc1 / s_sg10 have node trees, no mesh) |
  s_sg06 (200 vertices, 0x20004c43) is in the package but on no plan node (debris or a cutscene piece).

## 4. How Stonehenge Returns ported AC:I to AC8 (AC8_Stonehenge_Returns_Source_1.zip in the repo root)
- AC:I meshes cooked as UE 5.4 static meshes (SM_SH_RailgunBarrel / Turret / EcmCentre / EcmSite, each with a
  `...Wreck` mesh), textures as T_SH_tex<AC:I texture id>, MI_SH_tex<id> instances.
- The units are stock blueprints copied with their mesh references repointed (zen package edits, no blueprint cooked):
  BP_SH_EcmCentre is a child of /Game/Blueprints/Vehicle/AI/MapObj/BPD/BP_BPD_Base (MainMesh = SM_SH_EcmCentre,
  DestroyMesh = SM_SH_EcmCentreWreck, LiveDefaultDestroySystemChangeMesh, a fire control system, the radar tower's
  explosion sound); BP_SH_Railgun is the Land Aegis main cannon's blueprint (BP_GR038_ldbs3_MainCannon) with its meshes.
- Tools/scripts (Python, no extra packages; usmap.pkl = Live-5.4.3): zenw.py (imports: PackageImport =
  (2<<62)|(pkg<<32)|hash index, export hash = city64 of the lower-case utf-16 class name), chdr.py (container header),
  repack5.py, uprop.py (lossless unversioned properties). Tools/NOTES.md = hard rules 1-7 here.

## Decided (user, 2026-11-03)
- Impact: the airfield is **down for 2 rounds** (as the captured airfield after a failed beach assault: landing and
  the STORE closed, the rounds left on the HUD).
- The SOLG round has **no other aircraft**: the satellite and its targets alone (as the Ladon and ALICORN rounds).
- **No cutscene** (user: "We won't need the cutscene either"): DATA01 429 / 431 / 433 aren't ported.

## 5. The fight in AC:I (the Ace Combat wiki's Satellite Interception I page, acecombat.wiki.gg; read 2026-11-03)
6-minute limit, the SOLG falling on Tokyo (the map's height limit raised for these missions: SetMs10StallAltitude):
1. Solar Array Wings (SAWs) and the exterior MAG panels. Broken off, they fly back at the players (damage); a big fire
   starts at the satellite's front after some SAWs are gone.
2. Once all are gone: the KEW shells targetable; its Tactical Laser System (TLS) defences on; small panels fall off
   (damage). (A Su-47 squadron halfway: left out, the user's "SOLG alone".)
3. Once the KEW shells are gone: the four core units at the front; more laser units on the body.
4. Once the core units are gone: the back opens, the special artillery shell (SP SHELL) exposed; destroying it ends
   the SOLG. Time out = failure (in Survival: it hits the airfield).
The user (2026-11-03): "All of the solg pieces were targets that turned on at different phases".

**Which piece is which: AC:I's own data** (2026-11-03). The mission data (DATA92 529, its 1.25 MB graph "1.7.0"
and the OIF resource table) names everything by CRC-32/BZIP2 of the plain name (MSB-first, poly 0x04C11DB7, init and
final xor 0xFFFFFFFF: crc("s_solg") = 0x2f6b50fe). The graph has one record per piece type (graph offsets 143640 ..
146952): +8 flags, +12 crc(HUD name key, DATA94 entry 4's CONT_* table), +20 crc(model), +28 two u16 (health, then
a second value, likely its score), +60.. per-weapon damage rates (the SP shell's 1.0 / 0.1: the higher tiers' limit on
air-to-ground weapons):
| model | count | HUD name | health | 2nd | flags |
|---|---|---|---|---|---|
| s_sg04 + s_sg05 | 6 + 12 | SAW (Solar Array Wing) | 900 | 560 | 0xc01 |
| s_sg07 | 32 | MAG PANEL | 600 | 120 | 0x001 |
| s_sg06 | ? (not on the body's plan nodes) | KEW SHELL | 1000 | 180 | 0x401 |
| s_sg03 | 4 | CORE UNIT | 1500 | 1200 | 0x401 |
| s_sgc1 | 1 (no mesh of its own; node f_sgc1, z 785) | SP SHELL | 2500 | 640 | 0x401 |
| s_solg (body), s_sg01 (the 4 arms) | 1, 4 | SOLG | 1 | - | 0x401 / 0xc01 |
| s_sg02 (ring 2), s_sg08 (nose), s_sg09 (ring 1 centre) | 4, 1, 1 | CONT_UNKNOWN (no name) | 1 | 20 | 0x401 / 0x001 |
| s_sg10 (no mesh) | ? | SOLG | 1 | - | 0x401 |
The KEW shell's record (816 B) holds a second object with gravity 9.8, launch angles (40 / 75 / 90 deg) and speeds
1000-1200: the shells are launched or fall at some point. Where the KEW shells sit isn't in the models: the graph has
~110 placed spots on the barrel's surface (radius 40-64 m, z -912 .. +965; types 0x80084af0 x196 at 75 spots and
0x800853c0 x49 at 36, rounded positions such as (45, 35, -880)): more likely its effect / falling-panel spots or the
TLS turrets than KEW mounts (the wiki: "multiple defensive TLS turrets along its barrel and ammunition storage
units"). Not decoded further.

## 6. Built (2026-11-03, branch feature/solg in a worktree; not committed)
- `tools/solg/` (prepare.py, ue_import.py, build.sh): build/solg/out/SurvivalMode_SOLG_P (44 packages, 9.5 MB, padded),
  /Game/Mods/SurvivalMode/SOLG: SM_SV_SOLG_Body (+_Wreck), SM_SV_SOLG_SG01..SG09 (+_Wreck), 11 textures
  T_SV_SOLG_<id> + flat normal / Livemap, MI_SV_SOLG_<id> on AC8's M_Live_Base (stubbed, never packed; Stonehenge's
  MI_SH_* parent). Static meshes, no collision. tools/build_all.sh stages the container when built.
- Axes: UE 5.4's glTF importer maps glTF (x, y, z) to UE (x, z, y) (ue_import.py's probe). prepare.py turns AC:I a
  quarter about up first, so UE = (AC.z, -AC.x, AC.y) x 100: the SOLG's nose (core end, s_sg08) along UE +X, AC:I's
  left on UE -Y, up up. The body: x +-1015 m, y / z +-55.5 m.
- SM_SV_SOLG_Body has 67 sockets: SG01_01..04, SG02_01..04, SG03_01..04, SG04_01..06, SG05_01..12, SG07_01..32,
  SG08_01, SG09_01, CORE_01 (f_sgc1), RING_1 / RING_2 (e.g. SG08_01 at +1011 m X, CORE_01 +785 m).
- Two prepare.py fixes over the kit: an NTP3 header can be 112 bytes (the kit's fixed +0x78 id read misses s_sg08's
  0x20004c3e: the id is read after GIDX); triangles checked against their normals (none needed flipping).
- `Scripts/sv_solg.lua` (MODULES after sv_spaceport) with test T0 only (TEST ONLY), Ctrl+F6 in sv_main.lua's test keys.

## 7. The carrier
- AC8's flying units with the most part slots (ChildActorComponents, `_CAT`): BP_OP0049_cleo_Base 47, OP0044_norn
  31, the Ladon 19. A part attaches to its parent blueprint's component named in the world data
  (ChildAIObjectDescs' ComponentFieldName), so a part's place is the parent's, not the world data's.
- Mission 23's Celaeno (the airship that launches the Barrier UAVs): WD_Mission023_global unit B_Unit_01_Air0, object
  B_Obj_01_Air0_Celaeno0, row OP0044_cleo_01, faction 2, area 35 km, altitude 500-12000 m, 25 parts (AAGun_01,
  BottomRadome, Core, MainWing_{Top,Bottom}{Left,Right} with 3 each, UAVHatch_L1-3 / R1-3, VLS_01-04,
  Wing_Bottom{Left,Right} #2-4 with 2-4 each): 55 slots with the grandchildren. The SOLG has 65 mounts.
- VALKA already moves parts on a flying AI plane (SPC.V.partsPlace: K2_SetActorLocation on each part actor, again
  every 2 s): the SOLG's parts can be put on its mounts the same way, whatever the carrier's slots.

## 8. Test T0 (installed 2026-11-03 in the user's game: main.lua, sv_main.lua, sv_solg.lua and SurvivalMode_SOLG_P
## over 0.73.76-coop2mp.77 VALKA; backup in the worktree's build/backup/install_before_solg_t0)
In a run: Ctrl+4 (the Ladons' round next), then when a Ladon is up, Ctrl+F6: it's dressed as the SOLG (the 2 km body on
it, its own meshes hidden, its parts each moved onto a SOLG mount with that mount's mesh and put back every 0.5 s).
What to look at: does the SOLG draw (textures, not black or white), is it the right way round (nose / arms ahead along
the Ladon's way), are the Ladon's parts (target boxes) sitting on the SOLG's pieces, can they be locked and shot there.
Log lines: `solg: T0 (...): <carrier> dressed as the SOLG: body on (N of its meshes hidden), N of 65 mounts' sockets
found ...; N of its M parts on mounts (...): <part>-><mount> ...`, `solg: T0 +2 / +10 / +30 s: parts drifted at most
N m off their mounts in 0.5 s ...` (near 0: a part stays where it's put; large: the plane pulls them back each frame),
`solg: SM_SV_SOLG_Body not loaded (...)` (the container didn't mount), `solg: T0: N of the carrier's own meshes came
back on ...`.

**T0 in game (2026-11-03 23:00, the user): the game crashed on Ctrl+F6**, before T0's first log line: access violation
reading 0xffffffffffffffff, the stack all AceCombat8 code (0x144b150c7 <- 0x14433455f <- 0x14429529e <- 0x144295484 <-
0x144332eb3 <- 0x14432e9cd: virtual calls through slots 0x7a0 / 0x610 / 0x340 / 0xa68, the shape of a component's
registration and render-proxy setup). T0's first steps were loading SM_SV_SOLG_Body and adding it as a
StaticMeshComponent. AC8 runs with r.RayTracing, Lumen (hardware RT) and r.GenerateMeshDistanceFields on (its
DefaultEngine.ini, tools/pak_read.py); our project cooked with none, so the static mesh's cooked render data likely
isn't what AC8's renderer reads. Not a hard rule yet (not isolated: loading vs the component vs the render data).
**T0b** (installed 23:08): the SOLG as ONE skeletal mesh, SK_SV_SOLG (prepare.py write_skinned: 133 bones, SOLG /
SOLG_W, a bone per mount and its _W wreck bone, CORE_01, RING_1 / RING_2; 166 primitives, 92,754 vertices; bones
checked in UE: SG08_01 at (101100, 0, 0) cm, CORE_01 (78505, 0, 0), SG04_01 (57307, -16771, 0)), added as a
SkeletalMeshComponent (VALKA's proven route), painted with an instance of the x40a's gear material per texture
(VALKA's paint 16), the wreck bones hidden (HideBoneByName), parts on the bones (GetSocketLocation by bone name).
Every step is a crumb (`solg: T0 ...` in AC8SurvivalMode_crumbs.log) so a crash shows where it stopped.

**T0b in game (2026-11-03 23:14, the user; screenshots her screenshots 2288340_20261103231432_1 / 231516 / 231526):
it works.** Every step ran (the crumbs); SK_SV_SOLG drew textured (grey metal, the panels' and lattice's detail) on the
gear-material instances (10 of 10 slots), the 65 wreck bones hidden, nose and arms ahead with the barrel trailing; the
Ladon's 12 parts SPC.V.parts found sat on SOLG mounts with their target boxes there ("MAIN ENGINE" on its mount); its
other parts' boxes stayed at the Ladon's own place mid-barrel (not found by SPC.V.parts: its CIWS / VLS). Their drift
off the mounts: 0.0 m at +2, +10 and +30 s at 2500 km/h (K2_SetActorLocationAndRotation every 0.5 s holds a part on a
flying AI plane). The `solg` tick cost 0.6 ms (worst 8). Not shot at yet (the user: "i didn't shoot anything but the
targets are there"). Candidate hard rule once a part is also shot down there: a skeletal mesh of ours added on an AI
plane carries any look, and its parts, moved onto its bones every 0.5 s, stay there.

## 9. Next (after T0)
1. The SOLG's own unit: Mission 23's Celaeno ported (port_unit + retag_parts), its meshes dressed as T0's, on a
   descending path from high and far to the airfield over AC:I's 6 minutes (make_path; a slow plane takes path
   handovers: hard rule 54); its weapons off until the lasers' phase.
2. The phases (5 above) in Lua: targets switched on phase by phase (bShowHUDBox / bIsNotLockonTarget / invincibility,
   SPC.V.PART_FLAGS), the TLS lasers, broken-off pieces falling back.
3. The round: a SPC kind, an impact countdown on the HUD; impact = the airfield down for 2 rounds; co-op.

## 10. Its animations, from AC:I's own data (2026-11-22; tools/solg/kfm1.py)
The user: "it's animations have to work, that means it's solar panels falling off too". MOP2 clips are KFM1, now
decoded whole (the kit read only the base pose): 32-byte track records (bone, type 0x0503 position / 0x0704
quaternion xyzw / 0x0001 a value), then the frame count and the (size, offset) of a CONSTANT block and an ANIMATED
block; each block 'cdab', a header of 8 + 8 a track (key count, first frame-number index, values offset), the u16
frame numbers, then the values. The records list the constant tracks first, then the animated ones, in the blocks'
order. [V: the decoded values are rotations of exactly 7.2 degrees a key and positions in metres]
- `auta` on the body's 68-node tree (MOP2 #978, 400 frames): ring auta1 and auta2 turning the opposite ways about the
  barrel, 0.3 degrees a frame each. In. The small `auta` clips (#213-317, 51 keys, a turn in 50 frames) belong to
  o_de01..05, NOT the SOLG's arms (first given to the arms: "The autoloaders are tumbling", the user). Was: the rings' spin, 51
  quaternion keys about the ring bone's local X, 7.2 degrees each: one full turn in 50 frames, a loop. In.
- The solar panels' fall: NOT an animation in AC:I. The mission model has no clip but `basepose` and `auta`; the three
  cutscene packages (DATA01 429 / 431 / 433: Tdemo__<piece>_t1__NN, a world-space track per piece, two cuts each)
  are the SOLG's ARRIVAL: every panel (s_sg04 x6, s_sg05 x12) keeps its exact offset from the body through both cuts
  (tools: a per-cut offset check), only the ring-borne pieces (s_sg06, s_sg01, s_sg02, s_sg07) circle the barrel.
  The 9.8-gravity blocks in the mission graph (DATA92 529) are weapon rounds (speeds 1000-6000, lives), not panels.
  So AC:I's game code breaks the panels off; ours does it with the engine's physics on the panel's own mesh (its wreck
  mesh, tumbling down), said so to the user.

## 11. Its targets, arms and lasers (2026-11-22; Scripts/sv_solg.lua, sv_valka_solg.lua)
- Targets: a unit per type on AC8's generic destructible base (Mission 4's radar tower, ported; the user's yes to the
  base, never a boss): SAW 18, MAG 32, KEW 36, CORE 4, SP 1, held on the SOLG's bones (K2_AttachToComponent, the bone as
  socket), their meshes hidden, their health AC:I's x0.25 at a floor (MinHealth): at the floor the SOLG breaks the
  piece (its wreck shown, a wing falling). Enemy units (Faction 2, TGT mark: the user, "Target boxes have to be enemy");
  their boxes "SOLG" over AC:I's name (their own model row SV_Model_SOLG, NPC rows SV_SOLG_<type>, mission rows
  sv_solg_<type>). Autotest solg2: 13/13.
- Placement checked against AC:I's arrival cutscene (DATA01 429): the 32 MAG panels match; the 36 KEW shells were 11.4
  degrees off (ring 1 had turned in that frame) and lie along their arms now, 9 an arm, 160-480 m out.
- The arms (autoloaders, s_sg01): each carries 8 MAG panels and 9 KEW shells; when the last is down it breaks off
  (the user: "Each of its autoloaders falls off after each has had all of its targets destroyed"): SK_SV_SOLG_ARM (arm
  4 with its pieces' wrecks and lasers in its own frame; the four arms are alike) falls in its place.
- Lasers (AC:I's TLS turrets; decoded by a helper from DATA92 529, tools/solg/lasers.py): model f_111t (crc
  0xef2cd596, a ~15.6 m dome, no wreck mesh), HUD CONT_LASER UNIT, health 850; its type record at graph offset 144736
  (type pointer 0x80023560), the only SOLG type with weapon blocks (offsets 145072 / 145184: ~10 km, ~10 s cycle, one
  shot; a 1.2 km burst-of-20 block). 28 placements (record 56 bytes before each pointer use: +4 position, +16 Euler
  radians Rz@Ry@Rx, +28 name crc): 16 on the arms (4 an arm, in the arm's frame, riding ring 1), 12 round the barrel
  (r 52 m, z 170 .. -868). Phases inferred, not decoded: arms' with the KEW shells (2), barrel's with the core units (3).
  Ours: LSR_01..28 on the rig; target types LSRA (16, phase 2) / LSRB (12, phase 3), optional (no phase waits on them),
  up with their phase, an arm's down with its arm; on AC8's land Phalanx (GR033_ciws_01) firing our own laser
  BP_SV_SolgTLS (a copy of AC8's anti-aircraft swing TLS BP_SwingTLS_ForPlane, damage and SlipDamage 5: the user, "a
  custom blueprint ... damage them for 5 health every hit") through its own arm BP_FCS_SV_SolgTLS (the ships' CIWS arm,
  its weapon swapped, after aircraft within 6 km) and row SV_FCS_SolgTLS (DT_SV_SolgFCS): tools/build_survival_solg.py.
  Autotest solglaser (0.75.8): 16 shots of BP_SV_SolgTLS, no stock laser; a hit took 3.8 health off the test plane
  (5 x the game's own scaling, ~0.76). Beams NOT seen by the user: 0.75.9 hides the Phalanx's meshes alone (not what's
  attached to them); untested.

## 12. The versions' skins (2026-11-22)
Each SOLG package carries a re-skin of the same meshes (its own texture ids; the meshes name the first set's):
DATA01 216 and 219 near the first grey, DATA92 528 near black with red lights. The user: "SOLG -Gould- is the one we
want, the black texture too". prepare.py SKINS['gould'] (matched by size and shape: edges of the grey images, 11 at
0.68-1.00): 20004c40<-200055ff, 20004c3d<-20005600, 200051da<-20005601, 20004c3f<-20005603, 20004c43<-20005605,
20004e4d<-20005606, 20004c3e<-20005607, 20004fa9<-20005608, 20004dae<-20005609, 2000520c<-2000560a,
20004c42<-2000560b. 20005602 / 20005604 (two more wing-panel variants) not placed. Which set is Gould, and its own
phase rules: being decoded.

## 13. SOLG -Gould-'s rules (2026-11-22; decoded by a helper from DATA92 529, the graph's 355 objects and 244 signals)
Gould = DATA92 528 / 529 / 530 (DATA94 entry 3: strings 3841-3843 Schroeter / Oort / Lexell, 3846 Gould; the four
packages DATA01 213 / 216 / 219, DATA92 528 by timestamps and enemy models). Its phase counter V62 (crc 75c5487c):
1 all 34 of V80 (the 18 wings + object 189's 16 MAG panels) + 15 s; 2 the 36 KEW shells + 15 s; 3 eight o_37s1 (+12 s);
4 the FA-45 (+15 s; 18 UAVs with it); 5 the 4 core units + 30 s; then the SP shell. Time limit 360 s (V64). Each wing
row of 3 opens from its third (T7 waits on its neighbour's death signal, objects 171-188); objects 190-193 (4 MAG panels
each, one per arm by their part index 109-142) wait on their arm's 4 of object 189's. An arm (s_sg01) waits for its 9
KEW shells, sheds 8 debris and is removed. Lasers: the arms' 16 fire 10 s at players within 1200 m, then 5 s, from
counter 1; the barrel's tail 4 (objects 333-339) from 1; its front 8 (317-331) sweep at 2, fire from 4.
Ours (the user: "SOLG pieces only", "Follow Gould exactly"): its aircraft phases cut; mag_required (by part index rank),
wing_rows, pause_s 15 / 15 / 30, arm_keys KEW only, LSRA (16, phase 2) / LSRB (barrel tail 4, phase 2) / LSRC (front 8,
phase 3), the laser row 1.2 km, 10 s, 15 s; travel_s 360. Autotest solg2: 16/17 (a test slip, fixed).

## 14. Co-op (2026-11-22; Scripts/sv_solg_coop.lua)
Her round runs on the host; the SOLG's pieces are units, so co-op mirrors them already (each joiner's copies, their hits
"ht" to the host, its health "hp" back). The host's word "vs|<kind>|...": po (its portal), up (the SOLG's course: where,
its velocity, T, its age), ph (a phase), b (a piece broken), dn, hit, vg (VALKA gone / back), st; SCOOP.syncTo gives a
player linking mid-fight the picture. Each joiner draws its own portal and SOLG on the host's course and places its
copies (COOP.groundCopies, in the order they were made) on the bones (SOLG.mirrorUp / adoptTick: the lasers' with the
host's phase); breaks and phases are the host's word (S.mirror: no break on its own, the same wing / arm / laser rules);
each player paid for each piece and the kill (team pay). The lines: SUB.say's "sb"; the airfield: "af".
Tests: coop_guard covers "vs" (19,493 messages, clean); autotest solgjoiner (one PC: COOP.client true only while the
joiner's side is handed the host's words, the copies stood in by units spawned there): 17/17. Two linked games: untested.
