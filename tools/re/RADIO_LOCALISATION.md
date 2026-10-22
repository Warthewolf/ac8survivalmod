# Radio and localisation (research, 2026-10-23)

Builds on `MUSIC_RADIO_CAMERA.md` section C (asset list, node args, M22 group table); that isn't repeated here.
Static research only, nothing tested in game. Addresses are for the current AceCombat8.exe; find them by signature.

Marks: **[V]** verified from game data, **[S]** verified statically in the exe's code, **[I]** inferred, **[T]** needs an
in-game test (section 4).

Scratch (in `build/research/loc/`, not in git):
- `pak.py`: reads the legacy `pakchunk*-Windows.pak` (v11, encrypted index, Oodle). The AES key comes from
  ACE8AircraftBuilder's settings.json, as in get_stock.sh. Usage: `pak.py list <pak>` / `pak.py get <pak> <substr> <outdir>`.
- `acloc.py`: decodes AC7/AC8 `.dat` text files (a Python port of `E:\Ace8Loceditor\bundle-1\src\Loc.cs`).
- `GameData/`: the 28 stock `.dat` files. `CP_en.tsv` / `ON_en.tsv` (index, key, English). `CP.json` / `ON.json` (every key in
  all 13 languages).
- `ms022_text.tsv`: Mission 22's 667 radio rows with their English subtitles. `awacs_all.tsv`: all 4154 AWACS rows in every
  radio table, with subtitles. `radio_scan.py`: the cross-table scan behind 1.3.

## 1. The radio pipeline

### 1.1 Which lines a level can play
Groups are registered once, when the level's `ULiveRadioWorldSubsystem` initialises. Init is 0x1478246c0, called from
0x147822b80 **[S]**. It reads:
1. **The level's `ChronicleWorldSettings.RadioSettings`** (world +0x30 -> +0x2A0 = world settings, +0x5A0 = RadioSettings).
   `RadioDataTables[]` is added to the group cache by AddRadioTables 0x147824930 -> 0x14781d1f0 per table. Then come the
   override table, the speaker tables, the process types and the automatic speakers. **[S]**
2. **The GameInstance's common tables** (BP_LiveGameInstance defaults **[V]**). Offline: GI+0x798 `CommonRadioTables` =
   [`DT_Rdo_PByP_CP`], GI+0x7A8 `CommonSpeakerTables` = [`DT_SpeakerTable`], GI+0x7B8 `CommonProcessTypeTables` (empty).
   Online: GI+0x7D8/0x7E8/0x7F8 (`DT_Rdo_PByP_AWACS`/`_Enemy`, `DT_Speaker`, `DT_ProcessTypeID_Online`). Online vs
   offline is GI vfunc +0xA10. `CommonEventPackages` = the 6 `EP_Play_by_play_Radio_{Ally,AWACS,Enemy,NamedAlly,
   NamedEnemy,Wingman}`, so **play-by-play runs in every campaign-type level, Survival included** (answers question (e)
   of MUSIC_RADIO_CAMERA.md). **[V]/[S]**

So **neither the event package nor the MC_ mission config decides which radio a level has. The level's world settings
do.** `PL_SurvivalMode` imports exactly Mission 22's set **[V]** (imp_pkgs): `DT_Rdo_ST_ms022`, `DT_Rdo_Override_ms022`,
`ms22_AutomaticSpeakerIDTable`, `ms22_OverrideSpeakerTable`, `DT_SpeakerTable`, `DT_ProcessTypeIDTable`.

- The cache is a TMap at subsystem +0x178, RadioGroupID -> rows (lookup 0x14781e8d0, used by RequestRadio's 0x147828d40)
  **[S]**. **Rows added to a table after the level started are not seen** **[I]**: the cache is only filled at init, and nothing
  re-reads the tables. So add rows before the level loads (at the main menu, like DT_SV_NpcRows).
- Per-mission switches: 0x14781d1f0 reads the current mission (campaign context +0xF38, the id Survival sets to 9101) from
  the InformationManager (GI+0x878, 0x147360850). It takes a string from the mission data (LevelStringID, e.g.
  "Mission 022"; Survival's is "Survival Mode"), trims it at the space, and filters rows on the matching `bMxx` column
  **[S, details partly I]**. The shuttle countdown plays in Survival, so an all-true row (every stock ms022 row) passes.
  Note that BUILD_PLAN still lists Comona Defense as `[~] untested`; it is the caller who reports it working. **Keep every
  `bMxx`/`bTxx` true in Survival's rows.**
- **Lines from another mission are not registered in Survival's level.** Mission 23's 379 groups live in `DT_Rdo_ST_ms023`,
  which PL_SurvivalMode doesn't reference. Their speakers and voices are already there: see 2b.

### 1.2 Row and speaker structs (usmap) **[V]**
`LiveRadioTable` (90 props). These are the ones that matter for Survival:
| Field | Type | Notes |
| --- | --- | --- |
| RadioGroupID | **FName** | what the node / RequestRadio asks for. Rows of one group play in row order |
| RadioType / Channel / Priority / InterruptionType | enums, byte | copy from a stock row (ms022: Scenario / Main / 20 / Continue) |
| LimitPlayCount, RequeueingWaitTime | int8, float | ms022 rows: 1 and 20 s. **Set LimitPlayCount 0 (or a high value) for Survival lines that repeat every round [T]** |
| TextID | **FName** | the subtitle key AND the voice (1.3) |
| Subtitle | enum Default / ForceEnable / ForceDisable | 264 stock rows ForceDisable (sound-only lines) |
| SpeakerID | **FString** | a `DT_SpeakerTable` row's SpeakerID |
| OverrideVoiceTypeID / OverrideProcessID / OverrideEnvSEID | FName | voice-FX overrides, not a different clip |
| bShowComWindow, ComWindowNoise, WarningSound, Noise, StartDelay, EndDelay, Volume | | presentation |
| NextRadioGroupID / NextRadioGroupDelay | FName / float | chains to another group |
| bCheckAliveSpeaker, CheckRequiredWingmen, CheckAliveRequiredSpeakers | | skip a line when its speaker is dead or absent (unset in ms022) |
| bM01..bM30, bM25_1/2, bT01..bT15 | bool | per-mission switches (1.1) |
| EventID | int | 746 rows set it (0/1). **Not a voice override** |

`LiveRadioSpeakerTable`: `SpeakerID` (Str), `CallSign` (Str, a text key such as `Callsign_Joker3`, empty for AWACS),
`ComWindowImage` (soft UTexture2D, the portrait), `ColorType` (ELiveRadioColorType), `ProcessID` (Name), `NoiseSound`,
`SilentGroups`, `bPending`. `DT_SpeakerTable` has 1276 rows and is common, so every campaign speaker exists in Survival.
That includes `ms23_*` and the enemy speakers `ms22_Sotoan_Fighter_A..F`. All 22 of Mission 23's speakers are in it.
`LiveRadioProcessTypeTable`: ProcessID -> `VoiceTypeID` (radio FX, e.g. `F_AWACS`, `F_TEAM`) + `EnvseID` (ambience,
e.g. `AKE_Radio_Amb_JET_AWACS`).

Portraits that exist (`/Game/UI/Texture/HUD/SubtitleSpeakerPortrait/T_HUD_SubtitleSpeakerPortrait_00_<X>_000`):
Baxter, Brand, Cope, Coster, Cruz, Doniphan, Evans, Everson, Garnett, Gordon, Green1, Immortal1, ImmortalsCrew,
Jackpot1/2, Jenkins, LandBattleShipNo1/No2Captain, Nagase, Nguyen, Pike, PurpleMagic2/3/4, Sean, Seversky, Shadow24,
Shark2, Stan, Tan, Tasha (000, 001), Tewy, Toprak, Webb, plus the BlockNoise / ComWin frames.

### 1.3 Subtitle, speaker name and voice all come from text keys **[V]**
- **Subtitle = the text of key `TextID`.** All 30,537 rows of the 33 tables (every `DT_Rdo_ST_*` + PByP_CP) were checked
  against the game's text and the voice bank's event list. 30,510 have both a text and a `<TextID>_Play` event, e.g.
  `v2200_0026` = "Joker 1, cleared for takeoff."
- **Voice = Wwise event `<TextID>_Play`** in `DA_SoundDB_AKB_Voice`. The exceptions: 18 rows have a voice but no text,
  7 have a text but no voice, 1 has neither, and 1 has no TextID. The radio plugin's strings include `_Play`, `_Stop`,
  `AKE_FLAG_` and `_TextOnly` **[S, strings]**.
- **Speaker name = the text of key `SpeakerID`.** `LIVE_AWACS` = "AWACS", `ms22_Comona_Space_Base_Air_Traffic_Controller`
  = "Comona Control Tower", `LIVE_Maintenance_team_leader` = "Endurance Mechanic". `CallSign` (when set) is another key.
  The option "Speaker Names" (`OptionDisplay_Select_SpeakerName`) hides them.
- **`AKB_Voice` is one bank for the whole campaign**: 75,432 `_Play` events, including Mission 23's `v2300_*` and every
  `v0001_*` AWACS line. Survival already plays M22 voices, so this bank is loaded in Survival's level, and **any campaign
  mission's voice line can be posted there** **[I, strong]**. Nothing extra has to be loaded for a Mission 23 voice.
- Text-only lines: stock data has 6 `_ALT` keys, alternative subtitles that have no `_ALT_Play` event, e.g.
  `v0002_2006_ALT` (ms004 group `01_W2_Slipped_Close`). `ULiveRadioDeveloperSettings` has `DisplayDurationForTextOnly`,
  not set in `DefaultLiveRadio.ini` (which only sets SubtitleLingeringDuration 1.5 and ...WhenInterrupted 0), so it keeps
  its class default. **So a line with no voice event is probably shown as text for a fixed time [T].**

### 1.4 Playing a group
- **Event node** `LiveRadioPlayExecution` (Execute 0x14748cec0, vtable 0x14c9f1648, from execvt.py). Fields: +0x58
  RadioGroupID (arg0), +0x60 speaker unit (arg1 `02`), +0x68 object (arg2 `0a`), +0x70 float (arg3), +0x74..0x76 bools
  (args 4-6). With bool +0x76 set, the resolved units are split by a dead/alive-style flag (unit +0x3D9 / +0x2E8). Bool
  +0x75 picks "all must pass" over "any" **[S; meaning I]**. Every stock use leaves args 3-6 at 0/false, which plays the
  line unconditionally. It then calls:
- **RequestRadio 0x1478220b0** `(radioSubsystem, FName groupId /*by value*/, AActor* speaker /*or NULL*/, bool)`. It returns
  a request id, or -1 when the group isn't in the cache (it calls 0x147828d40 first) **[S]**. The subsystem comes from
  World->GetSubsystem (0x147144590(world), called at Execute+0x75). The RequestRadio call is at Execute+0x442.
  RequestRadio's signature (mksig, unique, 22 bytes, no wildcards):
  `48 8B C4 55 53 41 54 48 8D 68 A1 48 81 EC C0 00 00 00 48 89 78 10`.
- The cheat manager's `PlayRadio(Name RadioGroupID)` has a real native body (exec 0x1471a7f50 -> 0x1471abde0), unlike
  `OverrideLocText`, whose exec only copies its argument and does nothing else. **[S]** Shipping builds normally have no cheat
  manager object.
- Other nodes (`LiveClearRadioQueueExecution`, `LiveSetActiveRadioTypeExecution`, `LiveSetRadioMuteOptionsExecution`,
  override activate/deactivate, triggers 24/25 Pre/PostRadioEvent): see MUSIC_RADIO_CAMERA.md C.

## 2. Recipes for Survival

### 2a. A stock Mission 22 line (works today)
Mission 22's 264 groups are registered in Survival's level. Use the shuttle pattern: `tpl('LiveRadioPlayExecution',
'CompositeEvent_CountDown_1')` and `g.execute(t_radio, trigger, {0: '<group>'}, delay=...)` in survival_events.py
(SHUTTLE_RADIO). Fire it from Lua through `SV_Event('RE_SV_Radio_<X>')`. Pick groups whose rows are only AWACS, tower or
mechanic (ms022_text.tsv): many groups also have Baxter/Tasha/Coster rows, and those wingmen aren't flying. Usable as they are:
- `00_Enter_Supply_land` (mechanic, "Get that aircraft ready again, now!")
- `01_All_Ship_Destroy`'s 2nd row (v0001_3636 "All enemy vessels destroyed. Well done!")
- `01_Aviation_Judgment` (v0001_2869/2870 "This is Dealer. Air superiority secured." x2)
- `ms22_Supplypoint_1st` (v0001_2881)
- `01_Wave4_Reinforcements_Attacker` (v0001_2857 "Joker Flight, a fourth wave of enemy reinforcements!")
- `01_Aviation_Judgment_Noob` (v0001_2523 "Not yet. More enemies approaching.")

Many good lines sit in `TBD` groups, which you can't call one at a time: v0001_2782 "More incoming from farther out.
Don't let them break through.", v0001_0038 "Joker 1, bandit downed!". Wrap them in Survival's own rows (2b).

### 2b. Lines from another mission, e.g. Mission 23 (one table of Survival's own)
Don't add a whole `DT_Rdo_ST_ms023` to the level. 25 group names collide with ms022 (`00_Appropriate_course_land`, all
the landing guidance), and nothing says which table wins. Instead:
1. **build_survival.py makes `/Game/Mods/SurvivalMode/Data/DT_SV_Radio`** (struct `LiveRadioTable`, one-table copy as for
   DT_SV_NpcRows). Each row is a clone of a stock row from any mission table. Change only `RadioGroupID` to an `SV_Radio_<Name>`
   value (FName: no numeric tail, hard rule 17), and give the row an `SV_Radio_<Name>_<k>` name so it can't collide with the
   stock "1".."7740". Keep its `TextID` (= its voice), `SpeakerID`, process type, delays and all-true `bMxx`. Raise
   `LimitPlayCount` for lines that repeat per round. Several rows with the same group = a multi-line call.
2. **Register it before the level loads.** Pick one:
   - (recommended, uses existing machinery) main.lua, at the main menu: load DT_SV_Radio (hard rule 9 route) and
     `AddRow` each row into **`DT_Rdo_PByP_CP`**. That table is always loaded (BP_LiveGameInstance hard-refs it as
     CommonRadioTables), so the rows are there when Survival's radio subsystem builds its cache. Other missions never
     request `SV_Radio_*` groups, so nothing changes for them. This matches hard rule 10 / DT_SV_NpcRows.
   - or append the loaded DT_SV_Radio to `GameInstance.CommonRadioTables` (a reflected `TArray<UDataTable*>`) and pin it
     (ReferencedObjects). Remove it after the run if wanted. **[I, untested]**
   - or (build time) add DT_SV_Radio as a 2nd `RadioSettings.RadioDataTables` entry in PL_SurvivalMode, with import and
     container header per hard rule 7. That needs a ChronicleWorldSettings serialiser: `dump_export.py` / `uprop` fail on
     that export today (`_err 4`).
3. Fire it like 2a. The EP record's arg 0 is the group name; it needs no import, because the node class is already in
   Survival's EP. Or call it natively (2d).
- Speakers: no work. `DT_SpeakerTable` is common, and M23's `ms23_*` speakers are in it.
- Voice: no work. Same `AKB_Voice` bank (1.3).
- Process type: `DT_ProcessTypeIDTable` (the level's) is the only offline one, so any campaign ProcessID resolves **[I]**.
- Candidates found in `awacs_all.tsv` (AWACS = "Dealer", no portrait):
  - inbound: ms028 `02_waves_AWACS` v0001_4111 "Bandits inbound! More reinforcements!", ms006 v0001_3682 "Bandits on radar! We've got company!"
  - all clear: ms017 v0001_2480 "All clear! No enemies in sight."
  - Ladon: ms016 v0001_1689 "Joker Flight. Engage the large aircraft immediately!"
  - Podarge: ms025_2 v0001_3417 "Bogey approaching from the southwest. It's a Podarge!"
  - Land Aegis: ms008 v0001_2365 "It's a Land Aegis. Watch out for SAMs from the VLS.", v0001_1463 "Land Aegis destroyed!"
  - ECM: ms012 v0001_0536 "Hostile EW aircraft destroyed! Jamming has been lifted!", ms023 v0001_2705 "Jamming device disabled!"
  - stealth: ms021 v0001_2085 "Joker 1 engaged stealth aircraft."

  Check each subtitle for place names before using it.

### 2c. Survival's own lines
| Want | Route | Status |
| --- | --- | --- |
| **Text-only line** (custom subtitle, no voice) | DT_SV_Radio row with `TextID = SV_Radio_<X>` (FName). The subtitle goes through the text lookup (section 3), which Survival's hook answers; `SV_Radio_<X>_Play` doesn't exist, so the line is silent | [I] subtitle path, [T] text-only display |
| **Custom speaker name** | A `DT_SV_Speakers` row (clone `LIVE_AWACS` or the tower) with `SpeakerID = SV_Spk_<X>`, text key `SV_Spk_<X>` = "COMONA COMMAND". AddRow it into **DT_SpeakerTable** at the main menu (common table, always loaded). The radio row's SpeakerID = `SV_Spk_<X>` | [I] (speaker names are text keys: verified in data) |
| **Portrait** | `ComWindowImage` = any stock `T_HUD_SubtitleSpeakerPortrait_*`, or None for AWACS-style. Your own art needs a cooked UTexture2D package in Survival's container: a separate job (Survival ships only stock-derived packages) | [I] |
| **Custom subtitle on a stock voice clip** | No row field does it: `TextID` drives both the subtitle and the voice. Only route: the row keeps the stock `TextID`, and the runtime's text hook overrides **that stock key** while mission 9101 runs (a new override map in OnText, checked before the SV_ test). The voice still says the stock words, so it's only good for paraphrases or translations of the same line | [I] |
| **New voice audio** | Needs a Wwise bank and event of Survival's own (`<TextID>_Play`, plus a sound-DB entry). Out of scope | |

Text-only presentation: the radio window still shows the speaker; ProcessID adds the radio noise/ambience. For a "system"
look, clone a row with `bShowComWindow` false **[T]**.

### 2d. Native `SV_Radio(group)` (optional, like SV_PlayBGM)
Decode both calls from LiveRadioPlayExecution::Execute (the vtable route of execvt.py, or a signature on its body): the
subsystem getter at +0x75 and RequestRadio at +0x442. Then `id = RequestRadio(GetSubsystem(world), FName(group), NULL, 0)`.
Lua gets the id: **-1 = group not registered**, which is the quickest way to check 2b's registration. It needs no EP record
per line, so Lua can pick lines at random. It runs on the game thread, as the other SV_ calls do.

## 3. Localisation

### 3.1 Where the game's text lives **[V]**
- **Not in UE FText/locres.** `Live/Content/Localization/Game/<culture>/Game.locres` exists for 13 cultures, but each is
  37 bytes (header only, no entries). `Engine.locres` holds engine strings only.
- The game uses **Ace Combat 7's own text system**: `Live/Content/Localization/GameData/` in the **legacy**
  `pakchunk0-Windows.pak`, staged as loose UFS files (`DefaultGame.ini: +DirectoriesToAlwaysStageAsUFS=(Path="Localization/GameData")`).
  - `CP_Cmn.dat`: campaign/common IDs, 44,736 keys -> 46,584 string slots. `CP_A.dat` .. `CP_M.dat`: one per language.
  - `ON_Cmn.dat` + `ON_A..M.dat`: online, 9,188 keys.
  - The exe also knows **`DLC_Cmn.dat`** (inlined literal at 0x14cb676a0). The loader 0x1473b04f9 reads it only when byte
    0x14e525188 is set **[S]**, and no DLC_ files ship today.
- Format (Loc.cs / acloc.py): a zlib stream XORed with a keystream seeded by (file length + language index). Cmn is a prefix
  tree of UTF-8 keys -> slot numbers. A language file is NUL-separated UTF-8 strings.
- **Language letters**, from the exe's culture table at 0x14cb653b0, used by BuildLangFilePath 0x1473b0180 **[S]**:
  A `ja`, B `en`, C `zh-CHT`, D `fr`, E `de`, F `it`, G `ko`, H `es`, I `es-MX`, J `pl`, K `pt-BR`, L `ru`, M `zh-CHS`.
  The data agrees: B = English, H = Spain Spanish ("¿Me oís?"), I = Latin American ("¿Me escuchan?").
- Example keys: `ContainerEnemyCallsign_Name_Shark` = "SHARK". Banners: `HudMissionprogress_Name_Missionupdate` =
  "MISSION UPDATED", `..._Waveupdate` "WAVE UPDATED", `..._Missionstart` "START MISSION", `..._Missionaccomplished`,
  `..._Missionfailed`, `HudMinigames_Name_Takeoffclear`, `..._Landingsuccessful`, `HudOther_Name_Returnbase`. Radio:
  `v<speaker>_<line>`. Speakers: `LIVE_*`, `msNN_*`. Cutscene names: `CINEMA_LIVE_*`.
- Markup in strings: `<color id="HUD_...">text</>`, `<img id=".."/>`, `<btn id=".."/>`, `<axis id=".." scale=".."/>`,
  and placeholders `{0}`, `{AircraftName}`, ...

### 3.2 The text manager at run time **[S]**
- A native singleton (not a UObject): `&mgr` = 0x14e511bc0, returned by 0x146eaed90 (built by 0x1473b04c0 on first use).
- **Two language slots.** +0x50 is the text language, its culture FString at **+0xF0**: SetTextLanguage 0x1473b18e0
  stores the culture there and reloads the slot. +0xA0 is a second language, its culture at **+0x100**: 0x146eaeea0
  stores it and reloads that slot. Each slot holds a map of set name ("CP"/"ON"/"DLC") -> key tree, and set name -> string
  array. The voice language is separate: 0x1473b1a20 sets Wwise "English(US)" or "Japanese" (mgr +0x110).
- **Lookup 0x1473B1750** `(mgr, bool secondSlot, const FString* key, bool* found) -> const FString*`. It searches each
  loaded set for the key. On a hit it sets `found` and returns that language's string. **On a miss it returns the key
  itself**, so an unknown key shows on screen as the raw key. Only two direct callers exist, both wrappers:
  - 0x146EAF1C0 (`(out, bool, key)`): copies the result, then runs 0x1473b3210 on it, the markup and icon pass (button
    glyphs U+E100..). 140 call sites. 131 pass slot 0 and 5 pass slot 1 (cinematics-style callers).
  - 0x146eaf2e0: the same lookup followed by `{n}` argument formatting.
- Reflected entry points: a UMG text widget's `SetLocalizeText(FString InTextID)` (exec 0x146eb0d80, one-function class).
  The cheat manager's `OverrideLocText` and `ShowlocalizationID` are stubs.

### 3.3 How Survival's texts fit
`OnText` (runtime/survival_rt.c, via kSigText) is an inline hook on **0x1473B1750 itself**, so it sits under both wrappers
and every one of the 141 call sites. Its `table` argument is the manager `mgr` and its `flag` argument is the slot bool.
An `SV_` key returns Survival's FString with `found = 1`. It still goes through the wrapper's markup pass, so `<color id=...>`
and `{0}` work in Survival texts as they do in stock ones **[I]**. The radio code is protected in places, but the radio
subsystem's own code region calls 0x146EAF1C0 (call sites at 0x14781f328 and 0x1477f5a4a), so radio subtitles should go
through the same lookup and therefore through the hook **[I, strong; T1]**. Stonehenge's main.dll hooks the same function
for `SH_` keys, and Survival chains onto it.

### 3.4 Translations: how Survival should do them
**Keep the hook and make its tables per-language.** The current culture is right there: `*(FString*)(mgr + 0xF0)`
(or `+0x100` when `flag` is 1) is one of the 13 strings in 3.1 **[S]**, and it updates when the player changes language.
1. Ship `Mods/AC8SurvivalMode/text/<culture>.tsv` (UTF-8, `key<TAB>text`, `\n` for line breaks), using the game's own
   codes: `en.tsv`, `ja.tsv`, `de.tsv`, `fr.tsv`, `zh-CHS.tsv`, ... `en.tsv` is complete. Others may be partial. Like
   Stonehenge's `data\text.tsv`, translators need no build step.
2. The runtime loads every file at start-up. OnText picks the table for the current culture (cache the last culture string
   and table pointer), falls back to `en`, and then to the original call (raw key). That replaces the hard-coded `g_text[]`.
3. Texts Lua builds (shop rows with prices, ace names): Lua must not hard-code English. Add `SV_Text(key)` (the current
   language's template) and `SV_Lang()` (the culture). Lua fills `{0}`-style placeholders and passes the result to
   `SV_SetText` as now. Re-run it when `SV_Lang()` changes: the dynamic slots hold one language at a time.
4. Radio subtitles and speaker names that are `SV_` keys (2c) are then translated automatically. Stock radio lines and
   banners are already in all 13 languages.
5. CJK and Cyrillic: the stock fonts already render these languages (DT_SubtitleFont exists for subtitles) **[I]**.
   Note that ja/ko/zh strings in the stock files have no spaces in them.
6. Optional: an override map for **stock keys**, active only while mission 9101 runs. For example
   `HudMissionprogress_Name_Waveupdate` -> "ROUND 5" just before `LiveMessageExecution WAVE_UPDATE`, which would give a
   per-round banner (HUD_NOTES.md says the banner text is fixed). Untested: the widget may cache the text **[T4]**.

**Don't:**
- edit or override `CP_*.dat`: shared stock files, 13 x ~0.5 MB, break with every game patch and with Ace8LocEd users' edits.
- ship `DLC_*.dat`: reserved for the official DLC, gated by a flag, and two mods can't both own it.
- use UE StringTables or locres: the game's TextID widgets never consult them.

## 4. Small in-game tests
| # | Test | Expect / decides |
| --- | --- | --- |
| T1 | EP record (or SV_Radio) playing a Survival row cloned from v0001_2869, with `TextID` changed to `SV_Radio_Test` and SetText `SV_Radio_Test` = "SURVIVAL TEST LINE" | subtitle "SURVIVAL TEST LINE" = radio goes through the hook; the raw key = it doesn't. Also shows whether a voiceless line is shown, for how long, or skipped (DisplayDurationForTextOnly) |
| T2 | The same group's rows with stock `TextID`s from Mission 23 (e.g. v0001_2705) and Mission 16 (v0001_1689), added to DT_Rdo_PByP_CP at the main menu | voice + subtitle play in Survival = 2b works, AKB_Voice is global, rows added before load are cached |
| T3 | Same as T2, but AddRow after the level has loaded | not played (or SV_Radio returns -1) = the cache is init-only, as read in 1.1 |
| T4 | `SV_SetText`-style override of `HudMissionprogress_Name_Waveupdate` (needs the stock-key override map), then fire WAVE_UPDATE | banner says "ROUND n" = per-round banners possible |
| T5 | Switch the game's text language to Japanese, open the Survival menu; log `*(FString*)(mgr+0xF0)` from OnText | logs `ja` = the culture source for 3.4 is right |
| T6 | A DT_SpeakerTable row `SV_Spk_Command` (clone of LIVE_AWACS, portrait T_HUD_SubtitleSpeakerPortrait_00_Stan00_000) used by T1's row | speaker shows "COMONA COMMAND" (text key) and the portrait |
| T7 | Survival row with `LimitPlayCount` 1 vs 0, played twice | how often a line can repeat per run |

## 5. Addresses (current exe)
| What | Address | Find by |
| --- | --- | --- |
| text lookup (hooked) | 0x1473B1750 | kSigText (runtime/sigs.h) |
| text manager singleton / getter | 0x14e511bc0 / 0x146eaed90 | getter is called at the wrappers' start |
| SetTextLanguage (culture -> mgr+0xF0) | 0x1473b18e0 | mksig: 31 bytes, 4 wildcards, unique |
| 2nd language (mgr+0x100 / slot +0xA0) | 0x146eaeea0 | |
| culture table (13 x wchar_t*) | 0x14cb653b0 | |
| LiveRadioPlayExecution::Execute | 0x14748cec0 | execvt.py (vtable 0x14c9f1648, slot 87) |
| radio subsystem init / AddRadioTables | 0x1478246c0 / 0x147824930 | |
| RequestRadio | 0x1478220b0 | `48 8B C4 55 53 41 54 48 8D 68 A1 48 81 EC C0 00 00 00 48 89 78 10` |
| group cache lookup | 0x147828d40 -> 0x14781e8d0 (subsystem +0x178) | |
| GameInstance CommonRadioTables / Speaker / ProcessType (offline) | GI+0x798 / +0x7A8 / +0x7B8 | |
