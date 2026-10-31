-- AC8 Survival Mode - runtime (UE4SS Lua half; the native half is dlls\main.dll)
-- main.lua: the controller (tools/lua_split.py; user, 2026-10-24: "split the runtime into modules with a smaller
-- central controller"). The runtime is in Scripts/sv_*.lua, run here in MODULES' order into this mod's own Lua
-- state (UE4SS gives each Lua mod its own): a name one part shares with the others is a global of that state, each
-- part's own helpers stay local to it. A part that fails to load stops the rest, as one file used to.
-- (Hard rule 23 counts locals per part now: python tools/checks/lua_check.py Scripts/*.lua checks them all.)
VERSION = "0.73.44"

local MODULES = {
    "sv_core",
    "sv_config",
    "sv_rows",
    "sv_ai",
    "sv_hud",
    "sv_sound",
    "sv_spawn",
    "sv_anomalies",
    "sv_rounds",
    "sv_ladon",
    "sv_leaderboard",
    "sv_alicorn",
    "sv_amphib",
    "sv_spaceport",                -- the Spaceport Assault and its retake (tools/re/SPACEPORT_ASSAULT.md)
    "sv_flights",
    "sv_shop",
    "sv_allies",
    "sv_tactical",
    "sv_stats",                    -- the behaviour roadmap's measurements and P6's learning layer (BEHAVIOUR_DIRECTOR.md)
    "sv_weaponlog",                -- what the enemies carry and fire, in the log (CFG.log.weapons)
    "sv_spweapons",                -- the enemies' special weapons fired (CFG.special.fire)
    "sv_tells",                    -- P3's tells (before sv_coop: it keeps SV_Event as it was unwrapped)
    "sv_director",                 -- P2's squad director (calls SV_Event by name at run time: sv_coop wraps it)
    "sv_menu",
    "sv_coop",
    "sv_down",                     -- co-op's revives and the spectator camera (after sv_coop: its messages and players)
    "sv_audit",                    -- the run's audits in the log: targets, pay, sync (after sv_coop: its addCredits wrap)
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
