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
ModifyHealth(float InValue, UObject* DamageCauser, bool bCauseDamageEvent) -> float [impl 0x147d1ccb0], SetMinHealth(float)
[exec 0x147d193b0: MinHealth = min(max(0, int(value)), int(MaxHealth)): **whole health points only**, 0.1 -> 0; the
user's co-op run of 2026-10-30 died from 40 HP with SetMinHealth(0.1) set every pass. Write the reflected field
`MinHealth` for a fraction: the damage clamp reads it as is, GetMinHealth vfunc +0x928 = `movss xmm0,[rcx+0x3b8]` for
the player (0x146dc5730), and 0.1 HP stores as HealthInternal 1 (SetHealth truncates h x 10.0f)],
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

## 7. DOWN, its autopilot and the respawn (runtime 0.28.5, runtime/flight.c + down_ctl.c, 2026-10-30; untested in game)
The user (2026-10-29): "is there a revive option ... if you die ... you get put into a spectator camera". The runtime
gives Lua two pieces; keeping a DOWN player alive (MinHealth, section 4), the camera, the HUD and the revive are Lua's.
[V] verified by reading the code, [I] inferred, [?] for the test to settle.
### SV_Down(plane, cx_cm, cy_cm, alt_m, radius_m) -> 1 or an SV_ERR code; SV_Down(0) -> 1 (off)
- While on, OnBuildInput (the BuildFlightInput detour, after SV_Invert) gives that plane's pitch, yaw, roll, throttle and
  brake (high-G 0) from down_ctl.c's autopilot: a circle of radius_m round (cx, cy) at alt_m; the player's stick,
  throttle and brake do nothing. Its pose is read natively each frame (coop.c CoReadPose: the root component's world
  location and FRotator); velocity, Euler and body rates come from their changes. BuildFlightInput runs 2-3 times a
  frame: calls within 8 ms give the last inputs again.
- Guidance: the heading wanted is the circle's tangent turned in (outside) or out (inside) by 90 deg x (r - R) / R
  (clamped -45..80) plus a slow integral of the radius error (whatever bank the flight model needs for that radius);
  bank wanted 0.9 x the heading error, at most 40 deg (25 when lower than alt - 600 m or 400 m), kept on one side through
  a ~180 deg error; climb angle wanted 0.04 deg a metre of altitude error plus its slow integral, -12..15 deg. Roll input
  from the bank error (and a small integral of it: a flight model whose roll input asks for a bank angle, not a rate,
  stops short without it) less the roll rate, -0.5..0.5; pitch input from the climb-angle error less the pitch rate,
  over cos(bank), -0.35..0.5, none while upside down (it rolls back first); throttle and brake 0 = AC8's neutral, cruise
  speed (BuildFlightInput: throttle and brake are separate 0..1 inputs [V]); every input slewed at most 3 a second.
- Input signs [?]: which way a positive pitch or roll input moves the plane isn't settled by the code: BuildFlightInput
  passes InputPitch / InputRoll through, FlightEngine::SetInput (0x144d32580) negates pitch, yaw and roll into its own
  frame [V], and that frame's sense wasn't traced. So the first DOWN of a session learns them: hands off until the plane
  is calm (at most 1.5 s), roll +0.3, -0.3, -0.3, +0.3 for 0.25 s each, wings levelled (at most 2 s), the same with
  pitch; each sign is that of (the mean body rate under +) - (under -) when they differ by 2 deg/s or more, else +1 is
  kept and said. About 3-5 s of small inputs, in which a plane that went DOWN diving loses some height; later DOWNs
  circle at once. Once a test log shows `down: input signs learned (roll N, pitch N)`, the next runtime can start with
  them known (flight.c g_dnKnown / g_dnSRoll / g_dnSPitch) and never probe.
- Guards: a live player plane (coop.c CoKind 2), the local one (PlayerOwner(world) of Survival's level, AMMO.md);
  |cx|, |cy| under 10,000 km; alt 50-15000 m; radius 200-30000 m; BuildFlightInput hooked. Called again for the same
  plane while on: only the circle changes, the autopilot keeps its state. Codes: -4 bad args (or not a player plane),
  -5 BuildFlightInput not hooked, -1 / -6 not in Survival's level (yet), -12 not the local player's plane.
- Offline: tools/checks/flight_test.sh flies it against model planes (each pair of input signs; a rate-command roll, a
  bank-angle roll and a quicker plane; from far away, an inverted dive near the centre, a climb beside it; a pause in a
  probe; the signs known): the signs learned every time, and over the last 50 s of 200 within 30 % of the radius (most
  within 5 %) and 120 m of the altitude. The model planes aren't AC8's flight model.
- Log lines: `down: autopilot on plane <p>: circling (x, y) m at A m, radius R m; the plane at ...; learning the input
  signs first (...)` (or `input signs known`); `down: roll probe: body roll rate N deg/s at input +0.3, N at -0.3: roll
  input sign N` (or `inconclusive, roll input sign kept N`), the same for pitch; `down: input signs learned (roll N,
  pitch N): the next DOWN circles at once`; every 10 s `down: autopilot (<phase>, N s): N m from the centre (radius R),
  N m high (want A), heading error N deg, bank N (want N), climb N deg; inputs pitch N, roll N (x1000); input signs
  roll N, pitch N`; at the end the same line as `down: autopilot off (Lua)` / `(respawn)` / `: the plane is gone`;
  `down: refused: ...`.
- The test must confirm: the plane circles steadily at the altitude with no one flying it (the 10 s lines); the signs
  learned (to fix them in the next build); the probe isn't violent; nothing fights the autopilot (BuildFlightInput's
  flags byte bit 0 makes SetInput zero every axis; plane +0x58DC set gives zeros and flags 4: neither cleared here).
### SV_Respawn(plane, x, y, z, pitch, yaw, roll) -> 1 or an SV_ERR code
- The player plane's own respawn, vtable +0xbf8 (slot 383) = 0x147d6d440 (sigs.h kSigPPRespawn, 40 bytes, unique):
  `void (plane, const FVector* location, const FRotator* rotation, bool skipMove)` [V], from its callers: Online Mode's
  respawn at a respawn point 0x147d29220 (0x147d28e80 fills the location from the point's component translation, (0, 0,
  7000) by default, and the rotation from its quaternion; then vfunc +0xbf8; 0x147d6d3b0 calls that one and fires
  OnRespawnFinish). With skipMove false [V]: a camera / HUD flag when the game mode and the plane qualify; byte +0xdfd =
  0; slot 186 TeleportTo(location, rotation, false, false) (the player plane's: replay record, AActor::TeleportTo with
  the encroachment test, ProcessEvent(OnReposition) = its look reset, the flight-model reset 0x147d40830); vfunc +0x8e0
  = 0x147d1c440 SetActive(true) through 0x147d1c390 (replay event 0x12; the active byte +0x3f4); ProcessEvent(OnRestored);
  byte +0xdbd = 1; the movement-input block bits +0x13b8..+0x13be bit 0 cleared and re-applied (0x147d60ca0:
  bEnableMovementInput and kin); 0x1478c6f40(+0x1b90); HUD calls for the local plane; 0x147d28d90; and EP trigger 0x62
  RespawnedPlayer. It doesn't touch health, MinHealth or the dead flag +0xdb8 [V for the function; I: OnRestored's
  blueprint may restore the look]. Health stays Lua's (section 3: RestorePlayerPlane's SetHealth, or the pool).
- Guards: a live player plane, the local one, its vtable +0xbf8 the function found, the code's shape checked (+0x133
  `mov byte [rdi+0xdfd], 0`, +0x13a the skipMove test, +0x157 `call [rax+0x5d0]`); the position finite, |x| and |y|
  under 1,000 km, z -500 m to 30 km (all cm), pitch -90..90, yaw and roll -360..360. DOWN goes off for that plane first.
  Codes: -4, -5, -1 / -6, -12 as SV_Down.
- Log: `respawn: the player plane's respawn <p> (vtable +bf8)` (first use); `respawn: plane <p> respawned at (x, y) m,
  z m high, pitch P yaw Y roll R (it was at ...); now N m off that spot, heading H; health N of N (x10), dead flag N,
  active N`; `respawn: refused: ...`.
- The test must confirm: the plane appears at the pose and flies on (speed, controls back), nothing of the campaign
  mode's death flow starts (call it on a living plane: DOWN keeps it alive), and whether OnRestored restores its look.

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
