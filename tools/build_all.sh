#!/bin/sh
# build_all.sh : full Survival Mode build.
#   1. pull the stock packages the builder copies from (needs the game + the AES key in ACE8AircraftBuilder's settings)
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
  Datatables/AI/NPC/Mission/DT_NPC_Mission022.uasset
python -X utf8 -I tools/checks/lua_check.py mod/UE4SS/AC8SurvivalMode/Scripts/*.lua   # no Lua here: syntax check
sh runtime/build.sh   # native runtime: build/runtime/main.dll
python -X utf8 -I tools/build_survival.py
python -X utf8 -I tools/pack.py
rm -rf build/install && mkdir -p build/install/SurvivalMode
cp build/out/SurvivalMode_P.utoc build/out/SurvivalMode_P.ucas build/install/SurvivalMode/
cp -r mod/UE4SS/AC8SurvivalMode build/install/
mkdir -p build/install/AC8SurvivalMode/dlls && cp build/runtime/main.dll build/install/AC8SurvivalMode/dlls/
echo "staged build/install/SurvivalMode and build/install/AC8SurvivalMode"
