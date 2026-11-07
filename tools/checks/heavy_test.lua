-- heavy_test.lua <mod dir> <work dir> (run by tools/checks/heavy_test.sh): the heavy bombers' routes and the jammer's
-- ECM pod (0.72.1; the user's run of 2026-10-29: "tu-95's aren't attacking the base, they fly around nearby and do
-- nothing", "the EA-18G never activated it's ECM"), on the real sv_core, sv_config, sv_rows, sv_ai, sv_hud, sv_spawn,
-- sv_rounds and sv_flights, the game stubbed:
--   HEAVY.route: the compass sector of where the flight spawned (north -y, east +x), RE_SV_HeavyRoute_<NN><S> queued
--     route_delay_s on, its BOMBERS index; nothing with heavy_route off;
--   bombTick: the lead shot down, the next of its flight up takes the loop (RE_SV_HeavyLoop_<NN><L><S>, logged), once;
--     the whole flight down, nothing more;
--   JAM.tick: the jammer up and leading, RE_SV_JamEcm_NN at once and every ecm_every_s (its first answer logged); nothing
--     with ecm off; a jammer that isn't its flight's lead logged, no pod;
--   the build's sectors and names in step (survival_events.HEAVY_SECTORS, the formats it asserts).
local MOD, WORK = arg[1], arg[2]
local fails = 0
local function check(ok, what) if ok then print("  ok   " .. what) else print("  FAIL " .. what); fails = fails + 1 end end
local function readAll(p) local f = assert(io.open(p, "rb")); local s = f:read("a"); f:close(); return s end
local PARTS = dofile("parts.lua")(MOD, readAll)            -- (a part and its pieces: tools/checks/parts.lua)
local function writeAll(p, s) local f = assert(io.open(p, "wb")); f:write(s); f:close() end
do                                    -- (the runtime's paths are Windows ones: SCRIPT_DIR .. "..\\config\\")
    local rawOpen = io.open
    io.open = function(p, m) return rawOpen((tostring(p):gsub("\\", "/")), m) end
end
writeAll(WORK .. "/config/survival.default.ini", readAll(MOD .. "/config/survival.default.ini"))

local clock = 1000
os.clock = function() return clock end           -- luacheck: ignore

-- the game's world, stubbed
VERSION = "0.72.1-heavy.test"
local FNm = { __index = { ToString = function(self) return self.s end }, __tostring = function(self) return self.s end }
function FName(s) return setmetatable({ s = tostring(s) }, FNm) end
local GI = { full = "GameInstance", addr = 1 }
function NotifyOnNewObject() end
function FindAllOf() return {} end
function FindFirstOf(c) if c == "BP_LiveGameInstance_C" then return GI end return nil end
function StaticFindObject() return nil end
function playerOnAirfield() return false end
local events, eventR = {}, 1
function SV_Event(name) events[#events + 1] = name; return eventR end
function SV_UnitAlive() return 0 end
function SV_SetAircraft() return 1 end
function SV_SetLevel() return 1 end
function SV_Spawn() return 1 end
SETUP = { enemyX = function() return 1 end, specialsX = function() return 1 end, breakS = function() return 20 end,
          skillAdd = function() return 0 end }

local function part(name, chunk) PARTS.load(name, chunk) end   -- (the part and its pieces)
part("sv_core.lua", "@" .. WORK .. "/Scripts/sv_core.lua")
local logs = {}
local logFile = assert(io.open(WORK .. "/test_lua.log", "wb"))
function log(s) logs[#logs + 1] = s; logFile:write(os.date("%H:%M:%S ") .. s .. "\n") end
function valid(o) return type(o) == "table" and not o.gone end
function nameOf(o) return type(o) == "table" and (o.full or "?") or "?" end
part("sv_config.lua")
part("sv_rows.lua"); part("sv_ai.lua"); part("sv_hud.lua"); part("sv_spawn.lua"); part("sv_rounds.lua")
part("sv_flights.lua")
local function since(from, pat) local n = 0; for i = from, #logs do if logs[i]:find(pat) then n = n + 1 end end; return n end
local function evs(pat) local t = {}; for _, e in ipairs(events) do if e:find(pat) then t[#t + 1] = e end end; return table.concat(t, ",") end
local function fresh()
    planes, events = {}, {}
    D = { round = 6, state = "fighting", now = 100, up = {}, flown = {}, queue = {}, events = {}, orders = {}, heavy = {} }
end
local function plane(unit, k, model)
    local p = { unit = unit, k = k, name = "BP_OP0011_" .. (model or "tu95") .. "_CP_C_" .. (100 + k),
                obj = { full = "x" }, at = { X = 0, Y = 0, Z = 200000 }, born = D.now }   -- (born: sv_core.lua logPlane's)
    function p.obj:K2_GetActorLocation() return { X = AIRFIELD.X + 2000000, Y = AIRFIELD.Y, Z = 200000 } end
    planes[#planes + 1] = p
    return p
end
local H1, H2 = CFG.airfield.bombers.heavy_units[1], CFG.airfield.bombers.heavy_units[2]

---------------------------------------------------------------------------------------------------- HEAVY.route
print("HEAVY.route: the sector of where the flight spawned")
local function at(bearing, km)                    -- a point km out at a compass bearing (north -y, east +x)
    local b = math.rad(bearing)
    return AIRFIELD.X + km * 100000 * math.sin(b), AIRFIELD.Y - km * 100000 * math.cos(b)
end
local n1 = BOMBER_INDEX[H1]
for _, c in ipairs({ { 0, "A" }, { 44, "B" }, { 91, "C" }, { 180, "E" }, { 200, "E" }, { 247, "F" }, { 250, "G" }, { 316, "H" }, { 340, "A" } }) do
    fresh()
    local x, y = at(c[1], 30)
    HEAVY.route(H1, x, y)
    local q = D.events[1]
    check(q and q.name == string.format("RE_SV_HeavyRoute_%02d%s", n1, c[2]) and math.abs(q.at - (100 + CFG.airfield.bombers.route_delay_s)) < 1e-6
          and D.heavyPath[H1].s == c[2] and D.heavyPath[H1].k == 0,
          string.format("bearing %d: sector %s (%s)", c[1], c[2], q and q.name or "nothing queued"))
end
fresh()
CFG.airfield.bombers.heavy_route = false
HEAVY.route(H1, at(270, 30))
check(#D.events == 0 and not D.heavyPath, "heavy_route off: no route")
CFG.airfield.bombers.heavy_route = true

---------------------------------------------------------------------------------------------------- the lead's handover
print("bombTick: the lead shot down, the next aircraft up takes the loop")
fresh()
local n2 = BOMBER_INDEX[H2]
D.heavy[H2] = true
HEAVY.route(H2, at(270, 30))
local a, b, c = plane(H2, 0, "t160"), plane(H2, 1, "t160"), plane(H2, 2, "t160")
local from = #logs + 1
bombTick(2)
check(evs("HeavyLoop") == "", "the lead flying: nothing")
a.down = true
bombTick(6)
check(evs("HeavyLoop") == string.format("RE_SV_HeavyLoop_%02dBG", n2) and D.heavyPath[H2].k == 1
      and since(from, "lead down: object 1 takes the loop") == 1, "lead down: object 1 (B) on the loop, logged")
bombTick(10)
check(evs("HeavyLoop") == string.format("RE_SV_HeavyLoop_%02dBG", n2), "and only once")
b.down, c.down = true, true
bombTick(14)
check(not D.heavyPath[H2] and evs("HeavyLoop") == string.format("RE_SV_HeavyLoop_%02dBG", n2), "the whole flight down: nothing more")

-- ((review of 27097b9, finding 0) a fresh spawn's planes reach `planes` ~2 ticks after it (sv_main.lua's pending, then
-- logPlane), and bombTick can run first: its entry is kept until one of them is seen (5 s at most), and a plane of the
-- flight's last spawn the sweep hasn't marked down yet isn't taken for this one's (born before it)
print("bombTick: a fresh spawn's route kept until its planes are seen")
fresh()
D.heavy[H2] = true
HEAVY.route(H2, at(270, 30))                      -- (D.now 100; its planes still pending)
bombTick(2)
check(D.heavyPath[H2] and D.heavyPath[H2].k == 0 and evs("HeavyLoop") == "",
      "its planes not yet seen: the entry kept (0.73.80: dropped, so no handover when its lead went down)")
D.now = 100.5
local f1, f2 = plane(H2, 0, "t160"), plane(H2, 1, "t160")
plane(H2, 2, "t160")
bombTick(6)
check(evs("HeavyLoop") == "" and D.heavyPath[H2], "its planes seen, the lead up: nothing")
f1.down = true
from = #logs + 1
bombTick(10)
check(evs("HeavyLoop") == string.format("RE_SV_HeavyLoop_%02dBG", n2) and D.heavyPath[H2].k == 1
      and since(from, "lead down: object 1 takes the loop") == 1, "then its lead down: object 1 (B) on the loop")
fresh()
D.heavy[H2] = true
D.now = 90
local old = plane(H2, 3, "t160")                  -- (the last spawn's object 3: down, not yet seen so by the sweep)
D.now = 100
HEAVY.route(H2, at(0, 30))
bombTick(2)
check(evs("HeavyLoop") == "" and D.heavyPath[H2] and D.heavyPath[H2].k == 0,
      "the last spawn's plane not yet swept down: not this spawn's, no handover to its object 3 (" .. evs("HeavyLoop") .. ")")
old.down = true
D.now = 100.5
local g1, g2 = plane(H2, 0, "t160"), plane(H2, 1, "t160")
g1.down = true
bombTick(6)
check(evs("HeavyLoop") == string.format("RE_SV_HeavyLoop_%02dBA", n2) and D.heavyPath[H2].k == 1 and not g2.down,
      "this spawn's lead down: its object 1 (B) on the loop (" .. evs("HeavyLoop") .. ")")
fresh()
D.heavy[H2] = true
HEAVY.route(H2, at(90, 30))
D.now = 104
bombTick(2)
check(D.heavyPath[H2], "no plane seen 4 s on: still kept")
D.now = 106
bombTick(6)
check(not D.heavyPath[H2] and evs("HeavyLoop") == "", "none ever seen, 6 s on: dropped")

---------------------------------------------------------------------------------------------------- the jammer's pod
print("JAM.tick: the jammer's ECM pod")
local POOL1 = CFG.pool[1]
local idx = poolIndex(POOL1)
local function jam(k)
    fresh()
    D.jammer = { unit = POOL1 }
    local j = plane(POOL1, k, "e18g")
    j.name = "BP_OP1010_e18g_CP_C_" .. (200 + k)
    j.at = { X = 0, Y = 0, Z = 200000 }
    return j
end
jam(0)
from = #logs + 1
JAM.tick()
check(evs("JamEcm") == string.format("RE_SV_JamEcm_%02d", idx) and since(from, "its ECM pod on %(RE_SV_JamEcm") == 1,
      "up and leading: its pod on at once, logged")
D.now = 108; JAM.tick()
check(evs("JamEcm") == string.format("RE_SV_JamEcm_%02d", idx), "not again within ecm_every_s")
D.now = 100 + CFG.jammer.ecm_every_s; JAM.tick()
check(select(2, evs("JamEcm"):gsub("JamEcm", "")) == 2 and since(from, "its ECM pod on") == 1, "again after ecm_every_s, not logged again")
eventR = -3
D.now = 100 + 2 * CFG.jammer.ecm_every_s; JAM.tick()
check(since(from, "not fired: ") == 1, "an answer that isn't 1: logged")
eventR = 1
jam(0)
CFG.jammer.ecm = false
JAM.tick()
check(evs("JamEcm") == "", "ecm off: no pod")
CFG.jammer.ecm = true
jam(1)
from = #logs + 1
JAM.tick()
check(evs("JamEcm") == "" and since(from, "isn't its flight's lead") == 1, "not its flight's lead: no pod, logged")
-- ((2026-11-07) the user: "The Enemy EA-18G Growlers are not using ECM against the players": a first look before the
-- sweep had read its position dropped the jammer for the round, its pod never on)
do
    local j = jam(0)
    j.at = nil                                         -- (logPlane's new plane: no position yet)
    local near = plane(CFG.pool[2] or POOL1, 0, "f18e")
    near.rankSet = 2
    near.obj.PilotRank = 2
    near.at = { X = AIRFIELD.X + 2000000 + 50000, Y = AIRFIELD.Y, Z = 200000 }
    JAM.tick()
    check(D.jammer ~= nil and j.at ~= nil and evs("JamEcm") == string.format("RE_SV_JamEcm_%02d", idx),
          "found before the sweep read its position: its position read, its pod on, the jammer kept")
    check(near.jammed == true and near.obj.PilotRank == math.min(5, 2 + CFG.jammer.rank_add), "... and the enemy beside it sharpened")
    local j2 = jam(0)
    j2.at = nil
    function j2.obj:K2_GetActorLocation() error("not readable") end
    JAM.tick()
    check(D.jammer ~= nil and evs("JamEcm") ~= "", "its position not readable: kept, its pod on anyway")
    D.now = 100 + CFG.jammer.ecm_every_s
    j2.at = { X = 0, Y = 0, Z = 200000 }
    j2.down = true
    JAM.tick()
    check(D.jammer == nil, "down: dropped")
end
-- ((0.74.12) the user: "enemy EA-18G that spawned in just then still doesn't use ECM": RE_SV_JamEcm fired, nothing said
-- whether its pod jammed) ecm_check_s after each firing its own pod is made to jam (on, on until the next firing, its
-- reach x ecm_range_x once), logged once; another plane's pod untouched; none of its own up: said once
do
    local j = jam(0)
    j.obj.GetAddress = function() return 4100 end
    local function pod(n, owner)
        local w = { full = "BP_wp_ecm_a0_C /Game/Maps/PL_SurvivalMode.x:BP_wp_ecm_a0_C_" .. n, bJammingEnable = false,
                    JammingEffectRangeMeter = 2000, EffectRangeMeter = 2000, JammingTimeCampaign = 5 }
        w.GetAddress = function() return 4200 + n end
        w.GetOwner = function() return owner end
        w.GetInstigator = function() return nil end
        return w
    end
    local otherPlane = { full = "y", GetAddress = function() return 4300 end }
    local mine, theirs = pod(1, j.obj), pod(2, otherPlane)
    JAM.pods = { mine, theirs }
    from = #logs + 1
    JAM.tick()
    check(evs("JamEcm") ~= "" and mine.bJammingEnable == false, "fired; its pod not touched before ecm_check_s")
    D.now = D.now + CFG.jammer.ecm_check_s + 0.1
    JAM.tick()
    check(mine.bJammingEnable == true and mine.JammingTimeCampaign == CFG.jammer.ecm_every_s + 2
          and mine.JammingEffectRangeMeter == 2000 * CFG.jammer.ecm_range_x and theirs.bJammingEnable == false
          and theirs.JammingEffectRangeMeter == 2000, "its own pod made to jam (on, held to the next firing, its reach scaled), another's untouched")
    check(since(from, "its ECM pod made to jam: BP_wp_ecm_a0_C_1: jamming false, 2000 m, 5 s %-> jamming true, 3000 m, 16 s") == 1,
          "logged with what it read")
    D.now = D.now + CFG.jammer.ecm_every_s
    JAM.tick()
    D.now = D.now + CFG.jammer.ecm_check_s + 0.1
    mine.bJammingEnable = false
    JAM.tick()
    check(mine.bJammingEnable == true and mine.JammingEffectRangeMeter == 2000 * CFG.jammer.ecm_range_x and since(from, "made to jam") == 1,
          "the next firing: on again, its reach scaled once only, not logged again")
    local j2 = jam(0)
    j2.obj.GetAddress = function() return 4400 end
    JAM.pods = { theirs }
    from = #logs + 1
    JAM.tick()
    D.now = D.now + CFG.jammer.ecm_check_s + 0.1
    JAM.tick()
    check(since(from, "no ECM pod of its own up") == 1 and theirs.bJammingEnable == false, "none of its own up: said, nothing touched")
end

---------------------------------------------------------------------------------------------------- the raid's minimap pings
-- (user, 2026-10-31: "an alert that pings the aircraft via the minimap that are attacking the airfield")
print("raidPings: each bomber flight near the airfield pinged on the minimap")
do
    local function count(pat) local n = 0; for _, e in ipairs(events) do if e:find(pat) then n = n + 1 end end; return n end
    local S1 = CFG.airfield.bombers.pool[1]
    local pg = CFG.airfield.bombers.ping
    fresh()
    D.up[S1], D.up[H1] = true, true
    plane(S1, 0, "su34"); plane(H1, 0, "tu95")          -- (both 20 km out)
    local from = #logs + 1
    bombTick(2)
    check(count(string.format("^RE_SV_RaidPing_%02d$", BOMBER_INDEX[S1])) == 1 and count(string.format("^RE_SV_RaidPing_%02d$", BOMBER_INDEX[H1])) == 1
          and since(from, "pinged on the minimap, 20.0 km from the airfield") == 2, "a strike and a heavy flight 20 km out: each pinged, logged once")
    bombTick(6); bombTick(46)
    check(count("^RE_SV_RaidPing_") == 2, "not again within every_s (" .. pg.every_s .. " s)")
    bombTick(50)
    check(count("^RE_SV_RaidPing_") == 4 and since(from, "pinged on the minimap") == 2, "every_s on: both again (logged only the first time)")
    fresh()
    D.up[S1] = true
    D.shipStrike = { [S1] = "SV_Unit_ShipAegisA" }
    plane(S1, 0, "su34")
    bombTick(2)
    check(count("^RE_SV_RaidPing_") == 0, "a flight sent at an allied ship: not pinged (it isn't attacking the airfield)")
    fresh()
    D.up[S1] = true
    local far = plane(S1, 0, "su34")
    function far.obj:K2_GetActorLocation() return { X = AIRFIELD.X + (pg.within_km + 5) * 100000, Y = AIRFIELD.Y, Z = 200000 } end
    bombTick(2)
    check(count("^RE_SV_RaidPing_") == 0, "farther than within_km (" .. pg.within_km .. " km): not pinged")
    fresh()
    D.up[S1] = true
    plane(S1, 0, "su34")
    local rawCoop = COOP
    COOP = { client = function() return true end }
    bombTick(2)
    check(count("^RE_SV_RaidPing_") == 0, "a co-op joiner: none of its own (the host's are forwarded)")
    COOP = rawCoop
    pg.enabled = false
    bombTick(6)
    check(count("^RE_SV_RaidPing_") == 0, "[bombers.ping] enabled = false: none")
    pg.enabled = true
end

---------------------------------------------------------------------------------------------------- the build in step
print("the build's sectors and names")
do
    local ev = readAll(MOD .. "/../../../tools/survival_events.py")
    check(ev:find('HEAVY_SECTORS = \'' .. HEAVY_SECTORS .. '\'', 1, true) ~= nil, "survival_events.HEAVY_SECTORS is sv_flights' " .. HEAVY_SECTORS)
    check(ev:find("RE_SV_HeavyRoute_{n:02d}{s}", 1, true) and ev:find("RE_SV_HeavyLoop_{H[\"n\"]:02d}{chr(65 + j)}{H[\"sector\"]}", 1, true)
          and ev:find("RE_SV_JamEcm_{k + 1:02d}", 1, true) and ev:find("ping = f'RE_SV_RaidPing_{k + 1:02d}'", 1, true),
          "the build makes the events Lua fires")
end

print(fails == 0 and "heavy test: all passed" or ("heavy test: " .. fails .. " FAILED"))
logFile:close()
os.exit(fails == 0 and 0 or 1)
