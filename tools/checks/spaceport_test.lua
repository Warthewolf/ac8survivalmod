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
    if name == "RE_SV_SpIslandRemove" then for u in pairs(alive) do if u:find("^SV_Unit_SpIsl") then alive[u] = 0 end end end
    if name == "RE_SV_SpRocketRemove" then for _, d in ipairs({ "SV_Unit_SpRockets", "SV_Unit_SpDebriA", "SV_Unit_SpDebriB", "SV_Unit_SpDebriC" }) do alive[d] = 0 end end
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
    if u == "SV_Unit_SpRockets" or u:find("^SV_Unit_SpDebri") then return 2 end
    if u == "SV_Unit_SpIslExsam" or u == "SV_Unit_SpIslAA" then return 5 end
    if u:find("^SV_Unit_SpIsl") then return 4 end
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
function liveAddr(o) return valid(o) and (addrOf(o) or 1) or nil end   -- (sv_core liveAddr: the runtime's live check, here valid())
svLevelOn = true                                                         -- (sv_config: Survival's level loaded)
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
ALLY.fleetReady = true                           -- (the turrets' rows: sv_allies.lua ALLY.setup at the main menu)
local function since(from, pat) local n = 0; for i = from, #logs do if logs[i]:find(pat) then n = n + 1 end end; return n end
local function evs(pat) local t = {}; for _, e in ipairs(events) do if e:find(pat) then t[#t + 1] = e end end; return table.concat(t, ",") end
local function spawned(pat) local t = {}; for _, s in ipairs(spawns) do if s.unit:find(pat) then t[#t + 1] = s.unit end end; return t end
local function called(text) for _, c in ipairs(callouts) do if c.text == text then return c end end end
local function paid(pat) local n = 0; for _, c in ipairs(credits) do if tostring(c.why):find(pat) then n = n + c.n end end; return n end
local function fresh(round)
    alive, events, spawns, callouts, credits, flights, FLAGS, planes = {}, {}, {}, {}, {}, {}, {}, {}
    SP.tu160.enabled = false                     -- (the Tu-160s: their own section, at the end)
    RUN = { kills = 0 }
    D = { round = round or 10, state = "fighting", now = 0, at = 0, up = {}, flown = {}, queue = {}, spare = {},
          events = {}, orders = {}, taken = {}, special = { kind = "spaceport", state = "pending" } }
    SPORT.fordActor = nil
    SPORT.shipObjs, SPORT.rkObjs, SPORT.hostRow = {}, {}, nil      -- ((0.73.77) the objects as SV_Spawn makes them)
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
-- ((0.73.80) the craft's unit count read from its kept SV_UnitAlive answer (sv_spawn.lua ALIVE): up to a second old,
-- asked again in turn, so the pay within 2 s)
run(s, now + 0.25, now + 2)
check(paid("landing craft sunk") > 0, "a craft shot down: paid")
-- ((0.73.77, I2: S3) its reason isn't one sv_coop.lua's addCredits keeps from the joiners: " down (", a plane kill)
local craftWhy = nil
for _, c in ipairs(credits) do if tostring(c.why):find("landing craft") then craftWhy = c.why end end
check(craftWhy and not craftWhy:find(" down %("), "the craft's pay reaches the joiners: no \" down (\" in its reason (" .. tostring(craftWhy) .. ")")

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
check(D.spWithdrawn and D.spWithdrawn[ER], "(0.73.77, I4) the withdrawn flight kept for the next round's plan (D.spWithdrawn)")
local before = #spawned("^SV_Unit_SpLcac")
run(s, now + 0.25, now + SP.wave_every_s + 5)
check(#spawned("^SV_Unit_SpLcac") == before, "no more waves once captured")
SPORT.roundOver(now, s)
local carried = 0
for _ in pairs(RUN.sport.ships) do carried = carried + 1 end
check(carried == 26 and s.state == "done" and called(T.sp_lost) ~= nil, "its end: 26 ships carried over, SPACEPORT LOST (" .. carried .. ")")
check(specialFor(D.round + 1) == "retake", "specialFor: the next round is the retake")

print("the retake")
SP.retake.rockets.enabled = false                -- (the rockets and the island: their own sections below)
SP.retake.island.enabled = false
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
SP.retake.rockets.enabled = true

print("the retake's island enemies")
fresh(12)
D.special = { kind = "retake", state = "pending" }
SP.retake.island.enabled, SP.retake.rockets.enabled = true, false
check(SPORT.retakeSpawn(0) == true and #spawned("^SV_Unit_SpIsl") == 7, "7 island units spawned (" .. #spawned("^SV_Unit_SpIsl") .. ")")
local si = D.special
for u in pairs(alive) do if u:find("^SV_Unit_SpGarrison") then alive[u] = 0 end end
for _ = 1, 4 do now = now + 0.5; SPORT.retakeTick(now, si) end
check(SPORT.retakeBusy(si) and since(1, "the island's defences and armour: Exsam 5 up") >= 1, "busy while the island's enemies are up; logged")
alive.SV_Unit_SpIslExsam, alive.SV_Unit_SpIslTankA = 2, 1
now = now + 1; SPORT.retakeTick(now, si)
check(paid("air defences: one down") > 0 and paid("armour: one down") > 0, "an EXSAM down and a tank down: each paid by its kind")
for u in pairs(alive) do if u:find("^SV_Unit_SpIsl") then alive[u] = 0 end end
now = now + 1; SPORT.retakeTick(now, si)
check(not SPORT.retakeBusy(si), "all down: not busy")
SPORT.retakeOver(now, si)
check(evs("^RE_SV_SpIslandRemove$") ~= "", "its end: the island's units taken off")
check(SPC.kinds.retake.budget(20) == math.floor((20 * SP.retake.fighter_share + SP.retake.extra_aircraft) / 2 + 0.5) * 2,
      "the retake's aircraft: fighter_share + extra_aircraft (" .. SPC.kinds.retake.budget(20) .. " of 20)")
SP.retake.rockets.enabled = true
SP.retake.island.enabled = false                 -- (the rockets alone below)

print("the retake's rockets")
local RK = SP.retake.rockets
local function rtick(s, from, to) for t = from, to, 0.5 do now = t; D.now = t; SPORT.retakeTick(t, s) end end
local function retakeWithRockets()
    fresh(12)
    D.special = { kind = "retake", state = "pending" }
    RUN.credits = 20000
    check(SPORT.retakeSpawn(0) == true, "the retake spawned with its rockets")
    local s = D.special
    for u in pairs(alive) do if u:find("^SV_Unit_SpGarrison") then alive[u] = 0 end end
    return s
end
local s3 = retakeWithRockets()
check(alive.SV_Unit_SpRockets == 2 and alive.SV_Unit_SpDebriA == 2 and alive.SV_Unit_SpDebriC == 2 and s3.rk and s3.rk.n == 2,
      "both rockets and the 3 debris units spawned")
rtick(s3, 0, 3)
check(evs("^RE_SV_SpRocketSplitOff$") ~= "" and evs("^RE_SV_SpRocketLaunch") == "", "the split off at the start; nothing launched yet")
check(SPORT.retakeBusy(s3), "busy: the rockets on the pads (the garrison down)")
rtick(s3, 3.5, RK.launch_a_s + 0.5)
check(evs("^RE_SV_SpRocketLaunch") == "RE_SV_SpRocketLaunchA" and called(T.sp_rocket_launch) ~= nil, "rocket A launched at launch_a_s: ROCKET LAUNCH")
rtick(s3, RK.launch_a_s + 1, RK.launch_a_s + RK.boost_s + 0.5)
check(evs("^RE_SV_SpRocketBoost") == "RE_SV_SpRocketBoostA", "boosted boost_s on")
alive.SV_Unit_SpRockets = 1                     -- A shot down
rtick(s3, RK.launch_a_s + RK.boost_s + 1, RK.launch_a_s + RK.boost_s + 2)
check(paid("a rocket shot down") > 0 and called(T.sp_rocket_down) ~= nil and evs("^RE_SV_SpRocketSplitOn$") ~= "",
      "A down: paid, ROCKET DOWN, the split on for the last one")
rtick(s3, RK.launch_a_s + RK.boost_s + 2.5, RK.launch_b_s + 0.5)
check(evs("^RE_SV_SpRocketLaunchB$") ~= "", "rocket B launched at launch_b_s")
alive.SV_Unit_SpRockets = 0                     -- B shot down: it breaks up
rtick(s3, RK.launch_b_s + 1, RK.launch_b_s + 1)
check(called(T.sp_debris) ~= nil and s3.rk.stage == 1 and SPORT.retakeBusy(s3), "B down: THE ROCKET BREAKS UP, stage 1, still busy")
rtick(s3, RK.launch_b_s + 1.5, RK.launch_b_s + 1 + RK.debris_tgt_s + 0.5)
check(evs("^RE_SV_SpDebriTgt1$") ~= "", "stage 1 targetable debris_tgt_s on")
alive.SV_Unit_SpDebriA = 0
rtick(s3, now + 0.5, now + 0.5 + RK.debris_next_s + 0.5)
check(evs("^RE_SV_SpDebriTgt2$") ~= "" and paid("the rocket's debris") > 0, "stage 1 down: its pieces paid, stage 2 targetable")
alive.SV_Unit_SpDebriB = 0
rtick(s3, now + 0.5, now + 0.5 + RK.debris_next_s + 0.5)
alive.SV_Unit_SpDebriC = 0
rtick(s3, now + 0.5, now + 1)
check(evs("^RE_SV_SpDebriTgt3$") ~= "" and s3.rk.done and called(T.sp_debris_down) ~= nil and not SPORT.retakeBusy(s3),
      "stages 2 and 3 down: DEBRIS DESTROYED, the rockets done, not busy")
SPORT.retakeOver(now, s3)
check(paid("spaceport retaken") > 0, "no escape: the retake reward paid")
-- an escape: the penalty, no reward, its despawn not a kill; the other shot down breaks up; the debris never splits: taken off
-- ((0.73.77, I5) with no height to read, an escape counts only ESCAPE_MIN_S (50 s) after its launch: the flag at +60 s)
local s4 = retakeWithRockets()
rtick(s4, 0, RK.launch_a_s + 59)
FLAGS.SV_SpRocketEscA = 1
rtick(s4, RK.launch_a_s + 60, RK.launch_a_s + 60)
alive.SV_Unit_SpRockets = 1                     -- (its despawn a second later)
rtick(s4, RK.launch_a_s + 61, RK.launch_a_s + 61)
check(called(T.sp_rocket_escaped) ~= nil and RUN.credits == 20000 - RK.escape_penalty and paid("a rocket shot down") == 0
      and s4.rk.kills == 0 and evs("^RE_SV_SpRocketSplitOn$") ~= "",
      "A escaped: ROCKET ESCAPED, -escape_penalty, its despawn not a kill, the split on for B")
rtick(s4, RK.launch_a_s + 61.5, RK.launch_b_s + 0.5)
alive.SV_Unit_SpRockets = 0
rtick(s4, RK.launch_b_s + 1, RK.launch_b_s + 1 + RK.debris_tgt_s + 1)
check(s4.rk.stage == 1 and evs("^RE_SV_SpDebriTgt1$") ~= "", "B shot down after A escaped: it breaks up (stage 1)")
rtick(s4, now + 0.5, now + RK.debris_timeout_s + 1)
check(s4.rk.done and evs("^RE_SV_SpRocketRemove$") ~= "" and since(1, "nothing changed for") >= 1, "debris that never changes: taken off after debris_timeout_s")
SPORT.retakeOver(now, s4)
check(paid("spaceport retaken") == 0 and since(1, "reward withheld: 1 rocket escaped") >= 1, "an escape: no retake reward")
-- both escape: no debris
local s5 = retakeWithRockets()
rtick(s5, 0, RK.launch_b_s + 59)
FLAGS.SV_SpRocketEscA, FLAGS.SV_SpRocketEscB = 1, 1
rtick(s5, RK.launch_b_s + 60, RK.launch_b_s + 61)
check(s5.rk.done and not s5.rk.stage and evs("^RE_SV_SpDebriTgt") == "" and RUN.credits == 20000 - 2 * RK.escape_penalty,
      "both escaped: done, no debris, two penalties")
-- off: no rockets
RK.enabled = false
local s6 = retakeWithRockets()
rtick(s6, 0, 1)
check(s6.rk == nil and alive.SV_Unit_SpRockets == nil and not SPORT.retakeBusy(s6), "rockets.enabled = false: none")
RK.enabled = true
SP.retake.island.enabled = true

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

print("switched off (CFG.specials.spaceport.enabled = false, tools/nospaceport.py)")
fresh(10)
CFG.specials.spaceport.enabled = false
check(SPORT.ready() == false and SPC.kinds.retake.ready() == false, "enabled = false: no Spaceport Assault, no retake (ready)")
RUN.sport = { retakeRound = D.round + 1, troops = 8, lostRound = D.round, ships = {} }
check(specialFor(D.round + 1) ~= "retake", "enabled = false: a captured spaceport's next round isn't the retake")
CFG.specials.spaceport.enabled = true
check(SPORT.ready() == true and SPC.kinds.retake.ready() == true and specialFor(D.round + 1) == "retake", "enabled again: both can come")
CFG.specials.spaceport.retake.enabled = false
check(SPC.kinds.retake.ready() == false and specialFor(D.round + 1) ~= "retake", "retake.enabled = false: no retake")
CFG.specials.spaceport.retake.enabled = true
RUN.sport = nil

print("startRound: its fleet still up (0.73.77, I3: S4: it comes, the leftovers taken off first)")
fresh(10)
alive.SV_Unit_SpAegisC = 1
D.forceSpecial, D.state = "spaceport", "wait"
local okR, errR = pcall(startRound)
check(okR and D.special ~= nil and D.special.kind == "spaceport", "a spaceport with a ship still up from before: it comes (" .. tostring(errR) .. ")")
events = {}
alive.SV_Unit_SpAegisC = 1
check(SPORT.spawn(0) == true and evs("^RE_SV_SpFleetRemove$") ~= "" and since(1, "were still up from before %(AegisC%)") >= 1,
    "its spawn: the leftover taken off (RE_SV_SpFleetRemove), logged")
-- a leftover still going after the removal: the queue waits, then counts it as it is
fresh(10)
s = D.special
alive.SV_Unit_SpWaspA = 1
local rawEv = SV_Event
SV_Event = function(name) events[#events + 1] = name; return 1 end      -- (a removal that takes a while)
SPORT.spawn(0)
run(s, 0, 2)
check(#spawned("^SV_Unit_SpWaspA$") == 0 and #s.queue == 26, "the new fleet waits for the leftover (the Ford out, " .. #s.queue .. " queued)")
alive.SV_Unit_SpWaspA = 0
run(s, 2.25, 8)
check(#spawned("^SV_Unit_Sp[FWAB]") == 27 and #s.queue == 0, "the leftover gone: the whole fleet spawned (" .. #spawned("^SV_Unit_Sp[FWAB]") .. ")")
fresh(10)
s = D.special
alive.SV_Unit_SpWaspA = 1
SPORT.spawn(0)
run(s, 0, 15)
check(#s.queue == 0 and #spawned("^SV_Unit_Sp[FWAB]") == 26 and s.ships.SV_Unit_SpWaspA and s.ships.SV_Unit_SpWaspA.old,
    "still up 8 s on: counted in this fleet as it is, the rest spawned (" .. #spawned("^SV_Unit_Sp[FWAB]") .. ")")
SV_Event = rawEv

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

print("the wave report")
local wl, sl = {}, {}
for _, l in ipairs(logs) do
    if l:find("^special: wave SV_Unit_SpLcac") then wl[#wl + 1] = l end
    if l:find("^special: the Spaceport Assault's waves") then sl[#sl + 1] = l end
end
local avl = nil
for _, l in ipairs(wl) do if l:find("^special: wave SV_Unit_SpLcacAV: 2 craft, 0 shot down, 1 landed, 1 troop vehicles ashore") then avl = l end end
check(avl ~= nil, "each wave's line as it's done (AV: 2 craft, 1 landed, its troops ashore): " .. tostring(avl or wl[1]))
check(#sl >= 2 and sl[1]:find("troop vehicles: 2 ashore, 2 got in", 1, true) and sl[1]:find("the capture: ", 1, true),
    "the round's line at its end, the capture's timeline: " .. tostring(sl[1]))

---------------------------------------------------------------------------------------------------- 0.73.77: Workstream I
-- (testing/2026-11-03/PLAN_desync_lag_compatibility.md I1-I8, the review's S1-S13, the economy's C2)
SP.retake.island.enabled = false                 -- (the garrison, the ships and the rockets alone below)
local function tp(base) return (TIER.pay(base * TIER.specialX(), TIER.index(D.round))) end
local function count(t, text) local n = 0; for _, c in ipairs(t) do if c.text == text then n = n + 1 end end; return n end
local nextAddr = 5000
local function obj(cls, x, y, z)
    nextAddr = nextAddr + 1
    local o = { full = cls .. "_C /Game/x.PersistentLevel." .. cls .. "_C_" .. nextAddr, addr = nextAddr, HealthInternal = 1000,
                pos = { X = x or -2964629, Y = y or -26491, Z = z or 50 } }
    function o:SetMinHealth() end
    function o:ModifyHealth(d) self.HealthInternal = math.max(0, self.HealthInternal + d) end
    function o:K2_GetActorLocation() return self.pos end
    function o:SetActorHiddenInGame(h) self.hidden = h end
    function o:SetActorEnableCollision() end
    function o:SetIsInvincible(v) self.inv = v end
    for _, f in ipairs(onNew) do f(o) end
    return o
end

print("I1: a ship counted by its hull (S1, S2, S5; the economy's C2)")
-- each ship its hull and its turrets, as the game makes them (SV_UnitAlive: its objects still up)
local PARTS = { SV_Unit_SpAegis = { "BP_VE002_aegs_CP", "BP_VE002_aegs_mk15_01_CP", "BP_VE002_aegs_mk41_CP", "BP_VE002_aegs_mk45_CP",
                                    "BP_VE002_artillery_CP" },
                SV_Unit_SpFord = { "BP_VE004_grfd_CP", "BP_VE004_grfd_mk15_01_CP_Ally", "BP_VE004_grfd_mk15_02_CP_Ally",
                                   "BP_VE004_grfd_mk15_03_CP_Ally", "BP_VE004_grfd_mk15_04_CP_Ally" },
                SV_Unit_SpBoat = { "BP_VE011_mslb_CP", "BP_VE011_mslb_sam_CP" }, SV_Unit_SpWasp = { "BP_VE023_wasp_CP" } }
local objs = {}
local rawSpawn, rawAlive, rawEvent = SV_Spawn, SV_UnitAlive, SV_Event
SV_Spawn = function(unit, ...)
    local l = nil
    for pre, x in pairs(PARTS) do if unit:find("^" .. pre) then l = x end end
    if not l then return rawSpawn(unit, ...) end
    spawns[#spawns + 1] = { unit = unit }
    objs[unit] = {}
    for i, cls in ipairs(l) do objs[unit][i] = obj(cls) end
    return #l
end
SV_UnitAlive = function(u)
    if objs[u] then
        local n = 0
        for _, o in ipairs(objs[u]) do if not o.gone and o.HealthInternal > 0 then n = n + 1 end end
        return n
    end
    return rawAlive(u)
end
SV_Event = function(name)
    if name == "RE_SV_SpFleetRemove" then for _, l in pairs(objs) do for _, o in ipairs(l) do o.HealthInternal = 0 end end end
    return rawEvent(name)
end
fresh(13)
local sI = D.special
SPORT.spawn(0)
run(sI, 0, 5)
clock = clock + 5                                -- (their objects a moment old: the hull told)
local L0 = #logs
run(sI, 5.25, 7)
check(since(L0, "27 of its 27 ships counted by their hull") == 1, "every ship's hull told (logged once)")
check(sI.ships.SV_Unit_SpAegisA.hull == objs.SV_Unit_SpAegisA[1] and sI.ships.SV_Unit_SpFord.hull == objs.SV_Unit_SpFord[1]
      and sI.ships.SV_Unit_SpWaspA.hull == objs.SV_Unit_SpWaspA[1], "the hull: the one object that isn't a turret (a Wasp's only one)")
credits, callouts = {}, {}
objs.SV_Unit_SpAegisA[3].HealthInternal = 0      -- (its mk41 shot off)
-- ((0.73.80) a ship watched by its hull: its unit's count (its turrets') asked again every 3 s, not every second: the
-- turret's pay within 3 s; its hull's own end still at the next look, below)
run(sI, now + 0.25, now + 3.25)
check(paid("turret shot off") == tp(SP.pay.turret) and paid("aegis sunk") == 0 and SPORT.shipsUp(sI) == 27,
      "a turret shot off alone: pay.turret (" .. paid("turret shot off") .. "), not sunk, still afloat")
L0 = #logs
objs.SV_Unit_SpAegisA[1].HealthInternal = 0      -- (its hull down: the turrets still up)
run(sI, now + 0.25, now + 1.25)
local tleft = 0
for i = 2, 5 do if objs.SV_Unit_SpAegisA[i].HealthInternal > 0 then tleft = tleft + 1 end end
check(paid("aegis sunk") == tp(SP.pay.aegis) and since(L0, "SV_Unit_SpAegisA sunk %(its hull down") == 1 and SPORT.shipsUp(sI) == 26,
      "its hull down: sunk once, its price once (" .. paid("aegis sunk") .. "), no longer afloat")
check(tleft == 0 and since(L0, "3 of its turrets still up finished off") == 1, "its 3 turrets still up finished off with it")
run(sI, now + 0.25, now + 3)
check(paid("aegis sunk") == tp(SP.pay.aegis) and since(L0, "SV_Unit_SpAegisA sunk") == 1, "never paid or sunk again")
objs.SV_Unit_SpFord[1].HealthInternal = 0        -- the Ford's hull: CARRIER SUNK once
run(sI, now + 0.25, now + 4)
check(count(callouts, T.sp_ford_down) == 1 and paid("ford sunk") == tp(SP.pay.ford), "the Ford's hull down: CARRIER SUNK once, paid once (S2)")
local nfl = #flights
run(sI, now + 0.25, now + 3 * SP.deck.every_s)
check(#flights == nfl, "the Ford sunk by its hull: no more deck launches (" .. (#flights - nfl) .. ")")
local bA = objs.SV_Unit_SpBoatA                  -- a turret the finish can't take: the boat still counted sunk
bA[2].ModifyHealth = function() error("refused") end
bA[1].HealthInternal = 0
L0 = #logs
run(sI, now + 0.25, now + 1.25)
check(sI.ships.SV_Unit_SpBoatA.sunk and since(L0, "1 NOT %(still up%)") == 1 and SV_UnitAlive("SV_Unit_SpBoatA") == 1,
      "a turret the finish didn't take: the boat sunk all the same (afloat only while its hull lives)")
for _, l in pairs(objs) do l[1].HealthInternal = 0 end
for u in pairs(alive) do if u:find("^SV_Unit_SpLcac") then alive[u] = 0 end end   -- (the craft out sunk too)
run(sI, now + 0.25, now + 2.25)
check(not SPORT.busy(sI) and SPORT.shipsUp(sI) == 0, "every hull down, nothing coming in: the round doesn't wait on a turret")
events = {}
L0 = #logs
SPORT.roundOver(now, sI)
check(evs("^RE_SV_SpFleetRemove$") ~= "" and since(L0, "the spaceport held: 1 of the fleet's units still had parts up %(BoatA%)") == 1,
      "held: the turret left up taken off at the round's end (RE_SV_SpFleetRemove)")
check(paid("aegis sunk") == 14 * tp(SP.pay.aegis) and paid("ford sunk") == tp(SP.pay.ford) and paid("wasp sunk") == 4 * tp(SP.pay.wasp)
      and paid("boat sunk") == 8 * tp(SP.pay.boat), "each ship paid its price once: the fleet " .. (paid(" sunk") - paid("craft sunk")))
SV_Spawn, SV_UnitAlive, SV_Event = rawSpawn, rawAlive, rawEvent

print("I2: co-op money (S3 above; S9: the escape penalty on every game)")
local debits = {}
COOP = { host = function() return true end, client = function() return false end, players = function() return {} end,
         debit = function(n, why) debits[#debits + 1] = { n = n, why = why } end }
local sD = retakeWithRockets()
rtick(sD, 0, RK.launch_a_s + 59)
FLAGS.SV_SpRocketEscA = 1
rtick(sD, RK.launch_a_s + 60, RK.launch_a_s + 61)
check(#debits == 1 and debits[1].n == RK.escape_penalty and RUN.credits == 20000 - RK.escape_penalty,
      "the host: the penalty off its zollars and sent to every joiner (COOP.debit " .. tostring(debits[1] and debits[1].n) .. ")")
COOP.host, COOP.client = function() return false end, function() return true end
RUN.credits = 3000
local took = SPORT.debit(RK.escape_penalty, "rocket A escaped", true)
check(took == 3000 and RUN.credits == 0 and #debits == 1 and since(1, "credits: %-3000 %(rocket A escaped, the host's round%), now 0") >= 1,
      "a joiner: the host's penalty off its own zollars (what it has of it), never sent on")
-- ((0.73.78) the penalty split as a special's reward: the host works out each player's share and sends that)
COOP.host, COOP.client = function() return true end, function() return false end
COOP.specialShare = function() return 0.5 end
RUN.credits, debits = 20000, {}
took = SPORT.debit(RK.escape_penalty, "rocket B escaped")
local half = math.floor(RK.escape_penalty * 0.5 / 10 + 0.5) * 10
check(took == half and RUN.credits == 20000 - half and #debits == 1 and debits[1].n == half
      and since(1, "special: the penalty's co%-op share x0%.50 of " .. RK.escape_penalty) >= 1,
      "the host: a co-op penalty split as the specials' rewards (" .. half .. " each, sent as it is)")
COOP.specialShare = function() return 1 end
RUN.credits, debits = 20000, {}
took = SPORT.debit(RK.escape_penalty, "rocket B escaped")
check(took == RK.escape_penalty, "solo / alone: the whole penalty")
COOP = nil

print("(review of 0.73.80, finding 6) co-op: the rockets, their debris, the garrison and the island taken off as nobody's")
-- (on the host, COOP.takenOff for each unit a removal event takes off, before it: a destroy with no attacker isn't the
-- kill of a player who once hit a piece, nor the host's)
COOP = { host = function() return true end, client = function() return false end, players = function() return {} end,
         debit = function() end, takenOff = function(u) events[#events + 1] = "takenOff:" .. u; return 0 end }
local RK_UNITS = { "SV_Unit_SpRockets", "SV_Unit_SpDebriA", "SV_Unit_SpDebriB", "SV_Unit_SpDebriC" }
local function offFirst(ev, units)                -- each of units' takenOff before the first ev
    local at
    for i, e in ipairs(events) do if e == ev then at = i; break end end
    if not at then return false end
    for _, u in ipairs(units) do
        local ok = false
        for i = 1, at - 1 do if events[i] == "takenOff:" .. u then ok = true end end
        if not ok then return false end
    end
    return true
end
local sC = retakeWithRockets()                   -- A and B shot down, B breaks up, its debris never changes: the timeout
rtick(sC, 0, RK.launch_a_s + RK.boost_s + 0.5)
alive.SV_Unit_SpRockets = 1
rtick(sC, RK.launch_a_s + RK.boost_s + 1, RK.launch_b_s + 0.5)
alive.SV_Unit_SpRockets = 0
rtick(sC, RK.launch_b_s + 1, RK.launch_b_s + 1 + RK.debris_tgt_s + 1)
check(sC.rk.stage == 1 and evs("^RE_SV_SpRocketRemove$") == "", "B shot down: it breaks up, nothing taken off yet")
rtick(sC, now + 0.5, now + RK.debris_timeout_s + 1)
check(sC.rk.done and offFirst("RE_SV_SpRocketRemove", RK_UNITS),
      "debris taken off at the timeout: the rockets and every debris unit through COOP.takenOff first (" .. table.concat(events, ",", math.max(1, #events - 6)) .. ")")
local sN = retakeWithRockets()                   -- both down at once: no split, the debris under the sea taken off
rtick(sN, 0, RK.launch_b_s + 1)
alive.SV_Unit_SpRockets = 0
rtick(sN, RK.launch_b_s + 1.5, RK.launch_b_s + 2)
check(sN.rk.done and not sN.rk.stage and offFirst("RE_SV_SpRocketRemove", RK_UNITS), "no split: taken off through COOP.takenOff first")
local sX = retakeWithRockets()                   -- nothing ends them: each taken off at its timeout, through it too
rtick(sX, 0, RK.launch_b_s + RK.timeout_s + 1)
check(sX.rk.done and offFirst("RE_SV_SpRocketRemove", RK_UNITS), "rockets lost at their timeout: through COOP.takenOff first")
SP.retake.island.enabled = true
local sG = retakeWithRockets()                   -- the round's end with the garrison, the island and the rockets up
alive.SV_Unit_SpGarrisonA = 4
SPORT.retakeOver(now, sG)
local isl = {}
for _, u in ipairs({ "SV_Unit_SpIslExsam", "SV_Unit_SpIslFlak", "SV_Unit_SpIslSam", "SV_Unit_SpIslAA", "SV_Unit_SpIslTankA",
                     "SV_Unit_SpIslTankB", "SV_Unit_SpIslApc" }) do isl[#isl + 1] = u end
check(offFirst("RE_SV_SpGarrisonRemove", { "SV_Unit_SpGarrisonA", "SV_Unit_SpGarrisonB", "SV_Unit_SpGarrisonC" })
      and offFirst("RE_SV_SpIslandRemove", isl) and offFirst("RE_SV_SpRocketRemove", RK_UNITS),
      "the retake's end: the garrison, the island's units and the rockets through COOP.takenOff before their removals")
SP.retake.island.enabled = false
COOP = nil

print("I3: a fleet no retake can follow is taken off (S4)")
fresh(10)
s = D.special
SPORT.spawn(0)
run(s, 0, 5)
s.captured = true
RUN.sport = { retakeRound = 11, troops = 8, lostRound = 10, ships = {} }
SP.retake.enabled = false
events = {}
SPORT.roundOver(6, s)
SP.retake.enabled = true
check(evs("^RE_SV_SpFleetRemove$") ~= "" and RUN.sport == nil and since(1, "no retake follows") >= 1,
      "lost with the retake off: the fleet taken off at once, nothing pending")
local noPick = function() return {}, 0 end
fresh(11)
alive.SV_Unit_SpAegisC = 1
RUN.sport = { retakeRound = 11, troops = 8, lostRound = 10, ships = { SV_Unit_SpAegisC = { kind = "aegis", group = "B" } } }
SPORT.planRound("retake", noPick)
check(RUN.sport ~= nil and evs("^RE_SV_SpFleetRemove$") == "", "the retake's own round: its fleet kept for it")
SPORT.planRound("ladon", noPick)
check(RUN.sport == nil and evs("^RE_SV_SpFleetRemove$") ~= "" and since(1, "Retake due in round 11 didn't come %(round 11 is ladon%)") >= 1,
      "a retake that didn't come: the fleet left from its assault taken off, forgotten")

print("I4: the fighters withdrawn at a capture (S6)")
fresh(13)
local W1, W2 = CFG.pool[1], CFG.pool[4]
D.spWithdrawn, alive[W1], alive[W2] = { [W1] = true, [W2] = true }, 2, 0
SPORT.planRound(nil, noPick)
check(D.taken[W1] and not D.taken[W2] and D.spWithdrawn[W1] and not D.spWithdrawn[W2]
      and since(1, "1 still up kept out of round 13's picks %(no SV_Recycle in this runtime%)") >= 1,
      "no SV_Recycle: one still up kept out of the round's picks, one down forgotten")
local recycled = {}
SV_Recycle = function(u, force) recycled[#recycled + 1] = u .. ":" .. force; alive[u] = 0; return 1 end
D.taken = {}
SPORT.planRound(nil, noPick)
check(recycled[1] == W1 .. ":1" and not D.taken[W1] and next(D.spWithdrawn) == nil and since(1, "1 recycled %(SV_Recycle%): " .. W1) >= 1,
      "SV_Recycle(unit, 1): the one still up recycled in the next round's plan")
SV_Recycle = nil

print("I5: rockets and debris that always end (S7, S8)")
local sE = retakeWithRockets()                   -- an escape flag 4 s after its launch, no height read: not an escape
rtick(sE, 0, RK.launch_a_s + 0.5)
FLAGS.SV_SpRocketEscA = 1
rtick(sE, RK.launch_a_s + 4, RK.launch_a_s + 5)
check(sE.rk.lost.A and not sE.rk.escaped.A and RUN.credits == 20000 and since(1, "rocket A's climb ended short") >= 1,
      "an escape 4 s on (no height read): taken off, no penalty")
alive.SV_Unit_SpRockets = 1
rtick(sE, RK.launch_a_s + 5.5, RK.launch_a_s + 6)
check(sE.rk.kills == 0 and evs("^RE_SV_SpRocketSplitOn$") ~= "", "its despawn not a kill; one left, the split on")
rtick(sE, RK.launch_a_s + 6.5, RK.launch_b_s + 1)
alive.SV_Unit_SpRockets = 0
rtick(sE, RK.launch_b_s + 1.5, RK.launch_b_s + 2)
check(sE.rk.stage == 1, "the other shot down: it breaks up")
local sT = retakeWithRockets()                   -- nothing ends them: each taken off timeout_s after its launch
rtick(sT, 0, RK.launch_b_s + RK.timeout_s + 1)
check(sT.rk.done and sT.rk.lost.A and sT.rk.lost.B and RUN.credits == 20000 and not SPORT.retakeBusy(sT)
      and since(1, "rocket B neither shot down nor escaped") >= 1 and since(1, "the rockets are done: 0 shot down, 0 escaped, 2 taken off") >= 1,
      "a rocket neither down nor escaped timeout_s on: taken off, no penalty; the round goes on")
local sB = retakeWithRockets()                   -- both down in one look: no split, no debris
rtick(sB, 0, RK.launch_b_s + 1)
alive.SV_Unit_SpRockets = 0
L0 = #logs
rtick(sB, RK.launch_b_s + 1.5, RK.launch_b_s + 2)
check(sB.rk.done and not sB.rk.stage and evs("^RE_SV_SpDebriTgt") == "" and since(L0, "went down without breaking up %(its split wasn't on yet") == 1,
      "both rockets down at once: no split, no debris marked as targets")
-- each one's object: told by its pad, its height and its kill read from it; the debris up from under the sea
local rkO, debO = {}, {}
local spawnNoObj = SV_Spawn
SV_Spawn = function(unit, ...)
    if unit == "SV_Unit_SpRockets" then                    -- (B's pad first: told apart by their pads, not their order)
        local r = spawnNoObj(unit, ...)
        rkO = { obj("BP_OP0058_crkt_CP", -1325196, 59778, 76000), obj("BP_OP0058_crkt_CP", -1384043, -41261, 76000) }
        return r
    elseif unit:find("^SV_Unit_SpDebri") then
        local r = spawnNoObj(unit, ...)
        if unit == "SV_Unit_SpDebriB" then alive[unit] = nil; return -3 end    -- (one that never came)
        debO[unit] = { obj("BP_OP0058_crkt_ABR_p1", 0, 0, -50000), obj("BP_OP0058_crkt_L_p1", 0, 0, -50000) }
        return r
    end
    return spawnNoObj(unit, ...)
end
local sO = retakeWithRockets()
rtick(sO, 0, 3)
check(sO.rk.byObj and sO.rk.obj.A == rkO[2] and sO.rk.obj.B == rkO[1] and since(1, "each one's height and kill read from it") >= 1,
      "the rockets' objects told apart by their pads")
rtick(sO, 3.5, RK.launch_a_s + 15)
rkO[2].pos.Z = 200000                            -- (A at 2 km, its path's end flag)
FLAGS.SV_SpRocketEscA = 1
rtick(sO, RK.launch_a_s + 15.5, RK.launch_a_s + 61)
check(sO.rk.lost.A and RUN.credits == 20000 and since(1, "rocket A's climb ended short %(at 2000 m") >= 1,
      "an escape at 2 km, 60 s on: below escape_min_m, taken off, no penalty")
rtick(sO, RK.launch_a_s + 61.5, RK.launch_b_s + 70)
rkO[1].pos.Z = 2020000                           -- (B at 20.2 km: its climb's end)
FLAGS.SV_SpRocketEscB = 1
rtick(sO, RK.launch_b_s + 70.5, RK.launch_b_s + 71)
check(sO.rk.escaped.B and RUN.credits == 20000 - RK.escape_penalty and sO.rk.done, "B at 20.2 km: escaped, the penalty; the rockets done")
local sK = retakeWithRockets()
rtick(sK, 0, RK.launch_a_s + 1)
rkO[2].HealthInternal = 0                        -- (A down: its unit's count unchanged)
rtick(sK, RK.launch_a_s + 1.5, RK.launch_b_s + 1)
check(sK.rk.kills == 1 and paid("a rocket shot down") == tp(RK.rocket_pay) and evs("^RE_SV_SpRocketSplitOn$") ~= "",
      "A's object at 0 health: a kill (its unit's count unchanged), the split on")
rkO[1].HealthInternal = 0
L0 = #logs
rtick(sK, RK.launch_b_s + 1.5, RK.launch_b_s + 1 + RK.split_wait_s + 1)
check(sK.rk.done and not sK.rk.stage and since(L0, "no debris came up in 10 s") == 1, "B down, its debris still 500 m down: no split, done")
local sS = retakeWithRockets()
rtick(sS, 0, RK.launch_b_s + 1)
rkO[2].HealthInternal, rkO[1].HealthInternal = 0, 100
rtick(sS, RK.launch_b_s + 1.5, RK.launch_b_s + 3)
rkO[1].HealthInternal = 0
for _, o in ipairs(debO.SV_Unit_SpDebriA) do o.pos.Z = 1500000 end
L0 = #logs
rtick(sS, RK.launch_b_s + 3.5, RK.launch_b_s + 4)
check(sS.rk.stage == 1 and since(L0, "the last rocket broke up %(its debris seen coming up%)") == 1, "B down, its debris up: stage 1")
credits = {}
rtick(sS, now + 0.5, now + RK.debris_tgt_s + 1)
alive.SV_Unit_SpDebriA = 0
rtick(sS, now + 0.5, now + 2 * RK.debris_next_s + 3)
alive.SV_Unit_SpDebriC = 0
rtick(sS, now + 0.5, now + RK.debris_next_s + 2)
check(sS.rk.done and paid("the rocket's debris") == 4 * tp(RK.debris_pay), "a debris unit that never came pays nothing (" ..
      paid("the rocket's debris") .. " for 4 pieces)")
SV_Spawn = spawnNoObj

print("I6: the clocks wait while you're down at the airfield (S10)")
fresh(10)
s = D.special
SPORT.spawn(0)
run(s, 0, 5)
grounded = true
L0 = #logs
run(s, 5.25, 50)
check(#spawned("^SV_Unit_SpLcac") == 0 and since(L0, "clocks wait while you're down at the airfield") == 1, "down at the airfield: no wave")
grounded = false
run(s, 50.25, 62)
check(#spawned("^SV_Unit_SpLcac") == 0 and since(L0, "clocks run again") == 1, "flying again: the waves' clocks moved on by the time held")
run(s, 62.25, 68)
check(#spawned("^SV_Unit_SpLcac") == 4, "the first waves first_wave_s of flying after the fleet came (" .. #spawned("^SV_Unit_SpLcac") .. ")")
local sG = retakeWithRockets()
grounded = true
rtick(sG, 0, 60)
check(not sG.rk.launched.A, "down at the airfield: no rocket launched")
grounded = false
rtick(sG, 60.5, 60 + RK.launch_a_s - 2)
check(not sG.rk.launched.A, "flying again: its launch moved on by the time held")
rtick(sG, 60 + RK.launch_a_s - 1.5, 60 + RK.launch_a_s + 3)
check(sG.rk.launched.A ~= nil, "rocket A launched launch_a_s of flying into the retake")

print("I7: a whole capture share (S11); the pending retake on the joiners (S12)")
fresh(10)
s = D.special
SPORT.spawn(0)
run(s, 0, 5)
SP.capture_per_troop = 7.4
s.troops = { { unit = "SV_Unit_SpTroopsAVL", key = "AVL", at = now - 5 } }
FLAGS.SV_SpAtAVL = 1
local okC, errC = pcall(run, s, now + 0.25, now + 1.25)
SP.capture_per_troop = 10
check(okC and s.capture == 7 and math.type(s.capture) == "integer" and SPORT.row(s, T):find("CAPTURE: 7%%"),
      "capture_per_troop 7.4: 7 % a vehicle, the row and logs fine (" .. tostring(errC or s.capture) .. ")")
check(SPORT.coopCode() == "a:27:0:7:0;-", "the host's share in the assault (no Tu-160 up): " .. SPORT.coopCode())
s.capture, s.captured = 100, true
RUN.sport = { retakeRound = 11, troops = 9, lostRound = 10, ships = {} }
SPORT.roundOver(now, s)
local code = SPORT.coopCode()
check(code:find("^%-;11:9:10:AegisA,") ~= nil and select(2, code:gsub(",", ",")) == 26, "after the capture: the retake due, 27 ships (" .. code:sub(1, 40) .. "...)")
COOP = { host = function() return false end, client = function() return true end, players = function() return {} end }
local hostRun = RUN
RUN = { credits = 0 }
SPORT.fromHost(code)
local nShips = 0
for _ in pairs(RUN.sport and RUN.sport.ships or {}) do nShips = nShips + 1 end
check(RUN.sport and RUN.sport.fromHost and RUN.sport.retakeRound == 11 and nShips == 27 and since(1, "kept here for a host migration") >= 1,
      "a joiner keeps the host's pending retake (for a host migration)")
SPORT.fromHost("a:5:2:30;-")
check(SPORT.clientRow(T) == string.format(T.sp_row, 5, 2, 30) and RUN.sport == nil and since(1, "no longer pending") >= 1,
      "a joiner's NEXT row: the host's Spaceport row; the retake no longer pending")
SPORT.fromHost("a:5:2:300;1:2:3:Bogus,AegisA")
check(SPORT.hostRow == nil and RUN.sport and RUN.sport.ships.SV_Unit_SpAegisA and not RUN.sport.ships.SV_Unit_SpBogus,
      "the host's share checked: a capture over 100 dropped, units of the fleet only")
SPORT.fromHost("a:5:2:30;-")
clock = clock + 6
check(SPORT.clientRow(T) == nil, "the host's row 5 s old: none")
COOP = nil
check(SPORT.clientRow(T) == nil, "not a joiner: none")
RUN = hostRun
-- a host by migration: the retake comes, the old host's ships (taken down with its copies here) spawned again
fresh(11)
RUN.sport = { retakeRound = 11, troops = 8, lostRound = 10, fromHost = true,
              ships = { SV_Unit_SpAegisC = { kind = "aegis", group = "B" }, SV_Unit_SpFord = { kind = "ford", group = "Ford" } } }
check(specialFor(11) == "retake", "a host by migration: specialFor still brings the retake")
D.special = { kind = "retake", state = "pending" }
SP.retake.rockets.enabled = false
check(SPORT.retakeSpawn(0) and #spawned("^SV_Unit_SpAegisC$") == 1 and #spawned("^SV_Unit_SpFord$") == 1 and SPORT.shipsUp(D.special) == 2
      and since(1, "spawned again on this game") >= 1, "its ships spawned again on the new host")
check(SPORT.coopCode() == "r:8:2;11:8:10:AegisC,Ford", "the retake in play shared (for the next migration): " .. SPORT.coopCode())
SP.retake.rockets.enabled = true

print("I8: the Ford's deck flights held back when the round is planned (S13)")
fresh(12)
D.forceSpecial, D.state = "spaceport", "wait"
local okP, errP = pcall(startRound)
local held = {}
for u in pairs(D.spDeck or {}) do held[#held + 1] = u end
local planned = math.min(SP.deck.max_flights, SP.deck.flights + math.floor(13 * SP.deck.flights_per_round))
check(okP and #held == math.min(SP.deck.reserve, planned) and since(1, "held back from round 13's fighters for it") >= 1,
      "round 13: " .. #held .. " 2-ships held back for the deck (" .. tostring(errP) .. ")")
local inWaves = false
for _, w in ipairs(D.waves or {}) do for _, u in ipairs(w) do if D.spDeck and D.spDeck[u] then inWaves = true end end end
local inSpare = false
for _, u in ipairs(D.spare or {}) do if D.spDeck and D.spDeck[u] then inSpare = true end end
check(not inWaves and not inSpare, "none of them among the round's fighters or spares")
s = D.special
SPORT.spawn(0)
run(s, 0, SP.deck.first_s + 1)
check(#flights == 1 and D.spDeck[flights[1].unit] and since(1, "%(held for the deck%)") >= 1, "the deck launches one held for it")
run(s, SP.deck.first_s + 1.25, SP.deck.first_s + 4 * SP.deck.every_s)
local first = flights[1].unit
alive[first], D.up[first] = 0, nil                -- (shot down: launched again)
local nb = #flights
run(s, now + 0.25, now + SP.deck.every_s + 1)
check(#flights == nb + 1 and D.spDeck[flights[#flights].unit], "one shot down: a held flight launched again")
SP.retake.island.enabled = true

---------------------------------------------------------------------------------------------------- the Tu-160s
print("the Tu-160s at the airfield (CFG.specials.spaceport.tu160; user, 2026-11-04)")
local heavyRoutes, setAc = {}, {}
HEAVY = { route = function(u, x, y) heavyRoutes[#heavyRoutes + 1] = { u = u, x = x, y = y } end }   -- (sv_flights.lua's)
local rawSetAc = SV_SetAircraft
function SV_SetAircraft(u, ac) setAc[u] = ac; return 1 end
local function compassOf(x, y) return math.deg(math.atan(x - AIRFIELD.X, -(y - AIRFIELD.Y))) % 360 end
local function offBy(a, b) local d = math.abs(a - b) % 360; return math.min(d, 360 - d) end
fresh(12)
SP.tu160.enabled = true
s = D.special
local L1 = #logs + 1
check(SPORT.spawn(0) == true and s.tu and #s.tu.sides == 2, "planned at the assault's start: two flights")
local side = {}
for _, sd in ipairs(s.tu.sides) do side[sd.bearing] = sd.unit end
check(side[0] and side[180] and side[0] ~= side[180] and HEAVY_UNIT[side[0]] and HEAVY_UNIT[side[180]],
      "the two heavy flights, one from the north (0), one from the south (180): " .. tostring(side[0]) .. ", " .. tostring(side[180]))
check(since(L1, "^special: the Tu%-160s come 45 s into the assault: EA_Unit_01_Air%d from the NORTH %(bearing 0%), "
      .. "EA_Unit_01_Air%d from the SOUTH %(bearing 180%)$") == 1, "logged at the assault's start")
run(s, 0, SP.tu160.after_s - 0.25)
check(#spawned("^EA_Unit_01_Air[12]$") == 0 and SPORT.busy(s), "none before after_s, and the round can't end while they're to come")
grounded = true                                  -- (solo, down at the airfield: the Spaceport's clocks wait)
run(s, now + 0.25, now + 10)
check(#spawned("^EA_Unit_01_Air[12]$") == 0, "down at the airfield: their clock waits")
grounded = false
local L2 = #logs + 1
run(s, now + 0.25, now + 1)
local tu = spawned("^EA_Unit_01_Air[12]$")
check(#tu == 2, "after_s of flying on: both flights sent (" .. table.concat(tu, ",") .. ")")
local okPos, why = true, ""
for _, sp in ipairs(spawns) do
    local want = sp.unit == side[0] and 0 or sp.unit == side[180] and 180 or nil
    if want then
        local b, d = compassOf(sp.x, sp.y), math.sqrt((sp.x - AIRFIELD.X) ^ 2 + (sp.y - AIRFIELD.Y) ^ 2) / 100000
        local yawWant = math.deg(math.atan(AIRFIELD.Y - sp.y, AIRFIELD.X - sp.x)) % 360
        local alt = sp.z / 100
        local band = CFG.airfield.bombers.altitude_m
        if offBy(b, want) > SP.tu160.spread_deg + 0.01 or d < SP.tu160.distance_km[1] - 0.01 or d > SP.tu160.distance_km[2] + 0.01
            or offBy(sp.yaw, yawWant) > 0.01 or alt < band[1] or alt > band[2] then
            okPos = false
        end
        why = why .. string.format("%s at bearing %.1f, %.1f km, yaw %.1f, %.0f m; ", sp.unit, b, d, sp.yaw, alt)
    end
end
check(okPos, "each from its side within spread_deg, distance_km out, facing the airfield, at the heavies' height: " .. why)
check(setAc[side[0]] == "t160_common" and setAc[side[180]] == "t160_common", "both on the Tu-160's row")
check(D.up[side[0]] and D.up[side[180]] and D.heavy[side[0]] and D.heavy[side[180]],
      "up for the round (it ends only once they're down) and bombing as heavies (D.heavy: bombTick's bomb runs)")
check(#heavyRoutes == 2 and offBy(compassOf(heavyRoutes[1].x, heavyRoutes[1].y), s.tu.units[heavyRoutes[1].u]) <= SP.tu160.spread_deg + 0.01,
      "each given the heavies' route in from where it spawned (HEAVY.route)")
local c1 = called(T.sp_tu160)
check(c1 and c1.sub == string.format(T.sp_tu160_sub, "NORTH AND SOUTH"), "called out: " .. tostring(c1 and c1.sub))
check(since(L2, "^special: the Tu%-160s at the airfield: 6 sent %(EA_Unit_01_Air%d: %d from the NORTH; EA_Unit_01_Air%d: %d from the SOUTH%)$") == 1,
      "logged: 6 sent")
check(not SPORT.busy(s) or SPORT.shipsUp(s) > 0, "once sent, their flights hold the round (D.up), not the special's busy")
-- the row: the host's and a joiner's
planes = { { unit = side[0], obj = { full = "BP_OP0060_t160_a" }, name = "BP_OP0060_t160_a" },
           { unit = side[180], obj = { full = "BP_OP0060_t160_b" }, name = "BP_OP0060_t160_b" },
           { unit = side[180], obj = { full = "BP_OP0060_t160_c" }, name = "BP_OP0060_t160_c", down = true } }
check(SPORT.tuUp(s) == 2 and SPORT.row(s, T):find(string.format(T.sp_row_tu160, 2), 1, true), "the row: " .. SPORT.row(s, T))
local code2 = SPORT.coopCode()
check(code2:find("^a:%d+:%d+:%d+:2;") ~= nil, "the host's share carries them: " .. code2)
COOP = { host = function() return false end, client = function() return true end, players = function() return {} end }
SPORT.fromHost(code2)
check(SPORT.clientRow(T) and SPORT.clientRow(T):find(string.format(T.sp_row_tu160, 2), 1, true), "a joiner's row: " .. tostring(SPORT.clientRow(T)))
SPORT.fromHost("a:5:2:30:99;-")
check(SPORT.hostRow == nil, "a joiner: a Tu-160 count past 24 dropped")
COOP = nil
local L3 = #logs + 1
SPORT.roundOver(now, s)
check(since(L3, "^special: the Tu%-160s this assault: 6 sent %(.*%), 2 still up at the round's end$") == 1, "the round's line")
-- captured before they come: none
fresh(12)
SP.tu160.enabled = true
s = D.special
SPORT.spawn(0)
s.captured = true
L3 = #logs + 1
run(s, 0, SP.tu160.after_s + 1)
check(#spawned("^EA_Unit_01_Air[12]$") == 0 and since(L3, "the Tu%-160s don't come: the spaceport was captured first") == 1,
      "the spaceport captured before they come: none")
-- one flight still up from before: the other alone, called out for its side
fresh(12)
SP.tu160.enabled = true
s = D.special
SPORT.spawn(0)
for _, sd in ipairs(s.tu.sides) do side[sd.bearing] = sd.unit end
alive[side[0]] = 2
L3 = #logs + 1
run(s, 0, SP.tu160.after_s + 1)
tu = spawned("^EA_Unit_01_Air[12]$")
local c2 = callouts[#callouts]
check(#tu == 1 and tu[1] == side[180] and since(L3, side[0] .. " still up from before: not sent") == 1
      and c2.text == T.sp_tu160 and c2.sub == string.format(T.sp_tu160_sub, "SOUTH"), "the north's flight still up: the south's alone, said so")
-- off: switched off, the airfield off
fresh(12)
s = D.special
SPORT.spawn(0)
check(s.tu == nil, "enabled = false: none planned")
SP.tu160.enabled = true
CFG.airfield.enabled = false
fresh(12)
SP.tu160.enabled = true
s = D.special
SPORT.spawn(0)
check(s.tu == nil, "the airfield off: none planned")
CFG.airfield.enabled = true
-- the fighters' next wave isn't held back by the Tu-160s (on top of the round), but the round's end waits for them
fresh(12)
SP.tu160.enabled = true
s = D.special
SPORT.spawn(0)
run(s, 0, SP.tu160.after_s + 1)
local tuA, tuB = s.tu.sides[1].unit, s.tu.sides[2].unit
local fighter = "ERA_Unit_02_Dep_Air1"
D.waves, D.wave = { { tuA }, { fighter } }, 1
D.state, D.at, D.waveAt, D.waveSeen, D.queue = "wave", 0, now, now, {}
local okW, errW = pcall(roundsTick, now + 1)
check(okW and D.wave == 2, "6 Tu-160s up: the fighters' next wave comes all the same (next_at " .. CFG.waves.next_at .. "; "
      .. tostring(errW) .. ", wave " .. tostring(D.wave) .. ")")
for u in pairs(alive) do if not (u == tuA or u == tuB) then alive[u] = 0 end end
D.state, D.at, D.up = "fighting", 0, { [tuA] = true, [tuB] = true }
okW, errW = pcall(roundsTick, now + 2)
check(okW and D.state == "fighting" and s.state == "assault", "every ship sunk, the Tu-160s still up: the round goes on (" .. tostring(errW) .. ")")
alive[tuA], alive[tuB] = 0, 0
planes = {}
D.at = 0
okW, errW = pcall(roundsTick, now + 4)
check(okW and D.state == "wait" and s.state == "done", "the Tu-160s down too: the round ends (" .. tostring(errW) .. ")")
-- (review of 7bcd4c4, findings 0 / 1) the spaceport captured with the Tu-160s up: they fall back with the fighters (off
-- D.up, D.heavy and D.heavyPath, their planes down and withdrawn, kept for the next round's recycle, nobody's in co-op),
-- so the round ends and the retake follows; before, they held the round (and bombed on) until all 6 were shot down
fresh(12)
SP.tu160.enabled = true
s = D.special
SPORT.spawn(0)
run(s, 0, SP.tu160.after_s + 1)
tuA, tuB = s.tu.sides[1].unit, s.tu.sides[2].unit
check(D.up[tuA] and D.up[tuB] and D.heavy[tuA] and D.heavy[tuB], "captured with them up: both Tu-160 flights sent first")
D.heavyPath = { [tuA] = { s = "A", k = 0 }, [tuB] = { s = "E", k = 0 } }      -- (HEAVY.route's, stubbed here)
local ERt = CFG.pool[1]
D.up[ERt], alive[ERt] = true, 2
planes = { { unit = tuA, obj = { full = "BP_OP0060_t160_a" }, name = "BP_OP0060_t160_a" },
           { unit = tuB, obj = { full = "BP_OP0060_t160_b" }, name = "BP_OP0060_t160_b" },
           { unit = ERt, obj = { full = "p" }, name = "p" } }
local tookOff = {}
COOP = { takenOff = function(u) tookOff[u] = true; return 0 end }
s.capture = 100
L3 = #logs + 1
run(s, now + 0.25, now + 1.5)
COOP = nil
check(s.captured and not D.up[tuA] and not D.up[tuB] and not D.up[ERt], "captured: the Tu-160s off D.up with the fighters")
check(not (D.heavy and (D.heavy[tuA] or D.heavy[tuB])) and not (D.heavyPath and (D.heavyPath[tuA] or D.heavyPath[tuB])),
      "off D.heavy and D.heavyPath: no more bomb runs or loops")
check(planes[1].down and planes[1].withdrawn and planes[2].down and planes[2].withdrawn and SPORT.tuUp(s) == 0,
      "their planes marked down and withdrawn (unpaid, bombTick skips them), none up on the row")
local wKeys = true
for k in pairs(D.spWithdrawn or {}) do if type(k) ~= "string" then wKeys = false end end
check(D.spWithdrawn and D.spWithdrawn[tuA] and D.spWithdrawn[tuB] and D.spWithdrawn[ERt] and wKeys,
      "kept for the next round's recycle (D.spWithdrawn: SPORT.planRound), unit names only")
check(tookOff[tuA] and tookOff[tuB], "co-op: theirs taken off as nobody's on the host (COOP.takenOff)")
check(since(L3, "^special: the round's fighters fall back with the capture: %d+ flights %(%d+ aircraft%) taken off: .*"
      .. "; the Tu%-160s too: EA_Unit_01_Air%d, EA_Unit_01_Air%d %(6 aircraft, no despawn event: recycled at the next round's plan%)$") == 1,
      "logged with the fighters'")
check(s.tu.why == "withdrawn at the capture", "their reason kept for the round's line: " .. tostring(s.tu.why))
for u in pairs(alive) do if u:find("^SV_Unit_Sp") then alive[u] = 0 end end
D.state, D.at = "fighting", 0
okW, errW = pcall(roundsTick, now + 2)
check(okW and D.state == "wait" and s.state == "done", "the Tu-160s still flying but withdrawn: the round ends (" .. tostring(errW)
      .. "; " .. tostring(D.state) .. ", " .. tostring(s.state) .. ")")
check(specialFor(D.round + 1) == "retake", "the retake follows")
check(since(L3, "^special: the Tu%-160s this assault: 6 sent %(.*%), withdrawn at the capture, 0 still up at the round's end$") == 1,
      "the round's line says they were withdrawn")
-- (review of 7bcd4c4, finding 2) a Tu-160 flight's spawn raising: its error text in the log, not "error nil"
fresh(12)
SP.tu160.enabled = true
s = D.special
SPORT.spawn(0)
local rawFrom = spawnBomberFrom
spawnBomberFrom = function() error("boom: no spawner") end
L3 = #logs + 1
run(s, 0, SP.tu160.after_s + 1)
spawnBomberFrom = rawFrom
check(since(L3, "^special: the Tu%-160s at the airfield: 0 sent %(EA_Unit_01_Air%d: error .*boom: no spawner; EA_Unit_01_Air%d: error .*boom: no spawner%)$") == 1,
      "a spawn that raised: its error text logged")
check(s.tu.n == 0 and s.tu.why == "none could spawn" and next(s.tu.units) == nil, "none sent, none counted up")
SV_SetAircraft, HEAVY = rawSetAc, nil

print(fails == 0 and "spaceport test: all passed" or ("spaceport test: " .. fails .. " FAILED"))
os.exit(fails == 0 and 0 or 1)
