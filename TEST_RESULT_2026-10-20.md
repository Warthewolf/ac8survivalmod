# Test 1 result (2026-10-20 20:10), read from the game's logs

Result: no SURVIVAL MODE menu entry; Ctrl+F8 crashed the game.

## Root cause: SurvivalMode_P did not mount
ue4ss\Mods\IoStoreLoaderMod\AC8IoStoreLoader.log:
    mounting [SurvivalMode] ... SurvivalMode_P.utoc
      result code=6 message=Failed reading 576 bytes at offset 87823
    done: 5 of 6 containers mounted

- SurvivalMode_P.ucas is 88,395 bytes. 87,823 + 576 = 88,399, so the .utoc points 4 bytes past the end of the .ucas.
  The .utoc's last compression block size/offset doesn't match the .ucas written (padding/alignment of the last block?).
- Also: every other mod in the folder has a 347-byte `<name>_P.pak` next to its .utoc/.ucas. SurvivalMode has none.
  Check whether build/install should ship one (compare with Stonehenge's release).

## Knock-on effects (all caused by the failed mount)
- UE4SS.log: [AC8SurvivalMode] rows: could not load /Game/Mods/SurvivalMode/Data/DT_SV_MissionRows and DT_SV_MenuRows
  -> no menu row was added, so no entry on the menu.
- Ctrl+F8 then opened /Game/Mods/SurvivalMode/Maps/PL_SurvivalMode, which doesn't exist in the game -> crash.

## The native runtime looked fine
AC8SurvivalMode.log: runtime 0.1.0 found all game functions, hooked text lookup and menu transition,
installed menu hooks (mission 9101, hangar menu D).

## Fixes to make
1. Fix the .utoc/.ucas size mismatch (and add the .pak stub if needed). Verify by re-reading the built container
   with the same reader the loader uses, before installing.
2. Lua: before OpenLevel, check the map package exists. If it doesn't, log it and show a message instead of crashing.
   Same guard for the menu: if rows can't load, log once and leave the menu untouched.
3. Note: Stonehenge Returns is not currently installed in IoStoreLoaderMod, so the "both buttons" test needs it reinstalled.

---
# Test 2 result (2026-10-20 20:24): mount FIXED, menu entry still missing

- AC8IoStoreLoader.log: [SurvivalMode] result code=0 OK, 11 packages, 6 of 6 containers mounted. Fix 1 worked.
- UE4SS.log, Lua 0.2.2:
    20:24:00.85 rows: added 'SurvivalMode' to DT_LiveMissionTable
    20:24:39.24 rows: added 'SurvivalMode' to DT_LiveMenuMainTopCommands (QuitGame kept last)
- Native runtime: menu hooks installed 20:23:54 (mission 9101, hangar menu D).
- Screenshot at the main menu: CAMPAIGN, CAMPAIGN TRAINING, ACE COMBAT ONLINE, ACE COMBAT STORE, SYSTEM, QUIT GAME. No SURVIVAL MODE.

## Likely cause: the menu row is added too late
The menu row went in about 39 s after load, which is probably after WBP_Menu_Main_000 had already built its button
list from DT_LiveMenuMainTopCommands. The widget doesn't re-read the table, so a row added afterwards never shows.
(The mission row was added 39 s earlier than the menu row. Find out why the menu row waits so long.)

## Fix ideas
1. Add the menu row as soon as DT_LiveMenuMainTopCommands is loaded (NotifyOnNewObject on the DataTable or a
   LoadAsset at mod start), before the title screen/main menu is constructed.
2. And/or after adding the row, force the main menu list to rebuild (re-run the widget's list setup, or hook
   LiveNUIMenuMainWidget construct and add the row there).
3. Quick check for the user: go into SYSTEM and back out, or back to the title screen and in again. If the entry
   then appears, the timing is confirmed.

## Test 2b (20:26): user went into SYSTEM and back, then to the title and back. Still no entry.
So it is NOT only timing: the menu rebuilt after the row was added and still didn't show it.
Nothing new was logged by [AC8SurvivalMode] during those menu changes.

Next things to check (in this order):
1. Compare Survival's added row field-by-field with Stonehenge's row in its overridden DT_LiveMenuMainTopCommands
   (source/stonehenge). Look for a command ID/enum, text key, sort order, visibility/unlock condition or
   platform flag that Survival's row is missing. An unknown command type or an empty text key may be filtered out.
2. Check whether the menu reads the DataTable asset at all, or a native copy of it built once at startup.
   The runtime log shows native "menu tables: main menu 14C82CF38". If the list comes from there,
   the row has to go in before that copy is made (very early), or the runtime has to add it to the native list.
3. Add logging: hook the main menu widget's list build and log each row name it reads. That shows directly
   whether 'SurvivalMode' is being read and dropped, or never read.

---
# Test 3 (20:41-20:43): menu entry SHOWS. Routing after difficulty is wrong.

What happened: SURVIVAL MODE -> difficulty select (good) -> Free Mission select with the 31 stock missions (wrong;
should go to the hangar for mission 9101).

AC8SurvivalMode.log (runtime 0.1.0):
    20:41:52 main menu: Survival Mode chosen, opening the difficulty select (context mode 0)
    20:41:54 menu transition 7 while Survival is chosen, but the difficulty page is not known; passed on
    20:41:55 difficulty page: next menu asked        (repeated, never redirected)
UE4SS.log: the page actually opened is WBP_Menu_FreeMissionDifficulty_000 (a WBP_MenuCommon_MainList_000), then
WBP_Menu_CampaignFreeMission_000 (31 entries).

Cause: the runtime doesn't recognise the difficulty page it opened (its "difficulty page" table 14C7F5C20 doesn't match
WBP_Menu_FreeMissionDifficulty_000's object), so transition 7 and "next menu asked" fall through to stock behaviour.
Fix: on transition 7 while Survival is chosen, record that page as the Survival difficulty page (or match it by class
WBP_Menu_FreeMissionDifficulty_000_C / LiveNUI class), and in "difficulty next menu" redirect to the hangar
for mission 9101 instead of passing on. Log the redirect.

Also: the entry sits BELOW QUIT GAME. The table order is Campaign, CampaignTraining, Online, Shop, System, QuitGame,
SurvivalMode, so "QuitGame kept last" didn't take. Insert SurvivalMode before QuitGame (or re-add QuitGame after it).

---
# Test 4 (20:51): runtime 0.2.0, still goes to Free Mission select

AC8SurvivalMode.log:
    20:51:28 main menu: Survival Mode chosen, opening the difficulty select (context mode 0)
    20:51:30 menu transition 7 while Survival is chosen, but no difficulty page was found; passed on
    20:51:31 difficulty page: next menu asked

Reading it:
- The "difficulty next menu" hook (vtable slot 14C7F64A8) DOES fire on this page: "next menu asked" is logged.
- The "difficulty decide" hook (slot 14C7F6390) never logs, and the page lookup at transition 7 fails.
- So finding the page object at transition 7 is the wrong thing to depend on.

Suggested fix: stop requiring the page to be found. The main menu hook already sets "Survival is chosen".
In the "difficulty next menu" hook: if Survival is chosen, apply the chosen difficulty, set mission 9101 and return
the hangar menu (D) instead of calling the stock next (146ECA6E0, which returns Free Mission select). Log
"redirect: hangar for 9101, difficulty N". Clear the Survival flag when the player backs out to the main menu,
so a normal Free Mission run afterwards isn't hijacked.

---
# Test 5 (20:56): runtime 0.3.0, redirect WORKS. Hangar is black and empty.

User: went into the game, black loading screen with text, then a "start mission" prompt, then the hangar screen,
completely black.

AC8SurvivalMode.log:
    20:56:44 difficulty page: next menu asked while Survival is chosen: going to the hangar instead of Free Mission
    20:56:44 start (next menu): difficulty Casual, context mode 0 -> 0, mission -1 -> 9101
    20:56:44 start: going to the hangar (menu D)
UE4SS.log: the hangar widgets were built, but every hangar list is empty, including
    WBP_Menu_Hangar_AircraftSettings_000 ... ScrollCommandList shows 0 entries   (20:56:50 and 20:56:55)
Menu table order is now ... System, SurvivalMode, QuitGame (the QUIT GAME order fix worked).

Reading it: the hangar opens for mission 9101 but has nothing to show. No aircraft list, and no hangar background
level (black). The hangar most likely builds its aircraft/background from mission 9101's row in DT_LiveMissionTable
and related tables (hangar level / situation, allowed aircraft, player-plane unlocks, briefing). The runtime-added
row is copied from Mission022 but changed, or is missing fields the hangar uses.

Next things to check:
1. Dump Survival's DT_LiveMissionTable row next to Mission022's and Stonehenge's (9001) rows, every field.
   Look for a hangar map/level, hangar situation, aircraft restriction/allowed list, campaign/free-mission flags.
2. Check other tables keyed by MissionID that 9101 isn't in (hangar situation, briefing, free-mission list,
   aircraft unlock per mission). Stonehenge's source shows which tables it added 9001 to.
3. The "start mission" prompt came BEFORE the hangar. Check the flow order; the stock Free Mission flow is
   difficulty -> hangar -> sortie. The black loading screen with text may be the briefing or loading for the wrong level.
4. Turn down the per-widget "menu: list ..." logging. It writes hundreds of lines per menu change.

## Test 5 update (user, 20:59): on Sortie the aircraft's taxi lights were visible in the black hangar.
So the aircraft IS spawned in the hangar and the sortie animation runs. The hangar is unlit, not empty.
- Point 1 above changes: the "0 entries" lines were probably widget templates, not the real lists. Don't chase the aircraft list first.
- Most likely missing: the hangar's lighting/situation for mission 9101. The hangar picks a lighting/background setup
  per mission (cf. DataViewer "SelectHangarSituation"). With no situation for 9101 it loads the hangar with no light.
- Fix: give 9101 the same hangar situation/lighting as Mission022 (or any stock mission). Check which table maps
  mission -> hangar situation, and add 9101 there at runtime the same way as the other rows.
