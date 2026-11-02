-- teardown_test.lua <mod dir> <work dir> (run by tools/checks/teardown_test.sh): the level going away (0.73.73, the
-- testers' logs of 0.73.70, 2026-11-01), on the real sv_core, sv_config, sv_ai, sv_spawn, sv_stats, sv_coop, sv_ladon,
-- sv_leaderboard, sv_flights and sv_main's creditKill .. probeTick chunk, the game and the runtime stubbed:
--   levelGoing: the native spawner gone once it answered in this level (SV_UnitAlive -1 / -6), another level loading
--     (svLevelOn false); never before the spawner answered (a level starting); sticky until LEAVE.reset;
--   the walks (FindAllOf / FindFirstOf, every part's): held while the level goes (8 s), a run still on with another level
--     loading, a main level just made (3 s: the main menu, a hangar, the transition map out of a run; not Survival's
--     own), the engine freeing objects (SV_GcBusy); a held walk finds nothing, the hold logged once and its end;
--   the plane sweep: a plane shot down (0 health) paid at once; one gone without its death seen paid 1 s later if the
--     level's still on; A10's order (planes gone 63 ms before the main menu's world, the spawner gone with them): none
--     paid or counted (credits, kills, the leaderboard's air kills), logged once; any going after it the same;
--   the run's end at once (leaveNow / runLeft): another level loading, or the spawner gone with your plane; a restart
--     (the spawner and the plane kept) ends nothing;
--   svFlags: no look for the event containers while the level goes, the live ones while the walks are held;
--   gameInstance kept once found;
--   the hooks, by their place in the source (sv_main, sv_flights, sv_shop, sv_hud, sv_menu).
local MOD, WORK = arg[1], arg[2]
local fails = 0
local function check(ok, what) if ok then print("  ok   " .. what) else print("  FAIL " .. what); fails = fails + 1 end end
local function readAll(p) local f = assert(io.open(p, "rb")); local s = f:read("a"); f:close(); return s end
local function writeAll(p, s) local f = assert(io.open(p, "wb")); f:write(s); f:close() end
local function has(s, part) return s ~= nil and s:find(part, 1, true) ~= nil end
do                                    -- (the runtime's paths are Windows ones: SCRIPT_DIR .. "..\\config\\")
    local rawOpen = io.open
    io.open = function(p, m) return rawOpen((tostring(p):gsub("\\", "/")), m) end
end
writeAll(WORK .. "/config/survival.default.ini", readAll(MOD .. "/config/survival.default.ini"))

local clock = 1000
os.clock = function() return clock end           -- luacheck: ignore

-- the game's world and the runtime, stubbed; the walks counted (what the wrapper lets through)
VERSION = "0.73.73-teardown.test"
local notify = {}
function NotifyOnNewObject(cls, fn) notify[cls] = notify[cls] or {}; table.insert(notify[cls], fn) end
function FName(s) return s end
local walked, found = {}, {}
function FindAllOf(c) walked[#walked + 1] = c; return found[c] end
local GI = { addr = 0x1, full = "BP_LiveGameInstance_C /Engine/Transient.GameInstance" }
function FindFirstOf(c) walked[#walked + 1] = "first:" .. c; if c == "BP_LiveGameInstance_C" then return GI end return nil end
function StaticFindObject() return nil end
function playerOnAirfield() return false end
function hudCallout() end
function queueEvent() end
function SV_Event() return 1 end
function SV_SetAircraft() return 1 end
function SV_SetLevel() return 1 end
local alive, asked = 0, 0                         -- (SV_UnitAlive's answer: the native spawner's state)
function SV_UnitAlive() asked = asked + 1; return alive end
function SV_MenuChoice() return 0 end
SETUP = { zollars = function() return 0 end, payX = function() return 1 end }
SND = { stopAll = function() end, setPaused = function() end }
TAC = { reset = function() end }

local function run(name, chunk)
    local src = readAll(MOD .. "/Scripts/" .. name)
    if name == "sv_coop.lua" then src = src:gsub("\nlocal M = {", "\nM = {", 1) end
    assert(load(src, chunk or ("=" .. name)))()
end
run("sv_core.lua", "@" .. WORK .. "/Scripts/sv_core.lua")
local logs = {}
local logFile = assert(io.open(WORK .. "/test_lua.log", "wb"))
function log(s) logs[#logs + 1] = s; logFile:write(os.date("%H:%M:%S ") .. s .. "\n") end
function valid(o) return type(o) == "table" and not o.gone end
function nameOf(o) return type(o) == "table" and o.full or "?" end
function addrOf(o) return type(o) == "table" and o.addr or nil end
run("sv_config.lua"); run("sv_ai.lua"); run("sv_spawn.lua"); run("sv_stats.lua"); run("sv_coop.lua")
run("sv_ladon.lua"); run("sv_leaderboard.lua"); run("sv_flights.lua")
M.mirror = M.mirror or 0                          -- (sv_coop's addCredits wrap: co-op closed, nothing mirrored)
local finished = {}
LB.finish = function(how) finished[#finished + 1] = how end
local function line(pat, from) for i = #logs, from or 1, -1 do if logs[i]:find(pat) then return logs[i] end end return nil end
local function count(pat, from) local n = 0; for i = from or 1, #logs do if logs[i]:find(pat) then n = n + 1 end end return n end
local function world(path)                        -- the engine makes a World: every part's callback (sv_core's, sv_config's)
    local w = { full = "World " .. path .. "." .. path:match("([^/]+)$") }
    for _, fn in ipairs(notify["/Script/Engine.World"] or {}) do fn(w) end
end
local mainSrc = readAll(MOD .. "/Scripts/sv_main.lua")
local cA, cB = mainSrc:find("\nlocal function creditKill%(p%)"), mainSrc:find("\nlocal function probeTick%(tick%)")
check(cA and cB and cA < cB, "sv_main.lua: creditKill .. probeTick found")
local _, _, planeSweep, runLeft, leaveNow = assert(load(mainSrc:sub(cA, cB) ..
    "\nreturn creditKill, timed, planeSweep, runLeft, leaveNow\n", "=sv_main.lua"))()
check(type(planeSweep) == "function" and type(runLeft) == "function" and type(leaveNow) == "function", "sv_main.lua's chunk loads")

-- the scene: your plane, the level's planes
local you = { X = 0, Y = 0, Z = 300000 }
local pawn = { addr = 0x9, full = "BP_PlayerPlane_PP1000_f16c_C /Game/Mods/SurvivalMode/Maps/PL_SurvivalMode.PL_SurvivalMode:PersistentLevel.Me",
               MaxHealth = 100, HealthInternal = 800 }
function pawn:K2_GetActorLocation() return you end
local nextAddr = 0x1000
local function plane(code)
    nextAddr = nextAddr + 0x10
    local o = { addr = nextAddr, HealthInternal = 1000, loc = { X = 400000, Y = 0, Z = 300000 }, fwd = { X = 1, Y = 0, Z = 0 },
                full = "BP_OP1022_" .. code .. "_CP_C /Game/Mods/SurvivalMode/Maps/PL_SurvivalMode.PL_SurvivalMode:PersistentLevel.BP_OP1022_"
                       .. code .. "_CP_C_" .. nextAddr }
    function o:K2_GetActorLocation() return self.loc end
    function o:GetActorForwardVector() return self.fwd end
    return { obj = o, name = o.full:match("([^%.:]+)$"), unit = "ERA_Unit_01_Dep_Air1", k = 0, addr = o.addr }   -- (logPlane's)
end
local function sweepAll() for s = 0, 7 do planeSweep(s) end end
local function newLevel()                         -- sv_main.lua's level-load reset, the parts this test needs
    LEAVE.reset()
    svLevelOn, levelTick = true, 0
    D = { round = 9, startRound = 1, state = "fighting", now = 500, up = {}, flown = {}, perf = { parts = {} }, leadRow = {} }
    RUN = newRun()
    STATS.roundStart(500)
    survivalPC, planes, alive = { Pawn = pawn, addr = 0x7 }, { plane("f18e") }, 0     -- (a plane of the level up)
    pawn.gone = nil
end

---------------------------------------------------------------------------------------------------- levelGoing
print("levelGoing: the level going away")
newLevel()
planes, asked = {}, 0
clock = clock + 1
check(not levelGoing() and asked == 0, "no plane of the level up yet: the runtime not asked (each ask then searches every object)")
planes = { plane("f18e") }
alive = -1
clock = clock + 1
check(not levelGoing(), "the spawner not ready before it ever answered (the level starting): not going")
alive = 0
clock = clock + 1
check(not levelGoing() and LEAVE.seen, "it answers (0): seen, not going")
alive = -1
clock = clock + 0.05
check(not levelGoing(), "asked 10 times a second at most: not asked again 50 ms on")
clock = clock + 0.1
local from = #logs + 1
check(not levelGoing(), "(0.73.73 review) then -1 once: not going yet (one odd answer as a restart makes its spawner)")
clock = clock + 1
local going, why = levelGoing()
check(going and why == "its unit spawner is gone: SV_UnitAlive -1", "-1 still a second on: going (" .. tostring(why) .. ")")
check(has(line("^level: Survival's level is going away", from), "its unit spawner is gone: SV_UnitAlive -1"), "logged: " .. tostring(line("^level:", from)))
alive = 0
clock = clock + 1
check(not levelGoing() and has(line("^level: its unit spawner answers again", from), "NOT going away"),
      "(0.73.73 review) the spawner answers again: not going any more, logged")
alive = -1
clock = clock + 1
levelGoing()
clock = clock + 1
check(levelGoing(), "gone again a second: going again")
svLevelOn = false
clock = clock + 1
check(levelGoing() and LEAVE.why == "another level is loading" and levelLeaving(), "then another level loading: hard")
svLevelOn, alive = true, 0
clock = clock + 1
check(levelGoing(), "a hard sign is sticky: an answer after it changes nothing")
newLevel()
check(not levelGoing(), "LEAVE.reset (a new level): not going")
alive = -6
clock = clock + 1
levelGoing()
clock = clock + 1
check(levelGoing() and has(LEAVE.why, "SV_UnitAlive -6") and not levelLeaving(), "-6 (no world) a second: going (a soft sign)")
newLevel()
svLevelOn = false
check(levelGoing() and LEAVE.why == "another level is loading", "svLevelOn false (another level made): going")
newLevel()
D = nil
svLevelOn = false
check(not levelGoing(), "no run: never going")

---------------------------------------------------------------------------------------------------- the walks
print("the walks over every object: held while a level comes or goes")
newLevel()
walked = {}
found.X = { "x" }
check(FindAllOf("X")[1] == "x" and #walked == 1, "a run on: FindAllOf walks")
from = #logs + 1
alive = -1
clock = clock + 1
levelGoing()
clock = clock + 1
levelGoing()
walked = {}
check(FindAllOf("X") == nil and FindFirstOf("Y") == nil and #walked == 0, "the level going away: FindAllOf and FindFirstOf hold (nil), nothing walked")
check(count("^walks: FindAllOf%(X%) and every walk over every object held: its unit spawner is gone", from) == 1, "the hold logged once")
clock = clock + 7.9
check(FindAllOf("X") == nil and #walked == 0, "7.9 s on: still held")
clock = clock + 0.2
check(FindAllOf("X")[1] == "x" and #walked == 1, "8 s on: walks again")
check(has(line("^walks: the hold is over", from), "(3 walks over every object waited)"), "the hold's end logged: " .. tostring(line("^walks: the hold is over", from)))
newLevel()
svLevelOn = false
walked = {}
check(FindAllOf("X") == nil and #walked == 0, "a run on and another level loading (svLevelOn false): held")
-- a main level made: 3 s (the main menu, a hangar; the transition map out of a run, or with no run); not Survival's own
D = nil
LEAVE.reset()
svLevelOn = true
world("/Game/Maps/Menu/PL_MainMenu")
from = #logs + 1
walked = {}
check(FindAllOf("X") == nil and #walked == 0 and has(line("^walks:", from), "a level is loading (PL_MainMenu)"), "the main menu's world made: held")
check(line("^world: /Game/Maps/Menu/PL_MainMenu") ~= nil and svLevelOn == false, "(sv_config's world watch too: svLevelOn false)")
clock = clock + 3.1
check(FindAllOf("X")[1] == "x", "3 s on: walks")
world("/Game/Maps/Hangar/PL_Hangar004")
check(FindAllOf("X") == nil, "a hangar's world: held")
clock = clock + 3.1
world("/Game/Mods/SurvivalMode/Maps/PL_SurvivalMode")
check(FindAllOf("X")[1] == "x" and levelTick == -1, "Survival's own level: not held (its sublevels load blocking the game thread)")
newLevel()
world("/Game/Maps/Transition/TransitionMap")
check(FindAllOf("X")[1] == "x", "the transition map made as Survival's level loads (a run on, nothing going): not held")
D = nil
world("/Game/Maps/Transition/TransitionMap")
check(FindAllOf("X") == nil, "the transition map with no run (main menu -> hangar): held")
clock = clock + 3.1
newLevel()
SV_GcBusy = function() return 1 end
from = #logs + 1
-- (0.73.73 review) the engine freeing objects holds only the walks that opt in (walkBusy: the weapons log's), not every
-- walk: an incremental purge runs often in play, and one-shot walks (the pad's removal, the missiles' toning) lost work
check(FindAllOf("X")[1] == "x" and walkBusy() == "the engine is freeing objects", "the runtime's SV_GcBusy 1: walkBusy holds, FindAllOf still walks")
SV_GcBusy = nil
check(FindAllOf("X")[1] == "x" and walkBusy() == nil, "SV_GcBusy gone: walks")

---------------------------------------------------------------------------------------------------- the plane sweep
print("the plane sweep: nothing paid or counted once the level's going away")
newLevel()
local P1 = plane("f16c")
planes = { P1 }
sweepAll()
P1.obj.HealthInternal = 0
from = #logs + 1
sweepAll()
check(P1.down and RUN.credits > 0 and RUN.kills.you == 1 and line("^round probe: " .. P1.name .. " down", from) ~= nil,
      "shot down (0 health, still there): paid at once (" .. RUN.credits .. " Z)")
-- gone without its death seen (destroyed): held 1 s, then paid with the level on
local c0, P2 = RUN.credits, plane("su33")
planes = { P2 }
sweepAll()
P2.obj.gone = true
from = #logs + 1
sweepAll()
check(P2.down and RUN.credits == c0 and #D.vanished == 1 and line("^round probe: " .. P2.name .. " down", from) == nil,
      "gone without its death seen: not paid yet, held")
clock = clock + 0.5; sweepAll()
check(RUN.credits == c0, "0.5 s on: still held")
clock = clock + 0.6; sweepAll()
check(RUN.credits > c0 and RUN.kills.you == 2 and #D.vanished == 0 and line("^round probe: " .. P2.name .. " down", from) ~= nil,
      "1 s on, the level still on: paid (a restart's or an ordinary loss's: as before)")
-- A10 (11:31:57.386): four planes gone 63 ms before the main menu's world, the spawner gone with them
newLevel()
local four = { plane("f15c"), plane("j39e"), plane("f02a"), plane("su33") }
planes = { four[1], four[2], four[3], four[4] }
sweepAll()
local c1, air1, kills1 = RUN.credits, (RUN.stats.air or 0), RUN.kills.you
for _, p in ipairs(four) do p.obj.gone = true end
from = #logs + 1
sweepAll()
check(#D.vanished == 4 and RUN.credits == c1, "four planes gone at once, the level not yet seen going: held, none paid")
clock = clock + 0.063
alive = -1
world("/Game/Maps/Menu/PL_MainMenu")
sweepAll()
check(RUN.credits == c1 and RUN.kills.you == kills1 and (RUN.stats.air or 0) == air1 and #D.vanished == 0,
      "the level going (the spawner gone, the main menu's world): none paid, no kill, no air kill counted")
check(count("^round probe: .* gone with the level", from) == 1 and line("^credits:", from) == nil and line("^kill%-time:", from) == nil,
      "logged once, no credits or kill-time lines: " .. tostring(line("gone with the level", from)))
local P5 = plane("m29a")
planes[#planes + 1] = P5
P5.obj.gone = true
sweepAll()
check(P5.down and RUN.credits == c1, "a plane gone after that: not paid either")
check(LEAVE.unpaid == 5, "5 counted unpaid (" .. tostring(LEAVE.unpaid) .. ")")

---------------------------------------------------------------------------------------------------- the run's end
print("the run's end: at once when the level goes for sure; a restart ends nothing")
newLevel()
alive = 0; clock = clock + 1; levelGoing()
alive = -1; clock = clock + 1; levelGoing(); clock = clock + 1
check(not leaveNow() and levelGoing(), "the spawner gone, your plane still there (a restart keeps both): the run goes on")
pawn.gone = true
check(not leaveNow(), "(0.73.73 review) your plane gone at one look: not yet (a restart swaps the pawn)")
clock = clock + 3
check(leaveNow(), "the spawner gone with your plane 3 s: the level's going for sure")
pawn.gone = nil
newLevel()
svLevelOn = false
check(leaveNow(), "another level loading: for sure")
planes = { plane("f16c") }
levelGoing()
D.vanished = { { p = planes[1], at = clock, now = 500 } }
from, finished = #logs + 1, {}
runLeft(LEAVE.why)
check(D == nil and levelTick == nil and #planes == 0 and finished[1] == "left", "runLeft: the run over (D, the planes), the leaderboard's finish")
check(has(line("^run over: left Survival's level in round 9", from), "(another level is loading)")
      and has(line("^round probe: %d+ planes gone with the level", from), "1 planes gone with the level: not paid or counted"),
      "logged: " .. tostring(line("^run over", from)))
newLevel()
levelTick = -1                                    -- (Survival's level made again before the run's end was seen)
svLevelOn = false
levelGoing()
runLeft(LEAVE.why)
check(D == nil and levelTick == -1, "a new Survival level waiting for its reset (levelTick -1): kept")
newLevel()
check(not leaveNow(), "a run on, nothing going: no end")

---------------------------------------------------------------------------------------------------- svFlags
print("svFlags: no look for the event containers over a level going away")
clock = clock + 3.1                               -- (the main menu's world above: its hold over)
local function container(n)
    return { addr = 0x5000 + n, full = "LiveEventContainer " .. n,
             FlagData = { IntegerFiled = { ForEach = function(_, fn)
                 fn({ get = function() return { ToString = function() return "SV_Kills" end } end }, { get = function() return { Value = n } end })
             end } } }
end
newLevel()
local C1, C2 = container(3), container(4)
found.LiveEventContainer = { C1 }
flagCache.at, flagCache.cs, flagCache.found = -1, nil, -100
walked = {}
local t = svFlags()
check(t and t.SV_Kills == 3 and #walked == 1, "the containers found (one walk), SV_Kills 3")
clock = clock + 1.1
found.LiveEventContainer = { C2 }
C1.gone = true
walked = {}
t = svFlags()
check(t and t.SV_Kills == 4 and #walked == 1, "one gone (a restart's new ones): looked for again")
clock = clock + 1.1
C2.gone = true
svLevelOn = false; levelGoing()
walked = {}
check(svFlags() == nil and #walked == 0, "another level loading (the hard sign): none, nothing walked")
svLevelOn = true
newLevel()
C2.gone = nil
flagCache.at, flagCache.cs, flagCache.found = -1, { C1, C2 }, clock
world("/Game/Maps/Hangar/PL_Hangar004")             -- (a hold with the level on: the live ones only)
svLevelOn = true
walked = {}
t = svFlags()
check(t and t.SV_Kills == 4 and #walked == 0, "the walks held, one container gone: the live one read, nothing walked")
clock = clock + 3.1

---------------------------------------------------------------------------------------------------- the game instance
print("gameInstance: kept once found")
walked = {}
check(gameInstance() == GI and gameInstance() == GI and gameInstance() == GI, "the game instance")
local n = 0
for _, w in ipairs(walked) do if w == "first:BP_LiveGameInstance_C" then n = n + 1 end end
check(n <= 1, "one walk for three calls (" .. n .. ")")
GI.gone = true
walked = {}
gameInstance()
check(#walked >= 1, "gone: looked for again")
GI.gone = nil

---------------------------------------------------------------------------------------------------- the hooks
print("the hooks, by their place in the source")
do
    local pt = mainSrc:find("\nlocal function probeTick%(tick%)")
    local ptB = mainSrc:find("\nlocal function probeTickB%(tick%)")
    local reset = mainSrc:find("LEAVE.reset()", pt, true)
    local l1 = mainSrc:find("if leaveNow() then runLeft(LEAVE.why) end", pt, true)
    local firstD = mainSrc:find("\n    if D then\n        if not liveObj(survivalPC)", pt, true)
    check(reset and l1 and firstD and reset < l1 and l1 < firstD, "probeTick: LEAVE.reset at the level load, the end check before the run's work")
    local l2 = mainSrc:find("if leaveNow() then runLeft(LEAVE.why) end", ptB, true)
    check(l2 and l2 < (mainSrc:find("timed(\"shop\", shopTick, tick)", ptB, true) or 0), "probeTickB: the end check first")
    check(has(mainSrc, 'runLeft("its player controller gone 8 s")'), "the player controller gone 8 s: the same end")
    check(has(mainSrc, "and not walkHold() then\n        c = { slots = {}"), "the ammo panel's TextBlock walk: held, not a try")
    local fl = readAll(MOD .. "/Scripts/sv_flights.lua")
    check(has(fl, "tick - levelTick >= 20 and not walkHold()"), "roundClock: the real-time fallback waits for the walks")
    local sh = readAll(MOD .. "/Scripts/sv_shop.lua")
    check(has(sh, "if walkHold() then return end                    -- (0.73.73: the walks held")
          and has(sh, "if walkHold() then return nil end                 -- (0.73.73: a held walk finds no manager")
          and has(sh, "if walkHold() then return nil end                  -- (0.73.73: a held walk finds no row"),
          "sv_shop: the STORE's relabel (its queue kept, no every-TextBlock fallback) and the menu list's check wait")
    check(has(readAll(MOD .. "/Scripts/sv_hud.lua"), "and not walkHold() then   -- look again only while they aren't found"),
          "sv_hud: the mission info panel's look waits")
    check(has(readAll(MOD .. "/Scripts/sv_menu.lua"), "if walkHold() or next(RELABEL) == nil then return 0 end"),
          "sv_menu: the main menu's relabel waits")
end

print(fails == 0 and "teardown test: all passed" or ("teardown test: " .. fails .. " FAILED"))
logFile:close()
os.exit(fails == 0 and 0 or 1)
