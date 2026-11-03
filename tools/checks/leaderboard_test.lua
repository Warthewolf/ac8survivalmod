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
--   - the Worker's answers: taken, refused (unqueued); no build hash from the runtime;
--   - (0.73.77, plan H2 / H5) a co-op run: the host's one record with its squad (names sanitized and unique ignoring
--     case, the host first as the run's pilot, the kills adding up, one who left with their kills, a part not counted),
--     a joiner keeping the host's word and sending nothing, a host by migration sending it under the same run id (and
--     not one its first host sent), a squad trimmed to 24, a co-op host nobody joined and a solo run as before. Every
--     body is written for the Worker's checkRun (leaderboard_bodies.mjs).
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

local tallyHook = 0
local function run(name, chunk)
    local src = readAll(MOD .. "/Scripts/" .. name)
    if name == "sv_coop.lua" then
        src = src:gsub("\nlocal M = {", "\nM = {", 1)
        -- ((0.73.77) the host's kill named in its "dn" counted for the squad: economy C1's tallyKill, called by hostTick)
        src, tallyHook = src:gsub("\nlocal function tallyKill%(", "\nfunction tallyKill(", 1)
    end
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
    -- ((0.73.78, economy C3-C5 and plan G6) the per-round prices, the airstrike's pay and limits, the specials' split:
    -- gameplay, counted; the shipped values are the defaults, so a stock run stays unedited (above))
    { "shop.items.Airstrike.price_per_round", function(c) c.shop.items.Airstrike.price_per_round = 0 end },
    { "shop.items.Ecm.price_per_round", function(c) c.shop.items.Ecm.price_per_round = 100 end },
    { "credits.airstrike_x", function(c) c.credits.airstrike_x = 0.5 end },
    { "credits.special_split", function(c) c.credits.special_split = 0 end },
    { "tactical.airstrike.per_round", function(c) c.tactical.airstrike.per_round = 0 end },
    { "tactical.airstrike.max_hit", function(c) c.tactical.airstrike.max_hit = 0 end },
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
CFG.coop.revive.price_per_round = 0                -- ((0.73.78, economy C6) the revive's price by the round)
check(edited(true)[1] == "coop.revive.price_per_round" and #edited(false) == 0, "a co-op run: the revive's price a round counts; solo it doesn't")
CFG.coop.revive.price_per_round = CFG_DEFAULTS.coop.revive.price_per_round
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

-- ---------------------------------------------------------------------------------------- a co-op run's squad (0.73.77)
-- (plan H2: one team run per co-op run, sent by the host, LB.coopRecord; each joiner's copy from the host's "lb"
-- messages, LB.coopMsg; a host by migration sends it, LB.coopTakeover.) Every body sent is also written for the Worker's
-- own checkRun (leaderboard_bodies.mjs, from leaderboard_test.sh when node is there).
local bodies = {}
local function keep(want, what, body) bodies[#bodies + 1] = want .. "\t" .. what .. "\t" .. body end
keep("ok", "a solo run without a build hash", posts[1] or "")
VERSION = "0.73.77-coop2mp.78"                              -- (a COOP2MP build's, plan H1)
local wire = {}
local rawCoopSend, rawPlayers, rawAddrOf = SV_CoopSend, COOP.players, addrOf
function SV_CoopSend(msg, rel, to) wire[#wire + 1] = { msg = msg, to = to }; return 1 end
local players = {}
COOP.players = function() return players end
addrOf = function(o) return type(o) == "table" and o.addr or nil end      -- (a ground target's: its part check)
local function fields(s) local t = {}; for x in (s .. "|"):gmatch("([^|]*)|") do t[#t + 1] = x end; return t end
local function lbWire(skipX)
    local out = {}
    for _, w in ipairs(wire) do if w.msg:sub(1, 3) == "lb|" and not (skipX and w.msg:sub(1, 5) == "lb|x|") then out[#out + 1] = w end end
    return out
end
local function coopPart(b) return b:match(',"coop":(%b{})') end
local function sumIn(part, key) local n = 0; for v in part:gmatch('"' .. key .. '":(%d+)') do n = n + tonumber(v) end; return n end
local function lastPost() return posts[#posts] or "" end
local SID = { "76561198000000001", "76561198000000002", "76561198000000003", "76561198000000004" }
check(tallyHook == 1 and type(tallyKill) == "function", "the test reaches sv_coop.lua's tallyKill (the host's named kills)")
posts, results, replies, LB.jobs = {}, {}, {}, {}
CFG.leaderboard.pilot = ""                                  -- (the run's pilot: the Steam name, Naish)
COOP.open, COOP.role, COOP.slot, M.linkedPeers = true, "host", 0, 3
M.roster = { [0] = { name = "Naish", sid = SID[1], code = "f16c" }, [1] = { name = "Wolf", sid = SID[2], code = "su57" },
             [2] = { name = "\208\146\208\158\208\155\208\154", sid = SID[3], code = "fa36" },   -- (Cyrillic: no Latin letters)
             [3] = { name = "NAISH", sid = SID[4], code = "adfx02" } }
players = { { slot = 0, isMe = true }, { slot = 1, inLevel = true }, { slot = 2, inLevel = true }, { slot = 3, inLevel = true } }
LB.co = nil
newRun(); RUN.stats.air, RUN.stats.ground = 40, 6           -- (the host's count: every kill its game saw, as solo)
wire = {}
LB.poll()
local co = LB.co
local n = 0
for _ in pairs(co and co.squad or {}) do n = n + 1 end
check(co and co.mine and #co.id == 32 and n == 4, "the host's co-op run: its id and 4 in the squad (" .. n .. ")")
local hostId = co and co.id or "?"
local w1 = lbWire()
check(#w1 >= 2 and w1[1].msg:find("^lb|r|" .. hostId .. "|%d+|40|6|") and w1[2].msg:find("^lb|p|" .. hostId .. "|sid" .. SID[1] .. ",0,40,6,0,f16c,Naish"),
    "the host tells everyone: lb|r (the run) and lb|p (the players): " .. tostring(w1[2] and w1[2].msg:sub(1, 90)))
LB.coopMsg(fields("lb|n|" .. hostId .. "|Wolfie"), 1)       -- (player 2's leaderboard name)
check(logged("player 2 goes on the leaderboard as Wolfie"), "a joiner's leaderboard name taken (lb|n)")
for _ = 1, 5 do tallyKill({ unit = "SV_Unit_Pool_01" }, { slot = 1 }) end
local function obj(a, parent)                                -- (a game object as sv_core's valid() reads it)
    return { addr = a, IsValid = function() return true end, GetAttachParentActor = function() return parent end }
end
for i = 1, 2 do tallyKill({ unit = "SV_Unit_Amphib", key = "BP_LCAC#" .. i, obj = obj(900 + i, nil) }, { slot = 2 }) end
tallyKill({ unit = "SV_Unit_Aegis", key = "BP_mk45#1", obj = obj(950, obj(951, nil)) }, { slot = 2 })   -- (a turret on its hull)
for _ = 1, 2 do tallyKill({ unit = "SV_Unit_Pool_02" }, { slot = 3 }) end
tallyKill({ unit = "SV_Unit_Pool_02" }, { slot = 0 })       -- (the host's own: in its count already)
tallyKill({ unit = "SV_Unit_Pool_02" }, { side = "allies" })  -- (no player's)
LB.stat("revives", 1, 1); LB.stat("revives", 1, 0)
check(logged("player 3's kill of ? not counted for them: a part of"), "a part (a turret on a ship) isn't a ground kill for the squad")
M.roster[3] = nil                                           -- (player 4 leaves: they keep what they did)
players = { { slot = 0, isMe = true }, { slot = 1, inLevel = true }, { slot = 2, inLevel = true } }
co.outAt, co.allAt = 0, 0
LB.poll()
local migrWire = lbWire(true)                                -- (what a joiner has before the host's run ends)
LB.finish("died")
local b = lastPost()
local cp = coopPart(b) or ""
check(#posts == 1 and b:find('"run_id":"' .. hostId .. '"', 1, true) and b:find('"pilot":"Naish"', 1, true)
    and b:find('"kills":{"air":40,"ground":6}', 1, true), "the host sends one record: the co-op run's id, its pilot, the squad's kills")
check(cp == '{"players":4,"squad":[{"pilot":"Naish","aircraft":"f16c","air":33,"ground":4,"revives":1,"host":true},'
    .. '{"pilot":"Wolfie","aircraft":"su57","air":5,"ground":0,"revives":1},{"pilot":"Pilot 3","aircraft":"fa36","air":0,"ground":2,"revives":0},'
    .. '{"pilot":"NAISH 2","aircraft":"adfx02","air":2,"ground":0,"revives":0}]}',
    "its squad: the host first (the run's kills less the joiners'), a joiner's own name, a non-Latin name as Pilot 3, a name "
    .. "twice ignoring case as NAISH 2, the one who left with their kills: " .. cp)
check(sumIn(cp, "air") == 40 and sumIn(cp, "ground") == 6, "the squad's kills add up to the run's exactly")
check(logged("leaderboard: co-op run " .. hostId:sub(1, 8) .. " over (died): 4 players") and logged("(co-op, 4 players)"),
    "logged: the squad, and the co-op send")
local sentX = false
for _, w in ipairs(wire) do if w.msg == "lb|x|" .. hostId then sentX = true end end
check(sentX, "everyone told it's sent (lb|x)")
keep("ok", "the host's co-op run (4 players, one who left)", b)
keep("squad's kills don't add up to the run's", "the same run with its squad's kills changed", (b:gsub('"air":33', '"air":32', 1)))

-- a joiner: the host's word kept, nothing sent
posts, results, replies, LB.jobs = {}, {}, {}, {}
COOP.role, COOP.slot, LB.co = "join", 1, nil
CFG.leaderboard.pilot = "Wolfie"
M.roster = { [0] = { name = "Naish", sid = SID[1], code = "f16c" }, [1] = { name = "Wolf", sid = SID[2], code = "su57" },
             [2] = { name = "\208\146\208\158\208\155\208\154", sid = SID[3], code = "fa36" } }
for _, w in ipairs(migrWire) do LB.coopMsg(fields(w.msg)) end
co = LB.co
local mn = 0
for _ in pairs(co and co.squad or {}) do mn = mn + 1 end
local hostLine = co and co.squad["sid" .. SID[1]]
check(co and co.id == hostId and not co.mine and mn == 4 and hostLine and hostLine.air == 33 and hostLine.pilot == "Naish"
    and co.run.air == 40, "a joiner keeps the host's squad (" .. mn .. ") and run (lb|r, lb|p)")
wire = {}
LB.poll()
check(wire[1] and wire[1].msg == "lb|n|" .. hostId .. "|Wolfie" and wire[1].to == 0, "a joiner tells the host its leaderboard name (lb|n)")
newRun(); LB.finish("died")
check(#posts == 0 and LB.show.state == "host" and summaryLine(LB.show) == "host" and logged("leaderboard: a co-op run; the host sends it"),
    "a joiner sends nothing: \"leaderboard: a co-op run; the host sends it\"")
check(string.format(CFG.hud.text.lb_coop_host) == "CO-OP: THE HOST SENDS THE RUN", "its summary says the host sends it")

-- that joiner takes over by host migration: the same run sent, under the host's run id, the old host in the squad
LB.coopTakeover()
COOP.role, COOP.slot, M.linkedPeers = "host", 0, 1
M.roster = { [0] = { name = "Wolf", sid = SID[2], code = "su57" }, [1] = { name = "\208\146\208\158\208\155\208\154", sid = SID[3], code = "fa36" } }
players = { { slot = 0, isMe = true }, { slot = 1, inLevel = true } }
newRun(); RUN.stats.air, RUN.stats.started = 7, os.time() - 300   -- (this game's own view, joined later)
D.round = 6                                                 -- (migration plays round 7 again: one lower until it starts)
LB.poll()
check(LB.co.mine and RUN.stats.air == 40 and RUN.stats.ground == 6 and os.time() - RUN.stats.started >= 890
    and logged("carried on here (host migration): 4 in its squad, 40 air / 6 ground"), "a host by migration carries the run on (its start, kills)")
LB.stat("air", 1)                                           -- (a kill counted here: player 2's, now in slot 1)
tallyKill({ unit = "SV_Unit_Pool_03" }, { slot = 1 })
LB.finish("died")
b = lastPost(); cp = coopPart(b) or ""
check(#posts == 1 and b:find('"run_id":"' .. hostId .. '"', 1, true) and b:find('"pilot":"Wolfie"', 1, true)
    and b:find('"kills":{"air":41,"ground":6}', 1, true), "the host by migration sends it: the first host's run id, its own pilot")
check(cp == '{"players":4,"squad":[{"pilot":"Wolfie","aircraft":"su57","air":5,"ground":0,"revives":1,"host":true},'
    .. '{"pilot":"Naish","aircraft":"f16c","air":33,"ground":4,"revives":1},{"pilot":"Pilot 3","aircraft":"fa36","air":1,"ground":2,"revives":0},'
    .. '{"pilot":"NAISH 2","aircraft":"adfx02","air":2,"ground":0,"revives":0}]}', "its squad: the new host first, the old one with what they did: " .. cp)
check(b:match('"time_s":(%d+)') and tonumber(b:match('"time_s":(%d+)')) >= 890, "its time from the first host's start")
check(b:find('"round":7,', 1, true), "its round the first host's (7), though this game's is 6 till the round starts again")
keep("ok", "a host by migration's co-op run", b)

-- a run its first host sent already: a host by migration doesn't send it again
posts, results, replies, LB.jobs = {}, {}, {}, {}
COOP.role, COOP.slot, LB.co = "join", 1, nil
M.roster = { [0] = { name = "Naish", sid = SID[1] }, [1] = { name = "Wolf", sid = SID[2] } }
for _, w in ipairs(migrWire) do LB.coopMsg(fields(w.msg)) end
LB.coopMsg(fields("lb|x|" .. hostId))
LB.coopTakeover()
COOP.role, COOP.slot = "host", 0
M.roster = { [0] = { name = "Wolf", sid = SID[2] } }
newRun(); LB.poll(); LB.finish("died")
check(#posts == 0 and LB.show.state == "host" and logged("its first host sent already (before host migration); not sent again"),
    "a host by migration of a run its first host sent: not sent again")

-- a squad of more than 24 (players came and went): the 24 who did the most, the kills still the run's
posts, results, replies, LB.jobs = {}, {}, {}, {}
LB.co, M.roster = nil, { [0] = { name = "Naish", sid = SID[1], code = "f16c" } }
CFG.leaderboard.pilot = ""
newRun(); RUN.stats.air = 1000
for i = 1, 30 do
    local s = (i - 1) % 23 + 1
    M.roster[s] = { name = "P" .. i, sid = string.format("765611980%08d", 1000 + i) }
    players = { { slot = 0, isMe = true }, { slot = s, inLevel = true } }
    LB.poll()
    LB.coopTally(s, "air", i)
end
LB.finish("died")
b = lastPost(); cp = coopPart(b) or ""
local np = 0
for _ in cp:gmatch('"pilot":') do np = np + 1 end
check(cp:find('^{"players":24,') and np == 24 and sumIn(cp, "air") == 1000 and b:find('"kills":{"air":1000,', 1, true)
    and cp:find('"pilot":"Naish","aircraft":"f16c","air":563,', 1, true) and not cp:find('"pilot":"P7"', 1, true),
    "31 who flew: 24 sent (the 7 who did least dropped, their kills the host's), the sums the run's")
keep("ok", "a co-op run trimmed to 24", b)

-- the run's pilot cut to 24 ending in a space (LB.pilot's), a joiner's name with symbols
posts, results, replies, LB.jobs = {}, {}, {}, {}
LB.co, CFG.leaderboard.pilot = nil, "Abcdefghijklmnopqrstuvw xyz"
M.roster = { [0] = { name = "Naish", sid = SID[1] }, [1] = { name = "D@rk|Ace!", sid = SID[2] } }
players = { { slot = 1, inLevel = true } }                  -- (and the host's own plane not read: its line all the same)
newRun(); LB.poll(); LB.finish("restart")
b = lastPost(); cp = coopPart(b) or ""
check(b:find('"pilot":"Abcdefghijklmnopqrstuvw ","difficulty"', 1, true) and cp:find('[{"pilot":"Abcdefghijklmnopqrstuvw ","air"', 1, true)
    and cp:find('{"pilot":"DrkAce","air":0', 1, true), "the host's line is the run's pilot exactly; a joiner's name sanitized: " .. cp)
keep("ok", "a co-op run with a 24-letter pilot and a sanitized name", b)

-- the host alone (nobody else flew): a solo record; co-op off: unchanged
posts, results, replies, LB.jobs = {}, {}, {}, {}
LB.co, CFG.leaderboard.pilot = nil, ""
M.roster = { [0] = { name = "Naish", sid = SID[1] } }
players = { { slot = 0, isMe = true } }
newRun(); LB.poll(); LB.finish("died")
b = lastPost()
check(#posts == 1 and not b:find('"coop"', 1, true) and not b:find(LB.co.id, 1, true) and logged("nobody else flew in it; it goes as a solo run"),
    "a co-op host nobody joined: sent as a solo run")
keep("ok", "a co-op host's run nobody else flew in", b)
COOP.open, COOP.role, COOP.slot, M.linkedPeers, LB.co = false, nil, nil, 0, nil
newRun(); LB.finish("died")
b = lastPost()
check(#posts == 2 and not b:find('"coop"', 1, true) and b:find('"pilot":"Naish"', 1, true) and b:find('"kills":{"air":40,"ground":6}', 1, true),
    "a solo run: as before, no co-op block")
keep("ok", "a solo run after co-op", b)
SV_CoopSend, COOP.players, addrOf = rawCoopSend, rawPlayers, rawAddrOf
writeAll(WORK .. "/bodies.txt", table.concat(bodies, "\n") .. "\n")

print("leaderboard: " .. (fails > 0 and (fails .. " FAILED") or "all passed"))
os.exit(fails > 0 and 1 or 0)
