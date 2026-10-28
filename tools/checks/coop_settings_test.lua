-- coop_settings_test.lua <mod dir> <work dir> <role: host|join|guard> (run by tools/checks/coop_settings_test.sh): Survival
-- COOP's settings sync (sv_coop.lua M.sendSettings / onSettings / restoreMine), the main menu's settings rows
-- (sv_menu.lua's, iniSet) and the co-op enemy scaling (COOP.more), on the real sv_config.lua, sv_menu.lua and sv_coop.lua (M exposed
-- for the test) with a survival.ini of the role's own. host: writes its settings messages and its synced CFG to <work>;
-- join: applies the host's messages and checks the result. guard: a joiner fed what a broken or hostile game could
-- send (bad settings, slots, credits, poses, texts) and the main menu's picks. <work>/<role>/Scripts and /config must
-- exist.
local MOD, WORK, ROLE = arg[1], arg[2], arg[3]
local fails = 0
local function check(ok, what) if ok then print("  ok   " .. what) else print("  FAIL " .. what); fails = fails + 1 end end
local function readAll(p) local f = assert(io.open(p, "rb")); local s = f:read("a"); f:close(); return s end
local function writeAll(p, s) local f = assert(io.open(p, "wb")); f:write(s); f:close() end
do                                    -- (the runtime's paths are Windows ones: SCRIPT_DIR .. "..\\config\\")
    local rawOpen = io.open
    io.open = function(p, m) return rawOpen((tostring(p):gsub("\\", "/")), m) end
end

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
function valid(o) return o ~= nil end
function nameOf() return "?" end
function addrOf() return nil end
local callouts, credits = {}, {}
function hudCallout(t) callouts[#callouts + 1] = tostring(t) end
function addCredits(n) credits[#credits + 1] = n end
SV_ERR = {}
local KNOWN_ROWS = { f16c_common = true }
function loadObject() return {} end
function dtCall(_, _, row) return true, KNOWN_ROWS[row] and {} or nil end

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
assert(load(readAll(MOD .. "/Scripts/sv_menu.lua"), "=sv_menu.lua"))()
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
    check(COOP.more(50, "max_aircraft") == 73, "host: 4 players, 50 aircraft -> 73 (under max_aircraft 80)")
    check(COOP.more(60, "max_aircraft") == 80, "host: 4 players, round 35's 60 -> capped at max_aircraft 80")
    check(COOP.more(30, "max_up") == 30, "host: the Ace preset's late 30 up at once stays 30 (max_up 30)")
    check(COOP.more(18, "max_up") == 26, "host: 4 players, wave of 18 -> 26")
    M.roster = { [0] = {} }
    check(COOP.more(20, "max_aircraft") == 20, "host: alone, unchanged")
elseif ROLE == "join" then
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
    -- the menu's settings rows pressed while playing with the host's (COOP JOIN picked): its own setup and co-op
    -- settings change and are saved; CFG keeps the host's
    local q = {}
    function SV_MenuSetting() return table.remove(q, 1) or "" end
    local function menuPress(n) q[#q + 1] = "SV_Set_" .. n; MENU.tick(1) end
    MENU.mode = "join"
    local hostStart = CFG.setup.host.start_round
    menuPress("StartRound"); menuPress("Break"); menuPress("Room"); menuPress("CoopEnemies")
    check(CFG.setup.host.start_round == hostStart and M.ownRoot().setup.host.start_round == 5,
          "join: START AT ROUND pressed: its own 1 -> 5, CFG still the host's")
    check(M.ownRoot().setup.host.break_s == 30, "join: BREAK 20 -> 30 (its own)")
    check(texts["SV_Pg_Host_Room"] == "CO-OP ROOM: 2 PLAYERS", "join: CO-OP ROOM 24 -> 2 (wraps; " .. tostring(texts["SV_Pg_Host_Room"]) .. ")")
    check(CFG.coop.max_players == 2 and CFG.coop.aircraft_per_player == 0.25, "join: CO-OP ENEMIES 0.15 -> 0.25")
    local f = readAll(WORK .. "/join/config/survival.ini"):gsub("\r\n", "\n")
    check(f:find("\nstart_round = 5\n", 1, true) and f:find("\nbreak_s = 30\n", 1, true) and f:find("\nmax_players = 2\n", 1, true)
          and f:find("\naircraft_per_player = 0.25\n", 1, true), "join: the four saved to survival.ini")
    check(f:find("[setup.host]", 1, true), "join: the setup's under [setup.host]")
    -- co-op closes: its own back (its edits, and the rows' new values)
    M.restoreMine()
    check(CFG.max_aircraft == 99 and CFG.credits.fighter == 100000 and CFG.setup.host.start_round == 5 and CFG.setup.host.break_s == 30,
          "join: own settings back (99, 100000, start 5, break 30)")
    check(CFG.waves == waves and CFG.waves.next_at == 4, "join: CFG.waves the same table, own next_at 4")
    -- the saved file reads back the same
    dofile(MOD .. "/Scripts/sv_config.lua")
    check(CFG.setup.host.start_round == 5 and CFG.setup.host.break_s == 30 and CFG.coop.max_players == 2, "join: survival.ini read again: the saved values")
    print2("  (log: " .. #logs .. " lines; last: " .. tostring(logs[#logs]) .. ")")
else                                             -- guard
    -- the main menu's picks (SV_MenuChoice: the entry + 16 x the picks so far)
    CFG.coop.enabled = true
    local menu, opens, closes, openResult, inbox = 0, 0, 0, 1, {}
    function SV_MenuChoice() return menu end
    function SV_MenuSetting() return "" end
    function SV_CoopOpen() opens = opens + 1; return openResult end
    function SV_CoopClose() closes = closes + 1 end
    function SV_CoopRecv() return table.remove(inbox, 1) or "" end
    function SV_CoopInfo() return "open=1;state=linked;peers=0/linked/40/10/host" end
    local function tick() COOP.tick(0) end
    tick(); check(not COOP.open and opens == 0, "menu: nothing picked: co-op closed")
    menu = 16 + 3; tick(); check(COOP.open and COOP.role == "host" and opens == 1, "menu: HOST picked: hosting")
    menu = 32 + 3; tick(); check(COOP.open and opens == 1 and closes == 0, "menu: HOST picked again: still hosting, links kept")
    menu = 48 + 0; tick(); check(not COOP.open and closes == 1, "menu: another entry picked: co-op closed")
    openResult, menu = -2, 64 + 4; tick(); check(not COOP.open, "menu: JOIN picked, Steam not ready: not open")
    openResult, menu = 1, 80 + 4; tick(); check(COOP.open and COOP.role == "join", "menu: JOIN picked again: open (a retry)")
    -- what a broken or hostile host could send
    local function enc(v, out)
        local t = type(v)
        if t == "table" then
            out[#out + 1] = "{"
            for k, x in pairs(v) do enc(k, out); enc(x, out) end
            out[#out + 1] = "}"
        elseif t == "string" then out[#out + 1] = "s" .. v:gsub("[%%,{}|%c]", function(c) return string.format("%%%02X", c:byte()) end)
        elseif t == "number" then out[#out + 1] = math.type(v) == "integer" and ("i" .. v) or string.format("n%.17g", v)
        elseif t == "boolean" then out[#out + 1] = v and "T" or "F" end
    end
    local tk = {}
    enc({ ver = "x", preset = "ace", pdiff = 5, max = 999, diff = {
        { { "start_round" }, "five" },                       -- a type that doesn't fit
        { { "intermission_s" }, 1e12 },                     -- far past the shipped size
        { { "max_aircraft" }, 45 },                         -- fine
        { { "no_such_setting" }, 1 },                       -- not in this build
        { { "pool" }, { "SV_Evil" } },                      -- build data
        { { "airfield", "bombers", "pool" }, { "SV_Evil" } },
        { { "waves", "next_at" } },                         -- a removal
        { { "coop", "name" }, "Evil" },                     -- personal
        { { "aircraft" }, { "f16c_common", 5 } },           -- a list item of another type
        { { "credits", "fighter" }, 250 },                  -- fine
    } }, tk)
    inbox = { "0|cf|1|1|" .. table.concat(tk, ","),
              "0|pi|99|f16c_common|v|SlotTooHigh", "0|pi|2|bogus_row|" .. string.rep("V", 80) .. "|" .. string.rep("N", 300),
              "0|cr|1000000000000|bonus", "0|cr|500|bonus", "0|co|" .. string.rep("X", 500) .. "||0",
              "0|sp|SV_Unit_X|1e300,0,0,0|-|-1|1", "0|sp|SV_Unit_Y|100,200,300,90|-|-1|2" }
    tick()
    check(CFG.max_aircraft == 45 and CFG.credits.fighter == 250, "guard: the fitting settings applied")
    check(CFG.start_round == 1 and CFG.intermission_s == CFG_DEFAULTS.intermission_s and CFG.waves.next_at == CFG_DEFAULTS.waves.next_at,
          "guard: wrong type, oversized and removed settings skipped (shipped values)")
    check(CFG.no_such_setting == nil and CFG.pool[1] ~= "SV_Evil" and CFG.airfield.bombers.pool[1] ~= "SV_Evil", "guard: unknown and build-data paths skipped")
    check(CFG.coop.name ~= "Evil" and #CFG.aircraft == #CFG_DEFAULTS.aircraft, "guard: personal and mistyped lists skipped")
    check(presetName() == "ace" and select(2, presetName()) == 5, "guard: the host's preset and difficulty number")
    check(M.hostMax == nil, "guard: an impossible room size (999) ignored")
    check(M.roster[99] == nil, "guard: a slot past 24 ignored")
    check(M.roster[2] and #M.roster[2].name == 32 and #M.roster[2].ver == 32, "guard: a name and version cut to 32")
    check(#credits == 1 and credits[1] == 500, "guard: 10^12 zollars refused, 500 paid")
    local longest = 0
    for _, c in ipairs(callouts) do longest = math.max(longest, #c) end
    check(longest <= 120, "guard: a callout cut to 120 characters (" .. longest .. ")")
    local q1, q2 = M.spawnQ[1], M.spawnQ[2]
    check(q1 and q1.pose == nil and q2 and q2.pose and q2.pose[1] == 100, "guard: a spawn at 1e300 has no pose, a normal one keeps it")
end
print2(fails == 0 and (ROLE .. ": all passed") or (ROLE .. ": " .. fails .. " FAILED"))
os.exit(fails == 0 and 0 or 1)
