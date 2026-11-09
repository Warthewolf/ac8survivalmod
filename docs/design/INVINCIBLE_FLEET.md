# INVINCIBLE FLEET: special round plan (2026-11-09; nothing built yet)

The user's special (2026-11-09): an enemy fleet after AC04's "Invincible Fleet", with the TANICORN hidden under its
aircraft carrier. When the carrier is destroyed it breaks up, the Tanicorn bursts out of the sea under it bow first,
climbs into the sky, crashes down flat onto the waves, and only then opens fire and becomes a target. The fleet's
weapons: flak, laser interceptors, VLS missiles and railguns.

The user's order of work, kept here as the plan's three stages:
1. **The Tanicorn fully working in game** (docs/re/TANICORN.md; milestone 0 done).
2. **A damage model for AC8's Ford-class carrier** and the Tanicorn's breach out of its wreck.
3. **The rest of the fleet** around them.

Tags as in docs/re: [V] read in a file or seen in game (where), [I] inferred, [?] not known yet. Everything here
reuses something Survival already runs where it can (the Spaceport Assault's enemy fleet, the Alicorn's dive and
surface, the ZFA-44s' AC7 laser, the fleet's flak). Read docs/re/TANICORN.md, docs/re/SPACEPORT_ASSAULT.md and
docs/re/ALICORN.md before building any of it.

## 1. The source: AC04's Aegir Fleet
- Ace Combat 04 Mission 06 "Invincible Fleet" (Operation Rough Seas, 23 November 2004): ISAF's surprise strike on the
  Erusean **Aegir Fleet**, "the invincible armada", lying at anchor in Comberth Harbor; most of it was sunk at anchor.
  The flagship, the Iowa-class battleship **Tanager** (Captain Matias Torres, later "the Hero of Comberth Harbor" for
  saving his crew), and the carrier **Geofon** got out of the harbour and were caught before open water. The Tanager
  sank outside the harbour mouth. The player scores points in a 15-minute limit; the briefing warns the operation is
  long and the player may need to resupply. [acecombat.wiki.gg: Aegir_Fleet, Invincible_Fleet, Tanager]
- The fleet as listed there: battleship Tanager (3 main guns), carrier Geofon (launches a KA-25), Aegis cruiser
  **Raven** (2 SAMs), cruisers **Beluga, Fenris, Kolga, Lazuli** (a SAM and an AA gun each), destroyers **Herne,
  Taisch, Thiassi**, submarines **Beowulf-Nu, Beowulf-Pi** (and five unnamed), missile boats, landing ships, a supply
  ship and container ships, with F/A-18s, F-14s and Tornados over it and an F-14 ace "Levy". AC04's audio names four
  more Aegis that never appear: Condor, Magpie, Sparrow, Finch.
- What we take from it: the names, the shape (a carrier group round a flagship), a fleet that's dangerous to approach
  (a "long operation": the airfield and STORE stay open during it), and the Tanager's escape run. The TANICORN is the
  Tanager's "what if": the battleship that didn't sink (docs/re/TANICORN.md).
- Survival is on Comona, not Comberth: the fleet sails the open sea west of the spaceport island, where the Spaceport
  Assault's 27 ships already ran (its Ford at (-29.65, -0.26) km, ford_cm) [V: docs/re/SPACEPORT_ASSAULT.md 0.73.39].

## 2. The round, as a player sees it
A first draft for the user to change (section 9's questions):
1. **Warning (break before the round):** callout `INVINCIBLE FLEET` / `THE AEGIR FLEET IS UNDER WAY`, the NEXT row
   `FLEET: n SHIPS  CARRIER: GEOFON`. Radio from Survival's own lines (config/subtitles.ini, never AC7 or AC04 voice).
2. **The fleet (phase 1):** the fleet appears in formation and sails a slow course (section 6). Its screen fires flak
   and VLS missiles, its laser interceptors shoot down missiles fired at the ships they cover, the Raven's railguns
   (with the RAILGUN WARNING) reach far out, and the carrier's deck launches fighters. The round's normal fighters
   are fewer (the fleet is the threat). Ships are paid as sunk, turrets as shot off (the Spaceport's pay).
3. **The carrier falls (phase 2):** its damage shows as it's hit (fires, smoke, a listing deck). At 0 it breaks in
   two and goes down. In its wreck, the sea erupts: the TANICORN's bow breaks the surface between the halves, the hull
   climbs bow first into the sky, hangs, and falls back flat onto the waves (spray, shock ring, camera shake). Nothing
   fires at it and nothing can lock it during the breach.
4. **The Tanicorn (phase 3):** it opens fire the moment it settles, then becomes targetable: boxes, TGT marks, the
   boss health bar. Weak points first (its weapon parts), its core last (TANICORN.md's phases). The fleet left afloat
   fights on with it.
5. **End:** the Tanicorn sunk (with its own death: section 3, M5) = round won, the big reward. Ships still afloat
   then: [?] sunk with it ("the fleet scatters"), or they must be sunk too (the user's call).

When the carrier should fall is the round's pacing lever: only by the players (they choose when to wake the boss), or
also on a timer (the "escape run": the Tanicorn breaks out anyway after N minutes). Section 9.

## 3. Stage 1: the TANICORN fully working
Where it stands [V: HISTORY 0.74.43-0.74.47, docs/re/TANICORN.md 5]: milestone 0's first own part, the 5-inch twin
mount BP_SV_Tani_T5 (our mesh, skeleton and blueprint on AC8's native ALiveAIGroundVehicleObject), loads in AC8 with
its fire control and spawns through Survival's own rows (Ctrl+T, test builds). Not seen yet: it aiming, firing, being
hit and swapping to its wreck. **The Iowa geometry may only be in the user's dev install** (TANI=1 builds;
package_release.sh drops the container), so the Invincible Fleet with this Tanicorn can't go to friends: section 8.

Milestones, each one test in game before the next (the test key, the log lines and a pass line for each go in
TANICORN.md as it's built):
- **M0b, the mount works.** The T5 aims (its yaw / pitch bones move as you fly round), fires flak, takes hits and
  swaps to its wreck. If it never turns: the bone names, SlotSocketPrefix or sockets (TANICORN.md's open questions).
  Then the other mount types on the same route, one at a time: the 16-inch triple (railgun shells:
  LiveFCSModule_LauncherTripleRailCannon + BP_wp_eml_ldbs01, three pitch bones as GR037's, the RAILGUN WARNING by
  hard rule 45), a CIWS / laser mount (an anti-missile arm, ours: BP_SwingTLS_ForMSL's values, or AC7's
  LaserInterceptor on ALiveLaserInterceptor as the ZFA-44s carry it: proven in game, hard rule 58), a VLS block
  (cells = sockets up to SlotNum, as the Alicorn's vls1..8 and the Aegis Mk 41's SOC_Vls_01..08).
- **M1, the hull.** The 650 m Leviathan hull (art/tanicorn/design/Leviathan_rev4.blend) as our static mesh with
  sockets, on AC8's submarine class (ALiveAISubmarine; ALiveAIVessels + a scripted rise if the submarine needs
  Alicorn-style data: TANICORN.md 0), its parts as LiveChildActorComponents on its sockets, spawned from Survival's
  world data with child AI objects (hard rule 7: every class imported, the container header too) and DT_NPC
  ChildNPCId / ChildNPCComponentNames paired by component name. Pass: the whole ship draws on the sea, every mount on
  its socket, each part boxed with its own health. First proof needed: **a static mesh with sockets of ours** loads in
  AC8 (TANICORN.md 4: not done yet).
- **M2, it fights.** Every part ordered by name a moment after it appears (a hull's order never reaches its turrets:
  the Spaceport's 0.73.40 lesson), each weapon's stock projectile firing (railgun shells, VLS missiles, flak, lasers),
  tuned for 1-4 players (the Alicorn's HP were for an online squad). The Spaceport's EXSAM homing and flak boosts apply
  (HISTORY 0.73.52-53).
- **M3, its moving parts.** The bow railcannon's raise and barrel split and the sub-railgun hatches as AnimSequences
  played natively (TANICORN.md 2: one sequence each, AnimationSingleNode; ULiveAISimpleAnimationComponent +
  LiveAISimpleAnimationPlayExecution, or hatch parts as the Alicorn's / Grifn's). No animation blueprints (BP script).
- **M4, its phases.** Weak points as child objects with their own health and tags (no separate weak-point system:
  TANICORN.md 1), the core shielded until they're down, phase changes fired from Lua (Survival's Lua polls part
  health and fires SV_Event remote events: the Alicorn special's pattern, sv_alicorn.lua), the boss health bar, its
  callouts.
- **M5, its death.** Its own destroyed mesh: a skeletal wreck with a sinking sequence (the Alicorn's
  SK_BA002_alcn_DAM + MainBodyDestructionDelayTime 12 s pattern), DamageEffects on sockets, AC8's own Niagara and
  sounds only (hard rule 58: no new master materials or shaders of ours).
- **M6, co-op and load.** Its parts linked by key on the joiners as the Alicorn's and the Spaceport's ships are, its
  remote events forwarded, the frame rate and Lua tick with it up (the perf line), and the STORE: no unit with child
  objects alive is ever taken off the spawner's list under them (0.74.48, Shazzy's crash), and the STORE freeze /
  restore runs over every one of its objects (docs/re/STORE_FREEZE.md).

## 4. Stage 2: the Ford's damage model and the breach

### 4.1 What AC8 has
- The Ford is VE004_grfd: Mission 16's allied Grindylow (A_Unit_01_Ship0, row VE004_grfd_Ally_01), four Mk 15 parts
  (BP_VE004_grfd_mk15_01..04), enemy rows VE004_grfd_01 with VE004_grfd_mk15_{RF,LF,RB,LB}_01. Survival already
  spawns it as an enemy in the Spaceport Assault (SV_Unit_SpFord, Faction 2) with its deck launching fighters, and it
  was sunk and paid in the user's test of 0.73.39 [V: SPACEPORT_ASSAULT.md].
- How it dies today [?]: not dumped. Campaign vessels die through LiveDefaultDestroySystemExtraEffect +
  BP_Vessel_BodyDestroyParam (a mesh swap to a hidden DamagedStaticMesh, sinking, FinalExplosionTime 80: the Aegis's,
  TANICORN.md 1). **First research step:** `ACE8AircraftBuilder dev obj` of BP_VE004_grfd_CP and its Base: its
  meshes (is there a _DAM?), DamagedStateComponent stages, DamageEffects sockets, destroy system and its params.

### 4.2 The damage model (ours, from the stock Ford's mesh)
Survival is built from stock files, so the Ford's own mesh (exported with ACE8 Aircraft Builder's `dev mesh`, as the
Alicorn's was) is the base. Our blueprint `BP_SV_grfd` on AC8's native vessel class (the TaniBuild route: our BP
straight on the native class, the stock BP's values copied from its dump; never a child of the stock BP, never the
stock package overridden), in Survival's own container:
- **Damage stages while afloat:** DamagedStateComponent ChangeMesh stages (e.g. at 66 % and 33 %: scorched deck
  sections, the island blackened) with the burnt look on its own mesh (hard rule 41: wreck meshes don't draw while it
  lives) and DamageEffects on new sockets (deck fires, island smoke, a list to one side).
- **Its death:** a skeletal wreck (the Alicorn's DestroyedBodyMesh pattern) cut at midships in Blender: two halves,
  torn edges, AC8's own _DAM materials. Its death sequence (~20 s): secondary explosions along the deck, the keel
  breaks, bow and stern lift and go under; AC8's own Niagara (Alicorn / Aegis explosions, smoke, sinking spray) and
  Wwise events placed as AnimNotifies (data, no BP script: AnimNotify_PlayNiagaraEffect and Wwise's AkEvent notify)
  [?: that cooked notifies play in AC8: to test on the T5's wreck first].
- **The gap for the Tanicorn:** the halves part far enough (~200 m) for a 650 m bow to come up between them, or the
  Tanicorn breaches just off the Ford's beam (simpler, and works with any wreck). The breach starts at a fixed time
  into the death sequence.
- Its deck launches stay the Spaceport's (SPORT's deck: a pool flight with a pose off its bow), stopping at its
  first damage stage or at its death (the user's call).

### 4.3 The breach
What has to happen: from under the wreck, bow first to the sky, hang, crash flat, settle, open fire, become
targetable. Lua can't do it (its tick is 250 ms and it can't move AI actors smoothly: hard rule 39), so the motion is
the game's own. Two routes, tried in this order:
- **A. The submarine's own surface, with our curves.** ALiveSubmarineBase surfaces along CUR_Surface{Location,
  Rotation}Curve between its UnderWaterLocation and OnWaterLocation (the Alicorn's: 56 m down, ALCN_Surface; Survival
  dives and surfaces the Alicorn with LiveSubmarineOperation records) [V: ALICORN.md 1.3]. If those curves are
  read as offsets or an overshootable alpha [?], our BP's own curves (pitch 0 -> 60 deg, height far past the water,
  back to 0 with a hard stop) make the AI hull do the whole breach itself. One test answers it: our curves on the M1
  hull, surfaced by the record.
- **B. A stand-in for the breach.** The whole Tanicorn as one skinned mesh with a root bone, its breach as one
  AnimSequence (Blender, ~12 s: under -> bow out -> 60 deg up, its bow ~550 m above the sea -> falls -> flat with a
  bounce -> still), played natively (AnimationSingleNode) on a SkeletalMeshComponent added to the hidden AI hull at run
  time (hard rule 46: AddComponentByClass + SetSkeletalMeshAsset draws on an AI object). At its end the stand-in hides
  and the real hull, already on the water at the same spot, is shown. Splashes, the shock ring and sounds as
  AnimNotifies (AC8's: the Alicorn's NS_ex03_alcn_surfacing0x, AKE_BA002_alcn_Surface_Play).
- **Untargetable, then targetable:** until it settles the hull and every part are switched off as sv_escort.lua's
  offObj does (no box, no lock-on, invincible, hidden) or held under water; at the slam they're switched on
  (sv_escort_laser.lua's onObj), every part's fire order goes out, and a moment later (the user's "before becoming
  targettable") the boxes and TGT marks come on. Keep each step a remote event fired from Lua (hard rule 26: never
  a delayed record gated on a flag set later).
- **The trigger:** Lua sees the Ford's hull die (the Spaceport's hull watch, SPORT.shipObjs) and starts the breach
  at the right time into the death sequence. (The rockets' LiveDefaultDestroySystemSpawnFromWD spawns world-data
  objects by name at a dying piece's socket [V: SPACEPORT_ASSAULT.md]: a native alternative for bringing the
  Tanicorn in at the Ford's keel.)
- **The camera:** the event focus camera on the Tanicorn for the breach (hard rule 28: it zooms by distance), with
  the HUD's callout `THE TANICORN` / `THE TANAGER RISES` (the user's words to be chosen).
- **Spawned when:** with the fleet, deep and switched off under the Ford (the Alicorn sits 56 m down without trouble)
  [I], so nothing big spawns mid-fight; or at the Ford's death (cheaper while the fleet is up, a spawn during the
  fight). Measure both.

## 5. Stage 3: the fleet

### 5.1 Composition (a first draft; every count a setting, as the Spaceport's)
| AC04 ship | Survival's ship (AC8 asset) | role | weapons |
|---|---|---|---|
| Tanager (flagship) | THE TANICORN (ours) | the boss, under the carrier | 16-inch railgun shells, 5-inch flak, CIWS / lasers, VLS, the bow railcannon |
| Geofon (carrier) | Ford VE004_grfd, our damage model | the centre, deck launches | its four Mk 15s as flak / CIWS, laser interceptors |
| Raven (Aegis cruiser) | Aegis VE002_aegs, named RAVEN | flagship's guard, long-range | Mk 41 VLS (EXSAM homing), Mk 45 flak, railguns |
| Condor, Magpie, Sparrow, Finch | Aegis VE002_aegs | inner ring round the carrier | Mk 41 VLS, Mk 45 flak, Mk 15 CIWS |
| Beluga, Fenris, Kolga, Lazuli (cruisers) | Mission 22's enemy fleet hulls (Kirov, Udaloy, Gorshkov, Grigorovich) [?] | outer screen | their stock SAMs and guns as flak, laser interceptors |
| Herne, Taisch, Thiassi | Grigorovich class [?] | screen | flak, SAM |
| missile boats | VE011_mslb | pickets, patrolling | SAM (as the Spaceport's patrol) |
| supply / container ship | VE021_ctslf | the train, worth sinking | none (or a Stinger mount) |
| Beowulf-Nu / Pi (submarines) | [?] no stock enemy submarine found yet | optional | - |

- Mission 22's enemy fleet is already in Survival's world data (Survival's WD/EP are copies of Mission 22's):
  EA_Unit_01_Ship0..3, udaloy + 2 grigorovich, gorshkov + 2 grigorovich, kirov + grigorovich, all Faction 2 [V:
  SPECIAL_ROUNDS.md 3, the section 12 positions]. Their parts, rows and whether they've ever spawned in Survival: [?].
- Size: the Spaceport's 27 ships (~110 objects) came up whole and ran [V: 0.73.39]; this fleet plus a 650 m boss
  with ~20-40 parts must stay near that. Start at ~16 ships plus the Tanicorn, and measure.

### 5.2 The weapons
- **Flak:** done for the fleet's AA mounts: NPC_FCS_VesselAAGun* (the Aegis's Mk 45, the Ford's four) on a clone of
  the ground flak gun's fire control, boosted (HISTORY 0.73.52-0.73.53). The Tanicorn's 5-inch mounts on the same.
- **VLS missiles:** the Aegis Mk 41 and the Ladon / Alicorn VLS, with the fleet's EXSAM homing and salvos
  (missile.homing_from, salvo_n 3). Never a scripted sure kill (hard rule 36: check what a copied fire record was for).
- **Laser interceptors:** the fleet's answer to missile spam: each covers the ships near it, burning down missiles
  fired at them, so players kill the laser mounts first or close in with guns and bombs. AC7's LaserInterceptor on
  ALiveLaserInterceptor, as the ZFA-44s carry it, spawned and attached at a ship's socket (proven to fire and
  intercept: 0.74.31) [V], or an AC8 anti-missile arm of ours (BP_SwingTLS_ForMSL's values) on the Tanicorn's
  CIWS mounts. Needs a turn rate / cool-down that leaves skilled missile play possible, and its own callout
  (`LASER DEFENCE ONLINE`). Its beam is AC8's NS_UAVTLS_Muzzleflash01 (hard rule 58).
- **Railguns:** the Tanicorn's 16-inch triples (TripleRailCannon, BP_wp_eml_ldbs01) and the RAVEN's. A railgun on a
  campaign ship's mount: the Alicorn's railgun part (ALiveAIRailgun, its NPC row in the ship's ChildNPCId: hard rule
  38's Arsenal Bird pods on the Ladon are the precedent) [?], or a mount swapped to a railgun fire control as the flak
  swap does (only where its MeshComponentName and SlotSocketPrefix exist on the part: TANICORN.md 3). The minimap and
  RAILGUN WARNING by hard rule 45. Telegraphed (the Alicorn's railgun tells) and survivable.

## 6. How it's built (reusing what runs)
- **The special:** a new SPC.kinds entry `fleet` (Scripts/sv_fleet.lua, a family of its own if it grows past 2,000
  lines), with the Spaceport's hooks (ready / busy / over / row, from_round, fighter_share), CFG.specials.fleet and
  survival.ini [specials.fleet] for every count, price and timing (players edit them without a rebuild).
- **The ships:** the Spaceport's builder generalised (survival_events.py sp_fleet / build_survival.py spaceport_units:
  one-ship units, Faction 2, no tags, TGT and a box, every part's own order by name, SPORT.shipObjs's hull watch and
  pay). Either a second fleet layout or a shared builder both specials call; keep the Spaceport's names working.
- **Formation and movement:** the fleet holds a formation round the carrier and sails slowly along make_path lanes
  (ControlType 1, smooth, hard rules 2, 35; one long path from appearance, hard rule 54 if it's fast), or holds its spot
  as the Spaceport's did. The Tanicorn stays under the carrier while it sails [?: a submarine following a ship: give
  both the same path at the same speed, or keep the fleet at anchor as AC04's was].
- **Rounds:** every 5th round's rotation from a high round (from_round), or THE final boss round (section 9).
- **The STORE and the airfield:** the clocks wait while you're down at the airfield with nobody else flying (the
  Spaceport's I6). Nothing with child objects alive is recycled (0.74.48). Removals by remote event, never a unit off
  the list while its parts are up.
- **Co-op:** every spawn through SV_Spawn with spawningUnit set (mirrored, linked by key), each RE_SV_Fleet* and the
  breach's events forwarded, the breach played on every game from the host's start time.
- **Tests without the game:** a fleet_test.sh like spaceport_test.sh (spawn, pay, phases, the breach's event order,
  co-op messages), the build's read-back checks for every new row and class.

## 7. Risks and unknowns
| risk | what answers it | fallback |
|---|---|---|
| a static mesh with sockets of ours (the 650 m hull) won't load or draw | M1's first test | the hull as a skeletal mesh (VALKA's route, proven) |
| ALiveAISubmarine needs Alicorn data our BP lacks | M1 | ALiveAIVessels + the stand-in breach (route B) |
| the surface curves can't overshoot | the 4.3 A test | route B |
| cooked AnimNotifies don't play | the T5 wreck test | effects fired from Lua at the sequence's times |
| a 650 m object leaving the water reads badly (water planes, culling at height) | the breach test | a lower climb, more spray |
| laser interceptors make missiles useless | balance in a test | fewer, slower, killable first |
| ~20 ships + the boss cost too much frame time | the perf line in a test | fewer ships, parts merged |
| the Iowa geometry can't ship to friends | section 8 | a Tanicorn of our own geometry |
| units with children recycled under them crash the STORE | 0.74.48's rule | (rule: never) |

## 8. What can ship
- The Tanicorn's hull is Sea Power's Iowa (the user: "my install only"); its container ships only in TANI=1 dev builds
  and package_release.sh drops it. So the Invincible Fleet round needs, for a friends' zip: the round without the
  Tanicorn (the carrier's death ends phase 2), or **a Tanicorn hull of our own geometry** (modelled from scratch on
  the Leviathan design, Alicorn parts allowed: AC8 stock). The user's decision; the code makes the boss a setting so
  the round runs either way.
- Every other ship is AC8 stock (allowed); the AC7 laser is the user's 2026-11-07 exception (never AC7 voice).

## 9. Questions for the user
1. Which round: in the special rotation (every 5th round, from round N), or the run's final boss (TANICORN.md's
   "final round")? Is there a final round?
2. Does the carrier fall only to the players, or does the Tanicorn break out on its own after N minutes (the
   Tanager's escape run)?
3. When the Tanicorn is sunk, do the ships left afloat sink with it or must they be sunk too?
4. The breach: between the Ford's two halves (needs the split wreck) or beside it (simpler)? How high into the sky?
5. Names: the fleet's ships with AC04's names (RAVEN, BELUGA, ...) on their boxes? The Tanicorn's own name on screen?
6. For friends' builds: the round without the Tanicorn, or a Tanicorn of our own geometry first?
7. The fleet: at anchor (AC04's harbour) or under way?

## 10. Order of work
1. M0b: the T5 mount aims, fires, takes hits, wrecks (test build, Ctrl+T). Then the other mount types.
2. Research: dump BP_VE004_grfd_CP (its death today), the submarine class's surface (curve semantics), Mission 22's
   enemy fleet parts and rows.
3. M1: the Tanicorn's hull with every mount, spawned from world data. M2: it fights.
4. The breach test on its own (route A on the M1 hull, else route B), from a test key, no fleet.
5. The Ford: BP_SV_grfd with its damage stages, then its death sequence and the gap; the breach timed into it.
6. M3-M5: the Tanicorn's moving parts, phases and death.
7. The fleet: composition, formation, weapons (lasers and railguns last: the least proven), the round's flow, pay,
   callouts, the NEXT row; fleet_test.sh.
8. M6: co-op, the perf line, the STORE; then into the rotation (or the finale) with every value in survival.ini.

Sources (AC04): https://acecombat.wiki.gg/wiki/Aegir_Fleet, https://acecombat.wiki.gg/wiki/Invincible_Fleet,
https://acecombat.wiki.gg/wiki/Tanager (read 2026-11-09).
