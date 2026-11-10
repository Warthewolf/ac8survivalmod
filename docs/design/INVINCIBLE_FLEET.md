# INVINCIBLE FLEET: implementation plan (round 30)

Written 2026-11-09 / 2026-11-10 from the user's design and decisions. Nothing of it is built yet. This file is meant
to be handed to an implementing agent (Fable 5.2, or any agent) as its brief: it says what to build, in what order,
on what Survival already runs, how each piece is tested, and what isn't known yet. Keep it up to date as work lands
(each work package's status line, section 4).

Tags as in docs/re: [V] read in a file or seen in game (where), [I] inferred, [?] not known yet.

---------------------------------------------------------------------------------------------------------------------
## 1. For the implementing agent: read this first

### 1.1 Read before any work
1. `AGENTS.md` whole (project rules, the 62 hard rules, the runtime layout, how the agents share work). It overrides
   anything here that disagrees.
2. This file whole.
3. The notes each work package names, at least: `docs/re/TANICORN.md` (the boss: ship assembly, moving parts, weapon
   mounts), `docs/re/SPACEPORT_ASSAULT.md` (the enemy fleet Survival already spawns: the Ford, Aegis, Wasps, missile
   boats, their parts' orders, pay, the deck), `docs/re/ALICORN.md` (a submarine boss: dive / surface, railguns,
   phases), `docs/re/STORE_FREEZE.md`, `docs/re/LASER_INTERCEPTOR.md` and `docs/re/ZFA44.md` (AC7's laser, the box
   name route), `docs/re/AIRCRAFT_MATERIALS.md` and `docs/re/FALKEN_MATERIALS.md` (AC8's materials),
   `docs/re/COMONA_MAP.md` (coordinates), `docs/re/SPECIAL_ROUNDS.md` (how specials are made).
4. The newest entries at the end of `HISTORY.md` (grep it for a feature; never load it whole).

### 1.2 What a cloud session can and can't do
- Can: edit Lua (`mod/UE4SS/AC8SurvivalMode/Scripts/sv_*.lua`), the Python generators (`tools/*.py`), the native
  runtime's C (`runtime/`), docs; run the Lua checks and tests (`python -X utf8 tools/checks/lua_check.py
  mod/UE4SS/AC8SurvivalMode/Scripts/*.lua`, `sh tools/checks/<name>_test.sh`, `python -X utf8
  tools/checks/size_check.py`). On Linux `tools/checks/lua_build.sh` fails to link (no `-lm`): build the test Lua by
  hand: `cd build/checks/luasrc/lua-5.4.6/src && clang -O2 -w -DLUA_USE_LINUX -o ../../../lua.exe $(ls *.c | grep -v
  '^luac\.c$') -lm -ldl` (after one lua_build.sh run has fetched the source).
- Can't (the user's Windows machine only, paths in `.env`): the game, UE 5.4 cooking (`tools/tanicorn/build.sh`,
  tools/laser7, tools/x02s), Blender, ACE8 Aircraft Builder dumps (`dev obj|mesh|sockets|skeleton`), `tools/build_all.sh`
  (it reads the stock game files), packaging (`tools/package_dev.sh`, `tools/package_release.sh`). Write those steps
  as exact instructions for the user, and ask the user for the dumps a step needs.
- Every in-game test is the user's. Give each one: the build to install, the key to press, what to look at, the log
  lines that prove it (UE4SS.log, AC8SurvivalMode.log, AC8SurvivalMode_lua.log, the crumbs), and the pass line.

### 1.3 Rules this work runs into most (AGENTS.md has the full text)
| rule | why it matters here |
|---|---|
| 2, 35, 54 | ship paths: start a little ahead, ControlType 1, smooth; a ship's whole course in the one path started at its appearance |
| 7, 31, 32, 34 | new units: imports and the container header; port_unit / copy rules; TGT and boxes; no object references in copied descs |
| 16, 0.74.48 | a unit spawns again only once off the phase's list; **never take a unit off the list while child objects of it are alive** (Shazzy's STORE crash: HISTORY 0.74.48) |
| 17 | FName numeric tails in flags, events and rows |
| 23, size_check | at most 200 locals per Lua part; no source file over 2,000 lines (split by family: AGENTS.md "Runtime layout") |
| 25 | native Lua function names at most 15 characters |
| 26 | an event record's conditions are checked when it fires: fire timed steps from Lua as remote events |
| 36, 40 | check what a copied fire record was for (scripted sure kills); WN_WEAPON_n = fire-control slot n-1 |
| 38, 45 | Online Mode parts can go on campaign ships; railgun minimap / RAILGUN WARNING |
| 39 | Lua can't move a flying AI actor smoothly: motion must be the game's own (paths, curves, animations) |
| 41, 46 | wreck meshes don't draw on a live object (put materials on its own mesh); a component added at run time draws |
| 42, 44, 58 | our cooked assets VERSIONED; no virtual textures of ours; no new master materials or shaders of ours (AC8's or stub-parented instances only) |
| 47 | `local ok, v = x and pcall(f)` keeps one value |
| 56, 61 | (if the rise touches the sky) the sky asset rules |
| 59 | an object kept between ticks must still have the name it was captured with before anything is done to it |
| licence | no other mod's files; AC7 assets only under the user's exceptions (the laser); never AC7 or AC04 voice lines; Sea Power's Iowa: the user's dev install only |

### 1.4 How work is recorded
- Before each build the user gets: `python -I tools/bump_version.py` (a new version every build). After it: a new
  entry at the END of `HISTORY.md` (what changed, the log lines, the test checklist), never in AGENTS.md.
- A lesson a test confirms becomes a hard rule in AGENTS.md.
- Commits `[claude] what changed` (or the agent's own tag), with the session's attribution lines; push only to the
  branch the session was given.
- Each work package below gets its log lines (`fleet: ...`, `tanicorn: ...`, `ford: ...`), its settings in
  CFG.specials.fleet / survival.ini [specials.fleet] (players edit values without a rebuild), and its test-only keys
  inside TEST ONLY blocks (tools/strip_test_only.py drops them from a release).

---------------------------------------------------------------------------------------------------------------------
## 2. The user's decisions
2026-11-09:
- The special is called **INVINCIBLE FLEET**, after Ace Combat 04's Mission 06 (section 7).
- Order of work: **(1) the TANICORN fully working, (2) a damage model for AC8's Ford-class carrier and the Tanicorn's
  rise out of it, (3) the rest of the fleet around them.**
- The Tanicorn hides under the carrier. When the carrier is destroyed, it **rises out of the ocean bow first to the
  sky, then crashes down onto the waves, then opens fire on the players and becomes targetable**.
- The fleet's weapons: **flak, laser interceptors, VLS missiles, railguns**.
- (docs/re/TANICORN.md 0) The Tanicorn's hull is AC8's submarine class; it rises once and never dives again; its
  weapons fire stock projectiles; our blueprints go straight onto the native classes.

2026-11-10:
- **Round 30**, a fixed slot: `CFG.specials.schedule.rounds[30] = "fleet"` (as round 2's shuttle, 6's escort, 9's
  fishing).
- **The carrier falls only when the players sink it** (no timer, no escape run).
- **Every ship must be sunk**: the round is won only with the Tanicorn and the whole fleet down.
- **The Tanicorn rises between the Ford's two halves** (the Ford's wreck breaks in two and the halves part).
- **Every ship carries its name** on its target box.
- **The Tanicorn model goes in first**: before the round reaches friends' builds the Tanicorn is a model of our own
  geometry (not the Iowa); the round never ships without its boss.
- **The fleet sails towards Comona from the north-west.**
- **Every ship shows its damage textures at all times, except the Tanicorn** (a battle-scarred fleet from the moment
  it appears; the Tanicorn pristine).

Still open: section 6.

---------------------------------------------------------------------------------------------------------------------
## 3. The round, as a player sees it (round 30)
1. **Round 29's break:** callout `INVINCIBLE FLEET` / `THE AEGIR FLEET IS UNDER WAY`, the NEXT row
   `FLEET: n SHIPS  CARRIER: GEOFON`. Radio: Survival's own lines in config/subtitles.ini (never AC7 or AC04 voice).
2. **Phase 1, the fleet:** it appears over the north-west horizon in formation, battle-scarred, each ship named on its
   box, and sails south-east towards Comona. Its screen fires flak and VLS missiles; laser interceptors burn down
   missiles fired at the ships they cover; the RAVEN's railguns (RAILGUN WARNING) reach far out; the carrier's deck
   launches fighters. The round's own fighters are fewer (the fleet is the threat). Ships paid as sunk, turrets as
   shot off (the Spaceport's pay).
3. **Phase 2, the carrier falls, only to the players:** as GEOFON is hit, its damage stages show (fires, smoke, a
   list). At 0 it breaks at midships and the halves drift apart. Between them the sea erupts: the TANICORN's bow
   breaks the surface, the hull climbs bow first into the sky, hangs, and falls back flat onto the waves (spray, a
   shock ring, camera shake). Nothing fires at it and nothing can lock it during the rise.
4. **Phase 3, the Tanicorn:** it opens fire as it settles, then becomes targetable (boxes, TGT marks, the boss bar).
   Its weapon parts first, its core last (its phases). The ships still afloat fight on with it.
5. **The end:** won when **every ship is sunk** (the Tanicorn and the whole fleet, in any order) and the round's
   aircraft are down: `THE AEGIR FLEET IS DESTROYED`, the big reward. The NEXT row counts what's left
   (`FLEET: n AFLOAT`). The players choose when to wake the boss: sink the screen first and the carrier last, or the
   carrier early and the Tanicorn with the fleet still round it.

---------------------------------------------------------------------------------------------------------------------
## 4. Work packages
Each package: goal, depends on, where, steps ([repo] = a cloud session can do it, [machine] = the user's Windows
machine), test in game, pass, fallback, unknowns. Do them in this order unless a package says it can run alongside.
Status lines: update them as work lands.

### WP0. The Tanicorn's own model
Status: not started. Depends on: nothing. Who models it: section 6, question 5.
- Goal: the Tanicorn's hull and every mount type in our own geometry (the Iowa's may stay in the user's dev install
  only), after the chosen design `art/tanicorn/design/Leviathan_rev4.blend` (650 m: the Alicorn's length; Alicorn-grey
  upper works; the bow railcannon in its teal bay; faired sponsons). The Alicorn's parts are AC8 stock and allowed.
- Deliverables, rigged as tools/tanicorn expects (tools/tanicorn/README.md, prepare_part.py): the hull (static mesh,
  its mount sockets named as the parts' components will attach), each mount type (16-inch triple, 5-inch twin, CIWS /
  laser, VLS block, the bow railcannon with its raise and barrel split) as Body > turret_yaw > turret_pitch with
  identity bones and muzzle sockets (SOC_Gun_01.. as the stock spelling), each with its wreck; textures ordinary (no
  VT: hard rule 44) on AC8 material instances parented on stubs (hard rules 42, 58).
- Also: a one-piece skinned version of the whole ship with a root bone for the rise (WP4 route B), and its rise
  animation (WP4).
- Test: renders for the user; then WP1's mount test with the new mount.
- Pass: the user approves the look; tools/tanicorn's pipeline takes the files unchanged.

### WP1. The Tanicorn's mounts work (milestone M0b)
Status: milestone 0 done (0.74.43-0.74.47: the 5-inch BP_SV_Tani_T5 loads with its fire control and spawns from
Survival's rows; Ctrl+T in a test build). Not seen: aiming, firing, hits, wreck. Depends on: nothing (WP0 alongside).
- Steps: [user test] Ctrl+T: the T5 aims (its `tanicorn: ... yaw / pitch` log values move as you fly round it),
  fires flak, takes hits, swaps to its wreck. If it never turns: bone names, SlotSocketPrefix or sockets
  (TANICORN.md open questions). Then one mount type at a time on the same route [machine build, repo Lua]:
  - the **16-inch triple, railgun shells**: LiveFCSModule_LauncherTripleRailCannon + weapon BP_wp_eml_ldbs01
    (GR036's land battleship), three pitch bones as GR037's or one pitch bone with three muzzles [?], the minimap
    and RAILGUN WARNING (hard rule 45);
  - **CIWS / laser**: an anti-missile arm of ours with BP_SwingTLS_ForMSL's values, or AC7's LaserInterceptor on
    ALiveLaserInterceptor as the ZFA-44s carry it (proven: hard rule 58, 0.74.31);
  - **VLS**: cells = sockets up to SlotNum (the Alicorn's vls1..vls8, the Aegis Mk 41's SOC_Vls_01..08); the fleet's
    EXSAM homing (HISTORY 0.73.52-53).
- Pass: each mount type aims, fires its stock projectile, takes hits and wrecks, on its own, from a test key.

### WP2. The Tanicorn's hull (M1)
Status: not started. Depends on: WP0 (the hull), WP1 (its mounts).
- First proof needed: **a static mesh with sockets of ours** loads and draws in AC8 (TANICORN.md 4: never done).
- Steps: our BP of the hull on AC8's submarine class (ALiveAISubmarine; ALiveAIVessels if the submarine needs
  Alicorn-style data our BP lacks: TANICORN.md 0, 1) [machine: TaniBuild]; its parts as LiveChildActorComponents on
  its sockets; world data with child AI objects (hard rule 7: every class imported, the container header too; the
  copy in the data folder); DT_NPC ChildNPCId / ChildNPCComponentNames paired by component name, part health from
  each part's model row (TANICORN.md 1) [repo: tools/build_survival_units.py, survival_events_specials.py, rows];
  spawned through SV_Spawn from a test key.
- Pass: the whole ship draws on the sea, every mount on its socket, each part boxed with its own health.
- Fallback: the hull as a skeletal mesh (VALKA's X-02S route, proven).

### WP3. The Tanicorn fights (M2)
Status: not started. Depends on: WP2.
- Every part ordered by name a moment after it appears (a hull's order never reaches its turrets: the Spaceport's
  0.73.40 lesson; Mission 16's Normal / PlayerFirst order), each weapon firing its stock projectile, health tuned for
  1-4 players (the Alicorn's are an online squad's). Phases come in WP11.
- Pass: it fights a player for a whole test without help, every weapon type seen in the weapons log.

### WP4. The rise, on its own
Status: not started. Depends on: WP2 (route A) or WP0's one-piece mesh (route B). Test it from a key with no fleet.
- What: from under the sea, bow first to the sky, hang, fall flat, settle; untargetable throughout; then fire, then
  targetable. Lua can't move it (250 ms tick, hard rule 39): the motion must be the game's.
- **Route A, the submarine's own surface with our curves:** ALiveSubmarineBase surfaces along
  CUR_Surface{Location,Rotation}Curve between UnderWaterLocation and OnWaterLocation (the Alicorn's: 56 m down) and
  Survival already dives and surfaces the Alicorn (RE_SV_AlcnDive / RE_SV_AlcnSurface: LiveSubmarineOperation)
  [V: ALICORN.md 1.3, survival_events_specials.py]. If the curves are offsets or an alpha that can overshoot [?], our
  BP's curves (pitch 0 -> ~60 deg, height far past the water, back to 0 with a hard stop) make the AI hull do it all.
  One test answers it: our curves on the WP2 hull, surfaced by the record.
- **Route B, a stand-in:** the one-piece skinned Tanicorn with a root bone and its rise as one AnimSequence (~12 s:
  under -> bow out -> ~60 deg up, the bow ~550 m above the sea -> falls -> flat with a bounce -> still), played natively
  (AnimationSingleNode) on a SkeletalMeshComponent added to the hidden AI hull at run time (hard rule 46). At its end
  the stand-in hides and the real hull, already on the water at the spot, is shown.
- Effects: AC8's own (the Alicorn's NS_ex03_alcn_surfacing0x, splashes; AKE_BA002_alcn_Surface_Play) as AnimNotifies
  (data, no BP script) [?: cooked notifies play: test on the T5's wreck first], else fired from Lua at the times.
- Untargetable -> fire -> targetable: hull and parts switched off as sv_escort.lua's offObj does (no box, no lock-on,
  invincible, hidden) or held under water; at the slam switched on (sv_escort_laser.lua onObj), every part's order
  sent (fire first), then a moment later boxes and TGT marks on. Each step a remote event fired from Lua (hard
  rule 26). The event focus camera on it for the rise (hard rule 28) and a callout.
- Pass: the rise looks right from 3-8 km (no culling, no water clipping), nothing can lock it until it's down, it
  fires before it's targetable, no hitch.

### WP5. The Ford's damage model (GEOFON)
Status: not started. Depends on: nothing (alongside WP1-WP4).
- Known [V: SPACEPORT_ASSAULT.md]: the Ford is VE004_grfd (Mission 16's allied Grindylow, A_Unit_01_Ship0, four Mk 15
  parts BP_VE004_grfd_mk15_01..04; enemy rows VE004_grfd_01 + VE004_grfd_mk15_{RF,LF,RB,LB}_01). Survival spawns it as
  an enemy in the Spaceport Assault (SV_Unit_SpFord) with its deck launching fighters; it sank in the user's test.
- Research first [machine dump, user]: ACE8 Aircraft Builder `dev obj` of BP_VE004_grfd_CP and its Base: meshes (a
  _DAM?), DamagedStateComponent stages, DamageEffects sockets, destroy system and params (campaign vessels:
  LiveDefaultDestroySystemExtraEffect + BP_Vessel_BodyDestroyParam: mesh swap, sinking, FinalExplosionTime 80, the
  Aegis's); its materials (WP8 step 1).
- Build: our blueprint `BP_SV_grfd` on AC8's native vessel class with the stock BP's values copied from its dump (the
  TaniBuild route: never a child of the stock BP, never the stock package overridden), in Survival's own container:
  - damage stages while afloat: DamagedStateComponent ChangeMesh stages (e.g. 66 % and 33 %: scorched deck, a
    blackened island) and DamageEffects on new sockets (deck fires, island smoke, a list); its always-on scars (WP8)
    under them;
  - its death: a skeletal wreck (the Alicorn's DestroyedBodyMesh + MainBodyDestructionDelayTime pattern) made in
    Blender from the Ford's own mesh (`dev mesh`), cut at midships: two halves, torn edges, AC8's _DAM materials; one
    death sequence (~20 s): secondary explosions along the deck, the keel breaks, **the halves drift apart along the
    keel line** (bow half forward, stern half back) to a gap of ~150 m (the Tanicorn's beam ~80 m [I: the Iowa's
    33 m at 650 m]), then both go under; AC8's own Niagara and Wwise as AnimNotifies or from Lua;
  - its deck launches stay the Spaceport's (SPORT's deck: a pool flight with a pose off its bow), stopping at its
    death.
- Pass: shot to 66 / 33 % its stages show; at 0 it breaks, the gap opens, both halves sink; no crash in a STORE after
  it (0.74.48's rule: none of its child objects alive under a recycled unit).

### WP6. The rise between the halves
Status: not started. Depends on: WP4, WP5.
- The trigger: Lua sees GEOFON's hull die (the Spaceport's hull watch: SPORT.shipObjs) and starts the rise a fixed
  time into its death sequence, once the gap is open. (Native alternative: LiveDefaultDestroySystemSpawnFromWD, which
  spawns world-data objects by name at a dying piece's socket: Mission 19's rockets [V: SPACEPORT_ASSAULT.md].)
- Where: the Tanicorn comes up in the gap, **set across the Ford's keel** (yaw 90 deg off the wreck's), so it falls
  flat across open water beside the halves, never onto them; the halves are under before it lands.
- When it spawns: the fleet is under way (WP7), so a Tanicorn waiting under the Ford would have to follow it at depth
  [?: a submarine on the Ford's path]. Simpler: spawned at the Ford's death, deep and switched off at the wreck's spot,
  during the ~20 s death sequence. Measure its spawn time (its parts) and the hitch; follow the Ford only if needed.
- Pass: in a test (Ford alone + Tanicorn, a key): sink the Ford; the Tanicorn rises from the gap, falls beside the
  wreck, fires, becomes targetable.

### WP7. The fleet: ships, names, course
Status: not started. Depends on: nothing for the ships (alongside); WP5 for GEOFON.
- **Composition** (a first draft; every count a setting, as the Spaceport's; ~16 ships + the Tanicorn to start, and
  measure: the Spaceport's 27 ships / ~110 objects ran [V: 0.73.39]):

  | AC04 ship | Survival's (AC8 asset) | role | weapons |
  |---|---|---|---|
  | Tanager (flagship) | THE TANICORN (ours, WP0-WP4) | the boss, rises from GEOFON's wreck | 16-inch railgun shells, 5-inch flak, CIWS / lasers, VLS, the bow railcannon |
  | Geofon (carrier) | GEOFON: the Ford VE004_grfd, WP5 | the centre, deck launches | its four Mk 15s as flak / CIWS, laser interceptors |
  | Raven (Aegis cruiser) | RAVEN: Aegis VE002_aegs | the carrier's guard, long range | Mk 41 VLS, Mk 45 flak, railguns |
  | Condor, Magpie, Sparrow, Finch | Aegis VE002_aegs | inner ring | Mk 41 VLS, Mk 45 flak, Mk 15 CIWS |
  | Beluga, Fenris, Kolga, Lazuli | Mission 22's enemy fleet hulls (Kirov, Udaloy, Gorshkov, Grigorovich) [?] | outer screen | their SAMs and guns (flak), laser interceptors |
  | Herne, Taisch, Thiassi | Grigorovich class [?] | screen | flak, SAM |
  | missile boats | VE011_mslb | pickets | SAM (the Spaceport's patrol) |
  | supply / container ship | VE021_ctslf | the train | none (or a Stinger mount) |
  | Beowulf-Nu / Pi | no stock enemy submarine found [?] | optional | - |

  Mission 22's enemy fleet is in Survival's world data already (EA_Unit_01_Ship0..3: udaloy + 2 grigorovich,
  gorshkov + 2 grigorovich, kirov + grigorovich, Faction 2) [V: SPECIAL_ROUNDS.md 3]; their parts, rows and whether
  they've ever spawned in Survival [?]: research first.
- **Builder:** generalise the Spaceport's (survival_events.py sp_fleet, build_survival.py spaceport_units /
  build_survival_world.py: one-ship units, Faction 2, no tags, TGT and a box, every part's own order by name 2.5 s after
  its ship appears, SPORT.shipObjs's hull watch, pay by kind, parts finished off when the hull sinks) so both specials
  call one builder; keep the Spaceport's names and its spaceport_test passing.
- **Names (the user: every ship named):** a box's first line is the MODEL row's GameObjectDisplayName01 (DT_NPC_Model;
  the NPC row has only 02), found for the ZFA-44 (HISTORY 0.74.11; sv_escort_laser.lua ZLAS.zfaModel adds Survival's
  copy of a model row with its own name at the main menu, before the NPC rows naming it). Each named ship: its own
  model row copy (SV_Model_Fleet_<Name> on its class's stock model row, only the name changed) and its own NPC row:
  GEOFON, RAVEN, CONDOR, MAGPIE, SPARROW, FINCH, BELUGA, FENRIS, KOLGA, LAZULI, HERNE, TAISCH, THIASSI; the Tanicorn's
  (section 6). The names also in config/subtitles.ini with the speaker names (players edit them). Unnamed ships keep
  their class's name. [?: whether a part's box shows its ship's name.]
- **Course (the user: from the north-west towards Comona):** the combat zone is 80 x 80 km centred on (-707, -262) km
  (north = -Y, east = +X: COMONA_MAP.md 1), its north-west corner about (-47, -42) km. The fleet appears ~5 km inside
  it at about (-40, -35) km and sails south-east (UE yaw ~53 deg, heading ~143) towards the spaceport island (pad
  (-13.25, +0.60) km), ~45 km [I: the marks to set in a test flight]. Every ship on its own lane parallel to GEOFON's,
  offset to its formation spot, all at one speed so the formation holds (make_path lanes, ControlType 1, smooth, the
  whole course in the path started at its appearance: hard rules 2, 35, 54). At ~30-40 km/h a 15-minute fight covers
  7-10 km [I]. Near the coast: section 6, question 2. The Tanicorn doesn't follow the course: it fights from where it
  lands [?: its own path or holding its spot].
- Pass: the fleet appears NW in formation, named, sails SE holding formation; every turret fires; sinking works and
  pays; the frame rate and the perf line's Lua tick with the whole fleet up.

### WP8. The fleet's damage textures at all times (not the Tanicorn)
Status: not started. Depends on: WP7 (its ships); WP5 for GEOFON's own BP (route B there).
- **Goal (the user, 2026-11-10):** every ship of the fleet (hull, superstructure and turret parts) shows its damage
  textures from the moment it spawns and for the whole round, whatever its health; **the Tanicorn never** (it stays
  pristine). No other unit in Survival changes (the STORE's allied DDG AEGIS, the Spaceport's fleet, the carriers).
- What's known:
  - hard rule 41: an AI object's wreck meshes don't draw while it lives: put damaged materials on its own mesh;
  - a run-time route already in Survival: AB.L..IN's "dead look" (Scripts/sv_anomalies.lua glitchDeadLook, 2026-10-23):
    for each material slot of each body component, the slot's asset found by its path (walking a run-time copy's
    Parent chain up to the asset), its `<name>_DAM` instance loaded beside it and set with SetMaterial(i, dam), a
    common burnt material where none exists; logged `special: <name>'s dead look: N of M material slots burnt` [V:
    code; whether the look was right in game: not recorded];
  - AC8's vehicle master MP_Live_Vehicle_Base_UDIM carries a damage layer (Charred_*, Blend_Damaged_*,
    T_Aircraft_Dam_Level_D / _N) and the aircraft skins expose PlayerPlane_Damage, DamegedNormal_Intencity,
    DNormal_Strength scalars (the player plane's progressive damage) [V: AIRCRAFT_MATERIALS.md 1, FALKEN_MATERIALS.md
    2.4]; whether ships' materials sit on the same master [?];
  - dynamic material instances work from Lua (kml:CreateDynamicMaterialInstance / comp:CreateDynamicMaterialInstance,
    SetScalarParameterValue, SetMaterial: sv_zfa44.lua, sv_anomalies_valka.lua, NIGHT_SEA_LIGHTS.md), and 1,500-2,000
    SetMaterial calls in one tick hitch the game: spread them [V: NIGHT_SEA_LIGHTS.md].
- **Step 1, research** [machine dumps + a Lua probe, user test]: for each fleet class (VE004_grfd and its Mk 15s,
  VE002_aegs + mk15 / mk41 / mk45 / artillery, Mission 22's hulls, VE011_mslb + sam, VE021_ctslf): every mesh
  component and its material slots, each material's parent chain to its master, the master's parameter names (from the
  master package's name map, as AIRCRAFT_MATERIALS.md advises), whether a `<name>_DAM` instance exists, and **what the
  game itself does as a ship takes damage** (a test-only Lua probe: log a stock Aegis's slot materials and their damage
  scalars every second while the user shoots it, and at its DamagedState stages). That decides the route.
- **Step 2, the route** (one shared Lua helper, e.g. `SCARS.apply(obj, mode)` in a new part `sv_fleet_scars.lua`;
  AB.L..IN's code moved into it and called by both):
  - **Route M (preferred, if the master has a damage scalar):** a dynamic instance of the slot's own material with
    the damage scalar(s) at a battle-scarred level (setting `level`, 0..1): the ship keeps its paint with damage
    blended over it. If step 1's probe shows the game writing that scalar as the ship takes hits, ours must hold: a
    floor (max of ours and the game's) written after the game's, each tick for the fleet's ships, or found where the
    game writes it.
  - **Route D (proven pattern):** each slot swapped to its `_DAM` instance (glitchDeadLook's): the wreck's charred
    look, darker than M. Use where M has nothing to drive.
  - **Route B (our own BPs: GEOFON's BP_SV_grfd, and any fleet BP we cook):** the damaged look baked into the live
    mesh's material instances at cook time (instances on the stubbed master with the damage parameters set): no
    run-time work.
- **Step 3, where and when** [repo]:
  - on each fleet object as it spawns (the fleet's spawn capture, as SPORT.shipObjs records a ship's objects), every
    mesh component of it: static and skeletal, the hull, bridge, the turrets' TurretPoseableMesh;
  - spread over ticks (setting `per_tick`, e.g. 40 slots a tick), with the object checked still the one captured
    (hard rule 59: its name) before each write;
  - again after anything that replaces a component's materials: a DamagedStateComponent ChangeMesh stage (a new mesh
    brings its default materials), WP5's stages, a component the game rebuilds; watched, not assumed (re-enforced as
    the ammo caps are: hard rule 19's lesson);
  - a ship's death: its own destroy system swaps to its wreck: left as the game does it;
  - co-op: cosmetic and local: each game scars its own copies of the fleet (by unit name), nothing sent;
  - **never the Tanicorn**: its units and parts skipped by name (setting `skip`), and never any unit that isn't the
    fleet's.
- Settings: `CFG.specials.fleet.scars = { enabled = true, mode = "auto" (M, else D), level = 0.7, per_tick = 40,
  skip = { "SV_Unit_Tani" } }`, mirrored in survival.ini [specials.fleet.scars]. A look-only setting: it goes in the
  leaderboard's free lists (AGENTS.md "Leaderboard": LB.edited ignores it).
- Log lines: `fleet: scars: <unit> (<name>): N of M slots (<route>, level L)`, `fleet: scars: <unit>: K slots
  re-applied (<why>)`, `fleet: scars: the Tanicorn skipped`.
- Test key (test only): scars on / off for every fleet ship up, to compare.
- Pass: screenshots: every fleet ship scarred from its spawn, the Tanicorn clean, nothing else changed; still scarred
  after hits, its damage stages, a STORE visit and a co-op join; no hitch at the fleet's spawn (the perf line).
- Unknowns: the master and its parameters (step 1); whether the game writes the damage scalar; whether
  TurretPoseableMesh takes SetMaterial like any mesh component [I: yes, it's a MeshComponent].

### WP9. The fleet's weapons
Status: partly there. Depends on: WP7.
- **Flak:** done for the fleet's AA mounts (NPC_FCS_VesselAAGun* on a clone of the ground flak gun's fire control,
  boosted: HISTORY 0.73.52-53). The Tanicorn's 5-inch mounts on the same.
- **VLS missiles:** the Aegis Mk 41 and the Ladon / Alicorn VLS with the fleet's EXSAM homing and salvos
  (missile.homing_from, salvo_n 3). Never a scripted sure kill (hard rule 36).
- **Laser interceptors:** each covers the ships near it and burns down missiles fired at them, so players kill the
  laser mounts first or close in with guns and bombs. AC7's LaserInterceptor on ALiveLaserInterceptor, spawned and
  attached at a ship's socket as on the ZFA-44s (fired and intercepted: 0.74.31) [V], or an AC8 anti-missile arm of
  ours (BP_SwingTLS_ForMSL's values) on the Tanicorn's CIWS mounts. A turn rate / cool-down that leaves skilled missile
  play possible; a callout `LASER DEFENCE ONLINE`; its beam AC8's NS_UAVTLS_Muzzleflash01 (hard rule 58).
- **Railguns:** the Tanicorn's 16-inch triples (WP1) and the RAVEN's: the Alicorn's railgun part (ALiveAIRailgun) in
  the ship's ChildNPCId (hard rule 38's Arsenal Bird pods on the Ladon are the precedent) [?], or a mount swapped to a
  railgun fire control as the flak swap does (only where its MeshComponentName and SlotSocketPrefix exist on the part:
  TANICORN.md 3). Minimap and RAILGUN WARNING by hard rule 45; telegraphed (the Alicorn's railgun tells) and survivable.
- Pass: the weapons log sees each type fire; a player can survive a railgun with the warning; missiles still kill
  ships once their lasers are down.

### WP10. The round
Status: not started. Depends on: WP7 (and WP6 for phase 3).
- A new SPC.kinds entry `fleet` in a new part `Scripts/sv_fleet.lua` (its own family if it grows past 2,000 lines),
  with the Spaceport's hooks (ready / busy / over / row, fighter_share), CFG.specials.fleet and survival.ini
  [specials.fleet] for every count, price and timing; `CFG.specials.schedule.rounds[30] = "fleet"`. Round 30 is in the
  late rounds (P8: +3 aircraft a round from 26), so cut its own fighters (fighter_share).
- Phases: 1 the fleet (WP7, WP9), 2 GEOFON's fall (WP5, WP6), 3 the Tanicorn (WP3, WP11); won when every ship and the
  round's aircraft are down. Pay by kind and per turret; the boss's reward. Callouts and radio lines (subtitles.ini).
  The NEXT row (`FLEET: n SHIPS  CARRIER: GEOFON`, then `FLEET: n AFLOAT`).
- The airfield: the clocks wait while you're down with nobody else flying (the Spaceport's I6). Removals by remote
  event; never a unit off the list while its parts are up (0.74.48).
- Tests without the game: `tools/checks/fleet_test.sh` (as spaceport_test.sh: spawn, pay, phases, the rise's event
  order, the win condition, co-op messages, the scars' skip list), the build's read-back checks for every new row
  and class.
- Pass: a whole round 30 played: the fleet, GEOFON's fall, the rise, the Tanicorn, every ship sunk, the reward.

### WP11. The Tanicorn's moving parts, phases and death (M3-M5)
Status: not started. Depends on: WP3.
- M3: the bow railcannon's raise and barrel split, the sub-railgun hatches: one AnimSequence each, played natively
  (ULiveAISimpleAnimationComponent + LiveAISimpleAnimationPlayExecution, or hatch parts as the Alicorn's / Grifn's);
  no animation blueprints (BP script).
- M4: weak points as child objects with their own health and tags (no separate weak-point system), the core shielded
  until they're down, phases fired from Lua (sv_alicorn.lua's pattern: poll part health, fire SV_Event), the boss
  bar, callouts.
- M5: its own destroyed mesh (a skeletal wreck with a sinking sequence: the Alicorn's SK_BA002_alcn_DAM pattern),
  DamageEffects on sockets, AC8's Niagara and sounds only.

### WP12. Co-op, load, the STORE, release
Status: not started. Depends on: everything above.
- Every spawn through SV_Spawn with spawningUnit set (mirrored, ships and parts linked by key as the Spaceport's and
  the Alicorn's), every RE_SV_Fleet* and rise event forwarded, the rise played on every game from the host's time.
  The scars are local (WP8).
- The perf line with the whole fleet and the Tanicorn up; the STORE's freeze and restore over every object of theirs
  (docs/re/STORE_FREEZE.md); 0.74.48's rule.
- Release: round 30's fleet in dev builds only until WP0's own Tanicorn is in (section 2); then into friends' zips
  (`BUILD_NAME=COOP2MP COOP=1 sh tools/package_release.sh online <version>`, registered on the leaderboard).

---------------------------------------------------------------------------------------------------------------------
## 5. Risks
| risk | what answers it | fallback |
|---|---|---|
| a static mesh with sockets of ours (the 650 m hull) won't load or draw | WP2's first test | the hull as a skeletal mesh (VALKA's route) |
| ALiveAISubmarine needs Alicorn data our BP lacks | WP2 | ALiveAIVessels + route B's rise |
| the surface curves can't overshoot | WP4 route A's test | route B |
| cooked AnimNotifies don't play | the T5 wreck test | effects fired from Lua at the sequence's times |
| a 650 m object leaving the water reads badly (water, culling at height) | WP4's test | a lower climb, more spray |
| the ships' materials have no damage scalar, or the game overwrites it | WP8 step 1 | route D (_DAM swap) |
| SetMaterial on ~16 ships' slots hitches | WP8's per_tick | fewer slots a tick, the hull first |
| laser interceptors make missiles useless | WP9 balance | fewer, slower, killable first |
| ~16-20 ships + the boss cost too much frame time | the perf line | fewer ships, parts merged |
| the Iowa geometry can't ship | WP0 | (decided: our own model first) |
| a unit with child objects recycled under them crashes the STORE | 0.74.48's rule | (rule: never) |

---------------------------------------------------------------------------------------------------------------------
## 6. Questions still open for the user
1. How high does the Tanicorn climb before it falls? (Draft: ~60 deg nose up, its bow ~550 m above the sea.)
2. What happens if the fleet gets close to Comona: it holds a station off the coast, its railguns and VLS shell the
   airfield / spaceport, or nothing (a normal fight ends ~35 km out)?
3. The Tanicorn's name on its box: TANICORN, TANAGER, or another?
4. Once a run at round 30, or does the fleet come back later in a run (60, 90 ...)?
5. Who models the Tanicorn's own geometry (WP0): the user in Blender from Leviathan_rev4, or the agent building it in
   scripted Blender from the design and the Alicorn's AC8 parts, the user reviewing renders?
6. The scars' strength (WP8 `level`): lightly weathered, or heavily burnt? Do the fleet's turrets get them too, or only
   the hulls?

---------------------------------------------------------------------------------------------------------------------
## 7. Reference: AC04's Aegir Fleet
- Ace Combat 04 Mission 06 "Invincible Fleet" (Operation Rough Seas, 23 November 2004): ISAF's surprise strike on the
  Erusean **Aegir Fleet**, "the invincible armada", at anchor in Comberth Harbor; most of it sunk at anchor. The
  flagship, the Iowa-class battleship **Tanager** (Captain Matias Torres, later "the Hero of Comberth Harbor" for saving
  his crew), and the carrier **Geofon** got out of the harbour and were caught before open water; the Tanager sank
  outside the harbour mouth. Points in a 15-minute limit; the briefing warns the operation is long and the player may
  need to resupply.
- The fleet: battleship Tanager (3 main guns), carrier Geofon (launches a KA-25), Aegis cruiser **Raven** (2 SAMs),
  cruisers **Beluga, Fenris, Kolga, Lazuli** (a SAM and an AA gun each), destroyers **Herne, Taisch, Thiassi**,
  submarines **Beowulf-Nu, Beowulf-Pi** (+ five unnamed), missile boats, landing ships, a supply ship, container ships;
  F/A-18s, F-14s and Tornados over it, an F-14 ace "Levy". AC04's audio names four Aegis never seen: **Condor, Magpie,
  Sparrow, Finch**.
- What Survival takes: the names, the shape (a carrier group round a flagship), a fleet that's dangerous to approach,
  and the Tanager's "what if": the battleship that didn't sink (the TANICORN). Survival is on Comona, not Comberth.
- Sources (read 2026-11-09): https://acecombat.wiki.gg/wiki/Aegir_Fleet, https://acecombat.wiki.gg/wiki/Invincible_Fleet,
  https://acecombat.wiki.gg/wiki/Tanager
