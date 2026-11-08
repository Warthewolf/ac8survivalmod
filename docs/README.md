# Documentation index

Where to look. Project rules for the AI agents stay in `../AGENTS.md` (read first); the player guide is `../release/README.txt`.

## design/ — what we build
| File | Read it to know |
| --- | --- |
| `design/SURVIVAL_SPEC.md` | The user's confirmed design (menu flow, map, airfield health, enemy roles). Overrides the design thesis. |
| `design/MISSION_REFERENCE.md` | Which stock mission already uses the node/event a feature needs. Check before building. |
| `design/node_catalog.tsv` | All 349 event node types. |

## re/ — how the game works (reverse-engineering notes)
| Topic | Notes |
| --- | --- |
| Spawning and events | `SPAWN_SYSTEM`, `EVENT_NOTES`, `EVENTS_AIRCRAFT`, `SPECIAL_ROUNDS`, `UNIQUE_ACTIONS` |
| Enemy AI | `AI_BEHAVIOURS`, `BEHAVIOUR_GUIDE`, `BEHAVIOUR_SCRIPTS`, `BEHAVIOUR_NATIVE_LOGIC`, `BEHAVIOUR_NATIVE_MOVE`, `GAME_LUA`, `NPC_DATA` |
| Player state | `AMMO`, `KILLS_HEALTH_DEATH` |
| HUD, menus, shop | `HUD_LAYOUT`, `HUD_NOTES`, `MINIMAP_MARKERS`, `AIRFIELD_SHOP_UI`, `AIRFIELD_SUPPLY`, `UI_SHOP_SAVE`, `ECONOMY_REVIEW` |
| Audio, radio, look | `MUSIC_RADIO_CAMERA`, `RADIO_LOCALISATION`, `WEATHER_DAYNIGHT`, `HELIOS_VFX`, `AIRCRAFT_MATERIALS` |
| Bosses and ports | `ALICORN`, `VALKA` |
| Native runtime | `STONEHENGE_MAIN_DLL` |

The scripts that produced these notes (`exe.py`, `xrefs.py`, `sigfind.py`, `mksig.py`, ...) stay in `../tools/re/`.

## Test results and build history
There is no `tests/` folder: each build's notes and test results are in `../HISTORY.md`. A lesson a test confirms becomes a hard rule in `../AGENTS.md`.
