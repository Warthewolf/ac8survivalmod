# AC8 Survival Mode

A round-based survival mode for **Ace Combat 8** (PC). Waves of enemy fighters grow bigger and sharper every round,
bombers raid Comona Airport, and special rounds bring bosses and set pieces. Between rounds you land at the airport
and spend the zollars you've earned on missiles, special weapons, flares, repairs and airfield defences.

Unofficial fan mod by **voidcallsreaper**. Issues and feedback: `@voidcallsreaper` on Discord.

## Features
- **Rounds that escalate:** more enemies each round, with pilots ranked from Rookie up to Reaper, difficulty spikes,
  and enemies that fly in roles (duellists, skirmishers, wolf packs) under a squad director.
- **Named ace squadrons:** from round 16, each with its own airframes, callsigns and moves.
- **Bomber raids:** they go for the airfield. Its health, repairs, and the AA guns and SAM sites you can build all
  matter.
- **The landing STORE:** buy ammunition, special weapons, flares, repairs, airfield defences, allied flights, tactical
  items (an airstrike, an ECM burst, a decoy) and the VAMPIRES' ZFA-44 carriers between rounds.
- **Co-op:** host or join over Steam with friends; everyone flies their own plane, and a downed player can be revived.
- **A day and a night:** after GONE FISHIN' the sun sets over Comona, a night of three rounds follows (stars, the moon,
  the airfield's lights), then the sun rises again.
- **A cast on the radio:** subtitles for SAL, Comona's tower and crew chief, CHARLENE and her KMG escorts, AUDREY and
  VALKA, and an intercepted Emblem Direct channel that was never meant for you.
- **Special rounds:** the first ones come on fixed rounds, then anything goes:
  - **Round 2, Shuttle Launch:** protect Emblem Direct's CORRIS shuttle through its countdown while War's jets attack.
  - **Round 6, THE ESCORT:** bring CHARLENE's B-1B and her four KMG escorts home to Comona and see them land.
  - **Round 9, GONE FISHIN':** SAL needs fish for the island's festival; shoot the shoals, weigh the haul.
  - **Round 15, THE FESTIVAL:** at sunset, Tu-160s and their fighters raid the festival with cruise missiles.
  - **After the festival, in any order:** The Anomaly (MINDRIPPER and its control-scrambling field), Amphibious
    Assault, the Ladons KOT and MISHKA, the Alicorn submarine carrier, AB.L..IN (IFF: FATAL ERROR), VALKA, the
    Spaceport Assault and its retake, and THE DECOY (the Tonitrus Spear).
- **Allies:** ships offshore, the airfield's defences and allied flights you can order around.
- **Difficulty presets** (Casual / Standard / Ace), Survival's own menu pages, and an editable `survival.ini`.
- **Optional Discord leaderboard:** `leaderboard/` holds a Cloudflare Worker; runs count only from registered builds.

## Playing it
Download a release zip and follow the `README.txt` inside it. You'll need UE4SS for Ace Combat 8 and the AC8 Mod
Loader. `release/README.txt` is the player guide that goes into every zip.

## Repository layout
| Path | What's there |
| --- | --- |
| `mod/UE4SS/AC8SurvivalMode/Scripts/` | The mod's runtime: `main.lua` runs the parts `sv_*.lua` (rounds, the STORE, HUD, co-op, special rounds, leaderboard) |
| `mod/UE4SS/AC8SurvivalMode/Scripts/ai/` | Survival's enemy behaviour scripts |
| `mod/UE4SS/AC8SurvivalMode/config/survival.default.ini` | Player settings (copied to `survival.ini` on first run) |
| `runtime/survival_rt.c` | The native UE4SS mod in plain C (menu hook, spawner, ammo, events, music, leaderboard upload), one translation unit with its parts #included: `survival_rt_game.c`, `coop.c`, `flight.c`, `survival_rt_lua.c` and theirs |
| `tools/build_survival.py`, `tools/survival_events.py` | Build Survival's game packages and event package from the game's own files |
| `tools/build_all.sh`, `tools/package_test.sh` | Build everything; make a release zip with test-only code stripped |
| `tools/re/` | Reverse-engineering notes on the game's systems |
| `leaderboard/` | The Discord leaderboard (Cloudflare Worker + D1) |
| `AGENTS.md`, `docs/design/SURVIVAL_SPEC.md`, `docs/design/MISSION_REFERENCE.md`, `HISTORY.md` | Project rules, the agreed design, the stock-mission reference, every build's notes |

## Building
See [CONTRIBUTING.md](CONTRIBUTING.md) for the whole setup, and `tools/README.md` for each tool. In short: Python
3.8+, LLVM (clang + lld-link) for the native runtime, retoc and Oodle for packing, and your own copy of the game. Your
machine's paths and the game's key go in a git-ignored `.env` (from `.env.example`). The build extracts what it needs
from your game files into `build/stock/` (never committed). Then:

```sh
python -I tools/env.py --init   # .env from .env.example; set AC8_DIR and the AES key in it
python -I tools/env.py --check  # "ready" when everything is found
tools/build_all.sh              # build/install/: the mod, ready to copy into the game
tools/package_test.sh 0.57.1    # build/release/: a release zip
```

No game assets are in this repository.

## Licence
All rights reserved; see `LICENSE`. The code is published for reference: please ask before reusing any of it.

ACE COMBAT is a trademark of Bandai Namco Entertainment Inc. This project isn't affiliated with or endorsed by
Bandai Namco.
