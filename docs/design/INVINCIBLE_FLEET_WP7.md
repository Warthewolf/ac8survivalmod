# INVINCIBLE FLEET, WP7: the fleet's ships, names, formation and course

Research and the first build, 2026-11-12 (night; nobody in game). Read with `docs/design/INVINCIBLE_FLEET.md` (sections 2, 3,
WP7, WP5, WP10) and `docs/design/INVINCIBLE_FLEET_RISE_FORD.md` 1 (the Ford in Survival). Nothing here has run in game yet:
section 5 is the first test.

Tags as in docs/re: [V] read in a file, a dump or seen in game (where), [I] inferred, [?] not known yet.

---------------------------------------------------------------------------------------------------------------------
## 0. In short
- **Survival's world data already holds every class WP7 asks for but the supply ship**: the Ford (Mission 16's, the
  Spaceport's port), the Aegis (Mission 22's allied AC_Unit_01_Ship1), Mission 22's whole enemy fleet (EA_Unit_01_Ship0..3:
  two Udaloys, a Gorshkov, a Kirov and six Grigoroviches, Faction 2 already) and the missile boat (Training006's, the
  Spaceport's port). Mission 22's enemy ships have **never spawned in Survival** (nothing names their units). [V]
- **Built tonight (repo side; no build installed):** 15 one-ship units of THE INVINCIBLE FLEET's own, `SV_Unit_IF<Key>`
  (the Spaceport's units untouched: a build's read-back compares them), 13 named ships on model and NPC rows of their own
  (GEOFON, RAVEN, CONDOR, FINCH, SPARROW, MAGPIE, BELUGA, KOLGA, HERNE, TAISCH, THIASSI, LAZULI, FENRIS) and two unnamed
  missile-boat pickets, the formation (rings round GEOFON), their 15 course lanes (one path each: the run in from 30 km
  north-west of the runway and two laps of the station), each ship's orders and lane as it appears, and **Ctrl+N** (test
  only) to spawn the whole fleet and log it every 10 s. Files: `tools/survival_events_fleet.py`,
  `tools/build_survival_fleet.py`, `Scripts/sv_fleet.lua` (its test-only block), `tools/checks/fleet_test.sh`.
- **The names** use the ZFA-44's proven route (HISTORY 0.74.11): a box's first line is its MODEL row's
  GameObjectDisplayName01, so each named ship has its own copy of its class's model row with only that name changed (a key
  whose text Lua sets), and its own hull row naming that model. The second line is its hull row's GameObjectDisplayName02:
  its class (CARRIER, AEGIS, BATTLECRUISER, DESTROYER, FRIGATE). Proven for an aircraft, not yet for a ship [?].
- **The formation holds exactly** on the run in and through the station's turns: every lane is GEOFON's course *moved* by
  the ship's spot (a translation, not turned with GEOFON's heading), so every lane has the same shape and length and, at
  one speed (45 km/h), every ship keeps its offset. The cost: the formation keeps its compass orientation on the station
  (the pickets lead the way in and trail on the station's back leg).

---------------------------------------------------------------------------------------------------------------------
## 1. What Survival's world data has (research, 2026-11-12)
Read from the stock packages (WD_Mission022_global = Survival's WD before its changes, DT_NPC_Mission022, DT_NPC,
DT_NPC_Model) with a scratch script over tools/build_survival.py's helpers (scratchpad `fleet_research.py`). [V]

### 1.1 The ships per class
| class (AC8) | DT_NPC hull row (model: its box's name, MaxHealth) | Survival's desc now | spawned in Survival? | WP7's use |
|---|---|---|---|---|
| Ford, VE004_grfd | VE004_grfd_01 (VE004_grfd: Aircraftcarrier, 235) | the Spaceport's SV_Unit_SpFord (Mission 16's A_Unit_01_Ship0, ported: RISE_FORD.md 1.1) | yes: the Spaceport (0.73.39, sank and paid), GEOFON's look tests Ctrl+B / Ctrl+G (0.74.63: posed, spawned) [V: HISTORY] | GEOFON |
| Aegis, VE002_aegs | VE002_aegs_01 (VE002_aegs: Aegis, 155) | Mission 22's allied AC_Unit_01_Ship1 (+ AC_Unit_01_Ship2), the Spaceport's 14 copies, the STORE's DDG AEGIS | yes (the Spaceport's, the STORE's) | RAVEN, CONDOR, FINCH, SPARROW, MAGPIE |
| Kirov, VE005_krov | VE005_krov_MS22 (VE005_krov: Battlecruiser, 195) | Mission 22's EA_Unit_01_Ship3 (with two Grigoroviches) | **never** | BELUGA |
| Gorshkov, VE001_gors | VE001_gors_MS22 (VE001_gors: "Aegis", 155) | EA_Unit_01_Ship2 (with two Grigoroviches) | **never** | FENRIS |
| Udaloy, VE007_udal | VE007_udal_MS22 (VE007_udal: Destroyer, 115) | EA_Unit_01_Ship0 and _Ship1 (each with two Grigoroviches) | **never** | KOLGA |
| Grigorovich, VE015_grig | VE015_grig_MS22 (VE015_grig: Frigate, 75) | in every EA_Unit_01_Ship (eight in all) | **never** | HERNE, TAISCH, THIASSI, LAZULI |
| missile boat, VE011_mslb | VE011_mslb_01 (Mslboat, 35) | the Spaceport's SV_Unit_SpBoat<A-H> (Training006's EA_UNIT_2_1) | yes (the Spaceport's, patrolling since 0.73.41) | the pickets |
| container ship, VE021_ctslf | VE021_ctslf_01..03 (Cargoship, 75) | THE ESCORT's SV_Unit_Cargo1/2 (their child is the ZFA-44s' container launcher) | yes (THE ESCORT) | (the supply ship: not built, 4) |
| Mission 22's allied frigate VE016_free | VE016_free_Ally_01 (Frigate, 75) | AC_Unit_01_Ship0 / _Ship3 (allied) | as Mission 22's scenery only | (none) |

DT_NPC also has classes no Survival desc carries: VE017_slav (Cruiser, 135; Mission 13's _MS13 rows), VE018_maya
(Destroyer, 115), VE003_kuzn (Aircraftcarrier, 235), VE009_gunb (Gunboat), VE013_oilt, VE019_lngt, VE020_ctsl (Cargoship,
no parts), VE025_cont. A port of any of them is a new source world data to find first (as the Spaceport's survey did).

### 1.2 Mission 22's enemy fleet (Survival's own world data) [V]
Faction 2, tags TAG_Enemy / TAG_Enemy_Ship, area 10 km, objects with a box (no TGT mark), each ship a stock lane
`01_Ship<N>_<class>_<k>_Path0` (3 points, ControlType 1, westward). Points cm.
| unit | point | ships (object: mission row -> DT_NPC row) |
|---|---|---|
| EA_Unit_01_Ship0 | (683432, 473608, 300) | EA_Obj_01_Ship0_udal_0 (udal_common -> VE007_udal_MS22), _grig_0, _grig_1 (grig_common -> VE015_grig_MS22) |
| EA_Unit_01_Ship1 | (502524, -860430, 300) | _udal_0, _grig_0, _grig_1 |
| EA_Unit_01_Ship2 | (684655, 559433, 300) | EA_Obj_01_Ship2_gors_0 (gors_common -> VE001_gors_MS22), _grig_0, _grig_1 |
| EA_Unit_01_Ship3 | (494936, -945672, 300) | EA_Obj_01_Ship3_krov_0 (krov_common -> VE005_krov_MS22), _grig_0, _grig_1 |

Their parts (the world data's ChildAIObjectDescs: component -> its mission row -> DT_NPC row, fire control):
| class | parts |
|---|---|
| Udaloy | BP_VE007_udal_ak130_01 (udal_ak130 -> VE007_udal_ak130_aagun_MS22, NPC_FCS_VesselAAGun000), BP_VE007_udal_ak130_02 (udal_ak130_artillery -> ..._artillery_MS22, NPC_FCS_VesselMS22Artillery000) |
| Grigorovich | BP_VE015_grig_a190 (grig_a190 -> VE015_grig_a190_MS22, MS22Artillery000), BP_VE015_grig_ak630_01 / _02 (grig_ak630_L / _R -> VE015_grig_ak630_L / R_MS22, NPC_FCS_VesselAAGun006) |
| Gorshkov | BP_VE001_gors_3r14 (VLS: NPC_FCS_VesselVLS3r14), BP_VE001_gors_a192 (MS22Artillery000), BP_VE001_gors_palma_01 (gors_plama_ciws -> VE001_gors_palma_ciws_MS22, NPC_FCS_VesselCIWS000), BP_VE001_gors_palma_02 (gors_plama_aagun -> ..._palma_aagun_MS22, VesselAAGun000) |
| Kirov | BP_VE005_krov_ak130 (krov_ak130 -> VE005_krov_ak130_aagun_MS22, VesselAAGun000) with its grandchild Artillery (krov_ak130_artillery), BP_VE005_krov_kashtan (SAM: NPC_FCS_VesselSAM000), BP_VE005_krov_s300fm (VLS: NPC_FCS_VesselVLSs300fm) |

- The hulls' DT_NPC rows pair ChildNPCId with ChildNPCComponentNames by position, and for the Gorshkov and the Kirov that
  pairing is **not** the world data's (the Gorshkov's palma_01 gets the AA gun row and palma_02 the CIWS row; the Kirov's
  three are rotated). The Spaceport's lesson (0.73.45): parts spawn on the rows their hull's DT_NPC row names. So the
  fleet's copies keep the stock pairing and only rename each child to its fleet copy; what the game does with the pairing
  is the first test's to see [?].
- Their DT_NPC rows also come in _01 (plain), MS25day2, MS26, Training, _MS13 variants; the _MS22 ones were copied.

### 1.3 The names route [V: HISTORY 0.74.11, sv_escort_laser.lua ZLAS.zfaModel, build_survival_rows.py]
- A target box's first line is the MODEL row's GameObjectDisplayName01 (DT_NPC_Model); the NPC row has only 02, the
  second line (the ZFA-44: "ZFA-44" over "VAMPIRE"). Survival's model row copies are in DT_SV_ModelRows; Lua adds them to
  DT_NPC_Model at the main menu, before the NPC rows that name them, and sets the keys' texts with SV_SetText.
- Rows must be in at the main menu, not at the key press: added after the level loads, the spawner made the unit with no
  object in it (the TANICORN's test mount, 0.74.43-0.74.45; TANI.setup since 0.74.46).
- An allied unit's callsign can also come from its desc's GameObjectDisplayNameID02 with bShowCallSignForAlly (VOID
  WATCHER, the co-op stand-ins); an enemy's name has only the model row route.

### 1.4 What each still needs
| ship | still needs |
|---|---|
| GEOFON | WP5 (stages, the V-break), its deck (the Spaceport's deck code on this unit: WP7's carrier-jet mix, AEGIR), WP8 scars, WP13 shelling, WP14 the landing marks; whether a Ford sails a path at all [?: the Spaceport's held its spot] |
| RAVEN | WP9: railguns (the Alicorn's railgun part in a slot, or a mount on a railgun fire control), its EW mast (WP14's source), laser interceptors |
| the Aegis | WP9's laser interceptors; the Spaceport's turret rows they fly already have the fleet's boosted fire control (<FCS>_SVA_Fleet) |
| Mission 22's ships | WP9: fire control of the fleet's own for the ids the Spaceport never cloned (MS22Artillery000, AAGun006, VLS3r14, VLSs300fm, SAM000: tonight they fly their stock ones, short ranges as the Spaceport's first test had), their flak (the AA mounts on the flak fire control, as 0.73.52), laser interceptors; WP8 scars (their materials undumped) |
| the pickets | nothing new (the Spaceport's rows); WP7's 5-6 km ahead: built at 5 km |
| the supply ship | a source: VE020_ctsl (no parts) or VE021_ctslf without its launcher child, from a stock world data not surveyed yet (4) |
| all | pay (WP10, double the Spaceport's), the round (WP10), the names into config/subtitles.ini (WP10: tonight they're CFG.specials.fleet's, test only), co-op health (+50 % a player), presets exempt, the frame rate with the whole fleet up |

---------------------------------------------------------------------------------------------------------------------
## 2. What was built (2026-11-12)
### 2.1 Units and rows (tools/survival_events_fleet.py IF_*, tools/build_survival_fleet.py)
Every ship a one-ship unit made as the Spaceport's ships are: Faction 2, no tags, a TGT mark and a box, never at the
level's start, its area 45 km (the whole course and the airfield), facing the course (UE yaw 45, heading 135), at its
spawn spot 500 m behind its lane's start (hard rule 2). New units even where the Spaceport has the class.
| Key (unit SV_Unit_IF<Key>) | box | class | source | spot (m ahead, m to starboard of GEOFON) | parts (as the records name them, after SV_Obj_IF<Key>_) |
|---|---|---|---|---|---|
| Geofon | GEOFON / CARRIER | ford | Mission 16's A_Unit_01_Ship0 (port_unit; parts by place, Mission 16's _CP_Ally classes as the Spaceport's) | 0, 0 | Mk15LB, Mk15RF, Mk15LF, Mk15RB |
| Raven | RAVEN / AEGIS | aegis | Survival's AC_Unit_01_Ship1 (copy_unit) | 0, 600 | BP_VE002_aegs_mk15_Base, _mk41_Base, _mk45_Base, _mk45_Base_Artillery |
| Condor, Finch, Sparrow, Magpie | <NAME> / AEGIS | aegis | the same | the inner ring, 1.5 km on the diagonals: (1061, 1061), (-1061, 1061), (-1061, -1061), (1061, -1061) | the same |
| Beluga | BELUGA / BATTLECRUISER | krov | EA_Unit_01_Ship3's krov_0 alone (fleet_copy_object) | the outer ring, 3.5 km, dead ahead: (3500, 0) | Gun, Gun_Artillery, Sam, Vls |
| Kolga | KOLGA / DESTROYER | udal | EA_Unit_01_Ship0's udal_0 | (2182, 2736) | Gun, Art |
| Herne, Taisch, Thiassi, Lazuli | <NAME> / FRIGATE | grig | EA_Unit_01_Ship0's grig_0 | (-779, 3412), (-3153, 1519), (-3153, -1519), (-779, -3412) | Art, GunL, GunR |
| Fenris | FENRIS / FRIGATE | gors | EA_Unit_01_Ship2's gors_0 | (2182, -2736) | Vls, Art, PalmaCiws, PalmaGun |
| PicketA, PicketB | the class's (unnamed) | boat | Training006's EA_UNIT_2_1 (port_unit, retag_parts) | (5000, 1000), (5000, -1000) | BP_VE011_mslb_sam |

48 parts, ~63 objects with the hulls (the Spaceport ran ~110 [V: 0.73.39]).
- Rows: DT_SV_ModelRows `SV_Model_Fleet_<Key>` (13: the class's stock model row, GameObjectDisplayName01 = key
  `SV_FleetName_<Key>`); DT_SV_NpcRows `SV_IF_<Key>` (13 hulls: the class's stock hull row, ModelId its model, 02 = key
  `SV_FleetClass_<Class>`, every ChildNPCId the fleet's copy) and `SV_IFF_*` (13 turrets of Mission 22's ships: UdalGun,
  UdalArt, GrigArt, GrigGunL, GrigGunR, GorsVls, GorsArt, GorsPalmaCiws, GorsPalmaGun, KrovGun, KrovArt, KrovSam, KrovVls);
  DT_SV_NpcMission `sv_if_<key>` (13, each shaped as its class's Mission 22 mission row) and `sv_iff_*` (13). The Ford's
  and the Aegis's parts fly the Spaceport's turret rows (SV_Fleet_Mk15Ford<pos>, SV_Fleet_Mk15Aegis ...), the pickets the
  Spaceport's boat rows (sv_sp_boat -> SV_Fleet_BoatHull).
- No new imports (471 in the world data before and after: every class the fleet uses was imported already), so no change
  to the container header (hard rule 7).

### 2.2 The course (survival_events_fleet.py if_course)
- GEOFON starts 30 km north-west of the runway's centre (1610476, -436143): its spawn (-5.46, -25.93) km, its lane from
  (-5.11, -25.57) km. It sails south-east (UE yaw 45, heading 135) 8 km straight, turns 90 deg to starboard (radius 2 km)
  onto the station's far leg 20 km out (the gun line, `IF_SHELL_KM`): 11.1 km, **~15 minutes at 45 km/h**. Then the
  station: a racetrack across the line of approach, the far leg on the gun line and the near leg 16 km out (`IF_HOLD_KM`:
  never nearer), legs 8 km, turns of 2 km to port, **a lap 28.6 km, ~38 minutes**; two laps in the same path (hard rule 54).
  The whole lane 70.1 km, ~94 minutes, 63 points (every 2 km on the straights, every 20 deg on the turns).
- Every lane is GEOFON's course moved by the ship's spot (turned by the course in, then the same for all of it), drawn
  with make_path's smooth tangents and the ship kept level (fleet_path: every point's Up straight up; smooth=True would bank
  a ship up to 50 deg into its turns), ControlType 1 (hard rule 35), on Mission 22's ship lane as the template (the
  Spaceport boats': no tube data, hard rule 34).
- The coast: every lane point at least 3 km from COMONA_MAP.md's 22 land tiles (a build assert); against the terrain grid
  (build/research/comona/height_20m.npy) the nearest land is 6.4 km (PicketA on the station's near end), GEOFON's 11.4 km.
- Records (build_fleet), each ship's on its appearance `SV_IFUp<Key>` and again on Lua's `RE_SV_IFGo<Key>`: the ship and
  its unit on its lane at 45 km/h (1 s on; the STORE's ships' path records, as the Spaceport's boat patrols), Mission 22's
  Normal ship order on the unit (2 s), every part its own Normal / PlayerFirst order (2.5 s). `RE_SV_IFFleetRemove`: every
  unit despawned. 31 triggers, 201 execs.
- The build's read-back (check_fleet_build): every unit, object, part, row, lane point (and its Up) and record, from the
  packages saved; the Lua's ship table, turret rows, key prefixes and course checked against the Python's.

### 2.3 The Lua (Scripts/sv_fleet.lua's test-only block; sv_main.lua and sv_weaponlog.lua, test-only lines)
- `IFLEET.setup` at the main menu (after the allies' setup, which puts the Spaceport's turret rows in on their fire
  control): the 13 model rows, the 13 turret rows (each weapon on the Spaceport fleet's fire control `<FCS>_SVA_Fleet` where
  sv_allies.lua made that clone, else its stock one; the fleet's search module), the Spaceport's rows the fleet names (in
  with the allies; added plain if not), the 13 hull rows, the 13 names and the classes' texts. Any missing: Ctrl+N refuses.
- Ctrl+N (free: tools/README.md's Ctrl keys): the fleet spawned at its course start (my call: each unit's own spot, not
  near the player: a lane is fixed in the world data, so a ship spawned off it would first sail back to its start), 3 ships
  every 0.5 s with spawningUnit set (co-op mirrors them as every spawn), a leftover recycled first; refused outside a run
  and on a co-op joiner. See 5 for its lines. Again: every ship hidden and taken off (SV_Recycle, as Ctrl+B's Ford).
- What fired: sv_weaponlog.lua's launch watch tells the test which object launched (IFLEET.onLaunch: its parts by address,
  checked still the object captured, hard rule 59), and a LiveBullet walk every 2 s finds their guns' shells (the
  Spaceport's turret watch's way, ~40 ms a walk).

---------------------------------------------------------------------------------------------------------------------
## 3. Checks (2026-11-12, in the worktree)
- `python -I -X utf8 tools/build_survival.py`: clean; `invincible fleet: 15 units, 48 parts, 15 lanes, 31 events (201 execs:
  LiveAIEngagementOrder 126, LiveAIPathExecution 60, LiveDestroyUnitExecution 15) and their rows read back from the
  packages: all there`; every other read-back as before.
- Against the build before it: the world data's 380 units and 415 paths, every row of DT_SV_NpcRows / ModelRows /
  NpcMission and the event package's 1825 triggers and 3882 execs unchanged (only additions: 15 units, 15 paths, 26 + 13 +
  26 rows, 31 triggers, 201 execs); every other package byte for byte the same.
- spaceport_test.sh, fleet_test.sh (Ctrl+N's part: 35 checks, 84 in all), weaponlog_test.sh, escort_test.sh, defences_test.sh,
  menu_pages_test.py, ini_check.py, subtitles.py check, lua_check (no new warning), lua_load_test, size_check: pass.

---------------------------------------------------------------------------------------------------------------------
## 4. Not done tonight, and why
- **The supply ship**: no stock desc of a plain cargo hull was found in the world data Survival reads (VE021_ctslf carries
  the ZFA-44s' container launcher as its child); the next survey: VE020_ctsl / VE013_oilt in the stock world data.
- **The builder generalisation** (one builder for the Spaceport and the fleet): the fleet's builder reuses the Spaceport's
  helpers and rows, but its code is its own part; folding the Spaceport's spaceport_units into it would change the
  Spaceport's build (its units must stay as they are), so it waits for a session that can test both.
- **GEOFON's deck, AEGIR, the allies sailing to engage, the names in subtitles.ini, pay**: WP7's later steps / WP10.
- **The weapons' fire control** of Mission 22's classes: WP9 (the ids above).

---------------------------------------------------------------------------------------------------------------------
## 5. The first test (dev install with this build: build_all.sh, package_dev.sh; Ctrl+N in a run)
Log lines (AC8SurvivalMode_lua.log), in order:
1. At the main menu, once: `fleet: rows at the main menu: 13 model rows in DT_NPC_Model, 13 hull rows and 13 turret rows
   in DT_NPC (N weapons on the Spaceport fleet's fire control; on their stock one: NPC_FCS_..., ...; their search
   NPC_AIModule_SV_Fleet), the Spaceport's 12 of 12; 20 names and classes set` (no `MISSING`).
2. Ctrl+N: `fleet: Ctrl+N: 15 ships coming up at their course start, 3 every 0.5 s (...)`, then fifteen
   `fleet: <NAME> (SV_Unit_IF<Key>, <class>): 1 up at its course start; N objects made` (GEOFON 5, an Aegis 5, BELUGA and
   FENRIS 5, KOLGA 3, a Grigorovich 4, a picket 2).
3. Two seconds after each: `fleet: up: GEOFON (SV_Unit_IFGeofon, ford): hull BP_VE004_grfd_CP_Ally at (-5.46, -25.93) km,
   health H; 4 parts: BP_VE004_grfd_mk15_0N_CP_Ally ...; its box: GEOFON / CARRIER` (and one a ship).
4. `fleet: Ctrl+N: 15 of 15 ships up with 48 parts at their course start (GEOFON 30.5 km from the runway, bearing 315 from
   it); GEOFON D km from you, bearing B: fly there`, and the callout `TEST: INVINCIBLE FLEET / 15 SHIPS D KM, BEARING B`.
5. ~15 s after each spawn: `fleet: +T s <NAME> under way (N m from where it came up)`; a ship that isn't:
   `fleet: +T s <NAME> not under way 15 s after its spawn (N m): RE_SV_IFGo<Key> fired (...)`, then under way or
   `... NOT under way ... after RE_SV_IFGo<Key> twice: its lane isn't taken`.
6. Every 10 s: `fleet: +T s GEOFON: (x, y) km, R km from the runway, D km from you, ~45 km/h heading 135, health 100 %, 4 of
   4 parts up`; for each other ship `fleet: +T s RAVEN (aegis): 0.60 km from GEOFON, N m off its spot, ~45 km/h heading
   135, health 100 %, 4 of 4 parts up`; and `fleet: +T s weapons (since the last line): <SHIP> <part class> <weapon> xN;
   <SHIP> <part class> gun; ...; N of 48 parts fired, you D km from GEOFON`.
7. A ship sunk: `fleet: +T s <NAME> sunk (its hull at 0); N of its M parts still up`.
8. Ctrl+N again: `fleet: Ctrl+N at +T s: the fleet taken off: 15 units, N objects hidden, SV_Recycle 1 x15`.

What to look at (fly to the bearing given, ~30 km north-west of the airfield): the rings round GEOFON (RAVEN beside it, the
four Aegis on the diagonals, the seven of the outer ring, the two pickets ahead), every box's name (GEOFON over CARRIER,
RAVEN over AEGIS, BELUGA over BATTLECRUISER ...), red with the TGT mark; the ships sailing south-east together at the same
speed, level (no heel), the formation holding (each `off its spot` under ~100 m), and turning onto the station after ~15
minutes; which turrets fire at you as you close (the weapons lines). Pass: all 15 up with their parts, named, under way,
in formation for the run in.

---------------------------------------------------------------------------------------------------------------------
## 6. Risks and unknowns for that test
| what | why it may not work | what then |
|---|---|---|
| Mission 22's ships as one-ship units | never spawned in Survival; copied out of three-ship units | the up lines say which came up with how many parts; the pairing quirk (1.2) may put a part on another's row |
| a ship's name on its box | the model row route is proven for an aircraft only | the box keeps the class's name: try the desc's GameObjectDisplayNameID02 (bShowCallSignForAlly is an ally's) |
| GEOFON on a path | the Spaceport's Ford never had one (it held its spot) | `not under way` twice: its lane isn't taken by the Ford's class; a sailing hull of another class as the fleet's centre, or the Ford moved by a rig |
| 45 km/h for every class | the path record's speed; a class may have its own top speed [?] | the off-its-spot lines grow: per-class speeds in the records |
| the turrets firing | Mission 22's on their stock fire control (short ranges); a hull's order doesn't reach them, so each part has its own | the weapons lines say which: WP9's clones |
| the frame rate | 15 ships, ~63 objects, 15 paths of 63 points | the perf line's Lua tick with the fleet up (the Spaceport's ~110 objects ran) |
