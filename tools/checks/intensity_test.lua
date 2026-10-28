-- intensity_test.lua <mod dir> <work dir> (run by tools/checks/intensity_test.sh): the behaviour roadmap's P4, the
-- intensity director (tools/re/BEHAVIOUR_DIRECTOR.md unit 7), on the real sv_core, sv_config, sv_rows, sv_ai, sv_hud,
-- sv_spawn, sv_rounds, sv_tactical, sv_stats, sv_tells, sv_director and sv_coop (M exposed), the game stubbed (HIT's
-- health and missiles as tables, planes as objects with a position and a heading):
--   survival.ini's [intensity] sections; every lever's switch on as shipped;
--   the scores: intensity's parts (damage in window_s, missiles homing on you within msl_km, enemies within near_km,
--     health lost) and their sums, the smoothing, the window; comfort's (time on a tail, from each plane's p.youAt,
--     kills a minute, healthy); a repair or a new aircraft never counted as damage;
--   the hold: intensity above high for after_s, the next wave held hold.secs once it's due (the real roundsTick's gate
--     open; hot long before that: no hold until then, the review of unit 7's case) and let go after, never made longer,
--     gap_s after the last, per_wave a wave, the rest of a later wave at its next flight (not wave 1's); the spawn gap's
--     add while hot; the top cover's own hold (its dive / max_s waiting, P2's heldTick), a wave due during or just after
--     it held all the same, the top cover not held twice in a row; nothing to hold: none; a boss round, the lever off;
--   hold.tactics: the squad director's cover refused on a player above high (and given with it off);
--   a push: comfortable for calm_s: a duelist flight turned onto you after "check your six", counted and tagged; a held
--     top cover dives instead (not while its hold is on); per_round, cooldown_s, from_round; the director off, nothing in
--     range (tried again 5 s on, logged once); co-op: the next calm player when the first can't have one;
--   the level: the room above high for down_after_s: one spike level down (levelFor, enemyTier's rank_min, a live
--     plane's provoke written again, the game's own back at level 0, the next round's aircraft_add), gap_s, max_drop,
--     back up after up_after_s below up_below, never under 0 (round 5: nothing), the lever off: the spikes' own; the
--     attack throttle's preset a letter gentler (DIR.pressure, pressureNow; not under pressure_min, not in an Anomaly);
--   co-op: a joiner's "in" once a second, its copies on the host's level ("rnd", bad values ignored); the host's "in"
--     guards (a bad slot or number, its own slot, out of range clamped, rate, stale after 3 s), the room's hold named
--     after the joiner who caused it, the host's level in "rnd", a joiner's push (the six tell by "tl", a hunt);
--   the hooks by their place in the source.
local MOD, WORK = arg[1], arg[2]
local fails = 0
local function check(ok, what) if ok then print("  ok   " .. what) else print("  FAIL " .. what); fails = fails + 1 end end
local function readAll(p) local f = assert(io.open(p, "rb")); local s = f:read("a"); f:close(); return s end
local function writeAll(p, s) local f = assert(io.open(p, "wb")); f:write(s); f:close() end
local function has(s, part) return s ~= nil and s:find(part, 1, true) ~= nil end
local function near(a, b, eps) return type(a) == "number" and math.abs(a - b) <= (eps or 0.01) end
do                                    -- (the runtime's paths are Windows ones: SCRIPT_DIR .. "..\\config\\")
    local rawOpen = io.open
    io.open = function(p, m) return rawOpen((tostring(p):gsub("\\", "/")), m) end
end
local defaultIni = readAll(MOD .. "/config/survival.default.ini")
writeAll(WORK .. "/config/survival.default.ini", defaultIni)
writeAll(WORK .. "/config/survival.ini", defaultIni ..
    "\r\n[intensity]\r\nhigh = 75\r\nskip_specials = anomaly, ladon\r\n[intensity.score]\r\nnear_full = 5\r\n" ..
    "[intensity.hold]\r\nsecs = 16, 18\r\n[intensity.level]\r\nmax_drop = 2\r\n[intensity.push]\r\nrange_km = 9.5\r\n")

local clock = 1000                               -- (co-op's levelReady and rate limits)
os.clock = function() return clock end           -- luacheck: ignore

-- the game's world, stubbed
VERSION = "0.71.5-intensity.test"
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
local events, eventR = {}, 1
function SV_Event(name) events[#events + 1] = name; return eventR end
local alive = {}
function SV_UnitAlive(u) return alive[u] or 0 end
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
local sent, inbox = {}, {}
function SV_CoopSend(msg, rel, to) sent[#sent + 1] = tostring(to) .. ">" .. msg; return 1 end
function SV_CoopRecv() return table.remove(inbox, 1) or "" end
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
part("sv_rows.lua"); part("sv_ai.lua"); part("sv_hud.lua"); part("sv_spawn.lua"); part("sv_rounds.lua")
part("sv_tactical.lua"); part("sv_stats.lua"); part("sv_tells.lua"); part("sv_director.lua")
part("sv_coop.lua", nil, { { "\nlocal M = {", "\nM = {" } })
local M = _G.M
function playerOnAirfield() return grounded end      -- (sv_rounds.lua's own reads the pawn)
LB.stat, LB.special = function() end, function() end
presetName = function() return "standard", 3 end
local FLAGS = {}
svFlags = function() return FLAGS end
ROLE.live = { duelist = true, lancer = true, wolf = true, skirm = true }
ANOM.fx = ANOM.fx or {}                              -- (the real roundsTick's specialTick: parts not loaded here)
AMPH.runTick = AMPH.runTick or function() end
math.randomseed(7)

local function line(prefix, from)
    for i = #logs, from or 1, -1 do if logs[i]:sub(1, #prefix) == prefix then return logs[i] end end
    return nil
end
local function since(from, pat) local n = 0; for i = from, #logs do if logs[i]:find(pat) then n = n + 1 end end; return n end
local function evs(pat) local t = {}; for _, e in ipairs(events) do if e:find(pat) then t[#t + 1] = e end end; return table.concat(t, ",") end
local function sentOf(pat) local t = {}; for _, s in ipairs(sent) do if s:find(pat) then t[#t + 1] = s end end; return table.concat(t, ";") end
local function deep(t) if type(t) ~= "table" then return t end; local c = {}; for k, v in pairs(t) do c[k] = deep(v) end; return c end

-- you (the pawn; MaxHealth 100, HIT.h in HP x 10) and the planes (cm; KM(x, y) a point x km east, y km "south", 3 km up)
local you, youFwd = { X = 0, Y = 0, Z = 300000 }, { X = 1, Y = 0, Z = 0 }
local pawn = { full = "BP_PlayerPlane_PP1000_f16c_C_1", addr = 9, MaxHealth = 100, HealthInternal = 800 }
local maxReads = 0
setmetatable(pawn, { __index = function(_, k) if k == "MaxHealth" then maxReads = maxReads + 1; return 100 end end })
pawn.MaxHealth = nil
function pawn:K2_GetActorLocation() return { X = you.X, Y = you.Y, Z = you.Z } end
function pawn:GetActorForwardVector() return { X = youFwd.X, Y = youFwd.Y, Z = youFwd.Z } end
survivalPC = { Pawn = pawn }
local function KM(x, y, z) return { X = x * 100000, Y = y * 100000, Z = (z or 3) * 100000 } end
local function DIRV(x, y, z) local l = math.sqrt(x * x + y * y + (z or 0) ^ 2); return { X = x / l, Y = y / l, Z = (z or 0) / l } end
local nextAddr = 100
local function mkObj(name, at, fwd)
    nextAddr = nextAddr + 1
    local o = { full = name, addr = nextAddr, at = at, fwd = fwd, HealthInternal = 1000 }
    function o:K2_GetActorLocation() return { X = self.at.X, Y = self.at.Y, Z = self.at.Z } end
    function o:GetActorForwardVector() return { X = self.fwd.X, Y = self.fwd.Y, Z = self.fwd.Z } end
    o.AIStateComponent = { BlackboardComponent = {
        SetValueAsObject = function(_, k, v) o.tgt, o.tgtKey = v, tostring(k) end,
        GetValueAsObject = function() return o.tgt end } }
    return o
end
local function plane(unit, k, at, fwd)
    local name = string.format("BP_OP1022_f16c_C_%d", nextAddr + 1)
    local o = mkObj(name, at, fwd)
    local p = { obj = o, name = name, unit = unit, k = k, at = { X = at.X, Y = at.Y, Z = at.Z }, fwd = fwd, born = 0,
                tier = CFG.tiers.list[3] }
    p.dist = km(p.at, you)                       -- (the sweep's, from where you are)
    planes[#planes + 1] = p
    alive[unit] = (alive[unit] or 0) + 1
    return p
end
local function moveP(p, at)                      -- (the plane and the sweep's last sample of it)
    p.obj.at, p.at = at, { X = at.X, Y = at.Y, Z = at.Z }
    p.dist = km(p.at, you)
end
local function missile(d, target, live)          -- an enemy missile d m from you homing on target (nil: unreadable)
    nextAddr = nextAddr + 1
    return { obj = { full = "BP_wp_msl_C", addr = nextAddr, TargetToHome = target }, name = "BP_wp_msl", d = d, seen = 0,
             live = live ~= false }
end
local function fresh(round, state)
    planes, alive, events, spawns, sent, callouts = {}, {}, {}, {}, {}, {}
    D = { round = round, state = state or "fighting", now = 99, up = {}, flown = {}, queue = {}, spare = {}, events = {},
          orders = {} }
    you, youFwd, grounded = { X = 0, Y = 0, Z = 300000 }, { X = 1, Y = 0, Z = 0 }, false
    COOP.open, COOP.role, COOP.slot = false, nil, nil
    D.pressure = "B"                                               -- (the attack throttle the round fired)
    HIT = { msl = {}, h = 800, pawn = "9" }
    RUN.kills.you = 0
    CFG.intensity = deep(CFG_DEFAULTS.intensity)
    DIR.roundStart(99)
end
-- the director (P4 first) and the tells' actions every 250 ms from t0 to t1; rounds: the real roundsTick too
local function tickTo(t0, t1, rounds)
    local n = math.floor((t1 - t0) / 0.25 + 0.5)
    for i = 0, n do
        local t = t0 + i * 0.25
        D.now = t
        for _, m in ipairs(HIT.msl) do if m.live then m.seen = t end end
        if rounds then roundsTick(t) end
        if not D then return end
        DIR.tick(t, false)
        TELL.tick(t)
    end
end
local function me() return D.int and D.int.me end
local function itick(t) D.now = t; DIR.intensityTick(t, false) end   -- (one sample's call, on the round clock)
local A, Q, L = "ERA_Unit_01_Dep_Air0", "ERA_Unit_02_Dep_Air1", "ERA_Unit_03_Dep_Air0"   -- a duelist, a duelist (pool 05), a Lancer (07)
local U1, U2, U3 = "ERA_Unit_04_Dep_Air0", "ERA_Unit_04_Dep_Air1", "ERA_Unit_06_Dep_Air0"
-- heavy pressure: four enemies 3.5-4.8 km off, nose on you (near, but no fight within top cover's 3 km and no tail for
-- the squad director), two missiles homing on you; with a drop of 400 (40 HP of 100) after the first sample:
-- damage 40 + missiles 25 + near 20 + health 15 x 0.6 = 94
local function pressure(unit)
    for k, d in ipairs({ 3.5, 4.0, 4.5, 4.8 }) do plane(unit or U1, k - 1, KM(0, d), DIRV(0, -1)) end
    HIT.msl = { missile(2000, pawn), missile(1500, pawn) }
end

---------------------------------------------------------------------------------------------------- survival.ini
print("survival.ini's [intensity]")
local DEF = CFG_DEFAULTS.intensity
check(cfgLine and not has(cfgLine, "not used"), "config: every line used (" .. tostring(cfgLine) .. ")")
check(CFG.intensity.high == 75 and #CFG.intensity.skip_specials == 2 and CFG.intensity.skip_specials[2] == "ladon"
      and CFG.intensity.score.near_full == 5 and CFG.intensity.hold.secs[1] == 16 and CFG.intensity.hold.secs[2] == 18
      and CFG.intensity.level.max_drop == 2 and CFG.intensity.push.range_km == 9.5,
      "[intensity] high / skip_specials, [intensity.score] near_full, [.hold] secs, [.level] max_drop, [.push] range_km read")
check(DEF.enabled and DEF.push.enabled and DEF.hold.enabled and DEF.level.enabled and DEF.hold.tactics
      and DEF.high == 80 and DEF.low == 35 and DEF.calm_s == 20 and DEF.hold.secs[1] == 15 and DEF.hold.secs[2] == 20,
      "every lever has an enabled switch, on as shipped; the thesis' numbers (above 80, 20 s, 15-20 s)")
local w = DEF.score
check(w.damage + w.missiles + w.near + w.health == 100 and DEF.comfort.tail + DEF.comfort.kills + DEF.comfort.healthy == 100,
      "intensity's and comfort's weights add up to 100")

---------------------------------------------------------------------------------------------------- the scores
print("the scores")
fresh(8)
itick(100)
check(me() and near(me().raw, 3) and near(me().i, 3) and near(me().c, 25) and near(me().hp, 80),
      "nothing on you, health 80 %: intensity 3 (health lost 20 % x 15), comfort 25 (healthy, above 70 %)")
fresh(8)
plane(A, 0, KM(0, 2), DIRV(0, -1)); plane(A, 1, KM(0, 4.5), DIRV(0, -1)); plane(Q, 0, KM(0, 6), DIRV(0, -1))
itick(100)
check(me().near == 2 and near(me().raw, 3 + 10), "2 enemies within near_km 5 (not the one 6 km off): + near 20 x 2/4")
fresh(8)
local other = { full = "BP_Ally", addr = 55 }
HIT.msl = { missile(3000, pawn), missile(2000, other), missile(800, nil), missile(1500, nil), missile(5000, pawn),
            missile(1000, pawn, false) }
HIT.msl[6].seen = 97
for _, m in ipairs(HIT.msl) do if m.live then m.seen = 100 end end
itick(100)
check(me().msl == 2 and near(me().raw, 3 + 25),
      "missiles: one homing on you 3 km off and one 800 m off whose target can't be read (not one on an ally, one unreadable 1.5 km off, one 5 km off, one gone 3 s): + 25")
fresh(8)
itick(100)
HIT.h = 600; itick(100.25)
HIT.h = 400; itick(101)
check(near(me().dmg, 40) and near(me().hp, 40) and near(me().raw, 40 + 9) and near(me().i, 3 + (49 - 3) * 0.35),
      "40 HP taken (40 % of your health, two drops between samples): damage 40 (full at dmg_full 0.4) + health 9; smoothed 3 -> 19.1")
for t = 102, 130 do itick(t) end
check(near(me().dmg, 40), "... the damage counts for window_s (30 s)")
itick(131)
check(near(me().dmg, 0) and near(me().raw, 9), "... and not after")
HIT.h = 800; itick(132)
check(near(me().dmg, 0), "a repair (your health back up) is no damage")
itick(133)
HIT.pawn, HIT.h = "10", 300; itick(134)
check(near(me().dmg, 0), "a new aircraft (HIT.pawn) with less health: no damage")
fresh(8)
CFG.intensity.smooth_x = 1
itick(100)
HIT.h = 400; HIT.msl = { missile(2000, pawn), missile(1500, pawn) }
for _, m in ipairs(HIT.msl) do m.seen = 101 end
itick(101)
check(near(me().i, me().raw) and near(me().i, 40 + 25 + 9), "smooth_x 1: no smoothing")
-- comfort
fresh(8)
local t1 = plane(A, 0, KM(1, 0), DIRV(1, 0))                       -- 1 km ahead of you, flying away: on its tail
for t = 100, 114 do itick(t) end
check(me().tailS == 15 and near(me().c, 40 + 25), "15 s of 30 on its tail (tail_full 0.5): comfort 40 + healthy 25")
RUN.kills.you = 2
itick(115)
check(near(me().kpm, 2) and near(me().c, 100), "two kills in the last minute (2 a minute, kpm_full 2): + 35, comfort 100")
t1.down = true
for t = 116, 175 do itick(t) end
check(near(me().kpm, 0) and near(me().c, 25), "a minute on, no tail, no kills: comfort 25")
fresh(8)
local t2 = plane(A, 0, KM(1, 0), DIRV(1, 0))
you = KM(5, 0)                                                     -- (you now ahead of it: not on its tail now)
t2.dist = 4
itick(100)
check(me().tailS == 0, "you 4 km ahead of it now: not on its tail")
t2.youAt = KM(0, 0)                                               -- (where you were at the sweep's sample of it)
itick(101)
check(me().tailS == 1, "... but behind it at the sweep's sample of it (p.youAt): on its tail")
fresh(8)
maxReads = 0
itick(100)
maxReads = 0
for t = 100.25, 109.75, 0.25 do itick(t) end
check(maxReads == 1, "your MaxHealth read every 5 s, no more (" .. maxReads .. " reads in the next 10 s)")

---------------------------------------------------------------------------------------------------- the hold
print("the hold: the next wave once it's due, the top cover")
local function holdScene(round, state)
    fresh(round or 10, state or "wave")
    D.waves, D.wave, D.waveAt, D.at = { { U1 }, { U2 }, { U3 } }, 1, 90, 0
    pressure(U1)
    D.up = { [U1] = true }
    alive[U1] = 6                                                  -- (6 left > waves.next_at 4: the gate shut by kills)
    CFG.intensity.window_s = 120                                   -- (the damage counts through the test: still hot)
    itick(99)                                   -- (your health 800 before the drop)
    HIT.h = 400
end
-- the review of unit 7's case: hot long before the gate opens; the hold must come when the wave's due, not before
holdScene()
local from = #logs + 1
tickTo(100, 130, true)
check(D.int.hold == nil and D.wave == 1 and (D.int.pl[0].hotFor or 0) >= 20 and since(from, "^intensity: round 10: held") == 0
      and since(from, "^intensity: hold") == 0,
      "above 80 for 20 s+ while wave 2's gate is shut (6 left > waves.next_at 4): no hold, nothing due to keep back")
alive[U1] = 2                                                      -- (the gate opens: 2 left)
tickTo(130.25, 131.5, true)
local h = D.int.hold
local holdLine = line("intensity: round 10: held", from)
check(h ~= nil and D.wave == 1 and D.state == "wave" and h.at == 131 and h.untilT - h.at >= 15 and h.untilT - h.at <= 20
      and has(holdLine, "(you at intensity") and has(holdLine, "): wave 2 wait"),
      "the gate open (131), you still above 80: wave 2 held 15-20 s from then (" .. tostring(holdLine) .. ")")
local holdUntil = h and h.untilT or 0
tickTo(131.75, holdUntil - 0.25, true)
check(D.wave == 1 and D.state == "wave" and has(line("round 10: wave 2 waits for the intensity hold", from), "s more)"),
      "the wave gate (roundsTick's) stays shut while the hold is on, logged")
check(since(from, "^round 10: wave 2 waits") == 1, "... once")
check(D.int.hold and D.int.hold.untilT == holdUntil, "still hot: the hold never made longer")
tickTo(holdUntil, holdUntil + 1, true)
check(D.wave == 2 and has(line("round 10: wave 2 of 3", from), "wave 2 of 3"), "the hold's end: wave 2 comes")
check(has(line("intensity: hold over after", from), "(wave 2)") and has(line("intensity: hold not now", from), "wave 2 had its 1): wave 2 comes"),
      "... the hold's end logged, and why there's no second for wave 2 (per_wave 1)")
-- the next wave due gap_s after the last hold, still hot: it comes
tickTo(holdUntil + 1.25, holdUntil + 10, true)
check(D.wave == 3 and D.int.hold == nil and has(line("intensity: hold not now", from), "hold.gap_s 20): wave 3 comes"),
      "still hot, wave 3 due within gap_s 20 of the last hold: it comes at once (logged)")
check(#spawns >= 1 and spawns[1].unit == U2 and has(line("intensity: round 10: wave 2's flights 3 s further apart", from), "(you at intensity"),
      "wave 2's flight came (its rest not held again: per_wave), the spawn gap 3 s longer while you're hot (logged)")
D.state = "wait"                                                   -- (the round's clear: its line)
itick(D.now + 1)
local rl = line("intensity: round 10: you avg", from)
check(rl ~= nil and rl:find("above 80 for %d+ s; comfort avg %d+; held 1 %(%d+ s%), pushes 0; level 0 %(the spikes' 1%)$") ~= nil,
      "the round's over: its line (your avg / peak / 30 s+ above 80, so the level eased too; comfort, holds, pushes): " .. tostring(rl))
-- per_wave, not gap_s, keeps a wave's second hold away
holdScene()
CFG.intensity.hold.gap_s = 0
from = #logs + 1
tickTo(100, 110, true)
alive[U1] = 2
tickTo(110.25, 112, true)
holdUntil = D.int.hold and D.int.hold.untilT or 0
check(holdUntil > 0, "(gap_s 0: wave 2 held once its gate opened)")
tickTo(112.25, holdUntil + 3, true)
check(D.int.hold == nil and D.wave == 2 and has(line("intensity: hold not now", from), "wave 2 had its 1") and #spawns == 1,
      "gap_s 0, still hot after wave 2's hold: none again for wave 2 (per_wave 1), its flight comes")
-- the rest of a later wave
holdScene(10, "spawning")
D.wave, D.queue, D.at = 2, { U2, U3 }, 1e9                         -- (no flight due until 112)
tickTo(100, 112, true)
check(D.int.hold == nil, "wave 2 still to spawn, you hot, no flight due yet: no hold")
D.at = 0
spawns = {}
from = #logs + 1
tickTo(112.25, 112.5, true)
check(D.int.hold and D.int.hold.at == 112.25 and has(line("intensity: round 10: held", from), "the rest of wave 2 wait") and #spawns == 0,
      "its next flight due (112.25): the rest of wave 2 held")
tickTo(112.75, D.int.hold.untilT - 0.25, true)
check(#spawns == 0 and #D.queue == 2 and has(line("round 10: the rest of wave 2 waits for the intensity hold", from), "s more"),
      "... its flights wait (roundsTick's spawns)")
tickTo(D.int.hold.untilT, D.int.hold.untilT + 1.25, true)
check(#spawns == 1 and spawns[1].unit == U2, "... and come once it's over (the next spawn tick)")
holdScene(10, "spawning")
D.int.hold = { at = 100, untilT = 200, round = 10, what = "test", said = {} }
D.wave, D.queue, D.at = 1, { U2 }, 0
spawns = {}
tickTo(100, 100.5, true)
check(#spawns == 1, "wave 1's spawns (a round's start) are never held")
-- the spawn gap while you're hot (hold.spawn_gap_add_s)
holdScene(10, "spawning")
D.wave, D.queue, D.at = 1, { U2, U3 }, 1e9
tickTo(100, 110, true)
D.at, spawns = 0, {}
tickTo(110.25, 110.25, true)
check(#spawns == 1 and near(D.at - 110.25, CFG.spawn_gap_s + 3), "hot: the next flight spawn_gap_s + spawn_gap_add_s 3 s on (" .. tostring(D.at - 110.25) .. ")")
CFG.intensity.hold.spawn_gap_add_s = 0
local second = D.at
tickTo(110.5, second, true)
check(#spawns == 2 and near(D.at, second + CFG.spawn_gap_s), "spawn_gap_add_s 0: spawn_gap_s only (" .. tostring(D.at - second) .. ")")
-- the top cover's dive and max_s wait for its hold
holdScene(10, "fighting")
D.waves = nil
local lp = plane(L, 0, KM(10, 10, 5), DIRV(1, 0))
alive[L] = 1
D.up[L] = true
D.dir.held[L] = { kind = "top", at = 70, dmg = 0, why = "top cover" }   -- (its max_s 45 at 115)
events = {}
from = #logs + 1
tickTo(100, 112, true)
check(D.int.cover and D.int.hold == nil and has(line("intensity: round 10: held", from), "the top cover (ERA_Unit_03_Dep_Air0) wait"),
      "no wave to come, a top cover held: the top cover's hold")
holdUntil = D.int.cover.untilT
tickTo(112.25, holdUntil - 0.25, true)
check(evs("^RE_SV_DirFree") == "" and D.dir.held[L] ~= nil and has(line("director: ERA_Unit_03_Dep_Air0 (top cover) waits for the intensity hold", from), "s more"),
      "its max_s (115) passed inside the hold: still held (P2's heldTick waits)")
tickTo(holdUntil, holdUntil + 1.5, true)
check(evs("^RE_SV_DirFree") == "RE_SV_DirFree_07" and D.dir.held[L] == nil, "the hold's end: let go (RE_SV_DirFree_07)")
-- a wave due while the top cover's hold is on: a hold of its own; the top cover not held twice in a row
holdScene()
plane(L, 0, KM(10, 10, 5), DIRV(1, 0))
alive[L] = 1
D.up[L] = true
D.dir.held[L] = { kind = "top", at = 95, dmg = 0, why = "top cover" }   -- (its max_s 45 at 140)
from = #logs + 1
tickTo(100, 110, true)
local cov = D.int.cover
check(cov and D.int.hold == nil, "hot, wave 2's gate shut, a top cover held: only the top cover's hold")
alive[U1] = 2
tickTo(110.25, 111.5, true)
h = D.int.hold
check(h and h.what == "wave 2" and h.at == 111 and D.int.cover == cov and D.wave == 1,
      "wave 2's gate open while the top cover's hold is on: wave 2 held from then, a hold of its own")
local covUntil = cov and cov.untilT or 0
tickTo(111.75, covUntil + 2, true)
check(D.int.cover == nil and D.int.hold == h and D.dir.held[L] ~= nil and has(line("intensity: hold not now", from), "the top cover's last ended")
      and DIR.holdOn(D.now) == false,
      "the top cover's hold over before the wave's: not held again within gap_s (logged; DIR.holdOn false), the wave's still on")
-- a wave due just after the top cover's hold: its own hold (the top cover's gap_s isn't the wave's)
holdScene()
plane(L, 0, KM(10, 10, 5), DIRV(1, 0))
alive[L] = 1
D.up[L] = true
D.dir.held[L] = { kind = "top", at = 95, dmg = 0, why = "top cover" }
from = #logs + 1
tickTo(100, 110, true)
covUntil = D.int.cover and D.int.cover.untilT or 0
tickTo(110.25, covUntil + 1, true)
check(covUntil > 0 and D.int.cover == nil and D.int.hold == nil and D.wave == 1, "(the top cover's hold over, wave 2's gate still shut)")
alive[U1] = 2
tickTo(covUntil + 1.25, covUntil + 2.5, true)
check(D.int.hold and D.int.hold.what == "wave 2" and D.wave == 1, "wave 2 due 1-2 s after the top cover's hold: held all the same")
-- nothing to hold
holdScene(10, "fighting"); D.waves = nil
from = #logs + 1
tickTo(100, 130, true)
check(D.int.hold == nil and D.int.cover == nil and since(from, "^intensity: round 10: held") == 0 and since(from, "^intensity: hold") == 0,
      "the round's last wave all up, no top cover: nothing to hold, nothing logged")
holdScene(); D.special = { kind = "anomaly", state = "fight" }
tickTo(100, 110)
check(DIR.holdWave(110.25, "wave") == false and D.int.hold == nil, "an Anomaly round (skip_specials): a wave due isn't held")
holdScene(); CFG.intensity.hold.enabled = false
tickTo(100, 110)
check(DIR.holdWave(110.25, "wave") == false and D.int.hold == nil and DIR.gap(110.25) == 0, "[intensity.hold] enabled = false: no hold, no spawn gap")
holdScene()
tickTo(100, 110)
check(DIR.holdWave(110.25, "wave") == true and D.int.hold ~= nil, "(the same with it on: held)")
holdScene(); CFG.intensity.enabled = false
tickTo(100, 110)
check(DIR.holdWave(110.25, "wave") == false and (D.int == nil or D.int.hold == nil), "[intensity] enabled = false: nothing")

---------------------------------------------------------------------------------------------------- hold.tactics
print("hold.tactics: no new pressure on a player above high")
local function coverScene(hot)
    fresh(3)
    local p = plane(A, 0, KM(1, 0), DIRV(1, 0))                    -- you on its tail
    plane(Q, 0, KM(0, 3), DIRV(0, -1))                             -- the cover
    D.up = { [A] = true, [Q] = true }
    CFG.intensity.smooth_x = 1
    itick(99)
    if hot then HIT.h = 400; HIT.msl = { missile(2000, pawn), missile(1500, pawn) } end
    return p
end
coverScene(true)
from = #logs + 1
tickTo(100, 106)
check(evs("^RE_SV_Ace") == "" and has(line("director: cover not now", from), "under pressure: intensity 84"),
      "intensity 84 (damage 40, missiles 25, 2 near 10, health 9): the squad director's cover refused, logged")
coverScene(true); CFG.intensity.hold.tactics = false
tickTo(100, 106)
check(evs("^RE_SV_Ace") == "RE_SV_AceTurn_05", "hold.tactics = false: the cover comes")
coverScene(false)
tickTo(100, 106)
check(evs("^RE_SV_Ace") == "RE_SV_AceTurn_05", "not under pressure: the cover comes")

---------------------------------------------------------------------------------------------------- a push
print("a push: comfortable for calm_s")
local function calmScene(round, qkm)
    fresh(round or 6)
    itick(99)                                   -- (the kills before)
    RUN.kills.you = 2                                              -- two kills: comfort 25 + 35 = 60
    local q = plane(Q, 0, KM(0, qkm or 7), DIRV(0, -1))            -- a duelist 7 km off (push.range_km 8)
    D.up = { [Q] = true }
    return q
end
local q = calmScene()
from = #logs + 1
tickTo(100, 118.75)
check(evs("^RE_SV_") == "" and D.int.pl[0].calmFor >= 18, "comfort 60, intensity 3: nothing before calm_s 20")
tickTo(119, 119)
check(evs("^RE_SV_RadioSix") ~= "" and evs("^RE_SV_Ace") == "" and has(line("intensity: you comfortable", from), "ERA_Unit_02_Dep_Air1 turns onto you (7.0 km off)"),
      "20 s: the six tell, then its flight turns in (" .. tostring(line("intensity: you comfortable", from)) .. ")")
check(has(line("director: round 6", from), "push on ERA_Unit_02_Dep_Air1 (1 planes)") and has(line("director: round 6", from), 'callout "six"'),
      "counted and logged by STATS.tactic (push), its callout")
tickTo(119.25, 120)
check(evs("^RE_SV_Ace") == "RE_SV_AceTurn_05" and type(q.dirTag) == "table" and q.dirTag.tactic == "push"
      and D.aceMoveAt[Q] == 119 + 1 + 30, "lead_s after: RE_SV_AceTurn_05, the plane tagged push, its next move 31 s on")
tickTo(120.25, 145)
check(evs("^RE_SV_Ace") == "RE_SV_AceTurn_05" and has(line("intensity: you comfortable", from), "no push (its cooldown"),
      "still comfortable 20 s later: its cooldown_s 40 (logged)")
RUN.kills.you = 4                                                  -- (two more: comfortable on)
D.aceMoveAt[Q] = 0
tickTo(145.25, 162)
check(evs("^RE_SV_Ace") == "RE_SV_AceTurn_05,RE_SV_AceTurn_05", "after the cooldown: the second")
RUN.kills.you = 6
tickTo(162.25, 230)
check(evs("^RE_SV_Ace") == "RE_SV_AceTurn_05,RE_SV_AceTurn_05" and has(line("intensity: you comfortable", from), "no push (its 2 this round)"),
      "per_round 2: no third this round (logged)")
-- a held top cover dives instead
q = calmScene()
local tp = plane(L, 0, KM(10, 0, 5), DIRV(-1, 0))
D.up[L] = true
D.dir.held[L] = { kind = "top", at = 99, dmg = 0, why = "top cover" }
events = {}
from = #logs + 1
tickTo(100, 121)
check(has(line("intensity: you comfortable", from), "held ERA_Unit_03_Dep_Air0 dives on you") and evs("^RE_SV_RadioDive") ~= ""
      and evs("^RE_SV_DirFree") == "RE_SV_DirFree_07" and evs("^RE_SV_Ace") == "",
      "a top cover held: it dives on you (its dive tell, RE_SV_DirFree_07), no flight turned")
check(has(line("director: round 6", from), "top_cover on ERA_Unit_03_Dep_Air0"), "... counted as top cover by STATS.tactic")
-- ... but not while the hold is on: a flight turns instead
q = calmScene()
plane(L, 0, KM(10, 0, 5), DIRV(-1, 0))
D.up[L] = true
D.dir.held[L] = { kind = "top", at = 99, dmg = 0, why = "top cover" }
D.int.cover = { at = 99, untilT = 500, round = 6, what = "test", said = {} }
events = {}
tickTo(100, 121)
check(evs("^RE_SV_DirFree") == "" and evs("^RE_SV_Ace") == "RE_SV_AceTurn_05", "the top cover's intensity hold on: it stays, a flight turns in")
-- none
calmScene(2)
tickTo(100, 125)
check(evs("^RE_SV_") == "", "round 2 (push.from_round 3): no push")
calmScene(); CFG.director.enabled = false
from = #logs + 1
tickTo(100, 125)
CFG.director.enabled = true
check(evs("^RE_SV_") == "" and has(line("intensity: you comfortable", from), "nothing sent (the squad director is off"), "[director] off: nothing sent (logged)")
calmScene(6, 9)
from = #logs + 1
tickTo(100, 130)
check(evs("^RE_SV_") == "" and has(line("intensity: you comfortable", from), "nothing sent (no flight within 8 km may turn onto you)")
      and since(from, "^intensity: you comfortable") == 1, "the only flight 9 km off: nothing sent, logged once")
for _, x in ipairs(planes) do if x.unit == Q then moveP(x, KM(0, 6)) end end
tickTo(130.25, 136)
check(evs("^RE_SV_Ace") == "RE_SV_AceTurn_05", "... tried again 5 s on: once a flight's in range, it comes")
calmScene(); CFG.intensity.push.enabled = false
tickTo(100, 125)
check(evs("^RE_SV_") == "", "[intensity.push] enabled = false: no push")
calmScene(); D.special = { kind = "ladon", state = "fight" }
tickTo(100, 125)
check(evs("^RE_SV_") == "", "a Ladon round (skip_specials): no push")

---------------------------------------------------------------------------------------------------- the level
print("the level: the spikes a ceiling")
local function levelScene(round)
    fresh(round or 15)
    CFG.intensity.window_s = 1000                                  -- (the damage counts through the test)
    pressure(U1)
    itick(99)
    HIT.h = 200                                                    -- (80 HP taken: damage 40 + missiles 25 + near 20 + health 12)
end
levelScene()
local vet = CFG.tiers.list[3]
D.flightTier = { [Q] = 3 }
local v = plane(Q, 0, KM(30, 0), DIRV(1, 0)); v.tier = nil
enemyTier(v, 15, 3); enemySpike(v, 15, vet)
local jv = plane(Q, 2, KM(30, 2), DIRV(1, 0)); jv.tier = nil
enemyTier(jv, 15, 1); jv.jammed = true                            -- (a Rookie near the jammer: its boost on top)
check(DIR.level(15) == 2 and levelFor(15) == 2 and v.spiked == 2 and v.obj.SurroundPursuitMinRange == 6000
      and v.rankSet == 5 and v.obj.PilotRank == 5 and v.rankBase == 4,
      "round 15: the spikes' level 2 (a Veteran: provoke surround 60-160 m, PilotRank 4 raised to level 2's rank_min 5)")
from = #logs + 1
tickTo(100, 128)
check(DIR.level(15) == 2, "the room above 80 under down_after_s 30 of fighting: still 2")
tickTo(128.25, 140)
local lvLine = line("intensity: round 15: the room above 80", from)
check(DIR.level(15) == 1 and levelFor(15) == 1 and has(lvLine, "enemies from now fly difficulty level 1 (the spikes' 2, at most 1 under)"),
      "30 s of it: level 1 (" .. tostring(lvLine) .. ")")
check(v.spiked == 1 and v.obj.SurroundPursuitMinRange == 8000 and has(line("intensity: level 1 on the enemies up (eased)", from), "provoke written again on 1 of 1, PilotRank on 2"),
      "the enemies up flown again at level 1: a Veteran's provoke (surround 80-220 m) and PilotRank, logged")
check(v.rankSet == 4 and v.obj.PilotRank == 4 and jv.rankBase == 2 and jv.rankSet == 4 and jv.obj.PilotRank == 4 + CFG.jammer.rank_add,
      "... PilotRank 4 (level 1's rank_min 4, was 5), a Rookie near the jammer 4 + its boost (" .. tostring(jv.obj.PilotRank) .. ")")
local nw = plane(Q, 1, KM(30, 1), DIRV(1, 0)); nw.tier = nil
enemyTier(nw, 15, 3)
check(nw.obj.PilotRank == 4, "a new Veteran: PilotRank 4 (level 1's rank_min 4, not level 2's 5)")
check(TIER.roundBudget(8, levelFor(8)) == TIER.roundBudget(8) - 2 and levelFor(8) == 0,
      "a round's aircraft (startRound's TIER.roundBudget on levelFor): round 8 eased to level 0, its aircraft_add (2) off")
tickTo(140.25, 230)
check(DIR.level(15) == 1 and since(from, "^intensity: round 15: the room above") == 1, "still hot, past gap_s 45: max_drop 1, no lower")
CFG.intensity.level.max_drop = 2
tickTo(230.25, 262)
check(DIR.level(15) == 0, "max_drop 2: level 0 after another 30 s")
CFG.intensity.level.max_drop = 1
check(DIR.level(15) == 1, "max_drop back to 1: never more than it under the spikes")
D.int.ease = 1
-- cool: back up after up_after_s below up_below
HIT.msl, HIT.h = {}, 800
for _, x in ipairs(planes) do x.dist = 20 end
from = #logs + 1
tickTo(262.25, 300)
check(DIR.level(15) == 1, "below 50 under up_after_s 60: still 1")
tickTo(300.25, 340)
check(DIR.level(15) == 2 and has(line("intensity: round 15: the room below 50", from), "level 2 (the spikes' 2)"), "60 s of it: back to 2")
levelScene(5)
tickTo(100, 160)
check(DIR.level(5) == 0 and (D.int.ease or 0) == 0, "round 5 (no spike yet): nothing to ease")
levelScene()
tickTo(100, 140)
CFG.intensity.level.enabled = false
check(DIR.level(15) == 2, "[intensity.level] enabled = false: the spikes' level")
tickTo(140.25, 142)
check(D.int.ease == 0 and has(line("intensity: level off"), "enemies fly the spikes' levels again"), "... and its ease dropped (logged)")
levelScene()
CFG.intensity.enabled = false
tickTo(100, 140)
check(DIR.level(15) == 2 and levelFor(15) == 2, "[intensity] enabled = false: the spikes' level")
-- spike 1 eased to 0: a tier without its own provoke has nothing to write at level 0, so the game's own values go back
levelScene(10)
D.flightTier = { [Q] = 1 }
local rk = plane(Q, 0, KM(30, 0), DIRV(1, 0)); rk.tier = nil
rk.obj.ProvokeConditionConeAngle, rk.obj.ProvokeDeterminationTime = 90, 3.0
rk.obj.SurroundPursuitMinRange, rk.obj.SurroundPursuitMaxRange = 10000, 30000
enemyTier(rk, 10, 1); enemySpike(rk, 10, CFG.tiers.list[1])
check(rk.spiked == 1 and rk.obj.ProvokeConditionConeAngle == 70 and rk.obj.SurroundPursuitMinRange == 8000,
      "round 10, a Rookie: spike 1's provoke (70 deg, surround 80-220 m) over the game's own (90 deg, 100-300 m)")
from = #logs + 1
tickTo(100, 140)
check(DIR.level(10) == 0 and rk.spiked == 0 and rk.obj.ProvokeConditionConeAngle == 90 and rk.obj.ProvokeDeterminationTime == 3.0
      and rk.obj.SurroundPursuitMinRange == 10000 and rk.obj.SurroundPursuitMaxRange == 30000
      and has(line("intensity: level 0 on the enemies up (eased)", from), "provoke written again on 1 of 1"),
      "eased to level 0: its provoke back to the game's own values it had before (logged 1 of 1)")
-- the attack throttle with the ease (level.pressure; U3's presets, CFG.late.pressure)
levelScene(28)
D.pressure = "C"                                                   -- (the band's, fired at the round's start)
events = {}
from = #logs + 1
tickTo(100, 140)
check(DIR.level(28) == 2 and evs("^RE_SV_Pressure") == "RE_SV_PressureB" and D.pressure == "B"
      and has(line("pressure: round 28: preset B", from), "the band's C, a letter gentler"),
      "round 28 (preset C) eased: RE_SV_PressureB, logged (" .. tostring(line("pressure: round 28", from)) .. ")")
HIT.msl, HIT.h = {}, 800
for _, x in ipairs(planes) do x.dist = 20 end
tickTo(140.25, 210)
check(DIR.level(28) == 3 and evs("^RE_SV_Pressure") == "RE_SV_PressureB,RE_SV_PressureC" and D.pressure == "C",
      "back up: the band's C again")
levelScene(15)
D.pressure = "B"
events = {}
tickTo(100, 140)
check(DIR.level(15) == 1 and evs("^RE_SV_Pressure") == "", "round 15 (preset B) eased: B already the floor (pressure_min B), none fired")
D.int.ease = 1
check(DIR.pressure("D") == "C" and DIR.pressure("C") == "B" and DIR.pressure("B") == "B" and DIR.pressure("A") == "A",
      "DIR.pressure, ease 1: D to C, C to B, B and A as they are (pressure_min B)")
CFG.intensity.level.pressure_min = "a"
check(DIR.pressure("B") == "A", "... pressure_min a (any case): B to A")
CFG.intensity.level.pressure_min = "x"
check(DIR.pressure("C") == "B" and DIR.pressure("B") == "B", "... pressure_min not a preset: B")
D.int.ease = 2; CFG.intensity.level.max_drop = 2
check(DIR.pressure("D") == "B", "ease 2 (max_drop 2): D to B")
CFG.intensity.level.pressure = false
check(DIR.pressure("D") == "D", "[intensity.level] pressure = false: the band's")
CFG.intensity.level.pressure = true
D.special = { kind = "anomaly", state = "fight" }
events = {}
from = #logs + 1
pressureNow("test")
check(evs("^RE_SV_Pressure") == "" and has(line("pressure: round 15: the anomaly's own throttle is up", from), "(test)"),
      "an Anomaly's own throttle up: none fired (logged), its boss down fires the band's")

---------------------------------------------------------------------------------------------------- co-op
print("co-op: a joiner")
CFG.coop.enabled = true
fresh(8)
COOP.open, COOP.role, COOP.slot = true, "join", 1
COOP.tick(30)
sent = {}
DIR.tick(100, false)
check(sentOf(">in|") == "-1>in|3.0|25.0|80.0|0.0", "a joiner's scores to the host: \"in\", intensity, comfort, health, missiles (" .. sentOf(">in|") .. ")")
DIR.tick(100.25, false); DIR.tick(100.5, false); DIR.tick(100.75, false)
check(#sent == 1, "... once a second")
DIR.tick(101, false)
check(#sent == 2, "... the next second")
check(COOP.host() == false and COOP.sendIntensity ~= nil, "(COOP.sendIntensity: a joiner's)")
fresh(15)
COOP.open, COOP.role, COOP.slot = true, "join", 1
COOP.tick(31)
local vj = plane(Q, 0, KM(30, 0), DIRV(1, 0))
enemySpike(vj, 15, nil)
inbox[#inbox + 1] = "0|rnd|15|fighting|0.0|1|2|10|1"
COOP.tick(32)
roundsTick(100)
check(D.intLevel and D.intLevel.level == 1 and DIR.level(15) == 1 and levelFor(15) == 1, "the host's \"rnd\" with level 1: the copies fly level 1")
from = #logs + 1
DIR.tick(100, false)
check(has(line("intensity: the host's difficulty level for round 15", from), ": 1 (the spikes' 2)") and vj.spiked == 1
      and vj.obj.SurroundPursuitMinRange == 8000, "... logged, a live copy's provoke written again for it")
for _, bad in ipairs({ "7", "1.5", "nan", "-1", "x" }) do
    inbox[#inbox + 1] = "0|rnd|15|fighting|0.0|1|2|10|" .. bad
    COOP.tick(33)
    roundsTick(101)
    check(D.intLevel == nil and DIR.level(15) == 2, "a level of " .. bad .. ": not taken (the spikes' 2)")
end
inbox[#inbox + 1] = "0|rnd|15|fighting|0.0|1|2|10"
COOP.tick(34); roundsTick(102)
check(DIR.level(15) == 2, "an older host's \"rnd\" (no level): the spikes' 2")
events = {}
tickTo(102, 110)
check(evs("^RE_SV_") == "", "DIR.tick on a joiner: no event of its own")

print("co-op: the host")
fresh(10, "wave")
COOP.open, COOP.role, COOP.slot = true, "host", 0
peerState[1] = "5000000,0,300000,0,0,0,600,100,3,100"            -- (player 2 50 km east, in the level, alive, fresh)
COOP.tick(40)
M.ints = {}
local function inMsg(s) inbox[#inbox + 1] = s; COOP.tick(41) end
inMsg("1|in|85|20|60|2")
local x = COOP.intensityOf(1)
check(x and x.i == 85 and x.c == 20 and x.hp == 60 and x.m == 2, "\"in\" from player 2: kept")
inMsg("1|in|90|20|60|2")
check(COOP.intensityOf(1).i == 85, "... a second within 0.25 s: dropped")
clock = clock + 0.3
inMsg("1|in|500|-5|60|99")
x = COOP.intensityOf(1)
check(x.i == 100 and x.c == 0 and x.m == 20, "out of range: clamped (100, 0, 20 missiles)")
M.ints = {}
for _, bad in ipairs({ "1|in|nan|20|60|2", "1|in|1e999|20|60|2", "1|in|x|20", "0|in|85|20|60|2", "30|in|85|20|60|2", "1|in" }) do inMsg(bad) end
check(next(M.ints) == nil, "not kept: a NaN, an infinity (1e999), a word, the host's own slot, a slot past 24, no numbers")
inMsg("1|in|85|20|60|2")
clock = clock + 3.5
check(COOP.intensityOf(1) == nil, "stale after 3 s: none")
check(COOP.sendIntensity(1, 2, 3, 4) == false, "the host sends none")
-- the room's hold, named after the joiner who caused it
fresh(10, "wave")
COOP.open, COOP.role, COOP.slot = true, "host", 0
COOP.tick(42)
M.peers[1].obj, M.peers[1].addr = mkObj("BP_OP1022_f16c_CoopPeerB_C_1", KM(50, 0), DIRV(1, 0)), nil
D.waves, D.wave, D.waveAt, D.at = { { U1 }, { U2 } }, 1, 90, 0
D.up = { [U1] = true }; alive[U1] = 6
from = #logs + 1
for t = 100, 106 do
    clock = clock + 1
    inMsg("1|in|90|10|40|2")
    if t == 104 then alive[U1] = 2 end                             -- (wave 2 due from 104)
    tickTo(t, t + 0.75, true)
end
check(D.int.hold and D.int.hold.at == 104 and has(line("intensity: round 10: held", from), "(player 2 at intensity 90, above 80 for ")
      and has(line("intensity: round 10: held", from), "): wave 2 wait; the room: you 3, player 2 90"),
      "player 2 above 80, wave 2 due: the room's next wave held, named after them (" .. tostring(line("intensity: round 10: held", from)) .. ")")
-- the host's level in "rnd"
fresh(15)
COOP.open, COOP.role, COOP.slot = true, "host", 0
COOP.tick(43)
D.int = nil; itick(99); D.int.ease = 1
sent = {}
clock = clock + 2
COOP.tick(44)
check(sentOf(">rnd|") ~= "" and sentOf(">rnd|"):match("|1$") ~= nil, "the host's \"rnd\" carries its level (1): " .. sentOf(">rnd|"))
-- a joiner's push: the six tell by "tl", a hunt with its target on their stand-in
fresh(6)
COOP.open, COOP.role, COOP.slot = true, "host", 0
COOP.tick(45)
local standIn = mkObj("BP_OP1022_f16c_CoopPeerB_C_2", KM(50, 0), DIRV(1, 0))
M.peers[1].obj = standIn
local jq = plane(Q, 0, KM(54, 0), DIRV(-1, 0))                   -- (4 km from player 2, 54 from you)
D.up = { [Q] = true }
grounded = false
sent, events = {}, {}
from = #logs + 1
for t = 100, 122 do
    clock = clock + 1
    inMsg("1|in|10|80|90|0")
    tickTo(t, t + 0.75)
end
check(sentOf("tl|six") == "1>tl|six||" and has(line("intensity: player 2 comfortable", from), "ERA_Unit_02_Dep_Air1 turns onto player 2"),
      "player 2 comfortable 20 s: the six tell to player 2 only (\"tl\"), a flight turns onto them")
check(evs("^RE_SV_Hunt") == "RE_SV_Hunt_05" and evs("^RE_SV_Ace") == "" and jq.obj.tgt == standIn,
      "... a hunt (RE_SV_Hunt_05, not LastTGT) with its TargetActor on player 2's stand-in")
-- two calm players: the first (you: the same comfort, the lower slot) with nothing to send doesn't keep player 2 waiting
fresh(6)
COOP.open, COOP.role, COOP.slot = true, "host", 0
COOP.tick(46)
M.peers[1].obj = standIn
M.ints = {}                                                        -- (the last scene's "in": not this one's)
itick(99)
RUN.kills.you = 2                                                  -- (you: comfort 60, intensity 3)
plane(Q, 0, KM(54, 0), DIRV(-1, 0))                                -- (4 km from player 2, 54 from you)
D.up = { [Q] = true }
sent, events = {}, {}
from = #logs + 1
for t = 100, 122 do
    clock = clock + 1
    inMsg("1|in|10|60|90|0")
    tickTo(t, t + 0.75)
end
local youL, p2L = line("intensity: you comfortable", from), line("intensity: player 2 comfortable", from)
check(has(youL, "nothing sent (no flight within 8 km may turn onto") and has(p2L, "ERA_Unit_02_Dep_Air1 turns onto player 2")
      and evs("^RE_SV_Hunt") == "RE_SV_Hunt_05" and D.int.pushNext[1] == 119 + 40,
      "you and player 2 comfortable (60 each): nothing within range of you, so player 2's push the same second, 119 (" .. tostring(p2L) .. ")")
-- ... and you with your pushes used up: player 2's comes
fresh(6)
COOP.open, COOP.role, COOP.slot = true, "host", 0
COOP.tick(47)
M.peers[1].obj = standIn
M.ints = {}
itick(99)
RUN.kills.you = 2
plane(Q, 0, KM(54, 0), DIRV(-1, 0))
plane(A, 0, KM(0, 5), DIRV(0, -1))                                 -- (a flight 5 km from you too)
D.up = { [Q] = true, [A] = true }
sent, events = {}, {}
from = #logs + 1
for t = 100, 122 do
    clock = clock + 1
    inMsg("1|in|10|61|90|0")                                     -- (player 2 the more comfortable: first)
    if t == 101 then D.int.pushN[1] = 2 end                        -- (player 2's 2 used: you next)
    tickTo(t, t + 0.75)
end
check(has(line("intensity: player 2 comfortable", from), "no push (its 2 this round)") and has(line("intensity: you comfortable", from), "ERA_Unit_01_Dep_Air0 turns onto")
      and evs("^RE_SV_Ace") ~= "", "player 2 the most comfortable but its 2 used: your push instead")
CFG.coop.enabled = false
COOP.open, COOP.role, COOP.slot = false, nil, nil

---------------------------------------------------------------------------------------------------- the hooks
print("the hooks, by their place in the source")
do
    local sr = readAll(MOD .. "/Scripts/sv_rounds.lua")
    check(has(sr, '(alive <= w.next_at or timedOut) and not (DIR and DIR.holdWave and DIR.holdWave(now, "wave"))'),
          "sv_rounds roundsTick: the wave gate waits for the hold")
    check(has(sr, 'DIR.holdWave(now, "spawning")') and has(sr, "TIER.roundBudget(D.round, levelFor(D.round))")
          and has(sr, "local level = levelFor(D.round + 1)"), "... a later wave's spawns; startRound's aircraft and the spike callout on levelFor")
    check(has(sr, "D.at = now + CFG.spawn_gap_s + gapAdd") and has(sr, "pcall(DIR.gap, now)"), "... the spawn gap's add (DIR.gap)")
    check(has(sr, "pcall(DIR.pressure, band)") and has(sr, "function pressureNow(why)"), "... the attack throttle's preset through DIR.pressure, pressureNow")
    local ai = readAll(MOD .. "/Scripts/sv_ai.lua")
    local _, nAi = ai:gsub("spikeCfg%(levelFor%(round%)%)", "")
    check(nAi == 2 and not ai:find("spikeLevel%(round%)"), "sv_ai: enemyTier's rank_min and enemyManeuvers' post_stall_all on levelFor")
    local rw = readAll(MOD .. "/Scripts/sv_rows.lua")
    check(has(rw, "level = level or levelFor(round)") and has(rw, "p.spiked = w and w.level or levelFor(round)")
          and has(rw, "function provokeStockWant(p, level)"), "sv_rows: provokeWant / enemySpike on levelFor, the game's own provoke kept")
    local sp = readAll(MOD .. "/Scripts/sv_spawn.lua")
    check(has(sp, "searchAircraft(ac, levelFor(D.round))") and has(sp, "topSpike or levelFor(D.round), tier.fcs or 0)"),
          "sv_spawn: the bombers' and fighters' fire-control level on levelFor (the tier's fcs the floor)")
    local co = readAll(MOD .. "/Scripts/sv_coop.lua")
    check(has(co, 'elseif k == "in" then') and has(co, "D.intLevel = r.level and") and has(co, "D.waves and #D.waves or 0, alive, lv)"),
          "sv_coop: the host's \"in\", the level in \"rnd\" and the joiner's D.intLevel")
    local d = readAll(MOD .. "/Scripts/sv_director.lua")
    local it, on = d:find("pcall(DIR.intensityTick, now, paused)", 1, true), d:find("if not (on() and now and D and D.round and not paused) then return end", 1, true)
    check(it and on and it < on, "DIR.tick: P4's part before the squad director's switch (each its own)")
    check(has(d, "DIR.holdOn and DIR.holdOn(now)") and has(d, "DIR.hot and DIR.hot(slot)"), "the squad director: top cover waits for the hold; per-player tactics on DIR.hot")
    check(not d:find("local%s+[%w_,%s]*=%s*SV_Event") and not d:find("local%s+[%w_,%s]*=%s*hudCallout"),
          "sv_director never keeps SV_Event / hudCallout at load (sv_coop wraps them after)")
    local cf = readAll(MOD .. "/Scripts/sv_config.lua")
    check(has(cf, "function levelFor(round)") and has(cf, "function TIER.roundBudget(round, level)"), "sv_config: levelFor, TIER.roundBudget's level")
end

print(fails == 0 and "intensity test: all passed" or ("intensity test: " .. fails .. " FAILED"))
logFile:close()
os.exit(fails == 0 and 0 or 1)
