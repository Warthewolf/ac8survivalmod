# The landing menu (in-game hangar) and a Survival STORE page (research 2026-10-23)

Research only, nothing tested in game. Builds on UI_SHOP_SAVE.md section 4 (window layout, the two UI frameworks,
fonts) and HUD_LAYOUT.md (run-time widgets, hard rule 18). Minimap / HUD markers are in MINIMAP_MARKERS.md.
Labels: **[V]** verified from the files or the exe (static), **[I]** inferred, **[T]** needs an in-game test (section 4).

Method: usmap schemas (tools/usmap.pkl), `tools/checks/dump_props.py`, `build/research/ai/dt.py`, `tools/re/hud_layout.py`,
`tools/re/exe.py` + llvm-objdump on AceCombat8.exe. Newly pulled into build/stock/: every `DA_LiveMenu*` settings asset,
`Datatables/UI/Menu/IngameMenu/{DT,DA}_IngameMenuSettingData`, the pause / retry command tables, `WBP_Menu_Pause_List_000`,
`WBP_Menu_Text_Focus_001`, `WBP_Hangar_IconParts_000`, `WBP_Menu_Detail_Text_005`, `WBP_MenuCommon_{List,ScrollList}_000`,
`WBP_MenuCommon_HelpText_001`, `WBP_MenuCommon_IngameHeader_000`.

## 1. How the landing menu's pages and "tabs" work

### 1.1 Pages are in-game menus, chosen by index **[V]**
The landing menu is part of the in-game menu system (`LiveMenuManager`, a world subsystem; it also runs pause, retry,
replay and briefing). Its settings asset `/Game/Datatables/UI/Menu/IngameMenu/DA_IngameMenuSettingData`
(`LiveMenuSettingsData`: BootMenuReference = WBP_Menu_Pause_Boot, MenuClassTable = the table below) names the table
`/Game/Datatables/UI/Menu/IngameMenu/DT_IngameMenuSettingData` (row struct `LiveMenuClassTable` {MenuID: FName,
MenuWidgetReference: soft class}). The rows, in table order:

| Index | Row | MenuID | Widget |
| --- | --- | --- | --- |
| 0 | NewRow | RetryMenu | Retry/WBP_Menu_Retry_000 |
| 1 | NewRow_0 | PauseTopMenu | Pause/WBP_Menu_PauseTop_000 |
| 2 | NewRow_1 | ReplayMenu | Replay/WBP_Menu_Replay_000 |
| 3 | NewRow_2 | IngameHangarWeaponSetting1 | IngameHangar/WBP_Menu_IngameHangar_Weapon1_000 |
| 4 | NewRow_6 | IngameHangarWeaponSetting2 | IngameHangar/WBP_Menu_IngameHangar_Weapon2_000 |
| 5 | NewRow_7 | IngameHagarMenu (sic) | IngameHangar/WBP_Menu_IngameHangar_Confirmation_000 |
| 6-15 | NewRow_8 ... NewRow_4 | PauseRestartFromCheckpointMenu, PauseRestartMissionMenu, PauseQuitMissionMenu, PauseFlightSystemTopMenu, Controller/Mouse/GamePlay/DisplayOptionsMenu, PauseSelectDifficulty, PauseMusicPlayer | Pause/... |
| 16 | NewRow_17 | Briefing | Briefing/WBP_AirBriefing_000 |
| 17-19 | NewRow_5, _16, _18 | ReplayDataSave, ReplayViewer, RetryMenu_ChangeDifficulty | Replay/..., Retry/WBP_Menu_Retry_001 |

The manager keeps it as reflected `LiveMenuManager.MenuWidgetClassList` (TArray of {MenuIDName: FString, MenuClass}),
plus `MenuStack` (LiveMenuStack {StackMenus [{Menu}], RootMenu}), `UniqueMenuIDs` (Map<Object, int>) and
`MenuSettingsData`.

The MenuIDs themselves are not in the exe (no "IngameHagarMenu", "PauseTopMenu", ... in either encoding). The code
works with an index instead:
- The pause / retry decides map their row's StringArgs with a name table (0x147b53390: "PauseTop" 1, "Replay" 2,
  "HangarWeaponSetting1" 3, "HangarWeaponSetting2" 4, "Hangar" 5, "PauseRestartCheckPoint" 6, ... "Briefing" 16,
  "Retry_ChangeDifficulty" 19, unknown 21) and then call `transition(page, id + 3)` (0x147b5431b, 0x147b58211,
  0x147b6274d). These ids match the table's row order exactly.
- The landing menu's decide (LiveMenuIngameHangarWidget vtable 0x14c80d868 slot 0xEE = 0x147b02960, the function
  Survival's OnHangarDecide hooks) does `n = _wtoi(StringArgs)`; `n < 0` -> `transition(page, 2)` (close = take off) plus
  sound 59 IngameHangar_Sortie; `n >= 0` -> `transition(page, (uint8)n + 3)` plus sound 60 IngameHangar_No.
  The stock "No" row has StringArgs "3", so it opens menu 3, the special-weapon page. Its cancel (slot 0xEF,
  0x147b02a80) does `transition(page, 6 or 7)`, i.e. menu 3 or 4, plus sound 56 IngameHangar_Cancel.
- `transition` (0x147a88370) stores the id at page+0x3E0. Once the page has closed, the consumer (0x147a87dc3) calls
  the LiveMenuManager's (0x14725e6b0: world subsystem StaticClass 0x146edd000 = ULiveMenuManager) vfunc +0x358 with
  that id. So a page change replaces one page with the next, and the target is "in-game menu id - 3".
- **[I]** That's why a Survival row with StringArgs "SV_Buy_*", left to the stock decide, would open menu 0 (RetryMenu).
  The runtime comment calls it "page 0".

**What this means:** a landing-menu row with StringArgs "N" opens in-game menu N. A row Survival adds to
DT_IngameMenuSettingData lands at index 20 (AddRow with a new name appends, hard rule 11), so a row "20" would open
Survival's own page. **[I]** That the manager indexes MenuWidgetClassList by id - 3, and checks the bounds, is not
proven yet (its vtable sits in protector-obfuscated code; ctors 0x146ee2490 / 0x146edca50 are packed). Tests T1-T3.

### 1.2 Page classes **[V]**
- `LiveMenuIngameHanagarCommonBaseWidget` (sic) < LiveMenuGenericBaseWidget (`RootPageSettingsData`, `CommonWidgets`
  Map<ELiveMenuCommonType, Object>) < LiveMenuBase (`ChangeProcessDetails {MenuClass}`, `ProhibitionInputObjects`)
  < LiveWidgetBase < UserWidget. Its subclasses are `LiveMenuIngameHangarWidget` and
  `LiveMenuIngameHangarWeaponSetting1Widget` (< 2). No UFUNCTIONs except the BlueprintImplementableEvent
  `OnIngameHangarInitialize(LiveIngameHangarParameterInfo)` and `SetParameter`.
- `LiveIngameHangarParameterInfo` = {GlowPanelName, TitleTextID (FName), CommonMenuWidget, MenuTitleWidget,
  SpecialWeaponDetailTextWidget, ExclusionSpecialWeaponDetailTextWidget, DetailWidget} (weak objects).
- `WBP_Menu_IngameHangar_Confirmation_000` (and Weapon1/2) is a thin shell: CanvasPanel_70 (2970x1340, centred) ->
  the window `WBP_Menu_IngameHangar_Common_000` (whose class is also LiveMenuIngameHangarWidget). Its only script is
  OnIngameHangarInitialize -> MakeStruct(GlowPanelName = Conv_StringToName(GetObjectName(..)), TitleTextID
  "CampaignReturnTitle_Name_Resupply", the Common widget's parts) -> SetParameter. Imports: only the Common widget and
  DA_LiveMenuIngameHangarSettings (store.txt). No other package imports the page, which is loaded softly through
  DT_IngameMenuSettingData.
- Window parts (Common_000, reflected): `WBP_Menu_Detail_Text_000_01` (header, WBP_MenuCommon_IngameHeader_000),
  `WBP_Menu_Pause_List_000` (list), `WBP_MenuCommon_HelpText_000` (help, class HelpText_001),
  `WBP_Menu_IngameHangar_WeaponDetail_001` (gauges), `WBP_Menu_IngameHangar_WeaponDetail_002` (ammo), `base`,
  Top/Bottom/Left/RightLine, `Mosaic_In`. Offsets are in UI_SHOP_SAVE.md (list 58,145; help 119,1001; details 1218,80
  and 2090,668; header 80,74; window at 435,410 on the 3840x2160 canvas).

### 1.3 The command list: 6 fixed rows, text only **[V]**
- `WBP_Menu_Pause_List_000` (`LiveMenuPauseCommandListWidget` < `LiveMenuCommandListWidget`: CommandWidgetClass (soft),
  bIsUsePauseMenu, RefType (ELiveMenuCommandListRefType), CommandDatas, ListVertical/Horizontal/WrapParentBox) holds
  six pre-placed rows, `WBP_Menu_Text_Focus_000_01` ... `_06` (class WBP_Menu_Text_Focus_001). Its CDO sets only
  AnimType = 1 (no CommandWidgetClass), so it doesn't create rows: six commands per page at most. **[I]** The rows
  beyond six are dropped. Survival's 2 + 4 rows fill it exactly.
- A row `WBP_Menu_Text_Focus_001` (`LiveUIFocusTextWidget` < `LiveUICommandWidget`): 828x88; `Focus` canvas (opacity 0
  until focused) with the `>` TextBlock `sel` at 40,12 (HUD 36); `HorizontalBox_59` at 88,0 (740x88) -> `TextWidget`
  (WBP_Menu_Text_000, Main 37, top pad 12). It has animations In/Loop/Invalid/Off (+ Type_B_*).
- The native row class supports an icon and a counter (reflected `CategoryIcon`, `IconWidget`, `NumCounterWidget`,
  `NumberTextWidget`, and Default/Focus/GrayoutTextColorName). Only the main hangar's row `WBP_Menu_Text_Focus_000`
  carries those widgets: CategoryIcon 32x32 at 16,26 (collapsed), IconWidget = `WBP_Hangar_IconParts_000` (IconImage
  48x48), NumCounterWidget = `WBP_Menu_Detail_Text_005` ("x" Main 26 + number Main 37) right-aligned at x 804.
  The landing menu's Focus_001 rows have none of them, so icons and prices there must be added by Survival.
- Row data `LiveMenuCommandsDataTable`: CommandID, TextRefArgs (None/MissionID/PlaneID/PlaneStringID/WeaponID),
  TitleTextID, HelpTitleTextID, HelpTextID, BackGroundID, MenuID, LevelId, OptionID, DialogID, StringArgs, bIsInvalid,
  InvalidAppearance (None/Grayout/Invisible), PlatformSettingsList[3], bIsEnableEmptyIcon. The help line at the bottom
  shows the focused row's HelpTextID: that's the item description, resolved through Survival's text hook (`SV_*` keys).

### 1.4 "Tabs" are not player tabs **[V]**
`LiveMenuPageSettingsData` = {TitleTextID, TabSettings: [{TabTitleTextID, CommandSettings (soft DataTable),
BackGroundID, DefaultHelpTextID}], BackGroundID}. In all 38 stock DA_LiveMenu*Settings, the TabSettings with more than
one entry are command sets the code picks from: Sound "ON" / "OFF" / "NotPS5", Graphic and DynamicRange "HDR" / "SDR",
Campaign top _000 / _001. None of them is a tab the player switches with L1/R1.
- `DA_LiveMenuIngameHangarSettings`: title CampaignReturnTitle_Name_Resupply, one tab "TAKE OFF" -> DT_LiveMenuIngameHangarCommands.
- `DA_LiveMenuIngameHangarSettings1` / `2`: titles HangarSelectweaponTitle_Name_SelectSPweapon1 / 2, one tab "TAKE OFF",
  CommandSettings None (the weapon list comes from native code).
- Adding a TabSettings entry, at build time or run time, therefore adds no visible tab. **[I]** The page code only
  reads entry 0.

### 1.5 Input **[V]**
Native code handles everything per page: decide is vtable slot 0xEE, cancel slot 0xEF, the selected command is vfunc
0x7A0 (slot 0xF4, `SelectedArgs` in survival_rt.c), and cursor moves play IngameHangar_MoveCursor. Survival's
OnHangarDecide is an inline hook on the function, not on one instance. Every page of class LiveMenuIngameHangarWidget,
a Blueprint subclass of it included, goes through it, so `SV_Buy_*` rows work on any such page. **[I]** That holds
because BP classes use their native parent's vtable.

## 2. Options, ranked

### Rank 1: a real STORE page, reached through the in-game menu table (a', recommended)
The landing menu gets one row, STORE (StringArgs "20"). It opens Survival's own page, which looks and behaves like the
stock one: window, header, 6-row list, help line, cursor sounds, native decide/cancel. Survival decorates its rows
with icons and prices, and replaces the gauge panel with an item panel.
1. Build time (tools/build_survival.py):
   - `WBP_SV_Store`: a copy of WBP_Menu_IngameHangar_Confirmation_000 under `/Game/Mods/SurvivalMode/UI/`.
     Rename the package only and keep the object names (`..._Confirmation_000_C`); renaming the class touches the
     ubergraph's field paths, so leave that for later. `retarget_import` its DA import onto `DA_SV_StoreSettings`.
     Rename the name-map entry `CampaignReturnTitle_Name_Resupply` to `SV_Store_Title`. Add the package to the
     container header (hard rule 7). rename_package() expects an export named like the package, which a WBP doesn't
     have, so it needs a variant that only renames the package path.
   - `DA_SV_StoreSettings`: a copy of DA_LiveMenuIngameHangarSettings with TitleTextID SV_Store_Title, tab "STORE",
     CommandSettings -> `/Game/Mods/SurvivalMode/Data/DT_SV_StoreCommands`.
   - `DT_SV_StoreCommands`: up to 6 LiveMenuCommandsDataTable rows, built like build_shop_rows (TitleTextID
     SV_Shop_<item>, HelpTextID SV_Shop_<item>_Help, StringArgs SV_Buy_<item>, or a page number).
   - `DT_SV_MenuClassRows`: a one-row copy of DT_IngameMenuSettingData: MenuID `SV_Store`,
     MenuWidgetReference -> `/Game/Mods/SurvivalMode/UI/WBP_SV_Store.WBP_Menu_IngameHangar_Confirmation_000_C`.
     For a second page (section 3) add `WBP_SV_Store2`, DA and DT, and a second row (index 21).
   - DT_SV_ShopRows shrinks to one row, STORE (StringArgs "20").
2. Lua:
   - AddRow DT_SV_MenuClassRows' row into DT_IngameMenuSettingData before Survival's mission level loads, since the
     manager is a world subsystem and builds its list when the world starts. Load, pin and watch it (hard rule 10),
     take it out again when Survival ends, and check with GetRowNames that it sits at index 20.
   - Once Survival's level is up, check `FindFirstOf("LiveMenuManager").MenuWidgetClassList`: the count must be > 20
     and [20].MenuIDName must be "SV_Store". Only then add the STORE row to the landing table.
   - Decorate the page while it's open (section 3).
3. Native (small):
   - Guard: OnHangarDecide passes a numeric row of 20 or more only after Lua has confirmed the menu exists (e.g.
     `SV_ShopRequest(2, n)`); otherwise it swallows the press and logs it. A bad index could otherwise crash or open
     RetryMenu.
   - Optional: `SV_HangarSelected()` returns the focused row's StringArgs (reuses SelectedArgs) for the item panel.
   - Optional: a cancel remap. On Survival's pages, cancel would open the special-weapon page (transition 6/7). A
     patch of vtable 0x14c80d868 slot 0xEF, filtered on the page's class path, can send transition 8 (= menu 5, back
     to the landing page) instead. Without it, add a BACK row (StringArgs "5").
   - Optional: grey out rows the player can't afford with the game's own `UpdateCommandValidity(ctx, TArray<FString>
     invalidArgs, bool grayout)` (0x147b575d0, already found as g_fPauseValidity). The landing list is the same
     LiveMenuPauseCommandListWidget class as the pause list. **[I]**
- Risks: whether the manager accepts index 20 (T1-T3); whether the WBP copy loads (zen class package; hard rule 9 is
  about Lua's LoadAsset, but the manager's soft load is the normal loader); what a page change does to the hangar
  camera and the FinishInGameHangar trigger (the Weapon1 page is the stock precedent, so probably nothing); cancel
  behaviour.

### Rank 2: better rows on the existing list (d: Lua only, the quick win and the base for rank 1)
On the live `WBP_Menu_IngameHangar_Confirmation_000_C`, find `WBP_Menu_IngameHangar_Common_000` ->
`WBP_Menu_Pause_List_000` -> `WBP_Menu_Text_Focus_000_0N` (childWidget() as hangarAmmoTick does). Survival's rows are
03-06. For each one:
- StaticConstructObject an Image (outer = the row's WidgetTree) into the row's `CanvasPanel_79` at 92,20, 48x48, with
  `SetBrushFromTexture(tex, false)`.
- Move `HorizontalBox_59`'s slot from x 88 to x 152.
- Add a price TextBlock right-aligned at the row's right edge (anchor (1,0), alignment (1,0), x -24, y 20). Copy the
  Font of the row's TextWidget TextBlock, as HUD_LAYOUT.md did for the HUD font.
- Collapse WeaponDetail_001 and put Survival's item panel in its place (section 3). Keep WeaponDetail_002, the ammo
  panel, which already shows the caps.
- Find the focused row from each row's `Focus` canvas opacity (0 when not focused), or from SV_HangarSelected.
- Re-apply whenever a new page instance appears, the way hangarAmmoTick re-finds its panels.
- Risks: the row animations (In/Loop/Off) may change opacity or transforms over Survival's children (T4). Only 4 rows.

### Rank 3: Survival's own panel drawn over the landing menu from Lua (b)
A full-screen Survival layer (HUD_LAYOUT.md base) shown while ELiveHUDMode == IngameHangar, built like the NUI shop
(tile grid: `[CATEGORY]`, name, 48x48 currency icon + price, red copy when unaffordable, 624x352 item image). Full
freedom of layout, but:
- the stock page still has focus. Every decide has to be swallowed natively while the panel is open, and the hidden
  stock cursor still moves and plays its sounds;
- navigation needs key polling (`IsInputKeyDown` / `GetActionMappingByName` with FKey from UE4SS 3.0.1 Lua, untested)
  in the LoopAsync tick (no per-frame timers), which lags up to one tick;
- it has to stay above the hangar's own render/glow layers.
It only makes sense if rank 1 fails at T1-T3.

### Not viable
- (a) An extra TabSettings entry in DA_LiveMenuIngameHangarSettings: entries are code-picked variants, not visible
  tabs (1.4). A build-time copy of the stock DA would also break the rule against overriding shared stock assets.
- (c) Reusing the weapon-select page: `LiveMenuIngameHangarWeaponSetting1Widget` fills its list natively from the
  aircraft's special weapons and changes the loadout. There's no data path for Survival entries.

## 3. Recommended design: the Survival STORE

### Flow
Land -> stock landing page `RESUPPLY` with TAKE OFF / SP WEAPON / **STORE** (Survival's one row, StringArgs "20").
- **SUPPLIES** (menu 20): MISSILES, SPECIAL WEAPON, FLARES, REPAIR AIRCRAFT, `AIRFIELD >` ("21"), TAKE OFF ("-1").
- **AIRFIELD** (menu 21): REPAIR AIRFIELD, AA GUN, SAM SITE, `< SUPPLIES` ("20"), TAKE OFF ("-1").
- Cancel: back to the landing page (with the native remap), or BACK rows.

The six-row limit makes two pages the clean way to get one row per item, AA gun and SAM site separate. Switching
pages with numeric StringArgs is the game's own mechanism. This means splitting CFG.shop.items.Airfield (today one row
doing three jobs) into RepairAircraft / RepairAirfield / AAGun / SAM; SHOP_ITEMS in build_survival.py must match.

### Layout (window coordinates; the window sits at 435,410 on the 3840x2160 canvas, 2944x1244)
| Part | Where | Source / style |
| --- | --- | --- |
| Title "AIRFIELD STORE: SUPPLIES" | 80,74 (native header) | `SV_Store_Title` through the text hook |
| Credits "CREDITS [Z] 12,450" | right-aligned to x 2864, y 74 | Lua TextBlock (Main 37) + 40x40 currency icon |
| List | 58,145, rows 80 apart (y 145...545) | native, 6 rows |
| Row icon | row-local 92,20, 48x48 | Lua Image |
| Row label | row-local x 152 (moved) | native TitleTextID `SV_Shop_<item>` ("MISSILES +12") |
| Row price | right edge of the 828-wide row, x -24 | Lua TextBlock "300", red (shop tile's red copy) when unaffordable, "FULL" when maxed |
| Item panel | 1218,80, 1464x744 (WeaponDetail_001 collapsed) | Lua: `[ SUPPLY ]` label (Main 24) at +0,0; name (Main 41) at +0,50; icon in a ScaleBox 640x320 at +0,130; stat rows in the BuyDetails style at +0,500: IN STOCK 24 / 48, AFTER PURCHASE 36, PRICE 300, BALANCE AFTER 12,150 (labels left, values right at +940, HUD 33), dashed line between |
| Ammo panel | 2090,668 (native WeaponDetail_002) | kept; hangarAmmoTick shows the caps |
| Description | 119,1001 (native help line) | the row's HelpTextID `SV_Shop_<item>_Help` |
Text colour (0.91,0.93,0.93,1) at opacity 0.8 like the menu texts (UI_SHOP_SAVE.md).

### Icons (stock textures; load with LoadAsset / StaticFindObject, `Image:SetBrushFromTexture`) **[I: visual check T8]**
| Item | Texture | Note |
| --- | --- | --- |
| Missiles | `/Game/UI/Texture/HUD/ProgressBar/Weapons/T_HUD_w_msl_a0` | the HUD weapon-gauge silhouette (`_inside` = fill layer) |
| Special weapon | `.../Weapons/T_HUD_w_<code>_a0` from the player's special weapon | codes present: 4aam 4agm 8agm ecm ecmp eml gpb iews laam lacm lagm lasm mgp mpbm qaa qaam rkt saam sasm sffs sod tls uav ugb ugbl xsdb; some only `_r0` / `_x0` (try a0, r0, x0, then msl_a0). The ammo panel's slot name text ("QAAM", ...) gives the code |
| Flares | `.../Weapons/T_HUD_w_flr` | |
| Repair aircraft | `/Game/UI/Texture/Icon/Aircraft/T_HUD_acIcon_<PPnnn_model>` (e.g. `T_HUD_acIcon_PP004_f15c`) | the player's own plane silhouette from the HUD damage display (136 files, `_inside` = fill). Model from the pawn's BP_PPnnn_<model> name. No wrench/repair icon exists in the game |
| Repair airfield | `/Game/UI/Texture/HUD/Radar/T_Icon_Radar_Base_000` (alt. `/Game/UI/Texture/Icon/Tutorial/T_UI_TutorialIcon_AllyBase_000`) | |
| AA gun | `/Game/UI/Texture/Icon/Tutorial/T_UI_TutorialIcon_TGT_Gnd_000` (alt. `/Game/UI/Texture/HUD/Radar/T_Icon_Radar_GndEscort_000`) | no AA-specific icon found |
| SAM site | the same ground icon + a small `T_HUD_w_saam_a0` overlay, or the ground icon tagged "SAM" | no SAM-specific icon found |
| Currency | `/Game/NUI/Common/Texture/IconMenu/T_Menu_Common_IconMenu_Token_Zoll_000_ss` | the game's own "Zoll" token, which suits zollars (Survival's currency) |
| STORE row / title | `/Game/NUI/Common/Texture/IconMenu/T_Menu_Common_IconMenu_Shop_000` | |
Not used: the parts icons `/Game/UI/Texture/Icon/Parts/T_UI_Icon_Parts_PartsCAT_*` and the NUI shop's item art (online store).

### Purchases
Unchanged path: the row's StringArgs `SV_Buy_<item>` -> OnHangarDecide (hooked function, so it covers Survival's page
class) -> queue -> SV_ShopRequest -> shopBuy. The page stays put (the hook returns 1). After a purchase, Lua updates
its own price, stock and credits widgets right away; the native label and help texts only change when the page re-reads
them. Unaffordable items are greyed out (UpdateCommandValidity) or shown in red.

### Lua notes
Keep the store helpers in a `do ... end` block (hard rule 23, the 200-local limit). Create only concrete widgets (rule
18). Run the decorator from the existing LoopAsync tick, with no per-frame timers.

## 4. In-game tests for the unverified parts
- **T1 (number = menu)**: temporarily give a Survival landing row StringArgs "5" (not SV_Buy, so it reaches the stock
  decide). Expected: the landing page closes and opens again. Then try "4": the Weapon2 page (on a plane with two
  special-weapon slots).
- **T2 (manager list)**: from Lua, log `FindFirstOf("LiveMenuManager")`: MenuWidgetClassList count and each
  MenuIDName / MenuClass, plus UniqueMenuIDs and MenuStack. Expected: 20 entries in the table's order (5 = IngameHagarMenu).
- **T3 (index 20)**: before Survival's level loads, AddRow a row into DT_IngameMenuSettingData pointing at the stock
  `WBP_Menu_IngameHangar_Confirmation_000` (no build needed), then press a row "20". Expected: count 21 in T2's log, and
  the landing page reopens. Also check whether UE4SS can append to MenuWidgetClassList directly, a fallback if the
  timing fails.
- **T4 (decorations)**: add an Image (T_HUD_w_msl_a0) and a price TextBlock to row 03 of the live landing page.
  Check they show, survive cursor moves and the focus animation, and come back on a second landing.
- **T5 (focus)**: log each row's `Focus` canvas RenderOpacity while moving the cursor, or test SV_HangarSelected.
- **T6 (copied page)**: build WBP_SV_Store + DA + DT + menu row, press STORE. Expected: Survival's title, its own 6
  rows, SV_Buy presses caught, hangar camera unchanged, FinishInGameHangar only on take-off.
- **T7 (back / cancel)**: on the STORE page, press cancel (stock: special-weapon page?) and a "5" row. Then on the
  weapon page, check where cancel goes.
- **T8 (textures)**: look at the icon candidates (FModel, or SetBrushFromTexture in game) for shape and aspect, and
  pick the special-weapon suffix rule.
- **T9 (more rows)**: optional: whether a 7th row added at run time to the list's VerticalBox is ever used (expected no).
