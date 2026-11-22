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
