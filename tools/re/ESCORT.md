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
