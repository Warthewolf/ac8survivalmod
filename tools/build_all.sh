#!/bin/sh
# build_all.sh : full Survival Mode build.
#   0. your machine's settings from .env (tools/env.sh; copy .env.example to .env: the game's folder, its AES key, LLVM)
#   1. pull the stock packages the builder copies from (the game and its AES key: AC8_DIR, AC8_AES_KEY in .env);
#      tools/menu_stock.py finds and pulls the main-menu page Survival's own menu pages copy (build/menu/stock.json)
#   2. build the native runtime (runtime/build.sh, LLVM) and generate mod/Content with build_survival.py
#   3. pack build/out/SurvivalMode_P.utoc/.ucas
#   4. stage the install folders:
#        build/install/SurvivalMode      -> ue4ss\Mods\IoStoreLoaderMod\SurvivalMode
#        build/install/AC8SurvivalMode   -> ue4ss\Mods\AC8SurvivalMode   (Lua runtime + dlls\main.dll)
set -e
cd "$(dirname "$0")/.."
. tools/env.sh                      # (.env: LLVM_BIN onto PATH for runtime/build.sh, the game's paths for get_stock.sh)
export MSYS_NO_PATHCONV=1
tools/get_stock.sh \
  Maps/Ingame/Mission022/PL_Mission022.umap \
  Maps/Ingame/Mission022/MC_Mission022.uasset \
  Maps/Ingame/Mission022/WD_Mission022_phase01.uasset \
  Maps/Ingame/Mission022/WD_Mission022_phase02.uasset \
  Maps/Ingame/Mission022/WD_Mission022_global.uasset \
  Maps/Ingame/Mission022/EF_Mission022_global.uasset \
  Maps/Ingame/Mission022/EP_Mission022_global.uasset \
  Maps/Ingame/Mission022/EP_Mission022_phase01.uasset \
  Maps/Ingame/Mission022/EP_Mission022_phase02.uasset \
  Datatables/Information/DT_LiveMissionTable.uasset \
  Datatables/UI/Menu/MainMenu/Top/DT_LiveMenuMainTopCommands.uasset \
  LuaSource/Chronicle/AI/LA_PursueTarget_0011.uasset \
  Datatables/AI/NPC/Mission/DT_NPC_Mission022.uasset \
  Datatables/AI/NPC/Mission/DT_NPC_Mission004.uasset Datatables/AI/NPC/Mission/DT_NPC_Mission013.uasset Datatables/AI/NPC/Mission/DT_NPC_Mission016.uasset Maps/Ingame/Mission016/WD_Mission016_global.uasset Maps/Ingame/Mission016/EP_Mission016_global.uasset OnlineMode/Maps/EmergencyCall/EB_002/WD_EB_002.uasset OnlineMode/Maps/EmergencyCall/EB_002/EP_EB_002.uasset OnlineMode/DataTables/AI/NPC/Mission/DT_NPC_Mission_EB_002_ON.uasset OnlineMode/DataTables/AI/NPC/DT_NPC_ON.uasset OnlineMode/DataTables/AI/NPC/DT_NPC_WeaponDurability_ON.uasset OnlineMode/DataTables/AI/NPC/DT_NPC_ExplosionDurability_ON.uasset Maps/Ingame/Mission013/WD_Mission013_global.uasset Maps/Ingame/Mission013/EP_Mission013_global.uasset \
  Datatables/AI/NPC/DT_NPC.uasset   Datatables/AI/NPC/Model/DT_NPC_Model.uasset   Datatables/Radio/DT_Rdo_ST_ms022.uasset \
  WwiseAssets/Database/DA_SoundDB_AKB_Voice.uasset \
  Maps/Ingame/Mission015/EP_Mission015_global.uasset \
  Maps/Ingame/Mission018/EP_Mission018_global.uasset \
  Maps/Ingame/MIssion006/EP_Mission006_global.uasset \
  Maps/Ingame/Training001/EP_Training001_global.uasset \
  Blueprints/Weapons/BP_FCS/CP/BP_FCS_Vessel_CIWS_00.uasset Blueprints/Weapons/BP_FCS/CP/BP_FCS_ECM_00.uasset Blueprints/Weapons/CIWS/Vessel/BP_wp_ciws_vessel.uasset Blueprints/Weapons/Laser/Tls/UAVN/BP_SwingTLS_ForMSL.uasset Maps/Ingame/Mission029/EP_Mission029_global.uasset Datatables/AI/NPC/FCS/DT_NPC_FCS.uasset \
  OnlineMode/DataTables/AI/NPC/DT_NPC_Model_ON.uasset \
  Datatables/Sound/DT_SoundMusicPlayerBGM.uasset OnlineMode/DataTables/Information/JukeBox/DT_JukeBoxMusic.uasset WwiseAssets/Database/DA_SoundDB_AKB_BGM_Campaign.uasset WwiseAssets/Database/DA_SoundDB_AKB_BGM_Online.uasset \
  Datatables/UI/Menu/IngameMenu/IngameHangar/DT_LiveMenuIngameHangarCommands.uasset   Datatables/UI/Menu/IngameMenu/IngameHangar/DA_LiveMenuIngameHangarSettings.uasset   Datatables/UI/Menu/IngameMenu/DT_IngameMenuSettingData.uasset   Blueprints/UI/Menu/Ingame/IngameHangar/WBP_Menu_IngameHangar_Confirmation_000.uasset
python -X utf8 -I tools/menu_stock.py   # Survival's menu pages: the stock main-menu page, its settings, the page tables
python -X utf8 -I tools/checks/menu_pages_test.py > /dev/null || { python -X utf8 -I tools/checks/menu_pages_test.py; exit 1; }
python -X utf8 -I tools/checks/lua_check.py mod/UE4SS/AC8SurvivalMode/Scripts/*.lua   # no Lua here: syntax check
python -X utf8 -I tools/checks/lua_check.py mod/UE4SS/AC8SurvivalMode/Scripts/ai/*.lua   # the behaviour scripts (packed)
python -X utf8 -I tools/checks/ini_check.py   # every survival.default.ini setting is one CFG has
python -X utf8 -I tools/subtitles.py check     # config/subtitles.ini: every line reads (sv_config_subs.lua), no mistake
python -X utf8 -I tools/checks/size_check.py  # no source file over 2,000 lines (CONTRIBUTING.md)
python -X utf8 -I tools/checks/paths_check.py  # no machine path in tools, runtime, mod, docs, AGENTS.md (.env instead)
# the native runtime's C suites that build and run on Windows and Linux alike (tools/llvm's clang, or clang on PATH; on
# Windows windowless), a few seconds in all: the formatter (hard rule 55), the liveness check, the spawner's unit table
# (lag-1), the UE4SS.log copy's filter (lag-8), the real planes' weapons, the co-op flag bits and DOWN's autopilot. A
# failure stops the build, its output shown. They are ordinary C programs: on Windows clang needs the MSVC / Windows SDK
# libs for them (runtime/build.sh doesn't), so where it can't build one (LLVM alone: CONTRIBUTING.md) they're skipped,
# said so. Not here: coop_test (~40 s, a dozen windows, fixed UDP ports), and safecall, pathguard, build_hash, logbundle
# (Windows only): sh tools/checks/run_all.sh runs them.
mkdir -p build/checks
t_cc=tools/llvm/LLVM/bin/clang.exe
[ -x "$t_cc" ] || t_cc=clang
printf '#include <stdio.h>\n#include <stdlib.h>\n#include <string.h>\nint main(void) { char* p = malloc(4); strcpy(p, "ok"); printf("%%s\\n", p); return 0; }\n' \
    > build/checks/hosted_probe.c
if "$t_cc" -O1 -o build/checks/hosted_probe.exe build/checks/hosted_probe.c > build/checks/hosted_probe.txt 2>&1; then
    for t in vfmt uobj unittab logdedup fwkind flight; do
        t_out=$(sh "tools/checks/${t}_test.sh" 2>&1) || { printf '%s\n' "$t_out"; echo "build_all: tools/checks/${t}_test.sh failed"; exit 1; }
    done
    echo "native checks passed: vfmt, uobj, unittab, logdedup, fwkind, flight (tools/checks/*_test.sh)"
else
    echo "native checks NOT run: $t_cc can't build an ordinary C program here (no MSVC / Windows SDK libs?" \
         "$(head -1 build/checks/hosted_probe.txt)); sh tools/checks/run_all.sh where it can"
fi
sh runtime/build.sh   # native runtime: build/runtime/main.dll
python -X utf8 -I tools/build_survival.py
python -X utf8 -I tools/pack.py
rm -rf build/install && mkdir -p build/install/SurvivalMode
cp build/out/SurvivalMode_P.utoc build/out/SurvivalMode_P.ucas build/install/SurvivalMode/
# VALKA's X-02S (AC7's model, cooked in UE 5.4 by tools/x02s/build.sh; no UE needed here): staged when built
if [ -f build/x02s/out/SurvivalMode_Valka_P.utoc ]; then
    cp build/x02s/out/SurvivalMode_Valka_P.utoc build/x02s/out/SurvivalMode_Valka_P.ucas build/install/SurvivalMode/
    echo "staged VALKA's X-02S (build/x02s/out/SurvivalMode_Valka_P)"
else
    echo "no VALKA X-02S container (tools/x02s/build.sh): she flies the x40a"
fi
# the ZFA-44 (the user's own model, cooked in UE 5.4 by tools/zfa44/build.sh; no UE needed here): the user's dev builds
# only, so staged with ZFA=1 only (package_dev.sh keeps it with ZFA=1; package_release.sh never ships it)
if [ "$ZFA" = 1 ]; then
    [ -f build/zfa44/out/SurvivalMode_ZFA44_P.utoc ] || { echo "ZFA=1: no ZFA-44 container (sh tools/zfa44/build.sh)"; exit 1; }
    cp build/zfa44/out/SurvivalMode_ZFA44_P.utoc build/zfa44/out/SurvivalMode_ZFA44_P.ucas build/install/SurvivalMode/
    echo "staged the ZFA-44 (build/zfa44/out/SurvivalMode_ZFA44_P; dev only)"
    # (2026-11-07) AC7's LaserInterceptor, the ZFA-44's weapon (tools/laser7: the user's AC7 exception of 2026-11-07)
    L7_MAIN=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)   # (the main tree, as release_dir.sh)
    if [ -n "$L7_MAIN" ]; then L7="$(dirname "$L7_MAIN")/build/laser7/out"; else L7=build/laser7/out; fi
    if [ -f "$L7/SurvivalMode_Laser7_P.utoc" ]; then
        cp "$L7/SurvivalMode_Laser7_P.utoc" "$L7/SurvivalMode_Laser7_P.ucas" build/install/SurvivalMode/
        echo "staged AC7's LaserInterceptor ($L7/SurvivalMode_Laser7_P)"
    else
        echo "no LaserInterceptor container (sh tools/laser7/build.sh): the ZFA-44s keep AC8's swing laser"
    fi
fi
# THE TANICORN's parts (tools/tanicorn: Survival's own blueprints on the Tanager stand-in, Sea Power's Iowa: the user's
# install only, 2026-11-09): staged with TANI=1 only (package_dev.sh keeps it with TANI=1; package_release.sh never ships it).
# (2026-11-11) TANI=1 also gives the world data THE TANACORN's live parts (tools/build_survival.py reads TANI: hard imports
# of this container): such a build is the user's dev install only (build/install/tani_wd.txt below)
if [ "$TANI" = 1 ]; then
    # (the main tree's build/tanicorn/out, where tools/tanicorn/build.sh writes it from any worktree: as L7 above)
    TA_MAIN=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)
    if [ -n "$TA_MAIN" ]; then TA="$(dirname "$TA_MAIN")/build/tanicorn/out"; else TA=build/tanicorn/out; fi
    [ -f "$TA/SurvivalMode_Tani_P.utoc" ] || { echo "TANI=1: no Tanicorn container in $TA (sh tools/tanicorn/build.sh)"; exit 1; }
    cp "$TA/SurvivalMode_Tani_P.utoc" "$TA/SurvivalMode_Tani_P.ucas" build/install/SurvivalMode/
    echo "staged the Tanicorn's parts ($TA/SurvivalMode_Tani_P; dev only)"
fi
# (2026-11-11, WP2 step 2) a TANI=1 build's world data imports the Tanicorn container's blueprints (THE TANACORN's live parts:
# tools/build_survival.py check_tanicorn_build writes build/out/tani_wd.txt): its marker staged beside the two mod folders
# (never zipped), so package_release.sh and package_test.sh refuse this build and package_dev.sh takes it with TANI=1 only
if [ -f build/out/tani_wd.txt ]; then
    [ "$TANI" = 1 ] || { echo "build/out/tani_wd.txt without TANI=1: the world data was built with TANI=1 (rerun)"; exit 1; }
    cp build/out/tani_wd.txt build/install/
    # ((2026-11-12, the weapons reviews) the container staged above is the one check_tanicorn_build checked: the same bytes,
    # every class the world data imports (tools/tani_container.py)
    python -I tools/tani_container.py verify build/install/SurvivalMode/SurvivalMode_Tani_P.utoc build/install/tani_wd.txt || exit 1
    echo "staged build/install/tani_wd.txt: this build's world data imports THE TANACORN's parts (TANI=1; dev installs only)"
fi
cp -r mod/UE4SS/AC8SurvivalMode build/install/
mkdir -p build/install/AC8SurvivalMode/dlls && cp build/runtime/main.dll build/install/AC8SurvivalMode/dlls/
# what the build found of the stock main-menu page (build_survival.py; Scripts/sv_menu.lua reads it): only with pages
if [ -f build/menu/sv_menu_stock.lua ]; then
    cp build/menu/sv_menu_stock.lua build/install/AC8SurvivalMode/Scripts/
    echo "staged Survival's menu pages' stock note (Scripts/sv_menu_stock.lua)"
else
    echo "no menu pages this build: the main menu has the flat Survival rows"
fi
# VALKA's railgun sounds (AC7's Mihaly EML, tools/ac7_sfx.py into build/ac7/sfx; never in git): staged when extracted,
# under the names CFG.sound.valka plays (Scripts/sv_config.lua)
SFX=build/ac7/sfx
if [ -f "$SFX/OBJ_M18_MIHAI_SHOT/shot_main_31813208.wav" ]; then
    SND=build/install/AC8SurvivalMode/Sounds/valka
    mkdir -p "$SND"
    while read -r src dst; do
        [ -n "$src" ] && cp "$SFX/$src" "$SND/$dst"
    done <<'LIST'
OBJ_M18_MIHAI_CHARGE/charge_start_873196140.wav charge_start.wav
OBJ_M18_MIHAI_CHARGE/charge_loop_802788028.wav charge_loop.wav
OBJ_M18_MIHAI_CHARGE_END/charge_end_1049060902.wav charge_end.wav
OBJ_M18_MIHAI_SHOT/shot_main_31813208.wav shot_main.wav
OBJ_M18_MIHAI_SHOT/shot_eml_818050031.wav shot_eml_1.wav
OBJ_M18_MIHAI_SHOT/shot_eml_933073312.wav shot_eml_2.wav
OBJ_M18_MIHAI_SHOT/shot_eml_1028805951.wav shot_eml_3.wav
OBJ_M18_MIHAI_SHOT/shot_far_922483504.wav shot_far.wav
OBJ_M18_MIHAI_SHOT/shot_whoosh_323018131.wav whoosh_1.wav
OBJ_M18_MIHAI_SHOT/shot_whoosh_813321654.wav whoosh_2.wav
OBJ_M18_MIHAI_SHOT/shot_whoosh_723610663.wav whoosh_3.wav
OBJ_M18_MIHAI_SHOT/shot_whoosh_656975517.wav whoosh_4.wav
LIST
    echo "staged VALKA's railgun sounds ($(ls "$SND" | wc -l) in AC8SurvivalMode/Sounds/valka)"
else
    echo "no AC7 railgun sounds (python -I tools/ac7_sfx.py): VALKA plays AC8's own"
fi
echo "staged build/install/SurvivalMode and build/install/AC8SurvivalMode"
