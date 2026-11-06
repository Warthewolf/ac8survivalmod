# THE DECOY: the Tonitrus guidance laser and the Spear strike

User, 2026-11-06: a DECOY round. A UAV far north must be destroyed; then the trap: up to 35 new UAVs spawn round the
players all the way back to the airfield, each with the Tonitrus Spear guided laser, locking the closest player from any
direction; a locked player has 8 s to kill that UAV before the Spear is called in on them.

Lua: `mod/UE4SS/AC8SurvivalMode/Scripts/sv_decoy.lua` (DECOY, `SPC.kinds.decoy`), `CFG.specials.decoy`,
`[specials.decoy]` / `.pay` / `.lead` / `.radio` in survival.default.ini. Build data: tools/build_survival.py and
tools/survival_events.py (the build agent's, from the contract of 2026-11-06). Unit test: `sh tools/checks/decoy_test.sh`.
Nothing here is confirmed in game: every **[T]** below is the checklist's.

Tags: **[D]** confirmed in data, **[I]** inferred, **[T]** needs an in-game test. The research's scratch (property dumps,
the stock packages it read) is in `E:\ACE8 Survival Mode\build\research\decoy\` (git-ignored); its DECOY.md is the full
version of section 1.

## 1. The research's essentials

### The guidance laser [D]
- AC8's "Tonitrus guided laser" is `ALiveAIAirshipLaserPod`, a child actor on its carrier. AC8 already puts one on a UAV:
  **OP0033_uavst, MARKER UAV** (Mission 30). Every OP0033_uavst carries `BP_OP0033_uavst_laser` (heading 180, elevation
  179: it aims anywhere; LaserDistanceLimit 50000, thickness 500; beam NS_SearchLaser; sound
  `AKE_Ms30_ARMS_SKY_OP0033_uavst_Laser_Emit_Play/_Stop`, a mission bank: may be silent in Survival **[T]**).
- Native defaults: SearchPhaseTime 30 s, DesignatePhaseTime 15 s, SuccessPhaseTime 3 s (the UAV's pod 1 s). Phases from
  `ELiveLaserDesignateNotify` {Failed, Success, StartSearch, Designate}: it spirals in, holds, succeeds **[I]**.
- Row OP0033_uavst_01: LuaSet NLID_0001_CP, FCS1 PlaneGun000, FCS2 PlaneMsl002. Model: MaxHealth 6 (one missile), speed
  1000 (800-3000) km/h: it can't hover, it orbits.
- The laser is driven by event nodes, never by its carrier's AI: `LiveAirshipLaserDesignate` (on),
  `LiveAirshipStopLaserDesignate` (off), `LiveAirshipChangeLaserTarget` (move). Its target is an AI object, never
  "Player": Mission 19 aims at invisible dummies it moves next to the player (`ALiveAIRelativeLocateDummy`,
  LiveUnitMoveActor NearPlayer).
- Designate's 9 args (shapes [D], meanings [I]): designator object, designator tag, target object, target unit, an extra
  object, a search-time override (Mission 30's UAVs 5), a hold (10000), an int, the virtual shooter (NoneSelect: laser
  only). Mission 30's UAV record: `{01 UAV} {0a NoneSelect} {01 ship} {02 NoneSelect} {01 NoneSelect} {10 5.0} {10 10000.0}
  {0f 0} {01 NoneSelect}`.
- Trigger `AirshipLaserDesignateResult` (0x91): only ever used on an airship; whether it fires for a UAV is **[T]**.
  Survival doesn't use it: Lua owns the 8 s.

### The Spear [D]
- The weapon `BP_RodsFromGod` (`ALiveMeteoriteImpact`), fired by the virtual shooter `ALiveAIRodOfGodVirtualShooter`.
  Only Mission 19's shooter (`BP_OP0034_aship_RoG_ms19_CP`, row OP0034_aship_RoG_MS19) has `bImpactAvoidPlayer` false
  (SuccesImpactRange 50, ImpactDangerRange 15); Mission 19 counts the player damaged and destroyed by it.
- Its fire control: one arm (WN_WEAPON_1, hard rule 40), magazine 1, reload 10 s: several launchers for strikes close
  together.
- The rod: 200 damage within 50 % of the blast's radius, 30 (graze) within 100 %; the radius curve 0 -> 200 m at 0.2 s
  -> 900 m at 5-5.5 s -> 0 at 12 s. SpeedInitial 2,777,778 (27.8 km/s if cm/s) from a virtual launcher 58 km up in the
  WNW: about 3 s of fall **[I]**. PredictionTime 0 (no lead), RandRangeMeters 0. Whether the blast catches a plane at
  altitude is **[T]**.
- Firing a meteor weapon on command: Mission 6 / 18's `LiveFireOneShotWeapon(WN_WEAPON_n, shooter, target, ..., "<tag>")`
  then a `MeteoriteImpact` trigger (0x67) on the tag. "Player" as the target is stock (998 uses) [D]; on the RoG shooter
  **[T]** (it may fire only at designations: the fallback is a designate with arg 9 = the shooter, Mission 11's way).
- Mission 26's `LiveDestroyPlayerPlaneExecution`: the stock sure kill (TakeDamage through the normal path).
- Nothing stock is as short as 8 s (Mission 11: 160 s; Mission 30: a 240 s timer; Mission 19: rods every ~6 s), so the
  8 s are Survival's own.

### Stock radio lines [D] (AC8 voice only)
`v0001_1514` "Joker Flight, laser targeting!", `v0001_1507` "Laser targeting! Tonitrus Spear incoming!", `v0001_1515`
"Strike imminent!", `v0001_1513` "Joker 1 took a direct Spear hit!", `v0001_1502` "Projectiles will hit locations marked
by the laser. Keep your distance." No stock HUD element for a laser lock: the beam is the cue.

## 2. The build (the contract of 2026-11-06)

| What | Names |
|---|---|
| The bait | `SV_Unit_DecoyBait` (row `sv_decoy_bait`: OP0033_uavst copied, more health, its laser part kept), 31.6 km due north of the runway, 2.5 km up: (1610476, -3600000, 250000) |
| Its mark | `SV_Unit_DecoyBaitMark` (an invisible dummy at the airfield); `RE_SV_DecoyBaitLaser` (laser only) |
| The trap's UAVs | `SV_Unit_DecoyUav_01` .. `_35` (one Marker UAV each on the weaponless row `sv_decoy_uav`, laser part kept, an orbit-in-place behaviour, out of the pool's chase) |
| Their marks | `SV_Unit_DecoyMark_01` .. `_35`; `RE_SV_DecoyLaserOn_<nn>` (UAV nn's laser on mark nn), `RE_SV_DecoyLaserOff_<nn>` |
| The Spear | launchers `SV_Unit_DecoySpear_1` .. `_4` (Mission 19's shooter on row `sv_decoy_spear`, player avoidance off, high up); `RE_SV_DecoySpear_<s>` (LiveFireOneShotWeapon WN_WEAPON_1 at Player, tag `SV_DecoySpear`); a MeteoriteImpact trigger adding 1 to the flag `SV_DecoySpearHit`; `RE_SV_DecoyKill` (Mission 26's sure kill) |
| Radio | `RE_SV_DecoyRadio_Lock` (v0001_1514), `_Incoming` (1507), `_Imminent` (1515), `_Hit` (1513), `_Brief` (1502) |

Names Lua asks for that the contract doesn't have (a build without them answers "no such unit" and the round goes on):
`RE_SV_DecoyBaitPing` (the bait's minimap ping: Mission 22's LiveBattleNavigationExecution on its unit, as
RE_SV_RaidPing_NN) and `RE_SV_DecoyBaitLaserOff` (the bait's laser off when it's down or leaves).

## 3. The Lua (sv_decoy.lua)

- **The kind** (`SPC.kinds.decoy`): from round 10 (`from_round`), in the rotation (appended to `CFG.specials.rotation`
  after the table, so tools/novalka.py's and nospaceport.py's string edits of the literal still match), once a run
  (`once_per_run`: `RUN.specialAt.decoy`), ready only when its units are in the world data (SV_UnitAlive -2 for none;
  asked once a level). `fighter_share` 0.3 of the round's aircraft fly as fighters; the round ends once they're down and
  the trap is over (`busy`).
- **The bait**: spawned where the world data puts it, with its mark and the four launchers; its laser on the mark once
  both are here (its pod's hold the whole wait: `bait_timeout_s` + 2 min), pinged every `ping_every_s`. Down: paid
  (`pay.bait` + `bait_per_round` x the round) and the trap springs. Not down in `bait_timeout_s` (its clock stops while
  everyone's down at the airfield): it's finished off unpaid (nobody's kill) and the trap springs anyway.
- **The trap's spawns** (the host's, or solo; every 0.5 s): for each player a UAV may lock, one every `spawn_every_s`,
  `spawn_km` 2.5-5 km from them at any bearing, within `alt_m` of their height (600-9000 m), never inside `safe_km` 5 of
  the runway, `edge_km` inside the combat zone, `gap_km` 1.5 from another UAV, at most `per_player_max` 4 within
  `near_km` 8 of a player, `max_up` 12 at once, `max_total` 35 in all; each UAV's mark spawned on that player; each unit
  once a round (one still up from before is recycled, force 1, and spawned again).
- **Locks**: `lock_after_s` after a UAV shows it locks the closest player a UAV may lock (alive, not DOWN, in the
  mission, out of the safe circle, off the airfield). Every game (the host's too) takes the lock as `DECOY.G[k]`: its mark
  attached to that player's plane there (`K2_AttachToActor`; the first time the mark is put 1 km above the plane first,
  and if it's more than 150 m off a moment later every mark is moved onto its plane each tick instead: `DECOY.markMode`,
  logged once a level), the UAV's pod on `lock_delay_s` search / `designate_s` hold (instance values), its laser on. The
  locked player's game alone runs `DECOY.R[k]`: lock_delay_s + lock_s (1.5 + 8 s) on the round clock, the radio's lock
  and imminent (`imminent_s` before the soonest call), then the Spear: `RE_SV_DecoySpear_<s>` from the launchers in turn
  (the next on a refusal). Cancelled: the UAV down (on a joiner also once its killing hit was sent: `COOP.killSent`), you
  DOWN, you inside the safe circle at the call. The host cancels a lock whose player became unreachable (`dk|c|..|safe`).
  `relock_s` 6 after the call the UAV locks its closest player again. Each game's laser goes off a second after the call,
  its mark is let go 5 s after that.
- **The Spear's lead**: every rod (`/Script/Live.LiveMeteoriteImpact` new objects, a callback that only keeps them) and
  the rods kept, before each call, get `PredictionTime` = `lead.fall_s` 3.0 on the instance (the stock rod's 0: no
  lead), so it lands where you'll be at your speed. A rod made and fired in the same frame may miss its first lead **[T]**.
- **The impact**: `SV_DecoySpearHit` up after a call: your health logged then and a second on; the radio's hit when it
  hurt you; `sure_kill` (off by default) fires `RE_SV_DecoyKill` once the rod lands (a co-op player goes DOWN through the
  revives' floor like any kill).
- **The end**: all that could come down (`all down`), every living player inside the safe circle `safe_hold_s` 5 from
  `safe_after_s` 30 into the trap (`safe`, reward x `reward_safe_x` 0.5), or `trap_s` 300 (`time`). Pays `reward` +
  `reward_per_round` x the round; `LB.special("decoy", won)` (not won when safe; the Worker's SPECIALS needs "decoy" before
  it counts). The UAVs still up: `COOP.takenOff` (nobody's) and the specials' clean-up 3 s on (sv_rounds.lua
  SPC.endTick: finished off, the units recycled). Each UAV down pays `pay.uav` + `uav_per_round` x the round (a special's
  pay: split in co-op); creditKill and the sweep's tier tuning skip THE DECOY's units (sv_main.lua).
- **Recycles**: a UAV down, its pod and mark switched off, then its unit and its mark's off the spawner's list
  (SV_Recycle force 1 while the pod or the mark keeps them "alive", 0 when nothing is), one a `recycle_gap_s` 1.0 (the
  runtime's 64 deferred destroys), `recycle_after_s` 4 after its kill.
- **Co-op** ("dk", host to joiners, reliable): `dk|s|<bait|trap|done>|<spawned>|<down>|<up>|<max>` (as it changes, every
  10 s anyway, and in the whole picture: sv_coop.lua hostSync -> DECOY.syncTo), `dk|l|<k>|<slot>|<seq>` (UAV k locks
  player slot; seq the host's count: a repeat or older lock is never taken), `dk|c|<k>|<down|safe|gone|end>`. Guards:
  whole numbers in range (k 1-35, slot 0-23 and COOP.slotOk, seq 1-1000000, counts 0-99), words from fixed sets, at most
  40 a second. Each joiner puts its own copy's laser on its own copy of the mark (the records are kept per game:
  KEEP_EVENTS `^RE_SV_Decoy` and the explicit `^RE_SV_DecoySpear_`, `^RE_SV_DecoyKill$`, `^RE_SV_DecoyLaser`,
  `^RE_SV_DecoyBait`, `^RE_SV_DecoyRadio_`; the Spear and its sure kill also in HOST_DOWN_SKIPS), its own bait laser and
  ping, its own radio, and on `dk|c|k|down` recycles its copies. A joiner's NEXT row from `dk|s` (sv_hud.lua).

## 4. Test keys (TEST ONLY: stripped from every release)

| Key | What |
|---|---|
| Ctrl+= (`OEM_PLUS`) | test 1, the Spear alone: launcher 1 spawned if it isn't up, `RE_SV_DecoySpear_1` at you; each rod's place every tick, the impact flag, your health before and after |
| Ctrl+BACKSPACE | test 2, one lock: UAV 1 spawned 3 km ahead of you at your height (its mark on you), its lock 2 s on, then the 8 s: shoot it down (`strike cancelled`) or leave it (`the Spear called on you`, the impact, your health) |
| Ctrl+- (`OEM_MINUS`) | THE DECOY next round (in the break: in 3 s), once a run or not |

(Through sv_core.lua testKey since 2026-11-07; were Ctrl+PAGE_UP / PAGE_DOWN / HOME, which GONE FISHIN', THE FESTIVAL and
the day-night arc take on feature/fishing-lua. Every Ctrl key: tools/README.md "Ctrl keys".)

## 5. Log lines

- `special: THE DECOY's units are in this build's world data ...` / `special: no DECOY round: this build's world data has no ...`
- `special: round N, THE DECOY: the bait up (...), its mark at the airfield (...), the Spear's launchers 1 1 1 1`
- `special: THE DECOY's bait lasing the airfield (RE_SV_DecoyBaitLaser fired)`, `... pinged on the minimap every 12 s (...)`
- `special: THE DECOY's bait shot down N s after it showed: +Z` / `special: THE DECOY's bait taken off (...)`
- `special: THE DECOY's trap springs (<why>): up to 35 Spear UAVs ...`
- `special: THE DECOY's UAV k up by <you|player N> at (x, y) km, alt z km, d km from them (...); n of 35 so far, m up`
- `decoy: UAV k locks <you|player N> (d km; lock n this trap)` (the host's; the first 6, then every 10th)
- `decoy: a laser pod's phases on its instance (...): DesignatePhaseTime 15 -> 40, SearchPhaseTime 30 -> 1.5`
- `decoy: UAV k's laser on <you|player N> (RE_SV_DecoyLaserOn_kk fired), its mark attached to the plane | moved onto the plane`
- `decoy: marks follow their planes attached (K2_AttachToActor held: N m off a moment on)` or `... by a move each tick (K2_AttachToActor didn't hold: N m off)`
- `decoy: UAV k locks you: the Spear in 9.5 s unless it's down (lock n this run)`
- `decoy: UAV k down N s into its lock on you: strike cancelled` / `... taken down by your hit (the host's kill to come) ...`
- `decoy: the Spear called on you (UAV k's lock, 9.5 s): RE_SV_DecoySpear_s fired; you at (...) km, alt z km, v m/s; aimed N m ahead of you (the rod's own lead, 3.0 s)`
- `decoy: the Spear's rods led by the fall: PredictionTime 0 -> 3 s (BP_RodsFromGod_C_..., an instance)`
- `decoy: the Spear's impact (SV_DecoySpearHit a -> b) N s after the call: your health X -> Y`, `decoy: a second after the Spear's impact: your health ...`, `decoy: no Spear impact seen N s after the call ...`
- `decoy: the Spear's sure kill (RE_SV_DecoyKill fired)`
- `decoy: radio <lock|imminent|incoming|hit|brief> (RE_SV_DecoyRadio_... fired; n this run)`
- `special: THE DECOY's UAV k shot down N s after it showed: +Z; d of 35 down, u up`
- `decoy: <label> off the spawner's list (<why>; n alive): SV_Recycle 1 (k so far)`
- `special: THE DECOY's trap over (<all down|safe|time>) N s in: ...; +Z` and `decoy: this game's locks this run: ...`
- co-op: `decoy: the host's DECOY round: <state> (...)`, `decoy: the host's UAV k locks you (lock n)`, `coop: THE DECOY's <state> sent to player N (k locks on)`
- tests: `test: Ctrl+=, the Spear at you from launcher 1`, `test: the Spear's rod ... at (x, y) km, alt z km, d km from you`, `test: Ctrl+BACKSPACE, one Spear UAV 3 km ahead of you ...`, `test: Ctrl+-, round N is THE DECOY (...)`

## 6. Test checklist (in game)

1. **Ctrl+=** flying straight, then circling slowly: the rod falls (its trace lines), the impact flag rises (the
   MeteoriteImpact trigger fires on a meteor at Player), your health drops (the blast catches a plane in the air), the
   Tonitrus sounds play. With the lead on, does it land ahead of you (`aimed N m ahead`) and hit? No impact line: the
   shooter refuses "Player" (the fallback: designate with arg 9 = the shooter).
2. **Ctrl+BACKSPACE** twice: the beam reaches you from the UAV and stays on you through turns and from behind; the marks'
   line says attached or moved; the pod's phase line; kill the UAV inside the 8 s (`strike cancelled`, no rod), then leave
   it (`the Spear called on you`, the impact, your health). The Ms30 laser sound plays or not.
3. **Ctrl+-**, a whole round: the bait far north with its beam on the airfield and its minimap ping; the trap's
   callout and brief; UAVs 2.5-5 km round you, never within 5 km of the runway; several locks at once; the radio's lock,
   imminent, incoming, hit with gaps; the round's end by each way (all down; back to the airfield; 5 minutes); the pay
   lines; no `NOT removed` lines from the clean-up; the perf line's `decoy` part.
4. **A dead UAV's unit**: after a kill `decoy: SV_Unit_DecoyUav_kk off the spawner's list (...; 1 alive)` (its pod kept it
   alive: the force-recycle path) and no stuck counts.
5. **Co-op** (host + a joiner): the joiner's beams on the right players, its own locks' 8 s, strike and radio, the host
   never struck for the joiner's lock; a joiner's kill at 7 s cancels (`taken down by your hit`); a joiner who links mid-
   trap gets the state and its locks; a Spear that downs a co-op player puts them DOWN (revivable).

## Build names (built 2026-11-06 on feature/fishing; nothing run in game)
What tools/build_survival.py (`decoy_units`, rows, radio) and tools/survival_events.py (`build_decoy`; the data: its "THE
ESCORT (CHARLENE) and THE DECOY" section, DECOY_*) build for the decoy contract of 2026-11-06. Lua spawns every unit and
fires every remote event; nothing spawns at the level's start. The build reads it all back from the saved packages
(`check_escort_decoy_build`) and fails on any difference. Coordinates UE cm (north -Y, east +X).

### Rows
| Row | Table | What |
|---|---|---|
| `sv_decoy_bait` | DT_SV_NpcMission (Mission 30's `uavst_ms30` whole) | NpcId the stock `OP0033_uavst_01` (MARKER UAV: gun and missiles kept), MaxHealthDifference +114 (6 -> 120 HP) |
| `sv_decoy_uav` | DT_SV_NpcMission (`uavst_ms30`) | NpcId `SV_DecoyUav` |
| `SV_DecoyUav` | DT_SV_NpcRows: **Lua adds it to DT_NPC at the main menu** | `OP0033_uavst_01` with its fire control slots emptied (weaponless; its laser pod is its blueprint's child, kept), LuaSet NLID_0001_CP |
| `sv_decoy_spear` | DT_SV_NpcMission (Mission 19's `aship_RoG_ms19` whole) | NpcId the stock `OP0034_aship_RoG_MS19` (BP_OP0034_aship_RoG_ms19_CP: bImpactAvoidPlayer false, its one arm the Spear BP_RodsFromGod) |
| `dummy_common` | (Mission 22's, in already) | the marks (GR000_dummy, VALKA's aim's) |

No text keys (the UAVs show the stock MARKER UAV name).

### Units
| Unit (SV_Spawn's name) | Objects (event args) | Row | Side, flags | World data spot |
|---|---|---|---|---|
| `SV_Unit_DecoyBait` | `SV_Obj_DecoyBait`, its laser pod `SV_Obj_DecoyBait_BP_OP0033_uavst_laser` | sv_decoy_bait | enemy (Mission 30's B_Unit_00_UAVST0 desc, the pod's class imported: hard rule 7), box + TGT | (1610476, -3600000, 250000) yaw 90 (31.6 km north, 2.5 km up); area 4 km, 100-12000 m |
| `SV_Unit_DecoyBaitMark` | `SV_Obj_DecoyBaitMark` | dummy_common | Mission 22's Unit_dummyN0 desc: invincible, from AI, attack-target exception, no box | the runway centre (1610476, -436142, 600) |
| `SV_Unit_DecoyUav_01` .. `_35` | `SV_Obj_DecoyUav01` .. `35`, pods `SV_Obj_DecoyUav<nn>_BP_OP0033_uavst_laser` | sv_decoy_uav | enemy, box + TGT | a ring 6 km round the airfield, 2 km up (Lua spawns them where it wants); area 2.5 km, 100-12000 m: they circle where spawned |
| `SV_Unit_DecoyMark_01` .. `_35` | `SV_Obj_DecoyMark01` .. `35` | dummy_common | as the bait's mark | under the airfield (z -10000, Unit_dummyN0's) |
| `SV_Unit_DecoySpear_1` .. `_4` | `SV_Obj_DecoySpearA` .. `D`, each with `SV_Obj_DecoySpear<X>_TargetingDummy` | sv_decoy_spear | Mission 19's E_Unit_01_God_0 desc (its targeting dummy's native class imported), invincible, from AI, attack-target exception, no box | 30 km up over the airfield, 1 km apart |

Unit names ending in digits are stored as the engine turns the string into an FName (hard rule 17): `SV_Unit_DecoyUav_10`
= ('SV_Unit_DecoyUav', 11), `SV_Unit_DecoyUav_01` whole (a leading zero isn't split), `SV_Unit_DecoySpear_1` =
('SV_Unit_DecoySpear', 2); so SV_Spawn("SV_Unit_DecoyUav_10") finds it. Object names have no split tail.
The marks are GR000_dummy pawns (BP_GR000_dummy_CP, no mesh): Mission 22's LiveActorTeleportExecution moved the same desc
(VALKA's aim, A_Obj_01_dummyN0) in game, so they are movable; K2_AttachToActor on one is untested.

### Records (EP_SurvivalMode_global; survival_events.build_decoy). Lua fires every RE_SV_*.
| Event | Does |
|---|---|
| `SV_DecoyBaitUp` / `SV_DecoyUavUp_<nn>` (appearances) | 0.5 s: the UAV's laser pod hidden from the HUD and invincible (Mission 30's RemoteEvent_Injection_uavst records); a trap UAV's engagement None on its unit (it circles, it doesn't hunt) |
| `RE_SV_DecoyBaitLaser` | the bait's laser on its mark: Mission 30's UAV LiveAirshipLaserDesignate {SV_Obj_DecoyBait, NoneSelect, SV_Obj_DecoyBaitMark, NoneSelect, NoneSelect, 5.0, 10000.0, 0, NoneSelect} (no shooter: laser only) |
| `RE_SV_DecoyBaitLaserOff` | LiveAirshipStopLaserDesignate on the bait (Mission 19's Impact_Center stop: {obj, NoneSelect, false, true, 0.1}) |
| `RE_SV_DecoyBaitPing` | the bait's minimap ping: Mission 22's LiveBattleNavigationExecution on SV_Unit_DecoyBait (RE_SV_RaidPing_NN's) |
| `RE_SV_DecoyLaserOn_<nn>` (01-35) | UAV nn's laser on mark nn: {SV_Obj_DecoyUav<nn>, NoneSelect, SV_Obj_DecoyMark<nn>, NoneSelect, NoneSelect, 1.5, 10000.0, 0, NoneSelect} (args 6 / 7: Mission 30's 5 / 10000, read as search s / hold s), and its engagement None again |
| `RE_SV_DecoyLaserOff_<nn>` | its laser off (the stop above) |
| `RE_SV_DecoyMarkOnMe_<nn>` (extra) | mark nn teleported onto this game's player (Mission 22's teleport, target Player, offset 0, Absolute): a fallback if Lua can't attach or move the mark; "Player" is each game's own, so keep it local in co-op |
| `RE_SV_DecoySpear_<s>` (1-4) | the Spear from shooter s at the player: Mission 6's LiveFireOneShotWeapon {WN_WEAPON_1, SV_Obj_DecoySpear<X>, Player, NoneSelect, false, SV_DecoySpear, false} (the shooter's one arm; its magazine 1, reload 10 s: four shooters) |
| `SV_DecoySpearImpact` (trigger) | Mission 6's MeteoriteImpact trigger (type 0x67) on the tag SV_DecoySpear, every impact: SV_DecoySpearHit + 1 |
| `RE_SV_DecoyKill` | Mission 26's LiveDestroyPlayerPlaneExecution (no args) |
| `RE_SV_DecoyRadio_Lock` / `_Incoming` / `_Imminent` / `_Hit` / `_Brief` | play DT_SV_Radio groups `SV_DecoyRadio_<X>`: v0001_1514 "Joker Flight, laser targeting!", v0001_1507 "Laser targeting! Tonitrus Spear incoming!", v0001_1515 "Strike imminent!", v0001_1513 "Joker 1 took a direct Spear hit!", v0001_1502 (the keep-your-distance briefing line); LIVE_AWACS, each a one-row group cloned from the tells' template row 382 (LimitPlayCount 0; Lock / Incoming / Imminent at StartDelay 0.1 on the interrupting channel) |

Int flag: `SV_DecoySpearHit` (starts at 0; Lua reads its rises). 155 triggers, 225 execs; 5 radio rows (726 in all).

### Lua to-do the contract doesn't say
- Add `SV_DecoyUav` (DT_SV_NpcRows) to DT_NPC at the main menu: without it the trap UAVs don't spawn.
- `RE_SV_DecoySpear_*`, `RE_SV_DecoyKill` and `RE_SV_DecoyMarkOnMe_*` act on this game's player: KEEP_EVENTS, never forwarded.
- Count a UAV down by its body: its pod is invincible (as Mission 30's) and may keep the unit "alive" (the Ladons' parts).

## Lua wired to the build (2026-11-07, branch feature/decoy; nothing run in game)
- **The row at the main menu** (DECOY.setup, sv_main.lua's setup pass; every game): `SV_DecoyUav` (CFG.specials.decoy.dt_npc)
  from DT_SV_NpcRows into DT_NPC (`decoy: the trap UAVs' row SV_DecoyUav in DT_NPC`); without it no DECOY round (`special:
  no DECOY round: its UAVs' DT_NPC row SV_DecoyUav isn't in (...)`).
- **The marks' last fallback**: attached (K2_AttachToActor), else moved each tick (K2_SetActorLocation); a move checked a
  look on (`decoy: marks moved onto their planes each tick hold ...`), and when the mark is 150 m or more from where it was
  put, a mark on this game's own plane is put there each tick by the build's `RE_SV_DecoyMarkOnMe_<nn>` (Mission 22's
  teleport onto "Player", kept local by KEEP_EVENTS ^RE_SV_Decoy: `decoy: a mark moved onto its plane didn't hold either
  ...`, `decoy: UAV k's mark onto your plane by the build's teleport (...)`); a mark on another player's plane is still
  moved (the teleport only knows this game's player). DECOY.markMode "teleport", forgotten with the level.
- Dead UAVs are counted by their body (the first object of the unit that isn't its laser pod; the pod is invincible and
  only keeps the unit "alive", so a recycle with it up is force 1), as before.
- Every unit, record and radio name it uses (`RE_SV_DecoyBaitLaser` / `Off` / `Ping`, `RE_SV_DecoyKill`, `_LaserOn_` /
  `_LaserOff_` / `_MarkOnMe_<nn>`, `RE_SV_DecoySpear_<s>`, `RE_SV_DecoyRadio_*`, the 35 UAVs and marks, the 4 launchers) was
  checked against the saved packages of `ZFA=1 sh tools/build_all.sh` (2026-11-07): all there.


## Code review of 2026-11-07 (branch feature/decoy; nothing run in game)
- A pause-menu restart (finding 3): THE DECOY needs nothing more. DECOY.tick sees the new run's D and lets every lock and
  runner go (resetRun: detach); its units go with the mission's reload or the next round's clean-up. (THE FESTIVAL's
  siren, SAL's boat, the card and THE ESCORT now have their own: tools/re/FISHING.md 10, ESCORT.md.)
- The rotation's commented ini line lists decoy last, as CFG's append puts it (finding 14), and the leaderboard Worker
  knows "decoy" (finding 15: redeploy it). tools/re/ESCORT.md's "Code review of 2026-11-07" has both.
