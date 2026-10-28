-- late_rounds_test.lua <mod dir> <work dir> (run by tools/checks/late_rounds_test.sh): the behaviour roadmap's P8, late
-- rounds (tools/re/BEHAVIOUR_DIRECTOR.md unit 3), on the real sv_core.lua, sv_config.lua, sv_ai.lua, sv_spawn.lua,
-- sv_rounds.lua, sv_stats.lua and sv_coop.lua (startRound, hostSync and mirroredEvent exposed) and sv_main.lua's
-- creditKill, the game stubbed:
--   the thesis' P8 table from TIER's helpers (rounds 25 / 28 / 31 / 35: the round's aircraft, the most up at once per
--     preset), rounds 1-25 as before, CFG.late off, the x1.5 health cap, the pressure bands, survival.ini's new sections;
--   startRound on its real code, many times a round (Monte Carlo): the budget, the wave cap, the aircraft picked and the
--     waves (the table's "Waves (Standard, about)"), each wave within the cap, with the menu's ENEMY AIRCRAFT % (cap ->
--     % -> co-op; the pool's 86 and its "pool short" line; the menu's help stops at the pool), co-op's COOP.more for 4,
--     12 and 24 players (the room's cap TIER.coopCap: 60 to round 25, 80 by round 32; max_up 30), an amphibious round
--     above 100 % (no longer cut back to 30), [late] grow off;
--   the attack throttle: RE_SV_Pressure<X> fired by startRound when the band's preset changes and in a run's first round
--     (B too: a restart keeps an earlier run's preset, the review's repro), none in an Anomaly or VALKA round, the band's
--     again 3 s after its boss is down (pressureAfterBoss) or the round after, a failed fire kept, forwarded to joiners,
--     re-sent by hostSync (B too; not while a boss is up);
--   the director kill bonus: creditKill pays x1.5 for your kill of a plane STATS.tactic tagged (p.dirTag = { tactic,
--     at }) within tag_s, nothing past it, for an ally's kill, a bare string tag or with it off.
local MOD, WORK = arg[1], arg[2]
local fails = 0
local function check(ok, what) if ok then print("  ok   " .. what) else print("  FAIL " .. what); fails = fails + 1 end end
local function readAll(p) local f = assert(io.open(p, "rb")); local s = f:read("a"); f:close(); return s end
local function writeAll(p, s) local f = assert(io.open(p, "wb")); f:write(s); f:close() end
do                                    -- (the runtime's paths are Windows ones: SCRIPT_DIR .. "..\\config\\")
    local rawOpen = io.open
    io.open = function(p, m) return rawOpen((tostring(p):gsub("\\", "/")), m) end
end
local defaultIni = readAll(MOD .. "/config/survival.default.ini")
writeAll(WORK .. "/config/survival.default.ini", defaultIni)
-- a player's survival.ini: the shipped one, then the new sections set live (any case for the presets)
writeAll(WORK .. "/config/survival.ini", defaultIni ..
    "\r\n[late.pressure]\r\nfrom_round = 27, 32\r\npreset = c, a\r\n[late.max_up_cap]\r\nstandard = 24\r\n" ..
    "[late.director_pay]\r\nx = 2.0\r\n[late]\r\naircraft_from_round = 30\r\n")

-- the game's world, stubbed
VERSION = "0.71.5-late.test"
local notify = {}
function NotifyOnNewObject(cls, fn) notify[cls] = notify[cls] or {}; table.insert(notify[cls], fn) end
function FName(s) return s end
function FindAllOf() return {} end
function FindFirstOf() return nil end
function StaticFindObject() return nil end
function playerOnAirfield() return false end
function hudCallout() end
function searchAircraft(a) return a end
function airfieldTick() end
function bombTick() end
local events, eventResult = {}, 1
function SV_Event(name) events[#events + 1] = name; return eventResult end
function SV_SetAircraft() return 1 end
function SV_SetLevel() return 1 end
function SV_UnitAlive() return 0 end
function SV_Spawn() return 0 end
-- co-op's natives (the host's sends are kept)
local sent = {}
function SV_MenuChoice() return 0 end
function SV_CoopOpen() return 1 end
function SV_CoopClose() end
function SV_CoopSend(msg, rel, to) sent[#sent + 1] = tostring(to) .. ">" .. msg; return 1 end
function SV_CoopRecv() return "" end
function SV_CoopInfo() return "open=1;state=linked;peers=1/linked/40/10/p" end
function SV_CoopMe() end
function SV_CoopReset() end
function SV_CoopTrack() return 1 end
function SV_CoopBind() return 1 end
function SV_CoopPeer() return 1 end
function SV_CoopPeerAt() return "" end
-- the menu's run setup (sv_menu.lua: SETUP.enemyX is the ENEMY AIRCRAFT %; menu_test.sh tests it)
local ENEMY_X = 1
SETUP = { enemyX = function() return ENEMY_X end, specialsX = function() return 1 end, breakS = function() return 20 end }

-- the real parts (sv_core's SCRIPT_DIR and log file in the work folder)
local function run(name, chunk, edits)
    local src = readAll(MOD .. "/Scripts/" .. name)
    for _, e in ipairs(edits or {}) do
        local n
        src, n = src:gsub(e[1], e[2], 1)
        assert(n == 1, name .. ": " .. e[1] .. " not found")
    end
    assert(load(src, chunk or ("=" .. name)))()
end
run("sv_core.lua", "@" .. WORK .. "/Scripts/sv_core.lua")
local logs = {}
local logFile = assert(io.open(WORK .. "/test_lua.log", "wb"))
function log(s) logs[#logs + 1] = s; logFile:write(os.date("%H:%M:%S ") .. s .. "\n") end
function valid(o) return type(o) == "table" and not o.gone end
function nameOf(o) return type(o) == "table" and o.full or "?" end
function addrOf(o) return type(o) == "table" and o.addr or nil end
run("sv_config.lua")
local cfgLine = nil
for _, l in ipairs(logs) do if l:find("^config: survival%.ini") then cfgLine = l end end
run("sv_ai.lua"); run("sv_spawn.lua")
run("sv_rounds.lua", nil, { { "\nlocal function startRound%(%)", "\nfunction startRound()" },
                             { "\nlocal function pressureAfterBoss%(now%)", "\nfunction pressureAfterBoss(now)" } })
run("sv_stats.lua")
run("sv_coop.lua", nil, { { "\nlocal M = {", "\nM = {" }, { "\nlocal function hostSync%(to%)", "\nfunction hostSync(to)" },
                          { "\nlocal function mirroredEvent%(name%)", "\nfunction mirroredEvent(name)" } })
local M = _G.M
LB.stat = function() end
local PRESET = "standard"
presetName = function() return PRESET, 3 end       -- (two values, as the game's: waveCap takes the first)
-- the specials startRound meets here (sv_anomalies.lua's SPC.kinds, cut down to what startRound reads)
SPC.kinds = {
    anomaly = { alone = function() return false end, aircraft = function() return 5 end },
    valka = { disguise = function() return true end, alone = function() return false end, budget = function() return 6 end },
    amphibious = { sub = "amphib_sub" },
}
function SPC.kindValue(v, ...) if type(v) == "function" then return v(...) end return v end
AMPH.ready = function() return true end
math.randomseed(8)

local function has(s, part) return s ~= nil and s:find(part, 1, true) ~= nil end
local function line(prefix, from)
    for i = #logs, from or 1, -1 do if logs[i]:sub(1, #prefix) == prefix then return logs[i] end end
    return nil
end
local function deep(t) if type(t) ~= "table" then return t end; local c = {}; for k, v in pairs(t) do c[k] = deep(v) end; return c end

---------------------------------------------------------------------------------------------------- survival.ini
print("survival.ini's new settings")
local pr = CFG.late.pressure
check(cfgLine and not has(cfgLine, "not used"), "config: every line used (" .. tostring(cfgLine) .. ")")
check(pr.from_round[1] == 27 and math.type(pr.from_round[1]) == "integer" and pr.preset[2] == "a",
      "[late.pressure] from_round = 27, 32 / preset = c, a read")
check(TIER.pressure(26) == "B" and TIER.pressure(27) == "C" and TIER.pressure(32) == "A", "the presets in any case (c -> C, a -> A)")
check(TIER.maxUp(40, "standard") == 24 and CFG.late.director_pay.x == 2.0, "[late.max_up_cap] standard = 24, [late.director_pay] x = 2.0")
check(TIER.roundCap(29) == 30 and TIER.roundCap(30) == 33 and math.type(CFG.late.aircraft_from_round) == "integer",
      "[late] aircraft_from_round = 30: the growth starts there")
check(CFG.late.grow == true and CFG.late.coop_max_aircraft == 80 and math.type(CFG.late.coop_max_aircraft) == "integer"
      and CFG.coop.max_aircraft == 60, "[late] grow / coop_max_aircraft and [coop] max_aircraft 60 as shipped")
CFG.late = deep(CFG_DEFAULTS.late)                    -- the shipped settings for the rest
pr = CFG.late.pressure

---------------------------------------------------------------------------------------------------- the table
print("the thesis' P8 table (TIER's helpers, 100 %)")
local TABLE = {                                        -- round, aircraft, most up at once casual / standard / ace
    { 25, 30, 14, 18, 22 }, { 28, 39, 17, 21, 25 }, { 31, 48, 20, 24, 28 }, { 35, 60, 20, 26, 30 },
}
for _, r in ipairs(TABLE) do
    local n, c, s, a = TIER.roundBudget(r[1]), TIER.maxUp(r[1], "casual"), TIER.maxUp(r[1], "standard"), TIER.maxUp(r[1], "ace")
    check(n == r[2] and c == r[3] and s == r[4] and a == r[5],
          string.format("round %d: %d aircraft (want %d), most up %d / %d / %d (want %d / %d / %d)", r[1], n, r[2], c, s, a, r[3], r[4], r[5]))
end
check(TIER.roundBudget(26) == 33 and TIER.roundBudget(33) == 54 and TIER.roundBudget(40) == 60 and TIER.roundBudget(80) == 60,
      "26: 33, 33: 54, 35+: 60 (late.max_aircraft)")
check(TIER.maxUp(60, "ace") == 30 and TIER.maxUp(60, "casual") == 20, "the most up stops at max_up_cap")
local same = true
for r = 1, 25 do                                       -- rounds 1-25: the old formula (min(4 + 2 (r - 1) + spike, 30))
    local old = math.min(4 + (r - 1) * 2 + (spikeCfg(spikeLevel(r)).aircraft_add or 0), 30)
    if TIER.roundBudget(r) ~= old or TIER.roundCap(r) ~= 30 then same = false end
    for p, n in pairs(CFG.waves.max_up_by_preset) do if TIER.maxUp(r, p) ~= n then same = false end end
end
check(same, "rounds 1-25: the budget and the most up as before (30 from round 13, 14 / 18 / 22)")
check(TIER.roundBudget(10) == 24 and TIER.roundBudget(35) == 60, "the ENEMY AIRCRAFT help's rounds: 10 has 24, 35 has 60")
check(TIER.maxUp(35, "other") == CFG.waves.max_up, "a preset without a cap doesn't grow")
CFG.late.enabled = false
check(TIER.roundBudget(26) == 30 and TIER.roundBudget(35) == 30 and TIER.maxUp(35, "ace") == 22 and TIER.pressure(35) == nil,
      "CFG.late off: today's 30, 22 up, no pressure")
CFG.late.enabled = true
CFG.late.aircraft_from_round = 0
check(TIER.roundBudget(35) == 30 and TIER.maxUp(35, "standard") == 18, "aircraft_from_round 0: no growth")
CFG.late.aircraft_from_round = 26
CFG.late.grow = false
check(TIER.roundBudget(35) == 30 and TIER.maxUp(35, "ace") == 22 and TIER.coopCap(35) == 60 and TIER.pressure(35) == "D"
      and TIER.lateHealthX(30) == 1.5, "[late] grow = false: no growth (co-op's cap too); the throttle and health stay")
CFG.late.grow = true
local cc, ccOk = {}, true
for r = 1, 25 do if TIER.coopCap(r) ~= 60 then ccOk = false end end
for _, r in ipairs({ 26, 28, 31, 32, 35, 60 }) do cc[#cc + 1] = r .. ": " .. TIER.coopCap(r) end
check(ccOk and TIER.coopCap(26) == 63 and TIER.coopCap(31) == 78 and TIER.coopCap(32) == 80 and TIER.coopCap(60) == 80,
      "co-op's room cap (TIER.coopCap): 60 in rounds 1-25, then " .. table.concat(cc, ", "))
CFG.late.enabled = false
check(TIER.coopCap(35) == 60, "co-op's room cap with [late] off: 60")
CFG.late.enabled = true
check(TIER.poolMost() == 86, "the fighter pool can field 86 (96 less the probes' 6 + 4): " .. TIER.poolMost())
local hx = TIER.lateHealthX
check(hx(14) == 1 and math.abs(hx(15) - 1.045) < 1e-9 and math.abs(hx(25) - 1.495) < 1e-9 and hx(26) == 1.5 and hx(60) == 1.5,
      string.format("health: x1 before 15, x1.045 at 15, x%.3f at 25, x1.5 from 26 (the cap)", hx(25)))
check(TIER.pressure(1) == "B" and TIER.pressure(25) == "B" and TIER.pressure(26) == "C" and TIER.pressure(30) == "C"
      and TIER.pressure(31) == "D" and TIER.pressure(50) == "D", "pressure: B to 25, C 26-30, D from 31")
pr.preset[2] = "Z"
check(TIER.pressure(31) == "C", "a preset letter the build doesn't have is skipped")
pr.preset[2] = "D"
pr.enabled = false
check(TIER.pressure(31) == nil, "pressure off: nothing")
pr.enabled = true

---------------------------------------------------------------------------------------------------- startRound
print("startRound on its real code")
CFG.airfield.enabled = false                          -- (normal rounds without bombers: the table's waves)
CFG.specials.enabled = false
local function fresh(round)
    planes = {}
    D = { round = round - 1, startRound = 1, state = "wait", at = 0, now = 1000, up = {}, flown = {}, queue = {}, spare = {},
          events = {}, pressure = D and D.pressure }
end
local function play(round)                             -- one startRound: the budget, the wave cap, aircraft picked, waves
    local from = #logs + 1
    D.round, D.state = round - 1, "wait"
    D.up = {}
    startRound()
    local picked, biggest = 0, 0
    for _, w in ipairs(D.waves) do
        local n = 0
        for _, u in ipairs(w) do if u:sub(1, 1) ~= "@" then n = n + flightSize(u) end end
        picked, biggest = picked + n, math.max(biggest, n)
    end
    local l = nil                                      -- (its start line: "round N: X aircraft: ...")
    for i = from, #logs do if logs[i]:find("^round " .. round .. ": %d+ aircraft:") then l = logs[i] end end
    local cap = l and tonumber(l:match("up to (%d+) at once"))
    local short = false
    for i = from, #logs do if logs[i]:find("pool short", 1, true) then short = true end end
    return { budget = D.budget, cap = cap, picked = picked, waves = #D.waves, biggest = biggest, short = short, line = l }
end
local function sample(round, runs)
    local s = { waves = {}, picked = {}, budget = nil, cap = nil, overCap = 0, short = 0, runs = runs }
    for _ = 1, runs do
        fresh(round)
        local r = play(round)
        s.budget, s.cap = r.budget, r.cap
        s.waves[r.waves] = (s.waves[r.waves] or 0) + 1
        s.picked[r.picked] = (s.picked[r.picked] or 0) + 1
        if r.biggest > r.cap then s.overCap = s.overCap + 1 end
        if r.short then s.short = s.short + 1 end
    end
    return s
end
local function mode(t) local best, bn = nil, -1; for k, n in pairs(t) do if n > bn then best, bn = k, n end end; return best end
local function dist(t)
    local ks, out = {}, {}
    for k in pairs(t) do ks[#ks + 1] = k end
    table.sort(ks)
    for _, k in ipairs(ks) do out[#out + 1] = string.format("%d x%d", k, t[k]) end
    return table.concat(out, ", ")
end
local function share(t, k, runs) return (t[k] or 0) / runs end
local RUNS = 300
local WANT_WAVES = { [25] = 2, [28] = 2, [31] = 2, [35] = 3 }   -- the table's "Waves (Standard, about)"
local PICK = { [25] = 30, [28] = 38, [31] = 48, [35] = 60 }   -- (whole 2 / 4 / 6-ships: an odd budget loses 1)
for _, p in ipairs({ "casual", "standard", "ace" }) do
    PRESET = p
    for _, r in ipairs(TABLE) do
        local s = sample(r[1], RUNS)
        local up = r[p == "casual" and 3 or p == "standard" and 4 or 5]
        print(string.format("    %-8s round %d: budget %d, up to %d at once; picked %s; waves %s%s", p, r[1], s.budget, s.cap,
            dist(s.picked), dist(s.waves), s.short > 0 and string.format("; pool short x%d", s.short) or ""))
        check(s.budget == r[2] and s.cap == up and s.overCap == 0,
              string.format("%s round %d: D.budget %d, the log's wave cap %d, no wave over it", p, r[1], r[2], up))
        check(mode(s.picked) == PICK[r[1]] and share(s.picked, PICK[r[1]], RUNS) >= 0.85 and s.short <= RUNS * 0.15,
              string.format("%s round %d: %d aircraft picked (%.0f %% of runs)", p, r[1], PICK[r[1]], 100 * share(s.picked, PICK[r[1]], RUNS)))
        if p == "standard" then
            local w = WANT_WAVES[r[1]]
            check(mode(s.waves) == w or (r[1] == 31 and share(s.waves, 2, RUNS) >= 0.3), string.format(
                  "standard round %d: about %d waves (%s)", r[1], w, dist(s.waves)))
        end
        local most = 0
        for k in pairs(s.waves) do most = math.max(most, k) end
        check(most <= (p == "casual" and 4 or 3), string.format("%s round %d: at most %d waves", p, r[1], p == "casual" and 4 or 3))
    end
end
PRESET = "standard"
check(share(sample(25, 100).waves, 2, 100) == 1, "standard round 25: always 2 waves (30 aircraft, 18 up)")
check(share(sample(35, 100).waves, 3, 100) == 1, "standard round 35: always 3 waves (60 aircraft, 26 up)")

print("the menu's ENEMY AIRCRAFT % (cap -> % -> co-op)")
for _, c in ipairs({ { 0.5, 30, 13 }, { 1.5, 90, 39 }, { 2.0, 120, 52 } }) do
    ENEMY_X = c[1]
    local s = sample(35, 40)
    local maxPicked = 0
    for k in pairs(s.picked) do maxPicked = math.max(maxPicked, k) end
    check(s.budget == c[2] and s.cap == c[3] and maxPicked <= 86,
          string.format("%d %%: round 35 asks %d, %d up at once; at most 86 picked (the pool)", c[1] * 100, c[2], c[3]))
    if c[1] > 1 then check(s.short == 40, string.format("%d %%: the 'pool short' line every time", c[1] * 100)) end
end
check(has(line("round 35: pool short:"), "fighters (") , "the pool short line: '" .. tostring(line("round 35: pool short:")) .. "'")
ENEMY_X = 1.5                                          -- an amphibious round above 100 %: capped first, then the %
fresh(20); D.forceSpecial = "amphibious"
local am = play(20)
check(am.budget == 45, "amphibious round 20 at 150 %: 45 (min(30 + 4, 30) x 1.5; was cut back to 30)")
ENEMY_X = 1
fresh(30); D.forceSpecial = "amphibious"
check(play(30).budget == 45, "amphibious round 30 at 100 %: within the round's cap 45")

print("co-op (COOP.more, 4 players)")
COOP.open, COOP.role = true, "host"
M.roster = { [0] = {}, [1] = {}, [2] = {}, [3] = {} }
for _, c in ipairs({ { "standard", 25, 44, 26 }, { "standard", 35, 80, 30 }, { "ace", 35, 80, 30 }, { "casual", 31, 70, 29 } }) do
    PRESET = c[1]
    fresh(c[2])
    local r = play(c[2])
    check(r.budget == c[3] and r.cap == c[4], string.format("%s round %d: %d aircraft, %d up at once (%d / %d)", c[1], c[2], c[3], c[4],
        r.budget, r.cap))
end
local function room(n) M.roster = {}; for s = 0, n - 1 do M.roster[s] = {} end end
PRESET = "standard"
for _, c in ipairs({ { 12, 20, 60, 30 }, { 24, 25, 60, 30 }, { 12, 28, 69, 30 }, { 24, 35, 80, 30 } }) do
    room(c[1])                                         -- (the review: 30 x 2.65 = 80 at round 20 with the flat 80)
    fresh(c[2])
    local r = play(c[2])
    check(r.budget == c[3] and r.cap == c[4], string.format("%d players, round %d: %d aircraft (the room's cap %d), %d up (%d / %d)",
        c[1], c[2], c[3], TIER.coopCap(c[2]), c[4], r.budget, r.cap))
end
M.roster = { [0] = {} }
fresh(35)
local solo = play(35)
check(solo.budget == 60 and solo.cap == 26, "host alone: one player's 60 and 26")
COOP.open, COOP.role = false, nil

---------------------------------------------------------------------------------------------------- the attack throttle
print("the attack throttle (RE_SV_Pressure)")
local function pressureRound(round, special)
    local from, ev = #logs + 1, #events
    D.forceSpecial = special
    play(round)
    local fired = {}
    for i = ev + 1, #events do if events[i]:find("^RE_SV_Pressure") then fired[#fired + 1] = events[i] end end
    local pl = nil
    for i = from, #logs do if logs[i]:find("^pressure:") then pl = logs[i] end end
    return table.concat(fired, ","), pl
end
D = nil
fresh(25)
local f, pl = pressureRound(25)
check(f == "RE_SV_PressureB" and D.pressure == "B" and pl == "pressure: round 25: preset B (was not known: the run's first round)",
      "a run's first round (25): its preset fired even when it's B (" .. tostring(pl) .. ")")
f, pl = pressureRound(25)
check(f == "" and pl == nil, "round 25 again: B in force, nothing fired")
f, pl = pressureRound(26)
check(f == "RE_SV_PressureC" and D.pressure == "C" and pl == "pressure: round 26: preset C (was B)", "round 26: preset C fired (" .. tostring(pl) .. ")")
f, pl = pressureRound(27)
check(f == "" and pl == nil, "round 27: C in force, nothing fired")
f, pl = pressureRound(28, "anomaly")
check(f == "" and D.pressure == "B" and has(pl, "round 28 is the anomaly's: its own throttle, then preset B; preset C again once it's down"),
      "an Anomaly round: none fired, B after it (" .. tostring(pl) .. ")")
local function afterBoss(now)                          -- pressureAfterBoss at `now`: the events it fired, its log line
    local from, ev = #logs + 1, #events
    pressureAfterBoss(now)
    local fired = {}
    for i = ev + 1, #events do fired[#fired + 1] = events[i] end
    local l = nil
    for i = from, #logs do if logs[i]:find("^pressure:") then l = logs[i] end end
    return table.concat(fired, ","), l
end
check(afterBoss(2000) == "" and D.special.pressureAt == nil, "the boss up: nothing")
D.special.state = "done"
f = afterBoss(2000)
check(f == "" and D.special.pressureAt == 2003, "the boss down: nothing yet (its records put B back first)")
f = afterBoss(2002.9)
check(f == "", "2.9 s later: nothing yet")
f, pl = afterBoss(2003)
check(f == "RE_SV_PressureC" and D.pressure == "C" and pl == "pressure: round 28: preset C (was B, the anomaly is down)",
      "3 s after the boss is down: the band's C again (" .. tostring(pl) .. ")")
check(afterBoss(2010) == "" and D.special.pressureAt == false, "once a special")
f, pl = pressureRound(29)
check(f == "" and D.pressure == "C", "the round after it: C already in force, nothing fired")
pressureRound(29, "anomaly")
D.special.state = "done"
afterBoss(3000)
f = afterBoss(3003)
check(f == "RE_SV_PressureC", "a boss round inside band C, its boss down: C again")
pressureRound(24, "anomaly")
D.special.state = "done"
afterBoss(3100)
f = afterBoss(3103)
check(f == "" and D.pressure == "B", "a boss round in band B: nothing after it (B is what its records put back)")
D.special = { kind = "ladon", state = "done" }
check(afterBoss(3200) == "" and afterBoss(3203) == "" and D.special.pressureAt == nil, "a Ladon round: not its business")
pressureRound(29)
check(D.pressure == "C", "(round 29 again: C)")
f, pl = pressureRound(30, "valka")
check(f == "" and D.pressure == "B" and has(pl, "is the valka's"), "a VALKA round (disguised as a normal one): none fired")
-- (VALKA never seen down here: the next round fires the band's preset)
f, pl = pressureRound(31)
check(f == "RE_SV_PressureD" and D.pressure == "D" and has(pl, "preset D (was B)"), "round 31: D")
pressureRound(32)
D.pressure, eventResult = "C", -3
f, pl = pressureRound(33)
check(f == "RE_SV_PressureD" and D.pressure == "C" and has(pl, "RE_SV_PressureD not fired: " .. SV_ERR[-3]),
      "a failed fire: kept as not in force, logged (" .. tostring(pl) .. ")")
eventResult = 1
f = pressureRound(34)
check(f == "RE_SV_PressureD" and D.pressure == "D", "fired again the next round")
pr.enabled = false
D.pressure = nil
f, pl = pressureRound(35)
check(f == "" and pl == nil and D.pressure == nil, "[late.pressure] off: nothing fired")
pr.enabled = true
D, eventResult = nil, -3                               -- a run's first round whose fire fails: tried again the next
fresh(5)
f, pl = pressureRound(5)
check(f == "RE_SV_PressureB" and D.pressure == nil and has(pl, "not fired"), "a failed first-round fire: still not known")
eventResult = 1
f, pl = pressureRound(6)
check(f == "RE_SV_PressureB" and D.pressure == "B", "fired again the next round")
-- co-op: forwarded (not in KEEP_EVENTS), and the one in force re-sent to a joiner who links later
check(mirroredEvent("RE_SV_PressureC") == true and mirroredEvent("RE_SV_AceTurn_03") == false,
      "RE_SV_Pressure* is forwarded to the joiners (the contract's table)")
COOP.open, COOP.role = true, "host"
M.roster = { [0] = {}, [1] = {} }
sent = {}
D.pressure = nil
pressureRound(26)
local fwd = false
for _, s in ipairs(sent) do if s == "-1>ev|RE_SV_PressureC" then fwd = true end end
check(fwd, "the host's fire goes to every joiner as ev|RE_SV_PressureC")
sent = {}
hostSync(1)
local resent = false
for _, s in ipairs(sent) do if s == "1>ev|RE_SV_PressureC" then resent = true end end
check(resent, "hostSync: a joiner who links later gets the preset in force")
local function synced()                                -- what hostSync(1) sends of the throttle
    sent = {}
    hostSync(1)
    local out = {}
    for _, s in ipairs(sent) do if s:find("RE_SV_Pressure", 1, true) then out[#out + 1] = s end end
    return table.concat(out, ",")
end
D.pressure = "B"
check(synced() == "1>ev|RE_SV_PressureB", "hostSync: B in force is sent too (a kept level may be on an earlier run's D)")
D.pressure = nil
check(synced() == "1>ev|RE_SV_PressureB", "hostSync: nothing known yet (before round 1): B")
D.pressure, D.special = "B", { kind = "anomaly", state = "hunt" }
check(synced() == "", "hostSync: nothing while the Anomaly is up (its own throttle)")
D.special.state = "done"
check(synced() == "1>ev|RE_SV_PressureB", "hostSync: its boss down: the one in force")
D.special = nil
pr.enabled = false
check(synced() == "", "hostSync: [late.pressure] off: nothing")
pr.enabled = true
-- the review's repro: the host's run starts over after round 31 (host and joiners on D), the levels kept
D = nil
fresh(31)
pressureRound(31)
check(D.pressure == "D", "(the host on D after round 31)")
sent = {}
D = nil                                                 -- a new run: sv_main.lua's new D, "rs" to the joiners
fresh(1)
local ev0 = #events
for r = 1, 5 do pressureRound(r) end
local again, fwdB = {}, 0
for i = ev0 + 1, #events do if events[i]:find("^RE_SV_Pressure") then again[#again + 1] = events[i] end end
for _, s in ipairs(sent) do if s == "-1>ev|RE_SV_PressureB" then fwdB = fwdB + 1 end end
check(table.concat(again, ",") == "RE_SV_PressureB" and fwdB == 1,
      "a restart after round 31: round 1 fires B, once, and every joiner gets it (" .. table.concat(again, ",") .. ")")
check(synced() == "1>ev|RE_SV_PressureB", "a joiner who links after the restart gets B")
COOP.open, COOP.role, M.roster = false, nil, { [0] = {} }

---------------------------------------------------------------------------------------------------- the director's kill bonus
print("the director kill bonus (creditKill)")
local mainSrc = readAll(MOD .. "/Scripts/sv_main.lua")
local cA, cB = mainSrc:find("\nlocal function creditKill%(p%)"), mainSrc:find("\nlocal function timed%(")
check(cA and cB and cA < cB, "sv_main.lua: creditKill found")
local creditKill = assert(load(mainSrc:sub(cA, cB) .. "\nreturn creditKill\n", "=sv_main.lua"))()
fresh(30)
D.now, D.special = 1000, nil
local veteran = CFG.tiers.list[3]
local nextAddr = 0x2000
local function kill(tag, dmg)
    nextAddr = nextAddr + 0x10
    local p = { name = "BP_OP1022_f16c_CP_C_" .. nextAddr, full = "BP_OP1022_f16c_CP_C", unit = "ERA_Unit_03_Dep_Air1", tier = veteran,
                dmg = dmg or { you = 100 }, dirTag = tag, addr = nextAddr }
    local before = RUN.credits
    local by = creditKill(p)
    return RUN.credits - before, line("credits: +"), by
end
local plain = kill(nil)
check(plain == 190, "an untagged kill, round 30, Veteran: 190 (100 x round 1.5 x 1.25)")
local n, l = kill({ tactic = "bracket", at = 995 })
check(n == 280 and has(l, ", director bracket x1.5)"), "tagged 5 s before: 280 (x1.5) '" .. tostring(l) .. "'")
n = kill({ tactic = "trap", at = 980 })
check(n == 280, "tagged exactly tag_s (20 s) before: paid")
n, l = kill({ tactic = "trap", at = 975 })
check(n == 190 and not has(l, "director"), "tagged 25 s before: no bonus")
n, l = kill({ tactic = "bracket", at = 995 }, { allies = 100 })
check(n == 90 and not has(l, "director"), "an ally's kill of a tagged plane: no bonus (its ally_x only)")
n = kill("bracket")
check(n == 190, "a bare string tag (not the contract's): no bonus")
CFG.late.director_pay.enabled = false
n = kill({ tactic = "bracket", at = 995 })
check(n == 190, "[late.director_pay] off: no bonus")
CFG.late.director_pay.enabled = true
CFG.late.enabled = false
n = kill({ tactic = "bracket", at = 995 })
check(n == 280, "[late] off: the bonus still pays (any round)")
CFG.late.enabled = true
-- end to end with unit 1's STATS.tactic: it tags the unit's live planes { tactic, at = D.now }
local unit = "ERA_Unit_05_Dep_Air1"
local p1 = { name = "BP_OP1022_su33_CP_C_1", full = "BP_OP1022_su33_CP_C", unit = unit, tier = veteran, dmg = { you = 50 }, addr = 0x3001 }
planes = { p1 }
D.now = 1200
STATS.tactic("trap", unit, nil, "test")
check(type(p1.dirTag) == "table" and p1.dirTag.tactic == "trap" and p1.dirTag.at == 1200, "STATS.tactic tags the plane { tactic, at }")
D.now = 1212
local before = RUN.credits
creditKill(p1)
check(RUN.credits - before == 280 and has(line("credits: +"), "director trap x1.5"), "its kill 12 s later pays the bonus")

---------------------------------------------------------------------------------------------------- the hooks, by their place
print("the hooks in the source")
local function body(name, from)
    local src = readAll(MOD .. "/Scripts/" .. name)
    local a = src:find(from)
    if not a then return "" end
    local b = src:find("\nend\n", a, true) or src:find("\nend\r\n", a, true) or #src
    return src:sub(a, b)
end
local sr = body("sv_rounds.lua", "\nlocal function startRound%(%)")
-- (the spike level the intensity director's, levelFor: unit 7, P4)
check(has(sr, "TIER.roundBudget(D.round, levelFor(D.round))") and has(sr, "waveCap(D.round)") and has(sr, "pcall(roundPressure, special)")
      and has(sr, 'COOP.more(budget, "max_aircraft", TIER.coopCap(D.round))') and has(sr, 'COOP.more(cap, "max_up")'),
      "startRound: the helpers, co-op (the room's cap by round) and the throttle")
check(has(body("sv_rounds.lua", "\nfunction roundsTick%(now%)"), "pressureAfterBoss(now)"), "roundsTick: pressureAfterBoss every tick")
local menuSrc = readAll(MOD .. "/Scripts/sv_menu.lua")
check(has(menuSrc, "roundN(35, 1)"), "the ENEMY AIRCRAFT help names round 35's (TIER.roundBudget)")
local mA = menuSrc:find("\nlocal function roundN%(r, x%)")
local mB = mA and menuSrc:find("\nend\n", mA, true)
local roundN = mA and mB and assert(load(menuSrc:sub(mA, mB + 4) .. "return roundN\n", "=sv_menu.lua"))()
check(roundN and roundN(35, 1) == 60 and roundN(10, 2) == 48 and roundN(35, 1.5) == 86 and roundN(35, 2) == 86 and roundN(35, 0.5) == 30,
      "the help's numbers: round 35 at 100 % 60, at 50 % 30, at 150 % and 200 % the pool's 86 (not 90 / 120); round 10 at 200 % 48")

logFile:close()
print(fails == 0 and "late rounds test: all passed" or ("late rounds test: " .. fails .. " FAILED"))
os.exit(fails == 0 and 0 or 1)
