-- rounds_test.lua <mod dir> <work dir> (run by tools/checks/rounds_test.sh): the 0.73.80 fixes from the 31-round co-op test
-- of 0.73.79 (testing/logs/2026-11-04/R30_FINDINGS.json), on the real sv_core, sv_config, sv_rows, sv_ai, sv_spawn,
-- sv_anomalies, sv_rounds (startRound exposed), sv_amphib, sv_spaceport, sv_stats and sv_tells, the game stubbed:
--   perf 1 / 2, the units' SV_UnitAlive answers kept and asked again in turn (sv_spawn.lua ALIVE): a kept answer used
--     under 1 s, a unit with a plane seen down asked at once, a spawn's count kept (SV_Spawn wrapped, and said by the
--     spawns), a recycle forgetting it (SV_Recycle wrapped), an error never kept; the rounds' fighting check over 20
--     flights: never more than a tick's share (5) asked in one tick (20 at once before), each about once a second, the
--     round's clear on time (a kill seen by the sweep: at the next check); the budget line once a run, the round's line;
--   specials 0, the shuttle's unit taken off the spawner's list after its liftoff (SV_Recycle(unit, 1)), and again as its
--     next round is planned (a forced one too); one still up then: another special (the dice's), or a normal round (a
--     forced one); a co-op joiner's copy taken off once the host's removal has run there (SPC.clientClean);
--   specials 1, the pacing (specialFor): the chance up chance_step a round with no special, one for sure after max_gap
--     (x / the menu's SPECIAL ROUNDS), each kind from the bag once before any comes again, an ace round and a round
--     nothing can come in not counted, the early window's own roll, no two in a row; a pick that can't start swapped
--     (specialSwap; swap off, the early window: a normal round); every roll logged.
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
VERSION = "0.73.80-rounds.test"
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
local alive, asks = {}, 0
local errAlive = {}                              -- unit -> an error code SV_UnitAlive answers for it
function SV_UnitAlive(u) asks = asks + 1; if errAlive[u] then return errAlive[u] end return alive[u] or 0 end
function SV_SetAircraft() return 1 end
function SV_SetLevel() return 1 end
function SV_Invert() return 1 end
local spawns, recycled, recycleTakes = {}, {}, true
function SV_Spawn(unit)
    spawns[#spawns + 1] = unit
    if (alive[unit] or 0) > 0 then return -3 end        -- (the spawner: its last spawn still up)
    local n = unit:find("^SV_Unit_") and 1 or flightSize(unit)
    alive[unit] = n
    return n
end
function SV_Recycle(unit, force)
    recycled[#recycled + 1] = unit .. ":" .. tostring(force)
    if recycleTakes then alive[unit] = 0 end
    return 1
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
function liveAddr(o) return valid(o) and (addrOf(o) or 1) or nil end
svLevelOn = true
local FLAGS = {}
function svFlags() return FLAGS end
part("sv_config.lua")
part("sv_rows.lua"); part("sv_ai.lua")
function hudCallout(text, sub, big) callouts[#callouts + 1] = { text = text, sub = sub, big = big } end
part("sv_spawn.lua"); part("sv_anomalies.lua")
part("sv_rounds.lua", nil, { { "\nlocal function startRound%(%)", "\nfunction startRound()" } })
part("sv_amphib.lua"); part("sv_spaceport.lua"); part("sv_stats.lua"); part("sv_tells.lua")
function playerOnAirfield() return grounded end
function addCredits() end
LB.stat, LB.special = function() end, function() end
presetName = function() return "standard", 3 end
ROLE.live = nil                                  -- (roles off: the whole pool as before)
ANOM.fx = ANOM.fx or {}
local SH, SP, T = CFG.specials.shuttle, CFG.specials, CFG.hud.text
local function since(from, pat) local n = 0; for i = from, #logs do if logs[i]:find(pat) then n = n + 1 end end; return n end
local function lineOf(from, pat) for i = #logs, from, -1 do if logs[i]:find(pat) then return logs[i] end end end
local function fresh(round, state)
    alive, events, spawns, callouts, recycled, errAlive, planes = {}, {}, {}, {}, {}, {}, {}
    recycleTakes = true
    RUN = { kills = 0, credits = 0, specialPick = {}, specialAt = {},
           roundKills = { you = 0, allies = 0, ships = 0, defences = 0, airstrike = 0 } }
    D = { round = round or 10, state = state or "fighting", now = 100, at = 0, up = {}, flown = {}, queue = {}, spare = {},
          events = {}, orders = {}, taken = {}, waves = { {} }, wave = 1 }
end
local function ticks(t0, t1, each)                -- roundsTick every 250 ms (the round clock); each(t) after each tick
    local n = math.floor((t1 - t0) / 0.25 + 0.5)
    for i = 0, n do
        local t = t0 + i * 0.25
        D.now = t
        roundsTick(t)
        if each then each(t) end
        if not D then return end
    end
end

---------------------------------------------------------------------------------------------------- ALIVE
print("ALIVE: the units' answers kept, asked again in turn")
fresh(10)
D.now = 10                                       -- (the round clock: D.now, roundsTick's `now`)
local L0 = #logs + 1
ALIVE.tick(10)
check(since(L0, "^alive: %(0%.73%.80%) the units' SV_UnitAlive answers kept and asked again in turn: 8 to 32 asks a second") == 1,
      "the budget logged once a run: " .. tostring(lineOf(L0, "^alive: %(0")))
ALIVE.tick(10.25)
check(since(L0, "^alive: %(0%.73%.80%)") == 1, "... not again in the same run")
alive.A = 2
asks = 0
check(ALIVE.ask("A", 10.25) == 2 and asks == 1, "a unit never asked: asked at once")
check(ALIVE.ask("A", 10.5) == 2 and asks == 1, "asked again under 1 s on: the kept answer, no native ask")
alive.A = 0
check(ALIVE.ask("A", 10.75) == 2 and asks == 1, "shot down under 1 s on, nothing seen by the sweep: the kept answer (at most 1 s old)")
planes = { { unit = "A", down = true } }
check(ALIVE.ask("A", 10.75) == 0 and asks == 2, "a plane of it seen down by the sweep: asked at once, whatever's kept")
planes = {}
alive.B, D.now = 0, 11
check(ALIVE.ask("B", 11) == 0 and asks == 3, "B down: 0")
local rB = SV_Spawn("B")
check(rB == 2 and ALIVE.ask("B", 11) == 2 and asks == 3, "SV_Spawn (wrapped): its count kept, no native ask (" .. tostring(rB) .. ")")
SV_Recycle("B", 1)
check(ALIVE.ask("B", 11) == 0 and asks == 4, "SV_Recycle (wrapped): forgotten, asked again")
ALIVE.spawned("C", 4)
check(ALIVE.ask("C", 11) == 4 and asks == 4, "ALIVE.spawned: kept as its count")
ALIVE.spawned("C", -3)
alive.C = 1
check(ALIVE.ask("C", 11) == 1 and asks == 5, "a refused spawn: forgotten, asked again")
errAlive.E = -6
check(ALIVE.ask("E", 11) == -6 and ALIVE.ask("E", 11) == -6 and asks == 7, "an error (-6) never kept: asked each time")
errAlive.E = nil
check(ALIVE.fresh("A", 11) == 0 and asks == 8, "ALIVE.fresh: asked now")
-- a longer maxAge (a Spaceport ship watched by its hull: its unit asked every 3 s), once nobody asks for the shorter one
D.now = 20
ALIVE.tick(20)
alive.H = 3
local a0 = asks
check(ALIVE.ask("H", 20) == 3 and asks == a0 + 1, "H asked (every 1 s)")
check(ALIVE.ask("H", 20.75, 3) == 3 and asks == a0 + 1, "... asked for with 3 s within its 1 s: kept, still every 1 s")
check(ALIVE.ask("H", 22, 3) == 3 and asks == a0 + 1, "... and 2 s on, nobody asking for 1 s: kept (2 s old), every 3 s now")
ALIVE.tick(22.25)
check(asks == a0 + 1, "not asked again 2.25 s on (every 3 s)")
ALIVE.tick(22.75)
check(asks == a0 + 2, "asked again in turn 2.75 s on (0.9 of its 3 s)")
D = { round = 11, now = 50 }                     -- (a new run: nothing kept)
a0 = asks
check(ALIVE.ask("A", 50) == 0 and asks == a0 + 1, "a new run (D): nothing kept, asked")

---------------------------------------------------------------------------------------------------- the rounds' check
print("the fighting check over 20 flights: spread over the ticks")
fresh(10, "fighting")
local units = {}
for i = 1, 20 do
    local u = CFG.pool[i]
    units[#units + 1] = u
    alive[u], D.up[u] = 2, true
    D.now = 100
    ALIVE.spawned(u, 2)                          -- (as spawnFlight says it)
end
ALIVE.tick(99.75)
local perTick, maxTick, total = {}, 0, 0
local last = asks
ticks(100, 110, function(t)
    local n = asks - last
    last = asks
    perTick[#perTick + 1] = n
    if n > maxTick then maxTick = n end
    total = total + n
end)
check(maxTick <= 5, "never more than a tick's share asked in one tick (" .. maxTick .. " at most; 20 in one tick before)")
check(total >= 170 and total <= 230, "each about once a second: " .. total .. " asks in 10 s for 20 flights")
check(D.state == "fighting", "the round still on")
-- all shot down at once, nothing seen by the sweep: the round clear within the old check + the answers' age
for _, u in ipairs(units) do alive[u] = 0 end
local L1 = #logs + 1
local clearAt = nil
ticks(110.25, 114, function(t) if not clearAt and D.state == "wait" then clearAt = t end end)
check(clearAt and clearAt <= 111.25, "every flight down: the round clear by " .. tostring(clearAt) .. " (the check at 111; at most 1.25 s)")
check(since(L1, "^alive: round 10: %d+ native SV_UnitAlive asks %(%d+ at once: a plane of the flight seen down%), %d+ kept answers used") == 1,
      "the round's line at its clear: " .. tostring(lineOf(L1, "^alive: round 10")))
-- a kill seen by the sweep: at the next check
fresh(11, "fighting")
ALIVE.tick(99.75)
for i = 1, 4 do local u = CFG.pool[i]; alive[u], D.up[u] = 2, true; D.now = 100; ALIVE.spawned(u, 2) end
ticks(100, 102.5)
planes = {}
for i = 1, 4 do
    local u = CFG.pool[i]
    alive[u] = 0
    planes[#planes + 1] = { unit = u, down = true }; planes[#planes + 1] = { unit = u, down = true }
end
clearAt = nil
ticks(102.75, 105, function(t) if not clearAt and D.state == "wait" then clearAt = t end end)
check(clearAt == 103, "every plane seen down by the sweep: the round clear at the next check (" .. tostring(clearAt) .. ")")

---------------------------------------------------------------------------------------------------- the shuttle
print("the shuttle's unit off the spawner's list after its liftoff")
fresh(4, "wait")
D.at, D.announced = 1e9, true
alive[SH.unit] = 1
D.shuttleCheckAt = 200
local L2 = #logs + 1
ticks(200, 200)
check(recycled[1] == SH.unit .. ":1" and since(L2, "special: shuttle unit " .. SH.unit .. ": 1 alive 5 s after it was taken off "
      .. "%(0: a fresh one next time%); taken off the spawner's list %(SV_Recycle 1%): 0 alive after") == 1,
      "still up 5 s after: SV_Recycle(unit, 1), logged: " .. tostring(lineOf(L2, "special: shuttle unit")))
local rawRecycle = SV_Recycle
SV_Recycle = nil
alive[SH.unit] = 1
D.shuttleCheckAt = 201
ticks(201, 201)
check(since(L2, "no SV_Recycle in this runtime: the next shuttle round's plan tries again") == 1, "no SV_Recycle: logged")
SV_Recycle = rawRecycle

print("startRound: the shuttle's last one still up as its round is planned")
fresh(16, "wait")
alive[SH.unit] = 1
D.forceSpecial = "shuttle"
local L3 = #logs + 1
local okR, errR = pcall(startRound)
check(okR and D.special and D.special.kind == "shuttle" and recycled[1] == SH.unit .. ":1"
      and since(L3, "still up as round 17 is planned: taken off the spawner's list %(SV_Recycle 1%): gone") == 1,
      "taken off the list first, the shuttle round goes on (" .. tostring(errR) .. ")")
local strike = 0
for _ in pairs(D.strikeUnits or {}) do strike = strike + 1 end
check(strike > 0 and D.specialAtWas and D.specialAtWas.kind == "shuttle", "its strike flights picked, its cooldown's last kept")
-- the recycle doesn't take, a forced one: a normal round
fresh(16, "wait")
alive[SH.unit], recycleTakes = 1, false
D.forceSpecial = "shuttle"
L3 = #logs + 1
okR, errR = pcall(startRound)
strike = 0
for _ in pairs(D.strikeUnits or {}) do strike = strike + 1 end
check(okR and D.special == nil and strike == 0 and RUN.specialPick[17] == false
      and since(L3, "round 17: no shuttle can come %(its last shuttle is still on the spawner's list%); a normal round") == 1,
      "still up (forced): a normal round, no strike flights (" .. tostring(errR) .. ")")
-- the dice's shuttle: another special that can come
fresh(16, "wait")
alive[SH.unit], recycleTakes = 1, false
RUN.specialBag = { "shuttle", "anomaly", "ladon" }
local rawRandom = math.random
math.random = function(a, b) if a == nil then return 0.0 end return b or a end
RUN.specialGap = 5
D.announced = true
L3 = #logs + 1
okR, errR = pcall(startRound)
math.random = rawRandom
check(okR and D.special and D.special.kind == "anomaly" and RUN.lastSpecial == "anomaly" and RUN.specialAt.anomaly == 17
      and RUN.specialAt.shuttle == nil and RUN.specialPick[17] == "anomaly", "the dice's shuttle can't start: the anomaly instead ("
      .. tostring(errR) .. ")")
check(table.concat(RUN.specialBag, ",") == "ladon,shuttle", "the shuttle back in the bag, at its end (" .. table.concat(RUN.specialBag, ",") .. ")")
check(since(L3, "specials: round 17: the shuttle can't start %(its last shuttle is still on the spawner's list%): the anomaly instead") == 1
      and since(L3, "round 17: no shuttle can come %(its last shuttle is still on the spawner's list%); the anomaly instead") == 1,
      "logged: " .. tostring(lineOf(L3, "can't start")))
check(#callouts >= 1 and callouts[#callouts].text == string.format(T.special, 17) and callouts[#callouts].sub == T.anomaly_sub,
      "the round called out again as the anomaly's")

print("a co-op joiner: its shuttle copy off this game's list once the host's removal has run")
fresh(4, "fighting")
D.hostSpecial = { kind = "shuttle", state = "countdown" }
SPC.cl = { up = {}, due = {} }
SPC.clientClean(500)
D.hostSpecial = { kind = "shuttle", state = "done" }
SPC.clientClean(501)
alive[SH.unit] = 1
local L4 = #logs + 1
SPC.clientClean(501 + SH.remove_s + 14)
check(#recycled == 0, "not before the host's own removal (remove_s + 15 s)")
SPC.clientClean(501 + SH.remove_s + 15)
check(recycled[1] == SH.unit .. ":1" and since(L4, "coop: the host's shuttle taken off: its copy here " .. SH.unit
      .. " 1 alive: taken off this game's spawner list %(SV_Recycle 1%): 0 alive after") == 1,
      "then SV_Recycle(unit, 1), logged: " .. tostring(lineOf(L4, "coop: the host's shuttle taken off")))

---------------------------------------------------------------------------------------------------- the pacing
print("specialFor: the pacing")
local rolls = {}
math.random = function(a, b)
    if a == nil then return table.remove(rolls, 1) or 0.99 end
    return b or a                                -- (the bag's shuffle keeps the rotation's order; a draw the last)
end
local function newRun()
    RUN = { kills = 0, credits = 0, specialPick = {}, specialAt = {} }
    D = { round = 1, now = 0 }
end
newRun()
local L5 = #logs + 1
for r = 7, 10 do specialFor(r) end
check(RUN.specialPick[7] == false and RUN.specialPick[10] == false and RUN.specialGap == 4, "rounds 7-10, no special: 4 rounds counted")
check(since(L5, "^specials: round 7's roll: 0%.99 >= chance 0%.30 %(0 rounds since the last special%): no special; the bag: empty") == 1
      and since(L5, "^specials: round 8's roll: 0%.99 >= chance 0%.45 %(1 round since") == 1
      and since(L5, "^specials: round 9's roll: 0%.99 >= chance 0%.60") == 1
      and since(L5, "^specials: round 10's roll: 0%.99 >= chance 0%.75") == 1,
      "the chance up chance_step (0.15) a round, each roll logged")
check(specialFor(11) == "shuttle" and RUN.specialGap == 0 and RUN.lastSpecial == "shuttle"
      and since(L5, "^specials: round 11's roll: 0%.99 >= chance 0%.90 %(4 rounds since the last special, 4 or more: one for sure%): "
          .. "the shuttle, from the bag; the bag: anomaly, amphibious, ladon, alicorn, glitch, valka, spaceport") == 1
      and since(L5, "^specials: round 11 will be shuttle$") == 1, "max_gap (4): round 11 a special for sure, the bag's first")
check(specialFor(12) == nil and since(L5, "round 12's roll") == 0 and RUN.specialGap == 0, "round 12: none after a special, no roll")
-- the bag: each once before any comes again
local seen, order = {}, {}
for r = 13, 25, 2 do
    rolls = { 0.0 }
    local k = specialFor(r)
    if k then seen[k] = (seen[k] or 0) + 1; order[#order + 1] = k end
    specialFor(r + 1)
end
local n = 0
for _ in pairs(seen) do n = n + 1 end
check(n == 7 and not seen.shuttle and #order == 7, "the next 7 specials: the other 7 kinds, each once (" .. table.concat(order, ", ") .. ")")
rolls = { 0.0 }
check(specialFor(27) == "shuttle" and since(L5, "^specials: round 27's roll: .*: the shuttle, from the bag") == 1,
      "the bag empty: filled again, the shuttle first")
-- an ace round with no special isn't counted
newRun()
local rawAce = aceRound
aceRound = function(r, sp) if not sp and r == 16 then return 1 end return nil end
RUN.specialGap = 2
L5 = #logs + 1
specialFor(16)
check(RUN.specialGap == 2 and since(L5, "round 16's roll: .*: no special %(an ace round takes it, not counted%)") == 1,
      "an ace round: not counted (" .. tostring(RUN.specialGap) .. ")")
specialFor(17)
check(RUN.specialGap == 3, "the next round counted")
aceRound = rawAce
-- nothing can come: not counted
newRun()
for _, k in ipairs(SP.rotation) do RUN.specialAt[k] = 15 end
RUN.specialGap = 1
L5 = #logs + 1
check(specialFor(18) == nil and RUN.specialGap == 1 and since(L5, "round 18: no special can come %(each cooling down or not yet in%), not counted") == 1,
      "every kind cooling down: no roll, not counted")
-- the early window
newRun()
rolls = { 0.1 }
L5 = #logs + 1
check(specialFor(3) == "shuttle" and since(L5, "^specials: round 3's roll %(the early window: the shuttle only%): 0%.10 < chance 0%.35") == 1,
      "the early window: the shuttle's own roll")
-- the menu's SPECIAL ROUNDS fewer (x 0.5): sure after 8
newRun()
SETUP.specialsX = function() return 0.5 end
for r = 7, 14 do specialFor(r) end
rolls = {}
check(RUN.specialPick[14] == false and specialFor(15) ~= nil, "fewer specials (x0.5): sure after 8 rounds, not 4")
SETUP.specialsX = function() return 1 end
-- bag off: an even draw
newRun()
SP.bag = false
rolls = { 0.0 }
L5 = #logs + 1
check(specialFor(9) == "spaceport" and RUN.specialBag == nil and since(L5, "the spaceport, from an even draw") == 1,
      "bag = false: an even draw (the stub's last)")
SP.bag = true
-- swaps
newRun()
rolls = { 0.0 }
check(specialFor(9) == "shuttle", "round 9: the shuttle")
L5 = #logs + 1
local alt = specialSwap(9, "shuttle", "test", function(k) return k == "ladon" end)
check(alt == "ladon" and RUN.specialPick[9] == "ladon" and RUN.lastSpecial == "ladon"
      and table.concat(RUN.specialBag, ",") == "anomaly,amphibious,alicorn,glitch,valka,spaceport,shuttle",
      "can't start: the first one of the bag that can (ladon), the shuttle to the bag's end (" .. table.concat(RUN.specialBag, ",") .. ")")
check(since(L5, "^specials: round 9: the shuttle can't start %(test%): the ladon instead %(from the bag%)") == 1, "logged")
newRun()
rolls = { 0.0 }
RUN.specialGap = 3
specialFor(9)
alt = specialSwap(9, "shuttle", "test", function() return false end)
check(alt == nil and RUN.specialPick[9] == false and RUN.specialGap == 4 and RUN.lastSpecial == nil,
      "none can: a normal round, counted in the gap")
newRun()
SP.swap = false
rolls = { 0.0 }
specialFor(9)
L5 = #logs + 1
check(specialSwap(9, "shuttle", "test", function() return true end) == nil and since(L5, "and %[specials%] swap is off: a normal round") == 1,
      "swap = false: a normal round")
SP.swap = true
newRun()
rolls = { 0.1 }
specialFor(3)
L5 = #logs + 1
check(specialSwap(3, "shuttle", "test", function() return true end) == nil and since(L5, "in the early window %(only it comes then%)") == 1,
      "the early window: no swap")
check(specialSwap(4, "anomaly", "test", function() return true end) == nil, "not the dice's pick for that round: no swap")
math.random = rawRandom

logFile:close()
print(fails == 0 and "rounds test: all passed" or ("rounds test: " .. fails .. " FAILED"))
os.exit(fails == 0 and 0 or 1)
