# AC8 stock mission reference (for Survival Mode)

Built from the name tables of every campaign mission's global event (EP_) and world (WD_) files
in E:\AceComba8EXPORTS\Live\Content\Maps\Ingame (Missions 001–030, 025_2, 028_Opening).
The full list of event nodes and which missions use them is in node_catalog.tsv (349 node types).
Names only: check the actual node settings in the mission before copying a pattern.

## Mission file layout (same in every mission)
- EP_<mission>_global / _phaseNN : event graphs (the logic). Most of the real work is in _global.
- WD_<mission>_global / _phaseNN : world data (units, paths, volumes, markers).
- EF_<mission>_global : event flags (bool / int / timer variables).
- MC_<mission>[_PhaseNN | _Timer600] : mission config (Timer600 = 10-minute timer missions: M003, M004, M020).
- PL_<mission>.umap : the persistent level. *_MiniGame maps hold minigames.

## Stock nodes that cover Survival Mode features

| Survival feature | Stock node(s) | Best mission to study |
| --- | --- | --- |
| Rearm at the airfield | LiveSetWeaponAmmoCount (player), LiveSetWeaponAmmoCountNPC | M015 (player), M004 (NPC) |
| Repair | LiveSetHealth, LiveSetMaxHealthExecution | M013, M019, M022 |
| Landing / takeoff | LiveSetTakeoffAndLandingEventExecution, LiveEnableLandingGear | M022, M004, M003 |
| A stock mid-mission resupply | "Supply", RE_Supply_WingmanMove, RE_BaseSupplyMute, In/OutSupplyBGM, Supply_Score | M022 (closest to the shop), M024, M026 |
| Waves of enemies | LiveReinforcementExecution, LiveReinforcementRelativeExecution | M006 Phase02 waves 2–6 (Wave2_Appear … Wave6_Appear) |
| Repeating attack waves | 02_Wave3_Attack_basse_repeat_* | M013 |
| Named / ace enemies | SpawnNamedEnemy (RE_/CE_/RA_), Appearance_Named, Ace_Special_Flare | M006, M010 (named); M004, M009 (ace squads) |
| Portal-style spawns | LiveActorTeleportExecution, LiveAIPathTeleportByPointExecution, LiveAIPathTeleportByDistanceExecution, RE_Phase02_Wave2_Path_Teleport | M006, M010, M013, M019 |
| Escalating AI skill per round | LiveAIChangePilotRankExecution, LiveAIChangeEnemySearchType | M006, M009, M024 |
| Random special rotation | LiveRandomStatement, LiveLotInstantRandomExecution, LiveRandomFilterExecution | M014, M029, M030 |
| Round counters / clear checks | LiveFlagOperation_IntExecution + LiveInequality_FlagIntStatement | almost every mission |
| Intermission timers | LiveStartTimerExecution, LiveStopTimerExecution, LiveSetPauseTimerExecution, LiveSetSecondaryTimerExecution, LiveHideRemainingTimerExecution | M014, M020, M023 |
| Phase changes without loading | LiveSeamlessSwitchPhaseExecution, LiveSwitchPhaseExecution | M004, M020 |
| Score / rank | LiveSetBorderScoreExecution, LiveExterminationBattleRankThresholdStatement | M008, M022, M024 |
| Low-health warnings | LiveIsPlayerLowHealthStatement | M005, M016, M029 |
| Airfield areas to reuse | "Airport" / "Airbase" areas | M006, M005 AreaB, M024 Area C, M025_2, M028 |
| Wingman reward | LiveSpawnWingmanExecution | M015, M028 |

## Naming patterns Bandai uses (copy them so ported events read cleanly)
- RE_ = remote event, CE_ = composite event, PRE_/Post = pre/post radio events, RA_ = radio,
  FI_/FT_/FlagInt_/FlagTimer_/FlagBool_ = flags, PathFinish_/PathPointReceive_ = path triggers.
- PhaseNN_Start, PhaseNN_Skip, PhaseNN_MissionRestart (_Ally/_Enemy/_Radio) appear in most missions:
  checkpoint restarts are built per phase.
- Wave-based missions name units Phase02_WaveN and fire WaveN_Appear events one after another (M006).

## Cautions
- PathPointReceive_ triggers exist in stock (M004 etc.) but never fired in our mods. Keep using PathFinish + delays.
- "warp_RemoteEvent" (M008) and the path warp in M025: keep warp off on ported paths.
- Debug_UAV_Respawn / Debug_BarrierUAV_Respawn (M023) show the devs had a respawn debug path. Worth a look for wave respawns.

## Suggested study order
1. M006: wave appear chain, named enemy spawn, path teleport, airport. Closest overall to Survival Mode.
2. M022: Supply event + takeoff/landing node. Base for the airfield shop.
3. M015: LiveSetWeaponAmmoCount on the player.
4. M013 / M014: repeating waves, random statements, timers.
