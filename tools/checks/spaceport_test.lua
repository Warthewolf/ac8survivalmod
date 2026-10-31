-- spaceport_test.lua <mod dir> <work dir> (run by tools/checks/spaceport_test.sh): the Spaceport Assault and its retake
-- (Scripts/sv_spaceport.lua; tools/re/SPACEPORT_ASSAULT.md), on the real sv_core, sv_config, sv_rows, sv_ai, sv_spawn,
-- sv_anomalies, sv_rounds (startRound exposed), sv_amphib, sv_spaceport, sv_stats and sv_tells, the game stubbed:
--   SPORT.fleet: the build's 27 ships in its order (tools/survival_events.py sp_fleet: the Ford, each group's Wasp, Aegis
--     pair and boat pair, the Ford's ring), 14 Aegis;
--   SPORT.spawn: the fleet queued (fewer of a kind with ships.<kind> lower), spawn_per_tick ships every 0.5 s; refused
--     with a ship still up (RE_SV_SpFleetRemove);
--   the waves: each Wasp's first first_wave_s on, then every wave_every_s, the next free wave (V, W, ...); none from a
--     sunk Wasp; a craft's landing (SV_SpLand<g><w><c>) puts its troops ashore; their arrival (SV_SpAt<g><w><c>) adds
--     capture_per_troop %; they go in troop_stay_s later (RE_SV_SpTroopsRemove); the wave taken off remove_after_s after
--     its first landing (RE_SV_SpLcacRemove); craft and ships shot down paid;
--   100 %: captured (RUN.sport, the craft recalled), the round no longer busy, its end: the ships still afloat carried
--     over, SPACEPORT LOST; specialFor names the next round "retake";
--   the retake: the garrison (troops / per_unit units, 3 at most), the carried ships, busy until all are down, its reward;
--   held: every ship sunk, nothing coming in: the round ends, the reward, RUN.sport cleared;
--   the Ford's deck: first_s on, a free 2-ship off its bow (ahead_m along ford_cm's heading, alt_m up), max_up, none with
--     the Ford sunk;
--   startRound: a spaceport with its fleet still up is a normal round; the rounds' generic busy / over (roundsTick).
local MOD, WORK = arg[1], arg[2]
local fails = 0
local function check(ok, what) if ok then print("  ok   " .. what) else print("  FAIL " .. what); fails = fails + 1 end end
local function readAll(p) local f = assert(io.open(p, "rb")); local s = f:read("a"); f:close(); return s end
local function writeAll(p, s) local f = assert(io.open(p, "wb")); f:write(s); f:close() end
do                                    -- (the runtime's paths are Windows ones: SCRIPT_DIR .. "..\\config\\")
    local rawOpen = io.open
    io.open = function(p, m) return rawOpen((tostring(p):gsub("\\", "/")), m) end
end
writeAll(WORK .. "/config/survival.default.ini", readAll(MOD .. "/config/survival.default.ini"))

local clock = 1000
os.clock = function() return clock end           -- luacheck: ignore

-- the game's world, stubbed
VERSION = "0.73.38-spaceport.test"
local FNm = { __index = { ToString = function(self) return self.s end }, __tostring = function(self) return self.s end }
function FName(s) return setmetatable({ s = tostring(s) }, FNm) end
local GI = { full = "GameInstance", addr = 1 }
local onNew = {}
function NotifyOnNewObject(cls, f) onNew[#onNew + 1] = f end
function FindAllOf() return {} end
function FindFirstOf(c) if c == "BP_LiveGameInstance_C" then return GI end return nil end
function StaticFindObject() return nil end
local grounded = false
function playerOnAirfield() return grounded end
function airfieldTick() end
function bombTick() end
local events, eventR = {}, 1
local alive = {}
function SV_Event(name)
    events[#events + 1] = name
    if name == "RE_SV_SpFleetRemove" then for u in pairs(alive) do if u:find("^SV_Unit_Sp[AFBW]") then alive[u] = 0 end end end
    local u = name:match("^RE_SV_SpLcacRemove(%u%u)$")
    if u then alive["SV_Unit_SpLcac" .. u] = 0 end
    u = name:match("^RE_SV_SpTroopsRemove(%u%u%u)$")
    if u then alive["SV_Unit_SpTroops" .. u] = 0 end
    return eventR
end
function SV_UnitAlive(u) return alive[u] or 0 end
function SV_SetAircraft() return 1 end
function SV_SetLevel() return 1 end
function SV_Invert() return 1 end
local spawns = {}
local SIZE = function(u)
    if u:find("^SV_Unit_SpLcac") then return 2 end
    if u:find("^SV_Unit_SpGarrison") then return 4 end
    if u:find("^SV_Unit_Sp") then return 1 end
    return flightSize(u)
end
function SV_Spawn(unit, x, y, z, yaw)
    spawns[#spawns + 1] = { unit = unit, x = x, y = y, z = z, yaw = yaw }
    local n = SIZE(unit)
    alive[unit] = n
    if unit == "SV_Unit_SpFord" then
        local hull = { full = "BP_VE004_grfd_C_1" }
        function hull:K2_GetActorLocation() return { X = -2964629, Y = -26491, Z = 50 } end
        for _, f in ipairs(onNew) do f(hull) end
    end
    return n
end
SETUP = { enemyX = function() return 1 end, specialsX = function() return 1 end, breakS = function() return 20 end,
          skillAdd = function() return 0 end }
local callouts = {}

local function part(name, chunk, edits)
    local src = readAll(MOD .. "/Scripts/" .. name)
    for _, e in ipairs(edits or {}) do
        local n
        src, n = src:gsub(e[1], e[2], 1)
        assert(n == 1, name .. ": " .. e[1] .. " not found")
    end
    assert(load(src, chunk or ("=" .. name)))()
end
part("sv_core.lua", "@" .. WORK .. "/Scripts/sv_core.lua")
local logs = {}
local logFile = assert(io.open(WORK .. "/test_lua.log", "wb"))
function log(s) logs[#logs + 1] = s; logFile:write(os.date("%H:%M:%S ") .. s .. "\n") end
function valid(o) return type(o) == "table" and not o.gone end
function nameOf(o) return type(o) == "table" and o.full or "?" end
function addrOf(o) return type(o) == "table" and o.addr or nil end
local FLAGS = {}
function svFlags() return FLAGS end
part("sv_config.lua")
part("sv_rows.lua"); part("sv_ai.lua")
function hudCallout(text, sub, big) callouts[#callouts + 1] = { text = text, sub = sub, big = big } end
part("sv_spawn.lua"); part("sv_anomalies.lua")
part("sv_rounds.lua", nil, { { "\nlocal function startRound%(%)", "\nfunction startRound()" } })
part("sv_amphib.lua"); part("sv_spaceport.lua"); part("sv_stats.lua"); part("sv_tells.lua")
function playerOnAirfield() return grounded end
local credits = {}
function addCredits(n, why) credits[#credits + 1] = { n = n, why = why } end
LB.stat, LB.special = function() end, function() end
local flights = {}
function spawnFlight(u, maxLevel, pose) flights[#flights + 1] = { unit = u, pose = pose }; alive[u] = 2; D.up[u] = true; return 2 end
local SP, T = CFG.specials.spaceport, CFG.hud.text
local function since(from, pat) local n = 0; for i = from, #logs do if logs[i]:find(pat) then n = n + 1 end end; return n end
local function evs(pat) local t = {}; for _, e in ipairs(events) do if e:find(pat) then t[#t + 1] = e end end; return table.concat(t, ",") end
local function spawned(pat) local t = {}; for _, s in ipairs(spawns) do if s.unit:find(pat) then t[#t + 1] = s.unit end end; return t end
local function called(text) for _, c in ipairs(callouts) do if c.text == text then return c end end end
local function paid(pat) local n = 0; for _, c in ipairs(credits) do if tostring(c.why):find(pat) then n = n + c.n end end; return n end
local function fresh(round)
    alive, events, spawns, callouts, credits, flights, FLAGS, planes = {}, {}, {}, {}, {}, {}, {}, {}
    RUN = { kills = 0 }
    D = { round = round or 10, state = "fighting", now = 0, at = 0, up = {}, flown = {}, queue = {}, spare = {},
          events = {}, orders = {}, taken = {}, special = { kind = "spaceport", state = "pending" } }
    SPORT.fordActor = nil
end
local now = 0
local function run(s, from, to, every)           -- the special's tick every 0.25 s
    for t = from, to, every or 0.25 do now = t; D.now = t; SPORT.tick(t, s) end
end

---------------------------------------------------------------------------------------------------- the fleet
print("SPORT.fleet: the build's ships, in its order")
local fl = SPORT.fleet()
local kinds = {}
for _, sh in ipairs(fl) do kinds[sh.kind] = (kinds[sh.kind] or 0) + 1 end
check(#fl == 27 and kinds.ford == 1 and kinds.wasp == 4 and kinds.aegis == 14 and kinds.boat == 8,
    string.format("27 ships: 1 Ford, 4 Wasps, 14 Aegis, 8 boats (%d: %s / %s / %s / %s)", #fl, tostring(kinds.ford),
        tostring(kinds.wasp), tostring(kinds.aegis), tostring(kinds.boat)))
check(fl[1].unit == "SV_Unit_SpFord" and fl[2].unit == "SV_Unit_SpWaspA" and fl[3].unit == "SV_Unit_SpAegisA"
    and fl[4].unit == "SV_Unit_SpAegisB" and fl[5].unit == "SV_Unit_SpBoatA" and fl[7].unit == "SV_Unit_SpWaspB"
    and fl[22].unit == "SV_Unit_SpAegisI" and fl[27].unit == "SV_Unit_SpAegisN", "the order: Ford, Wasp A, Aegis A-B, boats A-B, Wasp B ..., the ring I-N")
-- (the build's own names: tools/survival_events.py writes the same patterns)
local se = readAll(MOD .. "/../../../tools/survival_events.py")
check(se:find("SV_Unit_SpLcac{g}{w}", 1, true) and se:find("SV_Unit_SpTroops{g}{w}{c}", 1, true)
    and se:find("SV_SpLand{g}{w}{c}", 1, true) and se:find("SV_SpAt{g}{w}{c}", 1, true)
    and se:find("SP_WAVES = 'VWXYZ'", 1, true) and se:find("SP_CRAFT = 'LR'", 1, true) and se:find("SP_GROUPS = 'ABCD'", 1, true)
    and se:find("SP_GARRISON = 'ABC'", 1, true) and se:find("RE_SV_SpLcacRemove{grp}{w}", 1, true)
    and se:find("RE_SV_SpTroopsRemove{grp}{w}", 1, true), "the build's names (survival_events.py SP_*) in step")

---------------------------------------------------------------------------------------------------- the assault
print("SPORT.spawn and the fleet's spawns")
fresh(10)
local s = D.special
check(SPORT.ready() == true, "ready with no ship up")
check(SPORT.spawn(0) == true and s.state == "assault" and #s.queue == 27, "spawned: the assault, 27 ships queued")
check(called(T.sp_go) ~= nil, "its callout")
run(s, 0, 0)
check(#spawned("^SV_Unit_Sp[FWAB]") == SP.spawn_per_tick, "spawn_per_tick ships in the first tick (" .. #spawned("^SV_Unit_Sp[FWAB]") .. ")")
run(s, 0.25, 5)
check(#s.queue == 0 and #spawned("^SV_Unit_Sp[FWAB]") == 27, "every ship spawned within 5 s (" .. #spawned("^SV_Unit_Sp[FWAB]") .. ")")
check(SPORT.shipsUp(s) == 27 and SPORT.busy(s), "27 ships up: the round busy")

print("the waves")
run(s, 5.25, SP.first_wave_s - 1)
check(#spawned("^SV_Unit_SpLcac") == 0, "no craft before first_wave_s")
run(s, SP.first_wave_s - 0.75, SP.first_wave_s + 1)
local w1 = spawned("^SV_Unit_SpLcac")
check(#w1 == 4 and w1[1]:sub(-1) == "V", "each Wasp's first wave at first_wave_s (" .. table.concat(w1, ",") .. ")")
check(called(T.sp_landing) ~= nil, "the craft's callout")
run(s, SP.first_wave_s + 1.25, SP.first_wave_s + SP.wave_every_s + 1)
local w2 = spawned("^SV_Unit_SpLcac")
check(#w2 == 8 and w2[5]:sub(-1) == "W", "a wave a Wasp every wave_every_s, the next free one (W)")
alive.SV_Unit_SpWaspB = 0                        -- Wasp B sunk
local t0 = SP.first_wave_s + SP.wave_every_s + 1
run(s, t0 + 0.25, t0 + 2)
check(paid("wasp sunk") > 0 and called(T.sp_wasp_down) ~= nil, "Wasp B sunk: paid and called out")
run(s, t0 + 2.25, t0 + SP.wave_every_s + 1)
local w3 = spawned("^SV_Unit_SpLcac")
local fromB = 0
for _, u in ipairs(w3) do if u:find("^SV_Unit_SpLcacB") then fromB = fromB + 1 end end
check(#w3 == 11 and fromB == 2, "no more waves from Wasp B (" .. #w3 .. " waves, " .. fromB .. " from B)")

print("a landing, its troops, the capture")
local L0 = #logs
FLAGS.SV_SpLandAVL = 1
run(s, now + 0.25, now + 1.25)                   -- (its looks are once a second)
check(#spawned("^SV_Unit_SpTroopsAVL$") == 1 and #s.troops == 1, "craft AV L landed: its troops ashore")
check(called(T.sp_ashore) ~= nil, "TROOPS ASHORE")
local tLand = now
FLAGS.SV_SpAtAVL = 1
run(s, now + 0.25, now + 3)
check(s.capture == SP.capture_per_troop and s.inside == 1, "at their spot: capture_per_troop % (" .. tostring(s.capture) .. ")")
check(called(T.sp_troops_in) ~= nil, "TROOPS AT THE SPACEPORT")
run(s, now + 0.25, now + SP.troop_stay_s + 1)
check(evs("^RE_SV_SpTroopsRemoveAVL$") ~= "" and #s.troops == 0, "gone in troop_stay_s later: taken off")
run(s, now + 0.25, tLand + SP.remove_after_s + 1)
check(evs("^RE_SV_SpLcacRemoveAV$") ~= "" and s.lanes.A.waves.V == nil, "the wave taken off remove_after_s after its first landing")
alive.SV_Unit_SpLcacCW = 1                       -- a craft of wave C W shot down
run(s, now + 0.25, now + 1)
check(paid("landing craft down") > 0, "a craft shot down: paid")

print("100 %: captured")
local ER = CFG.pool[1]                          -- (a pool flight of the round still up, and one queued)
D.up[ER], alive[ER] = true, 2
planes = { { unit = ER, obj = { full = "p" } } }
D.queue, D.state = { CFG.pool[2] }, "spawning"
s.capture = 100 - SP.capture_per_troop
FLAGS.SV_SpLandDXL = 1
for _ = 1, 25 do now = now + 0.25; SPORT.tick(now, s) end
FLAGS.SV_SpAtDXL = 1
for _ = 1, 25 do now = now + 0.25; SPORT.tick(now, s) end
check(s.captured and RUN.sport and RUN.sport.retakeRound == D.round + 1, "captured: the retake next round")
check(called(T.sp_captured) ~= nil, "SPACEPORT CAPTURED")
check(evs("^RE_SV_SpLcacRemove") ~= "", "the craft out recalled")
check(SPORT.busy(s) == false, "captured: the round no longer waits for the fleet")
check(evs("^RE_SV_FlightOff_%d%d$"):find(string.format("RE_SV_FlightOff_%02d", poolIndex(ER)), 1, true) and next(D.up) == nil
    and planes[1].down and #D.queue == 0 and D.state == "fighting",
    "the round's fighters fall back (its own and the deck's): RE_SV_FlightOff_NN each, D.up empty, marked down, the queue dropped (" .. evs("^RE_SV_FlightOff") .. ")")
local before = #spawned("^SV_Unit_SpLcac")
run(s, now + 0.25, now + SP.wave_every_s + 5)
check(#spawned("^SV_Unit_SpLcac") == before, "no more waves once captured")
SPORT.roundOver(now, s)
local carried = 0
for _ in pairs(RUN.sport.ships) do carried = carried + 1 end
check(carried == 26 and s.state == "done" and called(T.sp_lost) ~= nil, "its end: 26 ships carried over, SPACEPORT LOST (" .. carried .. ")")
check(specialFor(D.round + 1) == "retake", "specialFor: the next round is the retake")

print("the retake")
local rs = RUN.sport
D.round = D.round + 1
D.special = { kind = "retake", state = "pending" }
spawns, callouts, credits = {}, {}, {}
RUN.sport.troops = 9
check(SPORT.retakeSpawn(now) == true and D.special.state == "retake", "the retake spawned")
local s2 = D.special
check(#spawned("^SV_Unit_SpGarrison") == 3, "9 troops in: 3 garrison units (" .. #spawned("^SV_Unit_SpGarrison") .. ")")
check(SPORT.shipsUp(s2) == 26 and RUN.sport == nil, "the 26 ships carried, RUN.sport used up")
check(called(T.sp_retake_go) ~= nil, "SPACEPORT RETAKE")
check(SPORT.retakeBusy(s2), "busy while the garrison and ships are up")
for u in pairs(alive) do if u:find("^SV_Unit_SpGarrison") then alive[u] = 0 end end
for u in pairs(rs.ships) do alive[u] = 0 end
alive.SV_Unit_SpFord = 0
for _ = 1, 8 do now = now + 0.25; SPORT.retakeTick(now, s2) end
check(not SPORT.retakeBusy(s2) and paid("garrison") > 0, "all down: not busy, the garrison paid")
SPORT.retakeOver(now, s2)
check(paid("spaceport retaken") > 0 and called(T.sp_retaken) ~= nil, "its end: the reward, SPACEPORT RETAKEN")
fresh(12)
D.special = { kind = "retake", state = "pending" }
check(SPORT.retakeSpawn(0) == true and #spawned("^SV_Unit_SpGarrison") == 2, "forced (no RUN.sport): test_troops 8: 2 garrison units")

print("held")
fresh(10)
s = D.special
SP.ships.aegis = 2
SPORT.spawn(0)
check(#s.queue == 1 + 4 + 2 + 8, "ships.aegis = 2: only 2 Aegis queued (" .. #s.queue .. ")")
SP.ships.aegis = 14
run(s, 0, 5)
for u in pairs(alive) do if u:find("^SV_Unit_Sp[FWAB]") then alive[u] = 0 end end
run(s, 5.25, 7)
check(not SPORT.busy(s), "every ship sunk, nothing coming in: not busy")
SPORT.roundOver(7, s)
check(paid("spaceport held") == SP.reward + SP.reward_per_round * 10 and RUN.sport == nil and called(T.sp_held) ~= nil,
    "held: reward + reward_per_round x the round, RUN.sport nil, SPACEPORT HELD")

print("the Ford's deck")
fresh(10)
s = D.special
SPORT.spawn(0)
run(s, 0, SP.deck.first_s - 1)
check(#flights == 0, "nothing before first_s")
run(s, SP.deck.first_s - 0.75, SP.deck.first_s + 1)
check(#flights == 1 and flights[1].pose and flights[1].pose.z == 50 + SP.deck.alt_m * 100, "first_s on: a flight off the deck, alt_m up")
local fp = flights[1].pose
local yaw = math.rad(SP.ford_cm[3])
check(fp and math.abs(fp.x - (-2964629 + math.cos(yaw) * SP.deck.ahead_m * 100)) < 1, "ahead_m off its bow along its heading")
run(s, SP.deck.first_s + 1.25, SP.deck.first_s + SP.deck.every_s + 1)
check(#flights == 2, "the next every_s later")
run(s, SP.deck.first_s + SP.deck.every_s + 1.25, SP.deck.first_s + 3 * SP.deck.every_s)
check(#flights == SP.deck.max_up, "never more than max_up up (" .. #flights .. ")")
for _, f in ipairs(flights) do alive[f.unit] = 0; D.up[f.unit] = nil end
alive.SV_Unit_SpFord = 0
local nf = #flights
run(s, now + 0.25, now + 3 * SP.deck.every_s)
check(#flights == nf, "the Ford sunk: no more")

print("startRound: its fleet still up")
fresh(10)
alive.SV_Unit_SpAegisC = 1
D.forceSpecial, D.state = "spaceport", "wait"
local okR, errR = pcall(startRound)
check(okR and D.special == nil, "a spaceport with a ship still up: a normal round (" .. tostring(errR) .. ")")

print("roundsTick: the generic busy and round end")
fresh(10)
s = D.special
SPORT.spawn(0)
run(s, 0, 5)
D.state, D.at, D.up = "fighting", 0, {}
local okT, errT = pcall(roundsTick, 6)
check(okT and D.state == "fighting", "ships up, no flights: the round goes on (" .. tostring(errT) .. ")")
for u in pairs(alive) do alive[u] = 0 end
D.at = 0
okT, errT = pcall(roundsTick, 8)
check(okT and D.state == "wait" and s.state == "done" and called(T.sp_held) ~= nil, "all sunk: the round ends, its over (" .. tostring(errT) .. ")")

print(fails == 0 and "spaceport test: all passed" or ("spaceport test: " .. fails .. " FAILED"))
os.exit(fails == 0 and 0 or 1)
