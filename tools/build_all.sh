#!/bin/sh
# build_all.sh : full Survival Mode build.
#   1. pull the stock packages the builder copies from (needs the game + the AES key in ACE8AircraftBuilder's settings);
#      tools/menu_stock.py finds and pulls the main-menu page Survival's own menu pages copy (build/menu/stock.json)
#   2. build the native runtime (runtime/build.sh, LLVM) and generate mod/Content with build_survival.py
#   3. pack build/out/SurvivalMode_P.utoc/.ucas
#   4. stage the install folders:
#        build/install/SurvivalMode      -> ue4ss\Mods\IoStoreLoaderMod\SurvivalMode
#        build/install/AC8SurvivalMode   -> ue4ss\Mods\AC8SurvivalMode   (Lua runtime + dlls\main.dll)
set -e
cd "$(dirname "$0")/.."
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
  Datatables/AI/NPC/DT_NPC.uasset   Datatables/Radio/DT_Rdo_ST_ms022.uasset \
  WwiseAssets/Database/DA_SoundDB_AKB_Voice.uasset \
  Maps/Ingame/Mission015/EP_Mission015_global.uasset \
  Maps/Ingame/Mission018/EP_Mission018_global.uasset \
  Maps/Ingame/MIssion006/EP_Mission006_global.uasset \
  Maps/Ingame/Training001/EP_Training001_global.uasset \
  OnlineMode/DataTables/AI/NPC/DT_NPC_Model_ON.uasset \
  Datatables/UI/Menu/IngameMenu/IngameHangar/DT_LiveMenuIngameHangarCommands.uasset   Datatables/UI/Menu/IngameMenu/IngameHangar/DA_LiveMenuIngameHangarSettings.uasset   Datatables/UI/Menu/IngameMenu/DT_IngameMenuSettingData.uasset   Blueprints/UI/Menu/Ingame/IngameHangar/WBP_Menu_IngameHangar_Confirmation_000.uasset
python -X utf8 -I tools/menu_stock.py   # Survival's menu pages: the stock main-menu page, its settings, the page tables
python -X utf8 -I tools/checks/menu_pages_test.py > /dev/null || { python -X utf8 -I tools/checks/menu_pages_test.py; exit 1; }
python -X utf8 -I tools/checks/lua_check.py mod/UE4SS/AC8SurvivalMode/Scripts/*.lua   # no Lua here: syntax check
python -X utf8 -I tools/checks/lua_check.py mod/UE4SS/AC8SurvivalMode/Scripts/ai/*.lua   # the behaviour scripts (packed)
python -X utf8 -I tools/checks/ini_check.py   # every survival.default.ini setting is one CFG has
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
