-- stats_test.lua <mod dir> <work dir> (run by tools/checks/stats_test.sh): the behaviour roadmap's foundations (unit 1,
-- tools/re/BEHAVIOUR_DIRECTOR.md) on the real sv_core.lua, sv_config.lua, sv_ai.lua, sv_spawn.lua, sv_stats.lua and
-- sv_coop.lua (M exposed), the game stubbed:
--   the spawn index: spawnFlight's planes get p.k 0.. in creation order, the "spawn index:" check names the lead at k 0
--     (and says so when a spawner made the lead last);
--   the measurements: engaged / first hit / tail / Provoke times per plane, KILL.geom's aspect and last weapon, the
--     kill-time line, a round's line (logged after its last kills come in), hits by source and brackets, the death line,
--     the run line's rounds 7-12 and Veteran+ figures, STATS.tactic's count and p.dirTag = { tactic, at };
--   the hooks on the other parts' real code: sv_main.lua's plane sweep and kill credit, sv_ladon.lua's HIT.tick,
--     sv_flights.lua's ammoTick, sv_leaderboard.lua's LB.deathCheck / LB.finish (the damage record at death too);
--   COOP.players() / COOP.slotOfAddr() solo and as a host, the ACE.movesTick guard on a joiner, a joiner's rounds, its
--     kills (not sorted into ordinary), the host's restart and a resync ("rs");
--   the code review of 2026-10-29: a special's guard kept out of the run line's Veteran+ figures, p.youAt kept by the
--     sweep with [stats] off (a kill's aspect for P6), a hook's first error logged once (hookErr), a joiner's round and
--     run lines saying the tail watch isn't measured there, ACE.hunt (the hunt tell) reading this visit's p.dist;
--   quieter logs (the clean up of 2026-10-29): the "ai:" lines only with [log] verbose, flagLine's key without the
--     counters, probeTick's flags / alive / nearest, the perf and ammo intervals and the intensity scores by their place
--     in the source; STATS.tactic's "told" (a tell said with a tactic: a radio line, no callout).
-- Its log lines also go to <work dir>/test_lua.log, for stats_test.sh to run tools/checks/stats_report.py on.
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

-- the game's world, stubbed
VERSION = "0.71.5-stats.test"
local notify = {}
function NotifyOnNewObject(cls, fn) notify[cls] = notify[cls] or {}; table.insert(notify[cls], fn) end
function FName(s) return s end
function FindAllOf() return {} end
function FindFirstOf() return nil end
function StaticFindObject() return nil end
local airfield = false
function playerOnAirfield() return airfield end
function hudCallout() end
function queueEvent() end
function searchAircraft(a) return a end
function roundsTick() end
function airfieldTick() end
function bombTick() end
local events = {}
function SV_Event(name) events[#events + 1] = name; return 1 end
local rows, reverse = {}, false
function SV_SetAircraft(unit, row, idx)
    rows[unit] = rows[unit] or { idx = {} }
    if idx == nil then rows[unit].all, rows[unit].idx = row, {} else rows[unit].idx[idx] = row end
    return 1
end
function SV_SetLevel() return 1 end
function SV_UnitAlive() return 0 end
local nextAddr = 0x1000
local function plane(code)
    nextAddr = nextAddr + 0x10
    local o = { addr = nextAddr, state = 10, HealthInternal = 1000, loc = { X = 0, Y = 0, Z = 300000 }, fwd = { X = 1, Y = 0, Z = 0 },
                full = "BP_OP1022_" .. code .. "_CP_C /Game/Mods/SurvivalMode/Maps/PL_SurvivalMode.PL_SurvivalMode:PersistentLevel.BP_OP1022_" ..
                       code .. "_CP_C_" .. nextAddr }
    function o:K2_GetActorLocation() return self.loc end
    function o:GetActorForwardVector() return self.fwd end
    o.AIStateComponent = { BlackboardComponent = { GetValueAsEnum = function() return o.state end, GetValueAsObject = function() return nil end } }
    return o
end
-- the spawner: a pool flight's planes, each on its desc's row (SV_SetAircraft), told to NotifyOnNewObject one by one;
-- `reverse`: desc 0 made last (what the spawn index's check must catch)
function SV_Spawn(unit)
    if not tostring(unit):match("^ERA_Unit_") then return 0 end
    local r, n = rows[unit] or { idx = {} }, flightSize(unit)
    for j = 0, n - 1 do
        local i = reverse and (n - 1 - j) or j
        local row = r.idx[i] or r.all or "f16c_common"
        local o = plane(row:match("^(%w+)_") or row)
        o.desc = i
        for _, fn in ipairs(notify["/Script/Live.LiveAIPlane"] or {}) do fn(o) end
    end
    return n
end
-- co-op's natives (for COOP.players as a host, and a joiner)
local menu, peerAt = 0, {}
function SV_MenuChoice() return menu end
function SV_CoopOpen() return 1 end
function SV_CoopClose() end
function SV_CoopSend() return 1 end
function SV_CoopRecv() return "" end
function SV_CoopInfo() return "open=1;state=linked;peers=2/linked/40/10/p" end
function SV_CoopMe() end
function SV_CoopReset() end
function SV_CoopTrack() return 1 end
function SV_CoopBind() return 1 end
function SV_CoopPeer() return 1 end
function SV_CoopPeerAt(s) return peerAt[s] or "" end

-- the real parts (sv_core's SCRIPT_DIR and log file in the work folder)
local function run(name, chunk)
    local src = readAll(MOD .. "/Scripts/" .. name)
    if name == "sv_coop.lua" then src = src:gsub("\nlocal M = {", "\nM = {", 1) end
    assert(load(src, chunk or ("=" .. name)))()
end
run("sv_core.lua", "@" .. WORK .. "/Scripts/sv_core.lua")
local logs = {}                               -- (sv_core's own log, valid, nameOf and addrOf replaced by the test's)
local logFile = assert(io.open(WORK .. "/test_lua.log", "wb"))
function log(s) logs[#logs + 1] = s; logFile:write(os.date("%H:%M:%S ") .. s .. "\n") end
function valid(o) return type(o) == "table" and not o.gone end
function nameOf(o) return type(o) == "table" and o.full or "?" end
function addrOf(o) return type(o) == "table" and o.addr or nil end
run("sv_config.lua"); run("sv_ai.lua"); run("sv_spawn.lua"); run("sv_stats.lua"); run("sv_coop.lua")
local M = _G.M
local function line(prefix, from)
    for i = #logs, from or 1, -1 do if logs[i]:sub(1, #prefix) == prefix then return logs[i] end end
    return nil
end
local function has(s, part) return s ~= nil and s:find(part, 1, true) ~= nil end

-- the player
local you = { X = 0, Y = 0, Z = 300000 }
local pawn = { addr = 0x9, full = "BP_PlayerPlane_PP1000_f16c_C /Game/Mods/SurvivalMode/Maps/PL_SurvivalMode.PL_SurvivalMode:PersistentLevel.BP_PlayerPlane_PP1000_f16c_C_1",
               MaxHealth = 100, HealthInternal = 800 }
function pawn:K2_GetActorLocation() return you end
survivalPC = { Pawn = pawn }
HIT = { msl = {}, h = 800 }
A = { caps = { [1] = 31, [2] = 10, [3] = 12, [4] = 3 } }
CFG.stats.enabled, CFG.ai_watch, CFG.probe.kills = true, false, true

---------------------------------------------------------------------------------------------------- the spawn index
print("spawn index")
D = { round = 8, startRound = 1, state = "spawning", now = 100, up = {}, flown = {}, queue = {}, spare = {} }
local function settle()                       -- sv_main's pending queue: each plane logged (logPlane, as wrapped by sv_coop)
    for _, p in ipairs(pending) do logPlane(p.obj, p.unit, p.k) end
    pending = {}
end
local JAM_UNIT, REV_UNIT = "ERA_Unit_03_Dep_Air1", "ERA_Unit_04_Dep_Air0"
D.jammerUnit = JAM_UNIT
SR.usable[CFG.jammer.aircraft] = true
check(spawnFlight(JAM_UNIT) == 4, "a 4-ship spawned (the jammer's flight)")
check(spawningUnit == nil and spawningIdx == nil, "spawningUnit / spawningIdx cleared after the spawn")
settle()
local fl = {}
for _, p in ipairs(planes) do if p.unit == JAM_UNIT then fl[#fl + 1] = p end end
check(#fl == 4 and fl[1].k == 0 and fl[2].k == 1 and fl[3].k == 2 and fl[4].k == 3, "p.k 0..3 in creation order")
check(fl[1].obj.desc == 0 and fl[1].name:find("_e18g_", 1, true), "k 0 is desc 0, the jammer's EA-18G")
check(fl[1].born == 100, "p.born from the round clock")
check(has(line("round probe: AI aircraft created"), ", k 3)"), "the created line names k")
check(has(line("spawn index:"), "k 0 is the lead: creation order = desc order"), "spawn index check: k 0 is the lead")
D.jammerUnit, reverse = REV_UNIT, true
spawnFlight(REV_UNIT)
settle()
reverse = false
check(has(line("spawn index: " .. REV_UNIT), "k 0 is NOT the lead"), "spawn index check: a lead made last is caught")
D.jammerUnit = nil
-- the aces (tools/build_survival.py ACES): Harvest's Named lead over Shadow wings tells by its whole blueprint; Bounty's
-- Shark lead and wings share one, so it can't tell
local function bpPlane(bp)
    local o = plane("x")
    o.full = bp .. "_C /Game/Mods/SurvivalMode/Maps/PL_SurvivalMode.PL_SurvivalMode:PersistentLevel." .. bp .. "_C_" .. o.addr
    return o
end
local nPlanes = #planes
local function aceCheck(unit, code, b0, b1)
    D.leadRow[unit] = { row = "sv_ace_test_l", code = code }
    logPlane(bpPlane(b0), unit, 0); logPlane(bpPlane(b1), unit, 1)
    return line("spawn index: " .. unit)
end
check(has(aceCheck("ERA_Unit_10_Dep_Air0", "su57", "BP_OP1021_su57_CP_Named", "BP_OP1021_su57_CP_Shadow"),
      "k 0 is a BP_OP1021_su57_CP_Named, k 1 a BP_OP1021_su57_CP_Shadow; k 0 is the lead"), "spawn index check: Harvest's Named lead at k 0")
check(has(aceCheck("ERA_Unit_10_Dep_Air1", "su57", "BP_OP1021_su57_CP_Shadow", "BP_OP1021_su57_CP_Named"), "k 0 is NOT the lead"),
      "spawn index check: Harvest's Named lead made last")
check(has(aceCheck("ERA_Unit_10_Dep_Air2", "rafale", "BP_OP1014_rflm_CP_Named", "BP_OP1011_typn_CP_Shadow"), "k 0 is the lead"),
      "spawn index check: the Rafale over Typhoons")
check(has(aceCheck("ERA_Unit_11_Dep_Air0", "f15c", "BP_OP1004_f15c_CP_Shark", "BP_OP1004_f15c_CP_Shark"),
      "can't tell: lead and wings fly one blueprint"), "spawn index check: one blueprint for lead and wings can't tell")
while #planes > nPlanes do table.remove(planes) end
local rev = {}
for _, p in ipairs(planes) do if p.unit == REV_UNIT then rev[#rev + 1] = p end end
spawningUnit = "SV_Unit_LadonA"                -- (any other spawn: no index)
for _, fn in ipairs(notify["/Script/Live.LiveAIPlane"]) do fn(plane("ldn")) end
spawningUnit = nil
check(pending[1] and pending[1].k == nil, "a spawn without spawningIdx gives no k")
pending = {}

---------------------------------------------------------------------------------------------------- the measurements
print("measurements")
local veteran = CFG.tiers.list[3]
for _, p in ipairs(fl) do p.tier = veteran end
for _, p in ipairs(rev) do p.tier = veteran end
local J, P1, P2, P3 = fl[1], fl[2], fl[3], fl[4]
J.jammer = true
local L = rev[1]
local function visit(p, now, at, fwd, state, dmg)       -- one sweep visit (sv_main.lua planeSweep)
    D.now = now
    p.obj.state, p.at, p.fwd, p.dmg = state or 10, at, fwd, dmg or p.dmg
    p.addr = p.addr or addrOf(p.obj)
    p.dist = km(p.at, you)
    aiWatch(p, you)
    STATS.track(p, you, now)
end
local function kill(p, now, by, ammo)
    D.now = now
    PR.ammo = ammo or {}
    p.down = true
    local g = KILL.geom(p, you)
    probeKill(p, you, g)
    STATS.down(p, g, by, now)
    return g
end
local AHEAD, BEHIND = { X = 1, Y = 0, Z = 0 }, { X = -1, Y = 0, Z = 0 }
local function x(km_) return { X = km_ * 100000, Y = 0, Z = 300000 } end
STATS.roundStart(100)
check(D.rs and D.rs.round == 8 and D.rs.tier == "Veteran", "round 8 starts (D.rs, its tier)")
STATS.sample(100, you)
airfield = true; STATS.sample(102, you); airfield = false
check(D.rs.ground == 2, "2 s down at the airfield counted (" .. tostring(D.rs.ground) .. ")")
-- P1: far, engaged at 104, hit at 106, on its tail from 108 (Provoke too), AttackAvoidance at 110, down at 112 by your gun
visit(P1, 102, x(10), AHEAD, 10)
visit(P1, 104, x(4.9), AHEAD, 10)
visit(P1, 106, x(3.5), AHEAD, 10, { you = 50 })
visit(P1, 108, x(1.5), AHEAD, 8)
visit(P1, 110, x(1.4), AHEAD, 5)
check(P1.engagedAt == 104 and P1.hitAt == 106 and P1.tailAt == 108 and P1.provokeAt == 108, "P1: engaged, first hit, tail and Provoke times")
check(P1.aiState == "AttackAvoidance" and not line("ai: "), "aiWatch keeps p.aiState with the ai: log off, logs nothing")
-- the "ai:" lines need [log] verbose too now (the clean up of 2026-10-29: quieter logs), CFG.ai_watch on or not
do
    local w = { obj = plane("aiw"), name = "BP_OP1022_aiw_CP_C_1", unit = "ERA_Unit_12_Dep_Air0", at = x(2) }
    CFG.ai_watch = true
    aiWatch(w, you)
    check(w.aiState == "PursueTarget" and not line("ai: "), "ai_watch on, [log] verbose off (the default): its state kept, no ai: line")
    CFG.log.verbose = true
    w.obj.state = 8
    aiWatch(w, you)
    check(w.aiState == "Provoke" and has(line("ai: BP_OP1022_aiw_CP_C_1"), "Provoke, target none"), "[log] verbose: the ai: line on a change")
    local n = #logs
    aiWatch(w, you)
    check(#logs == n, "... and only on a change")
    CFG.log.verbose, CFG.ai_watch = false, false
    check(CFG_DEFAULTS.log.verbose == false and logVerbose() == false, "[log] verbose ships false")
end
-- P2: tailed at 104 and Provoke, both gone at 106 (escapes), shot down by allies at 114
visit(P2, 102, x(3), AHEAD, 10)
visit(P2, 104, x(1), AHEAD, 8)
visit(P2, 106, x(1.2), { X = 0, Y = 1, Z = 0 }, 10)
check(D.rs.tailEscaped == 1 and D.rs.provokeEscaped == 1 and P2.tailAt == nil and P2.provokeAt == nil, "P2's tail and Provoke escapes counted")
-- a tactic on P3's flight while it flies, an ace reversal: counted apart
visit(P3, 102, x(4), BEHIND, 10)
STATS.tactic("cover", JAM_UNIT, 0, "test", "six")
check(type(P3.dirTag) == "table" and P3.dirTag.tactic == "cover" and P3.dirTag.at == 102, "STATS.tactic tags the unit's planes { tactic, at }")
check(has(line("director: round 8"), "cover on " .. JAM_UNIT) and has(line("director:"), 'told "six"'), "director: line")
STATS.tactic("reversal", "ERA_Unit_05_Dep_Air0", nil, "1500 m")
check(D.rs.nTactics == 1 and D.rs.moves.reversal == 1, "a reversal is counted apart from the director's tactics")
-- the kills (PR.ammo: what dropped last decides the weapon)
local g1 = kill(P1, 112, "you", { { [0] = 500, [1] = 30 }, { [0] = 480, [1] = 29 }, { [0] = 460, [1] = 29 } })
check(g1.wpn == "gun" and g1.used.gun == 40 and g1.used.msl == 1, "KILL.geom: the gun went last (40 rounds, 1 missile)")
check(g1.offNose and g1.offNose > 179 and math.abs(g1.km - 1.4) < 1e-6, "KILL.geom: you on its tail (180 deg) at 1.4 km, from p.youAt")
local kt = line("kill-time: ")
check(has(kt, "up 12 s, engaged 8 s (within 5 km), since your first hit 6 s, tailed 4 s (AI Provoke 4 s)"), "kill-time line: up, engaged, hit, tailed")
check(has(kt, ", k 1, ordinary)") and has(kt, "by you") and has(kt, "director cover 10 s before"), "kill-time line: k, ordinary, by, director tag")
check(has(line("kill: "), "180 deg off its nose"), "the kill: line from the same record")
kill(P2, 114, "allies")
visit(P3, 110, x(2), BEHIND, 10)
kill(P3, 116, "you", { { [0] = 500, [1] = 30 }, { [0] = 490, [1] = 30 }, { [0] = 490, [1] = 28 } })
visit(J, 104, x(3), BEHIND, 10)
kill(J, 118, "you", { { [2] = 10 }, { [2] = 9 } })
STATS.fired(1, 2); STATS.fired(0, 120); STATS.fired(2, 1)
-- the round clears at 120; a kill the sweep sees at 122 still counts in it
STATS.roundEnd(120)
STATS.sample(121, you)
check(not line("stats: round 8"), "the round's line waits for the sweep")
visit(L, 110, x(4), BEHIND, 10)
kill(L, 122, "you", { { [1] = 30 }, { [1] = 29 } })
STATS.sample(124, you)
local rl = line("stats: round 8")
check(rl ~= nil, "the round's line after its last kills")
check(has(rl, "length 20 s (2 s at the airfield)"), "round line: length and time at the airfield")
check(has(rl, "aircraft down 5 (yours 4), ordinary fighters 4 (yours 3)"), "round line: down, yours, ordinary fighters")
check(has(rl, "time to kill since engaged median 12 s (n 3)"), "round line: time to kill median (8, 14, 12 s)")
check(has(rl, "AI Provoke median 4 s (1 died, 1 escaped), geometric median 4 s (1 died, 1 escaped)"), "round line: tailed survival")
check(has(rl, "kills from behind 1/4 (25%)"), "round line: kills from behind")
check(has(rl, "your kills with missiles 2, gun 1, special 1, nothing seen 0"), "round line: weapons")
check(has(rl, "missiles left 31, fired 2 this round"), "round line: missiles left and fired")
check(has(rl, "director tactics 1 (cover x1; 1 told); ace reversals 1"), "round line: tactics and reversals")
-- round 9: hits by source, then shot down
D.round = 9
STATS.roundStart(130)
P3.down, P3.dist = false, 1.0
local hits = { { obj = { gone = true }, name = "BP_wp_msl", d = 300, seen = 132, from = "BP_OP1022_f16c_CP", fromAddr = P2.addr },
               { obj = { gone = true }, name = "BP_wp_msl", d = 1200, seen = 132, from = "BP_OP1022_f16c_CP", fromAddr = P1.addr } }
HIT.msl = hits
STATS.hit(132, 40, pawn)
local src, who, _, br = STATS.classify(132, pawn)
check(src == "missile" and who == JAM_UNIT and br == true, "a hit with a missile 300 m off: missile, its flight, a bracket")
HIT.msl = {}
STATS.hit(134, 10, pawn)
P3.down = true
STATS.hit(136, 50, pawn)
check(STATS.classify(136, pawn) == "unknown", "no missile and no enemy near: unknown")
-- a special's guard (its top tier given, not a skill band), tailed 17 s before it went down: not in the run line's
-- Veteran+ figures (code review of 2026-10-29)
local top = #CFG.tiers.list
STATS.down({ obj = plane("f16c"), name = "BP_OP1022_f16c_CP_C_guard", unit = "SV_Unit_AnomalyGuards", tier = CFG.tiers.list[top],
             tierI = top, provokeAt = 120, tailAt = 120 }, nil, "allies", 137)
D.now = 138
STATS.death("died")
local dl = line("death: ")
check(has(dl, "round 9 (died), 8 s into the round: last 30 s -100 HP: missiles 40% (1 hits from 1 shooters, 1 brackets), gun/close 10%, unknown 50%"),
      "death line: by source")
check(has(dl, "missiles left 31 (fired 2 this run, 0 this round), specials 10/12, flares 3"), "death line: what you had left")
STATS.runEnd("died")
check(has(line("stats: round 9"), "(cut short: died)"), "the round you died in gets its line")
local runL = line("stats: run over")
check(has(runL, "rounds 1-9"), "run line: the rounds")
check(has(runL, "time to kill rounds 7-12 median 12 s (n 3)"), "run line: time to kill, rounds 7-12")
check(has(runL, "tailed survival Veteran+ AI Provoke median 4 s (n 1), geometric median 4 s (n 1)"),
      "run line: tailed survival Veteran+ (the special's guard left out)")
check(has(runL, "missiles left at the end 31"), "run line: missiles left")
check(has(runL, "damage taken 100 HP: missiles 40%, gun/close 10%, unknown 50%, brackets 1"), "run line: damage by source")
check(has(runL, "director tactics per round avg 0.5 (1 in 2 rounds)"), "run line: tactics per round")
check(has(runL, "kills from behind 25% (1/4)") and has(runL, "fired: missiles 2, specials 1, flares 0, gun 120"), "run line: behind, fired")
check(STATS.median({ 3, 1, 2 }) == 2 and STATS.median({ 4, 1, 3, 2 }) == 2.5 and STATS.median({}) == nil, "median")
local n0 = #logs
STATS.runEnd("left")
check(#logs == n0, "one run line a run")

---------------------------------------------------------------------------------------------------- the hooks
-- The other parts' calls into STATS on their real code: sv_main.lua's plane sweep and kill credit (its creditKill ..
-- planeSweep, run as a chunk), sv_ladon.lua's HIT.tick, sv_flights.lua's ammoTick, sv_leaderboard.lua's LB.deathCheck /
-- LB.finish; the calls in startRound, the clear, SECOND CHANCE and probeTick by their place in the source.
print("hooks")
run("sv_ladon.lua"); run("sv_leaderboard.lua"); run("sv_flights.lua")    -- (sv_flights has a global M of its own:
_G.M = M                                                                    -- sv_coop's, exposed here, back)
local mainSrc = readAll(MOD .. "/Scripts/sv_main.lua")
local cA, cB = mainSrc:find("\nlocal function creditKill%(p%)"), mainSrc:find("\nlocal function probeTick%(tick%)")
check(cA and cB and cA < cB, "sv_main.lua: creditKill .. planeSweep found")
local creditKill, timed, planeSweep = assert(load(mainSrc:sub(cA, cB) .. "\nreturn creditKill, timed, planeSweep\n", "=sv_main.lua"))()
check(type(creditKill) == "function" and type(timed) == "function" and type(planeSweep) == "function", "sv_main.lua's chunk loads")
RUN = { kills = {}, credits = 0, earned = 0 }
D = { round = 9, startRound = 2, state = "fighting", now = 500, up = {}, flown = {}, perf = { parts = {} }, leadRow = {} }
STATS.roundStart(500)
local function sweepPlane(code, unit, k)
    local p = { obj = plane(code), unit = unit, k = k, tier = veteran, born = D.now }
    p.name = p.obj.full:match("([^%.:]+)$")
    return p
end
local SWEEP_UNIT = "ERA_Unit_06_Dep_Air0"
local Q = sweepPlane("f16c", SWEEP_UNIT, 0)
Q.obj.loc = x(4)
Q.obj.AIStateComponent.BlackboardComponent.GetValueAsObject = function() return pawn end
planes = { Q }                                             -- (planes[1]: the sweep's slot 1)
local okP = timed("planes", planeSweep, 1)
check(okP and Q.at and Q.at.X == 400000 and Q.youAt and Q.engagedAt == 500 and Q.dist == 4, "planeSweep: a live plane's position, STATS.track (engaged)")
check(Q.aiState == "PursueTarget" and Q.aiTarget == pawn and Q.aiTargetAddr == pawn.addr and COOP.slotOfAddr(Q.aiTargetAddr) == 0,
      "aiWatch keeps p.aiState and p.aiTarget / p.aiTargetAddr (you: slot 0)")
check(D.perf.parts.planes and D.perf.parts.planes.n == 1, "timed('planes') adds to the perf line")
Q.obj.HealthInternal = 0
D.now = 506
planeSweep(1)
local kq = line("kill-time: " .. Q.name)
check(Q.down and line("round probe: " .. Q.name .. " down") and has(kq, ", k 0, ordinary)") and has(kq, "by you"),
      "planeSweep's death branch: KILL.geom, creditKill's side, STATS.down's kill-time line")
check(D.rs.down == 1 and D.rs.fightersMine == 1 and RUN.kills.you == 1, "the kill counted (round, credits)")
-- an ace squadron's plane the sweep never saw alive, and the jammer's EA-18G down before JAM.tick found it: not ordinary
local QA, QJ = sweepPlane("su57", "ERA_Unit_07_Dep_Air0", 1), sweepPlane("e18g", "ERA_Unit_07_Dep_Air1", 0)
QA.obj.HealthInternal, QJ.obj.HealthInternal = 0, 0
D.aceSquad, D.leadRow[QJ.unit] = { [QA.unit] = true }, { row = "e18g_common", code = "e18g" }
planes = { QA }; planeSweep(1)
planes = { QJ }; planeSweep(1)
check(line("kill-time: " .. QA.name) and not has(line("kill-time: " .. QA.name), "ordinary")
      and not has(line("kill-time: " .. QJ.name), "ordinary") and D.rs.fighters == 1, "an untracked ace's and the jammer's kills aren't ordinary fighters")
-- [stats] off: the sweep still keeps where you were at each visit (p.youAt: KILL.geom's aspect, P6's samples and P4's
-- tail read it; code review of 2026-10-29): a kill from 500 m behind reads 180 deg at 0.5 km, not the aspect against
-- where you are at the death visit (1 km on, ahead of it)
CFG.stats.enabled = false
local QY = sweepPlane("f16c", "ERA_Unit_08_Dep_Air0", 0)
QY.obj.loc, QY.obj.fwd = x(0.5), AHEAD
planes = { QY }
planeSweep(1)
check(QY.youAt and QY.youAt.X == 0 and not QY.engagedAt, "[stats] off: the sweep keeps p.youAt (and no measurements)")
local kb = RUN.habit and RUN.habit.Kb or 0
you.X = 100000
QY.obj.HealthInternal = 0
D.now = 508
planeSweep(1)
you.X = 0
check(has(line("kill: " .. QY.name), "0.5 km away, 180 deg off its nose") and RUN.habit and RUN.habit.Kb == kb + 1,
      "[stats] off: the kill's aspect from p.youAt (P6 counts it from behind)")
CFG.stats.enabled = true
-- ACE.hunt (its hunt tell, TELL.hunted, reads p.dist) after this visit's p.dist (code review of 2026-10-29: it read the
-- last sweep's, 2 s late, and none at a plane's first visit)
do
    local rawHunt, seenD = ACE.hunt, "not called"
    ACE.hunt = function(p) seenD = p.dist end
    local QH = sweepPlane("f16c", "ERA_Unit_09_Dep_Air0", 0)
    QH.obj.loc = x(6)
    planes = { QH }
    planeSweep(1)
    ACE.hunt = rawHunt
    check(seenD == 6, "planeSweep: ACE.hunt reads this visit's p.dist (6 km at its first visit: " .. tostring(seenD) .. ")")
end
-- a hook that fails: its first error logged, once (code review of 2026-10-29: a bare pcall dropped it)
local function count(prefix) local n = 0; for _, l in ipairs(logs) do if l:sub(1, #prefix) == prefix then n = n + 1 end end return n end
local rawKill, rawTrack = PROF.kill, STATS.track
PROF.kill = function() error("test: PROF.kill broke") end
local HK = sweepPlane("f16c", "ERA_Unit_08_Dep_Air1", 1)
STATS.down(HK, nil, "you", 509); STATS.down(HK, nil, "you", 509.5)
PROF.kill = rawKill
STATS.track = function() error("test: STATS.track broke") end
planes = { sweepPlane("f16c", "ERA_Unit_08_Dep_Air2", 0) }
planeSweep(1); planeSweep(1)
STATS.track = rawTrack
check(count("learning: PROF.kill error") == 1 and has(line("learning: PROF.kill error"), "test: PROF.kill broke")
      and count("stats: STATS.track error") == 1 and has(line("stats: STATS.track error"), "(its first: not logged again)"),
      "a hook's first error logged once (STATS.down's PROF.kill, the sweep's STATS.track)")
planes = { Q, QA, QJ }
-- your health dropping (HIT.tick): STATS.hit
local pc = { Pawn = pawn }
pawn.HealthInternal = 800
HIT.tick(pc, 510)
pawn.HealthInternal = 700
HIT.tick(pc, 511)
check(D.hitRing and #D.hitRing == 1 and D.hitRing[1].hp == 10 and D.hitRing[1].src == "unknown" and RUN.metrics.hpTaken == 10,
      "HIT.tick: a drop of 10 HP to STATS.hit")
-- your shots (ammoTick, every 0.5 s): a missile under its cap, the gun's rounds
local ammo = { [0] = 500, 30, 10, 12, 3 }
function SV_Ammo(k, full) if full then return 999 end return ammo[k] end
function SV_SetAmmo() return 1 end
A = { pawn = nameOf(pawn), applied = true, caps = { [1] = 31, [2] = 10, [3] = 12, [4] = 3 }, seenAt = 0, tries = 0 }
PR.ammo = {}
ammoTick(2, pc)
ammo[0] = 480
ammoTick(4, pc)
check(RUN.metrics.fired[1] == 1 and RUN.metrics.fired[0] == 20 and D.rs.fired[1] == 1, "ammoTick: a missile and 20 gun rounds to STATS.fired")
-- shot down (LB.deathCheck, twice at 0): the death line with your aircraft's damage record, then LB.finish's run line
local sam = { addr = 0x5555, full = "BP_SAM_Launcher_C /Game/Mods/SurvivalMode/Maps/PL_SurvivalMode.PL_SurvivalMode:PersistentLevel.BP_SAM_Launcher_C_77" }
pawn.DamageHistoryMap = { ForEach = function(_, fn)
    fn({ get = function() return Q.obj end }, { get = function() return 55 end })
    fn({ get = function() return sam end }, { get = function() return 20 end })
end }
LB.deathCheck(pc)
pawn.HealthInternal = 0
D.now = 520
LB.deathCheck(pc); LB.deathCheck(pc)
local dh = line("death: round 9 (died)")
check(has(dh, "; record: 2 attackers, " .. SWEEP_UNIT .. " 55, BP_SAM_Launcher 20"), "LB.deathCheck: the death line, with your aircraft's damage record")
check(has(line("stats: round 9"), "(cut short: died)") and has(line("stats: run over (died)"), "rounds 2-9"), "LB.finish: the round's and the run's lines")
pawn.DamageHistoryMap = nil
D.now = 521
STATS.death("saved")
check(has(line("death: round 9 (saved by SECOND CHANCE)"), "; record: not read"), "no damage record: said so")
-- the calls left in place (their parts need the whole game to run)
local function body(file, from)
    local s = readAll(MOD .. "/Scripts/" .. file)
    local a = s:find(from)
    local b = a and s:find("\nend\r?\n", a + 1)
    return a and s:sub(a, b or #s) or ""
end
check(has(body("sv_rounds.lua", "\nlocal function startRound%(%)"), "pcall(STATS.roundStart, D.now)"), "startRound starts the measurements' round")
check(has(body("sv_rounds.lua", "\nfunction roundsTick%(now%)"), "pcall(STATS.roundEnd, now)"), "the clear (roundsTick) ends it")
check(has(body("sv_tactical.lua", "\nfunction INS.tick%(now%)"), 'pcall(STATS.death, "saved")'), "SECOND CHANCE gives a death line")
local pt = body("sv_main.lua", "\nlocal function probeTickB%(tick%)")   -- (the tick's second half since 0.73.56)
check(has(pt, 'timed("planes", planeSweep, slot)') and has(pt, 'timed("moves", ACE.movesTick, now, D)') and has(pt, "pcall(STATS.sample, D.now"),
      "probeTickB: the sweep and ACE.movesTick timed, STATS.sample every 2 s")
local spawnSrc, statsSrc = readAll(MOD .. "/Scripts/sv_spawn.lua"), readAll(MOD .. "/Scripts/sv_stats.lua")
check(has(spawnSrc, 'hookErr("roles: ROLE.spawned", pcall(ROLE.spawned') and has(spawnSrc, 'hookErr("director: DIR.spawned", pcall(DIR.spawned')
      and has(spawnSrc, 'hookErr("aces: ACE.squadUp", pcall(ACE.squadUp') and has(mainSrc, 'hookErr("stats: STATS.track", pcall(STATS.track')
      and has(mainSrc, 'hookErr("stats: STATS.down", pcall(STATS.down') and has(pt, 'hookErr("stats: STATS.sample", pcall(STATS.sample')
      and has(statsSrc, 'hookErr("learning: PROF.checkpoint", pcall(PROF.checkpoint))') and has(statsSrc, 'hookErr("learning: PROF.fold", pcall(PROF.fold, how))')
      and has(statsSrc, 'hookErr("learning: PROF.sample", pcall(PROF.sample, now, you))')
      and has(statsSrc, 'hookErr("learning: PROF.newRun", pcall(PROF.newRun, "the host started over"))'),
      "the hooks between parts log their first error (hookErr): spawnFlight's, the sweep's, probeTick's, STATS' calls to PROF")
pawn.HealthInternal, HIT.h = 800, 800

---------------------------------------------------------------------------------------------------- co-op
print("co-op")
local solo = COOP.players()
check(#solo == 1 and solo[1].slot == 0 and solo[1].at.X == you.X and solo[1].at.Z == you.Z and solo[1].hpPct == 80 and solo[1].alive
      and not solo[1].onAirfield, "COOP.players() solo: you only (slot 0, position, 80 % health)")
check(COOP.slotOfAddr(pawn.addr) == 0 and COOP.slotOfAddr(0x4242) == nil, "COOP.slotOfAddr: your pawn is slot 0")
check(COOP.me() == solo[1], "COOP.me(): read once a tick (the same D.now)")
D.now = D.now + 0.25
check(COOP.me() ~= solo[1], "COOP.me(): read again in the next tick")
-- the Reaper's reversal fires solo
D = { round = 30, now = 200, up = {}, flown = {} }
local R = { obj = plane("su57"), name = "BP_OP1022_su57_CP_C_9", unit = "ERA_Unit_05_Dep_Air0", tier = CFG.tiers.list[10] }
R.obj.loc, R.obj.fwd = x(1.5), AHEAD
planes = { R }
events = {}
ACE.movesTick(200, D)
check(events[1] == "RE_SV_AceTurn_13", "ACE.movesTick solo: a Reaper with you on its tail turns (" .. tostring(events[1]) .. ")")
ACE.movesTick(nil, D)
check(#events == 1, "ACE.movesTick before the round clock runs: nothing")
-- as the host: another player's state from SV_CoopPeerAt
CFG.coop.enabled = true
menu = 16 + 3
D = { round = 3, state = "fighting", now = 300, up = {}, flown = {} }
peerAt[2] = "1000,2000,3000,0,90,0,500,100,3,200"
COOP.tick(1)
check(COOP.host(), "co-op: hosting")
local ps = COOP.players()
local p2 = ps[2]
check(#ps == 2 and p2 and p2.slot == 2 and p2.at.X == 1000 and p2.hpPct == 50 and p2.alive and not p2.onAirfield and p2.fresh,
      "COOP.players() as the host: you and player 3 (position, 50 % health, alive, fresh)")
M.peers[2].addr = 0x777
check(COOP.slotOfAddr(0x777) == 2, "COOP.slotOfAddr: a joiner's stand-in is its slot")
peerAt[2] = "1000,2000,3000,0,90,0,500,100,5,4000"
COOP.tick(2)
ps = COOP.players()
check(ps[2] and not ps[2].fresh and not ps[2].alive and ps[2].onAirfield, "an old state: not fresh; flags 5: down at the airfield, not alive")
peerAt[2] = "nan,1,1,0,0,0,1,1,3,1"
COOP.tick(3)
check(#COOP.players() == 1, "a broken state: no position, left out")
-- as a joiner: no reversals of its own; its rounds from the host's
menu = 32 + 4
COOP.tick(4)
check(COOP.client(), "co-op: joined")
D.aceMoveAt = {}
planes = { R }
events = {}
ACE.movesTick(310, D)
check(#events == 0, "ACE.movesTick on a joiner: nothing fired")
RUN = { kills = {} }
D = { round = 3, state = "fighting", now = 300, up = {}, flown = {} }
M.rnd = { round = 4, state = "spawning", secs = 0, wave = 1, waves = 1, alive = 6, got = os.clock() }
roundsTick(320)
check(D.round == 4 and D.rs and D.rs.round == 4 and D.rs.at == 320, "joiner: the host's round 4 starts its measurements")
M.rnd = { round = 4, state = "wait", secs = 20, wave = 0, waves = 0, alive = 0, got = os.clock() }
roundsTick(400)
check(D.rs.ended == 400 and D.rs.kind == "?", "joiner: the host's clear ends it")
STATS.sample(404, you)
check(has(line("stats: round 4"), "length 80 s"), "joiner: its round line")
check(has(line("stats: round 4"), "; tail watch: not measured on a co-op joiner (its enemies are the host's)"),
      "joiner: its round line's tail watch not measured (it used to log 0 episodes as if it had)")
-- a joiner's kills: only the host knows its aces and jammer, so no time to kill here
M.rnd = { round = 8, state = "spawning", secs = 0, wave = 1, waves = 1, alive = 6, got = os.clock() }
roundsTick(420)
local JP = { obj = plane("f16c"), unit = "ERA_Unit_06_Dep_Air0", k = 0, born = 420 }
JP.name = JP.obj.full:match("([^%.:]+)$")
STATS.down(JP, nil, "you", 430)
check(has(line("kill-time: " .. JP.name), ", k 0, ordinary ?)") and D.rs.unsorted == 1 and D.rs.fighters == 0, "joiner: a pool fighter's kill is ordinary ? (not sorted)")
-- the host started over ("rs", not the answer to this game's own "jn"): the round cut short, the run so far its line
local inbox = {}
function SV_CoopRecv() return table.remove(inbox, 1) or "" end
local function runLines() local n = 0; for _, l in ipairs(logs) do if l:find("^stats: run over") then n = n + 1 end end; return n end
local runs0 = runLines()
M.jnAt = os.clock() - 100
SETUP = SETUP or { zollars = function() return 300 end }   -- (sv_menu.lua's run setup: the menu's STARTING ZOLLARS)
TAC = TAC or { reset = function() end }
RUN.credits, RUN.ups, RUN.items, RUN.insured = 9999, { gun = 2 }, { ecm = 1 }, true
inbox[1] = "0|rs"
COOP.tick(5)
-- (the co-op run of 2026-10-30: after the host's restart the joiners kept 4,400-15,260 zollars and their upgrades)
check(RUN.credits == SETUP.zollars() and next(RUN.ups) == nil and next(RUN.items) == nil and not RUN.insured and A == nil
      and has(line("run: the host's run started over"), "had 9999"),
      "joiner: the host's restart starts this game's run over too: " .. tostring(RUN.credits) .. " zollars, no upgrades or items, the loadout again")
local r8, run8 = line("stats: round 8"), line("stats: run over (the host started over)")
check(has(r8, "(cut short: the host started over)") and has(r8, "ordinary fighters ? (a joiner can't tell aces; 1 pool fighters down)"),
      "joiner: the host's restart ends its round; the round line has no time to kill")
check(has(run8, "rounds 1-8") and has(run8, "(n 0; 1 of your kills left out: a co-op joiner can't tell aces)") and runLines() == runs0 + 1,
      "joiner: the host's restart gives the run so far its line")
check(has(run8, "; tail watch Veteran+: not measured on a co-op joiner") and not has(run8, "died after median"),
      "joiner: the run line's tail watch not measured")
check(RUN.metrics == nil and D.round == 0 and D.state == "wait", "joiner: the host's next run starts on empty records")
-- a resync (the "rs" answering its own "jn"): the round cut short, the run goes on
M.rnd = { round = 9, state = "fighting", secs = 0, wave = 1, waves = 1, alive = 6, got = os.clock() }
roundsTick(500)
check(D.rs and D.rs.round == 9 and not D.rs.ended, "joiner: round 9 under way")
M.jnAt = os.clock()
RUN.credits = 4321
inbox[1] = "0|rs"
COOP.tick(6)
check(RUN.credits == 4321, "joiner: a resync (its own rejoin) keeps its money (" .. tostring(RUN.credits) .. ")")
check(has(line("stats: round 9"), "(cut short: co-op resync)") and runLines() == runs0 + 1 and RUN.metrics ~= nil,
      "joiner: a resync cuts the round short and keeps the run")

---------------------------------------------------------------------------------------------------- quieter logs
-- The clean up of 2026-10-29 (user: quieter logs, the per-round summaries kept): the periodic diagnostic lines come as
-- before only with [log] verbose (CFG.log.verbose, logVerbose()); without it on change, at a longer interval, or not.
print("quieter logs ([log] verbose)")
do
    local flagsWas = svFlags
    local F = { SV_Beat = 3, SV_Kills = 0, SV_AirHits = 0, SV_Alive = 2, SV_ShuttleHits = 0, SV_LadonRunKot = 0,
                SV_Up_01 = 1, SV_Up_02 = 0 }
    svFlags = function() return F end
    local fl, up, key = flagLine()
    check(has(fl, "SV_Beat=3") and has(fl, "SV_LadonRunKot=0") and has(fl, "flights up (SV_Up_*)=1") and up == 1,
          "flagLine: the whole line, every flag and the flights up, as before")
    check(key == "SV_LadonRunKot=0", "... and its key: the flags that aren't counters (" .. tostring(key) .. ")")
    F.SV_Beat, F.SV_Kills, F.SV_AirHits, F.SV_Alive, F.SV_ShuttleHits, F.SV_Up_02 = 4, 3, 2, 5, 1, 1
    local fl2, _, key2 = flagLine()
    check(fl2 ~= fl and key2 == key, "the heartbeat, kills, hits and flights up change the line, not its key")
    F.SV_LadonRunKot = 1
    local _, _, key3 = flagLine()
    check(key3 ~= key, "a state flag changes the key")
    svFlags = flagsWas
    local function body(file, from)
        local src = readAll(MOD .. "/Scripts/" .. file)
        local a = src:find(from)
        local b = a and src:find("\nend\r?\n", a + 1)
        return a and src:sub(a, b or #src) or ""
    end
    local pt = body("sv_main.lua", "\nlocal function probeTickB%(tick%)")   -- (the tick's second half since 0.73.56)
    local iF, iR, iA, iE = pt:find("local key = verbose and fl or flagKey", 1, true), pt:find("if not verbose then return end", 1, true),
                           pt:find("round probe: AI aircraft alive", 1, true), pt:find("enemies: nearest", 1, true)
    check(iF and iR and iA and iE and iF < iR and iR < iA and iR < iE and has(pt, "if fl and key ~= lastFlags then"),
          "probeTickB: the flags line on its key without [log] verbose; the planes alive and the nearest only with it")
    local mainSrc2 = readAll(MOD .. "/Scripts/sv_main.lua")
    check(has(mainSrc2, "if tick - pf.at < ((logVerbose() or not D.perfSaid) and 240 or 1200) then return end"),
          "the perf line every minute with [log] verbose, else a minute in and then every 5 (0.73.56)")
    local fs = readAll(MOD .. "/Scripts/sv_flights.lua")
    check(has(fs, "if tick % (logVerbose() and 40 or 240) == 0 then") and has(fs, 'if line ~= A.lastLine then log("ammo: now " .. line)'),
          "ammo: now every 10 s with [log] verbose, else every 60 s, each on a change")
    check(has(body("sv_director.lua", "\nlocal function scoreLine%(s, now%)"), "not logVerbose()"),
          "the intensity score line only with [log] verbose (its round summary either way: intensity_test)")
    check(type(CFG.log) == "table" and CFG.log.verbose == false, "CFG.log.verbose false as shipped")
end

logFile:close()
print(fails == 0 and "stats: all passed" or ("stats: " .. fails .. " FAILED"))
if fails > 0 then for i = math.max(1, #logs - 20), #logs do print("    log: " .. logs[i]) end end
os.exit(fails == 0 and 0 or 1)
