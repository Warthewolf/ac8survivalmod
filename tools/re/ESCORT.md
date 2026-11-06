# THE ESCORT (CHARLENE) and the ZFA-44 carriers (2026-11-06)

The user (2026-11-06): an ESCORT special round. CHARLENE, an allied B-1 Lancer, spawns in the map's south-west corner,
flies to Comona Airport under constant attack and lands. Four escorts (Su-57 YORKE, Su-57 ROCK, Su-33 ALI, Su-35
DANIELLE) land after her. The round is lost if she dies and completes once all five have landed. Then she says: "Thank
You Pilot, I've sent word to HQ and they've sent two Cargo Vessels into the Area with the Special ZFA-44 Airframes, you can
call for their support from the STORE". The reward: Mission 17's cargo ship (allied) in the STORE, launching ZFA-44s
(tools/re/ZFA44.md) and staying 3 rounds (VOID WATCHER 1's service model).

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
  side_km), and more come while she flies (`reinforce`: every every_s with fewer than `below` enemies up, a free pool
  flight of `size` ahead of her at alt_m, at most `max` a round; each always goes after her).
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
- The STORE item `ZfaCarrier` ("ZFA-44 CARRIER", 15,000 Z, raise 1.0), only once unlocked; at most `max_up` 2 out.
  STORE_PAGES has no free row (every page holds 6), so until the build gives it a row of its own it shares
  `store_row` "Revive" (the AIRFIELD page's revive row, a dead row solo and in co-op while nobody's down; label "CALL A
  ZFA-44 CARRIER"): sv_shop.lua `offer` asks ESC.rowItem; a revive to buy takes the row back.
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
- The ALLIES row adds `ZFA-44 CARRIERS n`.

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
- **Ctrl+F1**: the landing test T0: CHARLENE alone at the IAF (heading 067), invincible, her final at once, rollout, taxi
  and stop; no enemies sent at her, no escorts; the break held while it runs; taken off test.end_s (30) after she's down.
- **Ctrl+F2**: the ZFA-44 carriers unlocked and one sent now (free).
- (Ctrl+9 stays the ZFA-44's T0 dressing of the nearest enemy, tools/re/ZFA44.md 8.)

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
1. **T0 first (Ctrl+F1, in a break)**: no crash; `escort: T0 +...` lines every 0.5 s; she descends on the glide slope
   (height falling ~50 m a km), gear `down`, touches down 150-600 m past the west threshold (`her rollout began N m`), holds
   z 7.5 m (`... m over the runway` near 0) rolling, slows to the turn-off, taxis to the hold spot, stops (`T0 over (...):
   stopped`). Watch for a pull-up or bounce (avoidance off at 3 km), floating or sinking (RootHeight), the gear meshes.
2. A run to round 9 (or Ctrl+0): the callout, her and four escorts at the south-west corner, names on their boxes, all on
   their route paths; `sent after CHARLENE` lines and the flights really going for her (no `cover on` / `RE_SV_Hunt` line
   for them in co-op); enemies spawning ahead of her; her health holding a while (health_x).
3. Her final at the IAF (gear, orbit records, landing closed: the player can't land), the escorts circling, her landing
   as in T0, then each escort released and landing one at a time; the round not ending before.
4. Win: ESCORT COMPLETE, the pay, her line in two callouts, landing open; the AIRFIELD page's revive row now `CALL A ZFA-44
   CARRIER 15000 Z` (solo, or co-op with nobody down).
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
