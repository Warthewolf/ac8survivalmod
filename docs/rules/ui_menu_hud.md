# Menus, HUD, music and radio

The main menu and its pages, the HUD, info maps, radio lines, the music list.

Moved verbatim from AGENTS.md (2026-11-14). Rule numbers are unchanged: other notes cite them as "hard rule N".

12. Confirming the free-mission difficulty runs transition 7, which asks the page's GetNextMenu (vtable 0x111); that hook,
    with the page it's called on, is where Survival starts. Don't rely on the page's decide or on a FindAllOf lookup.

13. The hangar level travelled to must be 10 + the mission row's TravelHangarMap, or the hangar loads unlit.

18. Survival's HUD is built at run time in Lua (docs/re/HUD_LAYOUT.md). UUserWidget is Abstract: create the base with
    WidgetBlueprintLibrary.Create on a stock widget blueprint, then StaticConstructObject concrete widgets (TextBlock,
    Image, CanvasPanel, ScaleBox, SizeBox) in its WidgetTree. The game's own HUD is not in the viewport (drawn to a
    render texture), and GetCachedGeometry reads back 0x0 from Lua, so place things from the static layout.
    Confirmed by test 13 (2026-10-22).

24. The hangar (and its wingman panel) look a mission up in the GameInstance's InformationManager_ maps
    (MissionDataMap_ by MissionID, LevelDataMap_ by level id), built from DT_LiveMissionTable at start, not in the table.
    A row added after they were built is missing there: black hangar, then a crash at sortie (AceCombat8.exe+0x79a4153,
    an empty wingman list). main.lua's infoMapsTick adds Survival's row to both. Confirmed 2026-10-22 ("info maps: ...
    was missing 9101 ... added", hangar lit).

29. Never read a struct field that holds a soft class / object reference from UE4SS Lua (e.g. a menu row's
    MenuWidgetReference): UE4SS copies it through its FSoftObjectPath::operator= and crashed the game at the main menu
    (access violation in FString::operator=, test of 2026-10-23). FindRow + AddRow of such a row without touching the
    field is fine (STORE pages, 20 / 21 in the game's menu list in the same test).

33. Radio lines come from the level's RadioSettings (a hard import in PL_SurvivalMode): Survival's level points it at
    its own copy (DT_SV_Radio; build_radio), and a Mission 25 line played there with its voice (user, 2026-10-23).
    Speakers don't: the game instance holds its own DT_SpeakerTable (BP_LiveGameInstance imports it) and a copy for the
    level changed nothing. A speaker's enemy look is its row's ColorType / ProcessID (Enemy_Fighter_Mob): main.lua
    switches the row at run time while a run is on (CFG.allies.ally_speakers; not yet confirmed). Line IDs ending in
    digits without a leading zero are stored split (v0003_1682 = ('v0003', 1683)), as hard rule 17.

52. The main menu opens a row's page (its MenuID) through ELiveMenuMainIDs, the game's FIXED enum of its pages
    (GameTitle ... CampaignTraining, MAX): a page of a new name never opens, whatever the page list holds (25 presses,
    nothing). New pages borrow a stock id instead: main.dll points that id's MenuWidgetClassList entry (manager+0x118,
    { FString, UClass* } 0x18 each) at the page's class just before the press goes on (SV_MenuClass / SV_MenuSlot).
    The game ignores a request for the page shown, and goes BACK to a page already open under it rather than open it
    again: consecutive pages need different ids (Survival: CampaignTraining, InitialSetting_DualSence,
    InitialSetting_Accessibility), and a BACK row naming the page under it is a working way back. Copies of the main
    menu's top page have no cancel. Confirmed by the tests of 2026-10-29 (runtimes 0.27.0-0.28.3).

57. AC8's music player list shows 120 tracks at most (its scroll list's row limit). With more, the cursor runs on over rows
    that aren't drawn, and a press there reads past the list and crashes the game. The user's run of 0.74.29 (235 tracks)
    saw "Megalith" (row 120) last and crashed at row 231 (UECC AceCombat8.exe+0x7a8dc81), 2026-11-08. The list is also
    built only as a level starts (a world subsystem's Initialize), and each build writes what it lists into the save's
    OwnedMusicList. Survival rebuilds it (SV_MusicBuild) and keeps every list within player_max = 120 (sv_music.lua). The
    runtime cuts those save grants back off (SV_MusicSave). docs/re/MUSIC_BANKS.md.
    Only 2D events can be heard through it: the lobby jukebox's AKE_Bgm_JukeBox_* are 3D (MaxAttenuation 600, 6 m from the
    lobby's prop) and were silent in Alyssa's run of 0.74.30. Online Mode's versions (AKE_Bgm_Online_ACE7_* ...) played in
    0.74.31; build_music_rows refuses a 3D event. A looping event is given 60 s, not -1 (0.74.31: "Hush just abruptly ends").

## Survival's menu pages (Lua 0.71.5, runtime 0.28.3; working in game 2026-10-29)
SURVIVAL MODE opens Survival's own pages (user, 2026-10-27): SP OFFLINE / SP ONLINE / COOP HOST / COOP JOIN / QUICK START,
each but JOIN with a setup page (PRESET, STARTING ZOLLARS, ENEMY AIRCRAFT, ...) and MORE RULES, and a BACK row on every
page. The pages are copies of the game's main-menu page (tools/build_survival.py MENU_PAGES; tools/menu_stock.py finds the
stock), so their presses reach OnMainDecide; they open through borrowed stock page ids (hard rule 52; the user gave
CAMPAIGN TRAINING over completely, 2026-10-29, and its row stays hidden; the two first-start pages get their own class
back when any other main-menu entry is picked). Scripts/sv_menu.lua keeps one run setup per mode (CFG.setup,
survival.ini [setup.*]) that the rounds, store and leaderboard read through SETUP.*. Without the pages ([menu] pages =
false) the main menu has the flat rows. Confirmed 2026-10-29: the pages open, settings step in place and save, BACK
works all the way out. Not yet: B / Esc on the pages (no cancel), a whole run started from a setup page with its rules.
docs/re/MENU_PAGES.md has the design and log lines. Lua tests: tools/checks/menu_test.sh (and coop_settings_test.sh),
the build's: tools/checks/menu_pages_test.py (build_all.sh runs it).
