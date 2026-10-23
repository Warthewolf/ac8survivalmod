# AC8 Survival Mode

A round-based survival mode for **Ace Combat 8** (PC). Waves of enemy fighters grow bigger and sharper every round,
bombers raid Comona Airport, and special rounds bring bosses and set pieces. Between rounds you land at the airport
and spend the zollars you've earned on missiles, special weapons, flares, repairs and airfield defences.

Unofficial fan mod by **voidcallsreaper**. Issues and feedback: `@voidcallsreaper` on Discord.

## Features
- **Rounds that escalate:** more enemies each round, with pilots ranked from Rookie up to Reaper, and difficulty
  spikes along the way.
- **Named ace squadrons:** from round 16, each with its own airframes and callsigns.
- **Bomber raids:** they go for the airfield. Its health, repairs, and the AA guns and SAM sites you can build
  all matter.
- **The landing STORE:** buy ammunition, repairs and airfield defences between rounds.
- **Special rounds:**
  - **Comona Defense:** protect the EMBDIR shuttle through its countdown.
  - **The Anomaly:** MINDRIPPER and the control-inverting field.
  - **Amphibious Assault:** landing craft and BTRs heading for the runway.
  - **The Ladons:** KOT and MISHKA.
  - **The Alicorn:** the submarine carrier.
  - **AB.L..IN:** IFF: FATAL ERROR.
- **Difficulty presets** (Casual / Standard / Ace) and an editable `survival.ini`.
- **Optional Discord leaderboard:** `leaderboard/` holds a Cloudflare Worker.

## Playing it
Download a release zip and follow the `README.txt` inside it. You'll need UE4SS for Ace Combat 8 and the AC8 Mod
Loader. `release/README.txt` is the player guide that goes into every zip.

## Repository layout
| Path | What's there |
| --- | --- |
| `mod/UE4SS/AC8SurvivalMode/Scripts/main.lua` | The mod's runtime: rounds, the STORE, HUD, special rounds, leaderboard |
| `mod/UE4SS/AC8SurvivalMode/Scripts/ai/` | Survival's enemy behaviour scripts |
| `mod/UE4SS/AC8SurvivalMode/config/survival.default.ini` | Player settings (copied to `survival.ini` on first run) |
| `runtime/survival_rt.c` | The native UE4SS mod in plain C (menu hook, spawner, ammo, events, music, leaderboard upload) |
| `tools/build_survival.py`, `tools/survival_events.py` | Build Survival's game packages and event package from the game's own files |
| `tools/build_all.sh`, `tools/package_test.sh` | Build everything; make a release zip with test-only code stripped |
| `tools/re/` | Reverse-engineering notes on the game's systems |
| `leaderboard/` | The Discord leaderboard (Cloudflare Worker + D1) |
| `AGENTS.md`, `SURVIVAL_SPEC.md`, `BUILD_PLAN.md`, `MISSION_REFERENCE.md` | Project rules, the agreed design, the plan, the stock-mission reference |

## Building
See `tools/README.md`. In short: Python 3.8+, LLVM (clang + lld-link) for the native runtime, retoc and Oodle for
packing, and your own copy of the game. The build extracts what it needs from your game files into `build/stock/`
(never committed). Then:

```sh
tools/build_all.sh            # build/install/: the mod, ready to copy into the game
tools/package_test.sh 0.57.1  # build/release/: a release zip
```

No game assets are in this repository.

## Licence
All rights reserved; see `LICENSE`. The code is published for reference: please ask before reusing any of it.

ACE COMBAT is a trademark of Bandai Namco Entertainment Inc. This project isn't affiliated with or endorsed by
Bandai Namco.
