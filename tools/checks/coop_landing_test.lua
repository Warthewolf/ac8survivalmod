-- coop_landing_test.lua <mod dir> <work dir> (run by tools/checks/coop_landing_test.sh): the host down at the airfield
-- in Survival COOP (the user's question of 2026-10-29: "when the HOST is landed at the airfield that the game isn't
-- paused for the other players"; code review F5), on the real sv_core, sv_config, sv_rows, sv_ai, sv_hud, sv_spawn,
-- sv_rounds, sv_tactical, sv_stats, sv_tells, sv_director and sv_coop (M exposed), the game stubbed, the other players
-- through SV_CoopPeerAt as the runtime reports them:
--   othersFlying: another player alive, in the mission and not on the airfield; never you, solo or on a joiner;
--   roundsTick's spawns: solo, down at the airfield, held until you take off (as ever); a co-op host with another player
--     flying goes on (logged once a round), held again when they're down, dead, out of the mission or not heard from,
--     and goes on once one takes off while you're still down;
--   ordersTick: solo, nothing fired while you're down; a co-op host with another player flying fires
--     RE_SV_FlightOrders_NN after orders_check_s and every 5 s while you're down, none counted as a try (logged once),
--     the tries after your takeoff as ever; "has its orders now" with how many were fired;
--   the wave clock (waves.timeout_s): stopped while you're down solo, running in co-op while another player flies;
--   the Wolf trap's 30 s for its orders: your time down at the airfield not counted (U5's review), solo and co-op;
--   the Wolf trap's hold: solo, held at your takeoff (as ever); a co-op host with another player flying holds it
--     hold_after_s after its orders while still down (logged so) and lets it go after hold_max_s there; held at your
--     takeoff again when nobody else flies (F5's review, round 2: it was held at the host's takeoff, mid-fight);
--   the shuttle's countdown: solo, held and the shuttle invulnerable while you're down (as ever); a co-op host with
--     another player flying runs it on, never invulnerable (logged once, not as the count of others changes: the user,
--     2026-10-29: "Keep it running while others are flying"), held and invulnerable again when nobody else flies, can
--     be hit again at their takeoff or yours; it lifts off and is lost with you down; the first of its events not fired
--     with you down is logged, once a clock (whether they take with the landing menu up isn't known: F5's review of the
--     change); a joiner runs none of its own;
--   a joiner's rounds hold nothing on the host's landing;
--   the hooks by their place in the source (the ALICORN's deck: bosses_test.sh).
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

local clock = 1000                               -- (co-op's own clock: its info, ready and rate checks)
os.clock = function() return clock end           -- luacheck: ignore

-- the game's world, stubbed
VERSION = "0.72.0-landing.test"
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
ANOM.fx = ANOM.fx or {}                              -- (roundsTick's specialTick: parts not loaded here)
AMPH.runTick = AMPH.runTick or function() end
math.randomseed(3)

local function line(prefix, from)
    for i = #logs, from or 1, -1 do if logs[i]:sub(1, #prefix) == prefix then return logs[i] end end
    return nil
end
local function since(from, pat) local n = 0; for i = from, #logs do if logs[i]:find(pat) then n = n + 1 end end; return n end
local function evs(pat) local t = {}; for _, e in ipairs(events) do if e:find(pat) then t[#t + 1] = e end end; return table.concat(t, ",") end
local function units() local t = {}; for _, s in ipairs(spawns) do t[#t + 1] = s.unit end; return table.concat(t, ",") end

-- you (the pawn, 3 km up over the sea: the stubbed playerOnAirfield says where you are) and the room
local pawn = { full = "BP_PlayerPlane_PP1000_f16c_C_1", addr = 9, MaxHealth = 100, HealthInternal = 800 }
function pawn:K2_GetActorLocation() return { X = 0, Y = 0, Z = 300000 } end
function pawn:GetActorForwardVector() return { X = 1, Y = 0, Z = 0 } end
survivalPC = { Pawn = pawn }
local U1, U2, U3 = "ERA_Unit_01_Dep_Air0", "ERA_Unit_02_Dep_Air1", "ERA_Unit_01_Dep_Air2"
-- player 2's state as the runtime reports it: position (cm), rotation, health x 10, full health, flags (1 in Survival's
-- level, 2 alive, 4 down at the airfield) and its age (ms)
local function p2(flags, age) peerState[1] = string.format("5000000,0,300000,0,0,0,600,100,%d,%d", flags, age or 100) end
local FLYING, P2_DOWN, P2_DEAD, P2_OUT = 3, 7, 1, 2
local function room(on)                         -- co-op hosting (on) or solo; COOP.tick reads player 2's state
    CFG.coop.enabled = on
    if on then COOP.open, COOP.role, COOP.slot = true, "host", 0 else COOP.open, COOP.role, COOP.slot = false, nil, nil end
    clock = clock + 0.25
    if on then COOP.tick(0) end
end
local function fresh(round, state)
    planes, alive, events, spawns, sent = {}, {}, {}, {}, {}
    D = { round = round, state = state or "spawning", now = 99, at = 0, up = {}, flown = {}, queue = {}, spare = {},
          events = {}, orders = {}, pressure = "B", wave = 1 }
    grounded, FLAGS = false, {}
    DIR.roundStart(99)
end
local function ticks(t0, t1)                     -- roundsTick every 250 ms from t0 to t1 (the round clock)
    local n = math.floor((t1 - t0) / 0.25 + 0.5)
    for i = 0, n do
        local t = t0 + i * 0.25
        D.now = t
        roundsTick(t)
    end
end

---------------------------------------------------------------------------------------------------- othersFlying
print("othersFlying: the other players in the air")
fresh(5)
room(false)
check(othersFlying() == 0, "solo: 0")
room(true); p2(FLYING)
room(true)
check(othersFlying() == 1, "a co-op host, player 2 flying: 1")
p2(P2_DOWN); room(true)
check(othersFlying() == 0, "player 2 down at the airfield: 0")
p2(P2_DEAD); room(true)
check(othersFlying() == 0, "player 2 shot down (in the mission, not alive): 0")
p2(P2_OUT); room(true)
check(othersFlying() == 0, "player 2 not in the mission: 0")
p2(FLYING, 5000); room(true)
check(othersFlying() == 0, "player 2 not heard from for 5 s: 0")
p2(FLYING); room(true)
COOP.role = "join"
check(othersFlying() == 0, "on a joiner: 0 (the host's rounds)")
COOP.role = "host"

---------------------------------------------------------------------------------------------------- spawns
print("roundsTick's spawns while you're down at the airfield")
-- solo: held until you take off, as ever
fresh(5); room(false)
D.queue = { U1, U2 }
grounded = true
local from = #logs + 1
ticks(100, 110)
check(#spawns == 0 and has(line("round 5: spawns held while you are down at the airfield", from), "held"),
      "solo, down at the airfield: no spawn for 10 s (logged)")
grounded = false
ticks(110.25, 111)                               -- (held: looked at again each second)
check(units() == U1 and line("round 5: you took off, spawns go on", from) ~= nil, "... you take off: the next flight comes (logged)")
-- co-op, player 2 flying: they go on
fresh(5); p2(FLYING); room(true)
D.queue = { U1, U2, U3 }
grounded = true
from = #logs + 1
ticks(100, 100)
check(units() == U1 and has(line("round 5: spawns go on while you're down at the airfield", from), "(1 other player flying)"),
      "co-op, you down, player 2 flying: the flight comes at once (" .. tostring(line("round 5: spawns go on", from)) .. ")")
ticks(100.25, 100 + CFG.spawn_gap_s)
check(units() == U1 .. "," .. U2 and since(from, "^round 5: spawns go on") == 1, "... the next spawn_gap_s on, logged once a round")
check(line("round 5: spawns held", from) == nil and line("round 5: you took off", from) == nil, "... never held")
-- player 2 lands too: held; they take off again while you're still down: on again
p2(P2_DOWN); room(true)
ticks(100 + CFG.spawn_gap_s + 0.25, 110)
check(#spawns == 2 and has(line("round 5: spawns held", from), "down at the airfield"), "player 2 down at the airfield too: held")
p2(FLYING); room(true)
ticks(110.25, 111)
check(#spawns == 3 and since(from, "^round 5: spawns go on") == 2 and line("round 5: you took off", from) == nil,
      "player 2 takes off, you still down: on again (logged again after the hold, not 'you took off')")
for _, st in ipairs({ { P2_DEAD, 100, "shot down" }, { P2_OUT, 100, "out of the mission" }, { FLYING, 5000, "not heard from" } }) do
    fresh(5); p2(st[1], st[2]); room(true)
    D.queue = { U1 }
    grounded = true
    ticks(100, 105)
    check(#spawns == 0, "player 2 " .. st[3] .. ", you down: held")
end
-- a joiner's rounds hold nothing on the host's landing (the host's "rnd" is its round; its spawns come as "sp")
fresh(5); room(false)
COOP.open, COOP.role, COOP.slot, CFG.coop.enabled = true, "join", 1, true
clock = clock + 0.25
COOP.tick(0)
grounded = false
M.readyAt = nil
roundsTick(100)
clock = clock + 4
inbox[#inbox + 1] = "0|rnd|5|spawning|0.0|1|1|0"
inbox[#inbox + 1] = "0|sp|" .. U1 .. "|-|-|-1|1"
COOP.tick(0)
roundsTick(101)
check(units() == U1, "a joiner: the host's spawn comes as \"sp\", whatever the host's airfield (its own level ready)")
room(false)

---------------------------------------------------------------------------------------------------- orders
print("ordersTick while you're down at the airfield")
local I1 = poolIndex(U1)
local ORD = string.format("RE_SV_FlightOrders_%02d", I1)
local function ordersScene(coop)
    fresh(5, "fighting")
    if coop then p2(FLYING) end
    room(coop)
    alive[U1] = 2
    D.up[U1] = true
    FLAGS[string.format("SV_Up_%02d", I1)] = 0
    D.orders[U1] = { at = 100 + CFG.orders_check_s, tries = 0 }
end
ordersScene(false)
grounded = true
from = #logs + 1
ticks(100, 130)
check(evs("^RE_SV_FlightOrders") == "" and D.orders[U1].tries == 0, "solo, down at the airfield 30 s: no orders fired, no try used")
grounded = false
ticks(130.25, 131)                               -- (grounded: looked at again each second)
check(evs("^RE_SV_FlightOrders") == ORD and D.orders[U1].tries == 1, "... you take off: its first try (" .. ORD .. ")")
ordersScene(true)
grounded = true
from = #logs + 1
ticks(100, 100 + CFG.orders_check_s - 0.25)
check(evs("^RE_SV_FlightOrders") == "", "co-op, player 2 flying: nothing before orders_check_s")
ticks(100 + CFG.orders_check_s, 100 + CFG.orders_check_s)
check(evs("^RE_SV_FlightOrders") == ORD and D.orders[U1].tries == 0 and D.orders[U1].downTries == 1
      and has(line("orders: " .. U1 .. " appeared without its orders while you're down", from), "(1 other player flying); " .. ORD .. " fired"),
      "... at orders_check_s: fired while you're down, not a try (logged)")
ticks(104.25, 130)
local nDown = select(2, evs("^RE_SV_FlightOrders"):gsub(ORD, ""))
check(nDown == 6 and D.orders[U1].tries == 0 and since(from, "appeared without its orders while you're down") == 1,
      "... again every 5 s while you're down (" .. nDown .. " in 26 s), none a try, logged once")
grounded = false
events = {}
ticks(130.25, 150)                               -- (its tries at 134, 139, 144: 5 s on from the last one fired)
check(evs("^RE_SV_FlightOrders") == ORD .. "," .. ORD .. "," .. ORD and D.orders[U1] == nil
      and line("orders: " .. U1 .. " never got its orders", from) ~= nil, "... you take off: its 3 tries as ever, then given up")
ordersScene(true)
grounded = true
from = #logs + 1
ticks(100, 109.5)
FLAGS[string.format("SV_Up_%02d", I1)] = 1
ticks(109.75, 114)
check(D.orders[U1] == nil and has(line("orders: " .. U1 .. " has its orders now", from), "(2 fired while you were down at the airfield)"),
      "its flag up after two: it has its orders (" .. tostring(line("orders: " .. U1 .. " has its orders now", from)) .. ")")
ordersScene(true)
p2(P2_DOWN); room(true)
grounded = true
ticks(100, 120)
check(evs("^RE_SV_FlightOrders") == "" and D.orders[U1].tries == 0, "co-op, player 2 down at the airfield too: nothing fired")

---------------------------------------------------------------------------------------------------- the wave clock
print("the wave clock (waves.timeout_s) while you're down at the airfield")
local function waveScene(coop)
    fresh(5, "wave")
    if coop then p2(FLYING) end
    room(coop)
    CFG.waves.timeout_s = 60
    D.waves, D.wave, D.waveAt, D.at = { { U1 }, { U2 } }, 1, 100, 0
    alive[U1] = 6
    D.up[U1] = true
end
waveScene(false)
grounded = true
ticks(100, 140)
grounded = false
ticks(140.25, 165)
check(D.wave == 1, "solo, 40 s down at the airfield: wave 2 not at 60 s (its clock stopped while you were down)")
ticks(165.25, 201)
check(D.wave == 2, "... 60 s of your flying on: wave 2")
waveScene(true)
grounded = true
ticks(100, 159)
check(D.wave == 1, "co-op, player 2 flying: not before 60 s")
ticks(159.25, 161)
check(D.wave == 2, "... at 60 s with you down at the airfield: wave 2 (its clock ran)")
CFG.waves.timeout_s = CFG_DEFAULTS.waves.timeout_s

---------------------------------------------------------------------------------------------------- the Wolf trap
print("the Wolf trap's 30 s for its orders (U5's review)")
local W = "ERA_Unit_05_Dep_Air1"
local function wolfScene(coop)
    fresh(10, "fighting")
    if coop then p2(FLYING) end
    room(coop)
    alive[W] = 4
    WOLF.spawned(W, 4, 100)
end
local function wolfTicks(t0, t1) for t = t0, t1, 0.25 do D.now = t; WOLF.tick(t) end end
wolfScene(false)
grounded = true
from = #logs + 1
wolfTicks(100, 160)
check(D.wolf[W] and D.wolf[W].state == "pending" and line("roles: " .. W .. " (wolf) never got its orders", from) == nil,
      "solo, a Wolf flight up as you land, 60 s down without its orders: its trap still pending")
grounded = false
wolfTicks(160.25, 189.5)
check(D.wolf[W] and D.wolf[W].state == "pending", "... you take off: still pending 29 s on")
wolfTicks(189.75, 191)
check(D.wolf[W] == nil and has(line("roles: " .. W .. " (wolf) never got its orders", from), "your time down at the airfield not counted"),
      "... 30 s of your flying on: given up (logged)")
wolfScene(false)
grounded = true
wolfTicks(100, 160)
grounded = false
FLAGS[string.format("SV_Up_%02d", poolIndex(W))] = 1
events = {}
wolfTicks(160.25, 164)
check(evs("^RE_SV_WolfHold") ~= "" and D.wolf[W].state == "held", "... its orders after your takeoff: the trap held hold_after_s on")
wolfScene(true)
grounded = true
wolfTicks(100, 160)
check(D.wolf[W] and D.wolf[W].state == "pending", "co-op, you down 60 s with player 2 flying: its trap still pending (not counted)")

print("the Wolf trap's hold while you're down at the airfield (F5's review, round 2)")
local WUP = string.format("SV_Up_%02d", poolIndex(W))
local HOLD = string.format("RE_SV_WolfHold_%02dB,RE_SV_WolfHold_%02dD", poolIndex(W), poolIndex(W))
-- solo: its orders in while you're down: held only at your takeoff, as ever
wolfScene(false)
grounded = true
FLAGS[WUP] = 1
events = {}
wolfTicks(100, 160)
check(evs("^RE_SV_WolfHold") == "" and D.wolf[W].state == "pending" and WOLF.holding(W),
      "solo, its orders in while you're down 60 s: not held (pending)")
grounded = false
wolfTicks(160.25, 161)
check(evs("^RE_SV_WolfHold") == HOLD and D.wolf[W].state == "held", "... you take off: held then")
-- co-op, player 2 flying: held hold_after_s after its orders, you still down; let go after hold_max_s, you still down
wolfScene(true)
grounded = true
FLAGS[WUP] = 1
events = {}
from = #logs + 1
local hAfter, hMax = CFG.roles.wolf.hold_after_s, CFG.roles.wolf.hold_max_s
wolfTicks(100, 100 + hAfter - 0.25)
check(evs("^RE_SV_WolfHold") == "", "co-op, you down, player 2 flying: not before hold_after_s")
wolfTicks(100 + hAfter, 100 + hAfter)
check(evs("^RE_SV_WolfHold") == HOLD and D.wolf[W].state == "held"
      and has(line("roles: " .. W .. " (wolf) trap ", from), "after its orders, you down at the airfield (1 other player flying): held B, D"),
      "... at hold_after_s: held with you down (" .. tostring(line("roles: " .. W .. " (wolf) trap ", from)) .. ")")
wolfTicks(100 + hAfter + 0.25, 100 + hAfter + hMax + 1)
check(D.wolf[W].state == "free" and not WOLF.holding(W) and evs("^RE_SV_WolfFree") ~= ""
      and has(line("roles: " .. W .. " (wolf) trap freed", from), "held " .. hMax .. " s"),
      "... hold_max_s on, you still down: let go (its co-op hunt then goes on)")
grounded = false
events = {}
wolfTicks(100 + hAfter + hMax + 1.25, 100 + hAfter + hMax + 5)
check(evs("^RE_SV_WolfHold") == "", "... you take off: not held again")
-- co-op, player 2 down at the airfield too: held at your takeoff, as solo
wolfScene(true)
p2(P2_DOWN); room(true)
grounded = true
FLAGS[WUP] = 1
events = {}
wolfTicks(100, 130)
check(evs("^RE_SV_WolfHold") == "" and D.wolf[W].state == "pending", "co-op, player 2 down at the airfield too: not held")
p2(FLYING); room(true)
wolfTicks(130.25, 131)
check(evs("^RE_SV_WolfHold") == HOLD and D.wolf[W].state == "held", "... player 2 takes off, you still down: held then")

---------------------------------------------------------------------------------------------------- the shuttle
print("the shuttle's countdown and invulnerability while you're down at the airfield")
local SH = CFG.specials.shuttle
SPC.kinds = SPC.kinds or {}                          -- (specialTick: sv_anomalies.lua not loaded here)
local inv = {}                                       -- the shuttle's SetIsInvincible calls, in order
local shuttle = { full = "BP_OP0057_sstb_CP_C_1", addr = 7, MaxHealth = 100, HealthInternal = 1000 }
function shuttle:SetIsInvincible(on) inv[#inv + 1] = tostring(on) end
function shuttle:K2_GetActorLocation() return { X = 0, Y = 0, Z = 0 } end
local function shuttleScene(coop)                    -- the shuttle on its pad, its countdown at 0 s at 100, a flight up
    fresh(5, "fighting")
    if coop then p2(FLYING) end
    room(coop)
    alive[SH.unit], alive[U1], D.up[U1] = 1, 2, true  -- (the round isn't cleared under it)
    D.special = { kind = "shuttle", state = "countdown", at = 100 }
    D.shuttleClock = { cd = 0, fired = 0, at = 100, s = D.special }
    SHUTTLE.obj, inv = shuttle, {}
end
local function cd() return D.shuttleClock and D.shuttleClock.cd or -1 end
local function nT() return select(2, evs("^RE_SV_ShuttleT_"):gsub("RE_SV_ShuttleT_", "")) end
local function invs() return table.concat(inv, ",") end
local HELD, RUNS, DOWN = "special: shuttle countdown held (you're down at the airfield) at ", "special: shuttle countdown running at ",
    "special: shuttle countdown running while you're down at the airfield ("
local INV, HIT = "special: shuttle invulnerable while the countdown is held", "special: shuttle can be hit again"
-- solo: held and invulnerable while you're down, as ever (user, 2026-10-23)
shuttleScene(false)
grounded = true
from = #logs + 1
ticks(100, 120)
check(cd() == 0 and nT() == 0 and invs() == "true" and line(HELD .. "0 s", from) ~= nil and line(INV, from) ~= nil,
      "solo, down at the airfield 20 s: the countdown held at 0 s, the shuttle invulnerable (logged)")
grounded = false
ticks(120.25, 130)
check(cd() == 10 and nT() == 10 and invs() == "true,false" and line(RUNS .. "0 s", from) ~= nil and line(HIT, from) ~= nil,
      "... you take off: it runs (10 s in 10 s, RE_SV_ShuttleT_1-10), the shuttle can be hit again (logged)")
-- co-op, player 2 flying: it runs with you down, never invulnerable, said once
shuttleScene(true)
grounded = true
from = #logs + 1
ticks(100, 120)
check(cd() == 20 and nT() == 20 and invs() == "" and line(INV, from) == nil,
      "co-op, you down 20 s, player 2 flying: the countdown runs (" .. cd() .. " s, " .. nT() .. " events), not invulnerable")
check(line(DOWN .. "1 other player flying) at 0 s", from) ~= nil and since(from, "^special: shuttle countdown") == 1,
      "... logged once (" .. tostring(line("special: shuttle countdown", from)) .. ")")
local rawOthers = othersFlying                       -- (a third player takes off: the count changes, not the state)
othersFlying = function() return 2 end
ticks(120.25, 125)
othersFlying = rawOthers
check(cd() == 25 and since(from, "^special: shuttle countdown") == 1, "... 2 others flying, then 1 again: still running, not logged again")
-- player 2 lands too: held and invulnerable; they take off again: running, can be hit again
p2(P2_DOWN); room(true)
ticks(125.25, 135)
check(cd() == 25 and nT() == 25 and invs() == "true" and line(HELD .. "25 s", from) ~= nil and line(INV, from) ~= nil,
      "player 2 down at the airfield too: held at 25 s, invulnerable (logged)")
p2(FLYING); room(true)
ticks(135.25, 140)
check(cd() == 30 and invs() == "true,false" and line(DOWN .. "1 other player flying) at 25 s", from) ~= nil and line(HIT, from) ~= nil,
      "player 2 takes off, you still down: runs again, can be hit again (logged)")
p2(P2_DOWN); room(true)
ticks(140.25, 145)
check(cd() == 30 and invs() == "true,false,true", "player 2 down again: held, invulnerable")
grounded = false
ticks(145.25, 150)
check(cd() == 35 and nT() == 35 and invs() == "true,false,true,false" and line(RUNS .. "30 s", from) ~= nil
      and since(from, "^" .. HIT) == 2, "... you take off: it runs, the shuttle can be hit again (logged)")
for _, st in ipairs({ { P2_DEAD, 100, "shot down" }, { P2_OUT, 100, "out of the mission" }, { FLYING, 5000, "not heard from" } }) do
    shuttleScene(true); p2(st[1], st[2]); room(true)
    grounded = true
    ticks(100, 105)
    check(cd() == 0 and invs() == "true", "player 2 " .. st[3] .. ", you down: held, invulnerable")
end
-- co-op, you down all the countdown with player 2 flying: it lifts off and the clock ends, never invulnerable
shuttleScene(true)
grounded = true
from = #logs + 1
ticks(100, 100 + SH.countdown_s + 31)
check(D.special.state == "done" and not D.special.lost and has(line("special: round 5, the shuttle lifted off", from), "countdown over")
      and D.shuttleClock == nil and nT() == SH.countdown_s + 30 and invs() == "",
      "... down all " .. (SH.countdown_s + 30) .. " s with player 2 flying: lifted off, every second's event, the clock ended, never invulnerable")
-- lost while held (solo, you down): the invulnerability off as the clock ends
shuttleScene(false)
grounded = true
from = #logs + 1
ticks(100, 105)
FLAGS.SV_ShuttleLost = 1
ticks(105.25, 106)
check(D.special.lost and D.shuttleClock == nil and invs() == "true,false" and line(HIT, from) ~= nil,
      "solo, lost while held: the clock ends, the shuttle can be hit again")
-- lost while running with you down (co-op): the clock ends, nothing to undo
shuttleScene(true)
grounded = true
ticks(100, 105)
FLAGS.SV_ShuttleLost = 1
ticks(105.25, 106)
check(D.special.lost and D.shuttleClock == nil and invs() == "", "co-op, lost while running with you down: the clock ends, never invulnerable")
-- its events not fired while it runs with you down (your landing menu may be up): the first logged, once a clock;
-- flying, not logged (as ever)
local NOTF = "special: shuttle countdown event RE_SV_ShuttleT_"
shuttleScene(true)
grounded = true
from = #logs + 1
eventR = -6
ticks(100, 110)
check(cd() == 10 and nT() == 10 and since(from, "^" .. NOTF) == 1
      and line(NOTF .. "1 not fired (the level is still loading) while you're down at the airfield", from) ~= nil,
      "co-op, running with you down, its events not fired: the first logged once (" .. tostring(line(NOTF, from)) .. ")")
shuttleScene(true)
from = #logs + 1
ticks(100, 110)
eventR = 1
check(cd() == 10 and since(from, "^" .. NOTF) == 0, "... flying, its events not fired: not logged")
-- a joiner runs no countdown of its own (the host's RE_SV_ShuttleT_* come forwarded) and never makes it invulnerable
shuttleScene(false)
COOP.open, COOP.role, COOP.slot, CFG.coop.enabled = true, "join", 1, true
clock = clock + 0.25
COOP.tick(0)
grounded = true
local k = D.shuttleClock
roundsTick(100); roundsTick(110)
check(k.cd == 0 and nT() == 0 and invs() == "", "a joiner, down at the airfield: no countdown or invulnerability of its own")
room(false)

---------------------------------------------------------------------------------------------------- the hooks
print("the hooks, by their place in the source")
do
    local sr = readAll(MOD .. "/Scripts/sv_rounds.lua")
    check(has(sr, "local flying = playerOnAirfield() and othersFlying()") and has(sr, "if flying == 0 then")
          and has(sr, "if playerOnAirfield() and othersFlying() == 0 then D.waveAt"),
          "sv_rounds: the spawns and the wave clock ask othersFlying")
    check(has(sr, "local flying = down and othersFlying() or 0") and has(sr, "elseif not t or (down and flying == 0) then"),
          "sv_rounds: ordersTick's grounded wait asks othersFlying")
    local al = readAll(MOD .. "/Scripts/sv_alicorn.lua")
    check(has(al, "local flying = playerOnAirfield() and othersFlying()") and has(al, "if flying == 0 then return hold(1) end"),
          "sv_alicorn: the deck's airfield hold asks othersFlying")
    local sp = readAll(MOD .. "/Scripts/sv_spawn.lua")
    check(has(sp, "if not down then w.waited = (w.waited or 0) + (now - (w.waitAt or w.at)) end"),
          "sv_spawn: the Wolf trap's wait for its orders counts your flying only")
    check(has(sp, "local flying = down and othersFlying() or 0") and has(sp, "and not (down and flying == 0) then"),
          "sv_spawn: the Wolf trap's hold asks othersFlying")
end

print(fails == 0 and "co-op landing test: all passed" or ("co-op landing test: " .. fails .. " FAILED"))
logFile:close()
os.exit(fails == 0 and 0 or 1)
