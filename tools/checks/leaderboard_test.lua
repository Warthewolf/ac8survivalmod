-- leaderboard_test.lua <mod dir> <work dir> [override | override_error] (run by tools/checks/leaderboard_test.sh): the
-- leaderboard's edited-run check (LB.edited, 2026-10-30) and what's sent, on the real sv_core, sv_config,
-- sv_leaderboard, sv_menu and sv_coop with the game stubbed:
--   - a fresh install (the shipped survival.default.ini): nothing edited, the run sent with "edited":[] and its build hash;
--   - each kind of gameplay setting changed: edited, not sent, "NOT RANKED: EDITED (<key>)" on the summary, every key
--     in the log with its value and the shipped one;
--   - what isn't counted: the HUD, sound, music, log, the pilot name, the menu, the run setups, co-op's link and keys
--     (solo), texts, key bindings and the camera;
--   - a co-op run: the room's rules count (the host's setup, [coop]'s rules), each player's key and camera don't;
--   - a test key pressed in a run, and at the main menu (the next run's); a head start; SP ONLINE's START RUN label;
--   - the Worker's answers: taken, refused (unqueued); no build hash from the runtime.
-- override / override_error: a Scripts/survival_config.lua (returning a table / failing) found by require: edited.
local MOD, WORK, MODE = arg[1], arg[2], arg[3] or "plain"
local fails = 0
local function check(ok, what) if ok then print("  ok   " .. what) else print("  FAIL " .. what); fails = fails + 1 end end
local function readAll(p) local f = assert(io.open(p, "rb")); local s = f:read("a"); f:close(); return s end
local function writeAll(p, s) local f = assert(io.open(p, "wb")); f:write(s); f:close() end
do                                    -- (the runtime's paths are Windows ones: SCRIPT_DIR .. "..\\config\\")
    local rawOpen, rawRemove = io.open, os.remove
    io.open = function(p, m) return rawOpen((tostring(p):gsub("\\", "/")), m) end
    os.remove = function(p) return rawRemove((tostring(p):gsub("\\", "/"))) end
end
writeAll(WORK .. "/config/survival.default.ini", readAll(MOD .. "/config/survival.default.ini"))
os.remove(WORK .. "/config/survival.ini")
os.remove(WORK .. "/config/pending_runs.txt")
package.path = WORK .. "/Scripts/?.lua;" .. package.path      -- (as UE4SS: Scripts on require's path)
if MODE == "override" then writeAll(WORK .. "/Scripts/survival_config.lua", "return { intermission_s = 25 }\n")
elseif MODE == "override_error" then writeAll(WORK .. "/Scripts/survival_config.lua", "error('broken on purpose')\n")
else os.remove(WORK .. "/Scripts/survival_config.lua") end

-- the game's world, stubbed (as tools/checks/menu_test.lua)
VERSION = "0.72.2-coop.20"
TAG = "[AC8SurvivalMode] "
local BUILD = string.rep("ab", 32)
local buildHash = BUILD
function SV_BuildHash() return buildHash end
local posts, results, replies = {}, {}, {}
function SV_Post(body) posts[#posts + 1] = body; return #posts end
function SV_PostResult(id) return results[id] or 0 end
function SV_PostReply(id) return replies[id] or "" end
function SV_SteamName() return "Naish" end
KILL = { side = function() end }
function SV_CoopSend() return 1 end
local texts = {}
function SV_SetText(k, v) texts[k] = v; return 1 end
function FindAllOf() return {} end
function FindFirstOf() return nil end
function StaticFindObject() return nil end
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
local choice = 0
function SV_MenuChoice() return choice end
function SV_MenuSetting() return "" end
function SV_MenuQuick() return 1 end
function SV_CoopOpen() return 1 end
function SV_CoopClose() end
function SV_CoopRecv() return "" end
function SV_CoopInfo() return "open=1;state=searching;peers=" end
Key = { F8 = 119, F9 = 120 }
STATS = { runEnd = function() end }                             -- (sv_stats.lua, not loaded here)

local function run(name, chunk)
    local src = readAll(MOD .. "/Scripts/" .. name)
    if name == "sv_coop.lua" then src = src:gsub("\nlocal M = {", "\nM = {", 1) end
    assert(load(src, chunk or ("=" .. name)))()
end
run("sv_core.lua", "@" .. WORK .. "/Scripts/sv_core.lua")
local logs = {}
function log(s) logs[#logs + 1] = s end
local function logged(part) for _, l in ipairs(logs) do if l:find(part, 1, true) then return l end end return nil end
run("sv_config.lua"); run("sv_leaderboard.lua"); run("sv_menu.lua"); run("sv_coop.lua")
check(type(LB.edited) == "function" and type(COOP.cfgDiff) == "function", "the parts loaded: LB.edited, COOP.cfgDiff")
presetCache = { at = math.huge, name = "standard", d = 1 }      -- (the difficulty without the game's manager)
function presetName() return "standard", 1 end

local function edited(coopRun) local out, detail = LB.edited(coopRun); return out, detail end
local function has(list, v) for _, x in ipairs(list) do if x == v then return true end end return false end
-- a run: round 7, a few kills, no specials
local function newRun()
    D = { round = 7, startRound = 1 }
    RUN = { earned = 12000, spent = 3000, stats = { started = os.time() - 900, air = 40, ground = 6, aces = 1, allies = 0,
            af_down = 0, captured = 0, by_allies = 0, by_defences = 0, specials = {} } }
    LB.show = nil
end
local function summaryLine(sh)
    local t = CFG.hud.text
    return (sh.state == "unranked" and string.format(t.lb_unranked, tostring(sh.why):upper():sub(1, 48)))
        or (sh.state == "refused" and string.format(t.lb_refused, tostring(sh.why):upper())) or sh.state
end

if MODE ~= "plain" then
    -- ------------------------------------------------------------------------------------ a survival_config.lua
    check(CFG_USER_FILE == "survival_config.lua", MODE .. ": survival_config.lua found by require: CFG_USER_FILE set")
    local out = edited(false)
    check(out[1] == "survival_config.lua", MODE .. ": the run is edited (" .. table.concat(out, ", ") .. ")")
    if MODE == "override" then check(has(out, "intermission_s"), "override: its change is named too (intermission_s)") end
    newRun(); LB.finish("died")
    check(#posts == 0 and LB.show.state == "unranked" and summaryLine(LB.show) == "NOT RANKED: EDITED (SURVIVAL_CONFIG.LUA)",
        MODE .. ": not sent; the summary says " .. summaryLine(LB.show))
    os.remove(WORK .. "/Scripts/survival_config.lua")
    print(MODE .. ": " .. (fails > 0 and (fails .. " FAILED") or "all passed"))
    os.exit(fails > 0 and 1 or 0)
end

-- ---------------------------------------------------------------------------------------- a fresh install
check(CFG_USER_FILE == nil, "no survival_config.lua: CFG_USER_FILE not set")
local out = edited(false)
check(#out == 0, "the shipped survival.default.ini: nothing edited" .. (#out > 0 and (" (" .. table.concat(out, ", ") .. ")") or ""))
CFG.hud.info.enabled = false                                     -- (the runtime turns it off without key binds: on screen only)
check(#edited(false) == 0, "the HUD's info row switched off at run time: still nothing edited")
newRun(); LB.finish("died")
check(#posts == 1 and LB.show.state == "sending", "a stock run is sent (" .. tostring(LB.show.state) .. ")")
local body = posts[1] or ""
check(body:find('"edited":[]', 1, true) and body:find('"build":"' .. BUILD .. '"', 1, true) and body:find('"mod":"0.72.2-coop.20"', 1, true),
    "its body: \"edited\":[], the build hash, the co-op version")
check(readAll(WORK .. "/config/pending_runs.txt"):find(BUILD, 1, true) ~= nil, "queued in pending_runs.txt until answered")
-- the Worker took it
results[1], replies[1] = 200, '{"ok":true,"score":7900}'
LB.poll()
check(LB.show.state == "sent" and #LB.queue == 0 and io.open(WORK .. "/config/pending_runs.txt", "r") == nil, "taken: sent, unqueued, the queue file gone")

-- ---------------------------------------------------------------------------------------- what counts
local GAMEPLAY = {
    { "specials.chance", function(c) c.specials.chance = 0.5 end },
    { "credits.start", function(c) c.credits.start = 50000 end },
    { "intermission_s", function(c) c.intermission_s = 60 end },
    { "aircraft", function(c) c.aircraft = { "f16c_common" } end },
    { "tells.enabled", function(c) c.tells.enabled = false end },
    { "tells.lead_s.dive", function(c) c.tells.lead_s.dive = 3.0 end },
    { "profile.enabled", function(c) c.profile.enabled = false end },
    { "flares.magazine", function(c) c.flares.magazine = 5 end },
    { "probe.behaviour", function(c) c.probe.behaviour = true end },
    { "aces.flight.reaper.openers", function(c) c.aces.flight.reaper.openers = { "none" } end },
    { "shop.items.Flares.price", function(c) c.shop.items.Flares.price = 1 end },
}
for _, g in ipairs(GAMEPLAY) do
    local saved = deepCopy(CFG)
    g[2](CFG)
    local o = edited(false)
    check(o[1] == g[1] and #o == 1, "edited: " .. g[1] .. " (" .. table.concat(o, ", ") .. ")")
    for k, v in pairs(saved) do CFG[k] = v end
end
check(#edited(false) == 0, "put back: nothing edited")

local FREE = {
    { "hud", function(c) c.hud.x = 300; c.hud.text.lb_title = "FIN: %s" end },
    { "sound / music / log", function(c) c.sound.master_db = -10; c.music.enabled = true; c.log.verbose = true end },
    { "the pilot name and summary time", function(c) c.leaderboard.pilot = "Someone"; c.leaderboard.show_s = 30 end },
    { "the menu", function(c) c.menu.pages = false; c.menu.last = "offline" end },
    { "measurements", function(c) c.ai_watch = false; c.stats.enabled = false end },
    { "the run setups (SETUP.ranked's)", function(c) c.setup.offline.zollars = 5000; c.setup.host.enemies = 150 end },
    { "co-op in a solo run", function(c) c.coop.name = "Wolf"; c.coop.revive.price = 100; c.coop.aircraft_per_player = 0.5 end },
    { "texts (a translation)", function(c) c.allies.text.orders = "ALLIES: %s!"; c.shop.items.Flares.label = "LEURRES" end },
    { "display names and callsigns", function(c) c.allies.aircraft.name = "GHOST"; c.aces.demon.f22a = "Abaddon"; c.aces.demon.squadron = "Pit" end },
    { "key bindings", function(c) c.hud.info.key = "K"; c.tactical.keys = false; c.allies.orders.key = false end },
    { "sound names", function(c) c.shop.sounds.bought = "x" end },
}
for _, g in ipairs(FREE) do
    local saved = deepCopy(CFG)
    g[2](CFG)
    local o = edited(false)
    check(#o == 0, "not counted: " .. g[1] .. (#o > 0 and (" (" .. table.concat(o, ", ") .. ")") or ""))
    for k, v in pairs(saved) do CFG[k] = v end
end

-- ---------------------------------------------------------------------------------------- an edited run
CFG.specials.chance, CFG.tells.enabled = 0.5, false
posts = {}
newRun(); LB.finish("died")
check(#posts == 0 and LB.show.state == "unranked", "an edited run isn't sent")
check(summaryLine(LB.show) == "NOT RANKED: EDITED (SPECIALS.CHANCE)", "its summary: " .. summaryLine(LB.show))
local l = logged("leaderboard: not sent: the run was edited")
check(l and l:find("specials.chance = 0.5 (shipped 0.3)", 1, true) and l:find("tells.enabled = false (shipped true)", 1, true),
    "the log names every changed key with its value: " .. tostring(l))
check(#LB.queue == 0, "and it isn't queued")
CFG.specials.chance, CFG.tells.enabled = CFG_DEFAULTS.specials.chance, CFG_DEFAULTS.tells.enabled

-- ---------------------------------------------------------------------------------------- a co-op run
COOP.open = true
CFG.coop.revive.price = 100
check(edited(true)[1] == "coop.revive.price", "a co-op run: the room's revive price counts")
check(#edited(false) == 0, "the same setting in a solo run doesn't")
CFG.coop.revive.price = CFG_DEFAULTS.coop.revive.price
CFG.coop.revive.key, CFG.coop.revive.camera.back_m, CFG.coop.name, CFG.coop.transport = "P", 50, "Wolf", "udp"
check(#edited(true) == 0, "a co-op run: each player's key, camera, name and link don't")
CFG.setup.host.zollars = 5000
check(edited(true)[1] == "setup.host.zollars", "a co-op run: the host's setup counts")
CFG.setup.host.zollars = CFG_DEFAULTS.setup.host.zollars
CFG.coop.aircraft_per_player = 0.5
check(edited(true)[1] == "coop.aircraft_per_player", "a co-op run: more enemies per player counts")
CFG.coop.aircraft_per_player = CFG_DEFAULTS.coop.aircraft_per_player
CFG.coop.leaderboard = true                     -- (co-op runs sent: an opt-in, not a rule)
posts = {}
newRun(); MENU.mode = "host"; LB.finish("died")
check(#posts == 1, "a stock co-op run with [coop] leaderboard = true is sent")
MENU.mode = nil
CFG.coop.leaderboard = false
newRun(); LB.finish("died")
check(#posts == 1 and LB.show.state == "local", "a co-op run without it isn't (CFG.coop.leaderboard)")
COOP.open = false
for k, v in pairs(CFG_DEFAULTS.coop) do if type(v) ~= "table" then CFG.coop[k] = v end end
CFG.coop.revive = deepCopy(CFG_DEFAULTS.coop.revive)

-- ---------------------------------------------------------------------------------------- test keys
posts = {}
newRun()
LB.testKey(Key.F9)
check(RUN.stats.test_key == "Ctrl+F9" and edited(false)[1] == "test key Ctrl+F9", "a test key in a run: edited (Ctrl+F9)")
LB.finish("died")
check(#posts == 0 and summaryLine(LB.show) == "NOT RANKED: EDITED (TEST KEY CTRL+F9)", "not sent: " .. summaryLine(LB.show))
D, RUN = nil, { stats = nil }
LB.testKey(Key.F8)
check(LB.menuTestKey == "Ctrl+F8" and edited(false)[1] == "test key Ctrl+F8", "a test key at the main menu: the next run's")
newRun(); LB.finish("restart")
check(#posts == 0 and LB.show.state == "unranked" and LB.menuTestKey == nil, "that run isn't sent; the key's forgotten after it")
newRun(); LB.finish("died")
check(#posts == 1, "the run after is sent again")
results[#posts], replies[#posts] = 200, '{"ok":true,"score":1}'
LB.poll()

-- ---------------------------------------------------------------------------------------- a head start, the menu's label
newRun(); D.startRound = 5; LB.finish("died")
check(#posts == 1 and LB.show.state == "local", "a head start: not sent (as before)")
MENU.mode = "online"
MENU.texts(true, "test")
check(texts.SV_Pg_Online_Go == "START RUN: RANKED", "SP ONLINE, stock: START RUN: RANKED (" .. tostring(texts.SV_Pg_Online_Go) .. ")")
CFG.specials.chance = 0.9
MENU.texts(true, "test")
check(texts.SV_Pg_Online_Go == "START RUN: UNRANKED" and tostring(texts.SV_Pg_Online_Go_Help):find("Edited settings (specials.chance)", 1, true),
    "SP ONLINE, edited: START RUN: UNRANKED, the help names it (" .. tostring(texts.SV_Pg_Online_Go_Help) .. ")")
CFG.specials.chance = CFG_DEFAULTS.specials.chance
MENU.mode = nil

-- ---------------------------------------------------------------------------------------- the Worker's answers
posts = {}
newRun(); LB.finish("died")
results[1], replies[1] = 422, '{"ok":false,"error":"edited or unknown build"}'
LB.poll()
check(LB.show.state == "refused" and summaryLine(LB.show) == "NOT ACCEPTED: EDITED OR UNKNOWN BUILD" and #LB.queue == 0,
    "refused as an unknown build: " .. summaryLine(LB.show) .. ", unqueued")
buildHash = ""
posts, results, replies = {}, {}, {}
newRun(); LB.finish("died")
check(#posts == 1 and not posts[1]:find('"build"', 1, true) and logged("no build hash"), "no build hash from the runtime: sent without one, logged")
results[1] = 200; LB.poll()
buildHash = BUILD

print("leaderboard: " .. (fails > 0 and (fails .. " FAILED") or "all passed"))
os.exit(fails > 0 and 1 or 0)
