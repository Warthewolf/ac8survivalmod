# Survival Mode: reverse-engineering plan (for the Tuesday reset)

Written 2026-11-01. Covers what still has to be reverse engineered or confirmed, in order, so work can start straight away.
Most systems were already researched (tools/re/*.md, BUILD_PLAN.md "Research backlog"). Nearly all of that is from
AceCombat8.exe of 2026-09-29 and is *researched, not confirmed in game*. This plan sorts the gaps by what blocks a playable run.

## Phase 0: baseline and patch check (first hour)
Run this first in any case. If the game was patched, do it before anything else.
1. Record the exe build (date, size, hash) in tools/re/README or here. Re-run `tools/re/peinfo.py`.
2. Re-run every native signature (`tools/re/sigfind.py`, runtime `ScanCode` patterns): transition (vtable 0x111
   GetNextMenu), text, pause validity, hangar decide, BuildFlightInput, SpawnUnits/SpawnUnitByName, UnregisterUnit,
   LiveSetWeaponAmmoCount copy, remote-event (SV_Event), BGM controller. Each must still match **exactly once**.
3. Re-check the hard-coded offsets in runtime/survival_rt.c against the reflected layout (`tools/re/refl.py`):
   WORLD_GAME_INSTANCE 0x1D8, GI_CAMPAIGN_CONTEXT 0x8E0, CTX_MISSION_ID 0xF38 / CTX_MODE 0xF60, CMD_STRING_ARGS 0x130,
   SPAWNER_UNIT_CLASS 0x2E8, PLANE_AI_LEVEL 0x1048, ammo (+0x16a8, W+0x2e8 / +0x2e0), PLAYER_TARGET 0x1ae8 -> 0x750,
   GI_SOUND_MANAGER 0x908, BGM +0x120 / +0x13C / +0x14C, input pitch +0xff8 / roll +0xff4.
4. Check that Stonehenge Returns' main.dll still hooks the same slots, so Survival keeps chaining onto them (STONEHENGE_MAIN_DLL.md).
5. Re-extract the stock tables Survival copies from (`tools/get_stock.sh`): DT_NPC, M22 world data, DT_LiveMissionTable,
   radio tables. Diff them. If any changed, rebuild with `tools/build_all.sh`.
Gate: if a signature or offset moved, fix the runtime before running any test below.

## Phase 1: confirm the core loop (blocks everything; one test session)
The economy review build (Lua 0.70.x, runtime 0.19.0) has never been run. Use the log lines in ECONOMY_REVIEW.md.
| # | Question | Source note | How |
|---|----------|-------------|-----|
| 1 | Kill attribution: UE4SS TMap read of DamageHistoryMap (key = attacker) | KILLS_HEALTH_DEATH Q2 | log per kill: player / ally / other |
| 2 | Do missile and gun kills match the ObjectDestroy weapon filter (NormalMissile, SpecialWeapon)? | KILLS Q3 | kill with each weapon |
| 3 | Does the landing hangar repair / refill by itself? Where does the shop's repair go? | KILLS Q5, AIRFIELD Q4 | land at 50 % damage, read health before / after |
| 4 | HUD "DMG n%" vs HealthInternal and the +0x1400 armour pool | KILLS Q4 | SV repair, compare HUD |
| 5 | Death: does NotifyOnNewObject see LiveCampaignPlaneDeathMissionEndSequence in time for SECOND CHANCE? | KILLS Q1 | die once with and once without |
| 6 | Can Lua write FlagData.IntegerFiled (airfield HP reset)? | AIRFIELD Q3 | write, read back, watch the trigger |
| 7 | MissedWeapon_V2 on invincible dummies: hits counted? first one dropped (hard rule 6)? | AIRFIELD Q1, Q2 | M22 strike round, count per bomb |
| 8 | Compass: is north -Y? | ECONOMY_REVIEW | raid callout vs minimap |

## Phase 1b: STORE freeze while the online host is landed (user, 2026-11-01; top priority)
Bug: in an online session, while the **host** sits landed at the airfield with the STORE (in-game hangar) open, the
aircraft freeze. The notes don't cover the online session yet, so this starts with its basics.
1. Session basics: which machine owns the AI planes (host = server / authority?), how plane movement reaches the clients
   (replicated movement or the game's own sync), and where Survival's Lua runs (host only, or every player).
   Dump with reflection: the planes' `bReplicates` / `bReplicateMovement` / `NetUpdateFrequency` / `Role`, and the GameState / PlayerState classes.
2. Trace what the in-game hangar does on open / close (`FinishInGameHangar`, DT_LiveMenuIngameHangarCommands,
   AIRFIELD_SHOP_UI.md, UI_SHOP_SAVE.md). Look for SetGamePaused, global time dilation, the server's world tick, net
   update switches, or the AI being suspended (BrainComponent).
3. Log on host **and** client every tick while the host is landed: `IsGamePaused`, `GetGlobalTimeDilation`, the game
   clock, and for a few planes location, `CustomTimeDilation`, `IsActorTickEnabled`, net role. Which planes freeze
   (enemies, allies, the client's own plane?), on which screen, and does it change first on the host or the client?
4. Compare: the client landed while the host flies (no freeze = it's the host's / server's pause); a stock online-mode
   airfield, if one exists; Survival offline (landing alone).
5. Survival's own side while landed: sv_shop.lua / sv_main.lua (shop input, ammo panel, rearm re-apply), the chase
   (RE_SV_Chase every 6 s), SV_Spawn, and anything gated on the local player being in the hangar that runs only on the host.
6. Likely fixes, by cause: the hangar pauses the server -> keep the server's world running (hook the pause, restore time
   dilation) only while a session is online; Survival's own code stops the round -> gate it on the player, not the world.
Done when: the log names the switch that stops the planes, and a fix is tested online with the host landed for a whole round.

## Phase 2: enemies and AI (difficulty depends on it)
- PilotRank range and clamp (0..5? AI_BEHAVIOURS Q). Live write of PilotRank / AILevel (+0x1048) after spawn: does behaviour change?
- Open questions in BEHAVIOUR_NATIVE_LOGIC §14, BEHAVIOUR_NATIVE_MOVE and BEHAVIOUR_SCRIPTS §7: blackboard keys our
  NLID_SV_* sets may use, Selector variants, the unnamed option (not a speed). Needed before the "learning enemy" layer.
- Difficulty spike pursuit distances (live writes, untested).
- NPC_DATA open questions: which DT_NPC fields scale health / weapons safely. Ladon health x(1 + 0.04/round) via HealthInternal.
- Aircraft outside M22's table: confirm the DT_SV_NpcMission rows are cached at level start for every new airframe
  (EVENTS_AIRCRAFT: an uncached id crashes, `[0+0x110]`).

## Phase 3: specials (one per test, in rotation order)
- Ladon (0.70.6: Ladons alone, no escorts), Comona Defense shuttle, amphibious (LCAC/BTR beaches, SPECIAL_ROUNDS Q),
  Alicorn (ALICORN §4.3: does Online Mode content load offline, LiveSubmarineOperation), AB.L..IN blinks over low
  ground (0.57.0 clearance), named aces (Mercenary tier). For each: the open-question list in its note, then the log.
- Helios / portal VFX (HELIOS_VFX §5): one unchecked manager pointer offline; check it before using LiveFireHelios.
- VALKA is parked (2026-10-25). Only resume it on request (AIRCRAFT_MATERIALS: what loads her textures early, paint 1 vs 2).

## Phase 4: UI, radio, save (polish; not blocking)
- UI_SHOP_SAVE open questions: shop input from INP_Menu*, debriefing screen, own save in %LOCALAPPDATA%\AC8SurvivalMode\, unlocks.
- HUD colour source (HUD_LAYOUT: still to be found; config value for now).
- MUSIC_RADIO_CAMERA open questions: whether the radio uses the global FString lookup 0x1473B1750; what interrupts round BGM.
- Speaker enemy look via DT_SpeakerTable row switch (hard rule 33, not confirmed).
- MINIMAP_MARKERS: LiveRadarMapSearchAreaActiveException, ping types offline.

## Method (every item)
1. Static first: reflection dump, stock mission records (MISSION_REFERENCE.md, node_catalog.tsv), then the exe (fn.py / xrefs.py).
2. Log-only probe in Lua or runtime, test-only (stripped by strip_test_only.py), then the real feature.
3. One in-game test per batch, with the exact log lines to look for written down before the test.
4. Confirmed -> new hard rule in AGENTS.md. Disproved -> fix the note in tools/re/.
5. After every Lua edit: `python -X utf8 tools/checks/lua_check.py mod/UE4SS/AC8SurvivalMode/Scripts/*.lua`.

## Suggested first day
Morning: Phase 0 (signatures, offsets, table diff). Afternoon: one build with Phase 1 probes, one test session of
3 rounds plus a landing plus a death, read UE4SS.log against the table above. Evening: write the results into AGENTS.md
and BUILD_PLAN.md, then start Phase 2.
