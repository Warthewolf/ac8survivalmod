# How Stonehenge Returns' main.dll starts its mission (reverse-engineered 2026-10-20)

Binary: `AC8Stonehenge\dlls\main.dll` (release in `source/stonehenge/release`), MSVC C++, image base 0x180000000.
Tools: `tools/re/xrefs.py` (strings + code refs), `tools/re/fn.py` (whole function from .pdata, annotated),
`tools/llvm/LLVM/bin/llvm-objdump.exe -d -M intel`. RVAs below are into that DLL.

## Data side (no code)
- DT_LiveMissionTable (row struct `LiveLevelTable`) gets a row `Stonehenge`: MissionID 9001 (0x2329), LevelId 69,
  MapReference -> PL_Stonehenge, SH_* text IDs.
- DT_LiveMenuMainTopCommands (row struct `LiveMenuCommandsDataTable`) gets a row `Stonehenge`:
  CommandID `Main_Top_Stonehenge`, TitleTextID `SH_Menu_Title`, HelpTextID `SH_Menu_Help`,
  **MenuID `CampaignFreeMissionDifficulty`** (the game opens its own free-mission difficulty page),
  **StringArgs `Stonehenge`** (how the DLL recognises its entry).
- Both rows are added by overriding the stock tables. Survival must not do that (last mount wins).

## Hook install (0xe5d0, called from 0x179f0 when UE4SS is ready; text hook 0xede0 just before)
Exact byte signatures, each must occur exactly once in the game exe's executable sections (scanner 0xe000):
| # | rdata | len | use |
|---|---|---|---|
| 1 | 0x23460 | 0x18 | base-class function, slot 0xDF of both vtables (only used to find them) |
| 2 | 0x23478 | 0x20 | main-menu widget "decide" (vtable A slot 0xEE) |
| 3 | 0x23498 | 0x18 | free-mission difficulty page "decide" (vtable B slot 0xEE) |
| 4 | 0x234b0 | 0x10 | difficulty page "next menu" (vtable B slot 0x111) |
| 5 | 0x234c0 | 0x18 | go-to-menu(page, menuId); called with 0x0D = Hangar 02 |
| 6 | 0x234d8 | 0x18 | set difficulty(page, byte difficulty) |
| 7 | 0x234f0 | 0x10 | found but unused here |
| 8 | 0x23500 | 0x11 | menu transition(obj, int id); 17-byte prologue, inline-hooked |
| T | 0x23430 | 0x2a | text lookup(rcx, dl, FString* key, out); 15-byte prologue, inline-hooked |
Vtable finder (0xe120): pointer array in read-only data with [0xEE]==fn and [0xDF]==sig1 (and [0x111]==sig4 for B).
Patches: A[0xEE] -> 0x13f10, B[0xEE] -> 0xd230, B[0x111] -> 0x148c0 (log only); originals kept.
Inline hooks write `FF 25 00000000 <abs64>` + 0x90 padding; trampoline = copied prologue + jmp back.

## Flow
1. Main menu decide (0x13f10): cmd = widget->vfunc[0xF4]() (vtable +0x7A0) = the selected command row;
   StringArgs FString at cmd+0x130. If == "Stonehenge": flag = 1, save ctx[+0xF60] (context mode). Always calls original.
2. Difficulty page decide (0xd230): if flag: difficulty = match the page's selected row StringArgs against
   Casual 1 / Easy 2 / Normal 3 / Hard 4 / Ace 5; set difficulty (sig6); ctx[+0xF60] = saved mode;
   **ctx[+0xF38] = MissionID 9001**; go-to-menu(page, 0x0D) (sig5, Hangar 02); remember page + now+5 s; return 1.
   Otherwise calls original.
3. Transition hook (0x19280, on sig8): if flag and (id == 7, or id == 10 and obj is the difficulty page)
   -> same start as 2 ("transition"); while now < start+5 s, transitions of that page are swallowed (return 0).
- Campaign context: ctx = (obj->vfunc[0x31]())[+0x1D8] -> [+0x8E0]; ctx+0xF38 int mission id, ctx+0xF60 byte mode.
- Text hook (0x136d0): answers keys starting `SH_` from data\text.tsv, otherwise calls the original.

## What Survival copies
Same signatures, its own StringArgs (`SurvivalMode`), its own MissionID, `SV_` text keys.
Coexistence: Survival installs after Stonehenge (from a delayed thread with all other threads suspended) and
chains onto Stonehenge's patches: vtable slots that already point outside the game exe are taken as "original";
an inline hook already present (`FF 25 00000000 abs64`) is chained by swapping abs64.

## Seen in Survival's tests (2026-10-20)
- Confirming a difficulty on WBP_Menu_FreeMissionDifficulty_000 arrives as transition 7 sent by another menu object;
  the page's decide (vtable B slot 0xEE) does not run. Stonehenge's d390 finds the page with UE4SS FindAllOf
  (`void FindAllOf(const wchar_t*, std::vector<UObject*>&)`, class LiveMenuCampaignFreeMissionDifficultyWidget,
  vtable == B, not the class default object) - this path is required, not a fallback.
- The hold-back after the start applies to the object that sent the transition (Stonehenge stores r12 = that object).
- vtable B slot 0x111 (sig4, 0x146ECA6E0 in this build) is `FName* GetNextMenu(page, FName* out)`: it builds the
  FName "CampaignFreeMission" into *out and returns out (FName = 8 bytes, NAME_None = 0). Transition 7 asks it.
- gotoMenu(page, 0x0D): 0x0D is ELiveLevelID Hangar_02 (13), i.e. a level travel, not a menu name.
