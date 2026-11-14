-- store_events_test.lua <mod dir> <work dir> (run by tools/checks/store_events_test.sh): hard rule 64's rest (2026-11-11),
-- this game's landing STORE as a gate on the event package and the one-shot events that change the world fired again
-- here once it's shut (Scripts/sv_rounds_store.lua STOREQ), on the real sv_core, sv_config, sv_rows, sv_ai, sv_hud,
-- sv_spawn, sv_rounds (+ its pieces), sv_tactical, sv_stats, sv_tells, sv_director and sv_coop (+ its pieces, M exposed),
-- the game stubbed. The event package's stub drops what comes while a minigame is up (as the host's of 0.74.36 did:
-- SV_Event answered 1, none of its records ran) and otherwise does what the records do: flags set, counters added,
-- units taken off.
--   the gate: closed while the STORE is open and down at the airfield before it, 3 s after; a new spell each time;
--   the host: a boss's end (the flag it sets read back), a Wolf trap's free (dropped by a hold after it), a director's
--     free (dropped when its flight spawned again), the removals (the Alicorn's: its unit gone; a flight's switch-off),
--     pressure presets (only the last), a ship strike's orders, the Spaceport's fleet removal (its noted units), all
--     fired again here alone (never sent to the joiners again), in order, once the gate's open; one that took after all
--     not fired again; a solo game's the same;
--   bomber flights: one that appears in the STORE gets RE_SV_BomberOrders_NN once it's shut (its counter read back: the
--     shuttle's or the airfield's by SV_ShuttleRound), one whose appearance took gets nothing, one lost with the gate
--     open gets them too (the counter, not the gate); an event package without the counter: the airfield's retask when
--     SV_ShuttleRound is 0, nothing (logged) when it's 1; a heavy's route lost with it fired again after the orders, a
--     route that took not fired again, two loops of one flight lost in one STORE both fired again (a counter each); a
--     ship strike's flight left to its RE_SV_Strike; its watch on ALIVE's kept answers, not a native ask a tick;
--   a joiner: the host's forwarded one-shots held while its own STORE is open and fired in order once it's shut (each
--     effect read first), what shares a unit or chain with one still held behind it; the shuttle's countdown collapsed
--     to what changes the world (T-20, T-14, T-4, T, T+7, T+13, T+30, spaced by their own offsets from T-4 on), its
--     radio and the camera's start not played late; the Spaceport's launches (the boost boost_s after); repeating ones
--     fired at once as ever; held 420 s at most; its own rocket end fired now and again (not after a new retake's
--     rockets); nothing held with the gate open, nor behind held ones of other units (a backlog, a removal read back);
--     a held Spaceport removal dropped when its craft spawned again;
--   review fixes (2026-11-11): the host's queue back to back; an escort after its flight's own orders; the frees
--     undone by any newer hold of their flight; a boss's end fired late followed by the newer preset; the logs (no
--     summary while shut, held ones' wording, 'late' only with the gate shut); a STOREQ error never stops roundsTick;
--   the hooks in place (roundsTick, clientRounds, the SV_Event wrapper, hostEvent, ALIVE.spawned, spawnBomber).
-- Each section fails on the code before sv_rounds_store.lua (nothing fired again: the flags stay, the units stay up).
local MOD, WORK = arg[1], arg[2]
local fails = 0
local function check(ok, what) if ok then print("  ok   " .. what) else print("  FAIL " .. what); fails = fails + 1 end end
local function readAll(p) local f = assert(io.open(p, "rb")); local s = f:read("a"); f:close(); return (s:gsub("\r\n", "\n")) end
local PARTS = dofile("parts.lua")(MOD, readAll)
local function writeAll(p, s) local f = assert(io.open(p, "wb")); f:write(s); f:close() end
local function has(s, part) return s ~= nil and s:find(part, 1, true) ~= nil end
do
    local rawOpen = io.open
    io.open = function(p, m) return rawOpen((tostring(p):gsub("\\", "/")), m) end
end
writeAll(WORK .. "/config/survival.default.ini", readAll(MOD .. "/config/survival.default.ini"))

local clock = 1000
os.clock = function() return clock end           -- luacheck: ignore

VERSION = "0.74.52-storeq.test"
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

-- the event package, stubbed: every event in `events` (with D.now in `evAt`), its records run unless `minigame`
local FLAGS, alive = {}, {}
local events, evAt, minigame, counters = {}, {}, false, true
local FLEET = { "SV_Unit_SpFordTest", "SV_Unit_SpAegisTest" }
local function add(k) if FLAGS[k] ~= nil then FLAGS[k] = FLAGS[k] + 1 end end
local function records(name)
    if name == "RE_SV_AnomalyEnd" then FLAGS.SV_AnomalyUp = 0
    elseif name == "RE_SV_ValkaEnd" then FLAGS.SV_ValkaUp = 0
    elseif name == "RE_SV_AlcnRemove" then alive.SV_Unit_Alicorn = 0
    elseif name == "RE_SV_AwacsRemove" then FLAGS.SV_AwacsAir = 0
    elseif name == "RE_SV_SpFleetRemove" then for _, u in ipairs(FLEET) do alive[u] = 0 end
    elseif name:match("^RE_SV_BomberOrders_(%d%d)$") then add("SV_BOrd_" .. name:match("(%d%d)$"))
    elseif name:match("^RE_SV_BomberRetask_(%d%d)$") then add("SV_BOrd_" .. name:match("(%d%d)$"))
    elseif name:match("^RE_SV_HeavyRoute_(%d%d)%u$") then add("SV_BRoute_" .. name:match("_(%d%d)%u$") .. "R")
    elseif name:match("^RE_SV_HeavyLoop_(%d%d)%u%u$") then local nn, L = name:match("_(%d%d)(%u)%u$"); add("SV_BRoute_" .. nn .. L)
    elseif name:match("^RE_SV_FlightOrders_(%d%d)$") then FLAGS["SV_Up_" .. name:match("(%d%d)$")] = 1
    elseif name:match("^RE_SV_SpLcacRemove(%w+)$") then alive["SV_Unit_SpLcac" .. name:match("^RE_SV_SpLcacRemove(%w+)$")] = 0
    end
end
function SV_Event(name)
    name = tostring(name)
    events[#events + 1] = name
    evAt[#evAt + 1] = D and D.now or 0
    if not minigame then records(name) end
    return 1
end
local asks = {}                                                   -- (native SV_UnitAlive asks, by unit)
function SV_UnitAlive(u) asks[u] = (asks[u] or 0) + 1; return alive[u] or 0 end
function SV_SetAircraft() return 1 end
function SV_SetLevel() return 1 end
local spawns = {}
function SV_Spawn(unit, x, y, z, yaw)
    spawns[#spawns + 1] = unit
    local i = BOMBER_INDEX and BOMBER_INDEX[unit]
    if i and not minigame then add(string.format("SV_BOrd_%02d", i)) end    -- (SV_BomberUp_NN's count)
    alive[unit] = 2
    return 2
end
function SV_MenuChoice() return 0 end
function SV_CoopOpen() return 1 end
function SV_CoopClose() end
local sent = {}
function SV_CoopSend(msg, rel, to) sent[#sent + 1] = tostring(to) .. ">" .. msg; return 1 end
function SV_CoopRecv() return "" end
function SV_CoopInfo() return "open=1;state=linked;peers=1/linked/40/10/p" end
function SV_CoopMe() end
function SV_CoopReset() end
function SV_CoopTrack() return 1 end
function SV_CoopBind() return 1 end
function SV_CoopPeer() return 1 end
local peerState = {}
function SV_CoopPeerAt(slot) return peerState[slot] or "" end
SETUP = { enemyX = function() return 1 end, specialsX = function() return 1 end, breakS = function() return 20 end,
          skillAdd = function() return 0 end }

local function part(name, chunk, edits) PARTS.load(name, chunk, edits) end
part("sv_core.lua", "@" .. WORK .. "/Scripts/sv_core.lua")
local logs = {}
local logFile = assert(io.open(WORK .. "/test_lua.log", "wb"))
function log(s) logs[#logs + 1] = s; logFile:write(os.date("%H:%M:%S ") .. s .. "\n") end
function valid(o) return type(o) == "table" and not o.gone end
function nameOf(o) return type(o) == "table" and (o.full or "?") or "?" end
function addrOf(o) return type(o) == "table" and o.addr or nil end
part("sv_config.lua")
part("sv_rows.lua"); part("sv_ai.lua"); part("sv_hud.lua"); part("sv_spawn.lua"); part("sv_rounds.lua"); part("sv_flights.lua")
part("sv_tactical.lua"); part("sv_stats.lua"); part("sv_tells.lua"); part("sv_director.lua")
part("sv_coop.lua", nil, { { "\nlocal M = {", "\nM = {" } })
local M = _G.M
function playerOnAirfield() return grounded end
function airfieldTick() end
function bombTick() end
svFlags = function() return FLAGS end
LB.stat, LB.special = function() end, function() end
presetName = function() return "standard", 3 end
ROLE.live = { duelist = true, lancer = true, wolf = true, skirm = true }
ANOM.fx = ANOM.fx or {}
AMPH.runTick = AMPH.runTick or function() end
SPC.kinds = SPC.kinds or {}
math.randomseed(5)

local pawn = { full = "BP_PlayerPlane_PP1000_f16c_C_1", addr = 9, MaxHealth = 100, HealthInternal = 800 }
function pawn:K2_GetActorLocation() return { X = 0, Y = 0, Z = 300000 } end
function pawn:GetActorForwardVector() return { X = 1, Y = 0, Z = 0 } end
survivalPC = { Pawn = pawn, full = "PC", addr = 3 }

local function line(prefix, from)
    for i = #logs, from or 1, -1 do if logs[i]:sub(1, #prefix) == prefix then return logs[i] end end
    return nil
end
local function found(part, from)
    for i = from or 1, #logs do if logs[i]:find(part, 1, true) then return logs[i] end end
    return nil
end
local function n(name) local c = 0; for _, e in ipairs(events) do if e == name then c = c + 1 end end; return c end
local function at(name, k)                                        -- the round-clock time of name's k-th fire
    local c = 0
    for i, e in ipairs(events) do if e == name then c = c + 1; if c == (k or 1) then return evAt[i] end end end
    return nil
end
local function order(pat)                                         -- the events matching pat, in order
    local t = {}
    for _, e in ipairs(events) do if e:find(pat) then t[#t + 1] = e end end
    return table.concat(t, ",")
end
local function sentN(name) local c = 0; for _, m in ipairs(sent) do if m:find("ev|" .. name, 1, true) and m:sub(-#name) == name then c = c + 1 end end; return c end
local function near(a, b) return a ~= nil and b ~= nil and math.abs(a - b) < 0.01 end

-- player 2's state as the runtime reports it (flags: 1 in Survival's level, 2 alive, 4 down at the airfield)
local function p2(flags) peerState[1] = string.format("5000000,0,300000,0,0,0,600,100,%d,100", flags) end
local function room(role)                        -- "host" (player 2 flying), "join", or nil: solo
    CFG.coop.enabled = role ~= nil
    COOP.open, COOP.role, COOP.slot = role ~= nil, role, role == "join" and 1 or (role and 0 or nil)
    if role == "host" then p2(3); clock = clock + 0.25; COOP.tick(0) end
end
local U1 = "ERA_Unit_01_Dep_Air0"
local function fresh(role, state)
    events, evAt, spawns, sent, alive, FLAGS = {}, {}, {}, {}, {}, {}
    D = { round = 7, state = state or "fighting", now = 99, at = 0, up = { [U1] = true }, flown = {}, queue = {}, spare = {},
          events = {}, orders = {}, pressure = "B", wave = 1 }
    alive[U1] = 2
    grounded, minigame, counters = false, false, true
    SPC.gate = nil
    D.special = nil
    room(role)
    if role == "join" then M.spawnQ, M.cunits, M.copies, M.readyAt = {}, {}, {}, nil end
end
local function store(on) minigame, D.musicHold = on, on and 1 or 0 end
-- every 250 ms from t0 to t1 on the round clock: roundsTick (the host's rounds, or clientRounds on a joiner)
local function ticks(t0, t1)
    local k = math.floor((t1 - t0) / 0.25 + 0.5)
    for i = 0, k do
        local t = t0 + i * 0.25
        D.now = t
        clock = clock + 0.25
        roundsTick(t)
    end
end
local function fire(name) D.now = D.now or 0; return SV_Event(name) end     -- (the wrapper, as every part fires)

---------------------------------------------------------------------------------------------------- the gate
print("the gate: this game's landing STORE")
fresh("host")
ticks(100, 101)
check(STOREQ.gate(101) == true, "flying: open")
grounded = true
ticks(101.25, 102)
local o, why = STOREQ.gate(102)
check(o == false and why == "you're down at the airfield, your STORE not open yet", "down at the airfield, no STORE yet: closed (" .. tostring(why) .. ")")
store(true)
ticks(102.25, 110)
o, why = STOREQ.gate(110)
check(o == false and why == "your landing STORE is open", "the STORE open: closed (" .. tostring(why) .. ")")
store(false)
ticks(110.25, 112)
o, why = STOREQ.gate(112)
check(o == false and why == "your landing STORE closed a moment ago", "the STORE shut 2 s ago (still on the airfield): closed (" .. tostring(why) .. ")")
ticks(112.25, 113.5)
check(STOREQ.gate(113.5) == true and SPC.gate.spell == 1, "3 s after its last held tick (110): open, on the runway; one closed spell")
check(SPC.storeShut == STOREQ.gate, "SPC.storeShut is the gate (the shuttle's replay, the Spaceport's relaunch)")

---------------------------------------------------------------------------------------------------- the host
print("the host: its one-shots fired again here once its STORE is shut")
-- a boss's end in the STORE (a joiner shot MINDRIPPER down while she shopped): lost, then fired here alone, read back
fresh("host")
FLAGS.SV_AnomalyUp, FLAGS.SV_ValkaUp = 1, 1
local from = #logs + 1
ticks(100, 100.5)
grounded = true; store(true)
ticks(100.75, 105)
fire("RE_SV_AnomalyEnd")
check(n("RE_SV_AnomalyEnd") == 1 and FLAGS.SV_AnomalyUp == 1 and sentN("RE_SV_AnomalyEnd") == 1,
      "RE_SV_AnomalyEnd fired in her STORE: lost here (SV_AnomalyUp still 1), sent to player 2 on time")
check(found("storeq: RE_SV_AnomalyEnd fired while your landing STORE is open: fired again here once it's shut, unless it took after all", from) ~= nil,
      "... logged as to be fired again")
ticks(105.25, 140)
check(n("RE_SV_AnomalyEnd") == 1, "... nothing fired again while her STORE stays open")
store(false)
ticks(140.25, 142.75)
check(n("RE_SV_AnomalyEnd") == 1, "... nor in the 3 s after its last held tick (140)")
ticks(143, 150)
check(n("RE_SV_AnomalyEnd") == 2 and near(at("RE_SV_AnomalyEnd", 2), 143) and FLAGS.SV_AnomalyUp == 0
      and sentN("RE_SV_AnomalyEnd") == 1,
      "... fired again here 3 s after its last held tick (143), here alone (player 2 had it), it took (SV_AnomalyUp 0)")
check(found("storeq: this game's events can take again: 1 to fire here in order (AnomalyEnd 1)", from) ~= nil
      and found("storeq: RE_SV_AnomalyEnd took here (SV_AnomalyUp 0)", from) ~= nil
      and found("storeq: done here: AnomalyEnd (took 1)", from) ~= nil,
      "... logged: the pass, the fire, whether it took, the summary")
-- one that took after all (the gate closed, the package not dropping it): not fired again
fresh("host")
FLAGS.SV_ValkaUp = 1
grounded = true; D.musicHold = 1                                   -- (the hold on, the minigame not: it takes)
from = #logs + 1
ticks(100, 101)
fire("RE_SV_ValkaEnd")
D.musicHold = 0; grounded = false
ticks(101.25, 110)
check(n("RE_SV_ValkaEnd") == 1 and FLAGS.SV_ValkaUp == 0
      and found("storeq: RE_SV_ValkaEnd not fired again: it took after all (SV_ValkaUp 0)", from) ~= nil,
      "RE_SV_ValkaEnd in the STORE that took after all: read first, not fired again (logged)")
-- several in order; a Wolf trap's free undone by a hold after it, a director's free whose flight spawned again, a
-- removal, the pressure presets (the last one only), a flight's switch-off
fresh("host")
FLAGS.SV_AnomalyUp = 1
alive.SV_Unit_Alicorn = 1
local W3 = poolUnit(3)
local D4 = poolUnit(4)
alive[W3], alive[D4], alive[poolUnit(5)] = 2, 2, 2
ticks(100, 100.5)
grounded = true; store(true)
ticks(100.75, 102)
fire("RE_SV_WolfFree_03B"); fire("RE_SV_WolfFree_03A")
fire("RE_SV_DirFree_04")
fire("RE_SV_AlcnRemove")
fire("RE_SV_PressureA"); fire("RE_SV_PressureB")
fire("RE_SV_FlightOff_05")
fire("RE_SV_AnomalyEnd")
fire("RE_SV_WolfHold_03B")                                         -- (the trap held again: its free goes)
ALIVE.spawned(D4, 2)                                               -- (flight 4 spawned again: a fresh one, its own orders)
fire("RE_SV_RaidPing_01"); fire("RE_SV_ValkaHold")                 -- (repeating ones: never queued)
check(select(1, STOREQ.pending()) == 6, "queued: WolfFree 03A, DirFree 04, AlcnRemove, PressureA, PressureB, FlightOff 05, "
      .. "AnomalyEnd less PressureA and WolfFree 03B (" .. tostring(STOREQ.pending()) .. ")")
from = #logs + 1
store(false); grounded = false
ticks(102.25, 140)
local again = {}
for i, e in ipairs(events) do if evAt[i] > 102.2 then again[#again + 1] = e end end
check(table.concat(again, ",") == "RE_SV_WolfFree_03A,RE_SV_AlcnRemove,RE_SV_PressureB,RE_SV_FlightOff_05,RE_SV_AnomalyEnd",
      "fired again in order: " .. table.concat(again, ","))
check(alive.SV_Unit_Alicorn == 0 and FLAGS.SV_AnomalyUp == 0 and n("RE_SV_DirFree_04") == 1 and n("RE_SV_WolfFree_03B") == 1
      and n("RE_SV_PressureA") == 1 and n("RE_SV_RaidPing_01") == 1 and n("RE_SV_ValkaHold") == 1,
      "... the Alicorn gone, the end in; DirFree 04 (spawned again), WolfFree 03B (held again), PressureA (B after it) and "
      .. "the repeating ones not fired again")
check(found("storeq: RE_SV_WolfFree_03B not fired again here: RE_SV_WolfHold_03B came after it") ~= nil
      and found("storeq: RE_SV_DirFree_04 not fired again here: " .. D4 .. " spawned again since", from) ~= nil
      and found("storeq: RE_SV_PressureA not fired again here: RE_SV_PressureB came after it") ~= nil
      and found("storeq: RE_SV_AlcnRemove took here (none alive)", from) ~= nil
      and found("storeq: RE_SV_FlightOff_05 fired again here (WolfFree", from) == nil
      and found("storeq: RE_SV_FlightOff_05 fired again here (FlightOff: the first this time)", from) ~= nil,
      "... each logged once with its reason")
check(sentN("RE_SV_AlcnRemove") == 1 and sentN("RE_SV_WolfFree_03A") == 1 and sentN("RE_SV_FlightOff_05") == 1,
      "... none sent to player 2 again")
-- a removal that never takes: TRIES in all, logged
fresh("host")
alive.SV_Unit_Alicorn = 1
grounded = true; store(true)
ticks(100, 101)
fire("RE_SV_AlcnRemove")
minigame = false; D.musicHold = 0; grounded = false
local rawRec = records
records = function(name) if name ~= "RE_SV_AlcnRemove" then rawRec(name) end end   -- (it never goes)
from = #logs + 1
ticks(101.25, 140)
records = rawRec
check(n("RE_SV_AlcnRemove") == 4 and found("storeq: RE_SV_AlcnRemove never took here in 3 tries (1 alive)", from) ~= nil
      and found("storeq: RE_SV_AlcnRemove didn't take here (1 alive): fired here again, try 2 of 3 (fired)", from) ~= nil,
      "a removal that never takes: fired again 3 times, 3 s apart, then given up (logged)")
-- the Spaceport's fleet removal: its units noted, read back
fresh("host")
for _, u in ipairs(FLEET) do alive[u] = 1 end
STOREQ.note("RE_SV_SpFleetRemove", FLEET)
grounded = true; store(true)
ticks(100, 101)
fire("RE_SV_SpFleetRemove")
store(false); grounded = false
from = #logs + 1
ticks(101.25, 110)
check(n("RE_SV_SpFleetRemove") == 2 and alive[FLEET[1]] == 0 and found("storeq: RE_SV_SpFleetRemove took here (none alive)", from) ~= nil,
      "the Spaceport's fleet removal lost in the STORE: fired again, its noted units gone")
-- solo: the STORE pauses the game; the same once it's shut
fresh(nil)
FLAGS.SV_ValkaUp = 1
grounded = true; store(true)
ticks(100, 101)
fire("RE_SV_ValkaEnd")
store(false); grounded = false
ticks(101.25, 110)
check(n("RE_SV_ValkaEnd") == 2 and FLAGS.SV_ValkaUp == 0 and #sent == 0, "solo: VALKA's end lost in the STORE fired again once it's shut, nothing sent")
-- nothing queued with the gate open
fresh("host")
FLAGS.SV_AnomalyUp = 1
ticks(100, 101)
fire("RE_SV_AnomalyEnd")
ticks(101.25, 110)
check(n("RE_SV_AnomalyEnd") == 1 and select(1, STOREQ.pending()) == 0, "flying: fired once, nothing queued")
-- VOID WATCHER's removal and its sending home: their flags read back
fresh("host")
FLAGS.SV_AwacsAir, FLAGS.SV_AwacsHome = 1, 0
grounded = true; store(true)
ticks(100, 101)
fire("RE_SV_AwacsHome"); fire("RE_SV_AwacsRemove")
store(false); grounded = false
from = #logs + 1
records = function(name) if name == "RE_SV_AwacsHome" then FLAGS.SV_AwacsHome = 1 end; rawRec(name) end
ticks(101.25, 115)
records = rawRec
check(order("^RE_SV_Awacs") == "RE_SV_AwacsHome,RE_SV_AwacsRemove,RE_SV_AwacsHome,RE_SV_AwacsRemove" and FLAGS.SV_AwacsAir == 0
      and FLAGS.SV_AwacsHome == 1 and found("storeq: RE_SV_AwacsRemove took here (SV_AwacsAir 0)", from) ~= nil,
      "VOID WATCHER sent home and taken off in the STORE: both fired again in order, their flags read back")
-- a ship strike's orders (each player's own: kept on the host)
fresh("host")
local B2 = CFG.airfield.bombers.pool[2]
alive[B2] = 2
grounded = true; store(true)
ticks(100, 101)
fire("RE_SV_StrikeA1_02")
store(false); grounded = false
ticks(101.25, 110)
check(n("RE_SV_StrikeA1_02") == 2 and sentN("RE_SV_StrikeA1_02") == 0, "a ship strike's orders lost in the STORE: fired again here")

---------------------------------------------------------------------------------------------------- bomber flights
print("bomber flights: their appearance's orders read back, given again")
local function bomberScene(role, withCounter)
    fresh(role)
    for i = 1, #CFG.airfield.bombers.pool do
        if withCounter then
            FLAGS[string.format("SV_BOrd_%02d", i)] = 0
            for _, x in ipairs({ "R", "A", "B", "C", "D", "E", "F" }) do FLAGS[string.format("SV_BRoute_%02d%s", i, x)] = 0 end
        end
    end
    FLAGS.SV_ShuttleRound = 0
end
local BU = CFG.airfield.bombers.pool[1]
local function bspawn(unit, opts) return spawnBomberFrom(unit, opts) end
-- spawned in her STORE (others flying): its appearance lost; RE_SV_BomberOrders_01 once it's shut, read back
bomberScene("host", true)
ticks(100, 100.5)
grounded = true; store(true)
ticks(100.75, 101)
from = #logs + 1
bspawn(BU)
check(FLAGS.SV_BOrd_01 == 0 and found("storeq: bomber flight " .. BU .. " appeared while your landing STORE is open", from) ~= nil,
      "a bomber flight up in the STORE: its appearance's orders lost (SV_BOrd_01 0), logged")
ticks(101.25, 130)
check(n("RE_SV_BomberOrders_01") == 0, "... nothing fired while the STORE stays open")
store(false); grounded = false
ticks(130.25, 140)
check(n("RE_SV_BomberOrders_01") == 1 and near(at("RE_SV_BomberOrders_01"), 133) and FLAGS.SV_BOrd_01 == 1
      and sentN("RE_SV_BomberOrders_01") == 0
      and found("storeq: bomber flight " .. BU .. " appeared without its orders here (SV_BOrd_01 still 0): RE_SV_BomberOrders_01 fired, "
          .. "try 1 of 3 (SV_ShuttleRound 0: the airfield's)", from) ~= nil
      and found("storeq: bomber flight " .. BU .. " has its orders here (SV_BOrd_01 1; RE_SV_BomberOrders_01 fired here 1 time)", from) ~= nil,
      "... fired here alone 3 s after its last held tick (133), the airfield's; it took (logged)")
-- the shuttle round: the same event gives the shuttle's (its records' branch by SV_ShuttleRound)
bomberScene("host", true)
FLAGS.SV_ShuttleRound = 1
grounded = true; store(true)
ticks(100, 101)
bspawn(BU)
store(false); grounded = false
from = #logs + 1
ticks(101.25, 110)
check(n("RE_SV_BomberOrders_01") == 1 and n("RE_SV_BomberRetask_01") == 0
      and found("(SV_ShuttleRound 1: the shuttle's orders)", from) ~= nil,
      "the shuttle round's strike lost in the STORE: RE_SV_BomberOrders_01 (the shuttle's while SV_ShuttleRound is 1), never the airfield's retask")
-- its appearance took (flying): nothing fired, nothing said
bomberScene("host", true)
from = #logs + 1
ticks(100, 101)
bspawn(BU)
ticks(101.25, 112)
check(n("RE_SV_BomberOrders_01") == 0 and FLAGS.SV_BOrd_01 == 1 and found("storeq: bomber flight", from) == nil,
      "a bomber flight whose appearance took: nothing fired, nothing logged")
-- lost with the gate open (the counter says so, not the gate): given at its check
bomberScene("host", true)
ticks(100, 101)
minigame = true                                                   -- (lost some other way: the gate open)
bspawn(BU)
minigame = false
ticks(101.25, 112)
check(n("RE_SV_BomberOrders_01") == 1 and near(at("RE_SV_BomberOrders_01"), 105) and FLAGS.SV_BOrd_01 == 1,
      "a bomber flight's orders lost with the gate open: read back 4 s on (105), given then")
-- an event package without the counter: the airfield's retask once it's shut (SV_ShuttleRound 0), nothing when it's 1
bomberScene("host", false)
grounded = true; store(true)
ticks(100, 101)
bspawn(BU)
store(false); grounded = false
from = #logs + 1
ticks(101.25, 110)
check(n("RE_SV_BomberRetask_01") == 1 and n("RE_SV_BomberOrders_01") == 0
      and found("isn't readable: an event package without SV_BOrd_NN", from) ~= nil,
      "an older package (no SV_BOrd_NN): RE_SV_BomberRetask_01 (the airfield's) once it's shut, logged as not readable")
bomberScene("host", false)
FLAGS.SV_ShuttleRound = 1
grounded = true; store(true)
ticks(100, 101)
bspawn(BU)
store(false); grounded = false
from = #logs + 1
ticks(101.25, 110)
check(n("RE_SV_BomberRetask_01") == 0 and n("RE_SV_BomberOrders_01") == 0
      and found("its orders not given again (SV_ShuttleRound 1: the shuttle's need the event package with RE_SV_BomberOrders_NN", from) ~= nil,
      "... while SV_ShuttleRound is 1: nothing (the airfield's would be wrong), logged")
-- a heavy flight: its route lost with its orders: the orders first, the route 3 s after them; a route that took isn't
local HU
for u in pairs(HEAVY_UNIT) do if BOMBER_INDEX[u] then HU = u; break end end
local hi = BOMBER_INDEX[HU]
local RT, BO = "RE_SV_HeavyRoute_%02d", "RE_SV_BomberOrders_%02d"
bomberScene("host", true)
CFG.airfield.bombers.heavy_route = true
grounded = true; store(true)
ticks(100, 101)
bspawn(HU, { bearing = 0 })
ticks(101.25, 110)                                                 -- (its route queued 3 s on, fired in the STORE)
local route = order(string.format(RT, hi))
check(route ~= "" and FLAGS[string.format("SV_BRoute_%02dR", hi)] == 0, "a heavy flight up in the STORE: its route (" .. route .. ") lost too")
store(false); grounded = false
ticks(110.25, 130)
local ob, rt = at(string.format(BO, hi)), nil
for i, e in ipairs(events) do if e:find(string.format(RT, hi), 1, true) and evAt[i] > 110 then rt = evAt[i] end end
check(near(ob, 113) and near(rt, 116) and FLAGS[string.format("SV_BRoute_%02dR", hi)] == 1,
      "... once it's shut: its orders (" .. tostring(ob) .. "), its route 3 s after them (" .. tostring(rt) .. "), the route took")
bomberScene("host", true)
CFG.airfield.bombers.heavy_route = true
ticks(100, 101)
bspawn(HU, { bearing = 0 })
ticks(101.25, 103.5)
grounded = true; D.musicHold = 1                                   -- (the gate shuts as the route goes: it takes all the same)
ticks(103.75, 106)
D.musicHold = 0; grounded = false
ticks(106.25, 120)
check(#order(string.format(RT, hi)) > 0 and select(2, order(string.format(RT, hi)):gsub(",", ",")) == 0
      and FLAGS[string.format("SV_BRoute_%02dR", hi)] == 1, "a route that took in a closed gate: read back, not fired again (a second run starts it over)")
-- a ship strike's flight: its RE_SV_Strike is its orders, never RE_SV_BomberOrders
bomberScene("host", true)
local SB = CFG.airfield.bombers.pool[2]
D.shipStrike = { [SB] = "SV_Unit_ShipA1" }
local rawStrike = ALLY.strike
ALLY.strike = function() end                                       -- (sv_allies.lua's queue: fired here by hand)
grounded = true; store(true)
ticks(100, 101)
bspawn(SB)
fire("RE_SV_StrikeA1_02")
store(false); grounded = false
ticks(101.25, 115)
check(n("RE_SV_BomberOrders_02") == 0 and n("RE_SV_StrikeA1_02") == 2, "a ship strike's flight up in the STORE: its RE_SV_Strike fired again, never its appearance's orders")
D.shipStrike, ALLY.strike = nil, rawStrike

---------------------------------------------------------------------------------------------------- a joiner
print("a joiner: the host's one-shots held while its own STORE is open")
local function deliver(name) hostEvent(name) end                   -- (the host's "ev|<name>", as sv_coop_migration.lua passes it)
fresh("join")
FLAGS.SV_AnomalyUp = 1
alive.SV_Unit_Alicorn = 1
ticks(100, 103)                                                    -- (its level ready: READY_S)
deliver("RE_SV_AnomalyEnd")
check(n("RE_SV_AnomalyEnd") == 1 and select(1, STOREQ.pending()) == 0, "flying: the host's RE_SV_AnomalyEnd fired at once, nothing held")
FLAGS.SV_AnomalyUp = 1
grounded = true; store(true)
ticks(103.25, 104)
from = #logs + 1
deliver("RE_SV_AnomalyEnd"); deliver("RE_SV_WolfFree_03A"); deliver("RE_SV_AlcnRemove")
deliver("RE_SV_RaidPing_02")                                       -- (repeating: fired at once, as ever)
check(n("RE_SV_AnomalyEnd") == 1 and n("RE_SV_WolfFree_03A") == 0 and n("RE_SV_AlcnRemove") == 0 and n("RE_SV_RaidPing_02") == 1,
      "in its own STORE: the boss's end, the free and the removal held (not fired), the raid ping fired as ever")
check(found("storeq: the host's RE_SV_AnomalyEnd held here: your landing STORE is open; fired here once it's shut", from) ~= nil,
      "... logged once per kind")
ticks(104.25, 130)
store(false)
ticks(130.25, 132)
deliver("RE_SV_ValkaAlertOff")                                     -- (still closed: held behind them)
grounded = false
ticks(132.25, 150)
local jt = {}
for i, e in ipairs(events) do if evAt[i] > 130 then jt[#jt + 1] = e end end
check(table.concat(jt, ",") == "RE_SV_AnomalyEnd,RE_SV_WolfFree_03A,RE_SV_AlcnRemove,RE_SV_ValkaAlertOff",
      "once its STORE is shut 3 s: fired here in order (" .. table.concat(jt, ",") .. ")")
check(FLAGS.SV_AnomalyUp == 0 and alive.SV_Unit_Alicorn == 0 and #sent == 0, "... they took here; nothing sent")
-- the removal of copies already gone here: read first, not fired
fresh("join")
ticks(100, 103)
alive.SV_Unit_Alicorn = 0
grounded = true; store(true)
ticks(103.25, 104)
deliver("RE_SV_AlcnRemove")
store(false); grounded = false
from = #logs + 1
ticks(104.25, 115)
check(n("RE_SV_AlcnRemove") == 0 and found("storeq: RE_SV_AlcnRemove not fired here: its effect is in already (none alive)", from) ~= nil,
      "a held removal whose copies are gone here already: not fired (logged)")
-- the shuttle's countdown collapsed: T-20, T-14, T-4, T, T+7, T+13, T+30, spaced by their own offsets from T-4 on (T-20's
-- MinHealth kept: a copy left mortal could be shot down here); radio and the camera's start dropped
fresh("join")
local T = CFG.specials.shuttle.countdown_s
ticks(100, 103)
grounded = true; store(true)
ticks(103.25, 104)
from = #logs + 1
for s = T - 22, T + 30 do D.now = 104 + (s - (T - 22)); deliver("RE_SV_ShuttleT_" .. s) end
check(order("^RE_SV_ShuttleT_") == "" and select(1, STOREQ.pending()) == 7,
      "the host's countdown in its STORE: nothing fired here, 7 seconds held (" .. tostring(STOREQ.pending()) .. ")")
check(found("storeq: the host's RE_SV_ShuttleT_" .. (T - 22) .. " not fired here: your landing STORE is open, and it changes nothing that lasts", from) ~= nil,
      "... the rest (radio, sounds, the camera's start) not played late, logged once")
D.now = 157
store(false); grounded = false
ticks(157.25, 200)
local want = {}
for _, d in ipairs({ -20, -14, -4, 0, 7, 13, 30 }) do want[#want + 1] = "RE_SV_ShuttleT_" .. (T + d) end
check(order("^RE_SV_ShuttleT_") == table.concat(want, ","), "... once it's shut: " .. order("^RE_SV_ShuttleT_"))
local sT = {}
for _, d in ipairs({ -20, -14, -4, 0, 7, 13, 30 }) do sT[#sT + 1] = string.format("%.2f", at("RE_SV_ShuttleT_" .. (T + d)) or -1) end
check(table.concat(sT, ",") == "159.00,159.00,159.00,163.00,170.00,176.00,193.00",
      "... from 3 s after its last held moment (156: 159) T-20, T-14 and T-4 at once, then T 4 s, T+7 7 s, T+13 6 s and T+30 "
      .. "17 s on, as on the host (" .. table.concat(sT, ",") .. ")")
check(found("storeq: RE_SV_ShuttleT_" .. (T - 20) .. " fired here (held 53 s) (ShuttleT: the first this time)", from) ~= nil and found("ShuttleT fired again here", from) == nil
      and found("storeq: done here: ShuttleT (fired 7, dropped 46)", from) ~= nil,
      "... logged as held, never as 'fired again'; the summary counts the dropped seconds")
-- what comes while one of its chain is still held, or fired here a moment ago, goes behind it (the gate open again)
fresh("join")
ticks(100, 103)
grounded = true; store(true)
ticks(103.25, 103.5)
deliver("RE_SV_ShuttleT_" .. (T - 14))
D.now = 104
deliver("RE_SV_ShuttleT_" .. (T - 4))
store(false); grounded = false
ticks(104.25, 107)                                                 -- (open at 107: T-14 and T-4 fired)
D.now = 107.1
deliver("RE_SV_ShuttleT_" .. T)                                   -- (the gate open: T-4 fired here 0.1 s ago, so T waits)
ticks(107.25, 107.25)
check(order("^RE_SV_ShuttleT_") == "RE_SV_ShuttleT_" .. (T - 14) .. ",RE_SV_ShuttleT_" .. (T - 4) and near(at("RE_SV_ShuttleT_" .. (T - 4)), 107),
      "the gate open, T-14 and T-4 fired at once (107): T, come 0.1 s after T-4 fired here, waits behind it")
ticks(107.5, 115)
check(order("^RE_SV_ShuttleT_") == "RE_SV_ShuttleT_" .. (T - 14) .. ",RE_SV_ShuttleT_" .. (T - 4) .. ",RE_SV_ShuttleT_" .. T
      and near(at("RE_SV_ShuttleT_" .. T), 111),
      "... T 4 s after T-4 here, as on the host (" .. tostring(at("RE_SV_ShuttleT_" .. T)) .. ")")
-- the Spaceport's launches; held at most 420 s
fresh("join")
ticks(100, 103)
grounded = true; store(true)
ticks(103.25, 104)
deliver("RE_SV_SpRocketLaunchA"); deliver("RE_SV_SpRocketBoostA")
from = #logs + 1
ticks(104.25, 523)
check(n("RE_SV_SpRocketLaunchA") == 0, "the Spaceport's launch held in a long STORE stay")
ticks(523.25, 540)
check(n("RE_SV_SpRocketLaunchA") == 1 and n("RE_SV_SpRocketBoostA") == 1
      and near(at("RE_SV_SpRocketBoostA"), at("RE_SV_SpRocketLaunchA") + CFG.specials.spaceport.retake.rockets.boost_s)
      and found("storeq: RE_SV_SpRocketLaunchA fired here 420 s after it came, this game's STORE still open (as before)", from) ~= nil,
      "... 420 s on, still in it: fired whatever, as before (logged); its boost boost_s after its launch, as on the host")
-- its own end of a rocket (SPORT.rkFromHost: STOREQ.here): fired now and again once its STORE is shut
fresh("join")
ticks(100, 103)
grounded = true; store(true)
ticks(103.25, 104)
STOREQ.here("RE_SV_SpRocketEndA")
check(n("RE_SV_SpRocketEndA") == 1, "its own rocket end in its STORE: fired now")
store(false); grounded = false
ticks(104.25, 112)
check(n("RE_SV_SpRocketEndA") == 2, "... and again once it's shut")
-- its own field off (each player's own, through SV_Event): fired again; dropped when its field came on again after it
fresh("join")
ticks(100, 103)
grounded = true; store(true)
ticks(103.25, 104)
fire("RE_SV_AnomalyFieldOff")
store(false); grounded = false
ticks(104.25, 112)
check(n("RE_SV_AnomalyFieldOff") == 2, "its own RE_SV_AnomalyFieldOff in its STORE: fired again once it's shut")
fresh("join")
ticks(100, 103)
grounded = true; store(true)
ticks(103.25, 104)
fire("RE_SV_AnomalyFieldOff"); fire("RE_SV_AnomalyFieldOn")
store(false); grounded = false
ticks(104.25, 112)
check(n("RE_SV_AnomalyFieldOff") == 1, "... not when its field came on again after it")
-- the host's pressure presets held: the last one only
fresh("join")
ticks(100, 103)
grounded = true; store(true)
ticks(103.25, 104)
deliver("RE_SV_PressureA"); deliver("RE_SV_PressureB")
store(false); grounded = false
ticks(104.25, 112)
check(order("^RE_SV_Pressure") == "RE_SV_PressureB", "the host's presets held in its STORE: only the last fired once it's shut")
-- a hostile host's flood while its STORE is open: the queue bounded, odd names harmless
fresh("join")
ticks(100, 103)
grounded = true; store(true)
ticks(103.25, 104)
for k = 1, 500 do deliver(string.format("RE_SV_FlightOff_%02d", k % 100)) end
deliver("RE_SV_ShuttleT_99999999999999999999"); deliver("RE_SV_LcacTroopsRemoveZZ"); deliver("RE_SV_WolfFree_99Z")
check(select(1, STOREQ.pending()) <= 96, "a flood of 500 held events: the queue kept at 96 at most (" .. tostring(STOREQ.pending()) .. ")")
store(false); grounded = false
local okF = pcall(ticks, 104.25, 200)
check(okF and select(1, STOREQ.pending()) == 0, "... and fired or dropped once it's shut, no error")
-- a joiner never fires the host's queue (its own SV_Event of a host rule: not queued)
fresh("join")
ticks(100, 103)
grounded = true; store(true)
ticks(103.25, 104)
fire("RE_SV_AnomalyEnd")
store(false); grounded = false
ticks(104.25, 112)
check(n("RE_SV_AnomalyEnd") == 1, "a joiner's own SV_Event of a host one-shot: not queued (the host's to fire again)")

---------------------------------------------------------------------------------------------------- the review's fixes
print("the review's fixes (2026-11-11): order, units, counters, holds, the throttle, the logs")
local function lastIdx(name) local k = nil; for i, e in ipairs(events) do if e == name then k = i end end; return k end
local function count(part, from, to)
    local c = 0
    for i = from or 1, to or #logs do if logs[i]:find(part, 1, true) then c = c + 1 end end
    return c
end
-- (1) a joiner back from a 2-minute STORE with 12 of the host's frees and a removal that never takes here held: the frees
-- fired back to back once it's open, the removal read back on its own clock holding back only its unit's; the host's
-- liftoff seconds that come with the gate open fired at once
do
    fresh("join")
    ticks(100, 103)
    alive.SV_Unit_Alicorn = 1
    grounded = true; store(true)
    ticks(103.25, 104)
    for k = 1, 12 do
        D.now = 104 + k * 10
        alive[poolUnit(k)] = 2
        deliver(string.format("RE_SV_DirFree_%02d", k))
    end
    deliver("RE_SV_AlcnRemove"); deliver("RE_SV_AlcnAlertOff")
    records = function(name) if name ~= "RE_SV_AlcnRemove" then rawRec(name) end end   -- (its copy never goes here)
    ticks(224.25, 227)
    store(false); grounded = false
    ticks(227.25, 230)                                             -- (open at 230)
    local frees = 0
    for i, e in ipairs(events) do if e:find("^RE_SV_DirFree_") and near(evAt[i], 230) then frees = frees + 1 end end
    check(frees == 12, "a backlog of 12 held frees: all fired back to back as its gate opens (" .. frees .. " at 230)")
    D.now = 231; deliver("RE_SV_ShuttleT_" .. (T - 4))
    check(near(at("RE_SV_ShuttleT_" .. (T - 4)), 231), "... the host's T-4, come with the gate open: fired at once (" .. tostring(at("RE_SV_ShuttleT_" .. (T - 4))) .. ")")
    ticks(231.25, 235)
    D.now = 235; deliver("RE_SV_ShuttleT_" .. T)
    check(near(at("RE_SV_ShuttleT_" .. T), 235), "... T at once too, the removal still read back (" .. tostring(at("RE_SV_ShuttleT_" .. T)) .. ")")
    ticks(235.25, 250)
    records = rawRec
    check(n("RE_SV_AlcnRemove") == 3 and n("RE_SV_AlcnAlertOff") == 1 and lastIdx("RE_SV_AlcnAlertOff") > lastIdx("RE_SV_AlcnRemove")
          and at("RE_SV_AlcnAlertOff") >= 239, "... the Alicorn's warning off, behind its removal (its unit), fired once that's given up ("
          .. tostring(at("RE_SV_AlcnAlertOff")) .. ")")
end
-- (2) a held Spaceport removal knows its units on a joiner (from its name): dropped when its craft spawned again since
do
    local SPU, SPT = "SV_Unit_SpLcacAV", "SV_Unit_SpTroopsAVL"
    fresh("join")
    ticks(100, 103)
    alive[SPU], alive[SPT] = 2, 1
    grounded = true; store(true)
    ticks(103.25, 104)
    deliver("RE_SV_SpLcacRemoveAV"); deliver("RE_SV_SpTroopsRemoveAVL")
    ticks(104.25, 130)
    ALIVE.spawned(SPU, 2); ALIVE.spawned(SPT, 1)                  -- (the host's next wave of that lane: its copies here)
    store(false); grounded = false
    from = #logs + 1
    ticks(130.25, 140)
    check(n("RE_SV_SpLcacRemoveAV") == 0 and n("RE_SV_SpTroopsRemoveAVL") == 0 and alive[SPU] == 2
          and found("storeq: RE_SV_SpLcacRemoveAV not fired here: " .. SPU .. " spawned again since", from) ~= nil,
          "a joiner's held RE_SV_SpLcacRemoveAV / SpTroopsRemoveAVL, the lane's next wave spawned here before its STORE shut: dropped, the new copies kept")
    fresh("join")
    ticks(100, 103)
    alive[SPU] = 2
    grounded = true; store(true)
    ticks(103.25, 104)
    deliver("RE_SV_SpLcacRemoveAV")
    store(false); grounded = false
    from = #logs + 1
    ticks(104.25, 115)
    check(n("RE_SV_SpLcacRemoveAV") == 1 and alive[SPU] == 0 and found("storeq: RE_SV_SpLcacRemoveAV took here (none alive)", from) ~= nil,
          "... with no new wave: fired here once it's shut, read back (its craft gone)")
    -- its own rocket end with its units: not fired again once a new retake's rockets spawned
    fresh("join")
    ticks(100, 103)
    grounded = true; store(true)
    ticks(103.25, 104)
    STOREQ.here("RE_SV_SpRocketEndB", { "SV_Unit_SpRockets" })
    ticks(104.25, 110)
    ALIVE.spawned("SV_Unit_SpRockets", 2)
    store(false); grounded = false
    ticks(110.25, 120)
    check(n("RE_SV_SpRocketEndB") == 1, "its own rocket end in its STORE, a new retake's rockets spawned since: not fired again")
end
-- (3) two loops of one heavy flight lost in one STORE: each its own counter, both fired again
do
    bomberScene("host", true)
    CFG.airfield.bombers.heavy_route = true
    ticks(100, 101)
    bspawn(HU, { bearing = 0 })
    ticks(101.25, 110)                                             -- (its orders and its route took: the gate open)
    local LA, LB = string.format("RE_SV_HeavyLoop_%02dAA", hi), string.format("RE_SV_HeavyLoop_%02dBA", hi)
    grounded = true; store(true)
    ticks(110.25, 112)
    fire(LA)                                                        -- (its lead down: A's loop, lost)
    ticks(112.25, 120)
    fire(LB)                                                        -- (A down too: B takes the loop, lost)
    store(false); grounded = false
    from = #logs + 1
    ticks(120.25, 140)
    check(n(LA) == 2 and n(LB) == 2 and FLAGS[string.format("SV_BRoute_%02dA", hi)] == 1 and FLAGS[string.format("SV_BRoute_%02dB", hi)] == 1
          and found("it took after all", from) == nil
          and found(string.format("storeq: %s took here (SV_BRoute_%02dA 1, was 0)", LA, hi), from) ~= nil
          and found("storeq: done here: HeavyLoop (took 2)", from) ~= nil,
          "two loops of one heavy flight lost in one STORE: both fired again, each read back by its own counter (SV_BRoute_NNA / NNB)")
end
-- (4) a raid escort that appeared in her STORE: its escort duty given again after its flight's own orders, as on time
do
    fresh("host")
    local E6 = poolUnit(6)
    alive[E6] = 2
    FLAGS.SV_Up_06 = 0
    ticks(100, 100.5)
    grounded = true; store(true)
    ticks(100.75, 101)
    D.orders[E6] = { at = 104, tries = 0 }                        -- (spawned at 101: ordersTick checks it at 104)
    queueEvent(106, "RE_SV_Escort_06", E6 .. " escorts the raid")
    ticks(101.25, 130)
    check(FLAGS.SV_Up_06 == 0 and n("RE_SV_Escort_06") == 1 and n("RE_SV_FlightOrders_06") >= 1,
          "a raid escort up in her STORE (player 2 flying): its orders (every 5 s) and its escort duty lost")
    store(false)
    from = #logs + 1
    ticks(130.25, 135)                                             -- (her plane still on the runway: the gate open at 133)
    grounded = false
    ticks(135.25, 160)
    local lastE, lastO = 0, 0
    for i, e in ipairs(events) do
        if e == "RE_SV_Escort_06" then lastE = evAt[i] elseif e == "RE_SV_FlightOrders_06" then lastO = evAt[i] end
    end
    check(n("RE_SV_Escort_06") == 2 and FLAGS.SV_Up_06 == 1 and lastE > lastO + 2
          and found("storeq: RE_SV_Escort_06 waits here for " .. E6 .. "'s own orders first", from) ~= nil,
          string.format("... once it's shut: its orders (%.2f), then its escort duty (%.2f), as on time", lastO, lastE))
end
-- (5) the frees undone by any newer hold of their flight (a Wolf trap's, the director's, your decoy); the host's queue
-- back to back; a boss's end fired late followed by the newer preset (both set the attack throttle)
do
    fresh("host")
    for k = 3, 6 do alive[poolUnit(k)] = 2 end
    ticks(100, 100.5)
    grounded = true; store(true)
    ticks(100.75, 101)
    fire("RE_SV_DirFree_04"); fire("RE_SV_WolfHold_04A")
    fire("RE_SV_WolfFree_03A"); fire("RE_SV_DirHold_03")
    fire("RE_SV_WolfFree_05B"); fire("RE_SV_Decoy_05")
    fire("RE_SV_DecoyEnd_06"); fire("RE_SV_WolfHold_06A")
    check(select(1, STOREQ.pending()) == 0, "the host's frees each undone by a newer hold of their flight (" .. tostring(STOREQ.pending()) .. " left)")
    store(false); grounded = false
    ticks(101.25, 110)
    check(n("RE_SV_DirFree_04") == 1 and n("RE_SV_WolfFree_03A") == 1 and n("RE_SV_WolfFree_05B") == 1 and n("RE_SV_DecoyEnd_06") == 1,
          "... DirFree_04 (WolfHold_04A after it), WolfFree_03A (DirHold_03), WolfFree_05B (Decoy_05), DecoyEnd_06 (WolfHold_06A): none fired again")
    -- back to back: the several-in-order section's fires all at the gate's first open tick
    fresh("host")
    alive.SV_Unit_Alicorn, FLAGS.SV_AnomalyUp, alive[poolUnit(5)] = 1, 1, 2
    ticks(100, 100.5)
    grounded = true; store(true)
    ticks(100.75, 101)
    D.now = 101; fire("RE_SV_WolfFree_03A")
    D.now = 102; fire("RE_SV_AlcnRemove")
    D.now = 103; fire("RE_SV_FlightOff_05")
    D.now = 104; fire("RE_SV_AnomalyEnd")
    ticks(104.25, 104.5)
    store(false); grounded = false
    ticks(104.75, 115)
    local ts = {}
    for i, e in ipairs(events) do if evAt[i] > 104.6 then ts[#ts + 1] = string.format("%.2f", evAt[i]) end end
    check(#ts == 4 and table.concat(ts, ",") == "107.50,107.50,107.50,107.50",
          "the host's queue fired back to back once open, not with their old gaps (" .. table.concat(ts, ",") .. ")")
    -- the throttle: VALKA's end lost, its first fire here doesn't take, the band's preset fired (and took) in between
    fresh("host")
    FLAGS.SV_ValkaUp = 1
    ticks(100, 100.5)
    grounded = true; store(true)
    ticks(100.75, 101)
    fire("RE_SV_ValkaEnd")
    store(false); grounded = false
    local skip = 1
    records = function(name) if name == "RE_SV_ValkaEnd" and skip > 0 then skip = skip - 1; return end; rawRec(name) end
    ticks(101.25, 104)                                             -- (open at 104: its fire there doesn't take)
    D.now = 105; fire("RE_SV_PressureC")                           -- (the band's preset, the gate open: it takes)
    from = #logs + 1
    ticks(105.25, 115)
    records = rawRec
    check(n("RE_SV_ValkaEnd") == 3 and n("RE_SV_PressureC") == 2 and lastIdx("RE_SV_PressureC") > lastIdx("RE_SV_ValkaEnd")
          and FLAGS.SV_ValkaUp == 0
          and found("storeq: RE_SV_PressureC fired again here after RE_SV_ValkaEnd: it came after it, and both set the attack throttle (fired)", from) ~= nil,
          "VALKA's end fired again over a newer preset: the preset fired again after it (the band's throttle kept)")
    -- a joiner's: the host's preset, come while the end is still read back here, goes behind it
    fresh("join")
    FLAGS.SV_AnomalyUp = 1
    ticks(100, 103)
    grounded = true; store(true)
    ticks(103.25, 104)
    deliver("RE_SV_AnomalyEnd")
    store(false); grounded = false
    skip = 1
    records = function(name) if name == "RE_SV_AnomalyEnd" and skip > 0 then skip = skip - 1; return end; rawRec(name) end
    ticks(104.25, 107)                                             -- (open at 107: fired, doesn't take)
    D.now = 108; deliver("RE_SV_PressureC")
    check(n("RE_SV_PressureC") == 0, "a joiner: the host's preset, come while MINDRIPPER's end is read back here: held behind it")
    ticks(108.25, 120)
    records = rawRec
    check(n("RE_SV_PressureC") == 1 and n("RE_SV_AnomalyEnd") == 2 and lastIdx("RE_SV_PressureC") > lastIdx("RE_SV_AnomalyEnd") and FLAGS.SV_AnomalyUp == 0,
          "... fired once the end took here, after it")
end
-- (6) the logs: no summary while its STORE stays open through the countdown (a second a second), the pass's line as it
-- opens; a held one fired late with the gate open is no 'late' (the gate's shut only)
do
    fresh("join")
    ticks(100, 103)
    grounded = true; store(true)
    ticks(103.25, 104)
    from = #logs + 1
    for k = 0, 60 do
        D.now = 104 + k
        deliver("RE_SV_ShuttleT_" .. (T - 30 + k))
        ticks(104 + k + 0.25, 104 + k + 0.75)
    end
    local shutTo = #logs
    check(count("storeq: done here", from, shutTo) == 0, "a joiner's STORE open through the countdown: no 'done here' line while it's shut ("
          .. count("storeq: done here", from, shutTo) .. ")")
    store(false); grounded = false
    ticks(165.25, 230)
    check(found("storeq: this game's events can take again: 7 to fire here in order (ShuttleT 7)", shutTo) ~= nil
          and count("storeq: done here", shutTo) == 1 and found("storeq: done here: ShuttleT (fired 7, dropped 54)", shutTo) ~= nil,
          "... once it's shut: the pass's line, one summary with the seconds dropped")
    fresh("join")
    ticks(100, 103)
    alive.SV_Unit_Alicorn = 1
    grounded = true; store(true)
    ticks(103.25, 104)
    deliver("RE_SV_AlcnRemove"); deliver("RE_SV_AlcnAlertOff")
    records = function(name) if name ~= "RE_SV_AlcnRemove" then rawRec(name) end end
    ticks(104.25, 518)
    store(false); grounded = false
    from = #logs + 1
    ticks(518.25, 540)
    records = rawRec
    check(n("RE_SV_AlcnAlertOff") == 1 and at("RE_SV_AlcnAlertOff") >= 530 and found("STORE still open", from) == nil
          and found("storeq: RE_SV_AlcnAlertOff fired here (held 426 s)", from) ~= nil,
          "a held one past 420 s behind a removal read back, the gate open: logged as held, not 'STORE still open'")
end
-- (7) a bomber flight's watch through a 60 s STORE stay: ALIVE's kept answers (about one native ask a second), not one a tick
do
    bomberScene("host", true)
    ticks(100, 100.5)
    grounded = true; store(true)
    ticks(100.75, 101)
    bspawn(BU)
    asks[BU] = 0
    ticks(101.25, 161)
    local nAsk = asks[BU] or 0
    store(false); grounded = false
    ticks(161.25, 170)
    check(nAsk <= 75 and n("RE_SV_BomberOrders_01") == 1,
          "a bomber flight watched through a 60 s STORE stay: " .. nAsk .. " native asks (ALIVE's kept answers; one a tick was 240), its orders given once it's shut")
end
-- (8) an error in STOREQ never stops the host's roundsTick (its orders, its events)
do
    fresh("host")
    ticks(100, 101)
    local rawTick, rawGate = STOREQ.tick, STOREQ.gate
    STOREQ.tick = function() error("storeq test") end
    queueEvent(101.5, "RE_SV_TestEventA", "the test")
    from = #logs + 1
    local okT = pcall(ticks, 101.25, 103)
    STOREQ.tick = rawTick
    check(okT and n("RE_SV_TestEventA") == 1 and found("storeq: error", from) ~= nil, "STOREQ.tick failing: roundsTick goes on (its events fired), the error logged")
    STOREQ.gate = function() error("gate test") end
    queueEvent(103.5, "RE_SV_TestEventB", "the test")
    from = #logs + 1
    okT = pcall(ticks, 103.25, 105)
    STOREQ.gate = rawGate
    check(okT and n("RE_SV_TestEventB") == 1 and found("storeq: gate error", from) ~= nil, "... and the gate failing inside it: taken as open, logged")
end

---------------------------------------------------------------------------------------------------- the hooks
print("the hooks in place")
do
    local rounds, joiner, coop, spawn = PARTS.read("sv_rounds.lua"), PARTS.read("sv_coop_joiner.lua"), PARTS.read("sv_coop.lua"), PARTS.read("sv_spawn.lua")
    check(has(rounds, "local okQ, errQ = pcall(STOREQ.tick, now)") and has(rounds, "log(\"storeq: error \" .. D.storeQErr) end\n    end\n    D.orders = D.orders or {}\n    ordersTick(now)"),
          "roundsTick: STOREQ.tick (in a pcall) before its own orders and events")
    check(has(joiner, "if not levelReady() then return end\n    -- ((2026-11-11) hard rule 64") and has(joiner, "pcall(STOREQ.tick, now)"),
          "clientRounds: STOREQ.tick once its level is ready")
    check(has(joiner, "pcall(STOREQ.forwarded, name)") and has(joiner, "pcall(STOREQ.undo, tostring(name))"), "hostEvent: STOREQ.undo, then STOREQ.forwarded")
    check(has(coop, "pcall(STOREQ.before, name)") and has(coop, "pcall(STOREQ.fired, name, r, okB and c0 or nil)"), "the SV_Event wrapper: STOREQ.before / fired")
    check(has(spawn, "STOREQ.sawSpawn(unit, r)") and has(spawn, "pcall(STOREQ.bomberPre, unit)") and has(spawn, "pcall(STOREQ.bomberUp, unit, r, ordersBefore, D.now)"),
          "ALIVE.spawned and spawnBomber")
    local se = readAll(MOD .. "/../../../tools/survival_events.py")
    check(has(se, "orders, count = f'RE_SV_BomberOrders_{k + 1:02d}', f'SV_BOrd_{k + 1:02d}'")
          and has(se, "flag(H['ev'], f'SV_BRoute_{H[\"n\"]:02d}R', 'Add', 1)")
          and has(se, "flag(ev, f'SV_BRoute_{H[\"n\"]:02d}{chr(65 + j)}', 'Add', 1)")
          and has(se, "INT_FLAGS += [f'SV_BOrd_{k + 1:02d}' for k in range(len(BOMBERS))]")
          and has(se, "INT_FLAGS += [f'SV_BRoute_{BOMBERS.index(u) + 1:02d}{x}' for u in HEAVY_TRACKS"),
          "the build: RE_SV_BomberOrders_NN, SV_BOrd_NN and a route's / each loop's SV_BRoute_NN<R|L> (survival_events.py)")
    local spp = PARTS.read("sv_spaceport.lua")
    check(has(spp, "note(\"RE_SV_SpFleetRemove\", fleet)") and has(spp, "note(\"RE_SV_SpRocketRemove\", RK_UNITS)")
          and has(spp, "here = function(ev) return STOREQ.here(ev, RK_UNITS) end"),
          "sv_spaceport.lua: its removals' units noted at its load (every game), its own rocket end with its units")
end

print(fails == 0 and "store events test: all passed" or ("store events test: " .. fails .. " FAILED"))
logFile:close()
os.exit(fails == 0 and 0 or 1)
