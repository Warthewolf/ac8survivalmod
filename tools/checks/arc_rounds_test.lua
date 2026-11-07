-- arc_rounds_test.lua <mod dir> <work dir> (run by tools/checks/arc_rounds_test.sh): GONE FISHIN', the day-night arc and
-- THE FESTIVAL in the real rounds and in co-op (0.74.0; tools/re/FISHING.md 9), on the real sv_core, sv_config, sv_rows,
-- sv_ai, sv_hud, sv_subs, sv_sky, sv_spawn, sv_anomalies, sv_rounds (startRound exposed), sv_amphib, sv_spaceport,
-- sv_fishing, sv_festival, sv_tactical, sv_stats, sv_tells, sv_director and sv_coop (M exposed), the game stubbed:
--   the specials' dice: GONE FISHIN' in the rotation from from_round, once a run (out of the bag and never drawn again once
--     it's been; a test key's forced one still comes); THE FESTIVAL never drawn, the round F + 6 by specialFor; no
--     Spaceport the round before it; VALKA's gate (SPC.kinds.valka.ready by the round asked, her test key forced through
--     SPC.canStart); startRound's GONE FISHIN' and THE FESTIVAL rounds (their own, no fighters); roundsTick's generic busy /
--     over holding the round while the special runs;
--   the Alicorn's rows judged apart from THE FESTIVAL's searchlights (SPC.alicornSetup);
--   co-op: SAL's boat and the searchlights the host's allies (allyUnit); the host's "rnd" field 15 (F) and a joiner's
--     RUN.arcF from it; SUB.say in the host's round logic sent as "sb", SUB.sayHere never, a joiner's "sb" with its guards;
--     "fh" / "fsx" / "fw" / "fwe" to FISH.fromHost; COOP.payOwn never split or sent as "cr"; COOP.removeObj's "dn|<id>|r".
local MOD, WORK = arg[1], arg[2]
local fails = 0
local function check(ok, what) if ok then print("  ok   " .. what) else print("  FAIL " .. what); fails = fails + 1 end end
local function readAll(p) local f = assert(io.open(p, "rb")); local s = f:read("a"); f:close(); return s end
local PARTS = dofile("parts.lua")(MOD, readAll)            -- (a part and its pieces: tools/checks/parts.lua)
local function writeAll(p, s) local f = assert(io.open(p, "wb")); f:write(s); f:close() end
do
    local rawOpen = io.open
    io.open = function(p, m) return rawOpen((tostring(p):gsub("\\", "/")), m) end
end
writeAll(WORK .. "/config/survival.default.ini", readAll(MOD .. "/config/survival.default.ini"))
local clock = 1000
os.clock = function() return clock end           -- luacheck: ignore

VERSION = "0.74.0-arc.test"
local FNm = { __index = { ToString = function(self) return self.s end }, __tostring = function(self) return self.s end }
function FName(s) return setmetatable({ s = tostring(s) }, FNm) end
local GI = { full = "GameInstance", addr = 1 }
function NotifyOnNewObject() end
function FindAllOf() return {} end
function FindFirstOf(c) if c == "BP_LiveGameInstance_C" then return GI end return nil end
function StaticFindObject() return nil end
local grounded = false
function playerOnAirfield() return grounded end
function airfieldTick() end
function bombTick() end
local events = {}
function SV_Event(name) events[#events + 1] = name; return 1 end
local alive = {}
function SV_UnitAlive(u) return alive[u] or 0 end
function SV_SetAircraft() return 1 end
function SV_SetLevel() return 1 end
function SV_Invert() return 1 end
local spawns = {}
function SV_Spawn(unit, x, y, z, yaw) spawns[#spawns + 1] = { unit = unit, x = x }; return 1 end
function SV_MenuChoice() return 0 end
function SV_CoopOpen() return 1 end
function SV_CoopClose() end
local sent, inbox = {}, {}
function SV_CoopSend(msg, rel, to) sent[#sent + 1] = tostring(to) .. ">" .. msg; return 1 end
function SV_CoopRecv() return table.remove(inbox, 1) or "" end
function SV_CoopInfo() return "open=1;state=linked;peers=1/linked/40/10/p" end
function SV_CoopMe() end
function SV_CoopReset() end
function SV_CoopTrack() return 1 end
function SV_CoopBind() return 1 end
function SV_CoopPeer() return 1 end
function SV_CoopPeerAt() return "" end
SETUP = { enemyX = function() return 1 end, specialsX = function() return 1 end, breakS = function() return 20 end,
          skillAdd = function() return 0 end }
local paid = {}
function addCredits(n, why) paid[#paid + 1] = { n = n, why = why } end

local function part(name, chunk, edits) PARTS.load(name, chunk, edits) end   -- (the part and its pieces, each edit in the piece with its text)
part("sv_core.lua", "@" .. WORK .. "/Scripts/sv_core.lua")
local logs = {}
local logFile = assert(io.open(WORK .. "/test_lua.log", "wb"))
function log(s) logs[#logs + 1] = s; logFile:write(os.date("%H:%M:%S ") .. s .. "\n") end
function valid(o) return type(o) == "table" and not o.gone end
function nameOf(o) return type(o) == "table" and (o.full or "?") or "?" end
function addrOf(o) return type(o) == "table" and o.addr or nil end
function liveAddr(o) return valid(o) and (addrOf(o) or 1) or nil end
svLevelOn = true
local FLAGS = {}
function svFlags() return FLAGS end
part("sv_config.lua")
part("sv_rows.lua"); part("sv_ai.lua"); part("sv_hud.lua"); part("sv_subs.lua"); part("sv_sky.lua")
part("sv_spawn.lua"); part("sv_anomalies.lua")
part("sv_rounds.lua", nil, { { "\nlocal function startRound%(%)", "\nfunction startRound()" } })
part("sv_alicorn.lua"); part("sv_amphib.lua"); part("sv_spaceport.lua"); part("sv_fishing.lua"); part("sv_festival.lua")
part("sv_tactical.lua"); part("sv_stats.lua"); part("sv_tells.lua"); part("sv_director.lua")
function addCredits(n, why) paid[#paid + 1] = { n = n, why = why } end   -- (sv_ai.lua's own: co-op wraps this one)
part("sv_coop.lua", nil, { { "\nlocal M = {", "\nM = {" } })
local M = _G.M
function playerOnAirfield() return grounded end
LB.stat, LB.special = function() end, function() end
presetName = function() return "standard", 3 end
ANOM.fx = ANOM.fx or {}
AMPH.runTick = AMPH.runTick or function() end
ALLY.fleetReady = true
math.randomseed(5)
local function found(pat) for i = #logs, 1, -1 do if logs[i]:find(pat, 1, true) then return logs[i] end end return nil end
local SP = CFG.specials

---------------------------------------------------------------------------------------------------- the dice
print("the specials' dice: GONE FISHIN', THE FESTIVAL, VALKA's gate")
RUN = newRun and newRun() or { credits = 0, bought = {}, kills = {} }
RUN.specialPick, RUN.specialAt = {}, {}
D = { round = 0, state = "wait", at = 0, now = 0, up = {}, flown = {}, queue = {}, spare = {} }
check(specialOn("fishing") and specialOn("festival"), "both kinds on")
local inRot = false
for _, k in ipairs(SP.rotation) do if k == "fishing" then inRot = true end; check(k ~= "festival", "THE FESTIVAL isn't in the rotation") end
check(inRot, "GONE FISHIN' in the rotation")
-- ((code review of 2026-11-07, finding 10) no round without the shoal's rows in the game's tables (FISH.setup at the main
-- menu), but a test key's forced one
FISH.rowsReady = nil
check(SPC.kinds.fishing.ready(6) == false and SPC.kinds.fishing.ready(6, true) == true
      and found("fishing: no GONE FISHIN' round: the shoal's rows aren't in the game's tables"),
      "not ready without the shoal's rows (forced: still), logged")
FISH.rowsReady = true
check(SPC.kinds.fishing.ready(6) == true and SP.fishing.from_round == 7, "GONE FISHIN' ready, from round 7")
RUN.fished = 7
check(SPC.kinds.fishing.ready(20) == false and SPC.kinds.fishing.ready(20, true) == true, "once a run (forced: still)")
RUN.fished = nil
-- ((code review of 2026-11-07, finding 5) a host by migration has the arc's F (the old host's "rnd" field 15) and no
-- RUN.fished: its run had its GONE FISHIN' too)
RUN.arcF = 9
check(SPC.kinds.fishing.ready(20) == false and SPC.kinds.fishing.ready(20, true) == true,
      "once a run: the arc's F alone (a host by migration) counts it as had (forced: still)")
RUN.arcF = nil
RUN.arcF = 7
check(specialFor(13) == "festival", "round 13 (F + 6) is THE FESTIVAL")
check(RUN.specialPick[13] == nil, "never rolled: no dice for it")
check(SPC.kinds.spaceport.ready(12) == false, "no Spaceport the round before THE FESTIVAL")
check(SPC.kinds.valka.ready(10) == false and SPC.kinds.valka.ready(18) == false and SPC.kinds.valka.ready(19) == true,
    "VALKA's gate: none from 7 to 18, she can come from 19")
check(SPC.kinds.valka.ready(nil) == true, "the bag's fill (no round): she stays in the bag")
D.round = 10
local okV, whyV = SPC.canStart("valka")
check(okV == false and whyV == "it can't come now", "SPC.canStart: VALKA can't start in round 10")
check(SPC.canStart("valka", "valka") == true, "her test key forces her through")
RUN.arcF = nil
check(SPC.kinds.valka.ready(10) == true, "no GONE FISHIN' this run: no gate")
-- the bag: GONE FISHIN' out once it's been
RUN.specialBag, RUN.fished = nil, 9
local okB = true
for _ = 1, 20 do
    RUN.specialPick, RUN.lastSpecial, RUN.specialGap = {}, nil, 10
    local k = specialFor(30)
    if k == "fishing" then okB = false end
end
check(okB, "once it's been, the dice never draw GONE FISHIN' again")
RUN.fished = nil

---------------------------------------------------------------------------------------------------- startRound
print("startRound: GONE FISHIN' and THE FESTIVAL rounds")
local function newD(round) D = { round = round, state = "wait", at = 0, now = 100, up = {}, flown = {}, queue = {}, spare = {}, startRound = 1 } end
RUN.arcF = nil
newD(7)
D.forceSpecial = "fishing"
startRound()
check(D.special and D.special.kind == "fishing" and D.waves and #D.waves == 1 and #D.waves[1] == 1 and D.waves[1][1] == "@fishing",
    "a GONE FISHIN' round: the special alone, no fighters")
RUN.arcF = 7
newD(12)
startRound()
check(D.special and D.special.kind == "festival" and D.waves[1][1] == "@festival" and #D.waves[1] == 1, "round 13: THE FESTIVAL, alone")
-- roundsTick's generic busy / over hold the round while the special runs
D.state, D.at, D.queue, D.waves, D.wave = "fighting", 0, {}, { {} }, 1
D.special.state = "raid"
local overs = 0
local rawOver, rawTick = SPC.kinds.festival.over, SPC.kinds.festival.tick
SPC.kinds.festival.over = function(...) overs = overs + 1 end
SPC.kinds.festival.tick = function() end
roundsTick(200)
check(D.state == "fighting", "the raid on: the round goes on (busy)")
D.special.state = "done"
roundsTick(201.5)
check(D.state == "wait" and overs == 1, "the raid done: the round clears, its over() once")
SPC.kinds.festival.over, SPC.kinds.festival.tick = rawOver, rawTick

---------------------------------------------------------------------------------------------------- the Alicorn's rows
print("the Alicorn's tables: THE FESTIVAL's searchlight rows judged apart")
local function dtStub(name, rows)
    local t = { full = name, addr = 77, rows = rows }
    function t:FindRow(r) return self.rows[tostring(r)] end
    function t:AddRow(r, v) self.rows[tostring(r)] = v end
    function t:GetRowNames() local o = {}; for k in pairs(self.rows) do o[#o + 1] = k end; table.sort(o); return o end
    return t
end
local tables = {}
for i, tp in ipairs(SP.alicorn.tables) do
    local from = {}
    from["SV_Alcn_Row_" .. i] = { r = i }
    if i == 1 then from.GR053_seli_01 = { r = 1 }; from.GR053_seli_light_01 = { r = 1 } end
    if i == 2 then from.GR053_seli = { r = 1 }; from.GR053_seli_light = { r = 1 } end
    if i == 3 then from.NWDID_GroundNPC = { r = 1 } end
    tables[tp[1]] = dtStub(tp[1], from)
    tables[tp[2]] = dtStub(tp[2], {})
end
local rawLoad = loadObject
loadObject = function(p) return tables[p] end
local rawDt = dtCall
dtCall = function(dt, m, ...)
    if m == "AddRow" and select(1, ...) == "GR053_seli_light" then return true, nil end   -- (that row won't go in)
    return pcall(dt[m], dt, ...)
end
local rawPin = pin
pin = function() return true end
SPC.alicornDone = nil
SPC.alicornSetup()
check(SPC.alicornReady == true, "a searchlight row that won't go in never turns the Alicorn round off")
check(SPC.festRows and SPC.festRows.have == 4 and SPC.festRows.lost[1] == "GR053_seli_light" and FEST.lightsReady() == false,
    "THE FESTIVAL's rows: 4 of 5, no searchlights (" .. tostring(SPC.festRows and SPC.festRows.have) .. ")")
check(found("THE FESTIVAL's searchlight rows (in the Alicorn's tables): 4 of 5 in (missing: GR053_seli_light: no searchlights)") ~= nil, "logged")
loadObject, dtCall, pin = rawLoad, rawDt, rawPin

---------------------------------------------------------------------------------------------------- co-op
print("co-op: allies, the rnd field, the strip, the catches, the pay")
check(COOP.allyUnit(SP.fishing.boat_unit) and COOP.allyUnit("SV_Unit_FestLight_3"), "SAL's boat and the searchlights: the host's allies")
check(not COOP.allyUnit("SV_Unit_FishA") and not COOP.allyUnit("SV_Unit_FestN"), "the shoals and the Tu-160s: enemies")
-- the host
CFG.coop.enabled = true
COOP.open, COOP.role, COOP.slot = true, "host", 0
RUN.arcF = 7
newD(9)
D.state = "fighting"
sent = {}
M.nextRnd = 0
clock = clock + 1
COOP.tick(0)
local rnd = nil
for _, x in ipairs(sent) do if x:find(">rnd|", 1, true) then rnd = x end end
local f = {}
for v in ((rnd or ""):gsub("^[^>]*>", "") .. "|"):gmatch("([^|]*)|") do f[#f + 1] = v end
check(rnd and f[15] == "7", "the host's rnd: field 15 is F (" .. tostring(rnd) .. ")")
sent = {}
M.mirror = 1
SUB.say("SAL", "The fish are hiding.", 4)
SUB.sayHere("SAL", "THAT IS MY BOAT!")
M.mirror = 0
SUB.say("SAL", "Outside the rounds.", 4)
local sbs = {}
for _, x in ipairs(sent) do if x:find(">sb|", 1, true) then sbs[#sbs + 1] = x end end
check(#sbs == 1 and sbs[1]:find("sb|SAL|The fish are hiding.|4.0", 1, true), "SUB.say in the host's rounds sent as sb; sayHere and outside the rounds not")
sent, paid = {}, {}
M.mirror = 1
COOP.payOwn(6120, "GONE FISHIN' weigh-in (A, 770 kg)")
addCredits(4000, "spaceport held")
M.mirror = 0
local crs = 0
for _, x in ipairs(sent) do if x:find(">cr|", 1, true) then crs = crs + 1 end end
check(paid[1] and paid[1].n == 6120 and crs == 1, "COOP.payOwn: paid whole here, never sent as cr (a special's pay still is)")
local o = { full = "BP_OP0039_slcmp_C_7", addr = 4242 }
M.byId[77] = { obj = o, unit = "SV_Unit_FestCM_N1", ord = 1, addr = 4242 }
M.units.SV_Unit_FestCM_N1 = { planes = { [1] = { id = 77 } }, ground = {} }
sent = {}
check(COOP.removeObj(o) == true and sent[1] and sent[1]:find("dn|77|r|", 1, true) and M.byId[77].dead and M.byId[77].killer == false,
    "COOP.removeObj: that one missile down on every game, unpaid (" .. tostring(sent[1]) .. ")")
-- a joiner
COOP.open, COOP.role, COOP.slot = true, "join", 2
RUN = newRun and newRun() or { credits = 0 }
newD(9)
clock = clock + 1
local rnd15 = "0|rnd|9|fighting|0.0|1|1|4|||||||;|7"
inbox[#inbox + 1] = rnd15
COOP.tick(0)
check(RUN.arcF == 7 and found("sky: arc: GONE FISHIN' at round 7") ~= nil, "a joiner's F from the host's rnd field 15")
inbox[#inbox + 1] = "0|rnd|9|fighting|0.0|1|1|4|||||||;|0"
COOP.tick(0)
check(RUN.arcF == nil, "field 15 = 0: no arc here")
inbox[#inbox + 1] = rnd15
COOP.tick(0)
SUB.clear("test")
survivalPC = { Pawn = { full = "BP_PlayerPlane_C_1", addr = 9 } }
M.readyAt = 0
inbox[#inbox + 1] = "0|sb|SAL|Hello? Air force?|3.5"
inbox[#inbox + 1] = "0|sb|SAL|" .. string.rep("x", 300) .. "|4"
inbox[#inbox + 1] = "0|sb|SAL|bad seconds|999"
COOP.tick(0)
check(#SUB.q >= 1 and SUB.q[1].text == "Hello? Air force?" and SUB.q[1].secs == 3.5, "the host's sb on the strip here")
local longOk, badDropped = false, true
for _, l in ipairs(SUB.q) do
    if l.text:match("^x+$") then longOk = #l.text == 160 end
    if l.text == "bad seconds" then badDropped = false end
end
check(longOk and badDropped, "its guards: a line cut to 160, seconds out of range dropped")
inbox[#inbox + 1] = "0|fh|2|tuna|64|1803753|-1160858"
inbox[#inbox + 1] = "0|fsx|fishing|fishing|80|12|400"
COOP.tick(0)
check(FISH.cl.haul[2] and FISH.cl.haul[2].kg == 64 and FISH.cl.rows.fishing and FISH.cl.rows.fishing.b == 12, "fh and fsx to FISH.fromHost")
inbox[#inbox + 1] = "0|fw|2|64|1|0|tuna|64|0"
inbox[#inbox + 1] = "0|fwe|3|500|0|9|24"
paid = {}
COOP.tick(0)
local wantPay = FISH.payFor(64, 3, 9, false)
check(paid[1] and paid[1].n == wantPay and paid[1].why:find("GONE FISHIN' weigh-in", 1, true), "fwe: the joiner's own haul paid (" .. tostring(paid[1] and paid[1].n) .. ")")
COOP.open, COOP.role, COOP.slot = false, nil, nil

logFile:close()
print(fails == 0 and "arc rounds test: all passed" or ("arc rounds test: " .. fails .. " FAILED"))
os.exit(fails == 0 and 0 or 1)
