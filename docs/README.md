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
| Enemy AI | `ENEMY_MISSILES`, `AI_BEHAVIOURS`, `BEHAVIOUR_DIRECTOR`, `BEHAVIOUR_GUIDE`, `BEHAVIOUR_SCRIPTS`, `BEHAVIOUR_NATIVE_LOGIC`, `BEHAVIOUR_NATIVE_MOVE`, `GAME_LUA`, `NPC_DATA` |
| Player state | `AMMO`, `KILLS_HEALTH_DEATH` |
| HUD, menus, shop | `HUD_LAYOUT`, `HUD_NOTES`, `MINIMAP_MARKERS`, `MENU_PAGES`, `AIRFIELD_SHOP_UI`, `AIRFIELD_SUPPLY`, `UI_SHOP_SAVE`, `STORE_FREEZE`, `ECONOMY_REVIEW` |
| Co-op | `COOP`, `COOP2MP` |
| Map, sky, night | `COMONA_MAP`, `WEATHER_DAYNIGHT`, `NIGHT_SKY`, `NIGHT_SEA_LIGHTS` |
| Audio, radio, look | `MUSIC_RADIO_CAMERA`, `MUSIC_BANKS`, `RADIO_LOCALISATION`, `HELIOS_VFX`, `AIRCRAFT_MATERIALS`, `FALKEN_MATERIALS` |
| Special rounds | `SPACEPORT_ASSAULT`, `ESCORT`, `DECOY`, `FISHING` (also the day-night arc and THE FESTIVAL), `THUNDER` |
| Bosses and ports | `ALICORN`, `VALKA`, `ZFA44`, `LASER_INTERCEPTOR`, `TANICORN` (our own ship boss: assembly, moving parts, weapon mounts, build plan) |
| Native runtime | `STONEHENGE_MAIN_DLL` |

The scripts that produced these notes (`exe.py`, `xrefs.py`, `sigfind.py`, `mksig.py`, ...) stay in `../tools/re/`.

## Test results and build history
There is no `tests/` folder: each build's notes and test results are in `../HISTORY.md` (entries written before the move name these notes under their old path, `tools/re/`). A lesson a test confirms becomes a hard rule in `../AGENTS.md`.
