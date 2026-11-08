# Music banks: who loads AKB_BGM_Online_Lobby, and the music player's track list (research, 2026-11-08)

Static analysis of the current AceCombat8.exe (after the 2026-11-02 patch); nothing here has been run in game.
[D] decoded / verified in code or data, [I] inferred, [T] needs an in-game test. Addresses are for this exe: find them
by signature. Scratch dumps were made in the session scratchpad only (sound region 0x147880000-0x1478c0000, music player
region 0x147b20000-0x147b40000); tools: exe.py, refl.py property params (+0x32 offset), mksig.py, dump_props.py.

## Answer in short
- **AKB_BGM_Online_Lobby is already resident in every mode. Nothing has to load it.** [D] It is in
  `DA_SoundSettings.RegidentSoundBanks`, and the sound manager's one-time init queues a load for every name in that
  list at game start. No unprivileged code unloads a bank afterwards. [D for the clear code; the protected .sbss code
  can't be scanned]
- Route 1 (Lua: add the name to RegidentSoundBanks) does nothing. The name is already in the list, and the list is read
  once, in GameInstance init, before the main menu. [D]
- Route 2 (native load call) isn't needed. If another bank ever has to be loaded, the safe way is to push a request onto
  the bank thread's queue (section 3), not to call the loader directly.
- So if a jukebox event stays silent in Survival, the bank isn't the cause. Possible causes to test, in order [T]:
  (a) the music player never posts the event, because the track isn't in its list (section 5);
  (b) the post fails for some other reason. Check the post's playing ID (section 4).
  The Lobby bank's events are streamed, as the campaign MUSICPLAYER events are (StreamCookedData: 77 entries in
  Lobby, 253 in Campaign; every event has `bIsStreaming` true and PackagingStrategy 1). So they should stream the same
  way the MUSICPLAYER tracks already do in Survival. [I]

## 1. Data [D]
- `/Game/WwiseAssets/DA_SoundSettings` (ULiveSoundSettings; pulled into build/stock with get_stock.sh).
  `RegidentSoundBanks` (sic), in order: game_se, AKB_GameSe, AKB_BGM_3D, AKB_BGM_Campaign, AKB_BGM_Cinema,
  AKB_BGM_Online, **AKB_BGM_Online_Lobby**, AKB_PlayerAircraft, AKB_Voice, AKB_Cinema, AKB_Briefing, voice, AKB_IGC,
  AKB_GameSe_Online, AKB_Voice_Online, AKB_Cinema_Voice, AKB_GameSe_DLC, AKB_Voice_DLC, AKB_Cinema_DLC.
- `/Game/WwiseAssets/DA_SoundDatabase` (ULiveSoundDatabaseAsset). `BankAssets` (TMap<FName, bank asset>, 23 entries)
  includes AKB_BGM_Online_Lobby -> DA_SoundDB_AKB_BGM_Online_Lobby. It has no AKB_Online_Jukebox (that name is in
  BGMBankList only, with no database asset: a dead entry).
- DA_SoundDB_AKB_BGM_Online_Lobby: one bank, ID 0x8aaa4055, LanguageName SFX, Path AKB_BGM_Online_Lobby.bnk,
  NumEvents 78 (77 `AKE_Bgm_JukeBox_*_Play` events + one more), DataSize 0x1223e2, CookedData bContainsMedia true.
  Media are streamed .wem files: `WwiseAudio/Media/<id>.wem`, e.g. JukeBox acz_ZERO -> 128403660.wem.
- Reflected offsets (refl params): ULiveSoundSettings DatabaseAsset +0x50, BGMDataAsset +0x58, LobbyDataAsset +0x68,
  **RegidentSoundBanks +0x78** (Num +0x80), MusicPlayerDataTable +0x260. ULiveSoundBGMDataAsset BGMBankList +0x30,
  EventDelayList +0x80, HighPriorityBGMIDs +0x120. ULiveSoundDatabaseAsset BankAssets +0x140.
  ULiveSoundDatabaseBankAsset NumEvents +0x4c, Banks +0x50 (FLiveSoundDBBank, 0x130 bytes each), CookedData +0x60,
  StreamCookedData +0xc0, CookEvent +0x110. FLiveSoundDBBank: Name +0xc, ID +0x14, Type +0x18, LanguageName +0x1c,
  Path +0x24, Busses +0x70, ..., CookedData +0xc0, NumEvent +0x120, DataSize +0x128. ULiveSoundManager SoundSettings
  +0x210, LobbyDataAsset +0x158. ULiveGameInstance SoundSettings +0x828.

## 2. When the resident banks load [D]
- GameInstance init (the large function 0x1478c9ac1..0x1478cc1b5) creates the sound manager at GI+0x908 and, at
  0x1478ca193, calls **ULiveSoundManager init 0x147892220** `(soundManager, ?, GI->SoundSettings (+0x828))`. That is
  its only caller. The init stores the settings at soundManager+0x210 and the manager at the global 0x14e50fff8.
  Signature (mksig, with a mask for the je rel32): `4D 85 C0 0F 84 ?? ?? ?? ?? 4C 8B DC 55 53 56 49 8D AB 48 FF FF FF`.
- In that init, at 0x147892691..0x14789274e: `sub = soundManager+0x1c8`. If audio is on (byte 0x14e510039) and
  `sub+0x130` (the bank thread's runnable) isn't null, then for each name in settings+0x78:
  EnterCriticalSection(sub+0x108); `req = TArray add (0x1478bcc60)(sub+0x138)`; `req.name = name`;
  `*(u32*)(req+8) = 0x01010101`; `req+0xc = sub+0x198++`; LeaveCriticalSection. Then `(*(sub+0x130)+0x10)->vtbl[2]()`
  (FEvent::Trigger). Each name is skipped when byte 0x14e410248 is set (a global "exiting" flag [I]).
- `sub` (soundManager+0x1c8) is the object that holds the queue, the loaded-bank map and the bank database index (+0x348).
  0x1471d1470 returns the same kind of object (GEngine+0xfc0 engine-subsystem lookup with ULiveSoundSubsystem's
  StaticClass 0x146ff5fd0: class name string "LiveSoundSubsystem", size 0x590). So `sub` is **ULiveSoundSubsystem**
  [I, strong: both use +0x348 the same way]. Its constructor and ULiveSoundManager's are in protected code (jumps into
  .sbss), so their layouts come from use, not from the constructor.
- Only two places in clear code add requests to the queue (xref of the add helper 0x1478bcc60): the resident loop above
  and the language change 0x1478a4d20 (type 3, called from 0x14739e493). The loader's Load 0x1478a5090 and Unload
  0x1478a5370 are each called only from the thread loop. No type-2 (unload) request is ever queued in clear code, so
  resident banks stay loaded for the whole process. The language change (0x1478a5490) posts
  AKE_System_LanguageChange_Pre/Post, sets the language and rebuilds the database, and doesn't unload any bank.
- **BGMBankList isn't a load list** [D]. Sound setup 0x1478a3580 (rcx = the subsystem, rdx = the sound manager, stored at
  sub+0x340) copies it into sub+0x410 (`0x141900280(sub+0x410, settings->BGMDataAsset+0x30)`, at 0x1478a3861). The loader
  never reads it. I didn't find its reader; it probably marks which banks' events count as BGM [I]. Nothing decides
  "online banks only in online mode": all three BGM_Online* banks are resident.

## 3. The bank thread ("LiveSoundBankThread") [D]
Run loop 0x1478a4ee0 (FRunnable::Run; `this`+0x9 running, +0x10 FEvent*, +0x20 the subsystem):
`ev->Wait(-1)` (vtbl +0x20); lock sub+0x108; while queue Num (sub+0x140) != 0: lock sub+0x4a0; take the front 16-byte
request and set its +0x9 to 2; unlock 0x108; switch on type: **1 -> Load 0x1478a5090(sub, name, req+0xa, req+0xb, &req+0xc)**,
2 -> Unload 0x1478a5370(sub, name, req+0xb), 3 -> language 0x1478a5490(sub, name); then lock and remove the front, unlock.
Signature of the loop: `48 8B C4 41 55 48 83 EC 60 80 79 09 00 4C 8B E9`.

Request (sub+0x138 TArray, 0x10 bytes each): +0 FName bank, +8 type (1 load / 2 unload / 3 language), +9 status
(1 queued, 2 taken), +0xa flagA, +0xb **reference mask**, +0xc serial.

**Load 0x1478a5090** `(sub, FName bank, u8 flagA, u8 mask, int* serial)`, bank thread only:
1. `rec = Find 0x1478a5a40(sub, bank)` (under sub+0x108). If the bank is already loaded: `rec+0x11 |= mask`; return.
   So loading twice is safe: it only ORs a mask bit (refcounting is a bitmask, not a counter).
2. Looks the bank up in the database index `0x147891420(sub+0x348, &bank, 1, &out)` -> bank asset `sub+0x490[out+0xc]`
   -> FLiveSoundDBBank `asset+0x50 [asset+0x118] * 0x130`. If the bank's ID (+0x14) is 0 (not found: the empty record at
   0x14e337410), it returns without loading.
3. Allocates a 0x28-byte record: +0 serial, +4 FName, +0x10 flagA, +0x11 mask, **+0x12 state (1 loading, 2 loaded)**,
   +0x18 DataSize, +0x20 the Wwise loaded-bank handle.
4. Bank asset = `DatabaseAsset (sub+0x350)`.BankAssets (+0x140) [bank]. The Wwise resource loader comes from
   `0x146279b20()` -> vtbl +0x40 (shared ref), then **`vtbl +0xc8 (loader, &bankAsset->CookedData (+0x60), nullptr)`**:
   a blocking LoadSoundBank on the bank thread [I: matches FWwiseResourceLoader::LoadSoundBank(cooked data, language
   override)]. A non-null handle -> rec+0x20, state 2, and the record goes into **sub+0x148**
   (TMap<FName, rec*>: elements 0x18 bytes {FName, rec*, hash next, hash index}, Num +0x150, NumFree +0x17c, hash
   inline +0x180 / pointer +0x188 / size +0x190) under the lock. A null handle frees the record.
   Signature: `48 89 54 24 10 55 56 41 56 48 83 EC 60 41 0F B6 F1`.

**Unload 0x1478a5370** `(sub, bank, mask)`: `rec+0x11 &= ~mask`; when nothing is left, it removes the record from
sub+0x148 and calls loader vtbl +0xd0 (UnloadSoundBank(&handle)). Signature:
`48 89 5C 24 10 48 89 6C 24 18 56 57 41 56 48 83 EC 30 48 8D B9 08 01 00 00`.
Find 0x1478a5a40: `48 89 5C 24 08 48 89 6C 24 10 48 89 74 24 18 57 48 83 EC 20 48 8D B9 08 01 00 00 48 8B F1`.

**If a bank ever has to be loaded** (none does for the jukebox), copy the resident loop from the game thread:
`sub = *(GI+0x908)+0x1c8` (check that sub and `sub+0x130` aren't null). EnterCriticalSection(sub+0x108) (KERNEL32 IAT
0x14ab04490 / Leave 0x14ab04498: [D] via peinfo). Append the request with the array helper 0x1478bcc60(sub+0x138)
(signature from mksig: `48 89 5C 24 08 57 48 83 EC 20 48 63 79 08 48 8B D9 8D 47 01 89 41 08 3B 41 0C 76 07 8B D7 E8 ?? ?? ?? ?? 48 8B C7 48 C1 E0 04`;
it returns the new 16-byte slot). Write {FName, 1, 1, 1, a mod-owned mask bit such as 0x80, sub+0x198++}, leave, then
Trigger `*(*(sub+0x130)+0x10)`. Thread safety: the queue and the map are guarded by sub+0x108; Load runs only on the
bank thread. Never call 0x1478a5090 from the game thread: it would race the thread on Wwise [I]. The load is
asynchronous for the caller. Poll the sub+0x148 map (under the lock) for state 2. [T]

## 4. Checks for the next test [T]
1. Does a jukebox event play at all? In Survival, Lua
   `ULiveSoundBlueprintLibrary:PostEventByName(world, FName("AKE_Bgm_JukeBox_ac04_Comona_Play"))`: a playing ID other
   than 0 means the event is known, so the bank is loaded. Natively, `SV_PlayBGM("AKE_Bgm_JukeBox_ac04_Comona_Play")`
   and `SV_BGM` (controller +0x148: 2 playing, 3 post failed). Note: the BGM controller's own event set (built by
   0x1478a9b90 from AKB_BGM_Campaign only) leaves out names containing "JukeBox", "Online" or "MUSICPLAYER" and needs
   "_Play". Whether the controller's Play refuses events outside that set wasn't checked. The music player doesn't go
   through the controller (it posts with 0x1478a8f70 on the sound manager), so test the plain post first.
2. Optional native diagnostic: walk sub+0x148 under sub+0x108 and log each bank's FName, state (+0x12) and mask (+0x11).
   AKB_BGM_Online_Lobby should read state 2, mask 1.
3. Bus / scene state: if the post succeeds but nothing is heard, the Lobby events may sit on a bus muted outside the
   lobby scene state (`SceneStateValue`: Menu/Game/Pause...). That can't be told from the exe.

## 5. The music player's track list (answer to the coordinator's question, 2026-11-08)
- **Copied once at start, not read live.** [D] The playlist database's build **0x147b26b50** `(ULiveMusicPlayerPlaylistDatabase*)`
  first clears its own array (+0x30, 0x20-byte entries; count kept at +0x48). It then makes a new
  ULiveSoundMusicPlayerList (0x147819980) and stores it at +0x40 (SoundList). It calls
  **ULiveSoundMusicPlayerList init 0x14789bc20** `(list, settings->MusicPlayerDataTable (+0x260))`, which stores the
  table at list+0x90 (the reflected `DataTable` is at **+0x90**, not +0x28; +0x28 is a native TArray of 0x20-byte
  entries) and rebuilds list+0x28 from the table's row names (0x14789be90 clears that array first). After that the pages
  read the cached arrays. A row added with AddRow after the build doesn't show until the build runs again.
- **Who runs the build** [D]: only `0x147b296f0(musicPlayerSoundManager)` (gets the database with 0x147b1e9b0, builds it,
  then sets mgr+0xe0 to the first entry it gets back). It is called from:
  (a) ULiveMusicPlayerSoundManager vtable 0x14c875f98 slot +0x308 (0x147b29970, the subsystem's Initialize [I]: once at
  game start, before the main menu);
  (b) a Data Viewer page's virtual at vtable 0x14c80f518 +0x7e0 (0x147b1add0, it builds the string "DataViewerEditPlaylist") [I];
  (c) a fragment at 0x147b20042 (sets +0x140 and calls it) whose parent wasn't traced.
  So AddRow at the main menu or at level load shows nothing in the list until (b), (c) or a direct call runs. [I]
- **Rebuilding on purpose** [I, T]: call `0x147b296f0(mgr)` after the AddRows, with mgr = the
  ULiveMusicPlayerSoundManager GameInstance subsystem (the same object the music runtime already uses; SoundController
  +0x100). Do it from the game thread, with the music page closed and no music-player track playing: the call replaces
  SoundList with a new object and resets mgr+0xe0. Signature (mksig, mask on the call):
  `48 89 5C 24 08 57 48 83 EC 30 48 8B F9 E8 ?? ?? ?? ?? 48 8B D8 48 85 C0 74 5D`. The build itself:
  `40 55 53 56 57 41 54 41 57 48 8B EC 48 83 EC 78 8B 71 38`.
- **What makes a row visible / owned** [D for the code, I for "visible"]: for each row (FLiveSoundMusicInfoRow:
  TitleString +0x18, **bIsEnableUnlock +0x38**, **UnlockMissionID +0x39**), when bIsEnableUnlock is true the build checks
  that the save's mission-record list (save+0x1e0 -> +0x1e8 array, 0x48-byte entries, mission ID at +8) has
  UnlockMissionID; it skips the row if not. When bIsEnableUnlock is false (or the mission is found), the build adds the
  row name to the save's **OwnedMusicList** (save+0x1e0+0x470) and **NewlyOwnedMusicList** (+0x480) when it isn't there
  yet. So the visible set is OwnedMusicList, and a row with bIsEnableUnlock false is granted at the next build.
- Risk: granting writes Survival's row names into the player's save (OwnedMusicList / NewlyOwnedMusicList), and they
  stay there after the mod is removed. They'd name rows that don't exist then; what the game does with an unknown name
  is untested. [T]

## 6. How long a looping Online Mode track is (2026-11-08, 0.74.34) [D]
Saint Alessia's run of 0.74.32: "hush still ended abruptly". Each AKE_Bgm_Online_* event (AKB_BGM_Online.bnk, bank
version 154, in pakchunk0) is one play action (0x0403) on one Sound (HIRC type 0x02: AkBankSourceData plugin 0x00040001
Vorbis, stream type 1, then the media id) whose .wem streams from pakchunk10 (WwiseAudio/Media/<id>.wem). The database
gives these no length (DA_SoundDB_AKB_BGM_Online: DurationType 2, no DurationMin / Max), and the loop is in the .wem:
its smpl chunk's first loop (Hush: 48 kHz, 15,738,843 samples = 327.9 s, loop 1,838,678 - 15,005,181 = 38.3 - 312.6 s).
Wwise plays to the loop's end and goes back to its start, so one pass is the loop's end (the tail after it is never
heard). 0.74.32 used the lobby jukebox's recording of the same song (332.1 s, DurationMin = DurationMax): 19 s into
Hush's second pass. Werewolf's Online Mode mix is 518.8 s a pass (8:39, two of the album's runs). tools/music_lengths.py
reads them (only each .wem's first pak block) and writes sv_music.lua's SONG LENGTHS (116 tracks).

## Open
- The readers of BGMBankList's copy (sub+0x410) and of the bank assets' StreamCookedData weren't found in clear code.
- Code in the protected .sbss section (e.g. 0x15c316e8e, 0x157165ae9, 0x1572b127c) can't be scanned and might queue or
  unload banks. Only an in-game check (section 4) settles that.
