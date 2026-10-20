# Ace Combat 8 spawning system (reverse-engineered for Survival Mode, 2026-10-21)

Game build: AceCombat8.exe of 2026-09-29 (image base 0x140000000). Addresses are for that build; the runtime finds
everything by signature (runtime/sigs.h, made with `tools/re/mksig.py`) and by the game's reflection data, so a
patched exe only turns the spawner off instead of crashing. Tools: `tools/re/exe.py` (PE reader, xrefs, disassembly),
`tools/re/mksig.py` (unique masked signatures).

## The pipeline, top to bottom

```
EP exec LiveReinforcementExecution / ...RelativeExecution        (event package record, args below)
  Execute  0x1473e0ee0  (vtable slot 87; the Relative class's 0x1473e17b0 resolves its target and jumps here)
    manager = GameState-like(world)+0x1E8  ->  ALiveUnitSpawner*   (0x14721cb50; it reads manager+0x2E8 = UnitBPClass)
    wd      = the exec's world data (looked up from exec+0x34)
    tag set?   SpawnUnits(spawner, out, filter "has tag", wd, ...)        0x147e19a40
    else       SpawnUnitByName(spawner, &unitName, wd)                    0x147e119d0  <- what Survival calls
                 -> checkpoint record (0x14787ed20), then 0x147e11a40 -> SpawnUnits(..., filter "name ==", wd, 1, 1)
    async flag (exec+0x69) set: the same through 0x147e11c90 / 0x147e11bd0 with a completion delegate
    then, per spawned unit: vfunc +0x318 (Relative: move it next to its target actor)
SpawnUnits 0x147e19a40 (spawner, TArray<ALiveUnit*>* out, filter, wd, bool, bool fireAppeared)
  phase = FindPhase(spawner, wd)          0x147e11220 (obfuscated, jumps into .arch); for the global world data it is
                                          &spawner->GlobalPhase (spawner+0x348, an FLivePhase, 0x250 bytes)
  phase+0x241 set -> nothing (phase unloading)
  CollectDescs(filter, phase, &descs)     0x147e197a0: for every wd->UnitDescList entry (0xB0 bytes):
      skip if IsUnitIdSpawned(phase, desc.UniqueID)      0x147e1de00   <- the respawn refusal
      keep if the filter accepts it (name / tag)
  for each desc: SpawnOne(world, desc, &spawner->UnitBPClass, phase, params)   0x147e09ea0
      -> spawns the ALiveUnit actor and one AI object per AIObjectDesc at the desc's SpawnPoints (0x147e0ae60)
      -> RegisterUnit(phase, unit)        0x147e1d6c0: appends to phase.ManipulableObjects, registers its AI objects
  fireAppeared: posts event type 0x23 per unit = the EP trigger "reinforcement appeared" (RA_* / SV_FlightUp_*)
```

### Why a shot-down flight never came back
`IsUnitIdSpawned` walks `FLivePhase::ManipulableObjects` (+0x178, TArray of ALiveUnit*) and compares each unit's id
(`unit+0x2A0` is an interface; its vtable slot +0x20 returns the desc's UniqueID) with the desc's UniqueID. The only
code that removes a unit from that list is `UnregisterUnit` 0x147e1dac0, and the game calls it in exactly two places:
when a phase ends (0x147e18479: unregister + `AActor::Destroy` for every unit) and right after a phase-start spawn that
came up empty (0x147e16d70). A unit whose aircraft are all destroyed stays on the list, so its desc is skipped forever.
(No other code in the exe removes from that list: `tools/re` scan for removals at +0x180.) The probe builds' respawns in
tests 2-6 are not explained by this; tests 7-10 (and the latest, 23:24 on 2026-10-20: SV_SpawnG1=2 but SV_UpA/B=0)
match it exactly. The spawner's diagnostics (`SV_LogUnits`) print the list at every round start and clear.

### Fix used by Survival
Before spawning a desc again, take its old unit off the list the way a phase end does: `UnregisterUnit(phase, unit)`,
then `AActor::Destroy(unit, false)` (0x143fe0160). Only when the old unit has no living AI object
(`ALiveUnit::AliveChildAIGameObjects` is empty).

## Layouts (all read at run time; values for this build)

| what | offset | source |
|---|---|---|
| ALiveUnitSpawner.DefaultPhaseName / Phases / UnitBPClass / WingmanUnitBPClass | +0x290 / +0x298 / +0x2E8 / +0x2F0 | reflection |
| ALiveUnitSpawner.GlobalPhase (FLivePhase) / CachedVariation / CheckpointWriter | +0x348 / +0x5E8 / +0x688 | reflection |
| FLivePhase.WorldData / EventPackages / ManipulableObjects (spawned units) | +0x0 / +0x8 / +0x178 | reflection, and IsUnitIdSpawned's code |
| FLivePhase native: "unloading" flag / AI-object flag | +0x241 / +0x170 | SpawnUnits, SpawnOne |
| ALiveUnit id interface (vtable slot +0x20 = UniqueID) | +0x2A0 | IsUnitIdSpawned's code |
| ALiveUnit.ChildAIGameObjects / RootAIGameObjects / AliveChildAIGameObjects / TotalChildAIGameObjects | +0x2C0 / +0x2D0 / +0x2E0 / +0x2F0 | reflection |
| ULiveWorldData.UnitDescList (TArray<FLiveUnitDesc>, 0xB0 each) / NpcMissionDataTable | +0x30 / +0x110 | reflection |
| FLiveDescBase.UniqueID / Name / WorldDataName | +0x0 / +0x4 / +0xC | reflection |
| FLiveUnitDesc.AIObjectDescList / SpawnPoint (3 doubles) / Rotation (P, Y, R doubles) / RadiusInMeter | +0x18 / +0x58 / +0x70 / +0x90 | reflection |
| FLiveAIObjectDesc.MissionNpcID (the NPC table row = aircraft type) / SpawnPoint | +0x14 / +0x38 | reflection |

A desc's AI objects carry their own SpawnPoint (the formation, in world coordinates). A unit only works inside its
area (RadiusInMeter around its SpawnPoint, PatrolRadiusRatio of it to patrol); Survival's pool flights get 80 km.

## Survival's spawner (runtime 0.6.0 + Scripts/main.lua 0.6.0)

The native runtime registers Lua globals through UE4SS's `LuaMadeSimple::Lua::register_function` when UE4SS starts the
AC8SurvivalMode Lua mod (`CppUserModBase::on_lua_start(mod_name, lua, ...)`, called for every Lua mod before its
main.lua runs: vtable slot 6 in UE4SS 3.0.1, slot 8 its deprecated twin, traced at UE4SS.dll 0x180301b60; the runtime
doesn't rely on the number: every vtable slot of the mod object probes its arguments for a `std::wstring_view` naming
this mod). Call them only from the game thread (`ExecuteInGameThread`).

| function | does |
|---|---|
| `SV_Spawn(unit, x, y, z, yaw)` | moves the desc (and its formation) to x, y, z (cm), facing yaw (deg), recycles a shot-down previous flight, calls SpawnUnitByName. Returns aircraft spawned, or 0 (game spawned nothing), -1 not in Survival's level, -2 unknown unit, -3 previous flight still up, -4 bad args, -5 game code/offsets not found |
| `SV_SetAircraft(unit, npc [, index])` | sets MissionNpcID (e.g. `m29a_common`) of every AI object (or one) in the desc. Takes effect on the next spawn |
| `SV_UnitAlive(unit)` | aircraft alive in the flight's current spawn; -7 if it isn't on the phase's list |
| `SV_LogUnits(why)` | writes the phase's unit list (name, id, alive / total) to AC8SurvivalMode.log |
| `SV_Reset()` | forgets the cached spawner (main.lua calls it on level load) |
| `SV_Version()` | "0.6.0" |

The rounds (main.lua, "rounds" section, settings in `CFG`, optional `Scripts/survival_config.lua` overrides): each
round picks random flights that are down from the pool (Mission 22's 24 two-ship "kokatu" flights,
`ERA_Unit_01..08_Dep_Air0..2`), gives each a random aircraft type, and spawns them 18-25 km from Comona Airport on a
random bearing inside the combat zone, facing the airport, 3 s apart. The round is clear when every flight it spawned
has no aircraft left; 45 s later the next round has one flight more (up to 8). The event package gives each pool
flight its orders when it appears (air-only search, engage the player), counts SV_Alive / SV_Kills, and chases: every
6 s it teleports Mission 22's dummy Unit_dummyN0 onto the player and moves the area of every flight that is up
(SV_Up_NN) onto it with LiveUnitMoveActor (a unit only fights inside its 6 km area).

## Using it for the planned features
- **Any world-data unit can be spawned this way**, ground and sea units too, as long as its desc is in
  WD_SurvivalMode_global. New unit types (Ladon, Podarge, Land Aegis, ECM towers, stealth wing, named aces) are
  added as descs at build time (copied from the stock mission that has them, plus their blueprint imports per hard
  rule 7) and their NPC rows at run time (never override a shared NPC table).
- **Aircraft variety**: MissionNpcID must be a row of the world data's NpcMissionDataTable (Mission 22's); the rows
  Mission 22's units use are listed in main.lua's CFG.aircraft. Others need their NPC row and blueprint first.
- **Despawn / stragglers**: the same UnregisterUnit + Destroy can remove a living flight (not exposed yet: whether
  destroying the unit actor also removes its living aircraft actors is untested; for a shot-down flight it's confirmed
  safe).
- **Wingmen (shop)**: separate path - LiveSpawnWingmanExecution, FLiveUnitDesc.WingmanStartDescList and
  ALiveUnitSpawner.WingmanUnitBPClass (+0x2F0). Not reverse-engineered yet.
- **Portal arrivals**: spawn the special at the portal point with SV_Spawn, VFX from the world data's VFXActorDescList.

## Test results
Test 11 (2026-10-21 05:04, runtime 0.6.0):
- on_lua_start is slot 6 in UE4SS 3.0.1 (its deprecated twin, slot 8, is called too): "UE4SS: Lua mod AC8SurvivalMode
  started (mod slot 6)", and main.lua found the SV_* functions.
- FindPhase's phase for the global world data is &GlobalPhase: every spawn landed on that list.
- A MissionNpcID change spawns the new aircraft: MiG-29A, F-14D, Su-33 and Su-34 blueprints came up in flights whose
  Mission 22 type is different.
- Recycling works: a shot-down flight taken off the list (UnregisterUnit + AActor::Destroy of its unit actor) spawns
  again from the same desc, with its new type and position (rounds 3 and 5 of the same run; 6 recycles, all came up
  with 2 aircraft).

Event flags named in event records: the records name a flag by string, and the game turns that into an FName that splits
a numeric tail ("SV_Up_19" is SV_Up, number 20). The flag asset's keys must be stored the same way, as stock ones are
(Mission 22's Bool_IsAlive_f15e_0 is Bool_IsAlive_f15e, number 1). Test 11's keys weren't, so flags 10-24 never existed
and those flights were never chased. Test 12 (keys fixed): every flight up is flagged and the chase brings it to the
player (20 km closed in 20-30 s).
