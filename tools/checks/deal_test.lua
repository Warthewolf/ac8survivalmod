-- deal_test.lua <mod dir> (run by tools/checks/deal_test.sh): THE DEAL (Scripts/sv_deal.lua) on its own, the game, the
-- subtitles, the HUD and co-op stubbed (the design of 2026-11-23: an offer between rounds). Covered:
--   solo: an offer only in a break, by the dice (logged when they say no), once a break, offer_after_s in, never in the
--     STORE; the Hornet up ahead of you (higher on the ground), its name, an ally's unit, its event zoom; War's
--     introduction, the vote and its question for the deal offered; the break held for it; YES: the target (Podarge,
--     C-130s, the fleet's ships) up targets_after_s into the next round, onto its route, paid per target down and the
--     bonus for all; one left at the round's end taken off unpaid; NO: War's anger (20 %: 5 drones next round) or not;
--     nobody answering: 7 drones in each of the next 2 rounds; the Hornet turning away, taken off leave_s after;
--   co-op host: "dl" reliable as it opens, unreliable every resend_s; hostile "vt"s ignored; a tie is NO; "dr" sent;
--     allow_change; co-op joiner: the host's "dl" / "dr", "vt" sent, hostile ones ignored, never an offer;
--   Ctrl+H: offered now (host), refused on a joiner and with a deal on.
local MOD = arg[1]
local fails = 0
local function check(ok, what) if ok then print("  ok   " .. what) else print("  FAIL " .. what); fails = fails + 1 end end
local function has(s, part) return s ~= nil and tostring(s):find(part, 1, true) ~= nil end

-- the world
local logs, callouts, said, spawns, recycles, sent, credits, own = {}, {}, {}, {}, {}, {}, {}, {}
function log(s) logs[#logs + 1] = s end
local function logged(part) for _, l in ipairs(logs) do if has(l, part) then return true end end return false end
local function clearLogs() logs = {} end
function hudCallout(t, s) callouts[#callouts + 1] = { t, s } end
local isUsed = {}
SUB = {
    say = function(who, text)
        local key = who .. "|" .. text
        if isUsed[key] then return false end
        isUsed[key] = true
        said[#said + 1] = key
        return true
    end,
    fresh = function(x) for _, l in ipairs(x) do if isUsed[l] then return false end end return true end,
    left = function() return 6 end,
}
CFG = { specials = {}, hud = { subs = { colors = {} } } }
CFG_DEFAULTS = { specials = {}, hud = { subs = { colors = {} } } }
function deepCopy(v)
    if type(v) ~= "table" then return v end
    local t = {}
    for k, x in pairs(v) do t[k] = deepCopy(x) end
    return t
end
TEST_TICKS, TEST_KEYS = {}, {}
local testKeys = {}
function testKey(name, who, fn) testKeys[name] = fn; return true end
Key = { A = 65, X = 88, H = 72 }
ModifierKey = { CONTROL = 1 }
local binds = {}
function RegisterKeyBind(key, mods, fn) binds[key] = fn end
function ExecuteInGameThread(f) f() end
local PAUSED = false
function gamePaused() return PAUSED end
function valid(o) return o ~= nil end
local pawn = {
    K2_GetActorLocation = function() return { X = 100000, Y = 200000, Z = 300000 } end,
    K2_GetActorRotation = function() return { Yaw = 0 } end,
    GetVelocity = function() return { X = 0, Y = 0, Z = 0 } end,
}
survivalPC = { Pawn = pawn }
local HORNET_OK = true
local ALIVE = {}
-- the game's objects: NotifyOnNewObject's callback gets each one a spawn makes (a plane each C-130 and its 2 parts; the
-- Podarge's body and 3 parts; a ship's hull and a turret), each with its address, name and health
local newObj
function NotifyOnNewObject(cls, fn) newObj = fn end
local OBJS = {}
local nextAddr = 1000
local function mkObj(name, plane)
    nextAddr = nextAddr + 1
    local o = { name = name, addr = nextAddr, plane = plane, HealthInternal = 100 }
    function o:IsA() return self.plane end
    OBJS[#OBJS + 1] = o
    if newObj then newObj(o) end
    return o
end
function liveAddr(o) return (o and not o.gone) and o.addr or nil end
function nameOf(o) return o and o.name or "?" end
StaticFindObject = function() return {} end
local MADE = {}
function SV_Spawn(unit, x, y, z, yaw)
    spawns[#spawns + 1] = { unit, x, y, z, yaw }
    if unit == "SV_Unit_DealHornet" then return HORNET_OK and 1 or -2 end
    local l = {}
    if unit == "SV_Unit_DealCargo" then
        for k = 1, 3 do l[#l + 1] = mkObj("BP_OP0054_c130_CP_C_" .. k, true); mkObj("c130_part_a" .. k); mkObj("c130_part_b" .. k) end
    elseif unit == "SV_Unit_DealPodarge" then
        l[1] = mkObj("BP_OP0044_norn_MS12_01_CP_C_1", true); mkObj("norn_Turret_L1"); mkObj("norn_Wing_L1"); mkObj("norn_VLS_L1")
    else
        l[1] = mkObj("BP_VE_hull_" .. unit); mkObj("BP_Mk15_turret_" .. unit)
    end
    MADE[unit] = l
    ALIVE[unit] = #l
    return unit == "SV_Unit_DealCargo" and 9 or (unit == "SV_Unit_DealPodarge" and 4 or 2)
end
function SV_UnitAlive(unit) return ALIVE[unit] or -7 end
local events = {}
function SV_Event(ev) events[#events + 1] = ev; return 1 end
local function fired(ev) for _, e in ipairs(events) do if e == ev then return true end end return false end
local function spawned(u) for _, x in ipairs(spawns) do if x[1] == u then return true end end return false end
SPORT = { GROUPS = { "A", "B", "C", "D" } }
function SPORT.fleet()
    local out = { { kind = "ford", unit = "SV_Unit_SpFord", group = "Ford" } }
    for _, g in ipairs(SPORT.GROUPS) do out[#out + 1] = { kind = "wasp", unit = "SV_Unit_SpWasp" .. g, group = g } end
    return out
end
local angers = {}
DECOY = { angerStart = function(n, why) angers[#angers + 1] = { n, why }; return true end }
function specialPay(n) return n end
local texts = {}
function SV_SetText(k, v) texts[k] = v; return 1 end
function SV_Recycle(u, n) recycles[#recycles + 1] = u; return 1 end
SV_ERR = { [-2] = "no such unit or aircraft" }
ALLY = { unit = {}, fleetReady = true }
local STORE_SHUT = true
SPC = { storeShut = function() return STORE_SHUT end }
local raw = function(n, why) credits[#credits + 1] = { n, why } end
addCredits = raw
local ROLL = 0.1
math.random = function(n) if n then return 1 end return ROLL end        -- luacheck: ignore

-- co-op: off (solo) until a case turns it on
COOP = { open = false, role = nil, slot = nil, peers = 1 }
function COOP.host() return COOP.open and COOP.role == "host" end
function COOP.client() return COOP.open and COOP.role == "join" end
function COOP.msg(to, ...) sent[#sent + 1] = { to = to, reliable = true, f = { ... } } ; return true end
function sendTo(to, reliable, ...) sent[#sent + 1] = { to = to, reliable = reliable, f = { ... } }; return true end
function COOP.slotOk(s) return type(s) == "number" and s == math.floor(s) and s >= 0 and s <= 23 end
function COOP.players() local l = {}; for i = 1, COOP.peers do l[i] = { slot = i - 1 } end return l end
function COOP.payOwn(n, why) own[#own + 1] = { n, why } end
function COOP.localCallout(t, s) callouts[#callouts + 1] = { t, s, here = true } end

dofile(MOD .. "/Scripts/sv_deal.lua")
local C = CFG.specials.deal
check(type(DEAL) == "table" and type(C) == "table", "the part loads: DEAL and CFG.specials.deal")
check(CFG_DEFAULTS.specials.deal ~= nil and CFG_DEFAULTS.specials.deal ~= C and CFG_DEFAULTS.specials.deal.vote_s == 30,
    "its settings in CFG_DEFAULTS too (not an edit), a copy; vote_s 30 (the user)")
check(CFG.hud.subs.colors.WAR and CFG.hud.subs.colors.HAYTHORN and CFG_DEFAULTS.hud.subs.colors.WAR,
    "WAR's and HAYTHORN's colours on the subtitle strip (and in the defaults)")
check(binds[65] and binds[88] and TEST_KEYS[65] and TEST_KEYS[88], "Ctrl+A / Ctrl+X bound (and known to TEST_KEYS)")
check(testKeys.H ~= nil, "Ctrl+H, the test key")
check(#TEST_TICKS == 1 and TEST_TICKS[1].name == "deal", "its tick among the test ticks")

local clock = 1000
local function run(secs, step)
    step = step or 0.25
    local n = math.floor(secs / step + 0.5)
    for _ = 1, n do clock = clock + step; TEST_TICKS[1].fn(clock) end
end
local function reset()
    D = nil
    run(0.25)
    logs, callouts, said, spawns, recycles, sent, credits, own = {}, {}, {}, {}, {}, {}, {}, {}
    isUsed, events, angers, ALIVE, MADE = {}, {}, {}, {}, {}
end
-- a break after `round` (D.at: the next round's start, `gap` s on)
local function newBreak(round, gap)
    D = { round = round or 5, state = "wait", now = clock, at = clock + (gap or 20) }
end
local function nextRound() D.round, D.state, D.special = D.round + 1, "fighting", nil end
local function keepNow() if D then D.now = clock end end
local function runD(secs) local n = math.floor(secs / 0.25 + 0.5); for _ = 1, n do run(0.25); keepNow() end end
local function lastCallout() return callouts[#callouts] and callouts[#callouts][1] end

print("solo")
reset(); D = { round = 5, state = "fighting", now = clock }
runD(C.offer_after_s + 5)
check(DEAL.V == nil and #spawns == 0, "in a round: no offer")
reset(); ROLL = 0.9; newBreak(5)
runD(C.offer_after_s + 1)
check(DEAL.V == nil and logged("no offer (rolled 0.90, chance 0.35)"), "the dice say no: no offer, logged")
runD(5)
check(#spawns == 0, "rolled once a break only")
reset(); ROLL = 0.1; STORE_SHUT = false; newBreak(6)
runD(C.offer_after_s - 1)
check(DEAL.V == nil, "not before offer_after_s")
runD(5)
check(DEAL.V == nil, "not while the STORE's open")
STORE_SHUT = true
runD(0.5)
local V = DEAL.V
check(V and V.phase == "intro" and V.kind == "podarge" and V.round == 7 and logged("offered in the break after round 6 (podarge"),
    "offered once the STORE's shut: the Podarge (the weights), its target in round 7")
check(#spawns == 1 and spawns[1][1] == "SV_Unit_DealHornet" and math.abs(spawns[1][2] - 250000) < 1 and
    math.abs(spawns[1][3] - 270000) < 1 and spawns[1][4] == 370000, "the Hornet up 1.5 km ahead, 0.7 km right, 700 m up (on the ground)")
check(texts.SV_DealHornet == "WAR & HAYTHORN" and ALLY.unit.SV_Unit_DealHornet == "air", "its name WAR & HAYTHORN, an ally's unit")
runD(1.25)
check(fired("RE_SV_DealCam") and logged("the event zoom onto the Hornet"), "the event zoom onto it")
check(#said == 2 and has(said[1] .. said[2], "WAR|"), "War's introduction said (an exchange of two)")
check(D.at >= clock + C.vote_s and logged("the break held for the deal"), "the break held for the vote")
runD(6)
check(V.phase == "open" and has(said[3], "Podarge"), "the vote opens, War asks about the Podarge")
check(callouts[1] and callouts[1][1] == "THE DEAL", "its callout")
local row = DEAL.row()
check(has(row, "CTRL+A YES / CTRL+X NO") and has(row, "YES 0  NO 0"), "the NEXT row: " .. tostring(row))
binds[65]()
runD(0.25)
check(V.phase == "closed" and V.taken and logged("YES 1, NO 0: TAKEN (the most votes)"), "Ctrl+A: YES, one player: TAKEN")
check(DEAL.T and DEAL.T.kind == "podarge" and DEAL.T.round == 7 and DEAL.T.state == "due", "the Podarge due in round 7")
check(#sent == 0, "solo: nothing sent")
runD(C.leave_after_s + 0.5)
check(fired("RE_SV_DealLeave") and logged("the Hornet turns away"), "the Hornet turns away")
runD(C.hornet.leave_s)
check(#recycles == 1 and recycles[1] == "SV_Unit_DealHornet", "the Hornet taken off leave_s after")
nextRound(); runD(C.targets_after_s - 2)
check(not spawned("SV_Unit_DealPodarge"), "not before targets_after_s into round 7")
runD(3)
check(spawned("SV_Unit_DealPodarge") and DEAL.T.state == "up" and lastCallout() == "PODARGE INBOUND", "the Podarge up, its callout")
runD(1.5)
check(fired("RE_SV_DealPodargeGo"), "onto its route")
check(has(DEAL.row(), "PODARGE 0 / 1 DOWN"), "the row: " .. tostring(DEAL.row()))
check(DEAL.T.total == 1 and logged("SV_Unit_DealPodarge 4 objects, 1 body"), "one target: the Podarge's body (its parts not counted)")
credits = {}
MADE.SV_Unit_DealPodarge[1].HealthInternal = 0
runD(3)
check(credits[1] and credits[1][1] == 6000 + 300 * 7 and credits[2] and credits[2][1] == 3000 + 150 * 7,
    "paid: 6000 + 300 x 7 for the Podarge, the bonus 3000 + 150 x 7")
check(DEAL.T == nil or DEAL.T.state == "done", "the deal's over")
check(logged("podarge over (all down): 1 of 1 down") and lastCallout() == "THE DEAL PAID", "logged, THE DEAL PAID")

-- the C-130s, one escaping at the round's end
reset(); ROLL = 0.1; C.deals = { podarge = 0, fleet = 0, cargo = 1 }; newBreak(8)
runD(C.offer_after_s + 7)
check(DEAL.V and DEAL.V.kind == "cargo", "the C-130s offered")
binds[65](); runD(0.25)
nextRound(); runD(C.targets_after_s + 2)
check(spawned("SV_Unit_DealCargo") and DEAL.T.total == 3, "three C-130s up (3 bodies of 9 objects)")
credits = {}
MADE.SV_Unit_DealCargo[1].HealthInternal = 0
MADE.SV_Unit_DealCargo[2].gone = true
runD(3)
check(credits[1] and credits[1][1] == 2000 + 100 * 9 and credits[2] and credits[2][1] == 2000 + 100 * 9 and DEAL.T.down == 2,
    "two down (one at 0 health, one gone): each paid 2000 + 100 x 9")
D.state = "wait"; runD(0.5)
check(logged("cargo over (the round's over): 2 of 3 down, 1 left") and recycles[#recycles] == "SV_Unit_DealCargo" and
    lastCallout() == "THE DEAL: TARGET ESCAPED", "the round's over: the last one taken off unpaid, TARGET ESCAPED")

-- the fleet: the first two groups' ships
reset(); C.deals = { podarge = 0, fleet = 1, cargo = 0 }; newBreak(10)
runD(C.offer_after_s + 7); binds[65](); runD(0.25)
nextRound(); runD(C.targets_after_s + 2)
check(spawned("SV_Unit_SpWaspA") and spawned("SV_Unit_SpWaspB") and not spawned("SV_Unit_SpWaspC") and not spawned("SV_Unit_SpFord"),
    "the fleet: groups A and B's ships, not the Ford")
check(DEAL.T.total == 2, "a body each: its hull, not its turret (" .. tostring(DEAL.T.total) .. ")")
MADE.SV_Unit_SpWaspA[1].HealthInternal = 0
credits = {}
runD(3)
check(DEAL.T.down == 1 and credits[1] and credits[1][1] == 1200 + 60 * 11, "a hull down: that ship paid, its turret still up or not")
reset(); ALLY.fleetReady = false; newBreak(12)
runD(C.offer_after_s + 2)
check(DEAL.V == nil and logged("no deal to offer"), "no fleet rows: the fleet never offered")
ALLY.fleetReady = true
C.deals = { podarge = 1, fleet = 1, cargo = 1 }

-- NO: War's anger by the dice; nobody answering: 7 drones in the next 2 rounds
reset(); ROLL = 0.1; newBreak(14)
runD(C.offer_after_s + 7)
binds[88](); runD(0.25)
check(DEAL.V.phase == "closed" and not DEAL.V.taken and logged("War's anger (refused, rolled 0.10): 5 Marker Drones in round 15"),
    "Ctrl+X: NO, rolled 0.10 < 0.20: 5 drones next round")
nextRound(); runD(C.anger.after_s + 1)
check(angers[1] and angers[1][1] == 5 and lastCallout() == "WAR IS ANGRY", "round 15: 5 drones, WAR IS ANGRY")
reset(); ROLL = 0.5; newBreak(16)
runD(C.offer_after_s + 7)
check(DEAL.V == nil, "rolled 0.50 for the offer: none (0.35)")
ROLL = 0.1; testKeys.H(); runD(7); ROLL = 0.5; binds[88](); runD(0.25)
check(logged("War lets it go") and #DEAL.ANG == 0, "NO, rolled 0.50: War lets it go")
reset(); ROLL = 0.1; newBreak(18)
runD(C.offer_after_s + 7)
runD(C.vote_s + 0.5)
check(DEAL.V.phase == "closed" and logged("nobody answered") and logged("7 Marker Drones in rounds 19 to 20"), "nobody answers: 7 drones in rounds 19 and 20")
nextRound(); runD(C.anger.after_s + 1)
D.state = "wait"; runD(1); nextRound(); runD(C.anger.after_s + 1)
check(#angers == 2 and angers[1][1] == 7 and angers[2][1] == 7, "7 drones in each")

-- no Hornet in this build
reset(); HORNET_OK = false; newBreak(22)
runD(C.offer_after_s + 1)
check(DEAL.V and logged("the deal goes on without the plane"), "no Hornet unit: goes on, logged")
HORNET_OK = true
-- a new run with a vote open: dropped
reset(); newBreak(24)
runD(C.offer_after_s + 7)
clearLogs(); newBreak(1)
runD(0.25)
check(DEAL.V == nil and logged("the last run's deal dropped") and #recycles == 1, "a new run: the last run's vote dropped, its Hornet off")

print("co-op host")
reset(); COOP.open, COOP.role, COOP.slot, COOP.peers = true, "host", 0, 2
newBreak(12)
runD(C.offer_after_s + 7)
V = DEAL.V
local function sentOf(k, rel) local n = 0; for _, m in ipairs(sent) do if m.f[1] == k and (rel == nil or m.reliable == rel) then n = n + 1 end end return n end
check(V.phase == "open" and sentOf("dl", true) == 1 and sent[1].to == nil and sent[1].f[2] == V.id and sent[1].f[3] == V.kind,
    "\"dl\" to everyone, reliable, as it opens")
runD(C.resend_s + 0.25)
check(sentOf("dl", false) >= 1, "\"dl\" again unreliable every resend_s")
local id = tostring(V.id)
for _, bad in ipairs({ { 1, { "vt", "999", "1" } }, { 1, { "vt", id, "2" } }, { 1, { "vt", id, "nan" } }, { 1, { "vt", id, "0.5" } },
                       { 1, { "vt", id } }, { 1, { "vt" } }, { 30, { "vt", id, "1" } }, { -1, { "vt", id, "1" } },
                       { 0, { "vt", id, "1" } }, { 1.5, { "vt", id, "1" } }, { "x", { "vt", id, "1" } } }) do
    DEAL.onVote(bad[1], bad[2])
end
check(next(V.votes) == nil, "hostile \"vt\"s ignored")
binds[65]()
check(V.votes[0] == 1 and V.phase == "open", "the host's YES: still open (2 players)")
DEAL.onVote(1, { "vt", id, "1" })
DEAL.onVote(1, { "vt", id, "0" })
check(V.votes[1] == 0, "allow_change: the joiner's last answer counts")
runD(0.25)
check(V.phase == "closed" and not V.taken and logged("YES 1, NO 1: REFUSED (a tie is no)"), "everyone answered: a tie is NO")
local dr
for _, m in ipairs(sent) do if m.f[1] == "dr" then dr = m end end
check(dr and dr.reliable and dr.f[2] == V.id and dr.f[3] == 1 and dr.f[4] == 1 and dr.f[5] == 0, "\"dr\" sent: 1, 1, not taken")
reset(); C.allow_change = false; newBreak(13)
runD(C.offer_after_s + 7)
V = DEAL.V
DEAL.onVote(2, { "vt", tostring(V.id), "1" }); DEAL.onVote(2, { "vt", tostring(V.id), "0" })
check(V.votes[2] == 1, "allow_change off: the first answer counts")
C.allow_change = true
reset(); D = { round = 14, state = "fighting", now = clock }
testKeys.H()
check(DEAL.V and DEAL.V.phase == "intro" and logged("Ctrl+H"), "Ctrl+H: offered now, in a round too")
clearLogs(); testKeys.H()
check(logged("a deal is on already"), "Ctrl+H again with a deal on: refused")

print("co-op joiner")
reset(); COOP.role, COOP.slot = "join", 1
newBreak(15)
runD(C.offer_after_s + 7)
check(DEAL.V == nil and #spawns == 0, "a joiner never offers")
for _, bad in ipairs({ { "dl" }, { "dl", "0", "cargo", "30", "0", "0" }, { "dl", "1.5", "cargo", "30", "0", "0" },
                       { "dl", "1", "car go!", "30", "0", "0" }, { "dl", "1", "cargo", "inf", "0", "0" },
                       { "dl", "1", "cargo", "500", "0", "0" }, { "dl", "1", "cargo", "30", "25", "0" },
                       { "dl", "1", "cargo", "30", "-1", "0" }, { "dl", "1", string.rep("a", 400), "30", "0", "0" } }) do
    DEAL.fromHost("dl", bad)
end
check(DEAL.J == nil, "hostile \"dl\"s ignored")
DEAL.fromHost("dl", { "dl", "4", "cargo", "30", "1", "0" })
row = DEAL.row()
check(DEAL.J and has(row, "YES 1  NO 0") and has(row, "0:30"), "the host's \"dl\": the row " .. tostring(row))
binds[88]()
check(sent[#sent].to == 0 and sent[#sent].f[1] == "vt" and sent[#sent].f[2] == 4 and sent[#sent].f[3] == 0, "Ctrl+X: \"vt\" to the host")
check(has(DEAL.row(), "YOU: NO"), "your vote on the row")
for _, bad in ipairs({ { "dr", "4", "1", "0", "2" }, { "dr", "4", "x", "0", "1" }, { "dr", "4", "1", "99", "1" }, { "dr", "x", "1", "0", "1" } }) do
    DEAL.fromHost("dr", bad)
end
check(DEAL.J.phase == "open", "hostile \"dr\"s ignored")
DEAL.fromHost("dr", { "dr", "4", "2", "1", "1" })
check(DEAL.J.phase == "closed" and DEAL.J.taken and has(DEAL.row(), "TAKEN (YES 2 / NO 1)"), "\"dr\": taken, on the row")
reset(); newBreak(16); runD(0.25)
DEAL.fromHost("dl", { "dl", "5", "cargo", "30", "0", "0" })
runD(41)
check(DEAL.J == nil and logged("no result from the host"), "a vote with no result 10 s after its close: dropped")
clearLogs(); testKeys.H()
check(logged("on a joiner"), "Ctrl+H on a joiner: refused")

print(fails == 0 and "deal test: all passed" or ("deal test: " .. fails .. " FAILED"))
os.exit(fails == 0 and 0 or 1)
