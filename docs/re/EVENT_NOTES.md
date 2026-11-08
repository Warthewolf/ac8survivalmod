# Event packages (EP): how stock waves work (research for Milestone 2, 2026-10-20)

Dump any EP with `python -X utf8 -I tools/checks/ep_dump.py <EP.uasset> [regex]`.

## Record format (exact; every stock EP parses to the last byte)
After the LiveEventPackage properties (WorldData, MissionConfgReferences, PackageHash, EventFlagAsset):
`u32 0, u32 nTrig, LiveCustomEventTriggerTable x nTrig, u32 nExec, LiveCustomEventExecutionTable x nExec`.
Both are unversioned property structs, read/written with uprop (the fixed-layout `eprec.py` and its
`split_lists` only cope with simple records; Mission 006's composite/conditional records break it).
- Trigger: EventName (FName), EventHash, MonitorEvents[] (composite: fires when the listed events fire),
  LifeCount (fire limit; 1 = one-shot), TriggerPriority, EventType (byte), KeySpeakerOption, ArgsInfo[].
- Exec: ConnectionEventName (the trigger it belongs to), ExecutionClass (node class import), ConditionalStatementTables[]
  (e.g. LiveInequality_FlagIntStatement flag Geq 2 -> State_True), Delay, LoopCount, ArgsInfo[], ExecutionID/Number.
- ArgsInfo items: {Type (byte), TipsHash, Value (string)}; values are names of units/paths/flags or literals.

## Trigger EventTypes seen
01 mission start · 23 reinforcement group appeared (RA_*) · 2f composite (CE_*, MonitorEvents) · 4f remote event
(RE_*, called by LiveCallRemoteEventExecution) · 4c phase start · 72 unit damage / destroyed (UnitDamage_*, with a
count arg "Number") · 2e path point reached · 25 post-radio.

## Mission 006 wave chain (Phase02 Wave2..6)
LiveReinforcementExecution(group) -> RA_P2_WaveN_Appear (type 23) -> CE_P2_WaveN_Appear (life 1): LiveUnitMoveActor to an
anchor, LiveAIEngagementOrder (PlayerOnly), LiveCallRemoteEventExecution RE_Phase02_WaveN_Appear -> LiveAIPathExecution.
Waves chain on int flag "Phase02 AdditionalReinforcement AppearCount" (Geq 1..4). Each wave spawns once.

## Mission 022 (Comona) enemy pool
WD_Mission022_global: 71 UnitDescs. Enemy air reinforcements: ERA_Unit_01_Air0..6, ERA_Unit_01_Wave5_Air0..4,
and the "kokatu" groups ERA_Unit_0N_Dep_Air0..2 (N = 1..8, 3 aircraft each) spawned by
LiveReinforcementRelativeExecution in RE_SpawnEnemy_kokatu_1st..8th. NpcMissionDataTable is M22's NPC table.

## Respawn
No stock node respawns a destroyed unit. Mission 013's "repeat" waves re-run paths of living units; Mission 023
relaunches UAVs by firing a carrier's drone weapon. LiveReinforcementExecution can't spawn a desc again while its
shot-down flight is still on the phase's unit list, and nothing takes it off (see SPAWN_SYSTEM.md): Survival spawns
with its own spawner instead (runtime 0.6.0).
