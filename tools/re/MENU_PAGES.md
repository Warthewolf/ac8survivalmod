# Survival's own main-menu pages (2026-10-27; runtime 0.27.0, Lua 0.71.0; not yet run in game)

User, 2026-10-27: "Main Menu, The Player picks SURVIVAL MODE, then it goes into another menu where it lists SURVIVAL
MODE SP OFFLINE / SP ONLINE / COOP HOST / COOP JOIN. Each of these, except for COOP JOIN, would open up another menu
... presets that can be changed for the mission, such as Round Starting Money, Enemy Percentage, etc, feel free to
add some Quality of Life features".

Labels as in AIRFIELD_SHOP_UI.md: **[V]** verified (in game or in the files), **[I]** inferred, **[T]** to test.

## The menu

```
main menu: SURVIVAL MODE >                                   (DT_SV_MenuRows SurvivalMenu, MenuID SV_PgModes)
  SURVIVAL MODE (SV_PgModes)
    SURVIVAL MODE SP OFFLINE >     SV_Mode_Offline -> SV_PgOffline
    SURVIVAL MODE SP ONLINE  >     SV_Mode_Online  -> SV_PgOnline     (taken off in the Offline edition)
    SURVIVAL MODE COOP HOST  >     SV_Mode_Host    -> SV_PgHost       (taken off without co-op)
    SURVIVAL MODE COOP JOIN        SV_Mode_Join    -> CampaignFreeMissionDifficulty (a start)
    QUICK START: <last mode>       SV_Quick        -> CampaignFreeMissionDifficulty (a start, SV_MenuQuick's mode)
  SP OFFLINE / SP ONLINE (SV_PgOffline / SV_PgOnline)
    START RUN [: RANKED / UNRANKED] SV_Go_<mode>   -> CampaignFreeMissionDifficulty (a start)
    PRESET, STARTING ZOLLARS, ENEMY AIRCRAFT       SV_Set_<what> (stepped in place)
    MORE RULES >                   SV_Page_Rules   -> SV_PgRules
  COOP HOST (SV_PgHost): START RUN, LOBBY, CO-OP ROOM, CO-OP ENEMIES, PRESET, STARTING ZOLLARS, ENEMY AIRCRAFT, MORE RULES >
  MORE RULES (SV_PgRules; the mode picked last): START AT ROUND, BREAK BETWEEN ROUNDS, SPECIAL ROUNDS, AIRFIELD HEALTH,
    ZOLLAR INCOME, ENEMY SKILL, RESET TO DEFAULTS
```
After a start, the game's own free-mission difficulty page comes up and starts Survival as SURVIVAL MODE always has
(main.dll OnDiffNext). QoL: every mode keeps its own setup (survival.ini [setup.offline] / [setup.online] /
[setup.host]); QUICK START plays the last mode started; the START row's help line sums the setup up; SP ONLINE says
RANKED / UNRANKED live; the help lines give numbers (enemies in rounds 1 and 10, a fighter kill's pay, the airfield's
HP); the host's LOBBY row lists who has joined, while the host still sets up (co-op opens when COOP HOST is picked);
RESET TO DEFAULTS.

## How the pages are made

- The main menu is the "Menu" framework page LiveMenuMainTopWidget **[V]** (its rows come from
  DT_LiveMenuMainTopCommands through DA_LiveMenuMainTopPageSettings, BUILD_PLAN Milestone 1; its decide is vtable A
  slot 0xEE, which main.dll's OnMainDecide hooks: "main menu: Survival Mode chosen" in every test since 2026-10-20).
- A row's MenuID (a string) names the page it opens: SURVIVAL MODE's "CampaignFreeMissionDifficulty" opens the
  free-mission difficulty page **[V]**. The out-of-game LiveMenuManager (a world subsystem) keeps its pages in
  `MenuWidgetClassList` ({MenuIDName: FString, MenuClass}) built from its settings' MenuClassTable (row struct
  LiveMenuClassTable {MenuID: FName, MenuWidgetReference: soft class}) **[V]** (reflection; the in-game twin is
  DT_IngameMenuSettingData, where the STORE's pages went and opened: hard rule 29). That a page is looked up there by
  its MenuID **[I]** (GetNextMenu answers names, e.g. "CampaignFreeMission", which then opens: test 3 of 2026-10-20).
- Survival's pages are copies of the main-menu page itself (tools/build_survival.py MENU_PAGES), so they're the same
  native class: every press on them reaches OnMainDecide **[I]** (Blueprint classes use their native parent's vtable,
  as the STORE pages showed for the landing page **[V]**). Each copy's settings import points at its own
  DA_SV_Pg<page>Settings (title SV_Pg_<page>_Title, every tab's CommandSettings DT_SV_Pg<page>Commands), whose rows are
  copies of the main menu's Campaign row.
- tools/menu_stock.py finds the stock packages by what they hold, from build/scan/all_chunks.txt: the page table(s)
  that list CampaignFreeMissionDifficulty, and of their pages the one that imports DA_LiveMenuMainTopPageSettings.
  Nothing found: build/menu/stock.json says why, the build makes no pages, the main menu keeps the flat rows.
  tools/checks/menu_pages_test.py runs both on synthetic packages (build_all.sh runs it).
- DT_SV_MainMenuClassRows: rows SVPg<page> {MenuID SV_Pg<page>, MenuWidgetReference
  /Game/Mods/SurvivalMode/UI/WBP_SV_Pg<page>.<the stock page's class>} (a copy of DT_IngameMenuSettingData's row).

## At run time (Scripts/sv_menu.lua)

1. At start: Survival's class rows into every page table the build found (Scripts/sv_menu_stock.lua, staged by
   build_all.sh), loaded and pinned, before the main menu's manager builds its list from them **[T]** (whether Lua
   starts before the title world does).
2. When the main menu's manager appears (NotifyOnNewObject LiveMenuManager; a FindAllOf until the first one), its own
   table (`MenuSettingsData.MenuClassTable`) gets them too (pinned: the next main menu has them from the start), and
   its `MenuWidgetClassList` is checked for SV_PgModes ... SV_PgRules. Missing (the list was built first) and
   CFG.menu.late_register: each page is put into the live list, `list[n + 1] = { MenuIDName, MenuClass }` **[T]**
   (UE4SS 3.0.1 growing a struct TArray from a table; the log line "adding Survival's pages to the game's live page
   list (late)" comes before it, should it crash).
3. Decided (`menu pages: ... Survival's are in` or `are missing (...)`): the main menu gets SURVIVAL MODE (the pages,
   SV_MenuPages(1)) or the flat rows (SURVIVAL MODE straight to the difficulty, CO-OP HOST / JOIN). main.dll refuses
   the pages' row while SV_MenuPages isn't 1. A later main menu can switch over (the rows are swapped then).
4. The pages' command tables are loaded and pinned; the rows this game doesn't show come off (SVModesOnline in the
   Offline edition, SVModesHost / SVModesJoin without co-op).
5. Texts: every row's label and help are Lua's (SV_SetText), set at load and on every change; a changed label's live
   TextBlock is relabelled in place (the STORE's way: the game reads a row's label when its page opens). main.dll has
   built-in titles for the pages and the modes rows, used until Lua's are set (Lua's win since 0.27.0).
6. A setting row's press: main.dll takes it (SV_MenuSetting) as the coop branch's settings rows, Lua steps the value of
   the mode picked last (SV_MenuChoice: 2 SP OFFLINE, 3 COOP HOST, 4 COOP JOIN, 5 SP ONLINE, 6 the pages opened),
   saves it with iniSet and relabels.

## The rules a run plays with (SETUP.*)

The mode's setup (a joiner: the host's, synced with the host's settings: CFG.setup isn't one of co-op's personal
sections), read where it applies: SETUP.startRound (sv_main D), SETUP.zollars (RUN.credits), SETUP.airfieldHP (AF.max;
the HUD bar, the store's repairs and the airfield's health cap read AF.max), the airfield's return health
(repair_hp x SETUP.airfieldX), SETUP.enemyX (sv_rounds budget and waveCap), SETUP.breakS (the break), SETUP.specialsX
(sv_spawn specialFor: 0 none, the chances times it), SETUP.skillAdd (sv_ai enemyTier), SETUP.payX (sv_ai addCredits:
every zollar earned), SETUP.preset (presetName: the ammo caps, rank_add, waves' max_up_by_preset). SP ONLINE runs go
to the leaderboard only with the shipped setup (LB.send; co-op runs: CFG.coop.leaderboard as before).

## Test checklist (first test)

Log lines (AC8SurvivalMode_lua.log unless said):
- `menu pages: <table>: Survival's pages are in` (the build found the page table; else `could not load`)
- `menu pages: the game's main-menu page table is <path> (...)`, `the main menu's page list has N pages; Survival's are
  in: SURVIVAL MODE opens them` - or `are missing (...)` and maybe the late registration's lines
- `menu pages: page <...>, DeepLevel <n>` for each live menu page (what the copies inherit)
- AC8SurvivalMode.log: `main menu: Survival's pages are in the game's page list`, `main menu: Survival's page row
  'SV_Mode_Offline': SP Offline`, `... 'SV_Go_Offline': SP Offline, opening the difficulty select to start`,
  `main menu: setting SV_Set_Zollars picked`
- `menu: setup.offline.zollars 0 -> 1000 (saved to survival.ini)`, `menu: N text(s) changed (Zollars), M on screen`
- at level load: `menu: the run plays SP OFFLINE's setup (offline): ...; leaderboard: SP OFFLINE`

To look at:
- **[T1]** SURVIVAL MODE opens a page titled SURVIVAL MODE with the four modes and QUICK START, in the main menu's look.
- **[T2]** SP OFFLINE opens its setup page; pressing STARTING ZOLLARS steps the value on screen without leaving the page.
- **[T3]** Cancel (B / Esc) on a page goes back one page (not to the title screen). If it doesn't: the DeepLevel lines.
- **[T4]** START RUN -> the difficulty page -> the hangar -> Comona; the run starts with the zollars, the round etc. set.
- **[T5]** MORE RULES shows the mode you came from (its title says which).
- **[T6]** COOP HOST: the LOBBY row counts a friend who picks COOP JOIN; the joiner plays the host's rules.
- **[T7]** The flat fallback: with `[menu] pages = false` the old rows come back and work.

If T1 fails (nothing opens, or a black page): check the decided line. A page listed but not opening points at the
lookup being by index, not name (then the pages need the in-game way: AIRFIELD_SHOP_UI.md 1.1). A crash on opening a
page: the copy (its settings asset may be of a subclass, or the page wants a context the main menu has); send the
crash dump and the log.
