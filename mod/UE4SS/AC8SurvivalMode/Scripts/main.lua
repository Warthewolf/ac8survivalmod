-- AC8 Survival Mode - runtime (UE4SS Lua half; the native half is dlls\main.dll)
-- main.lua: the controller (tools/lua_split.py; user, 2026-10-24: "split the runtime into modules with a smaller
-- central controller"). The runtime is in Scripts/sv_*.lua, run here in MODULES' order into this mod's own Lua
-- state (UE4SS gives each Lua mod its own): a name one part shares with the others is a global of that state, each
-- part's own helpers stay local to it. A part that fails to load stops the rest, as one file used to.
-- (Hard rule 23 counts locals per part now: python tools/checks/lua_check.py Scripts/*.lua checks them all.)
VERSION = "0.74.64"

local MODULES = {
    "sv_core",
    "sv_config",
    "sv_config_specials",          -- (sv_config.lua's next piece: tools/lua_split_part.py)
    "sv_config_subs",              -- (sv_config.lua's next piece: config\subtitles.ini over CFG's lines, before CFG_DEFAULTS)
    "sv_config_ini",               -- (sv_config.lua's next piece: tools/lua_split_part.py)
    "sv_rows",
    "sv_ai",
    "sv_hud",
    "sv_subs",                     -- the subtitle strip and the results card: SUB.say (GONE FISHIN', THE FESTIVAL)
    "sv_sky",                      -- the sky Survival changes, the day-night arc's owner (docs/re/FISHING.md 5)
    "sv_sound",
    "sv_spawn",
    "sv_anomalies",
    "sv_anomalies_valka",          -- (sv_anomalies.lua's next piece: tools/lua_split_part.py)
    "sv_anomalies_dev",            -- (sv_anomalies.lua's next piece: tools/lua_split_part.py)
    "sv_rounds",
    "sv_ladon",
    "sv_leaderboard",
    "sv_alicorn",
    "sv_amphib",
    "sv_spaceport",                -- the Spaceport Assault and its retake (docs/re/SPACEPORT_ASSAULT.md)
    "sv_fishing",                  -- GONE FISHIN': the shoals and SAL's boat (docs/re/FISHING.md 1-4)
    "sv_festival",                 -- THE FESTIVAL: the cruise missiles and the siren (docs/re/FISHING.md 6)
    "sv_decoy",                    -- THE DECOY: the bait, the Spear UAVs' locks and the Tonitrus Spear (docs/re/DECOY.md)
    "sv_tanicorn",                 -- THE TANICORN's test mount, test builds only (docs/re/TANICORN.md)
    "sv_fleet",                    -- INVINCIBLE FLEET's tests, test builds only (docs/design/INVINCIBLE_FLEET_RISE_FORD.md)
    "sv_cine",                     -- THE TANACORN's rise cinematic and its director, test builds only (docs/re/CINEMATIC.md)
    "sv_flights",
    "sv_shop",
    "sv_music",                    -- the music player in Survival: every track unlocked, the game's other named ones added
    "sv_allies",
    "sv_tactical",
    "sv_stats",                    -- the behaviour roadmap's measurements and P6's learning layer (BEHAVIOUR_DIRECTOR.md)
    "sv_weaponlog",                -- what the enemies carry and fire, in the log (CFG.log.weapons)
    "sv_spweapons",                -- the enemies' special weapons fired (CFG.special.fire)
    "sv_tells",                    -- P3's tells (before sv_coop: it keeps SV_Event as it was unwrapped)
    "sv_director",                 -- P2's squad director (calls SV_Event by name at run time: sv_coop wraps it)
    "sv_escort",                   -- THE ESCORT and the ZFA-44 carriers (docs/re/ESCORT.md; before sv_coop: its logPlane wrap)
    "sv_escort_subs",              -- what CHARLENE, her KMG escorts and Comona say; the Anomalies' wait for her (2026-11-07)
    "sv_escort_laser",             -- the ZFA-44 carriers' anti-missile laser: its rows, its arm in the log, its kills (2026-11-07)
    "sv_escort_li",                -- AC7's LaserInterceptor on the ZFA-44s (runtime laser.c, tools/laser7; 2026-11-07)
    "sv_escort_dive",              -- the VAMPIRES' final dive: their Helios blast as the next round comes (2026-11-08)
    "sv_kaska",                    -- the Shuttle Launch round's intercepted channel: KASKA and his launch controller (2026-11-08)
    "sv_menu",
    "sv_coop",
    "sv_coop_joiner",              -- (sv_coop.lua's next piece: tools/lua_split_part.py)
    "sv_coop_planes",              -- (sv_coop.lua's next piece: tools/lua_split_part.py)
    "sv_coop_sync",                -- (sv_coop.lua's next piece: tools/lua_split_part.py)
    "sv_coop_migration",           -- (sv_coop.lua's next piece: tools/lua_split_part.py)
    "sv_down",                     -- co-op's revives and the spectator camera (after sv_coop: its messages and players)
    "sv_audit",                    -- the run's audits in the log: targets, pay, sync (after sv_coop: its addCredits wrap)
    "sv_zfa44",                    -- the ZFA-44's test T0 (docs/re/ZFA44.md; test code only: empty in every zip)
    "sv_main",
}

local DIR = debug.getinfo(1, "S").source:match("^@(.*[/\\])") or ""
-- each part read (io, as the ini is) and run as a chunk of its own named by its path, so debug.getinfo (SCRIPT_DIR)
-- and error lines point at the part
local function run(m)
    local path = DIR .. m .. ".lua"
    local f = io.open(path, "rb")
    if not f then return false, "not found: " .. path end
    local src = f:read("a")
    f:close()
    local chunk, err = load(src, "@" .. path, "t")
    if not chunk then return false, err end
    return pcall(chunk)
end
for _, m in ipairs(MODULES) do
    local ok, err = run(m)
    if not ok then
        print("[AC8SurvivalMode] " .. m .. ".lua failed to load: " .. tostring(err) .. "\n")
        error(err, 0)
    end
end
