# Store UI, debriefing, save game, unlocks (research 2026-10-22, backlog items 4, 7, 8, 11)

Research only: nothing here has been tested in game yet. Survival builds its own UI at run time in Lua (HUD_LAYOUT.md,
hard rule 18). This note lists what the game already has, what Survival can copy or reuse, and what it must not touch.

Scratch tools (not in the build): `build/research/ui/scripts/`
- `wbpinfo.py` / `reusable.py <pkgs>`: a widget blueprint's parent class and whether it has an event graph
  (`ExecuteUbergraph_*`). EaseIn/EaseOut exports are animation curves, not script.
- `dtrows.py <pkg> <RowStruct> [n]`: DataTable rows. Payload = 4 zero bytes, props, int32 0 (no GUID), int32 row count,
  then (FName, row struct)...
- `unlocks.py <DA_Unlock_*>`: condition -> action summary. `exps.py`: export list.
- Layout dumps of every widget pulled: `build/research/ui/layout/*.txt` (made with tools/re/hud_layout.py).

## 4. Store UI (airfield shop)

### Two UI frameworks in the game
| Framework | Base classes | Where | Used for |
| --- | --- | --- | --- |
| "Menu" (campaign, offline) | `LiveMenuGenericBaseWidget` < `LiveMenuBase` < `LiveWidgetBase` < UserWidget; parts `LiveMenuCommonBaseWidget` | `/Game/Blueprints/UI/Menu/...` | hangar, pause, retry, **in-game hangar**, debriefing, free mission |
| "NUI" (online era) | `LiveNUIRootUserWidget` < `LiveNUIUseMosaicUserWidget` < `LiveNUIUserWidget` | `/Game/NUI/...`, `/Game/OnlineMode/UI/NUI/...` | main menu (`LiveNUIMenuMainWidget`), online shop, dialogs |

Neither framework exposes UFUNCTIONs (refl.py finds none on LiveMenu*/LiveNUI* classes): everything runs in native code,
which is why Stonehenge/Survival hook vtables (STONEHENGE_MAIN_DLL.md: decide = slot 0xEE, GetNextMenu = 0x111).

### NUI/Shop is the online store: do not use it
`WBP_Menu_Shop_000` (parent `LiveNUIMenuShopWidget2`) carries `ShopAceCoinForm`, `RegionalStore`, `ShopContent`,
`ItemListDatas`; its data comes from `LiveShopAPIController` / `LiveShopGoodsDataTable` / `LiveCurrencyAPIController`
(Ace Coins, AcePass, gasha, platform purchases). Opening or driving it risks online/purchase code paths. Layout reference only.
- Item tile `WBP_Menu_Shop_Parts_ItemCommand_000` (`LiveNUIShopItemCommandWidget`): GridPanel; `[AIRCRAFT]` category
  (SizeBox 295x38), item name (SizeBox 560x60), price row = 48x48 currency icon + value "999,999" (32 high; red copy for
  "can't afford"; struck-through old price, Main 28), item image 624x352, NEW / SALE / rarity badges.
- `WBP_Menu_Shop_Parts_ItemScroll_000` = 10 tiles; `ListCategory_000` = 7 scrolls + pager; `Shop_000` = header + list +
  `WBP_NUIGuideFooter` (button hints) on the full 3840x2160 canvas.

### The in-game hangar: the stock "landed at base" menu (closest match to the shop)
Mission 22 (Survival's base mission) already has it. Flow, from M022's EP + the exe's enums:
1. Player lands at a base with takeoff/landing enabled (`LiveSetTakeoffAndLandingEventExecution`, M003/M004/M022;
   `LivePlayerTakeoffAndLandingComponent`: LandingControlTower / TakeoffControlTower / CatapultPointComponent).
2. HUD switches to `ELiveHUDMode::IngameHangar` (10) and the in-game hangar menu opens (exe string
   `Live.UI.Campaign.OpenIngameHangar`; camera `LiveIngameHangarCameraSystem`, DA_LiveIngameHangarCameraPropertySettings).
3. Pages (all `LiveMenuIngameHanagarCommonBaseWidget` subclasses, `/Game/Blueprints/UI/Menu/Ingame/IngameHangar/`):
   - `WBP_Menu_IngameHangar_Confirmation_000` (LiveMenuIngameHangarWidget): commands from
     `/Game/Datatables/UI/Menu/IngameMenu/IngameHangar/DT_LiveMenuIngameHangarCommands` (row struct
     `LiveMenuCommandsDataTable`, the SAME struct as DT_LiveMenuMainTopCommands):
     row 1 `MainmenuSystemGeneral_Select_Yes` (help CampaignReturn_Description_Takeoff, StringArgs "-1"),
     row 2 `MainmenuSystemGeneral_Select_No` (help CampaignReturn_Description_SpWeapon, StringArgs "3").
     Page title from DA_LiveMenuIngameHangarSettings (`LiveMenuPageSettingsData`: TitleTextID, TabSettings, BackGroundID).
   - `WBP_Menu_IngameHangar_Weapon1_000` / `Weapon2_000` (WeaponSetting1/2Widget): special-weapon select
     (DA_..Settings1 title `HangarSelectweaponTitle_Name_SelectSPweapon1`, tab "TAKE OFF").
   These three have small event graphs (`OnIngameHangarInitialize`); `WBP_Menu_IngameHangar_Common_000` (the window) has none.
4. On leaving: trigger `FinishInGameHangar` (ELiveEventTriggerType 157 = 0x9d), then `ReturnFromHangar` (153 = 0x99,
   arg `SeamlessOut` or `TakeOff`). M022 runs on FinishInGameHangar: SetActiveTrigger RemainingBullets_50/_20/_0/
   _30_sp/_30_normal, `Bool_IsLanding` = true, radio `00_permission_take_off`, start `Timer_supply_Interval`, engagement
   orders, `RE_BaseSupplyMute`. Supply music: `AKE_System_Bgm_InSupply` on entering the supply volume, `AKE_System_Bgm_OutSupply`
   on ReturnFromHangar/TakeOff (M008, M024, M026).
Window layout (`WBP_Menu_IngameHangar_Common_000`, 2944x1244 inside a 2970x1340 panel centred: x 435, y 410):
| Part | Widget | Offset in window |
| --- | --- | --- |
| Background | Image Base, black (0,0,0,0.5) | full window |
| Frame | WindowCorners: four 4 px Images, no texture (TopLine/BottomLine/LeftLine/RightLine) | edges |
| Title | WBP_MenuCommon_IngameHeader_000 (-> WBP_Menu_Detail_Text_007) | 80,74 |
| Command list | GridPanel -> WBP_Menu_Pause_List_000 (LiveMenuPauseCommandListWidget, 6 x WBP_Menu_Text_Focus_001, VerticalBox pad bottom -8) | 58,145 |
| Help text | WBP_MenuCommon_HelpText_001 | 119,1001 |
| Weapon stats | WBP_Menu_IngameHangar_WeaponDetail_001 (12 gauges, 14 values) | 1218,80 (1464x744) |
| Weapon info | WBP_Menu_IngameHangar_WeaponDetail_002 | 2090,668 |
List row `WBP_Menu_Text_Focus_001` (LiveUIFocusTextWidget): 828x88; focus marker `>` at x 40 (HUD 36, opacity 0 until
focused); label at x 88 (WBP_Menu_Text_000: Main 37). Rows are 80 apart (88 - 8).
The pause window `WBP_Menu_PauseCommon_000` (parent plain UserWidget, no graph) is the same frame at 2944x1244: header
80,74; list 58,146; help 116,688 (1640x240); objectives footer 80,940; minimap anchored top-right (-88,92).
The retry window `WBP_Menu_Retry_000`: 1802x897 at x 244, y 985 (bottom-left), same frame/header/list/help.

### Offline "buy" panel: aircraft tree MRP purchase
`WBP_MenuCommon_HangarAircraftTreeBuyDetails_000` (LiveMenuAircraftTreeBuyDetailsWidget, 1040x380), the stock look for
"balance / item / price": CurrentMRPTitleText at 0,0 with CurrentMRPText right-aligned at x 940; item names
(WBP_Hangar_Detail_Name_000, Main 33) at 0,85 with MainMRPText right at 940,85; dashed line (Main 36 "-----") at y 216;
"already purchased" row at y 300. All texts WBP_Menu_Text_000 scaled 0.8. Confirm dialog:
`LiveUIAircraftTreeBuyConfirmDialogContentsWidget` (NUI dialog `WBP_Menu_Common_Dialog_000`, has an event graph).

### Widgets with no event graph that Survival can create as bases (like WBP_HUD_NonGlowMessage_000)
Plain UserWidget parent, no ubergraph (only pure GetTextBlock getters):
| Widget | Contents | Use |
| --- | --- | --- |
| `/Game/Blueprints/UI/Menu/Ingame/Pause/Common/WBP_Menu_PauseCommon_000` | the 2944x1244 pause frame (but embeds functional LiveMenu parts + minimap) | shop window base; collapse its list/minimap |
| `/Game/Blueprints/UI/Menu/Debriefing/Common/WBP_Briefing_Detail_Text_000_4K` | row: Title (x 44, 560 w, Main 33), Num_01 (right edge 788, HUD 33), Num_02 (right edge 1032, HUD 33) | price rows, summary rows |
| `/Game/Blueprints/UI/Menu/Common/Parts/WBP_Menu_Detail_Text_000(_4K)` | "[ LABEL ]" (Main 24) | section labels |
| `.../Parts/WBP_Menu_Text_000` / `_001` / `WBP_Menu_Text_Header_000` | one text: Main 37 / HUD 33 / Main 41 | items, numbers, title |
Menu text style: font UI_FontSet_ja, typefaces `Main` (labels) and `HUD` (numbers, monospaced), colour
(0.91,0.93,0.93,1), RenderOpacity 0.8. Texts are `LiveLocalizeTextBlock` (a TextBlock subclass that localizes a key):
set Survival's text after construction, and test that it isn't re-localized over.
Parts with a Live* parent (LiveUIFocusTextWidget, LiveMenuPauseCommandListWidget, LiveMenuHeaderWidget, ...) expect
native set-up by their page; creating them stand-alone is untested.

### Menu input and focus
- Menu framework: classic action mappings (strings in the exe): `INP_MenuAccept`, `INP_MenuCancel`,
  `INP_MenuUp/Down/Left/RightKeyOnly` and `...StickOnly`, `INP_MenuL1/R1/L2/R2`, `INP_MenuSquare`, `INP_MenuTriangle`,
  `INP_MenuOptions`, `INP_MenuPauseMenuClose`, `INP_Pause`. Pages handle decide natively (vtable slot 0xEE on the page);
  page changes go through the transition function (Stonehenge's sig8) and `GetNextMenu` (0x111).
- NUI: `ELiveNUIInputActionType` (Up/Down/Left/Right/Decision/Cancel/TabPrev/TabNext/...) mapped by
  `/Game/NUI/System/Input/BP_NUIInputSettings` (`LiveNUIInputSettings.InputActionMap`) to action names `NUI_Decision_Pri`,
  `NUI_Cancel_Pri/_Sec`, `NUI_Up_Pri/_Sec`, `NUI_Down_Pri/_Sec`, `NUI_Left_Pri`, `NUI_Right_Pri`, `NUI_TabNext_Pri`, ...
- Sounds: `ELiveMenuSoundIDs::IngameHangar_Accept / _Cancel / _MoveCursor / _No / _Sortie`.

### How Survival should use this
1. Open Survival's shop from the stock landing flow, not instead of it: land -> the game's in-game hangar opens
   (the camera, the stopped aircraft and the blocked flight input come with it). Two options, prototype in this order:
   a. Own shop panel on Survival's run-time layer, shown while `ELiveHUDMode::IngameHangar` is active (watch the HUD
      mode or the Confirmation page's creation from Lua), hiding the stock confirmation behind it; on "Take off" let the
      stock page continue. Input: poll `PlayerController:IsInputKeyDown` for the keys bound to `INP_MenuAccept/Cancel/Up/Down`
      (`InputSettings:GetActionMappingByName`), so player rebinds work with pad and keyboard. Edge-detect in the existing
      LoopAsync job; no per-frame timers (hard-learned heap-crash rule).
   b. Data path: AddRow shop items into `DT_LiveMenuIngameHangarCommands` at run time (same struct as the main-menu rows,
      same load/pin/watch handling as hard rules 10/11) and route their decide in the native runtime (chain like the
      main-menu hook, StringArgs "SV_Buy_*"). Limited: the list widget has 6 rows (2 used), no price column.
2. Look: copy the in-game hangar window (black 0.5 base, 4 px frame lines, header at 80,74, rows 80 apart with the `>`
   marker at x 40, label x 88, help line at the bottom) and the BuyDetails layout for CREDITS / item / price (price
   right-aligned, red when unaffordable like the shop tile). Build from TextBlock/Image primitives on the existing layer;
   use WBP_Briefing_Detail_Text_000_4K rows where a stock row fits.
3. Ammo: the stock in-game hangar may refill ammo itself (M022 checks RemainingBullets triggers on FinishInGameHangar).
   Apply Survival's cap AFTER `FinishInGameHangar` (CFG.ammo / the shop purchase), or the stock refill overrides the cap.
4. Music: In/OutSupply BGM on landing/takeoff (BUILD_PLAN music item) uses the same two triggers.
5. When copying M022's supply records, leave out `LiveUnlockAchievementsExecution`, `LiveMissionFinishExecution`,
   `LiveSetBorderScoreExecution` and the RE_Wave6 score records (see section 11).

### Open questions (shop)
- What exactly opens the in-game hangar: the landing component on stop, or an event? Does Survival's map (with
  Mission022_MiniGame) open it already when landing (BUILD_PLAN test 5 follow-up: landing works)? Log the HUD mode.
- Does the stock in-game hangar refill ammo / repair, and by how much (full load?) - decides where the cap is applied.
- Can Survival's widget take focus over the stock page, or do both receive INP_MenuAccept? (May need the native runtime
  to swallow the page's decide while the shop is open, like Stonehenge's transition hold-back.)
- `IsInputKeyDown` / `GetActionMappingByName` from UE4SS 3.0.1 Lua (FKey struct param) is untested.

## 7. Debriefing / results screen

### How the stock debriefing works
- Only after `LiveMissionFinishExecution` with `MissionClear` (args: result enum MissionClear/MissionFailed + bools).
  A failed mission/death goes to the retry menu (`LiveMenuRetryTopWidget`, WBP_Menu_Retry_000; commands
  `LiveMenuRetryCommandsTable`), never to the debriefing.
- Page: `/Game/Blueprints/UI/Menu/Debriefing/WBP_Menu_Debriefing_000` (`LiveMenuDebriefingWidget`; event-graph-free,
  one BP function GetRewardRowWidgets), booted by WBP_Menu_DebriefingBoot_000 (`LiveMenuDebriefingBootWidget`: LevelSequence).
  It replays the mission on the briefing map: `LiveDebriefingDecoder` (replay speeds), `LiveDebriefingKillMarkManager`,
  `LiveDebriefingUnitActor`, camera `LiveDebriefingCameraActor`; settings `/Game/Blueprints/BriefingDebriefing/DA_BriefingDebriefingSettings`.
- Fed natively from the mission's result (`LiveMissionResultData`/`LiveGameResultData` have no reflected fields).
  `LiveMenuDebriefingWidget.ResultTextWidgets` = Map<row name, {ParentWidget, TextBlocks Map<Name, TextBlock>}>; row title
  text IDs: TotalTime, DestructionScore, TimeBonus, CheckpointRestart, RankScore, RankBonus, Rank, LandingBonus,
  RefuelingBonus, HealthBonus, HealthPerfect, GunOnlyBonus, InitialComplete, RoundBonus, TotalReward, TotalMRP,
  GroundTargets, TotalDestroyed; `ContentPerSituation` FollowReplay / FinalDisplay.
- Per-mission data from the mission row (`LiveLevelTable`): `DebriefingSettings.SubtitleTable` (radio, e.g.
  `/Game/Datatables/Radio/Debriefing/DT_Rdo_DBR_msNNN`, rows `LiveMenuDebriefingSubtitleData`: RadioGroupID + interrupts),
  DebriefingStartSequence, Debriefing*CinemaIDs, `DebriefingBGMID`. Survival's DT_SV_MissionRows still carries M022's:
  SubtitleTable DT_Rdo_DBR_ms022, BGM AKE_Bgm_Debriefing02.
Layout (3840x2160): header WBP_MenuCommon_Header_000 at 264,100 (Main 41); Left_Part 240,296 (1032 wide): mission
label, TotalTimeRow, [RANK], DestructionScore/TimeBonus/CheckpointRestart, dashed line, RankScore, Rank, [MAP REWARD],
RewardRow_0..7, line, TotalReward, TotalMRP; Right_Part right-anchored (x 2570, 1066 wide): [TARGET DESTROYED],
12 DestroedObjectRow (57 px apart), GroundTargets, TotalDestroyed; Center_Part (x 1387) the expanded list.
Every row is WBP_Briefing_Detail_Text_000_4K (Title / Num_01 / Num_02).

### How Survival should use this
- Don't route a run's end through the stock debriefing: it needs a MissionClear, and a clear writes the player's
  campaign save (mission record, score, MRP reward, replay info; see section 8: Stonehenge's 9001 is in the user's save).
  It also shows MRP rewards Survival must not give.
- Build Survival's own end-of-run summary on the run-time layer, shown when the player is shot down (before the retry
  menu takes over) and on quitting: copy the debriefing's left column (x 240, y 296, 1032 wide, rows 57 apart,
  header at 264,100) with WBP_Briefing_Detail_Text_000_4K rows: ROUNDS SURVIVED, KILLS (air / ground), CREDITS EARNED /
  SPENT, TIME, BEST ROUND (from Survival's own records), NEW RECORD marker. Same data later feeds the leaderboard submit
  (Milestone 8).
- Set DT_SV_MissionRows' debriefing fields to neutral values (no M022 radio) in case a clear is ever reached.

### Open questions (debriefing)
- Does the retry menu appear immediately on death, and can a Lua widget stay on top of it (Z order / input)?
- What does the 60-minute mission time limit do (fail -> retry menu)? A long run would hit it.

## 8. Save game

### Where and how the game saves (looked at only, nothing written)
`%LOCALAPPDATA%\BANDAI NAMCO Entertainment\ACE COMBAT 8\Saved\SaveGames\` (exe: `%sSaveGames/%s.sav`, enumerates `*.sav`;
own save system `LiveWindowsSaveGameSystem`, `SaveGameSystemModule`):
| File | Class | Holds |
| --- | --- | --- |
| Campaign.sav (~0.5 MB) | `LiveCampaignSaveGame` < LiveSaveGame | SavedVersion, PackedData, Checksum (`LiveCommonSaveData` + `LiveCampaignSaveData`) |
| System.sav | `LiveSystemSaveGame` | key config, language, sound, flight system, stick, display, graphics, accessibility |
| OnlineAccount.sav | `LiveAccountSaveGame` | credential, online menu badges, settings |
| OnlineLocalCacheMSD_0.sav | `LiveMasterSaveGame` (LiveMasterSaveData: ApiVersion, BinaryData, Crc) | online cache |
| Replay0..12.sav | `LiveReplaySaveGame` | replays (2-55 MB each) |
| steam_autocloud.vdf | - | Steam Auto-Cloud syncs this folder |
Format: GVAS 3 (UE5 package version 1012), class path `/Script/Live.LiveCampaignSaveGame`; PackedData is a plain
tagged-property stream (readable, not encrypted) with a checksum at the end. `SkinStudioSaveBackups\` next to it is a
third-party tool's backup folder (the user's own backups).
Contents that matter: `LiveCampaignSaveData`: CompletedMissionList (`LiveMissionSaveData`: MissionID, DifficultyList
{HighestRank, SortieCount, RecordList}, LastRank...), AccumulatedScore(ByMission), Unlocked*/NewlyUnlocked* lists,
AircraftTypeRecords (per-plane kill counts, flight time), WeaponTypeRecords, AircraftSets, ReplayInfos, MiscFlags.
`LiveCommonSaveData`: UnlockData (`LiveUnlockSaveData`: CA entry ID, activated), medals/skins/emblems lists,
UnlockedAircraftTreeNodeIDs, OwnedAircrafts, OwnedParts, CurrentMRP, TotalMRP.

Evidence from the user's save (read only, 2026-10-22):
- MissionID **9001** (Stonehenge Returns' mission) is in CompletedMissionList (with a difficulty record), the free-mission
  unlock lists and a ReplayInfo. So a modded mission that is cleared is written permanently into the real save.
- MissionID 9101 (Survival) appears nowhere. Campaign.sav was rewritten on 10-22 00:43, after Survival tests 11-12
  (10-21, dozens of kills), yet aerial kills (2213), sortie counts (90), MRP (171394 / 5141644) and AccumulatedScore
  equal the 10-20 23:12 backup: runs that end without a clear did not touch the save.

### Safest way for Survival to persist its data (best runs, "ace memory")
- Own file, never the game's save. Lua `io.open` already works from main.lua (hud_dump.txt in the mod folder).
- Format: a Lua table file (`return { version = 1, best = {...}, runs = {...}, ace = {...} }`), read with `loadfile`
  in a pcall like survival_config.lua; or a plain `key=value` text. Keep a `version` field for migrations.
- Atomic write: write `survival_records.tmp`, keep the previous file as `.bak`, then `os.rename` (Windows rename does not
  overwrite: remove the old file first). Write only at run end / round clear, never per frame.
- Location: not in `Saved\SaveGames` (the game enumerates `*.sav` there and Steam Auto-Cloud syncs it). Suggested
  `%LOCALAPPDATA%\AC8SurvivalMode\` (survives mod reinstalls and launcher toggles), falling back to the mod folder;
  name it in the config so players can find and reset it ("reset ace memory" option in config).
- Don't use GameplayStatics SaveGameToSlot: it would go through the game's save system into SaveGames and needs a
  SaveGame subclass Survival doesn't have.
Risks to the player's real save:
- Clearing Survival's mission (LiveMissionFinishExecution MissionClear) would add a 9101 record, score and possibly MRP,
  kill stats and medal progress to Campaign.sav, synced to Steam Cloud. If Survival is later uninstalled the save still
  references 9101 (the 9001 precedent shows the game keeps such records; whether it copes without the mod is untested).
- Saving a replay of a Survival run writes a ReplayN.sav + ReplayInfo for 9101 that can't play without the mod.
- Survival's EP has no MissionFinish / achievement / score nodes now (checked: 74 triggers, 221 execs); keep it that way.

### Open questions (save)
- When exactly does the game write Campaign.sav (mission end only, or also on quit to menu / retry)? Do kill stats of a
  failed or quit Survival run ever get saved (evidence says no for the runs so far)?
- Does the ACE8 Mod Launcher delete or overwrite `Mods\AC8SurvivalMode\` on toggle/update (decides the file location)?
- Is `os.getenv("LOCALAPPDATA")` available in UE4SS 3.0.1 Lua (else the native runtime can provide the path)?

## 11. Unlock tables

### What is unlocked how
`/Game/Unlock/`: `BP_ConditionActionManager` (`LiveConditionActionManager`: CADataAssetMap, ConditionActionAssets) and
`DA_Unlock_*` (`LiveConditionActionDataAsset`: MinId, MaxId, ConfigurationEntryList of `LiveCAConfigurationEntry`
{ID, ConditionEntryList {ConditionType, Parameters string}, ActionEntryList {ActionType, Parameters string}, Meta}).
State is saved per entry ID in LiveCommonSaveData.UnlockData.
| Asset | Entries | Conditions -> actions |
| --- | --- | --- |
| DA_Unlock_Achievement | 55 | CompleteLevel 34, GainStats 3, CollectItem 6 -> UnlockAchievement (`AchPs4:ACH_CLEAR_MISSION_001` ...) |
| DA_Unlock_AircraftTree | 1 | CompleteLevel `MissionID:15,Mode:Campaign` -> UnlockAircraft `Id:PP0013_a06e` |
| DA_Unlock_AssaultRecord | 83 | DestroyTargetInMission (`Count:>=4,AssaultID:ms04_Shadow`) -> UnlockAssaultRecord |
| DA_Unlock_Emblem | 112 | CompleteLevel `MissionId:AllBase` -> UnlockEmblem |
| DA_Unlock_Feature | 10 | CompleteLevel AllBase (Difficulty:>=Hard) -> UnlockFeature (AceDifficulty, AircraftSet, Skin, Emblem, Weathering...) |
| DA_Unlock_Medal | 29 | DestroyTarget `Count:>=1000,Mode:Campaign` (also by weapon/type), GainStats, CompleteLevel -> UnlockMedal |
| DA_Unlock_Skin | 586 | CompleteLevel 541, DestroyTargetInMission 44 (TacName), CollectItem 29 -> UnlockSkin |
| DA_Unlock_Training | 15 | CompleteLevel MissionID:3 -> UnlockTraining |
Enums: `ELiveCAConditionType` Always, CompleteLevel, ObserveAnniversary, GainStats, EarnScore, DestroyTarget, CollectItem,
PurchasePackage, PlayLevel, ActivateCAEntry, MissionSpecific, PerformanceEvaluation, DestroyTargetInMission;
`ELiveCAActionType` UnlockLevel, UnlockAchievement, UnlockMedal, UnlockEmblem, UnlockSkin, UnlockAircraft,
UnlockAircraftWeapon, UnlockAircraftPart, UnlockAircraftTreeNode, UnlockFeature, UnlockTraining, UnlockAssaultRecord.
Aircraft tree: `/Game/Datatables/UI/Menu/HangerMenu/AircraftTree/DT_LiveMenuAircraftTreeNodeDataTable` (90 rows,
`LiveMenuAircraftTreeNodeDataTable`: NodeType Aircraft/Parts, ReferenceId (plane 7010, 23010... / part 2050802...),
NodePosition, CostBase1..4 (MRP: aircraft 25 000-130 000, parts 5 000-45 000), UnlockTrigger Free 82 / ClearAllMission 7 /
ReleasedByStory 1, Src/DstReferenceNodeIDs). Bought nodes go to UnlockedAircraftTreeNodeIDs / OwnedAircrafts / OwnedParts,
paid from CurrentMRP. Steam achievements are also fired directly by `LiveUnlockAchievementsExecution` (10 missions, M022 included).

### How Survival should use this
- Award nothing to real progression: no MRP, aircraft, parts, skins, medals or achievements. These live in Campaign.sav
  (Steam Cloud) and can't be taken back; MRP buys aircraft, so Survival would become an MRP farm.
- Survival-only rewards (titles, best-run badges, "ace memory") go in Survival's own records file (section 8) and show
  on Survival's own UI.
- Copy no CA/achievement records or nodes from stock missions; never AddRow into DA_Unlock_* or the aircraft tree table.

### Open questions (unlocks)
- Is the CA manager evaluated at mission end only, or live (e.g. a DestroyTarget medal reached mid-mission)? If live,
  Survival kills could advance kill-count medals ("Mode:Campaign") even without a clear. The unchanged kill totals
  suggest not, but no medal threshold was crossed during the tests.
- What "AllBase" covers (assumed the 31 base campaign missions).
