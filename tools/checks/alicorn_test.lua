-- alicorn_test.lua <mod dir> <work dir> (run by tools/checks/alicorn_test.sh): the Alicorn in co-op after Saint Alessia's
-- 50-round run (2026-11-11, round 45: "alicorn desync, was invulnerable to Delta, Acorn relogged, shot the water a bit on
-- my end, suddenly alicorn destroyed"), on the real sv_core, sv_config, sv_rows, sv_ai, sv_spawn, sv_anomalies,
-- sv_rounds, sv_ladon, sv_alicorn, sv_stats, sv_tells and sv_coop with its pieces (M, onJoinerMessage exposed), the game
-- stubbed as it behaves (ModifyHealth moves health, stops at 0 and does nothing to an invincible object; a forwarded event
-- does what its stub records):
--   the host's core: its health at opening, each hit logged as the tanks' (one while shut too), CORE n% on the NEXT row
--     (SPC.alicornRow) and in "rnd" field 16 (SPC.alicornCode), a callout as it drops past 75 / 50 / 25 % (once each, the
--     lowest crossed only), none at its sink;
--   its core's size as it opens (the user, 2026-11-11): core_missiles + core_missiles_per_player for each other player
--     flying (solo; a co-op host alone, with 2 and 3 others; others down at their airfield, shot down or not heard from;
--     the host DOWN or down at the airfield), x the round's growth, split across its parts, CORE 100% that health, no hit
--     logged for it, in the host's next "hp" and on a joiner's copy; its health as it was when the missile's damage
--     can't be read or core_missiles is 0;
--   its hull: the way it sails from its moves, its place in the log every 30 s; the leg from each place on the lane
--     (SPC.alicornLegOf: the first waypoint 300 m or more ahead, the other way's whole leg at an end), the rejoiner's pose
--     and leg (SPC.alicornRejoin), the spawn back at the lane's start after one at a pose (SPC.alicornPose);
--   the host's co-op: hostSync's "sp" for a rejoiner at the hull, its leg 2 s on and its open core 12 s on; the joiners'
--     hits tallied a player a minute (taken, refused, dropped; the Alicorn's core apart), a special's part down logged
--     with the player its "dn" names;
--   a joiner: the host's row from "rnd" field 16 (hostile ones: none; 5 s old: none), the host's health kept for a copy
--     not bound yet and put on it as it's bound (forgotten at a new "gd" or a "dn"), its copy's surfacing checked and
--     ordered here (COOP.eventHere) up to resurface_tries times, the host's replay held until its copy's up, its spawn
--     at the host's hull (and back at the lane's start after it), its launches at a target with no co-op id counted.
local MOD, WORK = arg[1], arg[2]
local fails = 0
local function check(ok, what) if ok then print("  ok   " .. what) else print("  FAIL " .. what); fails = fails + 1 end end
local function readAll(p) local f = assert(io.open(p, "rb")); local s = f:read("a"); f:close(); return s end
local PARTS = dofile("parts.lua")(MOD, readAll)            -- (a part and its pieces: tools/checks/parts.lua)
local function writeAll(p, s) local f = assert(io.open(p, "wb")); f:write(s); f:close() end
local function has(s, part) return s ~= nil and s:find(part, 1, true) ~= nil end
do                                    -- (the runtime's paths are Windows ones: SCRIPT_DIR .. "..\\config\\")
    local rawOpen = io.open
    io.open = function(p, m) return rawOpen((tostring(p):gsub("\\", "/")), m) end
end
local defaultIni = readAll(MOD .. "/config/survival.default.ini")
writeAll(WORK .. "/config/survival.default.ini", defaultIni)
writeAll(WORK .. "/config/survival.ini", defaultIni)

local clock = 1000
os.clock = function() return clock end           -- luacheck: ignore

-- the game's world, stubbed (as tools/checks/bosses_test.lua's)
VERSION = "0.74.51-alicorn.test"
local FNm = { __index = { ToString = function(self) return self.s end }, __tostring = function(self) return self.s end }
function FName(s) return setmetatable({ s = tostring(s) }, FNm) end
local GI = { full = "GameInstance", addr = 1 }
function NotifyOnNewObject() end
local FA = {}
function FindAllOf(c) return FA[c] or {} end
function FindFirstOf(c) if c == "BP_LiveGameInstance_C" then return GI end return nil end
function StaticFindObject() return nil end
local grounded = false
function playerOnAirfield() return grounded end
function airfieldTick() end
function bombTick() end
local events = {}
function SV_Event(name) events[#events + 1] = name; return 1 end
local alive = {}
function SV_UnitAlive(u) return alive[u] or 0 end
function SV_SetAircraft() return 1 end
function SV_SetLevel() return 1 end
function SV_Invert() return 1 end
local spawns = {}
function SV_Spawn(unit, x, y, z, yaw) spawns[#spawns + 1] = { unit = unit, x = x, y = y, z = z, yaw = yaw }; return 1 end
function SV_MenuChoice() return 0 end
function SV_CoopOpen() return 1 end
function SV_CoopClose() end
local sent = {}
function SV_CoopSend(msg, rel, to) sent[#sent + 1] = (to and to >= 0 and (to .. ">") or "") .. msg; return 1 end
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
local callouts = {}
function hudCallout(text, sub, big) callouts[#callouts + 1] = { text = text, sub = sub, big = big } end

local function part(name, chunk, edits) PARTS.load(name, chunk, edits) end
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
hudCallout = function(text, sub, big) callouts[#callouts + 1] = { text = text, sub = sub, big = big } end
SND = { ids = {}, live = {} }
for _, k in ipairs({ "preloadValka", "tick", "set", "stop", "songStart", "songFade", "songStop" }) do SND[k] = function() end end
function SND.event() return {} end
function SND.play() return nil end
part("sv_spawn.lua"); part("sv_anomalies.lua")
part("sv_rounds.lua")
part("sv_ladon.lua"); part("sv_alicorn.lua"); part("sv_stats.lua"); part("sv_tells.lua")
part("sv_coop.lua", nil, { { "\nlocal M = {", "\nM = {" },
                           { "\nlocal function onJoinerMessage%(f%)", "\nfunction onJoinerMessage(f)" } })
function searchAircraft(a) return a end
function playerOnAirfield() return grounded end
function addCredits() end
LB.stat, LB.special = function() end, function() end
local M = _G.M
local AL = CFG.specials.alicorn
local T = CFG.hud.text
AL.deck.enabled = false                                    -- (its deck: bosses_test.lua)
local UNIT = SPC.alicornUnit

local function line(prefix, from)
    for i = #logs, from or 1, -1 do if logs[i]:sub(1, #prefix) == prefix then return logs[i] end end
    return nil
end
local function lines(prefix, from)
    local n = 0
    for i = from or 1, #logs do if logs[i]:sub(1, #prefix) == prefix then n = n + 1 end end
    return n
end
local function KM(x, y, z) return { X = x * 100000, Y = y * 100000, Z = (z or 0) * 100000 } end
local nextAddr = 100
local function mkObj(full, at, fwd, hp)
    nextAddr = nextAddr + 1
    local o = { full = full, addr = nextAddr, at = at, fwd = fwd or { X = 1, Y = 0, Z = 0 }, HealthInternal = hp or 4500 }
    function o:K2_GetActorLocation() return { X = self.at.X, Y = self.at.Y, Z = self.at.Z } end
    function o:GetActorForwardVector() return self.fwd end
    -- (as the game's: ModifyHealth in health (x 10 here), stopped at 0, nothing on an invincible object)
    function o:ModifyHealth(d) if not self.invincible then self.HealthInternal = math.max(0, self.HealthInternal + d * 10) end end
    return o
end
local function run(round) D = { round = round or 45, state = "fighting", now = 0, up = {}, flown = {}, queue = {}, spare = {} } end
local tanks, core, hull
local function alicornRound()
    run(45)
    tanks = {}
    for i, cls in ipairs(AL.tank_classes) do
        tanks[i] = mkObj(cls .. "_" .. i, KM(-20, -5.5), nil, 8784)
        FA[cls] = { tanks[i] }
    end
    core = mkObj(AL.core_class .. "_1", KM(-20, -5.5), { X = 1, Y = 0, Z = 0 }, 31250)   -- (scaled x0.92 at round 45: 28594)
    FA[AL.core_class] = { core }
    hull = mkObj("BP_BA002_alcn_N000_00100_C_1", KM(-20.1, -5.5), { X = 1, Y = 0, Z = 0 }, 100)
    SPC.CLEAN_OBJ[UNIT] = { at = clock, hull, core, tanks[1], tanks[2], tanks[3], tanks[4] }
    alive[UNIT] = 1
    D.special = { kind = "alicorn", state = "sail", at = 0, tanks = 4, coreOpen = false, dived = false,
                  nextDive = 1e9, nextRail = 1e9, nextVolley = 1e9 }
    events, callouts, spawns, sent = {}, {}, {}, {}
    return D.special
end
local function tickA(from, to)
    for t = from, to do D.now = t; SPC.alicornTick(t, D.special) end
end
local function called(text, from)
    local t = {}
    for i = from or 1, #callouts do if callouts[i].text == text then t[#t + 1] = callouts[i] end end
    return t
end

---------------------------------------------------------------------------------------------------- the host's core
print("the host's core: its hits, CORE n% on the row and in rnd, its callouts")
local s = alicornRound()
tickA(0, 12)                                              -- (the parts pass every 2 s; the missile's damage tried 5 times)
check(s.coreLast == 28594 and s.corePct == nil, "shut: its health read (28594), no percentage")
check(SPC.alicornRow(T) == "ALICORN: BALLAST TANKS 4/4  CORE SHUT" and SPC.alicornCode() == "4:s:0",
      "the row and rnd field 16 while shut: " .. tostring(SPC.alicornRow(T)) .. " / " .. SPC.alicornCode())
local f0 = #logs + 1
core.HealthInternal = 28000                               -- (a hit while shut)
tickA(13, 14)
check(has(line("special: Alicorn core hit:", f0), "-594 (28000 left, its core still shut)"), "a hit on it while shut logged: "
      .. tostring(line("special: Alicorn core hit:", f0)))
for _, o in ipairs(tanks) do o.HealthInternal = 0 end
f0 = #logs + 1
tickA(15, 16)
check(s.coreOpen and s.coreFull == 28000 and s.corePct == 100 and has(line("special: the Alicorn's core open with 28000 health", f0), "CORE 100%"),
      "the tanks gone: its core open, its health then its 100 % (logged)")
check(SPC.alicornRow(T) == "ALICORN: BALLAST TANKS 0/4  CORE 100%" and SPC.alicornCode() == "0:100:0",
      "the row: CORE 100% (" .. tostring(SPC.alicornRow(T)) .. ")")
local c0 = #callouts
core.HealthInternal = 21000                               -- (75 % of 28000)
f0 = #logs + 1
tickA(17, 18)
check(has(line("special: Alicorn core hit:", f0), "-7000 (21000 left, 75%)") and s.corePct == 75, "a hit on the open core logged with its % left")
check(#called(string.format(T.alicorn_core_left, 75), c0 + 1) == 1 and has(line("special: the Alicorn's core at 75%", f0), "(under 75%)"),
      "75 %: called out once (" .. tostring(T.alicorn_core_left) .. ")")
core.HealthInternal = 20000
tickA(19, 22)
check(#callouts == c0 + 1, "... not again at 71 %")
core.HealthInternal = 2800                                -- (10 %: past 50 and 25 at once)
f0 = #logs + 1
tickA(23, 24)
check(#callouts == c0 + 2 and callouts[#callouts].text == string.format(T.alicorn_core_left, 10)
      and has(line("special: the Alicorn's core at 10%", f0), "(under 25%)") and s.coreCalled[50] and s.coreCalled[25],
      "past 50 % and 25 % in one hit: one callout, the 10 % it's at")
check(SPC.alicornRow(T) == "ALICORN: BALLAST TANKS 0/4  CORE 10%" and SPC.alicornCode() == "0:10:0", "the row and rnd: 10 %")
core.HealthInternal = 3                                   -- (under half a percent: 1 %, never 0 while it's up)
tickA(25, 26)
check(s.corePct == 1 and s.state == "sail", "under half a percent: 1 % while it's up")
s.dived = true
check(SPC.alicornCode() == "0:1:1" and SPC.alicornRow(T):find("(DIVED)", 1, true), "dived: in rnd and on the row")
s.dived = false
core.HealthInternal = 0
c0 = #callouts
tickA(27, 28)
check(s.state == "done" and #called(string.format(T.alicorn_core_left, 0), c0 + 1) == 0 and SPC.alicornCode() == "",
      "sunk: no core callout, nothing in rnd any more")
-- the old row's behaviour without health: an unreadable core once open reads EXPOSED
s = alicornRound()
tickA(0, 12)
for _, o in ipairs(tanks) do o.HealthInternal = 0 end
core.HealthInternal = nil
tickA(13, 14)
check(s.coreOpen and SPC.alicornRow(T) == "ALICORN: BALLAST TANKS 0/4  CORE EXPOSED" and SPC.alicornCode() == "0:e:0",
      "its core's health unreadable: EXPOSED, \"e\" in rnd")

---------------------------------------------------------------------------------------------------- the core's size
-- (the user, 2026-11-11: "Yes add the alicorns core size") core_missiles for one player, core_missiles_per_player for each
-- other player flying as it opens, x the round's growth as the tanks' (round 45: x3.05); 48 damage a missile here
print("the core sized by the players flying as it opens")
local MSL = { full = "BP_plwp_msl_f0_C_1", addr = 90, damage = 48 }
local GROWTH = 0.915 / 0.3                                -- (hx / health_x at round 45)
local function sized(n) return math.floor(n * 48 * 10 * GROWTH + 0.5) end
local function peer(slot, alive_, fresh, onAirfield)
    M.peers[slot] = { at = KM(-15, -5, 2), alive = alive_, fresh = fresh, onAirfield = onAirfield, flags = 1 }
end
-- open its core after the round's first passes (the tanks found and sized, the missile's damage read); the core's health
-- then, and the log from its opening
local function openCore(cores)
    s = alicornRound()
    if cores then
        FA[AL.core_class] = cores
        SPC.CLEAN_OBJ[UNIT] = { at = clock, hull, cores[1], cores[2], tanks[1], tanks[2], tanks[3], tanks[4] }
        core = cores[1]
    end
    tickA(0, 12)
    for _, o in ipairs(tanks) do o.HealthInternal = 0 end
    local from = #logs + 1
    tickA(13, 14)
    return from
end
FA.LiveMissile = { MSL }
f0 = openCore()
check(core.HealthInternal == sized(30) and s.coreFull == sized(30) and s.corePct == 100
      and has(line("special: the Alicorn's core sized:", f0), "sized: 30 missiles (30 + 10 x 0 other players flying), " .. sized(30) .. " health"),
      "solo: 30 missiles x3.05 (" .. tostring(core.HealthInternal) .. "; " .. tostring(line("special: the Alicorn's core sized:", f0)) .. ")")
check(SPC.alicornRow(T) == "ALICORN: BALLAST TANKS 0/4  CORE 100%" and SPC.alicornCode() == "0:100:0"
      and has(line("special: the Alicorn's core open with " .. sized(30) .. " health", f0), "CORE 100%"),
      "CORE 100% is the sized core (its row, rnd, the log)")
check(line("special: Alicorn core hit:", f0) == nil, "its sizing isn't logged as a hit")
core.HealthInternal = math.floor(sized(30) * 0.74)
tickA(15, 16)
check(s.corePct == 74 and #called(string.format(T.alicorn_core_left, 74)) == 1, "a hit to 74 % of the sized core: 74 %, called out")
-- a co-op host: itself and the others flying (alive, fresh, not down at the airfield)
COOP.open, COOP.role, COOP.slot = true, "host", 0
M.peers = {}
f0 = openCore()
check(core.HealthInternal == sized(30) and has(line("special: the Alicorn's core sized:", f0), "(30 + 10 x 0 other players flying)"),
      "a co-op host flying alone: 30")
M.peers = {}; peer(1, true, true, false); peer(2, true, true, false)
f0 = openCore()
check(core.HealthInternal == sized(50) and has(line("special: the Alicorn's core sized:", f0), "50 missiles (30 + 10 x 2 other players flying)"),
      "3 flying: 50 (" .. tostring(line("special: the Alicorn's core sized:", f0)) .. ")")
peer(3, true, true, false)
f0 = openCore()
check(core.HealthInternal == sized(60) and s.coreFull == sized(60) and has(line("special: the Alicorn's core sized:", f0), "60 missiles (30 + 10 x 3 other players flying)"),
      "4 flying: 60")
peer(4, true, true, true); peer(5, false, true, false); peer(6, true, false, false)
f0 = openCore()
check(core.HealthInternal == sized(60), "... one more down at their airfield, one shot down, one not heard from: still 60")
local DOWN0 = DOWN
DOWN = { me = function() return true end }
f0 = openCore()
check(core.HealthInternal == sized(50) and has(line("special: the Alicorn's core sized:", f0), "(30 + 10 x 2 other players flying)"),
      "the host DOWN, 3 others flying: 50 (" .. tostring(line("special: the Alicorn's core sized:", f0)) .. ")")
DOWN = DOWN0
grounded = true
f0 = openCore()
check(core.HealthInternal == sized(50), "the host down at the airfield, 3 others flying: 50")
grounded = false
M.peers = {}; peer(1, true, true, false)
f0 = openCore()
check(has(line("special: the Alicorn's core sized:", f0), "(30 + 10 x 1 other player flying)") and core.HealthInternal == sized(40),
      "2 flying: 40, \"1 other player\"")
-- its health reaches the joiners: the host's next "hp" for its core's id
M.units, M.byId, M.replays = {}, {}, {}
M.units[UNIT] = { gen = 7, n = 0, planes = {}, ground = { ["BP_MP028_dummy_emlmcore_Base_C#1"] = { id = 2161 } }, at = clock }
s = alicornRound()
M.byId[2161] = { obj = core, unit = UNIT, key = "BP_MP028_dummy_emlmcore_Base_C#1", addr = core.addr, sentHp = 28594 }
tickA(0, 12)
for _, o in ipairs(tanks) do o.HealthInternal = 0 end
tickA(13, 14)
sent, M.nextHp = {}, clock
hostTick()
local hpMsg
for _, m in ipairs(sent) do if m:find("^hp|") then hpMsg = m end end
check(hpMsg and has(hpMsg, "2161:" .. sized(40)), "the sized core in the host's next hp, for the joiners' copies (" .. tostring(hpMsg) .. ")")
COOP.open, COOP.role, COOP.slot = false, nil, nil
M.peers, M.units, M.byId = {}, {}, {}
-- two core parts: the total split; a smaller core: no false hit
local cA = mkObj(AL.core_class .. "_1", KM(-20, -5.5), nil, 31250)
local cB = mkObj(AL.core_class .. "_2", KM(-20, -5.5), nil, 31250)
f0 = openCore({ cA, cB })
local half = math.floor(sized(30) / 2 + 0.5)
check(cA.HealthInternal == half and cB.HealthInternal == half and s.coreFull == 2 * half
      and has(line("special: the Alicorn's core sized:", f0), "; 2 parts, " .. half .. " each"), "two core parts: the total split between them")
AL.core_missiles = 5
f0 = openCore()
check(core.HealthInternal == sized(5) and s.corePct == 100 and line("special: Alicorn core hit:", f0) == nil,
      "core_missiles 5 (under what it had): " .. sized(5) .. ", CORE 100%, no hit logged")
AL.core_missiles = 0
f0 = openCore()
check(core.HealthInternal == 28594 and line("special: the Alicorn's core sized:", f0) == nil, "core_missiles 0: its health as it was")
AL.core_missiles = 30
-- the missile's damage unread: its health as it was, logged
FA.LiveMissile = nil
f0 = openCore()
check(core.HealthInternal == 28594 and s.coreFull == 28594 and s.corePct == 100
      and has(line("special: the Alicorn's core keeps its health", f0), "your missile's damage can't be read): 30 missiles"),
      "the missile's damage unread: its health as it was (" .. tostring(line("special: the Alicorn's core keeps its health", f0)) .. ")")
-- tank_missiles 0 (never read for the tanks): read as the core opens
AL.tank_missiles = 0
s = alicornRound()
tickA(0, 12)
FA.LiveMissile = { MSL }
for _, o in ipairs(tanks) do o.HealthInternal = 0 end
f0 = #logs + 1
tickA(13, 14)
check(core.HealthInternal == sized(30) and has(line("special: the Alicorn's core sized:", f0), "48 damage a missile from BP_plwp_msl_f0_C_1"),
      "tank_missiles 0: the missile's damage read as the core opens")
AL.tank_missiles = 6
FA.LiveMissile = nil

---------------------------------------------------------------------------------------------------- its hull and legs
print("its hull: its way, its place every 30 s, the leg from each place, the rejoiner's pose")
s = alicornRound()
f0 = #logs + 1
for t = 0, 64 do
    hull.at = KM(-20.1 + t * 0.033, -5.5)                 -- (east at 33 m/s)
    D.now = t; SPC.alicornTick(t, s)
end
check(s.legDir == "out", "moving east: its out leg (" .. tostring(s.legDir) .. ")")
check(lines("special: the Alicorn's hull at (", f0) == 3 and has(line("special: the Alicorn's hull at (", f0), "heading 0, its out leg"),
      string.format("its place logged every 30 s (%d in 64 s): %s", lines("special: the Alicorn's hull at (", f0),
          tostring(line("special: the Alicorn's hull at (", f0))))
local LEGS = {   -- (x km, east?) -> the event: the first waypoint 300 m or more ahead (A -27.7, B -23.0, C -19.0, D -15.3, E -11.5)
    { -27.7, true, "RE_SV_AlcnLegOutB" }, { -23.2, true, "RE_SV_AlcnLegOutC" }, { -23.4, true, "RE_SV_AlcnLegOutB" },
    { -17.0, true, "RE_SV_AlcnLegOutD" }, { -12.0, true, "RE_SV_AlcnLegBack" }, { -11.6, true, "RE_SV_AlcnLegBackD" },
    { -12.0, false, "RE_SV_AlcnLegBackD" }, { -15.5, false, "RE_SV_AlcnLegBackC" }, { -20.0, false, "RE_SV_AlcnLegBackB" },
    { -27.0, false, "RE_SV_AlcnLegOut" }, { -27.5, false, "RE_SV_AlcnLegOutB" }, { -30.0, true, "RE_SV_AlcnLegOutB" },
}
local okL, badL = true, ""
for _, c in ipairs(LEGS) do
    local ev = SPC.alicornLegOf(c[1] * 100000, c[2])
    if ev ~= c[3] then okL, badL = false, badL .. string.format(" %.1f %s: %s (want %s);", c[1], c[2] and "east" or "west", tostring(ev), c[3]) end
end
check(okL, "the leg from each place on the lane: the first waypoint 300 m ahead, the other way's leg at an end" .. badL)
hull.at, hull.fwd, s.legDir = KM(-20, -5.6), { X = -1, Y = 0, Z = 0 }, "back"
local pose, ev, what = SPC.alicornRejoin()
check(pose and pose[1] == -2000000 and pose[2] == -560000 and pose[3] == 0 and math.abs(pose[4] - 180) < 0.01
      and ev == "RE_SV_AlcnLegBackB" and has(what, "back: from B"), "the rejoiner's pose at its hull (heading 180) and its leg west from B: "
      .. tostring(what))
s.legDir = nil                                            -- (no moves seen yet: its bow says)
check(select(2, SPC.alicornRejoin()) == "RE_SV_AlcnLegBackB", "... its bow when its moves aren't known")
hull.gone = true; s.hullObj = nil; s.hullLooks = 0        -- (its hull not in the record: its core stands in)
SPC.CLEAN_OBJ[UNIT] = { at = clock, core }
core.at = KM(-14, -6.3)
check(select(2, SPC.alicornRejoin()) == "RE_SV_AlcnLegBack" and (SPC.alicornRejoin())[1] == -1400000,
      "... no hull in its record: its core's place, its bow east: to E, then back (" .. tostring(select(2, SPC.alicornRejoin())) .. ")")
D.special.state = "done"
check(SPC.alicornRejoin() == nil, "none once it's sunk")
SPC.alcnMoved = nil
check(SPC.alicornPose(nil) == nil, "a spawn with no pose: none (the world data's point)")
local p1 = { 1, 2, 0, 90 }
check(SPC.alicornPose(p1) == p1 and SPC.alcnMoved, "a spawn at a pose: that one, the unit marked moved")
f0 = #logs + 1
local back = SPC.alicornPose(nil)
check(back and back[1] == -2770000 and back[2] == -440000 and back[3] == 0 and back[4] == 0 and not SPC.alcnMoved
      and line("special: the Alicorn's spawn here at its lane's start again", f0), "the next with none: at its lane's start (logged), once")
check(SPC.alicornPose(nil) == nil, "... and none after it")
-- the host's own spawn after one at a pose: at the lane's start
SPC.alcnMoved, SPC.alicornReady = true, true
run(45); D.special = { kind = "alicorn" }; alive[UNIT] = 0; spawns = {}
local okS = SPC.alicornSpawn(0)
check(okS and spawns[1] and spawns[1].x == -2770000 and spawns[1].y == -440000 and spawns[1].yaw == 0, "the host's spawn after one at a pose: at its lane's start")
spawns = {}
SPC.alicornSpawn(0)
alive[UNIT] = 0
D.special = { kind = "alicorn" }
SPC.alicornSpawn(0)
check(spawns[#spawns] and spawns[#spawns].x == nil, "... the next: no pose (the world data's point)")

---------------------------------------------------------------------------------------------------- the host's co-op
print("the host's co-op: a rejoiner's Alicorn, the joiners' hits, a part's kill")
COOP.open, COOP.role, COOP.slot = true, "host", 0
s = alicornRound()
hull.at, hull.fwd = KM(-21, -5.4), { X = 1, Y = 0, Z = 0 }
s.legDir, s.coreOpen, s.dived = "out", true, false
M.units, M.byId, M.replays, M.peers = {}, {}, {}, {}
M.units[UNIT] = { gen = 7, pose = nil, ops = nil, level = nil, n = 0, planes = {}, ground = { ["BP_MP028_dummy_emlmcore_Base_C#1"] = { id = 2161 } }, at = clock }
M.byId[2161] = { obj = core, unit = UNIT, key = "BP_MP028_dummy_emlmcore_Base_C#1", addr = core.addr }
f0 = #logs + 1
hostSync(2)
local sp = nil
for _, m in ipairs(sent) do if m:find("^2>sp|" .. UNIT .. "|") then sp = m end end
check(sp and has(sp, "|-2100000,-540000,0,0.0|") and has(line("coop: player 3's Alicorn to come up at the host's hull", f0), "out: from C"),
      "hostSync: the rejoiner's sp at the host's hull, its leg logged (" .. tostring(sp) .. ")")
sent = {}
D.now = 0
clock = clock + 2.5
hull.at = KM(-19.2, -5.8)                                 -- (on: past C 200 m short of it, D the next 300 m ahead)
hostTick()
local evs = {}
for _, m in ipairs(sent) do local e = m:match("^2>ev|([%w_]+)|" .. UNIT .. "$"); if e then evs[#evs + 1] = e end end
check(#evs == 1 and evs[1] == "RE_SV_AlcnLegOutD", "2 s on: its leg as the hull is then (D, not C as at the sync), for its unit (" .. table.concat(evs, ",") .. ")")
local rnd16
for _, m in ipairs(sent) do if m:find("^rnd|") then rnd16 = select(16, table.unpack((function() local t = {}; for x in (m .. "|"):gmatch("([^|]*)|") do t[#t + 1] = x end; return t end)())) end end
check(rnd16 == "4:" .. tostring(s.corePct or "e") .. ":0" or rnd16 == "4:e:0", "rnd field 16: the Alicorn's row (" .. tostring(rnd16) .. ")")
sent = {}
clock = clock + 10
hostTick()
evs = {}
for _, m in ipairs(sent) do local e = m:match("^2>ev|([%w_]+)|" .. UNIT .. "$"); if e then evs[#evs + 1] = e end end
check(table.concat(evs, ",") == "RE_SV_AlcnAdvance,RE_SV_AlcnOpenCore", "12 s on: its open core, as before (" .. table.concat(evs, ",") .. ")")
-- the joiners' hits: tallied a player a minute
M.peers[3] = { real = true, addr = 0x700 }
M.hitT, M.hitTAt = nil, clock + 60
core.HealthInternal = 20000
hostHit(3, 2161, 120)
hostHit(3, 2161, 50)
check(core.HealthInternal == 20000 - 1700, "a joiner's hits on the core dealt (" .. core.HealthInternal .. ")")
core.invincible = true
hostHit(3, 2161, 30); hostHit(3, 2161, 30)                -- (refused: its health doesn't move)
core.invincible = false
hostHit(3, 999, 40)                                       -- (an id unknown here)
hostHit(3, 2161, 0 / 0)                                   -- (not a number)
hostHit(2, 2161, 10)
f0 = #logs + 1
M.hitTallyTick(clock + 61)
local tl = line("coop: the joiners' hits dealt here in the last 60 s", f0) or ""
check(has(tl, "player 3: 1 hits (1 taken, 0 refused, 0 dropped), 100: 100 on SV_Unit_Alicorn (core 100)")
      and has(tl, "player 4: 6 hits (2 taken, 2 refused, 2 dropped), 1700: 1700 on SV_Unit_Alicorn (core 1700)"),
      "a minute's line: each player's hits taken / refused / dropped, the core's share (" .. tl .. ")")
f0 = #logs + 1
M.hitTallyTick(clock + 200)
check(line("coop: the joiners' hits dealt here", f0) == nil, "... nothing in the next minute: no line")
-- a part of it down: whose kill
f0 = #logs + 1
M.byId[2161].by = { [3] = 1700, [2] = 10 }
M.nextHp = clock + 100
core.HealthInternal = 0
hostTick()
local dn
for _, m in ipairs(sent) do if m:find("^dn|2161|") then dn = m end end
check(dn == "dn|2161||3" and has(line("coop: SV_Unit_Alicorn's BP_MP028_dummy_emlmcore_Base_C#1 down here", f0), "player 4's kill; the joiners' hits on it: player 3 10, player 4 1700"),
      "its core down: the dn names player 4, logged with the joiners' hits (" .. tostring(line("coop: SV_Unit_Alicorn's", f0)) .. ")")
COOP.open, COOP.role, COOP.slot = false, nil, nil

---------------------------------------------------------------------------------------------------- a joiner
print("a joiner: the host's row, its health for a copy bound late, its surfacing, its replay, its spawn")
COOP.open, COOP.role, COOP.slot = true, "join", 3
run(45); D.special = nil
local pawn = mkObj("BP_PlayerPlane_PP1000_f16c_C_1", KM(-15, -5, 2))
survivalPC = { Pawn = pawn, full = "PC", addr = 8 }
M.copies, M.cunits, M.spawnQ, M.dead, M.evQ, M.rep, M.pendHp, M.pendHpN = {}, {}, {}, {}, nil, nil, nil, nil
M.readyAt = clock - 10
local function rnd(f12, f16)
    return { "rnd", "45", "fighting", "0.0", "1", "1", "0", "", "", "", "alicorn", f12, "0", ";", "0", f16 }
end
onJoinerMessage(rnd("alicorn:sail", "0:62:0"))
D.hostSpecial = M.rnd.hostSpecial
check(SPC.alicornRow(T) == "ALICORN: BALLAST TANKS 0/4  CORE 62%", "rnd field 16: the host's row here (" .. tostring(SPC.alicornRow(T)) .. ")")
onJoinerMessage(rnd("alicorn:sail", "2:s:1"))
check(SPC.alicornRow(T) == "ALICORN: BALLAST TANKS 2/4  CORE SHUT  (DIVED)", "... shut, dived (" .. tostring(SPC.alicornRow(T)) .. ")")
onJoinerMessage(rnd("alicorn:sail", "0:e:0"))
check(SPC.alicornRow(T) == "ALICORN: BALLAST TANKS 0/4  CORE EXPOSED", "... open, its health unread: EXPOSED")
local okH = true
for _, bad in ipairs({ "5:62:0", "0:101:0", "0:-1:0", "0:nan:0", "0:62", "0:62:2", "0:6.5:0", "x", "", "0:1e999:0",
                       "0:" .. string.rep("9", 400) .. ":0", "4:%d%s:0", "0:62:0:9" }) do
    onJoinerMessage(rnd("alicorn:sail", bad))
    if SPC.alicornRow(T) ~= nil then okH = false; print("    (taken: " .. bad .. ")") end
end
check(okH, "a hostile or broken field 16: no row")
onJoinerMessage(rnd("anomaly:hunt", "0:62:0"))
check(SPC.alicornRow(T) == nil, "the host's special not the Alicorn sailing: no row")
onJoinerMessage(rnd("alicorn:sail", "0:62:0"))
clock = clock + 6
check(SPC.alicornRow(T) == nil, "the host's word 6 s old: no row")
clock = clock - 6
-- the host's health before the bind
local copyCore = mkObj(AL.core_class .. "_9", KM(-20, -5.5, -0.0001), nil, 31250)
onJoinerMessage({ "hp", "2161:28594,2162:8784" })
check(M.pendHp and M.pendHp[2161] and M.pendHp[2161].h == 28594 and M.pendHpN == 2, "the host's hp for ids not bound here: kept (2)")
M.cunits[UNIT] = { gen = 7, n = 0, planes = {}, binds = {}, gbinds = {}, at = clock, upAt = clock }
f0 = #logs + 1
bindGround(2161, copyCore, UNIT, "BP_MP028_dummy_emlmcore_Base_C#1")
check(copyCore.HealthInternal == 28594 and M.copies[2161].exp == 28594 and M.copies[2161].hp == 28594 and M.pendHp[2161] == nil
      and has(line("coop: the host's SV_Unit_Alicorn here bound with the host's health", f0), "31250 -> 28594"),
      "bound: the host's health on it, not its stock 31,250 (logged once a spawn)")
onJoinerMessage({ "hp", "2161:" .. sized(60) })
check(copyCore.HealthInternal == sized(60) and M.copies[2161].exp == sized(60),
      "the host's core sized as it opened (more than it had): on the copy here (" .. copyCore.HealthInternal .. ")")
onJoinerMessage({ "hp", "2161:28594" })
onJoinerMessage({ "gd", UNIT, "7", "BP_BA002_alcn_btankfl_Base_C#1", "2162" })
check(M.pendHp[2162] == nil and M.pendHpN == 0, "a gd naming that id anew: its kept health forgotten")
onJoinerMessage({ "hp", "2163:500" })
onJoinerMessage({ "dn", "2163", "", "" })
check(M.pendHp[2163] == nil and M.pendHpN == 0, "a dn: forgotten")
for i = 1, 5000 do M.notePendHp(10000 + i, 100) end
check(M.pendHpN == 4096, "at most 4,096 kept (" .. tostring(M.pendHpN) .. ")")
clock = clock + 200
M.notePendHp(30000, 100)
check(M.pendHpN == 1, "... each 120 s at most (" .. tostring(M.pendHpN) .. ")")
M.pendHp, M.pendHpN = nil, nil
-- its surfacing (alicorn-7)
SPC.CLEAN_OBJ[UNIT] = { at = clock, copyCore }
copyCore.at = KM(-20, -5.5, -0.00005)                     -- (at the surface: -5 cm)
onJoinerMessage(rnd("alicorn:sail", "0:62:0"))
D.hostSpecial = M.rnd.hostSpecial
for _ = 1, 3 do clock = clock + 1; SPC.alicornClient(clock) end
events = {}
hostEvent("RE_SV_AlcnDive")
check(events[1] == "RE_SV_AlcnDive" and SPC.alcnCl and SPC.alcnCl.dived and SPC.alcnCl.seaZ == -5, "the host's dive here: fired, its copy's sea level kept")
copyCore.at.Z = -5600                                      -- (56 m down)
for _ = 1, 20 do clock = clock + 1; SPC.alicornClient(clock) end
hostEvent("RE_SV_AlcnSurface")
f0 = #logs + 1
events = {}
for _ = 1, 9 do clock = clock + 1; SPC.alicornClient(clock) end
check(#events == 1 and events[1] == "RE_SV_AlcnSurface" and has(line("special: the Alicorn's copy here is still 56 m down", f0), "not rising: surfaced here (1, fired)"),
      "still 56 m down 8 s after the host's order, not rising: surfaced here (COOP.eventHere), logged")
for _ = 1, 40 do clock = clock + 1; SPC.alicornClient(clock) end
check(#events == 4, "... resurface_tries (4) at most (" .. #events .. ")")
for _ = 1, 20 do clock = clock + 1; SPC.alicornClient(clock) end
check(has(line("special: the Alicorn's copy here still 56 m down", f0), "left as it is") and not SPC.alcnCl.surfaceSent,
      "up_wait_s on: left as it is, logged")
hostEvent("RE_SV_AlcnSurface")                            -- (the host's again after it: no new wait)
check(not SPC.alcnCl.surfaceSent, "... a later order of the host's starts no new wait")
hostEvent("RE_SV_AlcnDive"); hostEvent("RE_SV_AlcnSurface")
events = {}
f0 = #logs + 1
clock = clock + 1; SPC.alicornClient(clock)
copyCore.at.Z = -100
clock = clock + 1; SPC.alicornClient(clock)
check(#events == 0 and has(line("special: the Alicorn's copy here surfaced", f0), "after the host's order (1 of its orders, 0 sent here)"),
      "a dive then the host's order and it rises: surfaced, nothing sent here, logged")
f0 = #logs + 1
clock = clock + 31; SPC.alicornClient(clock)
check(has(line("special: the Alicorn's copy here at (", f0), "(the host's: 0 tanks, core 62%)"), "its place logged every 30 s, the host's word with it: "
      .. tostring(line("special: the Alicorn's copy here at (", f0)))
onJoinerMessage(rnd("anomaly:hunt", ""))
D.hostSpecial = M.rnd.hostSpecial
SPC.alicornClient(clock + 1)
check(SPC.alcnCl == nil, "the host's Alicorn over: the check here dropped")
-- the host's replay waits for its copy
M.cunits, M.spawnQ, M.evQ = {}, { { unit = UNIT, pose = { -2100000, -540000, 0, 0 }, ops = {}, gen = 9, at = clock + 100 } }, nil
events = {}
onJoinerMessage({ "ev", "RE_SV_AlcnOpenCore", UNIT })
check(#events == 0 and M.evQ and #M.evQ == 1 and M.evQ[1].waited, "the host's open core for its fresh copy: held (its spawn's still queued)")
onJoinerMessage({ "ev", "RE_SV_PressureB" })
check(events[1] == "RE_SV_PressureB", "... one for no unit: fired at once")
events = {}
M.spawnQ = {}
M.cunits[UNIT] = { gen = 9, n = 0, planes = {}, binds = {}, gbinds = {}, at = clock, upAt = clock }
M.lastSpawnAt = clock - 5
clientRounds(clock + 1)
check(#events == 0, "its copy up 1 s: still held")
f0 = #logs + 1
clock = clock + 3.5
clientRounds(clock)
check(events[1] == "RE_SV_AlcnOpenCore" and has(line("coop: the host's RE_SV_AlcnOpenCore for SV_Unit_Alicorn fired here", f0), "(its copy up first)"),
      "3 s after its copy's up: fired, logged (" .. tostring(events[1]) .. ")")
-- a copy kept through a resync: as before (keptThrough logs it, nothing fired)
M.rep = { at = clock + 1, done = clock + 1 }
M.cunits[UNIT].at = clock - 50; M.cunits[UNIT].upAt = clock - 50
events = {}
M.spawnQ = { { unit = UNIT, pose = nil, ops = {}, gen = 9, at = clock + 100 } }
f0 = #logs + 1
onJoinerMessage({ "ev", "RE_SV_AlcnAdvance", UNIT })
check(#events == 0 and (M.evQ == nil or #M.evQ == 0) and has(line("coop: the host's RE_SV_AlcnAdvance for SV_Unit_Alicorn not fired here", f0), "kept through the resync"),
      "a copy kept through a resync, its spawn the same one: not held, not fired (keptThrough)")
M.rep, M.spawnQ = nil, {}
-- its spawn at the host's hull, the next back at its lane's start
M.cunits, spawns, SPC.alcnMoved = {}, {}, nil
alive[UNIT] = 0
M.spawnQ = { { unit = UNIT, pose = { -2100000, -540000, 0, 12.5 }, ops = {}, gen = 11, at = 0 } }
f0 = #logs + 1
clientRounds(clock)
check(spawns[1] and spawns[1].x == -2100000 and spawns[1].y == -540000 and spawns[1].yaw == 12.5
      and has(line("coop: the host's Alicorn to spawn here at its hull", f0), "(-21.0, -5.4) km"), "the rejoiner's spawn at the host's hull (logged)")
M.cunits, spawns = {}, {}
M.spawnQ = { { unit = UNIT, pose = nil, ops = {}, gen = 12, at = 0 } }
clientRounds(clock)
check(spawns[1] and spawns[1].x == -2770000 and spawns[1].y == -440000, "the next with no pose: at its lane's start (its unit moved by the last)")
M.cunits, spawns = {}, {}
M.spawnQ = { { unit = UNIT, pose = nil, ops = {}, gen = 13, at = 0 } }
clientRounds(clock)
check(spawns[1] and spawns[1].x == nil, "... and the one after it: no pose")
-- a launch at a target with no co-op id: counted (sv_coop_sync.lua)
check(has(PARTS.read("sv_coop_sync.lua"), "S.n.pNoId = (S.n.pNoId or 0) + 1") and has(PARTS.read("sv_coop_sync.lua"), "your launches at a target with no ")
      and has(PARTS.read("sv_coop_sync.lua"), "S.n.pUntargeted = (S.n.pUntargeted or 0) + 1"),
      "the coopfire line counts launches with no co-op id (a joiner's) and those whose target isn't here (the host's)")
COOP.open, COOP.role, COOP.slot = false, nil, nil

print("the hooks, by their place in the source")
check(has(readAll(MOD .. "/Scripts/sv_hud.lua"), "SPC.alicornRow(t)"), "the HUD's NEXT row: SPC.alicornRow")
check(has(PARTS.read("sv_coop.lua"), "pcall(M.hitTallyTick, now)") and has(PARTS.read("sv_coop.lua"), "SPC.alicornCode()"),
      "hostTick: the hits' tally a minute, rnd field 16")
check(has(PARTS.read("sv_coop.lua"), "pcall(SPC.alicornClient, now)") and has(PARTS.read("sv_coop.lua"), "pcall(SPC.alicornHostEvent, tostring(name))"),
      "a joiner's clientRounds and hostEvent: the Alicorn's copy checked")

logFile:close()
if fails > 0 then print("alicorn test: " .. fails .. " FAILED"); os.exit(1) end
print("alicorn test: all passed")
