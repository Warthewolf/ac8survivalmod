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
