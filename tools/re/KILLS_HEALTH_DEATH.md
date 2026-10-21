# Kills, score, player health, death and run end (research 2026-10-22)

Research only: nothing here has been tested in game. Game build: AceCombat8.exe of 2026-09-29 (image base 0x140000000).
Scratch tools and dumps: `build/research/kills/` (run from `tools/re`):
- `poff.py <Prop>...`: offsets of reflected properties (FPropertyParams: u16 ArrayDim at +48, u16 Offset at +50).
- `natives.py <UFunction>...`: the exec thunk of a native UFUNCTION (FNameNativePtrPair {name, exec}).
- `execvt2.py <Class>` / `avt.py <AClass>`: vtable + Execute, following the jmp thunks execvt.py misses (AMMO.md).
- `fieldref.py <hex disp>`: functions that use `[reg + disp]` (the code section is `.ecode`, not `.text`).
- `cls.py` / `props.py <regex>`: usmap schemas; `ep_*.txt`: ep_dump of all 151 stock EPs; `strings.txt`: exe strings.

## 1. The game objects (reflected, Lua-readable)
`ALiveGameObject < APawn` (vtable 0x14cbfd7b8) is the base of `ALivePlayerPlane` (vtable 0x14cc01cc8; the player is
`PlayerController.Pawn`) and `ALiveAIGameObject` -> `ALiveAIPlane` (vtable 0x14c551db0).

| field | offset | type / meaning |
|---|---|---|
| MaxHealth / MinHealth | +0x3b4 / +0x3b8 | float, health units |
| HealthInternal | +0xda8 | int = health x 10 (GetHealth = HealthInternal x 0.1) |
| native "dead" flag | +0xdb8 | byte; alive = flag 0 and HealthInternal > 0 (CheckDeath, IsAlive) |
| KillBountyScore / BaseScore | +0x3f0 / +0xe68 | int; BaseScore comes from the NPC row (LiveNpcTable.BaseScore), set by SpawnOne |
| AttackingMainWeaponArray / LastAttackingSpecialWeaponOwner | +0x458 / +0x478 | missiles on it now / owner of the last SPW that hit it |
| DamageHistoryMap | +0xe70 | TMap<UObject*, float>: total damage per attacker (added on every hit, 0x147d21083) |
| native last-hit record | +0x480 u8 damage type, +0x484 FWeakObjectPtr DamageCauser (index, serial +0x488), +0x48c flag, +0x490 weak ptr | written by ModifyHealthInternal on every health change |
| native last player attacker | +0x498 FWeakObjectPtr, +0x4a0 time | set when the causer is a LivePlayerPlane; cleared after a timeout (settings +0x740): the kill-credit window |
| LivePlayerPlane: LastFiredWeapon / LastFiredWeaponTarget | +0x1500 / +0x1508 | the player's last fired weapon and its target |
| LivePlayerPlane: Evaluation | +0x16c8 | LiveEvaluation {EvaluationDamageMap, EvaluationAccumulateData} |
| LivePlayerPlane: native armour pool | +0x13fc float max, +0x1400 int current (x10) | damage drains this pool before HealthInternal (player's ModifyHealthInternal 0x147d5ab50) |
| LiveCampaignGameMode: MissionEndSequence / RestartSequence / MissionFinishReason | +0x3d8 / +0x780 / +0x1ed8 | see section 4 |

UFUNCTIONs of LiveGameObject (outer 0x147d19710; exec thunks in brackets): GetHealth [0x147d17ea0], GetMaxHealth,
GetMinHealth, GetDamagePercentage [0x147d17db0: (1 - min(1, Health/Max)) x 100, the HUD "DMG n%"], IsAlive,
ModifyHealth(float InValue, UObject* DamageCauser, bool bCauseDamageEvent) -> float [impl 0x147d1ccb0], SetMinHealth(float),
SetIsInvincible(bool), SetIsInvincibleFromAI, IsAttackedByMainWeapon / BySpecialWeapon / ByOpponent, OnHitByGun(Attacker),
OnDeath(DeadGameObject) [-> vfunc +0x898], IsPlayerTarget, GetFaction, GetUnitName, GetObjName, GetSpeedKmph, GetAltitudeMeters.
`K2_GetLastDamagedByAttacker() -> Object` exists only on `ALiveAIUniqueObjectBase` (bosses/unique objects), not on AI planes.
**ModifyHealth does nothing on the player**: it returns 0 when vfunc +0xaa0 is true, and LivePlayerPlane's +0xaa0 is
`mov al,1` (0x1416baca0). On AI objects it works (negative + bCauseDamageEvent = real damage through TakeDamage +0xa38).

## 2. The health / damage pipeline (native)
```
TakeDamage            vfunc +0xa38 (GO 0x147d203e0, AIPlane 0x147cd58b0, Player 0x147d5a430)
  (this, float dmg, FDamageEvent* ev (type byte ev+0x18; 7/8/9 = special path), AActor* causer)
  -> DamageHistoryMap[causer] += dmg, damage score (0x147d21a50) ...
ModifyHealthInternal  vfunc +0x938 (base 0x147d1ce30; player 0x147d5ab50 drains the +0x1400 pool first, then jumps to base)
  (this, float delta, u8 damageType, UObject* causer, bool flag)
  records +0x480..+0x4a0 (above), new health = clamp(health + delta, GetMinHealth (vfunc +0x928), MaxHealth)
  -> SetHealthInternal 0x147d1cbc0 (replay record 0x13, then SetHealth) -> CheckDeath 0x147d25820
SetHealth             vfunc +0x918 = 0x147d1cb80 for all three classes:
                      HealthInternal = clamp(int(h x 10), 0, int(MaxHealth x 10))
CheckDeath            0x147d25820 (callers: ModifyHealthInternal, one AI path 0x147cc36d7):
                      if dead flag or HealthInternal <= 0: replay record 0x14, tail-call Die = vfunc +0xb38
                      (GO/Player 0x147d252c0, AIPlane 0x147c919f0)
```
Damage cause is the attacking game object (ModifyHealthInternal tests `causer->vfunc+0xaa0` and IsA(ALivePlayerPlane)),
not the projectile. The damage-type byte's enum has no reflected name (ModifyHealth uses 1, or 0xe for a special case;
the player's death is "collide" when `player+0x4a9 == 7`).

## 3. Stock health nodes (traced; Execute = vtable slot 87)
| node | StaticClass / ctor / vtable / Execute | args (EP) | what Execute does |
|---|---|---|---|
| LiveRestorePlayerPlaneExecution (Training001) | 146df21e0 / 158e8e840 / 14c669310 / **147414eb0** | none | P = `[0x14721cb50(GetWorld())+0x1e0]` (the player, as in AMMO.md); `P->SetHealth(MaxHealth)` (vfunc +0x918); `[P+0x1400] = clamp(int([P+0x13fc] x 10), 0, int(Max x 10))` |
| LiveSetHealth (M006/09/13/18/19/22/25_2/26/29/30) | 146df02f0 / 158e38a20 / 14c671e70 / 14740ad80 | unit(02), tag(0a), object(01), float Value | for every target: `SetHealth(int(MaxHealth x Value))`, clamped, so 100.0 = full. No player target |
| LiveSetMaxHealthExecution (M004, M022 shuttle 175) | 146def650 / 158e1d260 / 14c6762a0 / 147406f10 | object, unit, tag, float, bool | sets MaxHealth (not traced further) |
| LiveSetMinHealthExecution | 146def5a0 / 158e18df0 / 14c68d698 / 147406b50 | target(0b: `Player` or a name), unit, tag, float | for `Player`: `[P+0x3b8] MinHealth = value`. M019/M021/M026 set Player 1.0 around scripted parts, 0 after |
| LiveTakeDamageUnitHealth (M013/16/20) | 146dec9c0 / 158d9bf40 / 14c67f800 / 1473f5770 | unit, tag, float | damages a unit |
| LiveDestroyPlayerPlaneExecution (M026 Player_Crash_Baxter) | 146df2290 / 158e98130 / 14c66b200 / 147414f80 | none | `P->TakeDamage(huge, event{...}, null)`: kills the player through the normal path |
| LiveMissionFinishExecution | 146deabc0 / 146dfa4c0 / 14c682530 / 1473e7fe0 | ELiveFinishExecutType (MissionClear 0 / MissionFailed 1), bool, bool | campaign mode: `[mode+0x728] = 1 clear / 2 failed`, `[mode+0x523] = !bool2`, then mode vfunc +0xab0 (end mission) |
| LivePlayerDeathExecution | 146de97f0 / 158d4b060 / 14c690040 / 1473df1d0 | - | used by no stock EP |
Statements: LiveIsPlayerLowHealthStatement (M016, M029), LiveIsDamagedFromPlayerStatement, LiveHasKillDamageTypeStatement (unused).

### Signatures (tools/re/mksig.py, unique in this build; ?? = wildcard)
| what | VA | bytes |
|---|---|---|
| RestorePlayerPlane Execute | 147414eb0 | `48 89 5C 24 08 48 89 6C 24 10 48 89 74 24 18 57 48 83 EC 20 48 8B 01 49 8B F1 49 8B E8 48 8B DA 48 8B F9 FF 90 88 01 00 00 48 8B C8 E8 ?? ?? ?? ?? 84 C0` |
| SetHealth (vfunc +0x918) | 147d1cb80 | `F3 0F 10 81 B4 03 00 00 F3 0F 59 05 ?? ?? ?? ??` |
| player ModifyHealthInternal (pool) | 147d5ab50 | `0F 57 D2 0F 2F CA 73 59 8B 81 00 14 00 00 85 C0` |
| base ModifyHealthInternal | 147d1ce30 | `48 89 5C 24 10 48 89 6C 24 18 56 41 56 41 57 48 83 EC 70 0F 29 74 24 60` |
| ModifyHealth impl | 147d1ccb0 | `48 8B C4 48 89 58 08 48 89 68 10 48 89 70 18 57 48 81 EC 90 00 00 00 0F 29 70 E8 41 0F B6 E9` |
| CheckDeath | 147d25820 | `40 53 48 83 EC 30 80 B9 B8 0D 00 00 00 48 8B D9` |
| campaign finish-reason (mode slot +0xae8) | 1478eef60 | `40 53 48 83 EC 20 48 8B D9 E8 ?? ?? ?? ?? 48 8B C8 E8 ?? ?? ?? ?? 48 8B 48 60` |
| campaign CreateEndSequence (slot +0xaf8) | 1478ef050 | `40 55 53 57 48 8D 6C 24 F0 48 81 EC 10 01 00 00 48 8B 05 ?? ?? ?? ?? 48 33 C4 48 89 45 E0 80 B9 28 07 00 00 01` |
Offsets to read from RestorePlayerPlane's bytes at run time (AMMO.md style, check the opcode bytes first): +0x55 call
0x14721cb50 (rel32), +0x5a `48 8B 98 <disp32>` = 0x1e0, +0x6c `F3 0F 10 8B <disp32>` = MaxHealth 0x3b4, +0x74
`FF 90 <disp32>` = SetHealth slot 0x918, +0x7a `F3 0F 10 83 <disp32>` = pool max 0x13fc, +0xae `89 83 <disp32>` = pool 0x1400.
HealthInternal 0xda8: SetHealth +0x2c `89 81 <disp32>`. Scale 10.0 is the float at 0x14d2aa8c0 (rip-relative in SetHealth +0x0c).

## 4. Player death and how a run ends
Flow (campaign/free mission, ALiveCampaignGameMode, vtable 0x14cbc5af0 by scan):
1. Player health reaches 0 (or a crash) -> CheckDeath -> Die (vfunc +0xb38).
2. Mode slot +0xae8 (0x1478eef60) sets `MissionFinishReason` (+0x1ed8, `ELiveCampaignMissionFinishReason`: None 0,
   MissionSuccess 1, **MissionFailureKill 2**, **MissionFailureCollide 3** (when `player+0x4a9 == 7`), Timeup 4,
   CombatZone 5 (0x1478ecd60), Special 6, QuitGame 7 (slot +0xa68 0x1478eddf0 `QuitGame(ELiveQuitGameReason)`:
   Default / PauseMenu / RetryMenuByFreeFlightTimeup)). It is MissionSuccess only when `[mode+0x728] == 1`.
3. Slot +0xaf8 CreateEndSequence (0x1478ef050) stores in `MissionEndSequence` (+0x3d8) a new
   **`ULiveCampaignPlaneDeathMissionEndSequence`** (StaticClass 0x146efb7a0, Execute 0x1474909c0) when the player is dead,
   else `ULiveCampaignMissionEndSequence` (0x146efb6f0; e.g. a scripted MissionFailed with the player alive).
4. The death sequence (kill camera, ELiveHUDMode::KillCamera) then opens the retry menu (`LiveMenuRetryTopWidget`,
   EMissionMenuIDs::Retry). Root commands: `DT_LiveRetryMenuRootCommandsData_0` = RetryFromCheckPoint, RetryMission,
   ChangeDifficulty, QuitMission; `_1` = RetryMission, QuitMission (no-checkpoint variant).
5. A failure never reaches the debriefing and writes no clear (UI_SHOP_SAVE.md: tests 11-12 left Campaign.sav untouched).
Pause menu (`EPauseMenuID`): RETURN_TO_MISSION, RESTART_FROM_CHECKPOINT, RESTART_MISSION, QUIT_MISSION, each with an
ACCEPT_ confirmation. Quit -> QuitGame (reason 7). A checkpoint restart fires EP trigger `MissionRestart` (type 0x05,
int arg = checkpoint number; 265 stock records) and uses `LiveCampaignGameMode.RestartSequence` (+0x780); a mission
restart reloads the level (Survival's level-load path already resets: SV_Reset).

## 5. EP triggers for kills (ELiveEventTriggerType, from the usmap)
0x70 **ObjectDestroy** (`LiveObjectDestroyTrigger`: reflected WeakObject Attacker, Victim, VictimTrackedTarget),
0x6f ObjectDamage (Attacker, Victim), 0x71 ObjectCrashedDestroy (Victim), 0x72 UnitDamage (Attacker; what Survival's
SV_FlightDown_NN uses now, counts any loss), 0x1d DestroyTarget, 0x83 WingmanEnemyDestroy, 0x3a/0x3b PlayerDestroyByThreatLevel/Rank
(online), 0x62 RespawnedPlayer, 0x55 ResumeGame, 0x02 MissionFinish, 0x05 MissionRestart, 0x85 WatingRepair, 0x86 RestoreComplete.
ObjectDestroy args (19, positions fixed; from 3069 stock records):
```
 0 attacker faction  ELiveObjectTriggerFactionType (Any, LocalPlayer, EnemyNPC, Wingman, SystemObject, ...)
 1 None   2 Any|AnyAir   3 ELiveGameObjectCategory   4 SubCategory   5 BossCategory
 6 attacker object name (01)   7 attacker ObjNameID string (0d)   8 attacker tag (0a)
 9 WEAPON filter: NoneSelect = any; WID_mg (gun, M030 "Destroy_mmslct_Player_By_mg"); NormalMissile (M022 ObjectDestroy_ESM);
   WID_sod / WID_ugb / WID_gpb / WID_sffs ... (ELiveWeaponID); ELiveProjectileTypeParam also has SpecialWeapon, Flare
10 victim faction (EnemyNPC, Enemy, ...)  11 None|TGT (ELiveTargetMarkType)  12 Any|AnyAir|AnyGround|AnySea
13 category  14 subcategory (SubCategory_Bomber ...)  15 BossCategory_None|MatchCategory_None
16 victim object name  17 victim ObjNameID (e.g. ContainerAircraft_Name_mr2k)  18 victim tag
```
Stock "player kills any enemy aircraft" (16 records, e.g. M022): `LocalPlayer, None, Any, Category_None, SubCategory_None,
BossCategory_None, NoneSelect, "", NoneSelect, NoneSelect, EnemyNPC, None, AnyAir, Category_None, SubCategory_None,
BossCategory_None, NoneSelect, "", NoneSelect`, life `-` (repeating).

## 6. Score
- Per kill: `0x147d2aa40(victim, attacker)` = `int(BaseScore x 0x147d2a4b0(victim, attacker) x InformationManager+0xcb0)`
  (`LiveScoreConstTable.NpcKillScoreRate`; 0x147d2a4b0 is a per-attacker rate, e.g. aircraft cost / threat tables in
  ChronInformationSettings). Damage score (0x147d21a50) = BaseScore x rate x damage / MaxHealth x NpcDamageScoreRate.
  Both are queued per attacker (hash map, entry type byte 1 = kill, 4 = damage) by the death/damage code; the HUD shows the sum.
- Where the live total sits natively was not traced. The engine `APlayerState.Score` / GetScore exist but nothing shows
  Live writes them. The cheat manager's AddScore/SetScore are empty stubs in shipping (exec 0x144118210).
- Lua can read the displayed value: CampaignInfo widget (`LiveCampaignInfoWidget.ScoreText` / `PrivateScoreText`, already
  found by Survival's HUD code) -> `:GetText():ToString()`. Border "/32000" comes from LiveSetBorderScoreExecution (M022).

## How Survival should do it
**Kills / credits (pick by need, in this order):**
1. Lua, no new code: keep the LiveAIPlane poll; on the first tick a plane is dead (`HealthInternal <= 0` or
   `not obj:IsAlive()`), read in the same tick: `DamageHistoryMap` (UE4SS 3.0.1 has TMap in Lua: "Parameter must be of
   type 'TMap'" in UE4SS.dll; ForEach untested) -> killed by the player if the pawn is a key (share = its damage / total);
   `LastAttackingSpecialWeaponOwner == pawn` -> SPW kill; `pawn.LastFiredWeaponTarget == plane` hints at a missile
   kill; distance = |victim - player|; aspect = angle between the victim's forward vector and (player - victim)
   (> 120 deg = from behind); BaseScore -> credits (`credits = CFG.credit_base + BaseScore x CFG.credit_rate`, or a table
   by aircraft row). A dead plane stays an object for TimeToDeactivateAfterDeath, so a 250 ms poll still finds it.
2. Game's own attribution by weapon: add ObjectDestroy triggers (args above, attacker LocalPlayer, victim EnemyNPC +
   AnyAir) with arg 9 = WID_mg / NormalMissile / SpecialWeapon (the last one untested), each `LiveSetFlagInt Add 1` on
   SV_KillGun / SV_KillMsl / SV_KillSpw, plus one with NoneSelect -> SV_KillPlayer. Lua reads the deltas per tick
   (flags as in main.lua's flagLine). Crash kills (manoeuvre kills) are then the difference to SV_Kills.
3. Native, full detail (needs a test): vtable-hook Die (slot +0xb38) on LiveAIPlane's vtable (0x14c551db0, slot value
   0x147c919f0), chaining to the original as the menu hooks do. At entry the victim holds +0x480 damage type,
   +0x484 causer and +0x498 last player attacker (compare the weak ptr's ObjectIndex with the pawn's InternalIndex
   `[pawn+0xc]`, no GUObjectArray lookup needed). Queue {victim address, by player, type, time} in a ring buffer;
   Lua drains it with `SV_KillEvents()` and matches `obj:GetAddress()`. Never call Lua from the hook.
**Score:** don't base credits on the game's score (includes damage score, rate tables, border score). Use per-kill
BaseScore and Survival's own table; read ScoreText only if the HUD should mirror it. Consider hiding the "/32000".
**Health (shop repair, HUD):** Lua can read `pawn.HealthInternal / 10`, `pawn.MaxHealth`, `pawn:GetDamagePercentage()`.
For writes add native `SV_Health([max])` and `SV_SetHealth(value)` built from RestorePlayerPlane's bytes: player = the
same owner path as SV_Ammo; `SV_SetHealth(v)` calls vfunc +0x918 (clamps itself); `v < 0` = full repair = exactly
the stock node (SetHealth(Max) + pool +0x1400 refilled from +0x13fc). Writing `pawn.HealthInternal` from Lua works too
but can't refill the native pool. Don't use the ModifyHealth UFUNCTION on the player (no-op).
**Death and run end:**
- Detect: `NotifyOnNewObject("/Script/Live.LiveCampaignPlaneDeathMissionEndSequence", ...)` (created exactly when the
  player is dead at mission end), backed by polling `GameMode.MissionFinishReason` (2 shot down, 3 crashed, 7 quit)
  and `pawn:IsAlive()`. Record the run (rounds, kills, credits, time) at that moment, before any menu.
- Let the stock failure flow run (no save write); show Survival's summary over the kill camera / retry menu, and
  reset the run on RetryMission (level reload) or quit. Never use MissionClear.
- To end a run on purpose (e.g. airfield lost, if that ends runs): `LiveMissionFinishExecution MissionFailed, false,
  true` from Survival's EP (the M015 record) -> retry menu, no debrief, no save. Optional later: player MinHealth
  (`pawn.MinHealth = 0.1`, the M026 trick) to hold the player at 1 HP, show the summary, then kill with
  LiveDestroyPlayerPlaneExecution; crashes may bypass MinHealth (damage type 7 path).
- Watch `MissionRestart` (EP trigger 0x05 -> remote event / flag) in case a checkpoint restart happens without a reload.

## Open questions (test)
1. Does `NotifyOnNewObject` fire for LiveCampaignPlaneDeathMissionEndSequence, and how long before the retry menu?
   Which retry list (with or without checkpoint) does Survival's row get?
2. UE4SS Lua TMap read of DamageHistoryMap (`ForEach` key = attacker UObject).
3. ObjectDestroy weapon filter: does arg 9 accept `SpecialWeapon`? Do missile kills of planes match `NormalMissile`?
4. Does the HUD "DMG n%" include the +0x1400 pool, and what sets +0x13fc (parts? difficulty `PlayerHealthModifier`)?
5. Does the stock in-game hangar (landing) repair the player itself (UI_SHOP_SAVE open question)? Decides where the
   shop's repair is applied.
6. RegisterHook on `/Script/Live.LiveGameObject:OnDeath`: only fires if the game calls it through ProcessEvent
   (it is a native UFUNCTION, likely a child-death delegate) - check before relying on it.
7. Name of the damage-type enum (+0x480; 1, 0xe, 7/8/9 seen) for "killed by gun / missile / crash" natively.
