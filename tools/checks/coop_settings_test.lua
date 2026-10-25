-- coop_settings_test.lua <mod dir> <work dir> <role: host|join> (run by tools/checks/coop_settings_test.sh): Survival
-- COOP's settings sync (sv_coop.lua M.sendSettings / onSettings / restoreMine), the main menu's settings rows
-- (M.stepSetting, iniSet) and the co-op enemy scaling (COOP.more), on the real sv_config.lua and sv_coop.lua (M exposed
-- for the test) with a survival.ini of the role's own. host: writes its settings messages and its synced CFG to <work>;
-- join: applies the host's messages and checks the result. <work>/<role>/Scripts and /config must exist.
local MOD, WORK, ROLE = arg[1], arg[2], arg[3]
local fails = 0
local function check(ok, what) if ok then print("  ok   " .. what) else print("  FAIL " .. what); fails = fails + 1 end end
local function readAll(p) local f = assert(io.open(p, "rb")); local s = f:read("a"); f:close(); return s end
local function writeAll(p, s) local f = assert(io.open(p, "wb")); f:write(s); f:close() end

-- the game's world, stubbed
local logs = {}
function log(s) logs[#logs + 1] = s end
function print2(s) io.stdout:write(s .. "\n") end
VERSION = "0.70.6-coop.9"
SCRIPT_DIR = WORK .. "/" .. ROLE .. "/Scripts/"
KILL, LB = { side = function() end }, { send = function() end }
local sent = {}
function SV_CoopSend(msg, rel, to) sent[#sent + 1] = msg; return 1 end
local texts = {}
function SV_SetText(k, v) texts[k] = v; return 1 end
function FindAllOf() return {} end
function FindFirstOf() return nil end
function liveWidget() return false end
function toText(s) return s end
function myAirframe() return "f16c" end

-- the role's survival.ini: the shipped one with a few edits
local default = readAll(MOD .. "/config/survival.default.ini")
writeAll(WORK .. "/" .. ROLE .. "/config/survival.default.ini", default)
local ini = default
local function set(sec, key, val)        -- (switch the shipped line on with a value)
    local s0 = assert(ini:find("\n[" .. sec .. "]", 1, true), sec)
    local a, b = ini:find("\n;" .. key .. " *=[^\n]*", s0)
    assert(a, sec .. "/" .. key)
    ini = ini:sub(1, a) .. key .. " = " .. val .. ini:sub(b + 1)
end
if ROLE == "host" then
    set("rounds", "start_round", "5")
    set("rounds", "aircraft", "f16c_common, su47_common")
    set("waves", "next_at", "6")
    set("coop", "name", "WarHost")
else
    set("rounds", "max_aircraft", "99")              -- (a joiner's own edits: gone while they play the host's game)
    set("zollars", "fighter", "100000")
    set("coop", "name", "Cress")
end
writeAll(WORK .. "/" .. ROLE .. "/config/survival.ini", ini)

-- load the real parts (sv_coop with its M exposed)
dofile(MOD .. "/Scripts/sv_config.lua")
local src = readAll(MOD .. "/Scripts/sv_coop.lua"):gsub("\nlocal M = {", "\nM = {", 1)
assert(load(src, "=sv_coop.lua"))()
local M = _G.M
check(type(M) == "table" and type(M.sendSettings) == "function", "sv_coop.lua loaded, M exposed")
check(type(CFG_DEFAULTS) == "table" and CFG_DEFAULTS ~= CFG, "CFG_DEFAULTS snapshot")

-- a deterministic dump of a value (sorted keys) for comparisons
local function dump(v)
    if type(v) ~= "table" then return type(v) .. ":" .. tostring(v) .. (math.type(v) or "") end
    local keys = {}
    for k in pairs(v) do if type(v[k]) ~= "function" then keys[#keys + 1] = k end end
    table.sort(keys, function(a, b) return tostring(type(a)) .. tostring(a) < tostring(type(b)) .. tostring(b) end)
    local out = {}
    for _, k in ipairs(keys) do out[#out + 1] = dump(k) .. "=" .. dump(v[k]) end
    return "{" .. table.concat(out, ",") .. "}"
end
local PERSONAL = { coop = true, hud = true, sound = true, music = true, leaderboard = true, probe = true, ai_watch = true }
local function syncedDump()
    local keys = {}
    for k in pairs(CFG) do if not PERSONAL[k] then keys[#keys + 1] = k end end
    table.sort(keys)
    local out = {}
    for _, k in ipairs(keys) do out[#out + 1] = k .. "=" .. dump(CFG[k]) end
    return table.concat(out, "\n")
end
local function split(s) local t = {}; for f in (s .. "|"):gmatch("([^|]*)|") do t[#t + 1] = f end; return t end

if ROLE == "host" then
    check(CFG.start_round == 5 and math.type(CFG.start_round) == "integer", "host: its ini read (start_round 5)")
    COOP.open, COOP.role = true, "host"
    M.sendSettings(1)
    check(#sent >= 1 and sent[1]:match("^cf|1|%d+|"), "host: settings sent as cf chunks (" .. #sent .. ")")
    for _, m in ipairs(sent) do check(not m:find("|", #m:match("^cf|%d+|%d+|") + 1, true), "host: no | inside a chunk") end
    writeAll(WORK .. "/messages.txt", table.concat(sent, "\n"))
    writeAll(WORK .. "/host_synced.txt", syncedDump())
    -- co-op scaling: 4 players in the room
    M.roster = { [0] = {}, [1] = {}, [2] = {}, [3] = {} }
    check(COOP.more(20, "max_aircraft") == 29, "host: 4 players, 20 aircraft -> 29 (" .. tostring(COOP.more(20, "max_aircraft")) .. ")")
    check(COOP.more(50, "max_aircraft") == 60, "host: capped at max_aircraft 60")
    check(COOP.more(18, "max_up") == 26, "host: 4 players, wave of 18 -> 26")
    M.roster = { [0] = {} }
    check(COOP.more(20, "max_aircraft") == 20, "host: alone, unchanged")
else
    local mineBefore = syncedDump()
    local waves, aircraft = CFG.waves, CFG.aircraft
    check(CFG.max_aircraft == 99 and CFG.credits.fighter == 100000, "join: its own edits read")
    COOP.open, COOP.role = true, "join"
    for line in readAll(WORK .. "/messages.txt"):gmatch("[^\n]+") do M.onSettings(split(line)) end
    local host = readAll(WORK .. "/host_synced.txt")
    local got = syncedDump()
    check(got == host, "join: every shared setting equals the host's")
    if got ~= host then
        local a, b = {}, {}
        for l in host:gmatch("[^\n]+") do a[l:match("^[^=]+")] = l end
        for l in got:gmatch("[^\n]+") do b[l:match("^[^=]+")] = l end
        for k, l in pairs(a) do if b[k] ~= l then print2("    differs: " .. k) end end
    end
    check(CFG.start_round == 5 and CFG.max_aircraft == 30 and CFG.credits.fighter ~= 100000, "join: host's start_round 5, the shipped max_aircraft, no 100000 a kill")
    check(CFG.waves == waves and CFG.waves.next_at == 6, "join: CFG.waves is the same table, host's next_at 6")
    check(CFG.aircraft == aircraft and #CFG.aircraft == 2 and CFG.aircraft[2] == "su47_common", "join: the aircraft list in place, the host's 2")
    check(CFG.coop.name == "Cress", "join: [coop] stays its own")
    check(texts["SV_Menu_SetStartTitle"] == "START AT ROUND 1", "join: the START row shows its own setting (" .. tostring(texts["SV_Menu_SetStartTitle"]) .. ")")
    -- a settings row pressed while playing with the host's: its own value, saved; CFG keeps the host's
    M.stepSetting("Start")
    check(CFG.start_round == 5 and M.ownRoot().start_round == 5, "join: START pressed: its own 1 -> 5, CFG still the host's 5")
    M.stepSetting("Break")
    check(texts["SV_Menu_SetBreakTitle"] == "BREAK BETWEEN ROUNDS: 30 S", "join: BREAK 20 -> 30 (" .. tostring(texts["SV_Menu_SetBreakTitle"]) .. ")")
    M.stepSetting("Room")
    check(CFG.coop.max_players == 2, "join: ROOM 24 -> 2 (wraps)")
    M.stepSetting("Enemies")
    check(CFG.coop.aircraft_per_player == 0.25, "join: ENEMIES 0.15 -> 0.25")
    local f = readAll(WORK .. "/join/config/survival.ini"):gsub("\r\n", "\n")
    check(f:find("\nstart_round = 5\n", 1, true) and f:find("\nintermission_s = 30\n", 1, true) and f:find("\nmax_players = 2\n", 1, true)
          and f:find("\naircraft_per_player = 0.25\n", 1, true), "join: the four saved to survival.ini")
    check(not f:find("\n;start_round", 1, true), "join: start_round's switched-off line replaced, not added twice")
    -- co-op closes: its own back (its edits, and the rows' new values)
    M.restoreMine()
    check(CFG.max_aircraft == 99 and CFG.credits.fighter == 100000 and CFG.start_round == 5 and CFG.intermission_s == 30,
          "join: own settings back (99, 100000, start 5, break 30)")
    check(CFG.waves == waves and CFG.waves.next_at == 4, "join: CFG.waves the same table, own next_at 4")
    -- the saved file reads back the same
    dofile(MOD .. "/Scripts/sv_config.lua")
    check(CFG.start_round == 5 and CFG.intermission_s == 30 and CFG.coop.max_players == 2, "join: survival.ini read again: the saved values")
    print2("  (log: " .. #logs .. " lines; last: " .. tostring(logs[#logs]) .. ")")
end
print2(fails == 0 and (ROLE .. ": all passed") or (ROLE .. ": " .. fails .. " FAILED"))
os.exit(fails == 0 and 0 or 1)
