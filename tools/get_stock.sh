#!/bin/sh
# get_stock.sh <game path suffix> ...   e.g. Maps/Ingame/Mission022/PL_Mission022.umap
# Pulls the stock zen package (ExportBundleData chunk) out of the game's Paks into build/stock/<same path>.
# The game's folder and AES key come from .env (AC8_DIR or AC8_PAKS; AC8_AES_KEY or AC8_AES_SETTINGS: .env.example),
# so neither lands in this repo.
cd "$(dirname "$0")/.."
. tools/env.sh
sv_need AC8_PAKS "the game's Paks folder: set AC8_DIR, ACE COMBAT 8's install folder"
PAKS=$AC8_PAKS
KEY=$(python -I tools/env.py --aes-key) || exit 2
[ -s build/scan/all_chunks.txt ] || { mkdir -p build/scan; tools/bin/retoc.exe -a "$KEY" list --path --package --size "$PAKS" > build/scan/all_chunks.txt; }
for p in "$@"; do
  line=$(grep -F "Live/Content/$p" build/scan/all_chunks.txt | grep ExportBundleData | head -1)
  [ -n "$line" ] || { echo "not found: $p"; continue; }
  id=$(echo "$line" | awk '{print $2}')
  mkdir -p "build/stock/$(dirname "$p")"
  tools/bin/retoc.exe -a "$KEY" get "$PAKS" "$id" "build/stock/$p" && echo "ok $p $(wc -c < "build/stock/$p")"
done
