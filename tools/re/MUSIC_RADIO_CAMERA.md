# Music, radio and event camera (research, 2026-10-22)

Research for Milestone 2's music items and research backlog items 6 (radio tables) and 14 (pause-menu music player +
event camera). Nothing here has been tested in game yet. Scratch dumps are under `build/research/audio/` (not in git).
Tools used: `tools/checks/ep_dump.py`, `tools/re/execvt.py`, `tools/re/refl.py`, `tools/re/exe.py`, uprop/zen.
Addresses are for the current AceCombat8.exe. Find them by signature, as the spawner does.

## A. Mission music (BGM)

### Event nodes (exact args from stock EPs)
| Node | Args (ArgsInfo Type: Value) | Stock use |
| --- | --- | --- |
| `LivePlayBGMExecution` | `0d` Wwise event name, `10` float `0` | M22 `MissionStart` -> `AKE_Bgm_Ms22A_Play`; M24 `MissionStart_9` -> `AKE_Bgm_Ms24A_Play` |
| `LiveStopBGMExecution` | `0d` stop event | M22 `Default_RemainingTime_7` -> `AKE_Bgm_Ms22A_Stop`; M06 `RE_ChangeBGM_Impact_0` -> `AKE_Bgm_Ms06A_Stop` |
| `LiveEventBGMExecution` | `0d` event (state / system event) | M24/M26 `InSupplyBGM` -> `AKE_System_Bgm_InSupply`, `OutSupplyBGM` -> `AKE_System_Bgm_OutSupply`; M06 `..._DistanceToLand_8000m_SetState` |
| `LivePlayBGMWithPositionExecution` | `0d` event, `11` `true`, `10` `0` | M22 `Default_ReturnFromHangar` -> `AKE_Bgm_Ms22A_TimeRestart_Play` (resume after the hangar) |
| `LiveSoundGeneralPostEventExecution` | `0d` event, `0b` actor (`NoneSelect`) | M08: `AKE_GEN_UI_HUD_Notice_AchieveTargetScore_Play` (any non-BGM sound) |

Every one of these node classes is in Mission 22's EP, so `survival_events.py` can clone them (`g.exec_template(...)`);
Survival already plays `AKE_Bgm_Ms08A_Play` at `MissionStart` this way.

Mission switches between tracks: M06 stops A (`RE_ChangeBGM_Impact_0`) and then plays B. M22 and M23 just play B over A
(`Default_CompositeEvent_127` -> `AKE_Bgm_Ms22B_Play`; M23 `PostRadio_02_Microwave_Irradiation_bgm_Change` ->
`AKE_Bgm_Ms23B_Play`).

### Landing / supply (Missions 024 and 026, identical)
- `TRIG InSupplyBGM`: type `3f` (volume event), args `06 Volume_ReturnBase_0` (M26: `Box_Return_0`) | `0a NoneSelect` |
  `0e Enter` | `0e Any` | `01 NoneSelect` | `02 NoneSelect` | `0a NoneSelect`, then
  `LiveEventBGMExecution AKE_System_Bgm_InSupply`.
- `TRIG OutSupplyBGM`: type `99` (return from the minigame / hangar), args `0e TakeOff` | `0f 0`, then
  `LiveEventBGMExecution AKE_System_Bgm_OutSupply`.
- Mission 22 does it its own way, with triggers Survival's EP already has: `Default_MiniGameEnding` (type `9a`, `0e SeamlessIn`, ...)
  -> `LiveEventBGMExecution AKE_Bgm_Ms22A_SupplyIn_State`. `Default_ReturnFromHangar` (type `99`, `SeamlessOut`) and
  `Default_ReturnFromHangar_1` (type `99`, `TakeOff`) -> `LiveStopBGMExecution AKE_Bgm_Ms22A_SupplyOut_Stop` and
  `LivePlayBGMWithPosition AKE_Bgm_Ms22A_TimeRestart_Play`. Mission 8 posts `AKE_System_Bgm_InSupply` from volume
  events and `AKE_System_Bgm_OutSupply` on `Default_ReturnFromHangar`.
- `AKE_System_Bgm_InSupply/OutSupply` are generic, not tied to a track: they're in the campaign bank's event list
  (with `AKE_System_Bgm_SetBusVolume_Down` / `_ResetBusVolume` / `_MissionFailed_Stop`). Use these for Survival.

### What the node does (exe)
- `LivePlayBGMExecution::Execute` 0x1473df1f0, `LiveStopBGMExecution` 0x1473df6d0, `LiveEventBGMExecution` 0x1473df930
  (from `execvt.py`). Path: `GetWorld` (vfunc 0x188) -> world+0x1D8 (game instance, class-checked) -> +0x908 -> +0x170 =
  the game's **BGM controller**. Play calls `0x1478bdad0(bgm, &playingId, FName* event /*node+0x58*/, float delay /*node+0x60*/)`.
- That float is a **delay**. When it's 0, the controller looks the event up in `EventDelayList` of
  `/Game/WwiseAssets/DA_SoundBGMSetting` (class `LiveSoundBGMDataAsset`), e.g. `AKE_Bgm_Ms06B_Play` 8.7 s,
  `AKE_Bgm_Ms27A_Play` 8 s, `AKE_Bgm_Ms23A_Play` 1 s. A delayed post is queued at controller+0x1A0. The same asset
  holds `BGMBankList` (AKB_BGM_Campaign, AKB_BGM_Cinema, AKB_Online_Jukebox, bgm_chunk1, AKB_BGM_Online,
  AKB_BGM_Online_Lobby) and `HighPriorityBGMIDs` = {`AKE_Bgm_GameOver_Play`} (a high-priority track can't be replaced).
- No UFUNCTION plays BGM through this controller: it's native only. The only reflected way to post a Wwise event by name is
  **`ULiveSoundBlueprintLibrary`** (`/Script/Live`, verify the module), with static UFUNCTIONs `PostEventByName(WorldContextObject, Name InEventName)
  -> LiveSoundPlayingID`, `PostEventAtActorByName(Name InEventName, Actor InActor)`, `PostEventByAkEvent`,
  `PostEventAtActorByAkEvent`. `UAkGameplayStatics` (`PostEvent`, `SetState`, `StopAll`, ...) takes UAkAudioEvent
  objects, and the campaign BGM events have no AkAudioEvent asset (only 73 BGM event .uassets exist; the campaign
  tracks live only in the bank database).

### Tracks (bank AKB_BGM_Campaign, `/Game/WwiseAssets/Database/DA_SoundDB_AKB_BGM_Campaign`)
The bank database lists 562 events, each with its Wwise duration (`LiveSoundDBEvent.DurationType` 0 OneShot / 2 Infinite,
`DurationMin/Max`). Full table: `build/research/audio/bgm_durations.tsv`. This bank is loaded in Survival (Ms08A plays).
- **Mission tracks, `Infinite` (they loop in Wwise):** `AKE_Bgm_Ms02A/02B/03A/04A/04B/05a/06A/06B/07A/08A/09A/09B/10B/11A/
  11B/12a/13A/14A/15A/15B/16A/17A/17B/18A/18C/19A/19B/20A/20B/20C/20D/21A/21B/21C/22A/23A/23B/24A/25_1A/25_1B/25_2A/
  26A/26B/27A/27B/28A/28C/29B/30A/30B/30C/30D_Play`. Stop event = same name with `_Stop` (e.g. `AKE_Bgm_Ms08A_Stop`).
  Some are interactive, i.e. Wwise states move them on (`..._State` / `_SetState` events, e.g. Ms06A DistanceToLand,
  Ms23A FindCELAENO). Without the state they stay in their current section, which is fine for Survival.
- **Short one-shots, avoid:** `AKE_Bgm_Ms22B_Play` 43 s, `Ms09_SotoaBattleSong` 35 s, `Ms26_SotoaBattleSong` 31 s,
  `Ms26postB` 40 s, `Ms04C` 12 s, `GameOver` 11 s.
- **Music-player versions (OneShot, full length, known duration):** `AKE_Bgm_MUSICPLAYER_BGM_<id>_Play`, e.g. M08A 280.8 s,
  M22A 458.7 s, M24A 285.6 s, M27A 346.1 s, M30B 554.8 s, M09B 321.8 s, SongOfWings 275.5 s, HortusLegisAlti 320.9 s.
  They end, but Lua knows each length, so it can queue the next track. Stop: `AKE_Bgm_JukeBox_All_Stop` /
  `AKE_Bgm_MUSICPLAYER_Fade_Out_100ms` (names from the exe; not checked against the bank).
- System BGM events, in the always-loaded game-SE bank (`DA_SoundDB_AKB_GameSe`): `AKE_System_BGM_Stop`, `_Stop_00s`,
  `_Stop_01s`, `_Fade_Out_01s`, `_Fade_In_01s`, `_Pause_On/Off`, `_Mute_On/Off`, `_Reset`. They stop or fade whatever is playing, so
  you don't need to know the current track's `_Stop` name.

**"Music stops around round 5": not explained.** `AKE_Bgm_Ms08A_Play` is `Infinite` in the bank metadata, so it shouldn't
just end. Possible causes, in the order to check: (1) Ms08A is an interactive track whose loop section needs Mission 8's
`AKE_Bgm_Ms08_PurpleMagicA_State` to carry on; (2) the airport minigame (Mission022_MiniGame) or landing posts a
system BGM event; (3) the game's own BGM stop on some mission event. Rotating the track every round sidesteps all three.

### How Survival should do it
1. **Event-package route (works with today's tools):** in `survival_events.py`, one remote event per track,
   `RE_SV_Bgm_<Track>`: `LiveEventBGMExecution AKE_System_BGM_Fade_Out_01s` (or `_Stop_01s`; whether these reset the
   controller's own state is untested, so `LiveStopBGMExecution <previous>_Stop` is the fallback),
   then after 1.5 s `LivePlayBGMExecution AKE_Bgm_<Track>_Play` with delay `0`. This way the event never needs the
   previous track's `_Stop` name. Lua fires `RE_SV_Bgm_<Track>` at round start through a native
   `SV_Event(name)` (`LiveCallRemoteEventExecution`'s dispatch, HUD_NOTES.md; not in survival_rt.c yet). Until
   `SV_Event` exists, the EP could pick the track from an int flag with `Equ` conditions (conditional
   `LiveCallRemoteEventExecution` works, probe test 3), but only if Lua or native code can write that flag (unverified).
2. **Native route (cleanest):** `SV_PlayBGM(name, delay)` in survival_rt.c: find `0x1478bdad0` and the controller
   offsets (+0x908, +0x170) by signature from `LivePlayBGMExecution::Execute`, then call it with an FName. Goes through the
   game's own controller, so pause / mute / delay table / supply states keep working.
3. **Quick Lua test (no build):** `ULiveSoundBlueprintLibrary:PostEventByName(world, FName("AKE_Bgm_Ms24A_Play"))`.
   This posts outside the BGM controller (its game object may differ), so the controller's pause/mute and the
   `_Stop` events may not reach it. Use it only to audition tracks.
- Rotation (CFG in main.lua, overridable): normal rounds draw from a pool of combat tracks without repeats, e.g.
  Ms02A, Ms04A, Ms05a, Ms07A, Ms11A, Ms12a, Ms14A, Ms17A, Ms18A, Ms20A, Ms21A, Ms22A, Ms24A. Special (5th) rounds get a
  big track, e.g. Ms09B (shadow ace), Ms20D, Ms23B, Ms27A, Ms28C, Ms30A/30B. Both lists are guesses and need auditioning.
  Don't use cinematic, IGC, restart or skip variants.
- Landing: copy M24's pair. `InSupplyBGM` = Mission 22's own landing / hangar triggers (`Default_MiniGameEnding`,
  `SeamlessIn`) or a volume trigger on the airport, then `LiveEventBGMExecution AKE_System_Bgm_InSupply`. `OutSupplyBGM`
  = type-99 `TakeOff` trigger (`Default_ReturnFromHangar_1` is that exact record) + `AKE_System_Bgm_OutSupply`.
  Both nodes and both trigger types are in Mission 22's EP.
- Music player in use (topic B): skip the per-round switch when Lua sees the player chose music.

## B. Pause-menu music player
Scratch: `build/research/audio/pause/`. Static analysis only.

### The entry already exists in the stock pause menu, but it's hidden
- Root page `/Game/Datatables/UI/Menu/IngameMenu/Pause/DA_PauseMenuRootPageSettingData` (LiveMenuPageSettingsData) soft-refs
  `/Game/Datatables/UI/Menu/IngameMenu/Pause/DT_LivePauseMenuCommandsData` (row struct `LiveMenuCommandsDataTable`, same as
  the main menu's). Rows, in order: Return, PauseRestartCheckPoint, PauseRestartMission, PauseSelectDifficulty,
  PauseFlightSystemTopMenu, **NewRow_3: TitleTextID `DataviewerGallery_Select_Music`, StringArgs `PauseMusicPlayer`,
  InvalidAppearance 2 (Invisible)**, PauseQuit. No row has bIsInvalid / RefFeature set: native code decides.
- MenuID `PauseMusicPlayer` opens `/Game/Blueprints/UI/Menu/Ingame/Pause/WBP_Menu_PauseMusicPlayer_000` (native class
  `LiveMenuPauseMusicPlayerWidfget`, sic) through `/Game/Datatables/UI/Menu/IngameMenu/DT_IngameMenuSettingData`
  (LiveMenuClassTable). Page settings `DA_PauseMenuMusicPlayerPageSettingData_000`.

### What hides it (exe)
- The pause list builder 0x147b564f0 (a ULiveMenuPauseWidget virtual) calls IsFreeFlight (0x147edb650, inlined): true
  when `LiveDifficultyManager.CurrentDifficulty == 6`. ELiveDifficulty: 1 Casual ... 5 Ace, **6 FreeFlight**. (A debug
  byte 0x14e525e34 also makes it true.) Free flight isn't its own mission row: it's a campaign row
  (`bIsPermissionSelectFreeFlight`) flown on difficulty FreeFlight.
- Not free flight: the invalid list is {"PauseMusicPlayer"}. Free flight: {"PauseRestartCheckPoint", "PauseSelectDifficulty"}. If
  the singleton at 0x14e4c50e8 (0x147930430) has byte +0x220 set, "PauseMusicPlayer" is greyed out instead.
- The list goes to **UpdateCommandValidity 0x147b575d0** `(ctx = &widget, TArray<FString>* invalidStringArgs, bool grayout)`,
  called only from the builder. For each row in widget+0x690 (stride 0x1B8, StringArgs FString at +0x130) it sets
  bIsInvalid (+0x140) = StringArgs is in the list. Unique signature (mksig, 30 bytes):
  `48 89 5C 24 10 44 88 44 24 18 48 89 4C 24 08 55 56 57 41 54 41 55 41 56 41 57 48 83 EC 30`.
- Picking an entry: 0x147b53390 maps StringArgs to a command type (PauseMusicPlayer = 0xF); decide 0x147b54090 ->
  transition 0x147a88370(widget, type+3); the last type picked is byte +0x368 of the object returned by 0x147a681e0.
- `LiveLevelTable` (mission row) has `GameModeType` (campaign 1, free flight 6), `PhaseRandomBGMIDList` (empty in every
  stock row), `HangarBGMID`, `DebriefingBGMID`. It has no music-player flag.

### How Survival should do it
- **Not** by flagging the mission or setting difficulty 6: that would turn on free flight everywhere (checkpoint and
  difficulty hidden, other HUD and retry behaviour) and overwrite the chosen difficulty. No row needs adding either.
- Native hook (survival_rt.c) on UpdateCommandValidity 0x147b575d0, found by the signature above. While Survival's mission
  (9101) runs, remove every "PauseMusicPlayer" string from the invalid list, then call the original. Make it chain onto
  any earlier hook, like the menu hooks (Stonehenge's main.dll doesn't hook it; check STONEHENGE_MAIN_DLL.md). Lua alone
  can't do this: widget+0x690 isn't reflected.
- Detect "player picked music": Lua `NotifyOnNewObject` on
  `/Game/Blueprints/UI/Menu/Ingame/Pause/WBP_Menu_PauseMusicPlayer_000.WBP_Menu_PauseMusicPlayer_000_C` (the page opened)
  sets `player_music = true`, and round music switching stops. Native alternative: command type byte (+0x368) == 0xF.
  `LiveMusicPlayerSoundManager` only reflects `SoundController` / `EnvironmentalBGMController`; the music classes have
  no UFUNCTIONs. A "reset to round music" option could clear the flag at the next round.
- Track list: `/Game/Datatables/Sound/DT_SoundMusicPlayerBGM` (`LiveSoundMusicInfoRow`: TitleTextID, TitleString,
  bIsEnableUnlock, UnlockMissionID, Filter1-3, ...). It has 75 rows named after their Wwise event `AKE_Bgm_MUSICPLAYER_BGM_<id>_Play`
  (M22A "The Star-Bound Bird", ...). Useful for naming Survival's rotation tracks on the HUD.
- Music-player questions: (a) after unpausing in a campaign-mode mission, does the chosen track keep playing, or do mission
  BGM nodes override it (if they do, Survival's own BGM events must also check the flag); (b) what the +0x220 byte is
  (it greys the entry out); (c) are tracks the player hasn't unlocked (`LiveMusicPlayerSaveData.OwnedMusicList`) hidden in the in-mission player.

## C. Radio (backlog 6)
Scratch: `build/research/audio/radio/` (`ms022_rows.tsv` = all 667 rows of Mission 22's table, `radio_execs.txt` =
every radio exec in the M06/08/13/15/22/23 EPs, `pbyp_cp_rows.tsv`).

### Assets and row structs (`/Game/Datatables/Radio/`)
- `DT_Rdo_ST_ms001..030`, `_mstut`: each mission's scripted lines, row struct **`LiveRadioTable`** (ms022: 667 rows, row
  names "1", "2", ...). `DT_Rdo_PByP_CP`: 7740 automatic play-by-play rows (same struct: `Player_Kill_Enemy`,
  `Player_Lockon`, `AWACS_Player_EnemyAzimuth`, ...), driven by `EP_Play_by_play_Radio_AWACS/Ally/Enemy/Wingman/...`.
- `DT_SpeakerTable` (1276 rows, `LiveRadioSpeakerTable`), `DT_ProcessTypeIDTable` (`LiveRadioProcessTypeTable`: ProcessID,
  VoiceTypeID, EnvseID), `OverrideRadioPLM/DT_Rdo_Override_msNNN` (`LiveOverrideRadioTable`),
  `AutomaticSpeakerIDTable/msNN_*` (`LiveAutomaticSpeakerTable`), `overridespeakertable/msNN_*`,
  `OverrideSpeakerOnDeath/*` (`LiveOverrideSpeakerIDOnDeathTable`). Online copies with the same structs:
  `/Game/OnlineMode/DataTables/RadioData/Mission/DT_Rdo_FF` (free flight), `DT_Rdo_C`, `DT_Rdo_TDM`, ...
- `LiveRadioTable` fields: `RadioGroupID` (what the node plays; a group = several rows played in row order), `RadioType`
  (Scenario / PlayByPlay / Chatter / ChatterInOrder), `Channel` (Main / Sub / InterruptMain ...), `Priority`,
  `LimitPlayCount`, `TextID`, `SpeakerID` (string), `bShowComWindow`, `Subtitle` (Default / ForceEnable / ForceDisable),
  `StartDelay`, `EndDelay`, `NextRadioGroupID`, `NextRadioGroupDelay`, `InterruptionType`, `bCheckAliveSpeaker`,
  `CheckRequiredWingmen`, per-mission switches `bM01..bM30` / `bT01..bT15` (all true in ms022).
- **Tables come from the level, not the mission row:** `ChronicleWorldSettings.RadioSettings` (`LiveRadioSettings`,
  PL_Mission022 export 23): `RadioDataTables[]` = [DT_Rdo_ST_ms022] (hard refs), `OverrideRadioTable` =
  DT_Rdo_Override_ms022, `RadioSpeakerTables[]` = [DT_SpeakerTable], `OverrideRadioSpeakerTables[]`,
  `AutomaticSpeakerTables`, `ProcessTypeTables[]`, `OverrideRadioSpeakerOnDeathTables`, `EventNotifyTables`.
  PL_SurvivalMode carries Mission 22's settings, so every ms022 group can already be played in Survival.
- **TextID = voice + subtitle key:** TextID `v2200_0030` plays Wwise `v2200_0030_Play` (bank AKB_Voice,
  `/Game/WwiseAssets/Database/DA_SoundDB_AKB_Voice`) and is presumably the subtitle key. The subtitle strings weren't read
  (not in any IoStore chunk; probably the legacy `pakchunk*.pak` locres).
- Speakers: `LIVE_AWACS` (ProcessID AWACS, AWACS noise, no portrait), `ms22_Comona_Space_Base_Air_Traffic_Controller`
  (Ally_GROUND_CONTROL), `LIVE_Maintenance_team_leader`, `LIVE_Tasha` (CallSign `Callsign_Joker3`, portrait).

### Nodes (from stock EPs)
- **`LiveRadioPlayExecution`** (2046 execs): `0d` RadioGroupID | `02 NoneSelect` (speaker unit; once `Wingman00_0`) |
  `0a NoneSelect` | `10 0` | `11 false` | `11 false` | `11 false`. M22: `RE_Wave01_Radio_Start` ->
  `00_Enter_BattleField`; `CompositeEvent_Destroy_1st` -> `01_Wave1_Destroy_Enemy_First`, 2 s later `..._First_After`;
  M24 `RemainingBullets_50_0` -> `01_Supply_Armament_50`; M26 `Introduction_Supply` -> `01_Introduction_Supply` (delay 5).
- `LiveSetActiveRadioTypeExecution` (`0e` PlayByPlay / Chatter / Scenario / ChatterInOrder; M08 adds `11 false` first),
  `LiveClearRadioQueueExecution` (`0d` group, empty = all), `LiveSetRadioMuteOptionsExecution` (`0e` type or None,
  `0d` group, `0d` ""), `LiveActivate/DeactivateOverrideRadioTableExecution` (`0d` override id, e.g. M13
  `ms13_OverrideRadio_Wing`), `LiveSetMuteRadioTensionExecution` (`0e` + `11`), `LiveSetMuteRadioSilentGroupExecution` (`11`).
- Triggers: type `24` PreRadioEvent / `25` PostRadioEvent, args `0d` RadioGroupID, `0d` TextID (M23
  `PostRadio_02_Microwave_Irradiation_bgm_Change` keys BGM on line `v0002_2642`).
- Runtime classes: `ULiveRadioWorldSubsystem`, `ALiveRadioPlayer`, `ULiveRadioManagerInterface`; also
  `ULiveMissionSimpleRadioWorldSubSystem`, `ULiveYesNoRadioWorldSubsystem` (the Yes/No radio prompt). A reflected cheat
  exec `PlayRadio(Name RadioGroupID)` exists (cheat manager, probably absent in shipping).

### Reusable Mission 22 groups (already loaded in Survival)
| Use | Group (TextIDs) | Note |
| --- | --- | --- |
| Airfield open / cleared to land | `00_permission_take_off_land` (v2200_0026, tower), `00_Start_Landing_land`, `00_Approach_Gear_Down_Volume` (v2200_0030-32) | tower only |
| Takeoff | `00_take_off_completion` (v2200_0029), `00_TakeOff_Again`, `00_prompt_take_off` | tower |
| Shop / resupply | `00_Enter_Supply_land` (v0036_0025, maintenance lead, PlayByPlay), `ms22_Supplypoint_1st` (AWACS v0001_2881), `00_Supplying_Ohayasi` | |
| Enemies inbound | `01_Wave2_Reinforcements_Attacker` (AWACS v0001_2816 + Baxter/Coster/Tasha), `01_Wave4_...`, `01_Wave5_...` (AWACS v0001_2859/2860/2861) | groups include wingmen |
| Round complete (guess) | `01_Wave2_Starting_to_Wave3` (AWACS v0001_2822/2823, Tasha v0003_1982/1983) | subtitle unread |
| Score | `01_All_Wave_20/50/75_Acquisition_Score` | |
Play-by-play (`Player_Kill_Enemy` etc.) needs no node.

### How Survival should do it
- Lines: Survival's own groups, so wingman lines (Baxter/Tasha, who aren't flying) are left out. **Build time (preferred):** a
  `/Game/Mods/SurvivalMode/Data/DT_SV_Radio` (`LiveRadioTable`, rows cloned from ms022 with only `RadioGroupID` changed,
  e.g. `SV_Inbound` = AWACS row v0001_2816, `SV_RoundClear` = v0001_2822, `SV_AirfieldOpen` = tower v2200_0026), added
  as a second entry of PL_SurvivalMode's `RadioSettings.RadioDataTables`. That is Survival's own level, and no shared table is touched.
  Run time AddRow on DT_Rdo_ST_ms022 would also work (hard-loaded by the level), but the radio subsystem may index rows
  at mission start, so prefer the build-time route.
- Fire: `RE_SV_Radio_<X>` remote events in EP_SurvivalMode_global, each one `LiveRadioPlayExecution` cloned from M22's
  7-arg record, called from Lua via `SV_Event` (or from the EP's own round flags).
- New text: a row whose TextID is an SV_ key (`SV_Radio_RoundClear`) could take its subtitle from the runtime's text hook
  (the global FString-keyed lookup 0x1473B1750, via wrapper 0x146EAF1C0, ~150 callers). It's unconfirmed whether the radio
  subtitle goes through it. With no `SV_..._Play` Wwise event the line would be text only
  (`LiveRadioDeveloperSettings.DisplayDurationForTextOnly` suggests that's supported). New voice would need a new bank.
- Radio questions: (a) the subtitle strings (needs a legacy .pak/locres reader); (b) do SV_ TextIDs reach the text hook;
  (c) is a line with no voice event shown or skipped; (d) are dead or absent speakers skipped (`bCheckAliveSpeaker` unset);
  (e) does play-by-play already run in Survival (what loads `EP_Play_by_play_*`); (f) names of PlayExecution args [2]-[6].

## D. Event camera (backlog 14)

### The node: `LiveEventFocusCameraExecution`
This is the "swing the view to the event" camera: it looks at a target unit or object with a named camera animation. It is used in M04,
M06, M08, M10, M11, M12, M17-M20, M22 and M23 (node_catalog). **Mission 22 already has one**, so Survival's EP can clone it as is:
```
EXEC RE_ShuttleFocusCamera  LiveEventFocusCameraExecution  delay=-  {01 Unit: AA_Obj_01_Ground0_Shuttle_0} | {0a Object: NoneSelect}
     | {01 Unit2: NoneSelect} | {0a Object2: NoneSelect} | {0d Camera: LookAt_Event_Camera_ms22-01} | {11 false} | {11 false}
EXEC RE_ShuttleFocusCamera  LiveEventFocusCameraExecution  delay=9  (all NoneSelect, camera "" , false, false)  <- ends it
```
- Args: [0] `01` target unit (world-data unit name), [1] `0a` target object (WD object, e.g. M19 `Obj_Rocket_Debri`),
  [2] `01` second unit / [3] `0a` second object (M06 `RE_CannonCamera_0`: target `CannonTarget_Phase01_Obj_0` + second
  `CameraTarget_Dummy_Obj_0`; looks like a "from" or framing point), [4] `0d` camera name, [5] `11` bool (TipsHash
  941811010; `true` only in M19 `Debri_Camera` and M23's core cameras), [6] `11` bool (436582458, always false).
- **End it with the same node:** everything `NoneSelect`, camera `""` (M22 9 s later, M06 `RE_CannonCamera_Stop_0`, M08 10 s later).
- Other examples: M08 Ladon takeoff `01_C_Ladon_Takeoff_PostRadioEvent_31` (target `EC_Obj01_Taxiing0_supersonicbomber_0`,
  `LookAt_Event_Camera_ms08-01`, only while bool flag `ladon_find` is false); M04 `RE_Phase02_Focus`
  (`AB_Obj_01_Air0_PPM1_Dummy_0`, `LookAt_Event_Camera_ms04-01`).
- Camera names resolve through `/Game/Blueprints/InGameCamera/BP_InGameCameraParameter` (a name -> camera anim map; anims are
  `/Game/Blueprints/InGameCamera/CameraAnim/LookAt_Event_Camera/CAS_LookAt_Event_Camera_*`). It's global, not per mission,
  and also has a generic **`LookAt_Event_Camera`** (+ `_Dummy`) besides the msNN ones.
- Exe settings it reads (strings): `EventFocusInGameCameraMinDuration`, `EventFocusInvalidDuration`,
  `EventFocusFOVZoomOutMax`, `EventFocusDistanceFOVCurve`, `EventFocusCameraShakeType`, `bUseFocusCameraLock`;
  sounds in the game-SE bank: `AKE_GEN_SPECIAL_EventFocusCamera_Enter_Play`, `_Exit_Play`, **`_PressButton_Play/Stop`**
  (so it's the button-prompt camera), plus Wwise RTPC/state `AKP_GEN_EventFocusCamera_MoveSpeed` and
  `AKST_Mixing_EventFocusCamera_isFocusing`. The class's constructor is in the protected (jumped-away) part of the exe,
  so `execvt.py` finds no vtable for it. Native use is out; use it through the event package.

### Related: `LivePlayInGameCameraExecution` (impact / kill camera)
`Execute` 0x1473fc5b0. Args: `0d` camera name, `0b` unit, `0b NoneSelect`. M04 plays `ImpactCamera_Common` on each
ace's destruction (`ObjectDestroy_Phase08_E_1..4`, units `EE_Obj_01_Ace0..3_m29a_0`); M16 `ImpactCamera_ms16*` on the
Ladons; M19 `ImpactCamera_ms19-01/02`. Generic names in BP_InGameCameraParameter: `ImpactCamera_Common`,
`ImpactCamera_Random`, `ImpactCamera_Front/Back/Side`. Trigger type `28` fires after it (`05_PostInGameCamera_Rocket`,
arg `0d ImpactCamera_ms19-02`). **Not in Mission 22's EP**: cloning it means adding the class import to
EP_SurvivalMode_global (hard rule 7 style; take the record from M04).

### How Survival should do it
- Ace / boss spawn, Helios barrage: `RE_SV_Focus_<Flight>` per pool / special unit = Mission 22's `RE_ShuttleFocusCamera`
  pair with arg [0] = the unit, camera `LookAt_Event_Camera` (generic) or a fitting msNN one (`ms08-01` Ladon takeoff,
  `ms22-01` shuttle), end record 6-9 s later. Make it fire once per spawn (hard rule 3), with a 2-3 s delay after
  `SV_FlightUp_NN` so the unit exists. Fire from Lua through `SV_Event`, or from the appear trigger.
- Shuttle launch (Milestone 7): use Mission 22's record unchanged (`AA_Obj_01_Ground0_Shuttle_0`, `ms22-01`).
- Ace shot down: `LivePlayInGameCameraExecution ImpactCamera_Common <unit>` (needs the M04 import).
- Config: a `CFG.event_camera = true` switch; skip the camera while landing / in the shop.

## Open questions
1. Why Ms08A stops (A above). A test that logs round times against when the music stopped would settle it.
2. Does `LivePlayBGM` over a playing track cross-fade, cut, or get refused? (M22/M23 do it, M06 stops first.) Test both.
3. Is `ULiveSoundBlueprintLibrary` in `/Script/Live`? Check with UE4SS `StaticFindObject` before relying on it.
4. Focus-camera bools [5] and [6]: the names aren't reflected (TipsHash only). Does [5]=true force the swing without
   the button prompt? Test M19's `true` against M22's `false`.
5. Do `AKE_System_Bgm_InSupply/OutSupply` work for a non-M24/M26 track (they look like bus/state events)?
6. Topic B and C questions are listed in their own sections. The most important for the plan: B(a), whether the pause music
   player survives unpausing or mission BGM nodes take over.
