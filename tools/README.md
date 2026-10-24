# Survival Mode build tools

One command builds everything (Git Bash): `tools/build_all.sh`
Output: `build/install/SurvivalMode/SurvivalMode_P.utoc` + `.ucas`. Copy the `SurvivalMode` folder into
`...\ACE COMBAT 8\Game\Binaries\Win64\ue4ss\Mods\IoStoreLoaderMod\`.
Also `build/install/AC8SurvivalMode` (the UE4SS runtime: `Scripts/main.lua` from `mod/UE4SS/AC8SurvivalMode`, and
`dlls/main.dll` built from `runtime/`): copy it into `ue4ss\Mods\`.

## Setup (once)
- Python 3.8+ (no extra packages).
- `tools/bin/retoc.exe` and `tools/bin/oo2core_9_win64.dll`: copy them from `E:\ACE8AircraftBuilder\` (not in git).
- LLVM for `runtime/build.sh` (not in git): `tools/llvm/LLVM/bin`, unpacked without admin rights from the winget-downloaded
  installer with `msiexec /a LLVM-<ver>-win64.msi /qn TARGETDIR=<repo>\tools\llvm`, or any LLVM on PATH.
- The game's AES key is read from `E:\ACE8AircraftBuilder\settings.json` at run time. Never commit it.

## Scripts
| Script | What it does |
| --- | --- |
| `build_all.sh` | get_stock -> runtime/build.sh -> build_survival -> pack -> stage `build/install/` |
| `package_release.sh online\|offline [version]` | After build_all: a Nexus release zip of one edition, `build/release/AC8SurvivalMode_<version>_Online.zip` / `_Offline.zip`. Offline: `main.dll` rebuilt with SV_OFFLINE (`OFFLINE=1 runtime/build.sh`), `main.lua` / ini / readme through `edition.py offline` (the `ONLINE ONLY BEGIN/END` blocks go, `OFFLINE:` lines come in), and the zip is refused if any network code is left |
| `package_test.sh [name]` | After build_all: test-release zip `build/release/AC8SurvivalMode_<name>.zip` (the staged mod + `release/README.txt` with the versions filled in; no player settings or logs) |
| `../runtime/build.sh` | Native runtime `survival_rt.c` -> `build/runtime/main.dll` (clang + lld-link, no SDK/CRT) |
| `re/` | Reverse-engineering: `exe.py` (PE reader: xrefs, .pdata function bounds, disassembly), `mksig.py <va>` (unique masked signature for runtime/sigs.h), `minidump_stack.py` (crash dumps), plus the Milestone 1 helpers `xrefs.py`, `fn.py`, `peinfo.py`, `sigfind.py`; notes: `hud_layout.py <widget pkg>` (a widget blueprint's layout on the 3840x2160 HUD canvas), `re/SPAWN_SYSTEM.md` (how the game spawns units, Survival's spawner), `re/HUD_LAYOUT.md` (the game's HUD layout and how Survival builds its own HUD at run time), `re/AMMO.md` (the player's live ammo counts and Survival's SV_Ammo / SV_SetAmmo), `re/GAME_LUA.md` (the game's own Lua 5.3, how behaviour scripts load, Survival's SV_GameLua bridge), research notes from 2026-10-22: `re/AI_BEHAVIOURS.md`, `re/NPC_DATA.md`, `re/UI_SHOP_SAVE.md`, `re/MUSIC_RADIO_CAMERA.md`, `re/HELIOS_VFX.md`, `re/SPECIAL_ROUNDS.md`, `re/KILLS_HEALTH_DEATH.md`, `re/AIRFIELD_SUPPLY.md`, `re/EVENTS_AIRCRAFT.md`, `re/EVENT_NOTES.md` (event package records), `re/STONEHENGE_MAIN_DLL.md` (menu hooks) |
| `lua_split.py [--write]` | Made the runtime's parts (Scripts/sv_*.lua) and the small controller main.lua out of the old one-file main.lua (2026-10-24), checking the pieces rebuild it byte for byte; kept for the record (it refuses to run on the controller) |
| `x02s/build.sh` | VALKA's X-02S from AC7 (UE 5.4 cook, its own container SurvivalMode_Valka_P): see x02s/README.md |
| `get_stock.sh <path>...` | Pulls stock zen packages out of the game Paks into `build/stock/` (e.g. `Maps/Ingame/Mission022/PL_Mission022.umap`) |
| `build_survival.py` | Writes Survival's packages into `mod/Content` from stock game templates only (see its docstring) |
| `pack.py` | Packs `mod/Content` into `SurvivalMode_P` with retoc `pack-raw`; container header imports come from each package's own import list |
| `zenpkg.py` | Zen package editor that handles wide (Japanese) names; `python zenpkg.py <pkgs>` checks round-trips |
| `make_scriptobjs.py` | Builds `scriptobjs.pkl` for `scripts/zen_ep.py` from `retoc print-script-objects` (inspection only) |
| `checks/` | Inspectors: `dump_props.py`, `dump_export.py`, `imp_pkgs.py`, `wd_find.py`, `verify_headers.py`, `ep_dump.py` (any event package's triggers/execs), `tex_info.py` (a cooked texture's size / format / virtual-texture layout, or which vertex factories and virtual samplers a material's shader map has: tools/re/AIRCRAFT_MATERIALS.md); `lua_check.py Scripts/*.lua` (Lua 5.4 syntax, each part's 200-local count, unknown globals across the parts together; there is no Lua on the build machine, run it after every Lua change) |
| `scripts/` | Zen package / property / container format libraries (`uprop.py`, `eprec.py`, `zen.py`, `chdr.py`, ...) |

Git Bash rewrites `/Game/...` arguments into Windows paths; `export MSYS_NO_PATHCONV=1` first (build_all.sh does).

## Format notes (found while building Milestone 1)
- A mission level's world settings import its MC, and the level imports every WD/EP (global + phases). The EP
  imports its WD and EF. Nothing is found by naming convention, so renamed copies must re-point these imports.
- Every export payload starts with 4 zero bytes before the unversioned property header. `uprop.read_struct` at
  offset 4 round-trips. At offset 0 it reads but writes back different bytes.
- An EP payload = properties, then u32 0, u32 trigger count, triggers, u32 exec count, execs. Empty EP = 12 zero bytes after the props.
- Public export hash = city64(UTF-16 lower-case object path), e.g. `mc_survivalmode`. Container id = city64(UTF-16 lower-case container name).
- `DT_Graphics_<Mission>` (PLDatas) is not imported by anything. The game must look it up by name.
- The game reads each .ucas compression block rounded up to 16 bytes (AES block size), even unencrypted. retoc pack-raw
  ends the .ucas right after the last block, so a last block that isn't a multiple of 16 is read past the end of the
  file and the whole container fails to mount (loader log: "Failed reading 576 bytes at offset 87823" for a 572-byte
  block). pack.py pads the .ucas and checks every block before staging. (Test 1, 2026-10-20.)
- No `<name>_P.pak` stub is needed next to the .utoc for the AC8 Mod Loader (Stonehenge's release ships none).
- UE4SS 3.0.1's Lua `LoadAsset` looks assets up in the game's asset registry, which never lists a mod's new packages,
  so it can't load them even when the container is mounted (Test 2, 2026-10-20). Load mod packages with
  KismetSystemLibrary MakeSoftObjectPath -> Conv_SoftObjPathToSoftObjRef -> LoadAsset_Blocking (as Stonehenge's DLL does).
- In unversioned properties an absent field means the class default, not zero/false. To set a field to false or 0,
  keep it as an explicit zero entry (uprop `(idx, name, True, None)`). Removing LiveUnitDesc.bIsSpawnFromStart
  (default true) spawned every unit in the world data (Milestone 2 probe, 2026-10-20).
