-- menu_test.lua <mod dir> <work dir> (run by tools/checks/menu_test.sh): Survival's menu pages and run setups
-- (Scripts/sv_menu.lua) on the real sv_config.lua, sv_menu.lua and sv_coop.lua, with the game stubbed: the texts of
-- every page row, the settings rows pressed in each mode (the values they step through, survival.ini), the rules a run
-- plays with (SETUP.*), the leaderboard's ranked check, the preset over the difficulty's, the main menu's mode picks
-- (SV_MenuChoice) and co-op opening / closing on them, and a joiner playing the host's setup. <work>/Scripts and
-- <work>/config must exist.
local MOD, WORK = arg[1], arg[2]
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
VERSION = "0.71.0"
SCRIPT_DIR = WORK .. "/Scripts/"
local rawSends = 0
KILL, LB = { side = function() end }, { send = function(sh) rawSends = rawSends + 1 end }
function SV_CoopSend() return 1 end
local texts = {}
function SV_SetText(k, v) texts[k] = v; return 1 end
function FindAllOf() return {} end
function FindFirstOf() return nil end
function NotifyOnNewObject() end
function liveWidget() return false end
function toText(s) return s end
function myAirframe() return "f16c" end
function valid(o) return o ~= nil end
function nameOf() return "?" end
function addrOf() return nil end
function hudCallout() end
function addCredits() end
function pin() return true end
function rowNames() return "" end
SV_ERR = {}
function loadObject() return nil, "stub" end
function dtCall() return true, nil end
local choice, queue, quick = 0, {}, nil
function SV_MenuChoice() return choice end
function SV_MenuSetting() return table.remove(queue, 1) or "" end
function SV_MenuQuick(q) quick = q; return 1 end
local opens, closes = 0, 0
function SV_CoopOpen() opens = opens + 1; return 1 end
function SV_CoopClose() closes = closes + 1 end
function SV_CoopRecv() return "" end
function SV_CoopInfo() return "open=1;state=searching;peers=" end

writeAll(WORK .. "/config/survival.default.ini", readAll(MOD .. "/config/survival.default.ini"))
writeAll(WORK .. "/config/survival.ini", readAll(MOD .. "/config/survival.default.ini"))

dofile(MOD .. "/Scripts/sv_config.lua")
assert(load(readAll(MOD .. "/Scripts/sv_menu.lua"), "=sv_menu.lua"))()
local src = readAll(MOD .. "/Scripts/sv_coop.lua"):gsub("\nlocal M = {", "\nM = {", 1)
assert(load(src, "=sv_coop.lua"))()
local M = _G.M
check(type(MENU) == "table" and type(SETUP) == "table" and type(MENU.tick) == "function", "sv_menu.lua loaded")
check(type(CFG.setup) == "table" and CFG.setup.offline and CFG.setup.online and CFG.setup.host, "CFG.setup has the three setups")

local t = 0
local function tick() t = t + 1; MENU.tick(t); COOP.tick(t) end
local function pick(code) choice = (math.floor(choice / 16) + 1) * 16 + code; tick() end
local function press(name, n) for _ = 1, n or 1 do queue[#queue + 1] = "SV_Set_" .. name; tick() end end

-- every page row's texts: there, short enough for the runtime's text slots (255), plain ASCII
local PAGES = {
    Modes = { "Offline", "Online", "Host", "Join", "Quick" }, Offline = { "Go", "Preset", "Zollars", "Enemies", "Rules" },
    Online = { "Go", "Preset", "Zollars", "Enemies", "Rules" },
    Host = { "Go", "Lobby", "Room", "CoopEnemies", "Preset", "Zollars", "Enemies", "Rules" },
    Rules = { "StartRound", "Break", "Specials", "Airfield", "Pay", "Skill", "Reset" },
}
tick()
local missing, long, wide = {}, {}, {}
for pg, rows in pairs(PAGES) do
    local keys = { "SV_Pg_" .. pg .. "_Title" }
    for _, r in ipairs(rows) do keys[#keys + 1] = "SV_Pg_" .. pg .. "_" .. r; keys[#keys + 1] = "SV_Pg_" .. pg .. "_" .. r .. "_Help" end
    for _, k in ipairs(keys) do
        local v = texts[k]
        if type(v) ~= "string" or v == "" then missing[#missing + 1] = k
        else
            if #v > 255 or #k >= 48 then long[#long + 1] = k .. " (" .. #v .. ")" end
            if v:find("[^\32-\126]") then wide[#wide + 1] = k end
        end
    end
end
check(#missing == 0, "every page row has a label and a help line" .. (#missing > 0 and (": missing " .. table.concat(missing, ", ")) or ""))
check(#long == 0, "every text fits the runtime's slots" .. (#long > 0 and (": " .. table.concat(long, ", ")) or ""))
check(#wide == 0, "every text is plain ASCII" .. (#wide > 0 and (": " .. table.concat(wide, ", ")) or ""))
check(texts.SV_Pg_Modes_Offline == "SURVIVAL MODE SP OFFLINE" and texts.SV_Pg_Modes_Join == "SURVIVAL MODE COOP JOIN", "the modes page's rows")
check(texts.SV_Pg_Online_Go == "START RUN: RANKED", "SP ONLINE with the shipped setup: ranked (" .. tostring(texts.SV_Pg_Online_Go) .. ")")
check(texts.SV_Pg_Modes_Quick == "QUICK START: SP ONLINE", "QUICK START before any run: the edition's (" .. tostring(texts.SV_Pg_Modes_Quick) .. ")")
check(quick == 5, "the runtime told QUICK START's mode (5, SP ONLINE)")

-- nothing picked: SURVIVAL MODE alone, the edition's setup (online here)
check(SETUP.mode() == "solo" and SETUP.zollars() == 0 and SETUP.enemyX() == 1 and SETUP.startRound() == 1, "no mode: the shipped rules")
check(SETUP.ranked() == true, "no mode in the leaderboard edition: ranked")

-- SP OFFLINE: its page's settings
pick(2)
check(MENU.mode == "offline", "SP OFFLINE picked")
press("Zollars", 2)
check(CFG.setup.offline.zollars == 2500 and SETUP.zollars() == 2500, "STARTING ZOLLARS 0 -> 1000 -> 2500")
check(texts.SV_Pg_Offline_Zollars == "STARTING ZOLLARS: 2,500", "its label (" .. tostring(texts.SV_Pg_Offline_Zollars) .. ")")
press("Enemies", 2)
check(CFG.setup.offline.enemies == 150 and math.abs(SETUP.enemyX() - 1.5) < 1e-9, "ENEMY AIRCRAFT 100 -> 125 -> 150")
press("Preset", 3)
check(CFG.setup.offline.preset == "ace" and SETUP.preset() == "ace", "PRESET auto -> casual -> standard -> ace")
check(presetName() == "ace", "the setup's preset over the difficulty's")
press("Preset")
check(CFG.setup.offline.preset == "auto" and presetName() == "standard", "PRESET wraps to auto: the difficulty's (standard here)")
press("StartRound", 2); press("Break"); press("Specials", 3); press("Airfield"); press("Pay", 4); press("Skill", 2)
check(SETUP.startRound() == 10 and SETUP.breakS() == 30 and SETUP.specialsX() == 0, "START AT ROUND 10, BREAK 30 S, SPECIAL ROUNDS OFF")
check(math.abs(SETUP.airfieldX() - 1.5) < 1e-9 and SETUP.airfieldHP() == 375, "AIRFIELD HEALTH 150%: 375 HP (" .. SETUP.airfieldHP() .. ")")
check(math.abs(SETUP.payX() - 0.5) < 1e-9, "ZOLLAR INCOME wraps 200 -> 50%")
check(SETUP.skillAdd() == 2, "ENEMY SKILL -1 .. 2: brutal")
check(texts.SV_Pg_Rules_Title == "MORE RULES: SP OFFLINE" and texts.SV_Pg_Rules_Skill == "ENEMY SKILL: BRUTAL", "MORE RULES shows SP OFFLINE's")
check(SETUP.ranked() == false, "SP OFFLINE: never ranked")
local ini = readAll(WORK .. "/config/survival.ini"):gsub("\r\n", "\n")
local sec = ini:match("\n%[setup%.offline%]\n(.-)\n%[") or ini:match("\n%[setup%.offline%]\n(.*)$") or ""
check(sec:find("\nzollars = 2500", 1, true) or sec:find("^zollars = 2500"), "zollars = 2500 saved under [setup.offline]")
check(sec:find("specials = off", 1, true) and sec:find("skill = 2", 1, true) and sec:find("start_round = 10", 1, true), "the other offline rules saved")
-- the leaderboard: SP OFFLINE runs aren't sent
local sh = {}
rawSends = 0
LB.send(sh)
check(rawSends == 0 and sh.state == "local", "SP OFFLINE: the run isn't sent")

-- SP ONLINE: its own setup, untouched by SP OFFLINE's
pick(5)
check(MENU.mode == "online" and SETUP.zollars() == 0 and SETUP.ranked() == true, "SP ONLINE: its own shipped setup, ranked")
rawSends = 0; LB.send({}); check(rawSends == 1, "SP ONLINE ranked: sent")
check(texts.SV_Pg_Rules_Title == "MORE RULES: SP ONLINE" and texts.SV_Pg_Rules_Skill == "ENEMY SKILL: NORMAL", "MORE RULES now shows SP ONLINE's")
press("Enemies")
check(SETUP.ranked() == false and texts.SV_Pg_Online_Go == "START RUN: UNRANKED", "SP ONLINE custom rules: unranked (" .. tostring(texts.SV_Pg_Online_Go) .. ")")
sh = {}; rawSends = 0; LB.send(sh); check(rawSends == 0 and sh.state == "local", "SP ONLINE unranked: not sent")
press("Reset")
check(SETUP.ranked() == true and CFG.setup.online.enemies == 100 and texts.SV_Pg_Online_Go == "START RUN: RANKED", "RESET TO DEFAULTS: ranked again")
check(CFG.setup.offline.zollars == 2500, "the reset left SP OFFLINE's alone")

-- co-op: HOST opens it, the menu page (6) leaves it, SP OFFLINE closes it
CFG.coop.enabled = true
pick(3)
check(COOP.open and COOP.role == "host" and opens == 1, "COOP HOST picked: hosting")
check(MENU.mode == "host" and texts.SV_Pg_Rules_Title == "MORE RULES: COOP HOST", "the host's setup on MORE RULES")
press("Zollars"); press("Room")
check(CFG.setup.host.zollars == 1000 and SETUP.zollars() == 1000, "the host's STARTING ZOLLARS 1000")
check(CFG.coop.max_players == 2, "CO-OP ROOM 24 -> 2")
check(texts.SV_Pg_Host_Lobby and texts.SV_Pg_Host_Lobby:find("^LOBBY: 1 OF 2 PLAYERS"), "the lobby row (" .. tostring(texts.SV_Pg_Host_Lobby) .. ")")
pick(6)
check(COOP.open and COOP.role == "host" and closes == 0 and MENU.mode == "host", "SURVIVAL MODE's page opened again: still hosting")
pick(2)
check(not COOP.open and closes == 1 and MENU.mode == "offline", "SP OFFLINE picked: co-op closed")
pick(4)
check(COOP.open and COOP.role == "join" and MENU.mode == "join", "COOP JOIN picked: joining")
check(SETUP.zollars() == 1000, "a joiner plays the host setup (its own, until the host's comes)")
-- the host's settings arrive: the joiner plays them; a press edits its own
CFG.setup.host.zollars = 1000
local hostSetup = deepCopy(CFG.setup)
hostSetup.host.enemies, hostSetup.host.preset = 200, "casual"
M.mine = {}
for k, v in pairs(CFG) do M.mine[k] = deepCopy(v) end
CFG.setup = hostSetup
check(math.abs(SETUP.enemyX() - 2) < 1e-9 and presetName() == "casual", "a joiner with the host's setup: 200% enemies, casual")
press("Enemies")
check(math.abs(SETUP.enemyX() - 2) < 1e-9 and M.mine.setup.host.enemies == 125, "a joiner's press edits its own setup, not the host's in CFG")
M.restoreMine()
check(CFG.setup.host.enemies == 125 and CFG.setup.host.preset == "auto", "co-op over: its own setup back, with its edit")

-- a run starts: its mode is QUICK START's
pick(2)
D = { round = 0 }
tick()
check(CFG.menu.last == "offline" and quick == 2 and texts.SV_Pg_Modes_Quick == "QUICK START: SP OFFLINE", "a run in SP OFFLINE: QUICK START plays it next")
D = nil; tick()
local ini2 = readAll(WORK .. "/config/survival.ini"):gsub("\r\n", "\n")
check(ini2:find("\nlast = offline", 1, true), "[menu] last = offline saved")

-- without the pages: the main menu's flat rows (coop.11's four settings rows) step SOLO's setup and the host's
MENU.pages = false
CFG.setup.online.zollars, CFG.setup.host.zollars = 0, 0
tick()
check(texts.SV_Menu_SetRoomTitle == "STARTING ZOLLARS: 0" and texts.SV_Menu_SetStartTitle == "START AT ROUND 1",
      "flat: the rows show STARTING ZOLLARS / START AT ROUND (" .. tostring(texts.SV_Menu_SetRoomTitle) .. ")")
check(texts.SV_Menu_SetRoomHelp and texts.SV_Menu_SetRoomHelp:find("Alone and when you host", 1, true) and #texts.SV_Menu_SetRoomHelp <= 255,
      "flat: their help says alone and when you host")
local rows = MENU.mainRows()
check(rows[1] == "SurvivalMode" and rows[#rows] == "SurvivalSetBreak" and #rows == 7, "flat with co-op: SURVIVAL MODE, HOST, JOIN, four settings rows")
press("Room"); press("Enemies"); press("Start")
check(CFG.setup.online.zollars == 1000 and CFG.setup.host.zollars == 1000, "flat: STARTING ZOLLARS 1000 alone and hosting")
check(CFG.setup.online.enemies == 125 and CFG.setup.host.enemies == 125 and CFG.coop.max_players == 2,
      "flat: ENEMY AIRCRAFT steps alone's (100 -> 125) and the host's takes the same value; CO-OP ROOM untouched")
check(CFG.setup.online.start_round == 5 and CFG.setup.host.start_round == 5, "flat: START AT ROUND 5 alone and hosting")
check(texts.SV_Menu_SetRoomTitle == "STARTING ZOLLARS: 1,000", "flat: the label follows (" .. tostring(texts.SV_Menu_SetRoomTitle) .. ")")
MENU.pages = nil

-- survival.ini read again: the saved setups
dofile(MOD .. "/Scripts/sv_config.lua")
check(CFG.setup.offline.zollars == 2500 and CFG.setup.offline.specials == "off" and CFG.setup.host.zollars == 1000 and CFG.menu.last == "offline",
      "survival.ini read again: the saved setups and last mode")
check(CFG_DEFAULTS.setup.online.zollars == 0, "the shipped setup stays the shipped one")
print(fails == 0 and "menu: all passed" or ("menu: " .. fails .. " FAILED"))
os.exit(fails == 0 and 0 or 1)
