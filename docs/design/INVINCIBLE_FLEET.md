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
| 57 | the music: only 2D events are heard (Online Mode's versions), the player's list at most 120 tracks |
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

2026-11-10, the last open questions ("your draft is fine" for the rest):
- **The rise:** the draft stands: ~60 deg nose up, its bow ~550 m above the sea, then flat onto the waves.
- **Near Comona the fleet shells the airfield** (WP13).
- **The boss's name on its box: TANACORN** (the user's spelling; the project's files, code and docs keep the name
  TANICORN: only the on-screen name is TANACORN).
- **Once a run, at round 30** (never drawn at random, never again later in the run).
- **The agent builds all of it**, the Tanicorn's own model included (WP0): no part is left to the user but the tests
  in game and the builds on the machine.
- The scars: the draft stands (WP8: `level` 0.7, hulls, superstructures and turrets).

The user's answers to the agent's questions, 2026-11-10:
- **Length:** 15-20 minutes for one player, start to finish (the gun line at ~13 minutes, so a quick team is never
  shelled).
- **Fleet size:** ~16 ships besides the TANACORN (the draft: every AC04 name once).
- **Laser interceptors: strong but killable:** most missiles fired at a covered ship are shot down, each laser with a
  cool-down; kill the laser mounts first or close in with guns and bombs. **Their swing 0.5 s**, the ZFA-44s' too
  (one setting, `li_intercept_s`; was AC7's 1.0): built in 0.74.49.
- **The rise: a short cinematic**: the view leaves the player's plane for an outside shot of the rise, then comes back;
  the player is invulnerable during it. **In co-op every player's view cuts to it at the same moment**, all invulnerable.
- **Reward:** ~50,000 zollars for the win, on top of each ship's own pay.
- **GEOFON's deck launches a mix of every carrier jet**, picked at random each launch: F-14D, F/A-18E/F, F/A-18C, Su-33,
  F-35C, Rafale M (rows f14d_common, f18e_common, f18c_common, su33_common, f35c_common, rflm_common).
- **An ace squadron, AEGIR:** a 4-ship of **F-14Ds** (AC04's ace Levy flew one), **off GEOFON's deck at the round's
  start**.
- **Sky:** whatever the day-night arc gives (no change).
- **The TANACORN: 3 phases:** (1) its guns, VLS and lasers; (2) once enough are down, the bow railcannon rises and
  charges; (3) its core opens: sink it.
- **Its bow railcannon shoots at the airfield**: a charged shot that takes a big piece of the airfield's health (kill
  it, or the core, before it fires).
- **Its death:** secondary explosions along the hull, then it breaks up and goes under (the Alicorn's wreck's way).
- **Co-op:** +50 % health per extra player (4 players: 2.5x); the fleet's size stays the same.
- **Music:** AC8's "Invincible Fleet" (Online Mode's AC04 track, `AKE_Bgm_Online_ACE04_Invincible_Fleet_Play`, 265.8 s)
  on loop from the round's start until the TANACORN rises, then AC8's "Invincible Fleet INFINITY Remix"
  (`AKE_Bgm_Online_ACEINF_Invincible_Fleet_INFINITY_Remix_Play`, 300.1 s) on loop until it dies. **AC8 tracks only**: the
  user's first choice, AC7's "Hero of Comberth Harbor" (AC7's Anchorhead Raid DLC), isn't in AC8, and the user chose
  not to bring AC7 music in (no new AC7 exception).
- **Radio and subtitle lines:** the agent drafts them in config/subtitles.ini with Survival's own speakers; the user
  and friends edit them there.
- **Airfield down from the shelling:** the usual rule (landing and the STORE close until the round after next; the run
  goes on).

GEOFON's capture (the user's idea, 2026-11-10: "a capture for the geofon, only for coop: it will select a random player
and take over their aircraft and force land it onto the geofon"), and the answers the same day (WP14):
- **Co-op only.** A random player is chosen.
- **A warning and a chance to escape:** a ~10 s CAPTURE LOCK on the chosen player first; it's broken by destroying its
  source or by getting far enough away. **The source is RAVEN's EW mast** (the user, 2026-11-10: "Use RAVEN's EW mast as
  the source instead").
- **The landing: fully scripted**: the plane flown in and set down on GEOFON's moving deck frame by frame (not a fade).
- **Captured = dead:** once on the deck the player dies and can be revived by co-op's revive (the STORE's REVIVE).
- **GEOFON sunk with a player being captured:** the captive goes down with it (downed, revivable as any).

The third round of questions, 2026-11-10:
- **No time limit:** the round lasts until every ship is down (the shelling and the railcannon are the pressure; every
  player down ends the run as always).
- **Radio voices:** COMONA CONTROL / TOWER (the friendly side), KASKA (the intercepted enemy channel), CHARLENE and her
  escorts (YORKE, ROCK, ALI, DANIELLE: when the VAMPIRES / her flight are around, else on the radio from the airfield),
  AUDREY and VALKA. No new speaker.
- **The round's own fighters: a few:** about a quarter of a normal round 30's aircraft, besides AEGIR and the deck.
- **The win also repairs the airfield fully:** its health, its defences and the allies, as well as the 50,000.
- **The TANACORN's own fight: about 8 minutes** for one player, from the rise to its sinking (~2-3 minutes a phase).
- **Captures:** the draft stands: first 2 minutes in, then every 3 minutes while RAVEN's mast and GEOFON are up, any
  player, never the same one twice within 5 minutes.
- **Difficulty presets: no change**: round 30 is the same on Casual, Standard and Ace (its values are exempt from the
  preset's multipliers).
- **RAVEN's EW mast also jams players near RAVEN** (the Alicorn jammer's own effect), one more reason to kill it first.
- **Ship pay: double the Spaceport's:** GEOFON 6,000, RAVEN and the Aegis 1,600, cruisers 1,400, destroyers 1,000,
  missile boats 600, the supply ship 1,000 [I: its own], a turret 300.
- **Formation: rings round GEOFON:** RAVEN beside it, the four Aegis an inner ring, the cruisers and destroyers an outer
  ring, the missile boats out front as pickets, the supply ship inside the outer ring astern.
- **The TANACORN's look: the Leviathan design** (rev4): Alicorn-grey upper works, the Alicorn's hull colour, the teal
  railcannon bay; pristine.
- **The players' allies sail and fly to engage the fleet:** the STORE's ships (the DDG AEGIS and the rest) head for it,
  the wingmen join the attack.

**The TANACORN's weapons (the user, 2026-11-10: "it only has 2 main guns now"; the rest the agent's proposals the user
left as they were):**

| weapon | count | where (the Leviathan design) | fires at | phase |
|---|---|---|---|---|
| bow railcannon (the Alicorn's) | 1 | its teal bay in the bow, where the Iowa's turret A stood | the airfield: a 30 s charge, again every 90 s while it lives | 2 |
| 16-inch triple turret, railgun shells | **2** | turret B forward of the bridge, turret C aft | the players, and the airfield from the gun line (WP13) | 1 |
| 5-inch twin flak mount | 6 | three a side along the superstructure | the players | 1 |
| close-in mounts | 8: **4 laser interceptors** (0.5 s swing) + **4 CIWS guns** | the superstructure's corners | lasers: the players' missiles; CIWS: the players | 1 |
| VLS block, 8 cells | 4 (32 cells) | the Alicorn's VLS, two a side | the players | 1 |
| sub-railgun (the Alicorn's) | 2 | its pop-up hatches, one a side | the players | 1 |
| SAM launchers | none | | | |
| launched aircraft / drones | none (GEOFON's deck does the launching) | | | |

Phase 1's weapon parts: 2 + 6 + 8 + 4 + 2 = **22**; phase 2 when `phase2_share` (60 %) of them are down. The design file
in the repo (Leviathan_rev4.blend) still holds three 16-inch turret objects (one presumably hidden under the bay: the
renders show two) and **4 CIWS positions** (the Iowa's Phalanx): WP0 adds 4 more close-in positions for the 8.

No question is open (section 6).

---------------------------------------------------------------------------------------------------------------------
## 3. The round, as a player sees it (round 30)
1. **Round 29's break:** callout `INVINCIBLE FLEET` / `THE AEGIR FLEET IS UNDER WAY`, the NEXT row
   `FLEET: n SHIPS  CARRIER: GEOFON  AIRFIELD IN RANGE: mm:ss`. Radio: Survival's own lines in config/subtitles.ini,
   from COMONA CONTROL / TOWER, KASKA's intercepted channel, CHARLENE and her escorts, AUDREY and VALKA (never AC7 or
   AC04 voice).
   The round's music starts: "Invincible Fleet", on loop.
2. **Phase 1, the fleet:** it appears over the north-west horizon in formation, battle-scarred, each ship named on its
   box, and sails south-east towards Comona's airfield. If it reaches its gun line (~13 minutes, AC04's 15-minute
   limit in another form) it starts **shelling the airfield** and holds station there (WP13). Its screen fires flak
   and VLS missiles; laser interceptors burn down
   missiles fired at the ships they cover; the RAVEN's railguns (RAILGUN WARNING) reach far out; the AEGIR squadron
   (four F-14D aces) launches off GEOFON's deck at once, and the deck goes on launching a mix of carrier jets. The
   round's own fighters are a few (a quarter of a normal round 30's). RAVEN's EW mast jams players near it. Ships paid
   as sunk, turrets as shot off (double the Spaceport's pay). The players' allies (the STORE's ships, the wingmen) sail
   and fly out to engage it.
   In co-op, GEOFON tries to **capture** a player now and then (WP14): a CAPTURE LOCK from RAVEN's EW mast on
   someone, who escapes by killing the mast or running; if not, their plane is taken over and landed on GEOFON's deck, and they die there
   (revivable).
3. **Phase 2, the carrier falls, only to the players:** as GEOFON is hit, its damage stages show (fires, smoke, a
   list). At 0 it breaks at midships and the halves drift apart. Between them the sea erupts: the TANICORN's bow
   breaks the surface, the hull climbs bow first into the sky, hangs, and falls back flat onto the waves (spray, a
   shock ring, camera shake), seen in a **short cinematic** (every player's view at once, everyone invulnerable).
   Nothing fires at it and nothing can lock it during the rise. The music turns to "Invincible Fleet INFINITY
   Remix", on loop until it dies.
4. **Phase 3, the TANACORN:** it opens fire as it settles, then becomes targetable (boxes, TGT marks, the boss bar:
   `TANACORN`). Its own three phases: its guns, VLS and lasers; then its bow railcannon rises and charges a shot **at
   the airfield** (a big piece of its health: stop it); then its core opens. It sails on towards the airfield's gun line
   and shells it from there too; the ships still afloat fight on with it. It dies breaking up under secondary
   explosions.
5. **The end:** won when **every ship is sunk** (the TANACORN and the whole fleet, in any order) and the round's
   aircraft are down: `THE AEGIR FLEET IS DESTROYED`, ~50,000 zollars, and the airfield fully repaired (its health,
   defences and allies). There's no time limit. One player should need 15-20 minutes, about 8 of them on the TANACORN. The NEXT row counts what's left
   (`FLEET: n AFLOAT`). The players choose when to wake the boss: sink the screen first and the carrier last, or the
   carrier early and the Tanicorn with the fleet still round it.

---------------------------------------------------------------------------------------------------------------------
## 4. Work packages
Each package: goal, depends on, where, steps ([repo] = a cloud session can do it, [machine] = the user's Windows
machine), test in game, pass, fallback, unknowns. Do them in this order unless a package says it can run alongside.
Status lines: update them as work lands.

### WP0. The Tanicorn's own model
Status: not started. Depends on: nothing. Who: the agent (the user, 2026-11-10: "You are building it all").
- Goal: the Tanicorn's hull and every mount type in our own geometry (the Iowa's may stay in the user's dev install
  only), after the chosen design `art/tanicorn/design/Leviathan_rev4.blend` (650 m: the Alicorn's length; Alicorn-grey
  upper works; the Alicorn's hull colour; the bow railcannon in its teal bay; faired sponsons; pristine: the user
  confirmed this look, 2026-11-10). The Alicorn's parts are AC8 stock and allowed.
- Deliverables, rigged as tools/tanicorn expects (tools/tanicorn/README.md, prepare_part.py): the hull (static mesh,
  its mount sockets named as the parts' components will attach: **2** 16-inch, 6 five-inch, 8 close-in, 4 VLS, 2
  sub-railgun hatches, the bow railcannon's bay: section 2's table), each mount type (16-inch triple, 5-inch twin, CIWS /
  laser, VLS block, the sub-railgun with its hatch, the bow railcannon with its raise and barrel split) as Body > turret_yaw > turret_pitch with
  identity bones and muzzle sockets (SOC_Gun_01.. as the stock spelling), each with its wreck; textures ordinary (no
  VT: hard rule 44) on AC8 material instances parented on stubs (hard rules 42, 58).
- Also: a one-piece skinned version of the whole ship with a root bone for the rise (WP4 route B), and its rise
  animation (WP4).
- **How the agent builds it:** scripted Blender (Python), never hand edits it can't repeat: a script under
  `tools/tanicorn/` (e.g. `model_hull.py`, `model_mounts.py`) that builds the hull from lofted cross-sections and the
  superstructure, mounts and details from parametric parts, in metres at the Alicorn's 650 m, UV-unwrapped for
  ordinary textures, and writes the .blend and the glTFs prepare_part.py takes. The Leviathan_rev4 design and its
  renders (`art/tanicorn/renders/leviathan/`) are the **visual reference only**: no vertex, mesh or texture of the
  Iowa is copied, traced or imported into the new model (it must be shippable). The Alicorn's parts (railcannon,
  sponsons, VLS hatches) may be used as AC8 stock exports.
- **Where Blender runs:** try Blender as a Python module in the cloud session first (`pip install bpy`: Blender's
  official wheel on PyPI, which the session's network allows; it needs the Python version that wheel is built for,
  ~400 MB of disk) to build and render there and send the renders to the user (SendUserFile); else the script runs
  on the user's machine (Blender 3.3: keep the script to the API both versions share) and the user sends the renders.
- **Texturing:** procedural in the script or baked there (panel lines, AC8 grey, the teal bay), written as ordinary
  PNGs (no VT: hard rule 44); materials as AC8 instances on stubs (tools/tanicorn ue_import.py's route).
- Test: renders for the user (the whole ship from four sides and close-ups of each mount type), then WP1's mount test
  with a mount of the new model.
- Pass: the user approves the look; tools/tanicorn's pipeline takes the files unchanged; nothing of the Iowa in them
  (the script's sources are its own code and AC8's exports only).

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
  rule 26).
- **The short cinematic (the user's choice):** the view leaves the player's plane for an outside shot of the rise
  (~12 s), then returns; the player's plane invulnerable meanwhile (its invincible flag / a health floor, back after
  it [?: which holds on a player plane]); in co-op every game cuts at the same moment (the host's start time, as the
  rise). Routes, in order:
  1. AC8's in-game camera node, `LivePlayInGameCameraExecution` (camera name, unit): the "impact" outside shots stock
     missions play on Mission 16's Ladons (ImpactCamera_ms16*) and Mission 19's rocket (ImpactCamera_ms19-01/02), named
     in /Game/Blueprints/InGameCamera/BP_InGameCameraParameter (generic ImpactCamera_Common / _Random / _Front / _Back /
     _Side) [V: docs/re/MUSIC_RADIO_CAMERA.md D]. Not in Mission 22's EP: its class import added from Mission 04's record
     (hard rule 7). Played on the TANACORN's unit (or a dummy at the wreck) as the rise starts; trigger type 28 fires
     after it ends. [?: how long it holds, and whether it frames a 650 m ship]
  2. Lua: a CameraActor (or a CameraComponent on a dummy) beside the wreck and the player controller's
     SetViewTargetWithBlend onto it, then back to the pawn: the spectator camera already sets the view target this way
     (sv_down.lua: a CameraComponent added to another player's plane) [V: code].
  3. The event focus camera (`LiveEventFocusCameraExecution`, Mission 22's RE_ShuttleFocusCamera pair: the view
     swings to it, the player keeps control; hard rule 28) as the fallback.
  A callout with it (`THE TANACORN RISES`).
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
    death; each launch's airframe picked at random from the carrier jets (WP7);
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
  | Raven (Aegis cruiser) | RAVEN: Aegis VE002_aegs | the carrier's guard, long range; the capture's source (WP14) | Mk 41 VLS, Mk 45 flak, railguns, its EW mast |
  | Condor, Magpie, Sparrow, Finch | Aegis VE002_aegs | inner ring | Mk 41 VLS, Mk 45 flak, Mk 15 CIWS |
  | Beluga, Fenris, Kolga, Lazuli | Mission 22's enemy fleet hulls (Kirov, Udaloy, Gorshkov, Grigorovich) [?] | outer screen | their SAMs and guns (flak), laser interceptors |
  | Herne, Taisch, Thiassi | Grigorovich class [?] | screen | flak, SAM |
  | missile boats | VE011_mslb | pickets | SAM (the Spaceport's patrol) |
  | supply / container ship | VE021_ctslf | the train | none (or a Stinger mount) |
  | Beowulf-Nu / Pi | no stock enemy submarine found [?] | optional | - |

  Mission 22's enemy fleet is in Survival's world data already (EA_Unit_01_Ship0..3: udaloy + 2 grigorovich,
  gorshkov + 2 grigorovich, kirov + grigorovich, Faction 2) [V: SPECIAL_ROUNDS.md 3]; their parts, rows and whether
  they've ever spawned in Survival [?]: research first.
- **Formation (the user: rings round GEOFON):** RAVEN beside GEOFON (~600 m off its beam: it sails with it, so the
  capture's 12 km escape is from both), the four Aegis an inner ring (~1.5 km), the cruisers and destroyers an outer
  ring (~3.5 km), the missile boats 5-6 km ahead as pickets, the supply ship inside the outer ring astern. Each ship's
  spot an offset from GEOFON in GEOFON's frame, its lane GEOFON's course shifted by it (5.2's lanes), so the rings hold
  as they sail and the station's racetrack keeps them (the racetrack's turns: the outer ring's lanes are longer; give
  each its speed so they stay abreast, or let the rings loosen on the turns) [I: distances to set from a test].
- **The players' allies (the user: sail / fly to engage):** at round 30's start the STORE's allied ships (the DDG AEGIS
  and the rest of sv_allies.lua's ships) are sent towards the fleet on lanes built from their spots to the fleet's
  course (make_path at build time: one per ally ship spot, started by a remote event; hard rules 2, 35), their
  engagement order Normal so they fire at the fleet [?: an allied ship's turrets on enemy ships], and the wingmen
  (the STORE's) ordered onto the fleet's ships and its fighters (their unit area onto the fleet, as the chase moves
  enemies'). After the round they go back to their stations (their own lanes back) [?: or stay where they are].
- **Builder:** generalise the Spaceport's (survival_events.py sp_fleet, build_survival.py spaceport_units /
  build_survival_world.py: one-ship units, Faction 2, no tags, TGT and a box, every part's own order by name 2.5 s after
  its ship appears, SPORT.shipObjs's hull watch, pay by kind, parts finished off when the hull sinks) so both specials
  call one builder; keep the Spaceport's names and its spaceport_test passing.
- **Names (the user: every ship named):** a box's first line is the MODEL row's GameObjectDisplayName01 (DT_NPC_Model;
  the NPC row has only 02), found for the ZFA-44 (HISTORY 0.74.11; sv_escort_laser.lua ZLAS.zfaModel adds Survival's
  copy of a model row with its own name at the main menu, before the NPC rows naming it). Each named ship: its own
  model row copy (SV_Model_Fleet_<Name> on its class's stock model row, only the name changed) and its own NPC row:
  GEOFON, RAVEN, CONDOR, MAGPIE, SPARROW, FINCH, BELUGA, FENRIS, KOLGA, LAZULI, HERNE, TAISCH, THIASSI, and the boss's
  **TANACORN** (the user's spelling; on screen only). The names also in config/subtitles.ini with the speaker names (players edit them). Unnamed ships keep
  their class's name. [?: whether a part's box shows its ship's name.]
- **Course (the user: from the north-west towards Comona; near it, it shells the airfield):** north = -Y, east = +X
  (COMONA_MAP.md 1); the combat zone is 80 x 80 km centred on (-707, -262) km, the airfield's runway centre
  (1610476, -436143) cm. The fleet appears ~30 km north-west of the airfield, about (-5, -26) km [I: open sea, 20 km
  north of the island chain: check on the minimap], and sails south-east (UE yaw ~45 deg, heading ~135) towards the
  airfield. At its gun line, `shell_km` (20 km) from the runway, it starts shelling (WP13) and slows to a station:
  a slow racetrack `hold_km` (16 km) off the runway, never nearer the coast. Every ship on its own lane parallel to
  GEOFON's, offset to its formation spot, all at one speed (`speed_kmh` 45) so the formation holds (make_path lanes,
  ControlType 1, smooth, the whole course and the station's laps in the one path started at its appearance: hard
  rules 2, 35, 54). 10 km to the gun line at 45 km/h: ~13 minutes [I], the round's soft clock (the NEXT row's
  `AIRFIELD IN RANGE`). The Tanicorn, once risen, takes its own path from where it lands along the fleet's course to
  the same station (one path from its landing, at the fleet's speed) [?: a submarine-class hull sailing a path:
  the Alicorn does].
- **GEOFON's deck (the user: a mix of every carrier jet):** each launch's airframe picked at random from F-14D,
  F/A-18E/F, F/A-18C, Su-33, F-35C and Rafale M (f14d_common, f18e_common, f18c_common, su33_common, f35c_common,
  rflm_common: rows CFG already names), set on the pool flight at its spawn (SV_SetAircraft: the airframe and AI
  module; its behaviour stays its flight's: hard rule 20).
- **The AEGIR squadron (the user: a 4-ship of F-14D aces off GEOFON's deck at the round's start):** an ace flight as the
  ace-squadron specials make theirs (sv_ai.lua ACE: an ace row at the top level, its own name on the boxes, its moves:
  hard rules 37, 22), named AEGIR 1-4 (subtitles.ini), launched off the deck as the fleet appears; paid as aces. Its
  airframe f14d_common [?: the F-14D's ace row and its post-stall moves: the CFG maneuvers list has no f14d].
- Pass: the fleet appears NW of the airfield in formation, named, sails SE holding formation, reaches its station and
  laps it; AEGIR launches at once and the deck's mix after it; every turret fires; sinking works and pays; the frame rate and the perf line's Lua tick with the whole
  fleet up.

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
- **Laser interceptors (the user: strong but killable):** each covers the ships near it and burns down **most**
  missiles fired at them (a cool-down after each kill, setting `cooldown_s`), so players kill the laser mounts first or
  close in with guns and bombs. **A 0.5 s swing** (the user, 2026-11-10: "up the swing speed for the laser
  interceptors"; both the fleet's and the ZFA-44s', one setting): the fleet's lasers take the ZFA-44s' `li_intercept_s`
  (0.5 since 0.74.49) and the same curve fit (docs/re/LASER_INTERCEPTOR.md 11). AC7's LaserInterceptor on ALiveLaserInterceptor, spawned and
  attached at a ship's socket as on the ZFA-44s (fired and intercepted: 0.74.31) [V], or an AC8 anti-missile arm of
  ours (BP_SwingTLS_ForMSL's values) on the Tanicorn's CIWS mounts. A turn rate / cool-down that leaves skilled missile
  play possible; a callout `LASER DEFENCE ONLINE`; its beam AC8's NS_UAVTLS_Muzzleflash01 (hard rule 58).
- **RAVEN's EW mast jams (the user):** players within its range get the Alicorn jammer's own effect (BP_wp_ecm_ON: the
  game's HUD jamming, missiles less reliable) while the mast is up [?: the jammer part's effect on players when it's on
  a campaign ship: ALICORN.md 1.2's `ecm` is a phase-3 weapon of the Alicorn's; test it on RAVEN]. If it doesn't work
  that way, the mast's own jamming is left out (the capture still works) and noted.
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
  [specials.fleet] for every count, price and timing; `CFG.specials.schedule.rounds[30] = "fleet"`, **once a run**: the
  kind is not in CFG.specials.rotation and never drawn at random (as THE ESCORT and GONE FISHIN' are once a run).
  Round 30 is in the late rounds (P8: +3 aircraft a round from 26): its own fighters are **a few** (the user):
  `fighter_share` 0.25 of a normal round 30's aircraft, besides AEGIR and the deck.
- **No time limit** (the user): the round ends only when every ship and its aircraft are down; every player down ends
  the run as in any round.
- **Presets: no change** (the user): round 30's health, lasers, shelling and capture values are the same on Casual,
  Standard and Ace: the fleet's units and the TANACORN exempt from the preset's multipliers (find where TIER / the
  preset scales enemy health and damage: sv_config_ini.lua's preset, and skip the fleet's units there) [?: which
  multipliers reach ships].
- Phases: 1 the fleet (WP7, WP9), 2 GEOFON's fall (WP5, WP6), 3 the Tanicorn (WP3, WP11); won when every ship and the
  round's aircraft are down. **Pay (the user: double the Spaceport's):** GEOFON 6,000, RAVEN and the Aegis 1,600, the
  cruisers 1,400, the destroyers 1,000, the missile boats 600, the supply ship 1,000, a turret 300; the win's
  `reward` 50,000 **and the airfield fully repaired** (the user): AF back to its full health, its defences and the
  allies repaired (sv_rounds.lua's between-rounds repair, ALLY.repairAll, at the win), callout `AIRFIELD RESTORED`.
- **Radio (the user):** the agent drafts the lines into config/subtitles.ini (`python -I tools/subtitles.py merge`
  after adding the Lua lists), the user edits them; never AC7 or AC04 voice. Speakers: COMONA CONTROL / TOWER (the
  warning, the gun line, the shelling, the airfield down or restored, the win), KASKA's intercepted channel (the
  fleet's side: the sailing, GEOFON's fall, the rise), CHARLENE and her escorts YORKE / ROCK / ALI / DANIELLE (their
  reactions; the VAMPIRES' pilots when up), AUDREY and VALKA (the rise, the TANACORN, the win). Each moment its own
  list: the warning, the fleet sighted, the gun line, a capture lock / broken / captured, GEOFON at half, GEOFON down,
  the rise, each TANACORN phase, the railcannon charging / fired / destroyed, the win.
- **Pacing:** one player 15-20 minutes start to finish, **about 8 of them on the TANACORN** (~2-3 minutes a phase) (the
  user); the fleet's health, the TANACORN's and the gun line (`shell_km`, `speed_kmh`) tuned to that from the tests; co-op +50 % health per extra player (`coop_health_x` 0.5:
  ships, parts and the TANACORN), the fleet's size the same.
- **Music (the user):** `AKE_Bgm_Online_ACE04_Invincible_Fleet_Play` on loop from the round's start until the rise,
  then `AKE_Bgm_Online_ACEINF_Invincible_Fleet_INFINITY_Remix_Play` on loop until the TANACORN dies (then the music
  player as after any special). Both are Online Mode's 2D versions, heard in Survival (hard rule 57: 0.74.31 played
  them; the lobby jukebox's 3D ones are silent). Looped by Survival's own music control (sv_music.lua; the track
  lengths 265,832 / 300,113 ms are in its table: start it again as it ends; hard rule 57's "a looping event is given 60
  s, not -1" for the music player's own lists). The round holds the music player as the specials do ("BGM held by
  Survival").
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
- M4, **three phases (the user)**, fired from Lua (sv_alicorn.lua's pattern: poll part health, fire SV_Event), with
  the boss bar and callouts:
  1. its 22 weapon parts fight (section 2's table: two 16-inch triples, six 5-inch, four lasers, four CIWS, four VLS
     blocks, two sub-railguns); the core shielded (invincible / no box);
  2. once `phase2_share` (60 %) of those parts are down, the bow railcannon rises (M3's animation) and charges a
     shot **at the airfield** (the user): a `railcannon_charge_s` (30 s) charge with the RAILGUN WARNING and a callout
     (`THE TANACORN IS AIMING AT THE AIRFIELD`); if it fires, `railcannon_damage` (e.g. 100 of the airfield's 250) comes
     off the airfield (WP13's scripted route: AF.pending, effects on the runway); the railcannon itself is a part that
     can be killed before it fires, and it charges again `railcannon_every_s` (90 s) later while it lives;
  3. once the railcannon is down (or `phase3_share` of everything), its core opens (shield off, box on): sink it.
  Weak points are child objects with their own health and tags (no separate weak-point system).
- M5, **its death (the user: breaks and sinks, explosions):** secondary explosions along the hull, then it breaks up
  and goes under: its own destroyed mesh (a skeletal wreck with a break-up and sinking sequence: the Alicorn's
  SK_BA002_alcn_DAM pattern; made by the agent in WP0's script), DamageEffects on sockets, AC8's Niagara and sounds
  only. The music stops looping with it.

### WP12. Co-op, load, the STORE, release
Status: not started. Depends on: everything above.
- Every spawn through SV_Spawn with spawningUnit set (mirrored, ships and parts linked by key as the Spaceport's and
  the Alicorn's), every RE_SV_Fleet* and rise event forwarded, the rise played on every game from the host's time.
  The scars are local (WP8).
- The perf line with the whole fleet and the Tanicorn up; the STORE's freeze and restore over every object of theirs
  (docs/re/STORE_FREEZE.md); 0.74.48's rule.
- Release: round 30's fleet in dev builds only until WP0's own Tanicorn is in (section 2); then into friends' zips
  (`BUILD_NAME=COOP2MP COOP=1 sh tools/package_release.sh online <version>`, registered on the leaderboard).

### WP13. The fleet shells the airfield
Status: not started. Depends on: WP7 (the course and station), WP9 (the railguns, VLS), WP10. The user, 2026-11-10:
near Comona, it shells the airfield.
- What exists [V: sv_rounds.lua airfieldTick, sv_config.lua CFG.airfield, docs/re/AIRFIELD_SUPPLY.md]: the airfield's
  health (hp 250) falls by `hit_damage` (3) for every enemy weapon that ends on one of its 4 target points (the event
  package's int flag SV_AirHits), and by damage Lua adds itself (AF.bomb / AF.pending: the heavies' bomb runs land
  `damage_delay_s` after the run; the festival's missiles add `impact_damage` on the runway: sv_festival.lua impact).
  At 0 the airfield is down: landing and the STORE close until the round after next (AirfieldDown, RE_SV_AirfieldClose
  / Open), reopening at repair_hp. The minimap ping on bombers heading for it (CFG.airfield.bombers.ping).
- **The shelling** (from the gun line, every ship still afloat with a long-range weapon, and the Tanicorn when it
  gets there): a salvo every `shell_every_s` (e.g. 20 s) per shelling ship, staggered; each salvo:
  1. its weapon fired at the airfield where the game's fire control can reach it: the railgun and VLS mounts ordered
     onto the airfield's target dummies by name (a LiveFireOneShotWeapon or attack-order record targeting the dummy
     unit, hard rule 40) [?: a ship's turret attacking a ground target 16-20 km off: the stock railgun's 15 km reach
     says no without our own fire-control values]: its hits count through SV_AirHits by themselves;
  2. else (or as well) scripted, as the heavies' bombs are: the salvo's damage (`shell_damage`, e.g. 6) put on
     AF.pending to land `shell_flight_s` (e.g. 6 s) later, with AC8's explosion effects on the runway at random spots
     at that moment (the festival's impact records' VFX, or Mission 22's airport-strike explosions) and the shake if a
     player is near;
  3. the warning: callout `THE FLEET IS SHELLING THE AIRFIELD` once, the RAILGUN WARNING while a railgun salvo is in
     the air (hard rule 45), the shelling ships pinged on the minimap (the bombers' ping), the airfield's bar.
- Tuned so a team that ignores the fleet loses the airfield in ~3-4 minutes of shelling (250 hp; settings), and one
  that fights it never sees it (the gun line ~13 minutes out).
- The TANACORN's bow railcannon (WP11 phase 2) hits the airfield from wherever it is, gun line or not: its charged
  shot is WP13's scripted route with its own damage and warning.
- While the airfield is down the shelling stops (nothing to shell); after its repair it starts again if the fleet's
  still on station.
- Co-op: the host shells (AF is the host's); the joiners see the effects from forwarded impact events and the host's
  airfield bar, as the heavies' runs.
- Settings: `CFG.specials.fleet.shell = { enabled = true, shell_km = 20, hold_km = 16, every_s = 20, damage = 6,
  flight_s = 6, real_fire = true }`.
- Log lines: `fleet: <ship> at the gun line (<d> km from the runway): shelling`, `fleet: shell salvo <ship>: <real |
  scripted>, <dmg> on the airfield in <s> s`, `airfield: hit (...)` (the existing line).
- Test key (test only): the fleet straight to its gun line (it appears 1 km short of it).
- Pass: the shelling begins at the gun line, the airfield's bar falls with each salvo, the callout and warnings
  show, the airfield goes down if ignored, shelling stops while it's down; no shelling before the gun line.

### WP14. GEOFON's capture (co-op only)
Status: not started. Depends on: WP5 (GEOFON's own BP, for the deck's landing marks), WP7 (GEOFON sailing; RAVEN and
its EW mast), co-op (sv_coop*.lua, sv_down.lua). The user's idea and answers: section 2.
- **What it is:** while GEOFON is afloat in round 30 with two or more players linked, now and then the host picks a
  random player who's flying (not down, not at the airfield or in the STORE, not in a capture already); a CAPTURE LOCK
  warns them for `lock_s`; if they don't break it, their plane is taken over, flown to GEOFON and landed on its deck,
  and they die there (DOWN, revivable). Solo: never (`coop_only`).
- **What already exists to build on:**
  - the runtime's loiter autopilot (runtime/flight.c SV_Down + down_ctl.c, KILLS_HEALTH_DEATH.md 7): on the local
    player's own plane, from the BuildFlightInput detour, it replaces pitch, yaw, roll, throttle and brake every frame
    (the stick does nothing) and flies the plane round a point; input signs learned in its first seconds. Its turn was
    loose in a test (COOP2MP.md: bank 40 for 90 s with a ~120 deg heading error), so its guidance needs work anyway;
  - co-op's DOWN and revive (sv_down.lua): the floor, DOWN (invincible, hidden, weapons off, the enemies' attacks held
    off, the loiter autopilot round the airfield, "dw" to the host), the spectator camera (a CameraComponent on another
    player's plane and SetViewTargetWithBlend from Lua), the revive bought at the STORE (REVIVE <NAME>), the run over
    when every player is down;
  - the runtime moving a player plane every frame (coop.c CoTeleport: AActor::TeleportTo + the flight reset; hard rules
    51 and 53: smooth on the second player plane, whose actor tick is off);
  - the HUD's lightning distortion (BeginHUDDistortionLightning, sv_anomalies_dev.lua) for the lock's flicker.
- **The source: RAVEN's EW mast** (the user's choice) [machine: rows / world data; repo: generators]: a part of its own
  on RAVEN, with its own health and box, named `EW MAST` (its own model row copy: WP7's names route). Routes, in order:
  1. **the Alicorn's ECM part in one of RAVEN's turret slots**: `BP_BA002_alcn_ecm_Base` (LiveAIGroundVehicleObject,
     row alcn_ecm_01 -> alcn_ecm, HP 500 / 2250, its jammer BP_wp_ecm_ON; its stock box name "JAMMER") [V: ALICORN.md
     1.2], in RAVEN's DT_NPC ChildNPCId in place of one of its parts (the Mk 15 CIWS slot on SOC_aegs_mk15, the
     highest), its class from the Alicorn's world data by import_from: the route the Ladons' CIWS slots took for the
     Arsenal Bird's pulse pods (hard rule 38, confirmed). [?: the jammer's own effect on players (the HUD's jamming) as
     a part of a campaign ship: a bonus if it works, switched off if it doesn't fit];
  2. a RAVEN of our own (BP_SV_aegs_Raven on the native vessel class, the stock Aegis BP's values copied, WP5's route)
     with a mast component on its radar socket SOC_Radar and a part of ours on it (the agent's model): only if route 1
     can't be done or looks wrong.
  No mast (destroyed, or RAVEN sunk): no more captures for the round (callout `RAVEN'S EW MAST DOWN: NO MORE
  CAPTURES`), and a lock running is broken.
- **1. The pick** [repo, host]: every `every_s` (first `first_s` after the fleet appears), if GEOFON and RAVEN's EW mast
  are up and no capture is on: a random player from COOP.players() alive, flying, not at the airfield, not the only
  one flying (a capture must never leave nobody up: the run would end), not captured in the last `per_player_s`.
  Message to everyone `cp|<slot>|<seq>` (reliable; sv_coop's guards: slot checked, one capture at a time).
- **2. The CAPTURE LOCK** [repo]: on the chosen player's game, `lock_s` (10 s): their HUD flickers, a tone, the
  callout `CAPTURE LOCK` / `GET CLEAR OR DESTROY RAVEN'S EW MAST`; on every other game `CAPTURE LOCK ON <NAME>` and the
  mast pinged on the minimap (the game's own ping, as the bombers'). It's broken when **RAVEN's EW mast is destroyed**
  (or RAVEN sunk) or the chosen player is more than `escape_km` (12 km) from RAVEN when the lock runs out (RAVEN sails
  beside GEOFON, so that's as far from both): `CAPTURE BROKEN`. GEOFON sunk: the lock ends.
- **3. The takeover** [machine: native; repo: Lua]: a new native mode beside SV_Down's loiter (e.g. `SV_Capture(plane,
  ship, ...)`, at most 15 characters: hard rule 25): from the BuildFlightInput detour, the player's inputs replaced
  every frame (stick, throttle, brake, weapons, flares, as DOWN does); guidance to a gate `gate_km` (3 km) behind
  GEOFON's stern at `gate_alt_m` (300 m), lined up with its heading, its moving pose read each frame (CoReadPose on
  the ship's root, as the planes'). The HUD: `AIRCRAFT CAPTURED`, the others' callout `<NAME> IS BEING TAKEN TO
  GEOFON`. Offline first: tools/checks/flight_test.sh's model planes, a moving gate.
- **4. The landing, fully scripted (the user's choice)** [machine: native]: from the gate the runtime moves the plane
  itself every frame (CoTeleport's TeleportTo + flight reset, its velocity set to match): a glide path (3-4 deg) to the
  deck's touchdown mark, the angled deck's line, a trap (decelerating ~100 m to a stop), then parked on its deck spot,
  carried with GEOFON each frame (its pose = the ship's transform x the spot). Gear down for the final (the input's gear
  bit, flight.c's flags). The deck's marks (touchdown, the angled line, the parking spot) as sockets on BP_SV_grfd
  (WP5) or offsets from GEOFON's root [I]. **First test, before any of it:** a test key that pins your own plane to a
  point moving at 45 km/h for 30 s (does the local plane's flight model or camera fight a per-frame teleport? the
  second player plane's smoothness needed its actor tick off: hard rule 51). If it fights: the user decides on a fade
  at short final (the fallback the user turned down for now).
- **5. Captured = dead** [repo]: `die_after_s` (3 s) after the trap: `<NAME> CAPTURED` to everyone, an explosion on the
  deck where the plane is, and the player goes DOWN through sv_down.lua's own path (the floor reached: the plane hidden
  and set flying round the airfield by the loiter autopilot from a spot high over it, the spectator camera on another
  player), revived as any DOWN player (the STORE's REVIVE: price x raise for each revive in the run). The captured
  plane's wreck isn't left on the deck (GEOFON's own deck launches spawn off its bow).
- **6. GEOFON sunk during a capture (the user: the captive goes down with it):** in the lock it just ends; in the
  takeover or the landing, or parked before die_after_s, the captive goes DOWN at once (the same path); the rise
  (WP6) waits for nothing.
- **Co-op sync:** the host decides (the pick, the lock's end, GEOFON's death); the captured player's own game flies its
  own plane (the takeover and landing are local to it) on its copy of GEOFON (a joiner's copies are drawn 120 ms behind
  the host's: COOP2MP); everyone else sees that plane through its stream, as any player's. Messages `cp` (pick), `cb`
  (broken, why), `cl` (landed), `cx` (cancelled: GEOFON sunk); a joiner that leaves mid-capture: the capture ends. Host
  migration: a capture in flight is cancelled (the player given back their plane).
- **Guards:** never solo, never the last player flying, never two at once, never during the TANACORN's cinematic or a
  STORE freeze, never a player who's down; the player's controls always given back on any end (lock broken, landing
  cancelled, DOWN, the round's end, a restart, the level gone), checked as DOWN's restoreAfter is.
- **Settings:** `CFG.specials.fleet.capture = { enabled = true, coop_only = true, first_s = 120, every_s = 180,
  per_player_s = 300, lock_s = 10, escape_km = 12, gate_km = 3, gate_alt_m = 300, glide_deg = 3.5, die_after_s = 3 }`,
  mirrored in survival.ini [specials.fleet.capture] (gameplay: not in the leaderboard's free lists).
- **Log lines:** `capture: RAVEN's EW mast up (<route>: <class>, health H)`, `capture: <name> picked (slot N; RAVEN at
  d km)`, `capture: lock on <name> broken (<the mast destroyed | RAVEN sunk | N km clear>)`, `capture: RAVEN's EW mast
  down: no more captures`, `capture: <name> taken over (gate at d km)`, `capture: <name> at the gate; the landing starts`,
  `capture: <name> trapped on GEOFON's deck`, `capture: <name> captured: DOWN`, `capture: cancelled (<why>)`; native
  `capture: autopilot on plane <p> ...` as DOWN's lines.
- **Tests:** offline: `tools/checks/capture_test.sh` (the pick and its guards, the lock's escape and source, the
  messages, every end giving the controls back, the DOWN hand-over) and flight_test.sh's moving gate; in game (test
  build, two games linked, or a test-only key that runs it on your own plane solo): RAVEN with its EW mast up and
  boxed (route 1's slot swap), the pin test, then a capture end to end. Pass: the mast is up on RAVEN, boxed EW MAST, and can be shot off; the lock shows and can be broken both ways; a capture flies the plane to the gate, lands it on the
  moving deck, kills it, and the revive brings it back; nobody's controls are ever left taken.

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
| ship turrets can't fire at the airfield 16-20 km off | WP13 step 1's test | the scripted salvo (step 2), proven for the heavies |
| `pip install bpy` doesn't fit the cloud session (Python version, disk) | WP0's first step | the script runs on the user's machine |
| the in-game camera node can't frame the rise, or its length is fixed | WP4's cinematic test | Lua's view target, else the event focus camera |
| a player plane's invulnerability doesn't hold through the cinematic | WP4's test | the player's health floored and put back after |
| no F-14D ace row / post-stall moves for AEGIR | WP7 | the ace rows Survival has (Su-33s) with F-14D airframes set at spawn |
| the looped tracks gap or overlap at their restart | WP10's music test | a short fade at the end, or the music player's own loop |
| the local player plane fights a per-frame teleport (the capture's scripted landing) | WP14's pin test | a fade at short final, if the user agrees |
| the capture autopilot can't reach the gate reliably (DOWN's turn was loose) | flight_test.sh, then WP14's test | a wider gate, more time; the takeover by teleport to the gate behind a flicker |
| a player's controls left taken after a capture | capture_test.sh (every end gives them back) | (must not happen) |

---------------------------------------------------------------------------------------------------------------------
## 6. Questions still open for the user
None (the last six answered 2026-11-10: section 2). New questions go here as work raises them, each with the
agent's recommended answer.

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
