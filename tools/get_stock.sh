#!/bin/sh
# get_stock.sh <game path suffix> ...   e.g. Maps/Ingame/Mission022/PL_Mission022.umap
# Pulls the stock zen package (ExportBundleData chunk) out of the game's Paks into build/stock/<same path>.
# The AES key is read from ACE8AircraftBuilder's settings.json so it never lands in this repo.
cd "$(dirname "$0")/.."
PAKS="E:/SteamLibrary/steamapps/common/ACE COMBAT 8/Game/Content/Paks"
KEY=$(python -I -c "import json;print(json.load(open(r'E:/ACE8AircraftBuilder/settings.json'))['aesKey'])")
[ -s build/scan/all_chunks.txt ] || { mkdir -p build/scan; tools/bin/retoc.exe -a "$KEY" list --path --package --size "$PAKS" > build/scan/all_chunks.txt; }
for p in "$@"; do
  line=$(grep -F "Live/Content/$p" build/scan/all_chunks.txt | grep ExportBundleData | head -1)
  [ -n "$line" ] || { echo "not found: $p"; continue; }
  id=$(echo "$line" | awk '{print $2}')
  mkdir -p "build/stock/$(dirname "$p")"
  tools/bin/retoc.exe -a "$KEY" get "$PAKS" "$id" "build/stock/$p" && echo "ok $p $(wc -c < "build/stock/$p")"
done
