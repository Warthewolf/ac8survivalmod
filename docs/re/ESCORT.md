# THE ESCORT (CHARLENE) and the ZFA-44 carriers (2026-11-06)

> 0.74.4 (2026-11-07): the landing below is out of date: the escorts now all go onto a ~15 km circuit from her rollout, one every 15 s, landed once taxiing, the round won 210 s after she lands; the carriers launch every arm (no "still up" skip). AGENTS.md's 0.74.4 entry has the details.


The user (2026-11-06): an ESCORT special round. CHARLENE, an allied B-1 Lancer, spawns in the map's south-west corner,
flies to Comona Airport under constant attack and lands. Four escorts (Su-57 YORKE, Su-57 ROCK, Su-33 ALI, Su-35
DANIELLE) land after her. The round is lost if she dies and completes once all five have landed. Then she says: "Thank
You Pilot, I've sent word to HQ and they've sent two Cargo Vessels into the Area with the Special ZFA-44 Airframes, you can
call for their support from the STORE". The reward: Mission 17's cargo ship (allied) in the STORE, launching ZFA-44s
(docs/re/ZFA44.md) and staying 3 rounds (VOID WATCHER 1's service model).

Tags: **[data]** confirmed in data, **[inferred]**, **[test]** needs an in-game test. Sections 1-5 are the research's
essentials (the full research, its dumps and route.json: `build/research/escort/` on the build machine, git-ignored).
Section 6 on is the Lua built on branch feature/zfa44 (`Scripts/sv_escort.lua`), not yet run in game.

## 1. AI aircraft landing
- Stock AC8 lands AI planes in two missions **[data]**: Mission 14's C-130 (one 116 km path from 4.8 km up to a flat
  rollout; speed changed by re-issuing the same path; touchdown at 50 km/h, accel 2.7; invincible at touchdown) and
  Mission 26's Baxter on the carrier (LiveEnableLandingGear true, a path down to the deck, then an 18 m path at speed 0).
- MOONCHILD's scramble at Comona (Mission 22 `01_Air0_f18e_0_Path0/1/2`) runs at z 7.5 m on runway 25's east end:
  an AI plane on a path holds the runway there **[data]**. Path speed overrides the model's SpeedMin (MOONCHILD taxis at
  50 km/h on a SpeedMin 650 F/A-18E) **[data]**.
- ALiveAIPlane has `EnableLandingGear(bool, delay)`, `EnableAvoidObstacle(bool)`, `RootHeight`, gear-on / off meshes
  **[data]**; the B-1B has gear-on meshes.
- Survival's landing (hard rule 1: no PathPointReceive): one path per leg (smooth, ControlType 1: hard rule 35), each
  handover at or below 320 km/h (hard rule 54 is for fast planes), each record fired by Lua by distance:

| leg | path (build) | from -> to | speed |
|---|---|---|---|
| route | SV_Path_CharRoute | spawn -> IAF (16 km out, 846 m, heading 067) | 600 km/h, 450 from 25 km out |
| final | SV_Path_CharFinal | IAF -> touchdown (300 m past the west threshold, z 7.5 m), 3 deg glide slope | 320 / 280 / 260 |
| rollout | SV_Path_CharRoll | past touchdown -> 120 m short of the east threshold | 50, accel 2.7 |
| taxi | SV_Path_CharTaxi | MOONCHILD's taxi reversed, to the hold spot | 30 |
| stop | (RE_SV_CharStop) | at the hold spot | 0 |

- Risks **[test]**: root height on a z 7.5 m path (float or sink); the flight model pulling up near the ground (backstop:
  `EnableAvoidObstacle(false)`); gear (the record, or `EnableLandingGear(true, 0)` from Lua); slowing 260 -> 50 km/h within
  ~1 km; the player's own landing on the runway and the solo STORE freeze (DeactivateForMinigame stops her mid-air): landing
  is closed to the players from her final until everyone's down. Fallback if touchdown fails: the safety timeout counts
  her landed and takes her off.

## 2. Mission 17's cargo ships and their launches [data]
- Ships `VE021_ctslf_01/02/03` (BP_VE021_ctslf_0N_CP): MaxHealth 75, no FCS on the hull; children: two container
  launchers (BP_VE021_ctslf_cntus_0N_CP, their weapons in the blueprint) and a Stinger mount.
- Each launcher: 6 `LiveFireControlSystemSpawner` arms (AllArms order = WN_WEAPON_1..6), each launching a world-data unit
  by name (`LiveFCSModule_ProjectileSpawnerFromWorldData` {Units: E_Unit_01_drone_<k>_<m>}); ship k's arms name
  drone_k_0 / drone_k_1. Mission 17 fires them with LiveFireOneShotWeapon {WN_WEAPON_n, container object}.
- The UAVs (`OP0019_uavcs_01`, MARTYR) are parked at z -245 m until launched **[data]**; whether a full-size fighter
  launches from a 5-slot drone rack, and when its plane object is made (at the ship's spawn or at the launch), is **[test]**.

## 3. The B-1B and the escorts [data]
- B-1B ally row `OP0008_b01b_Ally_01` (NLID_1000, flares + bombs): MaxHealth 130, SpeedNormal 600 / Min 300 / Max 2400.
- Escorts on Survival's own rows on the allied models OP1021_su57_Ally (115 HP), OP1030_su33_Ally (65), OP1028_su35_Ally
  (65); never NLID_0400_CP (hard rule 22); rows and behaviour before the level loads (hard rule 20).
- Names on the boxes: GameObjectDisplayNameID02 = SV_Charlene / SV_Yorke / SV_Rock / SV_Ali / SV_Danielle, texts by
  SV_SetText (as VOID WATCHER 1's).

## 4. Enemies attacking an allied plane
- Mission 14: TransitAttackAndEvade / TargetFirst orders on the C-130's object, unit areas moved onto it **[data]**.
- Survival: Lua `EngagementOrderOverride(Normal, her actor, TargetFirst, 0, false, 7, false)` per plane (VOID WATCHER 1's
  strike flight's way). The test of 2026-11-04: the director's cover and co-op's hunt re-aimed such a flight within ~60 s,
  so her attackers are kept out of both (and the allies' hunts) **[data]**.

## 5. The route [data: map; inferred: times]
- Spawn 6 km in from the south-west corner, (-41.1, 31.4) km, 3 km up; 51.2 km at heading 055 to the IAF, all over open
  sea; the final 16 km along runway 07 on a 3 deg glide slope; ~8.5 min spawn to stop, ~12-13 min with the escorts.
- Runway 07: west threshold (1541439, -406838), east (1679514, -465447) cm; touchdown 300 m past the west threshold;
  rollout end t 1380 m; her hold spot t 1435 m, s +63 m (south). (t: metres along 07 from its west threshold; s: to its
  right, south: `ESC.rw` / `ESC.rwPoint`.)

## 6. The Lua (Scripts/sv_escort.lua; CFG.specials.escort, CFG.allies.carrier, CFG.shop.items.ZfaCarrier)
Built 2026-11-06 on branch feature/zfa44 against the build contract of 2026-11-06 (unit, path, record and name-key names);
not yet run in game. None of it is a hard rule until a test confirms it.

**The special kind `escort`** (SPC.kinds.escort; the host's or solo):
- In CFG.specials.rotation from `from_round` 9, once a run (`once`, RUN.escort); `ready` only when SV_UnitAlive answers
  for every one of its five units (-2, "no such unit", for any: never picked, said once), so a build without them never
  draws it. Its round's budget x `budget_x`; not a "fly alone" special: the round's fighters come as usual.
- Spawn: CHARLENE (SV_Unit_Charlene) at `start` (heading 055), the escorts beside her (`side` / `back` x side_m /
  back_m), each one's route record `<rec>Go` go_delay_s later. Her health x `health_x` (scaleHealth); the escorts are the
  STORE's allied aircraft (ALLY.unit "air": scaled as MOONCHILD, repaired between rounds, their kills the allies').
- Attackers (`attack`): of the round's fighter flights up after_s (not an ace squadron's, a bomber, the jammer's, a raid
  escort, a held Wolf trap), `share` (at most `max` at once) get each plane's EngagementOrderOverride onto her (Normal,
  TargetFirst), again every again_s; `ESC.holds(unit)` keeps them out of the squad director (sv_director.lua `busy`: cover,
  salvo, top cover, regroup), co-op's split hunt (sv_coop.lua) and the allies' hunt and VOID WATCHER 1's strike flight
  (sv_allies.lua). Back on you (PlayerOnlyNoLimit; else RE_SV_FlightOrders_NN) at her touchdown or loss.
- The round's flights spawn ahead of her (`ahead`: DIR.spawnAt wrapped, `share` of them, km ahead of her heading within
  side_km), and waves come at her until she touches down (`waves`, 2026-11-07, the user: "Keep spawning Multiple enemy
  fighters until she lands, have them range from 4 to 12 aircraft spawning per wave in different directions"): every
  every_s (the first first_s after her spawn) min_n .. max_n aircraft of free pool flights (2-, 4- and 6-ships; one shot
  down flies again), all from one of eight directions round her (ahead, ahead right, ... ahead left; never the last
  wave's nor one next to it), km out, spread_deg apart, alt_m up, facing her; held while max_up enemies are up; each
  always goes after her. Log `escort: wave N: A aircraft (W asked, LO-HI[, max_up M for the room]) <side> of CHARLENE,
  from the <compass>, K km out: ...`, `escort: wave N held: ...`.
- Co-op (`coop_scale`, 2026-11-09, the user: "With the enemies in escort charlene, we need to scale the enemies by
  players"): in the host's room attack.max (her attackers at once) and the waves' min_n, max_n and max_up grow as a
  round's aircraft do (ESC.roomMore -> COOP.more: [coop] aircraft_per_player more for each player past the first; max_up
  within [coop] max_up, 30). With the shipped 0.15 and 4 players: 6 attackers, waves of 6-17, up to 30 up (solo 4, 4-12,
  24). The round's own flights were already scaled (sv_rounds.lua startRound). Solo and joiners: as set. The wave picker
  and ESC.roomMore are in sv_escort_waves.lua (sv_escort.lua's 2,000-line limit).
- The escorts (`guard`): every every_s each escort's planes onto an enemy within km of her (EngagementOrderOverride on an
  allied plane onto an enemy: **[test]**, COOP.coverFor's way).
- Landing (`landing`, `geo`), each step its record `<rec><Final|Roll|Taxi|Stop>`: her final within final_at_m of the IAF
  (or past it, or route_max_s on), gear down (`EnableLandingGear(true, 0)`), the escorts' `<rec>Orbit`, landing closed to
  the players (RE_SV_AirfieldClose; held while a player is on the airfield; not when the airfield's own logic has it
  closed); obstacle avoidance off within avoid_off_km of the touchdown; rollout within roll_at_m of the touchdown point
  (or past it under 20 m), invincible; taxi near the rollout's end (or slow near it, or roll_max_s on); stop near her
  parking spot (taxi_max_s, or stopped 3 s); landed when under landed_kmh for landed_hold_s (or stop_max_s on). The
  escorts: one released at a time once the runway's clear (nobody on final, rolling or inbound) and release_gap_s after
  the last; a released one takes its final once the IAF is within ahead_deg of its nose (or inbound_max_s on), then as
  hers, its parking spot `stop_t` / `stop_s`. Safety: land_timeout_s after a final, counted landed (taken off if still
  flying); max_s for the whole escort. Times count only while the world runs (not while you're down at the airfield
  with nobody else flying).
- The end: her death fails the special (callout, LB.special false, no pay, no unlock; the run goes on); everyone left
  landed (an escort shot down is out, not waited for) wins: reward + reward_per_round x the round (a co-op special's
  share), LB.special true, RUN.zfa unlocked, landing open again, her subtitle as callouts (CHARLENE / the text, cut at
  words to subtitle_chars: the big callout; the subtitle strip another branch is adding can take
  CFG.specials.escort.subtitle whole). The round is held (`busy`) until then; at its end (`over`) every one is switched
  off (no box or lock, invincible, inactive, hidden, no collision or tick; joiners' copies down first, COOP.removeNow) and
  its unit taken off the spawner's list 2 s on (SV_Recycle(unit, 1)). `remove_records` true also fires `<rec>Remove`.
- NEXT row (`row`): `CHARLENE 85%  23.4 KM  LANDED 0/5`, then `CHARLENE LANDING  LANDED n/5`.

**The ZFA-44 carriers** (the host's or solo; a joiner's STORE asks the host):
- The STORE item `ZfaCarrier` ("VAMPIRES": the user's name, 2026-11-07; 15,000 Z, raise 1.0), only once unlocked; at most `max_up` 2 out.
  STORE_PAGES has no free row (every page holds 6), so until the build gives it a row of its own it shares
  `store_row` "Revive" (the AIRFIELD page's revive row, a dead row solo and in co-op while nobody's down; label
  "VAMPIRES"): sv_shop.lua `offer` asks ESC.rowItem; a revive to buy takes the row back.
- Bought: one of SV_Unit_Cargo1 / 2 spawned (its world-data spot); its hull recorded as it spawns (NotifyOnNewObject
  LiveAIGameObject while spawningUnit is a cargo unit, a "ctslf" name that isn't a "cntus").
- Launch (`launch` "container"): first_s after it's on station its next launcher arm's record (`launchers[ship][n]`:
  { record = RE_SV_CargoLaunch_<s>_<n>, unit = the world-data unit that arm launches }, defaults E_Unit_01_drone_<s>_0 /
  _1: the names come with the build); an arm's unit launched before is taken off the spawner's list first (hard rule 16).
  A plane that appears with no unit (its launcher spawns it), or as its ship's, within capture_km of the ship is taken as
  that flight's (logPlane wrapped, on every game). A ship whose record fired but whose flight showed no plane in
  launch_wait_s launches by "pose" from then on: its `pose_units` flight (SV_Unit_ZfaA / B) spawned ahead_m off its bow,
  alt_m up (the ALICORN's deck's way). Relaunch relaunch_s after its flight is down (no live plane, SV_UnitAlive 0).
- Service (`service`): a round counted as it clears with the ship up min_s of it; after `rounds` 3, in the break, its
  flight and the ship are switched off (COOP.removeNow first, `remove_records`: RE_SV_Cargo<n>Remove too), its unit
  recycled 2 s on; sold again. A ship sunk: called out, gone, its flight flies on.
- Every game dresses its own planes of those flights as the ZFA-44 (`zfa`: sv_zfa44.lua ZFA.dress, paint 3, two a tick;
  ZFA.prodTick hides the host's meshes again every hide_s). Without SK_ZFA44 (every zip: the container is the user's dev
  builds only, and packaging cuts sv_zfa44.lua to its first line) they fly as their host airframe, said once.
- The ALLIES row adds `VAMPIRES n`. The ships keep "ZFA-44 CARRIER" on their boxes and callouts.

**Co-op**: every unit is an ally (ALLY.unit; sv_coop.lua allyUnit: copies' hits aren't a joiner's). The host sends
`es|<state>|<landed>|<of>|<her health %>|<km>|<unlocked>|<carriers out>|<landing closed>` on a change (once a second at
most) and every 5 s; a joiner keeps it (ESC.onHost): the room's unlock (RUN.zfa.room), the carriers out for its STORE,
its NEXT row (sv_hud.lua, ESC.clientRow), its own landing closed / open. A joiner's carrier purchase is asked of the host
(`ab|..|ZfaCarrier`), checked at the room's price (shopBuildFor), counted in RUN.bought (rnd field 14: M.ROOM_ITEMS);
host migration's ally list carries `ZfaCarrier:<buyer>` (rebuilt by a new host). The records are forwarded (RE_SV_*): a
joiner's copy of a cargo ship fires its own launch, so its ZFA-44s are its own planes, dressed and taken as allies there
(not copies of the host's) **[test]**.

**Leaderboard**: LB.special("escort", ...) is sent with the run; the Worker's SPECIALS (leaderboard/src/index.js) doesn't
know "escort" yet and drops it before the score (add `escort: "The Escort"` and redeploy).

## 7. Keys (test builds only: TEST ONLY blocks, stripped from every zip; each press makes the run unranked)
- **Ctrl+0**: the next round is THE ESCORT (in the break: in 3 s). A build without its units logs it and flies a normal
  round.
- **Ctrl+F5**: the landing test T0: CHARLENE alone test.before_m (1500) short of the IAF on heading 067 (her final's
  start a little ahead: hard rule 2), invincible, her final at once, rollout, taxi and stop; no enemies sent at her, no
  escorts; the break held while it runs; taken off test.end_s (30) after she's down.
- **Ctrl+DEL**: the ZFA-44 carriers unlocked and one sent now (free).
- (Were Ctrl+F1 / F2 until 2026-11-07: the tactical items' airstrike and ECM burst keys, so both ran on a press. Every
  Ctrl key: tools/README.md "Ctrl keys".)
- (Ctrl+9 stays the ZFA-44's T0 dressing of the nearest enemy, docs/re/ZFA44.md 8.)

## 8. Log lines (AC8SurvivalMode_lua.log)
- `escort: round N, THE ESCORT: CHARLENE and 4 escorts from (-41.1, 31.4) km to the airfield (67.5 km)`,
  `escort: <NAME> (<unit>) spawned at (...) km, 3.0 km up, yaw -35: 1 aircraft | NOT spawned (...)`,
  `escort: CHARLENE up: her health x4.00 (a -> b)`, `escort: <NAME> route: <rec>Go fired; t .. m, s .. m, .. m up, .. km/h,
  heading .., .. km from the airfield`
- `escort: <unit> sent after CHARLENE (n of m planes, Normal / TargetFirst onto her)`, `escort: <unit> off CHARLENE (<why>):
  n planes back on you`, `escort: more enemies: <unit> (n aircraft) 14.0 km ahead of CHARLENE (...)`, `escort: guarding
  CHARLENE: YORKE onto <plane> (.. km from her), ...`
- `escort: <NAME> <final|orbit|roll|taxi|stop> (<why>): <record> fired; <where>`, `escort: <NAME> gear down:
  EnableLandingGear(true, 0) done`, `escort: CHARLENE .. km from the touchdown: obstacle avoidance off (...)`,
  `escort: landing closed for the players (CHARLENE's landing): RE_SV_AirfieldClose fired`, `escort: <NAME> released for its
  landing (n of 4; the runway's clear)`, `escort: <NAME> landed (stopped | the safety timeout: counted as landed[, taken off:
  it was still flying])`, `escort: <NAME> shot down`, `escort: <NAME> lost (...)`
- `escort: round N, the escort WON: l of 5 landed (x lost), s s; +P zollars; CHARLENE: "<the line>"; the ZFA-44 carriers
  unlocked in the STORE` / `escort: round N, the escort FAILED: CHARLENE is down (...)`, `escort: <NAME> taken off (its round
  over): n planes switched off`, `escort: <unit> off the spawner's list (...): SV_Recycle 1`
- T0: `escort: T0: CHARLENE at the approach fix ...`, `escort: T0 +12.5 s: CHARLENE final: t -2310 m, s 4.0 m, 210.0 m over the
  runway (z 21750 cm), 286 km/h, pitch -3.0, roll 1.0, gear down[, avoidance off]` every 0.5 s, `escort: T0: her rollout began
  N m past runway 07's west threshold (the test's pass: 150-600 m)`, `escort: T0 over (...) after N s: stopped | timeout`
- `escort: no ESCORT special in this build: its units aren't in the world data (...)`, `escort: N of 8 name texts set`,
  `escort: the escort's state sent to the joiners: <key>`, a joiner's `escort: the host's escort was won: the ZFA-44 carriers
  are in the STORE here too (the room's)`
- Carriers: `carrier: ZFA-44 CARRIER i (<unit>) on station[ for player N]: its ZFA-44s launch in 20 s (...)`, `carrier:
  <unit>'s hull <name>`, `carrier: ZFA-44 CARRIER i launches its ZFA-44s: RE_SV_CargoLaunch_i_n fired (container arm n,
  <unit>)`, `carrier: a plane of <unit | no unit> near a carrier ship taken as its ZFA-44 flight's (<unit>)` (once),
  `carrier: ... ZFA-44s are up (<unit>, n planes seen)`, `carrier: ...: <record> fired N s ago and no plane of <unit> came:
  launched by pose from now on`, `carrier: ... launches its ZFA-44s by pose: SV_Unit_ZfaB, 4 aircraft 300 m off its bow,
  1100 m up`, `carrier: ...'s ZFA-44 flight <unit> is down: another in 30 s`, `carrier: ...: <unit> launched before: taken off
  the spawner's list first (SV_Recycle 1)`, `carrier: ... has served n of its 3 rounds`, `carrier: ... leaving after 3
  rounds: ...`, `carrier: ... gone (...): off the spawner's list (SV_Recycle 1)`, `carrier: ... sunk ...`
- Dressing: `zfa44: dressed <plane> (<unit>) as the ZFA-44 (n so far): placed on <body>, paint 3 GEAR, FLAT NORMAL: ...; n of
  its meshes hidden`, `zfa44: NOT dressed: ... not loaded ...: the ZFA-44s fly as their host airframe` (once),
  `carrier: no ZFA-44 dressing in this build (sv_zfa44.lua cut ...)` (once).

## 9. Test checklist (in game)
1. **T0 first (Ctrl+F5, in a break)**: no crash; `escort: T0 +...` lines every 0.5 s; she descends on the glide slope
   (height falling ~50 m a km), gear `down`, touches down 150-600 m past the west threshold (`her rollout began N m`), holds
   z 7.5 m (`... m over the runway` near 0) rolling, slows to the turn-off, taxis to the hold spot, stops (`T0 over (...):
   stopped`). Watch for a pull-up or bounce (avoidance off at 3 km), floating or sinking (RootHeight), the gear meshes.
2. A run to round 9 (or Ctrl+0): the callout, her and four escorts at the south-west corner, names on their boxes, all on
   their route paths; `sent after CHARLENE` lines and the flights really going for her (no `cover on` / `RE_SV_Hunt` line
   for them in co-op); enemies spawning ahead of her; her health holding a while (health_x).
3. Her final at the IAF (gear, orbit records, landing closed: the player can't land), the escorts circling, her landing
   as in T0, then each escort released and landing one at a time; the round not ending before.
4. Win: ESCORT COMPLETE, the pay, her line in two callouts, landing open; the AIRFIELD page's revive row now `VAMPIRES
   15000 Z` (solo, or co-op with nobody down).
5. Loss (let her die): CHARLENE IS DOWN, no unlock, the run goes on, the round ends with the enemies.
6. A carrier: on station at its spot, its launcher arms firing (`RE_SV_CargoLaunch_1_1 fired`) and the planes coming
   off it (else `launched by pose`), dressed as the ZFA-44 in a dev build with ZFA=1, fighting; a flight shot down, the
   next launch 30 s on; 3 rounds, then leaving; the ALLIES row's count.
7. Co-op: joiners see her, the escorts and their landing (copies), the unlock and the carriers in their STORE (asked of
   the host), the same NEXT row, their landing closed during hers; the ZFA-44s on their screens (their own launches).

## 10. Names the Lua needs that the contract doesn't give
- `RE_SV_CargoLaunch_<s>_<n>` (the coordinator's change of 2026-11-06) and each arm's launched unit
  (CFG.allies.carrier.launchers; defaults E_Unit_01_drone_<s>_0 / _1): set them to the build's at merge.
- Optional, off by default (`remove_records`): `RE_SV_CharRemove`, `RE_SV_Esc<Name>Remove`, `RE_SV_Cargo<n>Remove`.
- The STORE row `ZfaCarrier` on a page of its own (tools/build_survival.py STORE_PAGES; every page is full): until then
  it shares the revive row (CFG.allies.carrier.store_row).
- CFG.specials.escort.geo and the escorts' stop_t / stop_s follow route.json and the research's taxiway spots: set them
  to the built paths' points if they differ.

## Build names (built 2026-11-06 on feature/fishing; nothing run in game)
What tools/build_survival.py (`escort_units`, `cargo_units`, rows) and tools/survival_events.py (`build_escort`; the data:
its "THE ESCORT (CHARLENE) and THE DECOY" section) build for the escort contract of 2026-11-06. Lua spawns every unit and
fires every remote event; nothing spawns at the level's start. The build reads it all back from the saved packages
(`check_escort_decoy_build`) and fails on any difference. Coordinates UE cm (north -Y, east +X); the runway frame is
COMONA_MAP.md 6's: t m along runway 07/25 from the paved mesh's origin (1609740, -435830) (+ ENE), s m across it (+ SSE).

### Rows
| Row | Table | What |
|---|---|---|
| `sv_charlene` | DT_SV_NpcMission (Mission 22's `e767_common` shape: KeepMinHeight 0, as VOID WATCHER's) | NpcId the stock `OP0008_b01b_Ally_01` (NLID_1000, flares, bombs; nothing to add), MaxHealthDifference +170 (130 -> 300 HP) |
| `sv_esc_su57` / `sv_esc_su33` / `sv_esc_su35` | DT_SV_NpcMission (`f18e_common` shape, MOONCHILD's) | NpcId `SV_Esc_Su57` / `SV_Esc_Su33` / `SV_Esc_Su35` |
| `SV_Esc_Su57` / `SV_Esc_Su33` / `SV_Esc_Su35` | DT_SV_NpcRows: **Lua adds them to DT_NPC at the main menu** | copies of the plain `OP1021_su57_01` / `OP1030_su33_01` / `OP1028_su35_01` on the allied models `OP1021_su57_Ally` / `OP1030_su33_Ally` / `OP1028_su35_Ally` (no skin row), LuaSet `NLID_0003_CP` (MOONCHILD's row's set; never NLID_0400_CP), their flares, gun, missiles |
| `sv_zfa_ally` | DT_SV_NpcMission (`f18e_common` shape) | NpcId `SV_Zfa_Ally` |
| `SV_Zfa_Ally` | DT_SV_NpcRows: **Lua adds it** | the ZFA-44 host: the plain Su-47 `OP1026_su47_01` on `OP1026_su47_Ally`, NLID_0003_CP, every speed / turn coefficient 1.0 (the plain row's 0.8), hit spheres x1.25 kept, GameObjectDisplayName02 `SV_Zfa44`. Why the Su-47: the airframe nearest the ZFA-44's size (22.6 x 15.2 m against 24.0 x 14.6 m) and the one AC7 gave the ZFA-44EL's flight table (the False Mihaly Su-47's) |
| `sv_cargo_a` / `sv_cargo_b` | DT_SV_NpcMission (Mission 17's `VE021_ctslf_01` / `_03` whole) | the stock DT_NPC rows (MaxHealth 75; their Stinger mount's row `GR032_ctslf_0N_stgr` through the hull row's ChildNPCId: hard rule 38) |

Text keys Lua sets with SV_SetText: `SV_Charlene`, `SV_Yorke`, `SV_Rock`, `SV_Ali`, `SV_Danielle` (each aircraft's callsign
on its box), `SV_Cargo` (both ships), `SV_Zfa44` (every ZFA-44 host: desc callsign and its DT_NPC row's name).

### Units
| Unit (SV_Spawn's name) | Objects (event args) | Row | Side, flags | World data spot / notes |
|---|---|---|---|---|
| `SV_Unit_Charlene` | `SV_Obj_Charlene` | sv_charlene | ally; Mission 14's escorted C-130 desc (unit bIsEscortedUnit, the Attention mark, callsign shown, visible at any distance), its wing parts left out, box | the start (-4110000, 3140000, 300000), yaw -34.9 (heading 055); area 80 km, 0-12 km |
| `SV_Unit_EscYorke` / `EscRock` / `EscAli` / `EscDanielle` | `SV_Obj_EscYorke` ... | sv_esc_su57, su57, su33, su35 | ally; MOONCHILD's lead's desc, not invincible, box, callsign | their routes' starts: 0.6 km right / 0.6 left (+100 m), 1.2 right / 1.2 left (+250 m) of hers; area 80 km |
| `SV_Unit_Cargo1` / `SV_Unit_Cargo2` | `SV_Obj_Cargo1` / `2`, parts `SV_Obj_Cargo1_BP_VE021_ctslf_cntus_01_CP`, `..._cntus_02_CP`, `..._BP_VE021_stgr_Base`; ship 2 `SV_Obj_Cargo2_BP_VE021_ctslf_cntus_02_CP`, `..._cntus_03_CP`, `..._stgr_Base` | sv_cargo_a / b | ally (Mission 17's container ship desc made Faction 1, random group cleared), box, callsign | (1270476, -1096142, 50) 7.4 km NW of the runway, 6.4 km from land; (2130476, 103858, 50) 7.5 km SE, 5.0 km from land (both 3+ km from the fishing grounds and SAL); yaw -23; area 45 km |
| `E_Unit_01_drone_5_0`, `_4_0`, `_0_0`, `_1_0`, `_7_0`, `_8_0` | `SV_Obj_ZfaShip1ArmA_0` / `_1` ... `ArmF_0` / `_1` | sv_zfa_ally | ally (Mission 17's drone unit desc made Faction 1), box, callsign SV_Zfa44, 2 a unit | ship 1's launcher arms WN_WEAPON_1..6 in that order; parked under ship 1 at z -245 m (Mission 17's); area 40 km |
| `E_Unit_01_drone_3_1`, `_4_1`, `_1_1`, `_2_1`, `_6_1`, `_7_1` | `SV_Obj_ZfaShip2ArmA_0` / `_1` ... `ArmF_0` / `_1` | sv_zfa_ally | the same | ship 2's arms WN_WEAPON_1..6 |
| `SV_Unit_ZfaA` / `SV_Unit_ZfaB` | `SV_Obj_ZfaA_0` .. `_3` / `SV_Obj_ZfaB_0` .. `_3` | sv_zfa_ally | ally, MOONCHILD's desc (a lead and three wings), box, callsign | the pose-spawn fallback: 300 m over ship 1 / 2, 60 m apart |

The launch units must have exactly these names: each container launcher arm (LiveFCSModule_ProjectileSpawnerFromWorldData)
names one world-data unit, and the arm spawns it when fired (Mission 17's are not spawned at its level's start). The build
reads the arms from the stock blueprints (build/stock/Blueprints/Vehicle/AI/Vessels/VE021_ctslf/CP/BP_VE021_ctslf_cntus_0N_CP,
pulled with tools/get_stock.sh, not on build_all.sh's list) and builds the units from them. The three launcher variants name
18 different units, 6 each, and a ship carries two (its hull's components: VE021_ctslf_01 has cntus_01 + 02, _03 has 02 + 03):
**ship 1 fires only cntus_01, ship 2 only cntus_03**; cntus_02, on both, is never fired and has no units (the same arm on
both ships would pull the same unit). 2 ZFA-44s an arm (the arm's magazine is 5, its fire a Salvo: whether it launches 2 or
holds for 5 is untested), 6 arms a ship, 12 two-ships in all; an arm fires again only after its unit is off the phase's
unit list (SV_Recycle, hard rule 16).

### Paths (smooth ControlType 1 in the air; the runway's on MOONCHILD's roll / taxi path shape at z 750)
- `SV_Path_CharRoute`: the start to 1.5 km short of the IAF, 11 points, straight over open sea at heading 055, 3 km down to
  0.9 km; its end tangent toward the IAF. `SV_Path_EscRoute_<Name>`: the same, offset to her sides (above).
- `SV_Path_CharFinal` (everyone's): the IAF (96254, 206608, 846 m: 16 km before touchdown on the extended centre line)
  down 3.00 deg to touchdown (1569054, -418560, 7.5 m: t -442, 300 m past the west threshold), 14 points, the last 150 m a
  flare.
- `SV_Path_CharRoll` (everyone's): the centre line from t -402 (40 m past touchdown) to t +638 (120 m short of the east
  threshold), 9 points.
- `SV_Path_TaxiSlotA` .. `E`: from t +660 on the centre line, MOONCHILD's taxi path backwards (its U-turn off the east end
  onto the parallel taxiway, its hold spot t +693 s +62.5), then west along the taxiway (s 62.5) to the slot: A t +90
  (1620467, -433593), B +170, C +250, D +330, E +410 (1649923, -446097), each 38-52 m from every building or prop box.
  `SV_Path_StopSlotA` .. `E`: 3 m past the slot, 18 m on west (Mission 26's 18 m stop path). Slots are taken in landing
  order (the first lander the farthest west), so nobody taxis past a parked aircraft whatever order Lua lands them in.
  These replace the contract's single `SV_Path_CharTaxi` (one shared taxi path would park all five on one spot).
- `SV_Path_EscOrbit_<Name>`: the escorts' wait, one path each (not the contract's one `SV_Path_EscOrbit`): a 6 km circle
  1.2 km up, touching the extended centre line at (-271946, 362900) (20 km before touchdown, 4 km before the IAF) along
  heading 067, its centre (-506384, -189400) to the north, flown anticlockwise on the map; 8 laps in the path (no
  handover: rule 54), each escort's begun 90 deg further round (Yorke 90, Rock 180, Ali 270, Danielle 360 = the touching
  point) so they pass the touching point about a minute apart. Release an escort onto the final (its Final record) as it
  nears the touching point heading 067: the final's start, the IAF, is then 4 km ahead (hard rule 2). Not over the
  airfield as the contract has it: the final starts 16 km west of the runway, so an escort released from a circle over the
  airfield would fly back to the IAF and turn round onto it.

### Records (EP_SurvivalMode_global; survival_events.build_escort). Lua fires every RE_SV_*.
For CHARLENE (`RE_SV_Char<Step>`) and each escort (`RE_SV_Esc<Name><Step>`, Name Yorke Rock Ali Danielle):

| Step | Does (speeds km/h) |
|---|---|
| `Go` | gear up, her engagement None / theirs Normal + air search, visible and not invincible, the route at 600 (Mission 16's Ladon path record); hers also sets SV_EscortSlots 0 |
| `CruiseSlow` (extra) | the route again at 450 (a path given again goes on along it: Mission 14's speed control) |
| `Orbit` (escorts) | off its path, its area back to 80 km, its orbit at 500 0.1 s on |
| `Final` | gear down (0.5 s), the final at 320, accel 30 (Mission 14's descent record); an escort first off its path, engagement None, area 80 km, the final 0.1 s on (Mission 26's switch) |
| `FinalSlow` / `FinalShort` (extras) | the final again at 280 (from 6 km) / 260 (from 2 km) |
| `Roll` | the rollout at 50, accel 2.7 (Mission 14's touchdown record), engagement None, gear down, invincible (her Attention mark kept) |
| `Taxi` | once: the next free slot's taxi path at 30 (SV_EscortSlots 0..4 -> slot A..E, 5+ -> E), the slot in SV_TaxiSlot<Who> (1..5), SV_EscortSlots + 1 |
| `Stop` | its slot's stop path at speed 0 (Mission 26's Baxter_Stop_0) |
| `GearDown` | LiveEnableLandingGear true (MOONCHILD's hold record) |
| `Guard` (escorts, extra) | off its path, Normal, air search, its unit area onto SV_Obj_Charlene (Mission 22's LiveUnitMoveActor) at 3 km (Mission 6's LiveChangeUnitRadius): Mission 14's way of keeping units on its C-130; fire it every few seconds while she's attacked |
| `Remove` (extra) | Mission 22's despawn (LiveSetActiveGameObjectExecution false on the unit), then SV_Recycle |

Each step sets its leg flag: `SV_CharLeg` (1 route, 2 final, 3 roll, 4 taxi, 5 stop) and `SV_EscLeg<Name>` (1 route,
2 orbit or guard, 3 final, 4 roll, 5 taxi, 6 stop): Lua can read where each aircraft is (5 / 6 = stopping on its slot).
Backstops (PathFinish triggers `SV_<Who>End<Path>`, hard rule 1): the end of a route starts her Final / an escort's Orbit,
the end of the final starts the Roll, the rollout's end the Taxi, a taxi path's end the Stop, an orbit's end the orbit
again, each only while the leg flag says Lua hasn't moved that aircraft on (read as the PathFinish fires: hard rule 26).
`RE_SV_EscortReset`: every leg and slot flag back to 0 (before a landing test without her). Appearances `SV_CharUp`,
`SV_EscUp<Name>`: gear up, her engagement None (theirs Normal, air search), visible, not invincible.
Gear: the Final, Roll and GearDown records lower it (the stock way); Lua's EnableLandingGear(true, 0) is the backstop.

Cargo ships: `SV_CargoUp1` / `2` (appearance): the hull's engagement Normal (Mission 22's ship order), the Stinger mount's
Normal / Default. `RE_SV_CargoLaunch_<s>_<n>` (s 1 / 2, n 1..6): Mission 17's LiveFireOneShotWeapon {WN_WEAPON_n, the
ship's launcher (`SV_Obj_Cargo1_BP_VE021_ctslf_cntus_01_CP` / `SV_Obj_Cargo2_BP_VE021_ctslf_cntus_03_CP`), NoneSelect,
NoneSelect, false, "", false} (Mission 17 fires its launchers so, no target), then at 6 s and 10 s the launched unit's
orders: gear up on each, Normal, air search. `SV_ZfaUp<s><L>` (L A..F = arm n): the same orders as a launch unit appears.
`RE_SV_CargoRemove_<s>`: the ship off (Mission 22's despawn). The fallback: `SV_ZfaUpA` / `B` and `RE_SV_ZfaGoA` / `B`:
gear up, Normal, air search.

Int flags: `SV_CharLeg`, `SV_EscLeg<Name>`, `SV_TaxiSlotChar`, `SV_TaxiSlot<Name>`, `SV_EscortSlots`.
140 triggers, 723 execs.

### Lua to-do the contract doesn't say
- Add `SV_Esc_Su57`, `SV_Esc_Su33`, `SV_Esc_Su35`, `SV_Zfa_Ally` (DT_SV_NpcRows) to DT_NPC at the main menu, as the STORE's
  ally rows are (sv_allies.lua ROWS): without them those units don't spawn.
- Set the seven text keys above.
- Land them in any order; release escorts from the orbit at its touching point; fire `RE_SV_EscortReset` before a round.
- A STORE MOONCHILD or VOID WATCHER takes off westward on the same runway from the hold spot the taxi passes: hold them
  while the escort round lands.
- The STORE pages are build data and all six are full (6 rows each): a cargo ship row needs a build change (a page or a row
  given up), not done here.

## Lua wired to the build (2026-11-07, branch feature/decoy; nothing run in game)
The build agent's to-do list and the gaps between the two sides, done in Scripts/sv_escort.lua (and its CFG, sv_allies.lua,
sv_main.lua); tools/checks/escort_test.sh covers each. Not a hard rule until a test confirms it.
- **Rows and names at the main menu** (ESC.setup, sv_main.lua's setup pass after FISH.setup; every game): `SV_Esc_Su57`,
  `SV_Esc_Su33`, `SV_Esc_Su35` (CFG.specials.escort.dt_npc) and `SV_Zfa_Ally` (CFG.allies.carrier.dt_npc) from
  DT_SV_NpcRows into DT_NPC; the seven texts (SV_Charlene, SV_Yorke, SV_Rock, SV_Ali, SV_Danielle, SV_Cargo "ZFA-44 CARRIER",
  SV_Zfa44). `escort: the escorts' and the ZFA-44's rows: ... in DT_NPC`. Without the escorts' rows no ESCORT round
  (`escort: no ESCORT round: its escorts' DT_NPC rows aren't in (...)`); without SV_Zfa_Ally no carrier is sold.
- **RE_SV_EscortReset** before each operation's spawns and before T0 (`escort: RE_SV_EscortReset fired: ...`); the build's
  flags are read (svFlags) only from a read 2 s or more after it.
- **The build's flags**: each tick the legs (SV_CharLeg / SV_EscLeg<Name>) are read; one ahead of the step Lua has (a
  PathFinish backstop moved the aircraft on) is taken with Lua's own step's gear / invincibility / slot (`escort: <NAME>
  <step> (the build's backstop moved it on: <flag> N; it was <step> here)`); an escort's leg 2 while Lua's Guard has it
  is its cover, not its orbit. The parking slot is the build's: counted here in landing order as each taxi begins (A for
  the first lander), SV_TaxiSlot<Who> taken once it can be read (`escort: <NAME>'s parking slot D (the build's ...)`);
  the stop is called within stop_at_m of that slot's point (CFG geo.slots: the ends of SV_Path_TaxiSlotA-E, metres along
  runway 07 from its west threshold, the build's t + 742). geo.hold and the escorts' stop_t / stop_s are gone.
- **The escorts' cover**: from the first enemy within guard.km of her, each escort on its route (or an orbit its route's
  end began) also gets `<rec>Guard` every guard.record_every_s (6) while she flies her route (`escort: <NAME> covers
  CHARLENE (...Guard ...)`), so its area follows her; never once she's on final.
- **Her slow-downs**: `RE_SV_CharCruiseSlow` within landing.cruise_slow_km (25) of the touchdown (and each escort still on
  its own route, not covering her); every final's `<rec>FinalSlow` within final_slow_km (6), `<rec>FinalShort` within
  final_short_km (2).
- **The escorts' release** (escortsTick): at her final every escort not already waiting gets `<rec>Orbit` (its
  SV_Path_EscOrbit_<Name>); with the runway clear and release_gap_s since the last, the first one within landing.touch_m
  (2500) of geo.orbit_touch (-271946, 362900, 1.2 km up) heading within touch_deg (35) of geo.heading 067 gets its Final
  there (`escort: <NAME> released for its landing (n of 4; the runway's clear): at its orbit's touching point (...), the
  approach fix 4 km ahead`); none there in orbit_max_s (330, about a lap and a quarter) of a clear runway: the old way
  (inbound, its final once the approach fix is within ahead_deg of its nose).
- **The runway held**: ESC.runwayBusy() (her landing, from her final until everyone left is down; T0 too) holds MOONCHILD's,
  SNIPER's and VOID WATCHER 1's take-offs (sv_allies.lua ALLY.escortHold: `allies: <name>'s take-off held: THE ESCORT is
  landing ...`, then `allies: the runway's clear of THE ESCORT: the take-offs go on`).
- **The carriers**: CFG.allies.carrier.launchers are the build's six arms a ship (ship 1 `RE_SV_CargoLaunch_1_1..6` ->
  E_Unit_01_drone_5_0, 4_0, 0_0, 1_0, 7_0, 8_0; ship 2 `RE_SV_CargoLaunch_2_1..6` -> 3_1, 4_1, 1_1, 2_1, 6_1, 7_1); the next arm
  in turn whose unit has nothing alive is fired, its unit taken off the spawner's list first when it's still on it (an
  earlier carrier's launch too: hard rule 16); a downed flight's unit is recycled 2 s on. The pose fallback fires
  `RE_SV_ZfaGoA` / `B` (pose_go) right after its SV_Spawn. ship_at (was `spots`, which build_valka's regex read as VALKA's
  and failed the build: `main.lua CFG.specials.valka.spots != VALKA_SPOTS`) is the ships' world-data spots. remove_records
  fires `RE_SV_CargoRemove_<n>` (was RE_SV_Cargo<n>Remove, not in the build).
- Every unit, record and path name these parts use was checked against the saved packages of `ZFA=1 sh tools/build_all.sh`
  (2026-11-07): all there.

## Code review of 2026-11-07: fixes (branch feature/decoy; nothing run in game)
Three reviewers checked each finding against the code; these are the ones in THE ESCORT and the carriers. Checks:
escort_test (each below), copy_floor_test (the co-op side), leaderboard_test's rotation mode, worker.test.mjs.
- **The escorts' sides** (finding 2): CFG's side signs put YORKE and ALI on her left, ROCK and DANIELLE on her right, 250 /
  500 m behind, all at her height, the opposite of the build's routes (survival_events.py ESC_ESCORTS: YORKE 0.6 km and ALI
  1.2 km to her right, ROCK and DANIELLE to her left, 100 / 250 m up, none behind), so at Go each crossed her track at 600
  km/h. Each escort's CFG entry now has `right_m` / `up_m` (600 / 100, -600 / 100, 1200 / 250, -1200 / 250) and startPose
  puts it right_m across the exact start -> geo.iaf line (the build's esc_route_pts) and up_m above her (start.side_m /
  back_m gone). escort_test reads ESC_START and ESC_ESCORTS from survival_events.py and checks each spawn within 1 m of
  its route's start, on the right side, none behind.
- **A sunk ship that stayed up** (finding 7): its unit's alive count holds its launchers and Stinger mount, so a ship whose
  hull sank held its slot and the STORE's count. carrierTick counts it sunk when its hull (ESC.hulls, liveAddr) is at
  HealthInternal 0, or gone after it was seen live: `carrier: <name> sunk N s after it came (its hull at 0 health; ...): N
  of its parts still up finished off, its unit off the list 3 s on`; its slot is held (state "leaving") until that
  recycle, so a ship bought meanwhile can't be taken off by it. A freed slot forgets its hull and objects (ESC.hulls /
  ESC.shipObjs), so the next ship of that unit is recorded afresh, never the old switched-off or sunk hull.
- **Co-op ZFA-44s on joiners** (finding 1; also ZFA44.md): the host's `RE_SV_CargoLaunch_<s>_<n>` stays forwarded (each
  joiner sees the launches), and each joiner's copy of the ship launches ZFA-44s of its own (no co-op id). Now
  ESC.localZfa() (every zfa-kind plane here: ESC.planes and the allies' list) goes into sv_coop.lua M.standInSet() as -1
  (the host's allies' copies), so their damage on an enemy copy is never sent as that joiner's "ht" (and M.floorLoss sends
  only what a copy's map doesn't explain when it shows another's hit: never the whole); before a forwarded launch fires
  on a joiner, ESC.beforeHostEvent takes the arm's unit off that game's list (SV_Recycle(unit, 1): from a ship's 7th
  launch its arm spawned nothing there) and switches that ship's last flight there off (`carrier: the host's
  RE_SV_CargoLaunch_1_2 here: E_Unit_01_drone_4_0 first (...); N of this game's ZFA-44s of ship 1 before it switched
  off`); "es" field 10 carries the ships up as bits, and a ship the host no longer has (left or sunk) takes the joiner's
  own ZFA-44s of it off (ESC.localOff: `carrier: the host's ZFA-44 CARRIER 1 is gone (...): N of this game's own ZFA-44s
  of it switched off, M of its arms' units off the list 2 s on`). An older host (no field 10): all of them once it has no
  carrier out. A bound copy of the host's pose flight (COOP.copyAt) is left to the host's "dn".
- **A restart mid-escort** (finding 3): ESC.restart(why), from sv_main.lua's level-load block before the new run's D: the
  operation's aircraft taken off as its round's end does (switched off, joiners' copies down first, unpaid, units off
  the list 2 s on), the players' landing opened again if she'd closed it, every carrier out taken off the same way, a
  joiner's own ZFA-44s off (`escort: <why>: N of the escort's aircraft and M carriers taken off, K of this game's own
  ZFA-44s off`). Before, ESC.tick dropped the old run's escort and carriers untouched: landing closed, CHARLENE and the
  ships up with nobody minding them, a ship's STORE slot held.
- **Parked allies exploding on joiners** (finding 13): at a won round's end, a carrier leaving, its flight (and VOID
  WATCHER 1 going home) the host's COOP.removeNow sends "dn|id|r", and a joiner's killCopy finished each allied copy off.
  Now an ally copy's "dn|id|r" switches it off there as the host does (no box or lock-on, invincible, inactive, hidden,
  no collision, no tick) and takes its unit off that game's list 2 s on once no copy of it is left (`coop: the host took
  an ally off (copy N, <unit>): switched off here, not finished off`, once).
- **The rotation line** (finding 14): the default ini's commented rotation now lists the specials in CFG's order after
  sv_config.lua's append (..., spaceport, escort, fishing, decoy), its note too; leaderboard_test's rotation mode
  uncomments it as shipped and finds nothing edited (LB.edited, COOP.cfgDiff).
- **The leaderboard** (finding 15): the Worker's SPECIALS has escort, decoy, fishing and festival (an unknown kind was
  dropped before the score): redeploy it.
- Open: the joiners' own ZFA-44s still fight the enemy copies there (for the look; nothing of it counts), and a forwarded
  destroy record that takes a copy before the host's "dn" arrives can still be paid there by the raw rule (not new).

## Who they are, what they say, and the Anomalies' wait (2026-11-07, Lua 0.74.6; nothing run in game)
The user: CHARLENE "is a Wealthy CEO who owns one of the worlds largest plane collections, she is from the KOKODA
MERCENARY GROUP, based out of Aurelia"; YORKE, ROCK, ALI and DANIELLE are KMG too, "they should each have a squadron tag
KMG". Their boxes read `[KMG] CHARLENE`, `[KMG] YORKE`, ... (CFG.specials.escort.tag / tag_format, set with SV_SetText
at the main menu).

Subtitles (Scripts/sv_escort_subs.lua, lines in CFG.specials.escort.text.say; the user: "Charlene, Yorke, Rock, Ali,
Danielle all should have their own unique Subtitles", "Give Charlene Unique Lines for Landing, Being Attacked, Being
Defended"). Speakers: the five by name, Comona's staff `C|` COMONA CONTROL, `T|` COMONA TOWER, `G|` CREW CHIEF (each its
colour, CFG.hud.subs.colors). ESUB.tick (each escort tick, from ESC.step) says what changed:
- her spawn: one of three check-ins (CONTROL, CHARLENE twice, each escort once);
- the first enemies sent at her (first_attack, once the check-in is through), each wave sent at her (`wave`, {dir}: the
  compass point it comes from, S.reinf.dir), her health down hit_drop points in hit_window_s (`hit`), under 75 / 50 / 25%
  (`hurt_<n>`);
- an enemy within defended_km of her shot down (KILL.by): her escorts' / an ally's (`defended_ally`), a player's
  (`defended_you`), Comona's guns (`defended_staff`), once in defended_gap_s;
- her final (TOWER clears her), touchdown, landing; each escort's own landing line (not a timeout's) and its own last
  words when shot down, then the reply naming it; nobody speaks for one who's down;
- the win: her thanks (the user's exact `subtitle`) on the strip, cut after its commas into lines of at most
  thanks_chars, then Comona's line on the ZFA-44s (VAMPIRES in the STORE); no callout of her thanks any more (the strip
  off: callouts as before). The ESCORT COMPLETE banner with the pay stays a callout, as every special's;
- her loss: her last words, then CONTROL or YORKE.
Pool lines (waves, hits, defended, first_attack) are said only while the strip has room (busy_s); exchanges always.
A co-op host's lines go to the joiners as every SUB.say does ("sb").

The Anomalies wait for her (CFG.specials.anomaly_gate; the user: "Anomaly Rounds shouldn't start until Charlene arrives
at the airbase btw, That Includes, Valka, Mindripper, Abelcain" and the lightning Anomaly): specialReady (sv_spawn.lua)
asks ESC.anomalyOk, false for MINDRIPPER, AB.L..IN and VALKA (and a special whose settings say wait_for_charlene) until
RUN.escort.arrived (her landed()). No wait when THE ESCORT can't come (off, out of the rotation, its rows or units not
in); after_lost (default true): once she's shot down they come anyway. A test key's forced round never waits.
Her warning (the user: "the round before an Anomaly Round appears, a Subtitle from Charlene ... (she will not be able to
warn players about VALKA though)"): at each round's end (sv_rounds.lua, after "round n clear") ESUB.warnNext draws the
next round's special then (specialFor keeps its pick for that round: the break's announcement and startRound read the
same), and for MINDRIPPER or AB.L..IN (warn_kinds; the lightning Anomaly's own charlene_warn) she warns, only once she's
at Comona. Log lines: `escort subs: ...`, `specials: the <kind> waits for CHARLENE to land at Comona (...)`.

## The ZFA-44s' end (2026-11-11: Saint Alessia's 50-round co-op run of 0.74.36; nothing run in game yet)
What the logs showed (the host's and Delta's, a joiner): not one of the run's 24 ZFA-44s died in 4.5 h. Every scripted end
hit them with `GameplayStatics.ApplyDamage(o, 1e8, nil, nil, nil)`, which runs on AC8's AI objects without an error and
takes no health off (70 "finished off" under the sea, 70 Helios blasts, all 24 at full health at round 51; the shuttle's
"damage applied" left it 1 alive 5 s on). The survivors went back to escorting, were held again at the next leaving (2,
4 ... 10 a ship), and sat on the combat zone's east edge (every blast at x 29.9-31.7 km; why is unknown).
- One finish: sv_core.lua `finishUnpaid(o)` (invincible off, the MinHealth field and SetMinHealth 0, switched on, then
  `ModifyHealth(-(h / 10 + 1000), nil, true)`, read back; still up: without the damage event, then ApplyDamage last), the
  route sv_rounds.lua's clean-up killed with in the same run. `ZLAUNCH.finish(e, why, final)` (sv_escort_laser.lua) wraps
  it for a ZFA-44: ESC.same first (hard rule 59), the host's copies down first; not down and final: switched off
  (ESC.offObj) and retired (never escorted or held again). Every end goes through it: the dive (ZDIVE.finish), parkedOff,
  offKill, flightOff (a flight finished, no longer only switched off), ESC.restart, a joiner's own (ownZfaOff: when the
  host's carrier goes, and its last flight before each forwarded launch, never a parked one: Delta's 24 had stayed up
  switched off, and that launch had switched off the arm's parked pair it then released, hidden), and the shuttle
  (SPC.shuttleTakeOff, finishUnpaid alone). A plane a new launch brings out flies again. ModifyHealth on an allied plane
  is the open question: its log lines say.
- The dive: a plane counts as gone only once its health reads 0; its blast once (e.blasted), its finish tried 3 times a
  second apart, then switched off. Each carrier leaving (or sunk: its flight no longer flies on) is a dive of its own, with
  its id in "zd": `h <ship> <round> <dive>`, `v <count> <dive>`, `b <x> <y> <z> <its down> <dive>`, `e <dive>` (an older
  host's without it: every dive); its own callout, start line, "over" and units' recycle. The dive's clock (dive_s) starts
  once its target is in its reach (its speed, speed_kmh while it reads slow, x dive_s) or approach_s after its first
  target; a held plane escorts the player nearest it until it dives. The callouts of a second are one (both ships, 20
  blasts).
- holdHull: while it holds a hull, the ship's ZFA-44s (not the dive's) are finished off again every 5 s; 60 s after the
  dive's last one it gives up, said once: the hull and the ship's STORE slot stay held (nothing frees the slot without
  SV_Recycle, never with planes up).
- The cover: only while the plane's carrier is on station (a held one until its dive); never one the dive took or that
  couldn't be finished. Every pos_log_s (30 s) each plane up is logged where it is, on every game.
- Log lines: `carrier: a ZFA-44 finished off (<why>): its health read 0 after ModifyHealth (damage event), ...` (the first
  each level), `carrier: a ZFA-44 <id> (<why>) could not be finished (health N after ModifyHealth and ApplyDamage):
  switched off`, `carrier: <why>: N parked ZFA-44s of ship i finished off under the sea (N by damage event)[; k could not
  be (health ...): switched off], ...`, `carrier: <why>: its flight <unit>: N ZFA-44s finished off, k switched off`,
  `carrier: <ship> sunk ...; N ZFA-44s of its flight kept for their dive or finished off`, `carrier: <who> (<why>): N
  ZFA-44s of its launchers still up 60 s on, finished off every 5 s: given up; ...`, `carrier: VAMPIRES <unit> <plane> at
  (x, y) km z m, v km/h, health h (escorting | held for its dive | diving | its carrier gone | this game's own | switched
  off: it couldn't be finished)`, `dive: a ZFA-44 of dive k onto the nearest enemy aircraft, d km off (about s at v
  km/h; r km in its 40 s)`, `dive: Helios blast n (...) ...: N enemy aircraft down, M ... hurt (dive k: T down); its ZFA-44
  down | NOT down yet (health N): tried again`, `dive: over (dive k, ship i): ...`, `dive: the host's dive k over ...`,
  `special: shuttle and pad off: the shuttle killed (damage event) | NOT killed (health N after ModifyHealth and
  ApplyDamage); ...`. The per-round `allies: ... at round N's level` lines show whether the 24 are still the same ones.
- Checks: tools/checks/dive_test.sh, escort_test.sh, pad_test.sh (ApplyDamage stubbed as the no-op it is in game; the old
  code fails them), coop_guard_test.sh (the "zd" rows with their dive ids).
