-- profile_test.lua <mod dir> <work dir> (run by tools/checks/profile_test.sh): the behaviour roadmap's P6, the learning
-- layer (tools/re/BEHAVIOUR_DIRECTOR.md unit 8), on the real sv_core, sv_config, sv_rows, sv_ai, sv_hud, sv_spawn,
-- sv_rounds (startRound exposed), sv_leaderboard, sv_tactical, sv_stats, sv_tells, sv_director and sv_coop (M exposed),
-- the game stubbed:
--   survival.ini's [profile] sections and [flares]; every switch on as shipped;
--   the classification: your kills (yours only: KILL.by "you"; the shares from fighters only, not a bomber's, a Ladon's
--     or a special's) by weapon and aspect, your flying every 2 s (high over the enemies near, high alone, near the
--     airfield, on a tail from p.youAt; on the ground, between rounds and a paused clock not counted; landings; the
--     airfield's time: not while bombers or a Ladon are up, not just after a takeoff, a landing's approach taken back),
--     the real sweep (sv_main.lua planeSweep) with fewer than 8 planes up: STATS.sample reads where you are, the shares,
--     the five habits, the strengths over their thresholds;
--   the counters: this run's shares once live_kills / live_samples, a saved profile weighed against them (prior_*),
--     D.counter (the jammer's and the strike's chance, PilotRank from Veteran, post-stall from Regular, cover and trap,
--     role weights, the Lancers' height, the top cover), each habit's switch, [profile] off, a co-op joiner (none: the
--     host's);
--   the levers on the real code: startRound's strike and jammer picks, the role mix (ROLE.pickRound), the squad
--     director's budgets (DIR.roundStart: cover and trap, the top cover), enemyTier's rank, enemyManeuvers' post-stall,
--     spawnFlight's Lancer height,
--     searchSetup's flare row (fake tables) from PROF.menu's read of the saved profile;
--   the file (config/survival_profile.ini): a run's end written and read back the same (the round trip), a second run
--     blended in, a short run and a head start counted only, a round's checkpoint ([run]) learnt from once at the next
--     start (the game closed mid-run), a wrong format, broken values, no file, a folder that can't be written (a
--     neutral profile, never an error; this session's kept at the next load), save off; LB.finish -> STATS.runEnd ->
--     PROF.fold (with [stats] off too), a co-op host's new run (STATS.hostReset), a joiner's own kills; min_samples (a
--     run's few samples never stand as the profile's time habits or height);
--   the code review of 2026-10-29: each kill share in force and folded on its own count (Kw, Kgeo, the gun's half), not
--     Kf; a co-op joiner linked at the host's round 20 counted, not learnt from (from round 1: learnt); the file never
--     lost: written whole (its end line), a full disk at the .tmp's write or close and a failed move in leave the old
--     file as it was (logged), a .bak (or a whole .tmp, never a cut-off one) a write the game didn't finish left read
--     and moved back in (a .bak only beside a .tmp: one a finished write couldn't remove is logged, then passed over
--     once the file's deleted), a file that isn't a profile kept as .old by the first write (logged), a file that can't
--     be read now and a failed level load never written over;
--   the hooks by their place in the source.
local MOD, WORK = arg[1], arg[2]
local fails = 0
local function check(ok, what) if ok then print("  ok   " .. what) else print("  FAIL " .. what); fails = fails + 1 end end
local function readAll(p) local f = assert(io.open(p, "rb")); local s = f:read("a"); f:close(); return s end
local function writeAll(p, s) local f = assert(io.open(p, "wb")); f:write(s); f:close() end
local function has(s, part) return s ~= nil and s:find(part, 1, true) ~= nil end
local function near(a, b, eps) return type(a) == "number" and math.abs(a - b) <= (eps or 0.001) end
do                                    -- (the runtime's paths are Windows ones: SCRIPT_DIR .. "..\\config\\")
    local rawOpen = io.open
    io.open = function(p, m) return rawOpen((tostring(p):gsub("\\", "/")), m) end
    local rawRemove, rawRename = os.remove, os.rename
    os.remove = function(p) return rawRemove((tostring(p):gsub("\\", "/"))) end
    os.rename = function(a, b) return rawRename((tostring(a):gsub("\\", "/")), (tostring(b):gsub("\\", "/"))) end
end
local defaultIni = readAll(MOD .. "/config/survival.default.ini")
writeAll(WORK .. "/config/survival.default.ini", defaultIni)
writeAll(WORK .. "/config/survival.ini", defaultIni ..
    "\r\n[profile]\r\nmin_kills = 6\r\n[profile.high]\r\nabove_m = 1200\r\n[profile.missile]\r\nrank_from = veteran\r\n" ..
    "[flares]\r\nmagazine = 24\r\n")
local PFILE = WORK .. "/config/survival_profile.ini"
os.remove(PFILE)

-- the game's world, stubbed
VERSION = "0.71.5-profile.test"
local FNm = { __index = { ToString = function(self) return self.s end }, __tostring = function(self) return self.s end }
function FName(s) return setmetatable({ s = tostring(s) }, FNm) end
local GI = { full = "GameInstance", addr = 1 }
function NotifyOnNewObject() end
function FindAllOf() return {} end
function FindFirstOf(c) if c == "BP_LiveGameInstance_C" then return GI end return nil end
local OBJ = {}
function StaticFindObject(p) return OBJ[p] end
local grounded = false
function playerOnAirfield() return grounded end
function airfieldTick() end
function bombTick() end
local events = {}
function SV_Event(name) events[#events + 1] = name; return 1 end
function SV_UnitAlive() return 0 end
function SV_SetAircraft() return 1 end
function SV_SetLevel() return 1 end
local spawns = {}
function SV_Spawn(unit, x, y, z, yaw)
    spawns[#spawns + 1] = { unit = unit, x = x, y = y, z = z, yaw = yaw }
    local ok, n = pcall(flightSize, unit)
    return ok and n or 1
end
function SV_MenuChoice() return 0 end
function SV_CoopOpen() return 1 end
function SV_CoopClose() end
function SV_CoopSend() return 1 end
function SV_CoopRecv() return "" end
function SV_CoopInfo() return "open=0" end
function SV_CoopMe() end
function SV_CoopReset() end
function SV_CoopTrack() return 1 end
function SV_CoopBind() return 1 end
function SV_CoopPeer() return 1 end
function SV_CoopPeerAt() return "" end
SETUP = { enemyX = function() return 1 end, specialsX = function() return 1 end, breakS = function() return 20 end,
          skillAdd = function() return 0 end }

-- the real parts (sv_core's SCRIPT_DIR and log file in the work folder)
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
function nameOf(o) return type(o) == "table" and (o.full or "?") or "?" end
function addrOf(o) return type(o) == "table" and o.addr or nil end
part("sv_config.lua")
local cfgLine = nil
for _, l in ipairs(logs) do if l:find("^config: survival%.ini") then cfgLine = l end end
part("sv_rows.lua"); part("sv_ai.lua"); part("sv_hud.lua"); part("sv_spawn.lua")
part("sv_rounds.lua", nil, { { "\nlocal function startRound%(%)", "\nfunction startRound()" } })
part("sv_leaderboard.lua"); part("sv_tactical.lua"); part("sv_stats.lua"); part("sv_tells.lua"); part("sv_director.lua")
part("sv_coop.lua", nil, { { "\nlocal M = {", "\nM = {" } })
function playerOnAirfield() return grounded end      -- (sv_rounds.lua's own reads the pawn)
LB.stat, LB.special = function() end, function() end
presetName = function() return "standard", 3 end
SPC.kinds = {}
function SPC.kindValue(v, ...) if type(v) == "function" then return v(...) end return v end
AMPH.ready = function() return true end
ANOM.fx = ANOM.fx or {}
local rawRandom = math.random
math.randomseed(6)

local function line(prefix, from)
    for i = #logs, from or 1, -1 do if logs[i]:sub(1, #prefix) == prefix then return logs[i] end end
    return nil
end
local function deep(t) if type(t) ~= "table" then return t end; local c = {}; for k, v in pairs(t) do c[k] = deep(v) end; return c end
local function body(file, from)
    local s = readAll(MOD .. "/Scripts/" .. file)
    local a = s:find(from)
    local b = a and s:find("\nend\r?\n", a + 1)
    return a and s:sub(a, b or #s) or ""
end

---------------------------------------------------------------------------------------------------- survival.ini
print("survival.ini's [profile] and [flares]")
check(cfgLine and not has(cfgLine, "not used"), "config: every line used (" .. tostring(cfgLine) .. ")")
check(CFG.profile.min_kills == 6 and math.type(CFG.profile.min_kills) == "integer" and CFG.profile.high.above_m == 1200
      and CFG.profile.missile.rank_from == "veteran" and CFG.flares.magazine == 24,
      "[profile] min_kills, [profile.high] above_m, [profile.missile] rank_from and [flares] magazine read")
CFG.profile, CFG.flares = deep(CFG_DEFAULTS.profile), deep(CFG_DEFAULTS.flares)
local P = CFG.profile
check(P.enabled and P.save and P.checkpoint and P.missile.enabled and P.gun.enabled and P.tail.enabled and P.high.enabled
      and P.airfield.enabled and CFG.flares.enabled and not CFG.flares.always, "every switch on as shipped (always off)")
check(PROF.weights and PROF.kill and PROF.sample and PROF.fold and PROF.menu and PROF.levelLoad and PROF.checkpoint,
      "PROF's hooks exist")

---------------------------------------------------------------------------------------------------- classification
print("the classification")
RUN = {}
D = { round = 5, startRound = 1, state = "fighting", now = 100, up = {}, flown = {}, queue = {}, spare = {} }
local function geo(wpn, offNose, km)                -- a kill's KILL.geom: your shots in the 6 s before, its aspect
    local used = { gun = 0, msl = 0, sp1 = 0, sp2 = 0, flr = 0 }
    if wpn == "msl" then used.msl = 1 elseif wpn == "gun" then used.gun = 12 elseif wpn == "sp1" then used.sp1 = 2
    elseif wpn == "both" then used.msl, used.gun = 1, 5 end
    return { used = used, offNose = offNose, km = km }
end
local function F() return { unit = "ERA_Unit_03_Dep_Air1" } end      -- (a pool flight's fighter)
for _ = 1, 4 do PROF.kill(F(), geo("msl", 170, 1.5), "you") end      -- missiles from behind
for _ = 1, 2 do PROF.kill(F(), geo("msl", 20, 2.5), "you") end       -- missiles head on
PROF.kill(F(), geo("sp1", 160, 1.0), "you")                           -- a special from behind, close
for _ = 1, 2 do PROF.kill(F(), geo("gun", 175, 0.6), "you") end      -- the gun from behind, close
PROF.kill(F(), geo("both", 30, 0.9), "you")                           -- gun and a missile: the gun's, close, head on
PROF.kill(F(), geo("msl", 170, 1.5), "wingmate")                      -- (not yours: none of these count)
PROF.kill(F(), geo("msl", 170, 1.5), "allies")
PROF.kill(F(), geo("msl", 170, 1.5), nil)
PROF.kill(F(), nil, "you")                                            -- yours, nothing read: a kill only
PROF.kill(F(), geo("none", 100, 4), "you")                            -- nothing fired seen; 100 deg at 4 km: not behind
-- yours, but not a fighter's: a raid's bomber, a Ladon, a special (and a plane with no flight): kills, not the shares
PROF.kill({ unit = CFG.airfield.bombers.pool[1] }, geo("msl", 175, 1.5), "you")
PROF.kill({ unit = "SV_Unit_LadonA" }, geo("msl", 175, 1.5), "you")
PROF.kill({ unit = CFG.specials.anomaly.unit }, geo("msl", 175, 1.5), "you")
PROF.kill({}, geo("msl", 175, 1.5), "you")
local h = RUN.habit
check(h and h.K == 16 and h.Kf == 12 and h.Kw == 10 and h.Km == 7 and h.Kg == 3 and h.Kgeo == 11 and h.Kc == 4 and h.Kb == 7,
      string.format("your kills only: K %s (of fighters %s), with a weapon %s (missiles %s, gun %s), with an aspect %s (close %s, behind %s)",
      h and h.K, h and h.Kf, h and h.Kw, h and h.Km, h and h.Kg, h and h.Kgeo, h and h.Kc, h and h.Kb))
-- your flying (every 2 s of the round clock): you 30 km east of the airfield
local AF = AIRFIELD
local function pt(dx, z) return { X = AF.X + dx * 100000, Y = AF.Y, Z = z * 100 } end
local function enemy(at, fwd, dist) return { at = at, fwd = fwd, dist = dist, unit = "ERA_Unit_01_Dep_Air0", obj = {} } end
local E1 = enemy(pt(33, 3000), { X = -1, Y = 0, Z = 0 }, 3.6)       -- 3 km up, nose on you (you're ahead of it)
local samples = {
    { you = pt(30, 6000), planes = { E1 } },                          -- high over it (6 km >= 3 + 1)
    { you = pt(30, 4500), planes = { enemy(pt(32, 4000), { X = -1, Y = 0, Z = 0 }, 2.1) } },   -- not high (4.5 < 5)
    { you = pt(30, 5500), planes = { enemy(pt(55, 3000), { X = -1, Y = 0, Z = 0 }, 25) } },    -- none near: 5.5 >= 5
    { you = pt(30, 4000), planes = {} },                              -- none near, 4 km: not high
    { you = pt(5, 2000), planes = {} },                               -- 5 km from the runway: near the airfield
}
for i, s in ipairs(samples) do
    planes = s.planes
    PROF.sample(100 + 2 * i, s.you)
end
-- on a tail: from where you were at its sample (p.youAt), not where you are now (60 km off)
local E2 = enemy(pt(31, 2500), { X = 1, Y = 0, Z = 0 }, 1.1)
E2.youAt = pt(30, 3000)                                              -- 1 km behind it, 500 m over: 27 deg off its six
planes = { E2 }
PROF.sample(112, pt(90, 3000))
check(h.S == 6 and h.Sh == 2 and h.Sa == 1 and h.SaN == 6 and h.St == 1,
      string.format("6 samples: high 2 (over the enemies near, alone over 5 km), near the airfield 1 of 6, on a tail 1 (p.youAt): %d / %d / %d of %d / %d",
      h.S, h.Sh, h.Sa, h.SaN, h.St))
PROF.sample(113, pt(30, 3000))
check(h.S == 6, "a second sample within 1.5 s of the round clock (a pause): not counted")
grounded = true
PROF.sample(116, pt(1, 10))
check(h.S == 6 and h.landings == 1 and h.Sa == 0 and h.SaN == 5,
      "on the ground: not a sample; a landing counted, its approach (the airfield sample 6 s before) taken back")
grounded = false
D.state = "wait"
PROF.sample(120, pt(30, 6000))
check(h.S == 6 and h.landings == 1, "between rounds: not a sample")
D.state = "fighting"
planes = {}
PROF.sample(130, pt(5, 2000))                                        -- 14 s after you were on the ground: the climb-out
check(h.S == 7 and h.Sa == 0 and h.SaN == 5, "over the airfield 14 s after a takeoff (after_takeoff_s 45): not the airfield's")
PROF.sample(170, pt(5, 2000))                                        -- 54 s after
check(h.S == 8 and h.Sa == 1 and h.SaN == 6, "over the airfield 54 s after: the airfield's")
local BMB = { unit = CFG.airfield.bombers.pool[1], at = pt(60, 3000), dist = 55, obj = {} }
planes = { BMB }
PROF.sample(172, pt(5, 2000))
check(h.S == 9 and h.Sa == 1 and h.SaN == 6 and h.Sh == 2, "a raid's bomber up (skip_raids): not the airfield's time (nor an enemy near)")
planes = { { unit = "SV_Unit_LadonB", at = pt(9, 3000), dist = 4, obj = {} } }
PROF.sample(174, pt(5, 2000))
check(h.S == 10 and h.SaN == 6, "a Ladon up: not the airfield's either")
P.airfield.skip_raids = false
PROF.sample(176, pt(5, 2000))
P.airfield.skip_raids = true
check(h.S == 11 and h.Sa == 2 and h.SaN == 7, "skip_raids off: counted")
planes = {}
PROF.sample(178, pt(30, 4000))
check(h.S == 12 and h.Sa == 2 and h.SaN == 8, "away from the airfield: the airfield's time, not near it")
local s = PROF.runShares(h)
check(near(s.missile, 0.7) and near(s.gun, 4 / 11) and near(s.behind, 7 / 11) and near(s.tail_time, (1 / 12) / 0.3)
      and near(s.high, 2 / 12) and near(s.airfield, 2 / 8),
      string.format("the shares: missile %.3f, gun %.3f (the bigger of gun 0.30 and close 0.36), behind %.3f, tail time %.3f, high %.3f, airfield %.3f (2 of 8)",
      s.missile, s.gun, s.behind, s.tail_time, s.high, s.airfield))
local hb = PROF.habitsOf(s)
check(near(hb.tail, 0.6 * 7 / 11 + 0.4 * (1 / 12) / 0.3), string.format("tail = 0.6 behind + 0.4 its time: %.3f", hb.tail))
check(PROF.strength("missile", 0.7) == 0 and near(PROF.strength("gun", 4 / 11), (4 / 11 - 0.35) / 0.65)
      and PROF.strength("tail", hb.tail) == 0 and PROF.strength("missile", 0.9) == 0.5 and PROF.strength("missile", 1) == 1
      and PROF.strength("missile", 0.8) == 0 and PROF.strength("high", nil) == 0, "the strengths: 0 at or under each threshold, 1 at 1.0")
local cur = PROF.current(h, nil)
check(near(cur.missile, 0.7) and cur.high == nil and cur.tail_time == nil and cur.airfield == nil,
      "this run's: its kills' shares (12 of fighters >= live_kills 5), not yet its time's (12 < live_samples 30)")
local h3 = { K = 9, Kf = 3, Kw = 3, Km = 3, Kg = 0, Kgeo = 3, Kc = 0, Kb = 3, S = 0, Sh = 0, Sa = 0, SaN = 0, St = 0, alt = {} }
check(PROF.current(h3, nil).missile == nil, "9 kills, 3 of fighters (under live_kills 5): nothing of this run's yet")
local saved = { learnt = 3, runs = 4, missile = 0.5, high = 0.9 }
check(near(PROF.current(h3, saved).missile, 0.5) and near(PROF.current(h3, saved).high, 0.9),
      "a saved profile alone until then")
local h10 = { K = 10, Kf = 10, Kw = 10, Km = 10, Kg = 0, Kgeo = 10, Kc = 0, Kb = 0, S = 30, Sh = 0, Sa = 0, SaN = 30, St = 0, alt = {} }
local c10 = PROF.current(h10, saved)
check(near(c10.missile, (20 * 0.5 + 10 * 1) / 30) and near(c10.high, (150 * 0.9 + 30 * 0) / 180),
      string.format("this run's against the profile's as prior_kills 20 / prior_samples 150 of its own: missile %.3f, high %.3f",
      c10.missile, c10.high))
check(PROF.current(h10, { learnt = 0, runs = 2, missile = 0.1 }).missile == 1, "a profile learnt from no run: not weighed")
-- through the real sweep (sv_main.lua planeSweep on its slot 0, then STATS.sample as probeTick calls it) with fewer than
-- 8 planes up: the sweep reads where you are only when it visits a plane (on slot 0 the 8th, 16th ...), so it read
-- nothing; STATS.sample reads it then, once for both (the U8 review: rounds 1-2 had no samples, later rounds none once
-- their 8th plane was down)
do
    local mainSrc = readAll(MOD .. "/Scripts/sv_main.lua")
    local cA, cB = mainSrc:find("\nlocal function creditKill%(p%)"), mainSrc:find("\nlocal function probeTick%(tick%)")
    local _, timedM, sweep = assert(load(mainSrc:sub(cA, cB) .. "\nreturn creditKill, timed, planeSweep\n", "=sv_main.lua"))()
    RUN = {}
    D = { round = 1, startRound = 1, state = "fighting", now = 200, up = {}, flown = {}, queue = {}, spare = {} }
    local reads, rawLoc = 0, playerLocation
    playerLocation = function() reads = reads + 1; return pt(30, 6000) end
    planes = { enemy(pt(33, 3000), { X = -1, Y = 0, Z = 0 }, 3), enemy(pt(34, 3000), { X = -1, Y = 0, Z = 0 }, 4),
               enemy(pt(35, 3000), { X = -1, Y = 0, Z = 0 }, 5), enemy(pt(36, 3000), { X = -1, Y = 0, Z = 0 }, 6) }
    local swept = 0                                   -- (sweeps that read you, or failed)
    for i = 1, 5 do
        D.now = 200 + 2 * i
        local okPl, you = timedM("planes", sweep, 0)
        if not okPl or you ~= nil then swept = swept + 1 end
        if D then pcall(STATS.sample, D.now, you or nil) end
    end
    playerLocation = rawLoc
    local hs = RUN.habit
    check(swept == 0 and hs and hs.S == 5 and hs.Sh == 5 and reads == 5,
          string.format("4 planes up: the sweep's slot 0 read nothing, STATS.sample read you (%d reads): 5 samples, 5 high (%s / %s)",
          reads, tostring(hs and hs.S), tostring(hs and hs.Sh)))
    local probe = body("sv_main.lua", "\nlocal function probeTick%(tick%)")
    check(has(probe, "pcall(STATS.sample, D.now, you or nil)") and has(body("sv_stats.lua", "\nfunction STATS.sample%("),
          "if not you then you = playerLocation() end"), "probeTick passes the sweep's you; STATS.sample reads it when that's nil")
end

---------------------------------------------------------------------------------------------------- counters
print("the counters (PROF.weights)")
-- a run with every habit: 20 kills, 19 with missiles, 12 close, 18 from behind; 100 samples, 80 high, 70 near the
-- airfield, 30 on a tail, all at 6 km
local function strong()
    return { id = "abc123", K = 20, Kf = 20, Kw = 20, Km = 19, Kg = 1, Kgeo = 20, Kc = 12, Kb = 18, S = 100, Sh = 80, Sa = 70,
             SaN = 100, St = 30, landings = 2, alt = { [24] = 100 } }
end
RUN = { habit = strong() }
PROF.saved = nil
D = { round = 12, startRound = 1, state = "spawning", now = 300, up = {}, flown = {}, queue = {}, spare = {} }
local from = #logs + 1
PROF.weights(12)
local C = D.counter
check(C and near(C.strength.missile, 0.75) and near(C.strength.gun, (0.6 - 0.35) / 0.65) and near(C.strength.tail, (0.94 - 0.7) / 0.3)
      and near(C.strength.high, 0.6) and near(C.strength.airfield, 0.5), "strengths: missile 0.75, gun 0.38, tail 0.80, high 0.60, airfield 0.50")
check(near(PROF.chance("jammer", 0.5), 0.875) and near(PROF.chance("jammer", 0.6), 0.9) and PROF.chance("jammer", 0.95) == 0.95,
      "the jammer's chance x (1 + jammer_x x 0.75), at most jammer_max 0.9 (never lowered)")
check(near(PROF.chance("strike", 0.35), 0.525) and PROF.chance("other", 0.4) == 0.4, "the strike's chance x 1.5")
local VET, REG = 3, 2
check(CFG.tiers.list[VET].name == "Veteran" and PROF.rankAdd(VET) == 1 and PROF.rankAdd(5) == 1 and PROF.rankAdd(REG) == 0,
      "PilotRank +1 from Veteran up, none under")
check(PROF.postStall(CFG.tiers.list[REG]) and PROF.postStall(VET) and not PROF.postStall(CFG.tiers.list[1]) and not PROF.postStall(nil),
      "post-stall from Regular (a tier or its index), not a Rookie")
check(near(C.tail, 0.8) and near(C.roleW.duelist, 1 + (0.6 - 0.35) / 0.65) and near(C.roleW.wolf, 1 + 0.5 * (0.6 - 0.35) / 0.65 + 0.8)
      and near(C.roleW.lancer, 1.9) and near(C.roleW.skirm, 1.75),
      string.format("cover and trap +0.80; role weights duelist %.2f, wolf %.2f, lancer %.2f, skirm %.2f", C.roleW.duelist,
      C.roleW.wolf, C.roleW.lancer, C.roleW.skirm))
check(PROF.lancerAlt() == 6125 + 1000, "the Lancers at your usual 6.1 km + above_m 1000 (" .. tostring(PROF.lancerAlt()) .. ")")
check(near(C.top, 0.6), "the top cover: top_cover_x 1.0 x the high habit's 0.60 (" .. tostring(C.top) .. ")")
local wl = line("learning: round 12: habits", from)
check(has(wl, "missile 0.95 (over 0.80, strength 0.75)") and has(wl, "this run 20 of your kills, 20 of fighters, 200 s flown; the profile none")
      and has(wl, "Lancers from 7.1 km up (your usual 6.1 km), top cover x1.60")
      and has(wl, "the jammer's chance 0.50 -> 0.87") and has(wl, "PilotRank +1 from Veteran")
      and has(wl, "post-stall on every airframe from Regular") and has(wl, "cover and trap x1.80")
      and has(wl, "Lancers from 7.1 km up (your usual 6.1 km)") and has(wl, "the strike's chance 0.35 -> 0.52")
      and has(wl, "role mix duelist x1.38, lancer x1.90, wolf x1.99, skirm x1.75 (roles off: no effect)"),
      "the round's line: every share and decision (" .. tostring(wl) .. ")")
-- each habit's own switch, the profile off, a joiner
P.missile.enabled = false
PROF.weights(12)
check(D.counter.strength.missile == 0 and not D.counter.jammerX and PROF.rankAdd(VET) == 0 and PROF.chance("jammer", 0.5) == 0.5,
      "[profile.missile] off: no jammer, rank or flare counter")
P.missile.enabled = true
P.high.enabled, P.airfield.enabled = false, false
PROF.weights(12)
check(near(D.counter.roleW.lancer, 1) and near(D.counter.roleW.skirm, 1) and PROF.lancerAlt() == nil and PROF.chance("strike", 0.35) == 0.35
      and D.counter.top == nil, "[profile.high] / [profile.airfield] off: no Lancer, top cover, Skirmisher or strike counter")
P.high.enabled, P.airfield.enabled = true, true
P.enabled = false
PROF.weights(12)
check(D.counter == nil and PROF.chance("jammer", 0.5) == 0.5 and PROF.rankAdd(VET) == 0, "[profile] off: no counters")
P.enabled = true
RUN = { habit = { id = "e1", K = 0, Kf = 0, Kw = 0, Km = 0, Kg = 0, Kgeo = 0, Kc = 0, Kb = 0, S = 0, Sh = 0, Sa = 0, SaN = 0, St = 0,
                  landings = 0, alt = {} } }
from = #logs + 1
PROF.weights(13)
check(D.counter and has(line("learning: round 13", from), "-> nothing to counter"), "no habits: nothing to counter (logged)")
COOP.open, COOP.role = true, "join"
RUN = { habit = strong() }
PROF.weights(12)
check(D.counter == nil, "a co-op joiner: no counters of its own (its enemies are the host's)")
D.counter = { jammerX = 2, rank = 1, rankFrom = 1, postStallFrom = 1, roleW = { lancer = 3 }, lancerAlt = 8000 }
check(PROF.chance("jammer", 0.5) == 0.5 and PROF.rankAdd(VET) == 0 and not PROF.postStall(VET) and PROF.roleW() == nil
      and PROF.lancerAlt() == nil, "a joiner reads none (its copies fly the host's)")
PROF.kill(F(), geo("gun", 175, 0.5), "you"); PROF.kill(F(), geo("msl", 170, 1.5), "wingmate")
check(RUN.habit.K == 21 and RUN.habit.Kf == 21 and RUN.habit.Kg == 2, "a joiner's own kills count in its own profile, a partner's don't")
COOP.open, COOP.role = false, nil

---------------------------------------------------------------------------------------------------- the levers
print("the levers on the real code")
-- enemyTier / enemyManeuvers (round 5: no difficulty spike)
RUN = { habit = strong() }
D = { round = 5, startRound = 1, state = "fighting", now = 400, up = {}, flown = {}, queue = {}, spare = {} }
PROF.weights(5)
local function enemyPlane(code) return { obj = { PilotRank = 1 }, name = "BP_OP1022_" .. code .. "_CP_C_7" } end
local pv, pr = enemyPlane("f16c"), enemyPlane("f16c")
enemyTier(pv, 5, VET); enemyTier(pr, 5, REG)
check(pv.rankSet == 5 and pv.obj.PilotRank == 5 and pv.rankBase == 5 and pr.rankSet == 3,
      "enemyTier: a Veteran 4 + 1 = 5 (rankBase too: P4's live rewrite keeps it), a Regular 3")
enemyManeuvers(pr, 5)
check(pr.obj.bCanManeuverPugachevsCobra == true and pr.obj.bCanManeuverKulbit == true,
      "enemyManeuvers: a Regular's F-16C gets cobra and kulbit (the gun habit)")
local saveCtr = D.counter
D.counter = nil
local pv0, pr0 = enemyPlane("f16c"), enemyPlane("f16c")
enemyTier(pv0, 5, VET); enemyTier(pr0, 5, REG); enemyManeuvers(pr0, 5)
check(pv0.rankSet == 4 and pr0.obj.bCanManeuverPugachevsCobra == false, "without a counter: Veteran 4, the Regular's F-16C no post-stall")
D.counter = saveCtr
-- spawnFlight: a Lancer above your usual height (within its band); roles live
ROLE.live = { duelist = true, lancer = true, wolf = true, skirm = true }
SR.usable = {}
for _, a in ipairs(CFG.aircraft) do SR.usable[a] = a .. "_sv" end
for _, e in ipairs(CFG.variety.late) do SR.usable[e[1]] = e[1] .. "_sv" end
SR.usable[CFG.jammer.aircraft] = "e18g_sv"
function searchAircraft(a) return a end
local LANCER = ROLE.units.lancer[1]
spawns = {}
spawnFlight(LANCER)
check(#spawns == 1 and near(spawns[1].z, 7125 * 100, 1), string.format("a Lancer at 7.1 km (your 6.1 + 1.0; its own 4-6.5 km): %.0f m",
      (spawns[1] and spawns[1].z or 0) / 100))
D.counter.lancerAlt = 9600
D.up = {}
spawns = {}
spawnFlight(LANCER)
check(near(spawns[1].z, (ROLE.LANCER_TOP_M - 500) * 100, 1), "never above its band: 8.5 km")
local DUEL = ROLE.units.duelist[1]
D.up = {}
spawns = {}
spawnFlight(DUEL)
check(spawns[1].z <= CFG.altitude_m[2] * 100, "a duelist keeps its own height")
-- startRound: the strike and the jammer (math.random fixed at 0.5: under the counters' chances, over the stock ones),
-- the role mix weighed, the squad director's cover and trap budgets
CFG.specials.enabled, CFG.allies.enabled = false, false
local b = CFG.airfield.bombers
local R = nil
for r = 9, 15 do if R == nil and (r - b.first_raid) % math.max(1, math.floor(b.raid_every)) ~= 0 then R = r end end
math.random = function(a, c) if a == nil then return 0.5 elseif c == nil then return 1 else return a end end
local function play(habit)
    planes = {}
    RUN = { habit = habit, kills = {} }
    D = { round = R - 1, startRound = 1, state = "wait", at = 0, now = 1000, up = {}, flown = {}, queue = {}, spare = {}, events = {} }
    local f = #logs + 1
    startRound()
    return f
end
local f0 = play({ id = "e2", K = 0, Kf = 0, Kw = 0, Km = 0, Kg = 0, Kgeo = 0, Kc = 0, Kb = 0, S = 0, Sh = 0, Sa = 0, SaN = 0, St = 0,
                  landings = 0, alt = {} })
local function since(f, pat) for i = f, #logs do if logs[i]:find(pat, 1, true) then return logs[i] end end return nil end
check(R and not since(f0, "a strike package") and not since(f0, "the jammer flies with") and has(since(f0, "learning: round " .. R), "nothing to counter"),
      "round " .. tostring(R) .. ", no habits: no strike (0.5 over 0.35), no jammer (0.5 not under 0.5)")
check(not has(since(f0, "roles: round " .. R), "weighed by your habits") and not has(since(f0, "director: round " .. R .. "'s budgets"), "your tail chasing"),
      "no habits: the role mix and the director's budgets as shipped")
local f1 = play(strong())
check(since(f1, "a strike package") and since(f1, "the jammer flies with"), "the airfield and missile habits: a strike (0.53) and the jammer (0.88)")
local rl = since(f1, "roles: round " .. R)
local band = ROLE.mixFor(R)
check(has(rl, "weighed by your habits") and near(tonumber(rl and rl:match("lancer (%d+%.%d+)")), band.lancer * 1.9, 0.006)
      and near(tonumber(rl and rl:match("skirm (%d+%.%d+)")), band.skirm * 1.75, 0.006)
      and near(tonumber(rl and rl:match("duelist (%d+%.%d+)")), band.duelist * (1 + (0.6 - 0.35) / 0.65), 0.006),
      "the role mix weighed by your habits (" .. tostring(rl) .. ")")
check(has(since(f1, "director: round " .. R .. "'s budgets"), "cover and trap x1.80 (your tail chasing)") and D.dir and near(D.dir.factor, 1.8),
      "DIR.roundStart: cover and trap budgets x1.80 (D.counter.tail)")
local bl = since(f1, "director: round " .. R .. "'s budgets")
local bl0 = since(f0, "director: round " .. R .. "'s budgets")
local top0, top1 = tonumber(bl0 and bl0:match("top_cover (%d+)")), tonumber(bl and bl:match("top_cover (%d+)"))
check(has(bl, "; top cover x1.60 (you stay high)") and near(D.dir.topFactor, 1.6) and top0 and top1
      and top1 == math.floor(top0 * 1.6 + 0.5) and not has(bl0, "top cover x"),
      string.format("DIR.roundStart: the top cover's budget x1.60 (D.counter.top): %s -> %s", tostring(top0), tostring(top1)))
math.random = rawRandom
-- searchSetup's flare row (fake tables, as roles_test's): from PROF.menu's read of the saved profile
local function copyRow(r)
    if type(r) ~= "table" then return r end
    local c = {}
    for k, v in pairs(r) do c[k] = copyRow(v) end
    return setmetatable(c, getmetatable(r))
end
local function fakeDT(name)
    local t = { full = name, rows = {} }
    function t.FindRow(self, n) return self.rows[type(n) == "table" and n.s or n] end
    function t.AddRow(self, n, r) self.rows[type(n) == "table" and n.s or n] = copyRow(r) end
    function t.RemoveRow(self, n) self.rows[type(n) == "table" and n.s or n] = nil end
    return t
end
local tbl = {}
local function tables()
    for k in pairs(OBJ) do OBJ[k] = nil end
    tbl.npc, tbl.mod, tbl.mission, tbl.fcs, tbl.wpn = fakeDT("DT_NPC"), fakeDT("DT_NPC_AIModule"), fakeDT("DT_SV_NpcMission"),
        fakeDT("DT_NPC_FCS"), fakeDT("DT_NPC_Weapon")
    tbl.mod.rows.NPC_AIModule_Plane000 = { Radius = 6000, bEnableLostTargetInClouds = true }
    for _, id in ipairs({ "NPC_FCS_PlaneMsl000", "NPC_FCS_PlaneLAAM000", "NPC_FCS_PlaneQAAM000", "NPC_FCS_Plane2AAM000",
                          "NPC_FCS_PlaneHCAA000" }) do
        tbl.fcs.rows[id] = { CaptureDistance = 2500, CaptureMinDistance = 300, CaptureAngleRange = 45, ActivationTime = 2,
                             TriggeringTime = 2.5, ShotIntervalTime = 10, RestingTime = 10, TriggerCount = 1, PredictionOffsetTime = 0 }
    end
    tbl.fcs.rows.NPC_FCS_PlaneFlr000 = { MagazineCapacity = 10, ReloadTime = 25.0, TriggerCount = 10 }
    tbl.fcs.rows.NPC_FCS_PlaneGun000 = { CaptureDistance = 1500, CaptureAngleRange = 30, TriggeringTime = 1.5, TriggerCount = 10,
                                         RestingTime = 1, PredictionOffsetTime = 0, NpcWeaponId = FName("GUN_000") }
    tbl.wpn.rows.GUN_000 = { damage = 1, MaxSpawnAngle = 3, LifeTime = 2 }
    local list = { "f16c_common" }
    for _, a in ipairs(CFG.aircraft) do list[#list + 1] = a end
    for _, e in ipairs(CFG.variety.late) do list[#list + 1] = e[1] end
    list[#list + 1] = CFG.jammer.aircraft
    for _, a in ipairs(list) do
        local npc = "OP_" .. a
        tbl.npc.rows[npc] = { NpcFCSId0 = FName("NPC_FCS_PlaneFlr000"), NpcFCSId1 = FName("NPC_FCS_PlaneGun000"),
                              NpcFCSId2 = FName("NPC_FCS_PlaneMsl000"), NpcFCSId3 = FName("None"), NpcFCSId4 = FName("None"),
                              NpcFCSId5 = FName("None"), LuaSetId = FName("NLID_0012_CP"), NpcAIModuleId = FName("NPC_AIModule_Plane000") }
        tbl.mission.rows[a] = { NpcId = FName(npc) }
        for lv = 0, #SPIKE_SUFFIX do
            tbl.mission.rows[a .. "_sv" .. SPIKE_SUFFIX[lv]] = { NpcId = FName(npc .. "_SV" .. SPIKE_SUFFIX[lv]:upper()) }
        end
    end
    OBJ[PROBE_TABLES[2].path], OBJ[SEARCH_MODULE.path] = tbl.npc, tbl.mod
    OBJ["/Game/Mods/SurvivalMode/Data/DT_SV_NpcMission.DT_SV_NpcMission"] = tbl.mission
    OBJ[FCS_TABLE], OBJ[WEAPON_TABLE] = tbl.fcs, tbl.wpn
end
local function search()
    BS.done, BS.ready = true, {}
    SR.done, SR.ready, SR.tries, SR.levels = false, {}, 0, {}
    tables()
    searchSetup()
end
-- a saved profile with the missile habit (missile 0.95 over 0.80), written as the game writes it
writeAll(PFILE, "; a test profile\r\n[profile]\r\nversion = 1\r\nruns = 2\r\nlearnt = 2\r\nkills = 40\r\nmissile = 0.95\r\n")
from = #logs + 1
PROF.menuDone = nil
PROF.menu()
check(PROF.menuDone and PROF.flareWant and PROF.flareWant.magazine == 20 and PROF.flareWant.reload_s == 8.0
      and has(line("learning: the AI's flares refilled this session", from), "your saved missile share 0.95, over 0.80"),
      "PROF.menu: the saved missile habit: this session's flare row refilled (20, 8 s)")
search()
local flr = tbl.fcs.rows.NPC_FCS_PlaneFlr000_SV_FLR
local npc0 = tbl.npc.rows["OP_f16c_common_SV"]
check(flr and flr.MagazineCapacity == 20 and flr.ReloadTime == 8.0 and flr.TriggerCount == 10
      and tbl.fcs.rows.NPC_FCS_PlaneFlr000.MagazineCapacity == 10, "searchSetup: NPC_FCS_PlaneFlr000_SV_FLR made (20, 8 s), the stock row untouched")
check(npc0 and tostring(npc0.NpcFCSId0) == "NPC_FCS_PlaneFlr000_SV_FLR" and tostring(tbl.npc.rows["OP_su47_common_SVB"].NpcFCSId0)
      == "NPC_FCS_PlaneFlr000_SV_FLR", "every fighter row's flare slot on it, at every spike level")
check(has(line("weapons: NPC_FCS_PlaneFlr000 -> NPC_FCS_PlaneFlr000_SV_FLR"), "20 in the magazine, 8.0 s to reload"), "its weapons: line")
writeAll(PFILE, "[profile]\r\nversion = 1\r\nruns = 2\r\nlearnt = 2\r\nkills = 40\r\nmissile = 0.70\r\n")
from = #logs + 1
PROF.menu()
search()
check(PROF.flareWant == nil and has(line("learning: the AI's flares stay stock", from), "your saved missile share 0.70")
      and tostring(tbl.npc.rows["OP_f16c_common_SV"].NpcFCSId0) == "NPC_FCS_PlaneFlr000" and not tbl.fcs.rows.NPC_FCS_PlaneFlr000_SV_FLR,
      "not missile-heavy: the stock flare row")
CFG.flares.always = true
PROF.menu()
check(PROF.flareWant and has(line("learning: the AI's flares refilled"), "[flares] always"), "[flares] always: refilled whatever the profile")
CFG.flares.always, CFG.flares.enabled = false, false
writeAll(PFILE, "[profile]\r\nversion = 1\r\nlearnt = 2\r\nmissile = 0.95\r\n")
PROF.menu()
check(PROF.flareWant == nil and has(line("learning: the AI's flares stay stock"), "[flares] off"), "[flares] off: stock")
CFG.flares.enabled = true
PROF.flareWant = nil

---------------------------------------------------------------------------------------------------- the file
print("the file (config/survival_profile.ini)")
os.remove(PFILE)
RUN = {}
D = { round = 9, startRound = 1, state = "fighting", now = 500, up = {}, flown = {}, queue = {}, spare = {} }
from = #logs + 1
PROF.load("level load")
check(PROF.saved and PROF.saved.runs == 0 and PROF.saved.learnt == 0 and has(line("learning: profile at level load", from), "none yet"),
      "no file: a neutral profile (logged)")
-- a run's end: written, read back the same
RUN.habit = strong()
from = #logs + 1
PROF.fold("died")
local text = readAll(PFILE)
local ro = line("learning: run over (died)", from)
check(has(text, "[profile]") and has(text, "version = 1") and has(text, "runs = 1") and has(text, "learnt = 1")
      and has(text, "kills = 20") and has(text, "missile = 0.9500") and has(text, "alt_m = 6125") and not has(text, "[run]"),
      "the run's end: the profile written (runs 1, learnt 1, your 20 kills, missile 0.95, your height)")
check(has(ro, "20 of your kills (20 of fighters: missiles 19, gun 1, of 20 with a weapon seen; close 12, from behind 18, of 20 with an aspect)")
      and has(ro, "200 s flown (high 80%, near the airfield 70% of 200 s it didn't need you, on a tail 30%, usually 6.1 km up), 2 landings")
      and has(ro, "; learnt from; the profile now 1 runs (1 learnt from)") and has(ro, "saved to config\\survival_profile.ini"),
      "its run-over line (" .. tostring(ro) .. ")")
local before = #logs
PROF.fold("died")
check(#logs == before, "a run is learnt from once")
PROF.saved = nil
PROF.load("level load")
local sv = PROF.saved
check(sv and sv.runs == 1 and sv.learnt == 1 and sv.kills == 20 and near(sv.missile, 0.95, 1e-4) and near(sv.gun, 0.6, 1e-4)
      and near(sv.behind, 0.9, 1e-4) and near(sv.tail_time, 1.0, 1e-4) and near(sv.high, 0.8, 1e-4) and near(sv.airfield, 0.7, 1e-4)
      and sv.alt_m == 6125, "the round trip: read back the same")
-- the next run's first round: countered from the saved profile alone (no kill yet)
RUN = {}
PROF.weights(1)
check(D.counter and near(D.counter.strength.missile, 0.75) and near(D.counter.roleW.lancer, 1.9) and D.counter.lancerAlt == 7125,
      "the next run's first round: the saved profile's counters (role mix, the Lancers' height) before a kill")
-- a second run blended in: 30 kills at missile 0.5 (a = min(0.5, 30 / 60) = 0.5), 300 samples none high
RUN.habit = { id = "b2", K = 30, Kf = 30, Kw = 30, Km = 15, Kg = 15, Kgeo = 30, Kc = 0, Kb = 30, S = 300, Sh = 0, Sa = 0,
              SaN = 300, St = 90, landings = 0, alt = { [12] = 300 } }
PROF.fold("restart")
PROF.saved = nil
PROF.load("level load")
sv = PROF.saved
check(sv.runs == 2 and sv.learnt == 2 and sv.kills == 50 and near(sv.missile, 0.725, 1e-4) and near(sv.high, 0.4, 1e-4)
      and near(sv.gun, 0.55, 1e-4) and near(sv.alt_m, 0.5 * 6125 + 0.5 * 3125, 1),
      string.format("a second run blended in (each a = min(run_weight_max 0.5, n / (n + fold_*))): missile %.3f, high %.3f", sv.missile, sv.high))
-- a short run and a head start: counted, not learnt from
RUN.habit = { id = "c3", K = 9, Kf = 5, Kw = 5, Km = 5, Kg = 0, Kgeo = 5, Kc = 0, Kb = 0, S = 40, Sh = 40, Sa = 0, SaN = 40, St = 0,
              landings = 0, alt = {} }
from = #logs + 1
PROF.fold("died")
check(PROF.saved.runs == 3 and PROF.saved.learnt == 2 and PROF.saved.kills == 59 and near(PROF.saved.missile, 0.725, 1e-4)
      and has(line("learning: run over (died)", from), "counted, not learnt from (only 5 of your kills of fighters, min_kills 8)"),
      "9 of your kills, 5 of fighters: counted, not learnt from")
D.startRound = 4
RUN.habit = { id = "d4", K = 12, Kf = 12, Kw = 12, Km = 0, Kg = 12, Kgeo = 12, Kc = 12, Kb = 0, S = 40, Sh = 0, Sa = 0, SaN = 40,
              St = 0, landings = 0, alt = {} }
from = #logs + 1
PROF.fold("died")
check(PROF.saved.runs == 4 and PROF.saved.learnt == 2 and near(PROF.saved.gun, 0.55, 1e-4)
      and has(line("learning: run over (died)", from), "(a head start at round 4)"), "a head start (round 4): counted, not learnt from")
D.startRound = 1
RUN.habit = { id = "e5", K = 0, Kf = 0, Kw = 0, Km = 0, Kg = 0, Kgeo = 0, Kc = 0, Kb = 0, S = 0, Sh = 0, Sa = 0, SaN = 0, St = 0,
              landings = 0, alt = {} }
PROF.fold("left")
check(PROF.saved.runs == 4, "nothing flown: not a run")
-- a round's checkpoint, then the game closes: learnt from at the next start, once
RUN = { habit = { id = "f6", K = 9, Kf = 9, Kw = 9, Km = 9, Kg = 0, Kgeo = 9, Kc = 0, Kb = 9, S = 40, Sh = 0, Sa = 0, SaN = 40,
                  St = 0, landings = 1, alt = { [10] = 40 } } }
D.round = 3
STATS.roundEnd(600)                                  -- (the clear's own call: PROF.checkpoint)
text = readAll(PFILE)
check(has(text, "[run]") and has(text, "id = f6") and has(text, "round = 3") and has(text, "K = 9") and has(text, "Kf = 9")
      and has(text, "S = 40") and has(text, "SaN = 40") and has(text, "alt_m = 2625") and has(text, "runs = 4"),
      "a round's end: the run so far in [run], the profile kept")
local hiBefore = PROF.saved.high
RUN = {}                                             -- (the game closed: no fold; the next start)
from = #logs + 1
PROF.load("the main menu")
local ml = line("learning: profile at the main menu", from)
check(PROF.saved.runs == 5 and PROF.saved.learnt == 3 and PROF.saved.kills == 80
      and has(ml, "the run the game closed in (round 3, 9 of your kills) learnt from, not its tail_time, high, airfield, height (40 samples")
      and has(ml, "min_samples 60) first") and near(PROF.saved.high, hiBefore, 1e-4) and not has(readAll(PFILE), "[run]"),
      "the next start: the unfinished run learnt from first (its 40 samples not: min_samples 60), [run] gone (" .. tostring(ml) .. ")")
writeAll(PFILE, text)                                -- (its [run] again, as if the write had failed)
from = #logs + 1
PROF.load("level load")
check(PROF.saved.runs == 4 and not has(line("learning: profile at level load", from), "closed in"),
      "a [run] already learnt from this session: never twice")
-- formats and broken values: a neutral profile, never an error
writeAll(PFILE, "[profile]\r\nversion = 2\r\nmissile = 0.9\r\n")
from = #logs + 1
PROF.load("level load")
check(PROF.saved.runs == 0 and PROF.saved.missile == nil and has(line("learning: profile at level load", from), "is format 2, not 1"),
      "another format: neutral (logged)")
writeAll(PFILE, "missile = 0.9\r\n")
PROF.load("level load")
check(PROF.saved.missile == nil and has(line("learning: profile at level load"), "has no version line"), "no version line: neutral")
writeAll(PFILE, "[profile]\r\nversion = 1\r\nruns = -3\r\nlearnt = 2.7\r\nmissile = 5\r\ngun = nan\r\nhigh = abc\r\n" ..
                "evil = os.exit()\r\nalt_m = 99999\r\nairfield = 1e999\r\n[run]\r\nid = zz!\r\nK = 50\r\n")
from = #logs + 1
local okL = pcall(PROF.load, "level load")
sv = PROF.saved
check(okL and sv.runs == 0 and sv.learnt == 2 and sv.missile == 1 and sv.gun == nil and sv.high == nil and sv.airfield == nil
      and sv.alt_m == 20000 and has(line("learning: profile at level load", from), "lines skipped") and sv.runs == 0,
      "broken values: clamped or skipped, a [run] without a good id never learnt from")
writeAll(PFILE, "\0\0\255garbage")
check(pcall(PROF.load, "level load") and PROF.saved and PROF.saved.runs == 0, "a binary file: neutral, no error")
-- a folder that can't be written: the profile stays this session's, logged once
local dir = SCRIPT_DIR
SCRIPT_DIR = WORK .. "/nowhere/Scripts/"
RUN = { habit = strong() }
from = #logs + 1
local okF = pcall(PROF.fold, "died")
SCRIPT_DIR = dir
check(okF and PROF.saved.learnt == 1 and has(line("learning: can't write", from), "the profile stays this session's")
      and has(line("learning: run over (died)", from), "NOT saved"), "can't write: logged, the profile kept for the session")
from = #logs + 1
PROF.load("level load")                              -- (the next level load: the file on disk is the binary one above)
check(PROF.saved and PROF.saved.learnt == 1 and PROF.saved.runs == 1
      and has(line("learning: profile at level load", from), "this session's kept (config\\survival_profile.ini couldn't be written"),
      "the next level load after a failed write: this session's profile kept, not the older file")
-- save off: nothing read or written
os.remove(PFILE)
P.save = false
PROF.load("level load")
RUN = { habit = strong() }
D.round = 4
PROF.checkpoint()
from = #logs + 1
PROF.fold("died")
check(PROF.saved == nil and not io.open(PFILE, "r") and has(line("learning: run over (died)", from), "not saved ([profile] save off)"),
      "save off: no profile, no file")
P.save = true
-- LB.finish -> STATS.runEnd -> PROF.fold, with [stats] off too
os.remove(PFILE)
PROF.load("level load")
CFG.stats.enabled = false
RUN = { habit = strong(), kills = {}, credits = 0, earned = 0, spent = 0 }
D = { round = 7, startRound = 1, state = "fighting", now = 700, up = {}, flown = {}, queue = {}, spare = {} }
pcall(LB.finish, "died")
check(has(line("learning: run over (died)"), "learnt from") and has(readAll(PFILE), "learnt = 1"),
      "LB.finish: the run learnt from and saved (the measurements off)")
PROF.saved.runs = 99                                 -- (a write landed: the next load reads the file again)
PROF.load("level load")
check(PROF.saved.runs == 1, "a write landed again: the next load reads the file")
CFG.stats.enabled = true
-- a co-op host's new run (a joiner told "rs"): this run learnt from, the next one empty
RUN = { habit = strong(), kills = {} }
RUN.habit.id = "g7"
from = #logs + 1
STATS.hostReset(800, false)
check(has(line("learning: run over (the host started over)", from), "learnt from") and RUN.habit == nil and PROF.saved.runs == 2,
      "the host started over: learnt from, the next run's counts empty")
RUN.habit = strong(); RUN.habit.id = "h8"
STATS.hostReset(801, true)
check(RUN.habit ~= nil and RUN.habit.id == "h8", "a resync: the run goes on")
-- min_samples: a run learnt from with few samples keeps its time shares and height out of the profile (they'd stand as
-- the profile, weighed as prior_samples 150, for runs to come: the U8 review); a later run's are its own then
os.remove(PFILE)
PROF.load("level load")
D.startRound = 1
RUN = { habit = { id = "m9", K = 10, Kf = 10, Kw = 10, Km = 10, Kg = 0, Kgeo = 10, Kc = 0, Kb = 10, S = 10, Sh = 10, Sa = 10,
                  SaN = 10, St = 10, landings = 0, alt = { [30] = 10 } } }
from = #logs + 1
PROF.fold("died")
sv = PROF.saved
local mr = line("learning: run over (died)", from)
check(sv.learnt == 1 and near(sv.missile, 1) and near(sv.behind, 1) and sv.high == nil and sv.airfield == nil and sv.tail_time == nil
      and sv.alt_m == nil and has(mr, "; learnt from; not its tail_time, high, airfield, height (10 samples, 10 of them for the airfield; min_samples 60)"),
      "10 samples (under min_samples 60): its kill shares learnt, not its time shares or height (" .. tostring(mr) .. ")")
RUN = { habit = { id = "n10", K = 10, Kf = 10, Kw = 10, Km = 5, Kg = 5, Kgeo = 10, Kc = 0, Kb = 10, S = 100, Sh = 50, Sa = 0,
                  SaN = 80, St = 0, landings = 0, alt = { [20] = 100 } } }
PROF.fold("died")
sv = PROF.saved
check(sv.learnt == 2 and near(sv.missile, 0.875) and near(sv.high, 0.5) and near(sv.airfield, 0) and sv.alt_m == 5125,
      string.format("the next run's 100 samples: its time shares and height the profile's own (high %s), its kill shares blended (missile %s)",
      tostring(sv.high), tostring(sv.missile)))
D.counter = nil

-- each kill share on its own count (code review of 2026-10-29: all three were weighed by Kf, your kills of fighters):
-- 20 kills of fighters, 3 with a weapon seen (missiles), 2 with an aspect (both close, neither from behind)
local hk = { K = 20, Kf = 20, Kw = 3, Km = 3, Kg = 0, Kgeo = 2, Kc = 2, Kb = 0, S = 0, Sh = 0, Sa = 0, SaN = 0, St = 0, alt = {} }
local ck = PROF.current(hk, nil)
check(ck.missile == nil and ck.gun == nil and ck.behind == nil,
      "3 kills with a weapon seen, 2 with an aspect (under live_kills 5): no kill share in force (on Kf 20: missile 1.0, gun 1.0)")
hk.Kw, hk.Km, hk.Kg = 10, 8, 2
ck = PROF.current(hk, nil)
check(near(ck.missile, 0.8) and near(ck.gun, 0.2) and ck.behind == nil,
      "10 with a weapon seen: missile 0.80, the gun's weapon half 0.20 in force (its range half, 1.0 on 2 kills, left out)")
local s5, n5 = PROF.runShares(hk)
check(near(s5.gun, 1.0) and n5.gun == 2 and n5.missile == 10 and n5.behind == 2,
      "runShares: the gun's bigger half (1.0 on its 2 kills), each share's own count")
os.remove(PFILE)
PROF.load("level load")
PROF.saved.learnt, PROF.saved.missile, PROF.saved.gun, PROF.saved.behind = 1, 0.5, 0.5, 0.5
D.startRound = 1
RUN = { habit = { id = "k5", K = 20, Kf = 20, Kw = 3, Km = 3, Kg = 0, Kgeo = 20, Kc = 0, Kb = 20, S = 0, Sh = 0, Sa = 0,
                  SaN = 0, St = 0, landings = 0, alt = {} } }
PROF.fold("died")
sv = PROF.saved
check(near(sv.missile, 0.5 + 0.5 * 3 / 33) and near(sv.behind, 0.5 + 0.5 * 20 / 50) and near(sv.gun, 0.5 * 30 / 50),
      string.format("folded, each share by its own count: missile a = 3 / 33 (%.4f; by Kf 0.7), behind and the gun's tie 20 / 50 (%.4f, %.4f)",
      sv.missile, sv.behind, sv.gun))

-- a co-op joiner's head start (code review of 2026-10-29): its D.startRound is its own level load's (1), but one that
-- links at the host's round 20 began its run there (PROF.roundStart, from STATS.roundStart: clientRounds' call when the
-- host's round number changes), so it's counted, not learnt from; one in the room from round 1 is learnt from
COOP.open, COOP.role = true, "join"
os.remove(PFILE)
PROF.load("level load")
D = { round = 0, startRound = 1, state = "wait", now = 900, up = {}, flown = {}, queue = {}, spare = {} }
RUN = { habit = strong() }
RUN.habit.id = "j20"
D.round = 20; STATS.roundStart(900)
D.round = 21; STATS.roundStart(960)
STATS.roundEnd(1000)                                 -- (its checkpoint)
check(RUN.habit.began == 20 and has(readAll(PFILE), "from = 20"), "a joiner linked at the host's round 20: its run began there ([run] from = 20)")
from = #logs + 1
PROF.fold("died")
check(has(line("learning: run over (died)", from), "counted, not learnt from (a head start at round 20)") and PROF.saved.learnt == 0,
      "the joiner's run from round 20: counted, not learnt from (its D.startRound 1)")
RUN = { habit = strong() }
RUN.habit.id = "j1"
D.round = 1; STATS.roundStart(1100)
from = #logs + 1
PROF.fold("died")
check(has(line("learning: run over (died)", from), "; learnt from;") and PROF.saved.learnt == 1, "a joiner from the host's round 1: learnt from")
COOP.open, COOP.role = false, nil

-- the file never lost (code review of 2026-10-29): written whole to a .tmp (write and close checked), the old one
-- aside as .bak until the new one's in; a .tmp or .bak a write the game didn't finish left read and moved back in; a
-- file that isn't a profile kept as .old; one that can't be read, or a failed load, never written over
local function exists(p) local f = io.open(p, "r"); if f then f:close(); return true end return false end
for _, x in ipairs({ "", ".tmp", ".bak", ".old" }) do os.remove(PFILE .. x) end
D = { round = 3, startRound = 1, state = "fighting", now = 1200, up = {}, flown = {}, queue = {}, spare = {} }
PROF.load("level load")
RUN = { habit = strong() }
RUN.habit.id = "a1"
PROF.fold("died")
RUN = { habit = strong() }
RUN.habit.id = "a2"
STATS.roundEnd(1210)
local good = readAll(PFILE)
check(has(good, "id = a2") and has(good, "; end of the profile") and not exists(PFILE .. ".bak") and not exists(PFILE .. ".tmp"),
      "a write over the file: whole (its end line), no .tmp or .bak left")
-- a full disk: the .tmp's write (or its close) fails
local rawOpen, rawRename = io.open, os.rename
local function fullDisk(at)
    io.open = function(p, m)
        local f, e, c = rawOpen(p, m)
        if f and m == "w" and tostring(p):find("%.tmp$") then
            local w = {}
            function w.write(_, s)
                f:write(s:sub(1, 40))
                if at == "write" then return nil, "No space left on device", 28 end
                return w
            end
            function w.close() f:close(); if at == "close" then return nil, "No space left on device", 28 end return true end
            return w
        end
        return f, e, c
    end
end
fullDisk("write")
RUN = { habit = strong() }
RUN.habit.id = "a3"
D.round = 4
from = #logs + 1
STATS.roundEnd(1220)
PROF.fold("died")
io.open = rawOpen
check(readAll(PFILE) == good and not exists(PFILE .. ".tmp") and not exists(PFILE .. ".bak")
      and has(line("learning: config\\survival_profile.ini not written (No space left on device)", from), "the old one kept; the profile stays this session's")
      and has(line("learning: run over (died)", from), ", NOT saved (config\\survival_profile.ini not written (No space left on device)"),
      "a full disk at the .tmp's write: the old file as it was (it used to be replaced by a 40-byte fragment), logged")
fullDisk("close")
RUN = { habit = strong() }
RUN.habit.id = "a4"
D.round = 5
STATS.roundEnd(1230)
io.open = rawOpen
check(readAll(PFILE) == good and not exists(PFILE .. ".tmp"), "the .tmp's close failing: the old file as it was")
-- the new one can't be moved in: the old one put back
os.rename = function(a, b) if tostring(a):find("%.tmp$") then return nil, "Permission denied", 13 end return rawRename(a, b) end
RUN = { habit = strong() }
RUN.habit.id = "a5"
D.round = 6
from = #logs + 1
STATS.roundEnd(1240)
os.rename = rawRename
check(readAll(PFILE) == good and not exists(PFILE .. ".bak") and not exists(PFILE .. ".tmp")
      and has(line("learning: config\\survival_profile.ini not moved in (Permission denied)", from), "the old one put back"),
      "the new one not moved in: the old one put back, nothing left over")
RUN = { habit = strong() }                           -- (a write that lands: wrote.failed off again)
RUN.habit.id = "a6"
D.round = 7
STATS.roundEnd(1250)
local A = readAll(PFILE)
local runsA = tonumber(A:match("\nruns = (%d+)"))                -- (the game writes text mode: \r\n here)
check(has(A, "id = a6") and runsA, "a write lands again")
-- the game closed between the old one's move aside and the new one's move in: no file, its .bak, a .tmp cut short
rawRename(PFILE, PFILE .. ".bak")
writeAll(PFILE .. ".tmp", A:sub(1, 120))
from = #logs + 1
PROF.load("level load")
local bl = line("learning: profile at level load", from)
check(PROF.saved and PROF.saved.runs == runsA and readAll(PFILE) == A and not exists(PFILE .. ".bak")
      and has(bl, "from config\\survival_profile.ini.bak (a write the game didn't finish left it; moved back in)"),
      "no file, its .bak: the .bak read and moved back in (a .tmp without its end line passed over) (" .. tostring(bl) .. ")")
-- no file, a .tmp written whole and the older .bak: the .tmp
rawRename(PFILE, PFILE .. ".bak")
local B = A:gsub("\nruns = %d+", "\nruns = 77", 1)
writeAll(PFILE .. ".tmp", B)
from = #logs + 1
PROF.load("level load")
check(PROF.saved and PROF.saved.runs == 77 and readAll(PFILE) == B and not exists(PFILE .. ".tmp")
      and has(line("learning: profile at level load", from), "from config\\survival_profile.ini.tmp ("),
      "no file, a whole .tmp and the .bak: the .tmp (the newer) moved back in")
RUN = { habit = strong() }
RUN.habit.id = "a7"
D.round = 8
STATS.roundEnd(1260)
check(has(readAll(PFILE), "id = a7") and not exists(PFILE .. ".bak"), "the next write: the .bak left over removed")
-- a write that went in but couldn't remove its .bak (another program held it), then the file deleted to start over:
-- the .bak (older) never moved back in without a .tmp beside it (F3 round 2: the review's p6 probe), the next write
-- removes it
do
    local keepRemove = os.remove
    os.remove = function(p) if tostring(p):find("%.bak$") then return nil, "Permission denied", 13 end return keepRemove(p) end
    RUN = { habit = strong() }
    RUN.habit.id = "c1"
    from = #logs + 1
    STATS.roundEnd(1262)
    os.remove = keepRemove
    check(has(readAll(PFILE), "id = c1") and has(readAll(PFILE .. ".bak"), "id = a7")
          and has(line("learning: config\\survival_profile.ini.bak (the profile before this one) couldn't be removed", from),
                  "(Permission denied): left beside the new one, never read back without a .tmp; the next write removes it"),
          "a .bak a write that went in couldn't remove: the new file in, the .bak left, logged")
    os.remove(PFILE)                                 -- (the player starts over)
    from = #logs + 1
    PROF.load("level load")
    check(PROF.saved and PROF.saved.runs == 0 and not exists(PFILE) and exists(PFILE .. ".bak")
          and has(line("learning: profile at level load", from), "none yet (config\\survival_profile.ini is made at your " ..
              "first run's end; survival_profile.ini.bak passed over: an older one a write that went in left, removed at " ..
              "the next write)"),
          "the file deleted, its .bak alone: passed over (it used to come back as a write the game didn't finish)")
    RUN = { habit = strong() }
    RUN.habit.id = "c2"
    STATS.roundEnd(1264)
    local c2 = readAll(PFILE)
    check(has(c2, "id = c2") and has(c2, "\nruns = 0") and not exists(PFILE .. ".bak"),
          "the next write: the new profile from none, the .bak removed")
end
-- a file that isn't a profile: neutral, kept as .old by the first write, said so
writeAll(PFILE, "\0\0garbage")
from = #logs + 1
PROF.load("level load")
check(PROF.saved and PROF.saved.runs == 0 and has(line("learning: profile at level load", from),
      "has no version line: starting from a neutral profile (the file's kept as survival_profile.ini.old once a new one is written)"),
      "a file that isn't a profile: neutral, the .old said at the load")
RUN = { habit = strong() }
RUN.habit.id = "a8"
D.round = 9
STATS.roundEnd(1270)
check(readAll(PFILE .. ".old") == "\0\0garbage" and has(readAll(PFILE), "id = a8")
      and has(line("learning: config\\survival_profile.ini (has no version line at its load) kept as survival_profile.ini.old", from),
      "a new profile written"), "the first round's end: the old file kept as .old, a new profile written, logged")
RUN = { habit = strong() }
RUN.habit.id = "a9"
D.round = 10
STATS.roundEnd(1280)
check(readAll(PFILE .. ".old") == "\0\0garbage" and has(readAll(PFILE), "id = a9") and not exists(PFILE .. ".bak"),
      "the next write: the .old stays")
PROF.fold("died")                                    -- (a9 learnt from: no [run] left in the file for the loads below)
-- a file that's there but can't be read now (another program holds it): no profile, nothing written over it
local held = readAll(PFILE)
io.open = function(p, m)
    if m == "r" and tostring(p):find("survival_profile%.ini$") then return nil, "survival_profile.ini: Permission denied", 13 end
    return rawOpen(p, m)
end
from = #logs + 1
PROF.load("level load")
RUN = { habit = strong() }
RUN.habit.id = "b1"
D.round = 11
STATS.roundEnd(1290)
PROF.fold("died")
io.open = rawOpen
check(PROF.saved == nil and readAll(PFILE) == held and has(line("learning: profile at level load", from), "couldn't be read (survival_profile.ini: Permission denied)")
      and line("learning: config\\survival_profile.ini not written: no profile was loaded", from) ~= nil
      and has(line("learning: run over (died)", from), "not learnt from or saved (no profile was loaded"),
      "a file that can't be read now: no profile, the run not written over it (it used to be replaced by a neutral one)")
-- a level load error (sv_main.lua's handler leaves PROF.saved nil): nothing written over the file
PROF.load("level load")
PROF.saved = nil
RUN = { habit = strong() }
RUN.habit.id = "b2"
D.round = 12
STATS.roundEnd(1300)
check(readAll(PFILE) == held, "after a level load error: nothing written over the file")
PROF.load("level load")
check(PROF.saved and PROF.saved.runs == tonumber(held:match("\nruns = (%d+)")), "read again at the next load")
for _, x in ipairs({ ".tmp", ".bak", ".old" }) do os.remove(PFILE .. x) end
D.counter = nil

---------------------------------------------------------------------------------------------------- hooks
print("the hooks by their place in the source")
local sr = body("sv_rounds.lua", "\nlocal function startRound%(%)")
local iW, iS, iJ = sr:find("pcall(PROF.weights, D.round)", 1, true), sr:find("local st = CFG.strike", 1, true),
    sr:find('pcall(PROF.chance, "jammer", jcChance)', 1, true)
check(iW and iS and iJ and iW < iS and has(sr, 'pcall(PROF.chance, "strike", stChance)') and has(sr, "math.random() < stChance")
      and has(sr, "math.random() < jcChance"), "startRound: PROF.weights before its picks, the strike and jammer chances through PROF.chance")
local pt = body("sv_main.lua", "\nlocal function probeTick%(tick%)")
local iM, iB = pt:find("pcall(PROF.menu)", 1, true), pt:find("pcall(setsSetup)", 1, true)
check(iM and iB and iM < iB and has(pt, "pcall(PROF.levelLoad)"), "probeTick: PROF.menu before the NPC rows, PROF.levelLoad at level load")
local st = readAll(MOD .. "/Scripts/sv_stats.lua")
check(has(st, "pcall(PROF.kill, p, g, by)") and has(st, "pcall(PROF.sample, now, you)") and has(st, "pcall(PROF.checkpoint)")
      and has(st, "pcall(PROF.fold, how)") and has(st, 'pcall(PROF.newRun, "the host started over")'), "sv_stats: STATS' hooks call PROF")
check(has(body("sv_ai.lua", "\nfunction enemyTier%("), "PROF.rankAdd, i") and has(body("sv_ai.lua", "\nfunction enemyManeuvers%("),
      "PROF.postStall, p.tier"), "sv_ai: enemyTier's rank, enemyManeuvers' post-stall")
check(has(body("sv_spawn.lua", "\nfunction ROLE.pickRound%("), "PROF.roleW") and has(readAll(MOD .. "/Scripts/sv_spawn.lua"), "pcall(PROF.lancerAlt)"),
      "sv_spawn: the role mix and the Lancers' height")
check(has(readAll(MOD .. "/Scripts/sv_rows.lua"), 'id:find("^NPC_FCS_PlaneFlr") and not (mind or glitch or valka)'),
      "sv_rows: the flare slot (not the specials' own)")
check(has(readAll(MOD .. "/Scripts/sv_coop.lua"), "profile = true, flares = true"), "sv_coop: [profile] and [flares] PERSONAL (never a host's)")
check(has(body("sv_director.lua", "\nfunction DIR.roundStart%("), "D.counter.tail"), "sv_director: DIR.roundStart reads D.counter.tail")
local pb = st:sub(st:find("P6: the learning layer", 1, true) or #st)
check(not pb:find("math%.random%(") and not pb:find("FindAllOf") and not pb:find("nameOf%("),
      "PROF: no math.random draws (the rounds' odds untouched), no FindAllOf, no nameOf")

logFile:close()
print(fails == 0 and "profile test: all passed" or ("profile test: " .. fails .. " FAILED"))
os.exit(fails == 0 and 0 or 1)
